import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Downloads and caches the SCRFD-2.5G-KPS TFLite model on first use.
///
/// Mirrors [YoloModelDownloader]/[FaceModelDownloader]: fetched once from
/// [modelUrl], stored in the app documents directory, served from cache on
/// every subsequent call.
class ScrfdModelDownloader {
  static const String _modelFileName = 'ffl_scrfd_2.5g_face.tflite';

  /// Minimum valid file size — guards against incomplete downloads.
  static const int _minValidBytes = 512 * 1024; // 512 KB

  /// Default bundled SCRFD-2.5G-KPS model.
  ///
  /// Converted from the verified official InsightFace ONNX export
  /// (`scrfd_2.5g_bnkps.onnx`, hosted at the `.onnx` sibling asset in this
  /// same release) via `onnx2tf` — see CHANGELOG for the conversion steps.
  static const String bundledModelUrl =
      'https://github.com/sanjaysharmajw/flutter_face_liveness/releases/download/v3.2.0-models/scrfd_2.5g_bnkps_float32.tflite';

  /// Remote URL to download the model from.
  final String modelUrl;

  /// Optional fallback URL tried if [modelUrl] returns a bad response.
  final String? fallbackUrl;

  /// Called with 0.0–1.0 during download; not called when served from cache.
  final void Function(double progress)? onProgress;

  ScrfdModelDownloader({
    String? modelUrl,
    this.fallbackUrl,
    this.onProgress,
  }) : modelUrl = modelUrl ?? bundledModelUrl;

  /// Returns the absolute filesystem path to the cached model, downloading it
  /// first if it is missing or corrupted.
  ///
  /// Throws [ScrfdModelDownloadException] when both primary and fallback fail.
  Future<String> ensureModel() async {
    final dir  = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$_modelFileName';
    final file = File(path);

    if (await _isValid(file)) {
      debugPrint('[ScrfdModelDownloader] Using cached model at $path');
      return path;
    }

    debugPrint('[ScrfdModelDownloader] Downloading SCRFD-2.5G-KPS model…');
    await _download(modelUrl, file);

    if (!await _isValid(file) && fallbackUrl != null) {
      debugPrint('[ScrfdModelDownloader] Primary download incomplete, trying fallback…');
      await _download(fallbackUrl!, file);
    }

    if (!await _isValid(file)) {
      throw ScrfdModelDownloadException(
        'Failed to download the SCRFD-2.5G-KPS model.\n'
        'Primary URL: $modelUrl\n'
        'Check your internet connection, or that the release asset exists.',
      );
    }

    debugPrint('[ScrfdModelDownloader] Model ready: $path');
    return path;
  }

  Future<bool> _isValid(File file) async {
    if (!await file.exists()) return false;
    return await file.length() >= _minValidBytes;
  }

  Future<void> _download(String url, File dest) async {
    try {
      final request  = http.Request('GET', Uri.parse(url));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        debugPrint('[ScrfdModelDownloader] HTTP ${response.statusCode} from $url');
        return;
      }

      final total    = response.contentLength ?? 0;
      int   received = 0;
      final sink     = dest.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.flush();
      await sink.close();
      onProgress?.call(1.0);
    } catch (e) {
      debugPrint('[ScrfdModelDownloader] Download error from $url: $e');
      if (await dest.exists()) await dest.delete();
    }
  }

  /// Delete the cached model to force a fresh download next time.
  static Future<void> clearCache() async {
    final dir  = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_modelFileName');
    if (await file.exists()) await file.delete();
    debugPrint('[ScrfdModelDownloader] Cache cleared');
  }
}

class ScrfdModelDownloadException implements Exception {
  const ScrfdModelDownloadException(this.message);
  final String message;

  @override
  String toString() => 'ScrfdModelDownloadException: $message';
}
