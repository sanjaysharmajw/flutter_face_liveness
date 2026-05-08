import 'package:flutter/foundation.dart';
import '../models/face_data.dart';
import '../models/liveness_action.dart';
import '../models/liveness_result.dart';
import '../models/detection_status.dart';
import '../ml/human_validator.dart';
import 'blink_detector.dart';
import 'head_movement_detector.dart';

/// Orchestrates all liveness checks and tracks challenge progress.
///
/// Call [processFrame] on every detected face. The engine emits state changes
/// via [onStatusChanged] and fires [onActionCompleted] / [onAllActionsCompleted]
/// when the sequence is finished.
class LivenessEngine extends ChangeNotifier {
  LivenessEngine({
    required List<LivenessAction> requiredActions,
    this.onActionCompleted,
    this.onAllActionsCompleted,
    this.onStatusChanged,
    this.sessionTimeoutMs = 60000,
  })  : _requiredActions = List.unmodifiable(requiredActions),
        _completedActions = [] {
    _sessionStartMs = DateTime.now().millisecondsSinceEpoch;
  }

  final List<LivenessAction> _requiredActions;
  final List<LivenessAction> _completedActions;

  final HumanValidator _humanValidator = HumanValidator();
  final BlinkDetector _blinkDetector = BlinkDetector();
  final HeadMovementDetector _headMovementDetector = HeadMovementDetector();

  final void Function(LivenessAction action)? onActionCompleted;
  final void Function(LivenessResult result)? onAllActionsCompleted;
  final void Function(DetectionStatus status)? onStatusChanged;
  final int sessionTimeoutMs;

  late int _sessionStartMs;
  DetectionStatus _status = DetectionStatus.initializing;
  bool _isComplete = false;
  int _consecutiveNoFaceFrames = 0;
  double _lastConfidenceScore = 0.0;
  static const int _noFaceFrameLimit = 15;

  DetectionStatus get status => _status;
  List<LivenessAction> get completedActions => List.unmodifiable(_completedActions);
  List<LivenessAction> get remainingActions {
    return _requiredActions.where((a) => !_completedActions.contains(a)).toList();
  }

  LivenessAction? get currentAction =>
      remainingActions.isNotEmpty ? remainingActions.first : null;

  double get progress =>
      _requiredActions.isEmpty ? 1.0 : _completedActions.length / _requiredActions.length;

  bool get isComplete => _isComplete;

  /// Main entry point called per camera frame.
  void processFrame(List<FaceData> faces) {
    if (_isComplete) return;
    if (_checkTimeout()) return;

    // Filter out background noise — only keep faces with meaningful size.
    // minFaceSize=0.10 in ML Kit can still pick up posters/patterns; a 1.5%
    // area threshold removes them without affecting real near/mid-range faces.
    final significant = faces.where((f) => f.faceAreaRatio >= 0.015).toList();

    // --- No face ---
    if (significant.isEmpty) {
      _consecutiveNoFaceFrames++;
      if (_consecutiveNoFaceFrames >= _noFaceFrameLimit) {
        _setStatus(DetectionStatus.noFace);
      }
      return;
    }
    _consecutiveNoFaceFrames = 0;

    // --- Multiple faces ---
    if (significant.length > 1) {
      _setStatus(DetectionStatus.multipleFaces);
      return;
    }

    final face = significant.first;

    // --- Distance checks ---
    if (face.isFaceTooFar) {
      _setStatus(DetectionStatus.faceTooFar);
      return;
    }
    if (face.isFaceTooClose) {
      _setStatus(DetectionStatus.faceTooClose);
      return;
    }

    // --- Centering check ---
    // normalizedBoundingBox is in raw camera image coords (landscape).
    // BoxFit.cover crops the sides, so the visible center maps to roughly
    // (0.5, 0.3–0.6) depending on device aspect ratio. Use generous tolerances
    // so a face inside the oval guide never falsely triggers this check.
    final norm = face.normalizedBoundingBox;
    final cx = (norm.left + norm.right) / 2;
    final cy = (norm.top + norm.bottom) / 2;
    if (cx < 0.10 || cx > 0.90 || cy < 0.05 || cy > 0.95) {
      _setStatus(DetectionStatus.faceNotCentered);
      return;
    }

    // --- Human validation / anti-spoof ---
    final humanResult = _humanValidator.validate(face);
    _lastConfidenceScore = humanResult.confidence;
    if (!humanResult.isValid) {
      _setStatus(DetectionStatus.fakeDetected);
      return;
    }

    // --- Process active liveness action ---
    final action = currentAction;
    if (action == null) return;

    _setStatus(DetectionStatus.actionInProgress);
    _processAction(action, face);
  }

  void _processAction(LivenessAction action, FaceData face) {
    bool detected = false;

    switch (action) {
      case LivenessAction.blink:
        detected = _blinkDetector.process(face);
        break;
      case LivenessAction.turnLeft:
      case LivenessAction.turnRight:
      case LivenessAction.lookUp:
      case LivenessAction.lookDown:
        final moved = _headMovementDetector.process(face);
        detected = moved == action;
        break;
      case LivenessAction.smile:
        detected = face.smilingProbability > 0.80;
        break;
    }

    if (detected) {
      _completedActions.add(action);
      onActionCompleted?.call(action);
      notifyListeners();

      if (remainingActions.isEmpty) {
        _complete();
      }
    }
  }

  bool _checkTimeout() {
    final elapsed = DateTime.now().millisecondsSinceEpoch - _sessionStartMs;
    if (elapsed > sessionTimeoutMs) {
      _isComplete = true;
      _setStatus(DetectionStatus.failed);
      onAllActionsCompleted?.call(
        LivenessResult.failure(
          reason: 'Session timed out',
          completedActions: List.from(_completedActions),
        ),
      );
      return true;
    }
    return false;
  }

  void _complete() {
    _isComplete = true;
    _setStatus(DetectionStatus.completed);
    final elapsed = DateTime.now().millisecondsSinceEpoch - _sessionStartMs;
    onAllActionsCompleted?.call(
      LivenessResult.success(
        completedActions: List.from(_completedActions),
        confidenceScore: _lastConfidenceScore,
        sessionDurationMs: elapsed,
      ),
    );
  }

  void _setStatus(DetectionStatus status) {
    if (_status != status) {
      _status = status;
      onStatusChanged?.call(status);
      notifyListeners();
    }
  }

  void reset() {
    _completedActions.clear();
    _isComplete = false;
    _consecutiveNoFaceFrames = 0;
    _sessionStartMs = DateTime.now().millisecondsSinceEpoch;
    _humanValidator.reset();
    _blinkDetector.reset();
    _headMovementDetector.reset();
    _setStatus(DetectionStatus.initializing);
  }

  @override
  void dispose() {
    super.dispose();
  }
}
