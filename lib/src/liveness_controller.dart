import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'models/face_data.dart';
import 'models/liveness_action.dart';
import 'models/liveness_result.dart';
import 'models/detection_status.dart';
import 'camera/camera_service.dart';
import 'ml/face_detector_service.dart';
import 'liveness/liveness_engine.dart';

/// ChangeNotifier that drives the entire liveness session.
///
/// Exposes all state needed by the widget tree and handles the full lifecycle:
/// camera init → frame processing → liveness evaluation → completion.
class LivenessController extends ChangeNotifier {
  LivenessController({
    required List<LivenessAction> actions,
    required this.onSuccess,
    required this.onFailed,
    this.sessionTimeoutMs = 60000,
    ResolutionPreset cameraResolution = ResolutionPreset.high,
  })  : _actions = actions,
        _cameraResolution = cameraResolution;

  final List<LivenessAction> _actions;
  final void Function(LivenessResult result) onSuccess;
  final void Function(String reason) onFailed;
  final int sessionTimeoutMs;
  final ResolutionPreset _cameraResolution;

  final CameraService _cameraService = CameraService();
  final FaceDetectorService _faceDetector = FaceDetectorService();
  late final LivenessEngine _engine;

  bool _isInitialized = false;
  bool _isDisposed = false;
  FaceData? _currentFace;
  String? _error;

  bool get isInitialized => _isInitialized;
  FaceData? get currentFace => _currentFace;
  String? get error => _error;
  CameraController? get cameraController => _cameraService.controller;
  DetectionStatus get status => _isInitialized ? _engine.status : DetectionStatus.initializing;
  LivenessAction? get currentAction => _isInitialized ? _engine.currentAction : null;
  double get progress => _isInitialized ? _engine.progress : 0.0;
  int get completedCount => _isInitialized ? _engine.completedActions.length : 0;
  int get totalActions => _actions.length;
  bool get isComplete => _isInitialized && _engine.isComplete;

  Future<void> initialize() async {
    try {
      _engine = LivenessEngine(
        requiredActions: _actions,
        sessionTimeoutMs: sessionTimeoutMs,
        onActionCompleted: (_) => notifyListeners(),
        onStatusChanged: (_) => notifyListeners(),
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
        resolution: _cameraResolution,
        onFrame: (image) => _processFrame(image, camera),  // returns Future<void>
      );

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      _error = 'Camera initialization failed: $e';
      notifyListeners();
    }
  }

  Future<void> _processFrame(CameraImage image, CameraDescription camera) async {
    if (_isDisposed || !_isInitialized) return;

    final faces = await _faceDetector.processCameraImage(
      image,
      camera.sensorOrientation,
      camera.lensDirection,
    );

    if (_isDisposed) return;

    _currentFace = faces.isNotEmpty ? faces.first : null;
    _engine.processFrame(faces);

    // notifyListeners is called by engine callbacks; also update face position
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

  Future<void> reset() async {
    _engine.reset();
    _currentFace = null;
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    await _cameraService.dispose();
    await _faceDetector.dispose();
    _engine.dispose();
    super.dispose();
  }
}
