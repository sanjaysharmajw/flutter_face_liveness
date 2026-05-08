import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'face_embedding_model.dart';
import 'face_preprocessor.dart';

/// Provides stable, persistent Face IDs across sessions.
///
/// Each unique face is assigned one ID (e.g. `FID-3A9F2B1C4E8D…`).
/// The same physical person always receives the same ID even after the app
/// restarts, because embeddings are persisted in [SharedPreferences].
///
/// Enable with [LivenessConfig.enableFaceId].
class FaceIdentityService {
  FaceIdentityService({this.similarityThreshold = 0.65});

  /// Cosine-similarity cutoff for matching the same face.
  /// 0.65 balances recall (same person in different conditions) vs
  /// precision (reject different people). Raise toward 0.80 for stricter
  /// matching, lower toward 0.50 to be more lenient.
  final double similarityThreshold;

  final FaceEmbeddingModel _model = FaceEmbeddingModel();

  // Each face stores up to [_maxEmbeddingsPerFace] embeddings (running mean).
  // The stored value is the L2-normalised average, so matching stays O(1).
  final Map<String, List<double>> _knownFaces = {};

  // How aggressively the stored embedding adapts toward new observations.
  // 0.25 = new sample has 25% weight; proven stable for gradual lighting drift.
  static const double _embeddingUpdateRate = 0.25;

  static const _kPrefsKey = 'ffl_known_faces_v1';

  bool get isReady => _model.isLoaded;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// [onModelDownloadProgress] fires 0.0–1.0 while the model is being
  /// downloaded for the first time (null on subsequent runs from cache).
  Future<void> initialize({
    void Function(double progress)? onModelDownloadProgress,
  }) async {
    await _model.load(onProgress: onModelDownloadProgress);
    await _loadStoredFaces();
  }

  void dispose() => _model.dispose();

  // ── Public API ────────────────────────────────────────────────────────────

  /// Identify the face visible in the last verified frame.
  ///
  /// Returns a stable [faceId] string:
  ///  - Same person → same ID (across all sessions on the same device).
  ///  - Different person → new unique ID.
  ///  - Returns `null` if preprocessing or inference fails.
  Future<String?> identifyFromFrame({
    required Uint8List imageBytes,
    required int imageWidth,
    required int imageHeight,
    required Rect faceBoundingBox,
    required int sensorOrientation,
  }) async {
    if (!isReady) return null;

    final input = await compute(_runPreprocess, _PreprocessInput(
      imageBytes:        imageBytes,
      imageWidth:        imageWidth,
      imageHeight:       imageHeight,
      bbox:              faceBoundingBox,
      sensorOrientation: sensorOrientation,
    ));
    if (input == null) return null;

    final embedding = _model.infer(input);
    if (embedding == null) return null;

    return _matchOrRegister(embedding);
  }

  /// Delete all stored face embeddings (e.g. on logout).
  Future<void> clearAllFaces() async {
    _knownFaces.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefsKey);
    debugPrint('[FaceIdentityService] All face data cleared');
  }

  /// Remove a single face by ID.
  Future<void> removeFace(String faceId) async {
    _knownFaces.remove(faceId);
    await _flushToPrefs();
  }

  /// All registered face IDs on this device.
  List<String> get registeredFaceIds => List.unmodifiable(_knownFaces.keys);

  // ── Matching / registration ───────────────────────────────────────────────

  Future<String> _matchOrRegister(List<double> embedding) async {
    String? bestId;
    double  bestSim = -1.0;

    for (final entry in _knownFaces.entries) {
      final sim = cosineSimilarity(embedding, entry.value);
      if (sim > bestSim) {
        bestSim = sim;
        bestId  = entry.key;
      }
    }

    if (bestId != null && bestSim >= similarityThreshold) {
      debugPrint('[FaceIdentityService] Matched $bestId (sim=${bestSim.toStringAsFixed(3)})');
      // Update stored embedding toward the new observation so the face
      // template gradually adapts to lighting / pose changes.
      _knownFaces[bestId] = _blendEmbeddings(
        _knownFaces[bestId]!,
        embedding,
        _embeddingUpdateRate,
      );
      await _flushToPrefs();
      return bestId;
    }

    // New face — register and persist
    final faceId = _newFaceId();
    _knownFaces[faceId] = embedding;
    await _flushToPrefs();
    debugPrint('[FaceIdentityService] New face registered → $faceId');
    return faceId;
  }

  /// Weighted blend: `(1-rate)*stored + rate*newEmbedding`, then L2-renormalise.
  static List<double> _blendEmbeddings(
    List<double> stored,
    List<double> incoming,
    double rate,
  ) {
    final blended = List<double>.generate(
      stored.length,
      (i) => (1 - rate) * stored[i] + rate * incoming[i],
    );
    // Re-normalise so cosine similarity stays valid
    double norm = 0.0;
    for (final v in blended) norm += v * v;
    norm = math.sqrt(norm);
    if (norm < 1e-10) return stored;
    return blended.map((v) => v / norm).toList();
  }

  // ── Storage ───────────────────────────────────────────────────────────────

  Future<void> _loadStoredFaces() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json  = prefs.getString(_kPrefsKey);
      if (json == null) return;
      final Map<String, dynamic> decoded = jsonDecode(json);
      for (final e in decoded.entries) {
        _knownFaces[e.key] = List<double>.from(e.value as List);
      }
      debugPrint('[FaceIdentityService] Loaded ${_knownFaces.length} known face(s)');
    } catch (e) {
      debugPrint('[FaceIdentityService] Load error: $e');
    }
  }

  Future<void> _flushToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data  = {for (final e in _knownFaces.entries) e.key: e.value};
      await prefs.setString(_kPrefsKey, jsonEncode(data));
    } catch (e) {
      debugPrint('[FaceIdentityService] Persist error: $e');
    }
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  /// Cosine similarity between two L2-normalised vectors.
  /// Equals dot product when both are unit vectors.
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dot = 0.0, magA = 0.0, magB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot  += a[i] * b[i];
      magA += a[i] * a[i];
      magB += b[i] * b[i];
    }
    final denom = math.sqrt(magA) * math.sqrt(magB);
    return denom < 1e-10 ? 0.0 : (dot / denom).clamp(-1.0, 1.0);
  }

  static String _newFaceId() {
    final rand  = math.Random.secure();
    final bytes = List.generate(12, (_) => rand.nextInt(256));
    return 'FID-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
  }
}

// ── Isolate helper ────────────────────────────────────────────────────────────

class _PreprocessInput {
  const _PreprocessInput({
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.bbox,
    required this.sensorOrientation,
  });
  final Uint8List imageBytes;
  final int imageWidth;
  final int imageHeight;
  final Rect bbox;
  final int sensorOrientation;
}

// Top-level function — required for compute()
Float32List? _runPreprocess(_PreprocessInput inp) =>
    FacePreprocessor.prepare(
      imageBytes:        inp.imageBytes,
      imageWidth:        inp.imageWidth,
      imageHeight:       inp.imageHeight,
      bbox:              inp.bbox,
      sensorOrientation: inp.sensorOrientation,
    );
