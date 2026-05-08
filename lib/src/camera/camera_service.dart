import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Manages camera lifecycle, stream access, and frame throttling.
class CameraService {
  CameraController? _controller;
  bool _isProcessingFrame = false;
  int _lastProcessedMs = 0;

  /// Minimum milliseconds between ML processing calls (~20 fps).
  static const int _frameThrottleMs = 50;

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  Future<void> initialize({
    required CameraDescription camera,
    required ResolutionPreset resolution,
    // Async callback — processing is awaited so _isProcessingFrame works correctly
    required Future<void> Function(CameraImage image) onFrame,
  }) async {
    await dispose();

    _controller = CameraController(
      camera,
      resolution,
      enableAudio: false,
      // yuv420 is supported by all Android devices (NV21 is rejected on many MIUI/Pixel devices)
      imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );

    await _controller!.initialize();
    await _controller!.startImageStream((image) => _onCameraImage(image, onFrame));
  }

  void _onCameraImage(
    CameraImage image,
    Future<void> Function(CameraImage) onFrame,
  ) async {
    if (_controller == null || _isProcessingFrame) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastProcessedMs < _frameThrottleMs) return;

    _isProcessingFrame = true;
    _lastProcessedMs = nowMs;

    try {
      // Await the async processing so the flag blocks concurrent calls
      await onFrame(image);
    } catch (e) {
      debugPrint('[CameraService] Frame error: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<List<CameraDescription>> getAvailableCameras() async {
    return await availableCameras();
  }

  Future<CameraDescription?> getFrontCamera() async {
    final cameras = await getAvailableCameras();
    try {
      return cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
    } catch (_) {
      return cameras.isNotEmpty ? cameras.first : null;
    }
  }

  Future<void> dispose() async {
    // Grab and null the controller immediately so _onCameraImage callbacks bail out.
    final ctrl = _controller;
    _controller = null;
    _isProcessingFrame = false;

    if (ctrl == null) return;
    try {
      if (ctrl.value.isStreamingImages) {
        await ctrl.stopImageStream();
      }
      // Let in-flight frame callbacks drain before releasing the surface.
      // 300ms is enough for one full ML Kit processing cycle on slow devices (Xiaomi MIUI).
      await Future.delayed(const Duration(milliseconds: 300));
      await ctrl.dispose();
    } catch (e) {
      debugPrint('[CameraService] Dispose error (ignored): $e');
    }
  }
}
