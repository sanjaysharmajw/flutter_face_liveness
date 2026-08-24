import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Downloads and caches the YOLOv8n-face TFLite model on first use.
///
/// Mirrors [FaceModelDownloader]/[TFLiteModelDownloader]: fetched once from
/// [modelUrl], stored in the app documents directory, served from cache on
/// every subsequent call.
class YoloModelDownloader {
  static const String _modelFileName = 'ffl_yolov8n_face.tflite';

  /// Minimum valid file size — guards against incomplete downloads.
  static const int _minValidBytes = 512 * 1024; // 512 KB

  /// Default bundled YOLOv8n-face model.
  ///
  /// NOTE: this asset does not exist in the GitHub release yet. Export
  /// `yolov8n-face.pt` to `.tflite` (e.g. `yolo export model=yolov8n-face.pt
  /// format=tflite int8=True`) and upload it to this release/tag before
  /// [FaceDetectorBackend.yolov8] can be used — [FaceIdentityService]
  /// surfaces the resulting download failure the same way it does for the
  /// FaceNet/anti-spoof models (isolated, non-fatal to the session).
  static const String bundledModelUrl =
      'https://github.com/sanjaysharmajw/flutter_face_liveness/releases/download/v3.2.0-models/yolov8n-face.tflite';

  /// Remote URL to download the model from.
  final String modelUrl;

  /// Optional fallback URL tried if [modelUrl] returns a bad response.
  final String? fallbackUrl;

  /// Called with 0.0–1.0 during download; not called when served from cache.
  final void Function(double progress)? onProgress;

  YoloModelDownloader({
    String? modelUrl,
    this.fallbackUrl,
    this.onProgress,
  }) : modelUrl = modelUrl ?? bundledModelUrl;

  /// Returns the absolute filesystem path to the cached model, downloading it
  /// first if it is missing or corrupted.
  ///
  /// Throws [YoloModelDownloadException] when both primary and fallback fail.
  Future<String> ensureModel() async {
    final dir  = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$_modelFileName';
    final file = File(path);

    if (await _isValid(file)) {
      debugPrint('[YoloModelDownloader] Using cached model at $path');
      return path;
    }

    debugPrint('[YoloModelDownloader] Downloading YOLOv8n-face model…');
    await _download(modelUrl, file);

    if (!await _isValid(file) && fallbackUrl != null) {
      debugPrint('[YoloModelDownloader] Primary download incomplete, trying fallback…');
      await _download(fallbackUrl!, file);
    }

    if (!await _isValid(file)) {
      throw YoloModelDownloadException(
        'Failed to download the YOLOv8n-face model.\n'
        'Primary URL: $modelUrl\n'
        'Check your internet connection, or that the release asset exists.',
      );
    }

    debugPrint('[YoloModelDownloader] Model ready: $path');
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
        debugPrint('[YoloModelDownloader] HTTP ${response.statusCode} from $url');
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
      debugPrint('[YoloModelDownloader] Download error from $url: $e');
      if (await dest.exists()) await dest.delete();
    }
  }

  /// Delete the cached model to force a fresh download next time.
  static Future<void> clearCache() async {
    final dir  = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_modelFileName');
    if (await file.exists()) await file.delete();
    debugPrint('[YoloModelDownloader] Cache cleared');
  }
}

class YoloModelDownloadException implements Exception {
  const YoloModelDownloadException(this.message);
  final String message;

  @override
  String toString() => 'YoloModelDownloadException: $message';
}
