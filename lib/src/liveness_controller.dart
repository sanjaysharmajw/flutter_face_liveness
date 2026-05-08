import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import 'models/face_data.dart';
import 'models/liveness_action.dart';
import 'models/liveness_config.dart';
import 'models/liveness_result.dart';
import 'models/detection_status.dart';
import 'models/frame_quality.dart';
import 'camera/camera_service.dart';
import 'ml/face_detector_service.dart';
import 'ml/tflite_service.dart';
import 'liveness/liveness_engine.dart';

/// ChangeNotifier that drives the full liveness verification session.
///
/// Lifecycle: [initialize] → frames processed automatically → callbacks fired.
class LivenessController extends ChangeNotifier {
  LivenessController({
    required List<LivenessAction> actions,
    required this.onSuccess,
    required this.onFailed,
    LivenessConfig config = const LivenessConfig(),
  })  : _actions = actions,
        _config  = config;

  final List<LivenessAction> _actions;
  final LivenessConfig _config;
  final void Function(LivenessResult result) onSuccess;
  final void Function(String reason)          onFailed;

  final CameraService _cameraService = CameraService();
  final FaceDetectorService _faceDetector = FaceDetectorService();
  TFLiteService? _tflite;
  late LivenessEngine _engine;

  bool _isInitialized = false;
  bool _isDisposed    = false;
  FaceData?     _currentFace;
  FrameQuality? _lastQuality;
  String?       _error;

  // ── Public getters ──────────────────────────────────────────────────────
  bool            get isInitialized   => _isInitialized;
  FaceData?       get currentFace     => _currentFace;
  FrameQuality?   get lastQuality     => _lastQuality;
  String?         get error           => _error;
  CameraController? get cameraController => _cameraService.controller;

  DetectionStatus get status =>
      _isInitialized ? _engine.status : DetectionStatus.initializing;
  LivenessAction? get currentAction  =>
      _isInitialized ? _engine.currentAction : null;
  double  get progress          => _isInitialized ? _engine.progress             : 0.0;
  int     get completedCount    => _isInitialized ? _engine.completedActions.length : 0;
  int     get totalActions      => _actions.length;
  bool    get isComplete        => _isInitialized && _engine.isComplete;
  String? get sessionId         => _isInitialized ? _engine.sessionId           : null;
  LivenessConfig get config     => _config;
  List<LivenessAction> get completedActions =>
      _isInitialized ? _engine.completedActions : const [];
  List<LivenessAction> get remainingActions =>
      _isInitialized ? _engine.remainingActions : _actions;

  // ── Initialisation ──────────────────────────────────────────────────────

  Future<void> initialize() async {
    try {
      // TFLite (optional)
      if (_config.enableTFLite && _config.tfliteModelPath != null) {
        _tflite = TFLiteService(
          modelPath: _config.tfliteModelPath!,
          inputSize: _config.tfliteInputSize,
        );
        await _tflite!.load();
      }

      _engine = LivenessEngine(
        requiredActions: _actions,
        config: _config,
        onActionCompleted: (_) => notifyListeners(),
        onStatusChanged:   (_) => notifyListeners(),
        onAllActionsCompleted: _onEngineComplete,
      );

      final camera = await _cameraService.getFrontCamera();
      if (camera == null) {
        _error = 'No front camera available';
        notifyListeners();
        return;
      }

      await _cameraService.initialize(
        camera: camera,
        config: _config,
        onFrame: (image) => _processFrame(image, camera),
      );

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      _error = 'Camera initialization failed: $e';
      notifyListeners();
    }
  }

  // ── Per-frame pipeline ──────────────────────────────────────────────────

  Future<void> _processFrame(
    CameraImage image,
    CameraDescription camera,
  ) async {
    if (_isDisposed || !_isInitialized) return;

    final result = await _faceDetector.processCameraImage(
      image,
      camera.sensorOrientation,
      camera.lensDirection,
    );

    if (_isDisposed) return;

    _currentFace = result.faces.isNotEmpty ? result.faces.first : null;
    _lastQuality = result.quality;

    _engine.processFrame(result.faces, quality: result.quality);
    notifyListeners();
  }

  void _onEngineComplete(LivenessResult result) {
    if (result.isSuccess) {
      onSuccess(result);
    } else {
      onFailed(result.failureReason ?? 'Liveness check failed');
    }
    notifyListeners();
  }

  // ── Reset / Dispose ─────────────────────────────────────────────────────

  Future<void> reset() async {
    if (!_isInitialized) return;
    _engine.reset(_actions);
    _currentFace = null;
    _lastQuality = null;
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    await _cameraService.dispose();
    await _faceDetector.dispose();
    _tflite?.dispose();
    _engine.dispose();
    super.dispose();
  }
}

