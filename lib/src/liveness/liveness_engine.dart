import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/detection_status.dart';
import '../models/face_data.dart';
import '../models/frame_quality.dart';
import '../models/liveness_action.dart';
import '../models/liveness_config.dart';
import '../models/liveness_result.dart';
import '../ml/human_validator.dart';
import '../camera/camera_validator.dart';
import '../security/frame_hasher.dart';
import '../security/session_manager.dart';
import 'blink_detector.dart';
import 'head_movement_detector.dart';

/// Orchestrates all liveness checks and tracks challenge progress.
///
/// Usage: call [processFrame] on every camera frame.
class LivenessEngine extends ChangeNotifier {
  LivenessEngine({
    required List<LivenessAction> requiredActions,
    required LivenessConfig config,
    this.onActionCompleted,
    this.onAllActionsCompleted,
    this.onStatusChanged,
  })  : _config = config,
        _cameraValidator = CameraValidator(config) {
    _buildActionSequence(requiredActions);
  }

  final LivenessConfig _config;
  final CameraValidator _cameraValidator;

  final HumanValidator _humanValidator = HumanValidator();
  final BlinkDetector _blinkDetector   = BlinkDetector();
  final HeadMovementDetector _headDetector = HeadMovementDetector();
  final FrameHasher _frameHasher  = FrameHasher();
  final SessionManager _session   = SessionManager();

  List<LivenessAction> _sequence = [];
  final List<LivenessAction> _completed = [];

  int _consecutiveNoFaceFrames = 0;
  double _lastConfidenceScore  = 0.0;
  bool _isComplete             = false;

  static const int _noFaceFrameLimit = 15;

  final void Function(LivenessAction action)?   onActionCompleted;
  final void Function(LivenessResult result)?   onAllActionsCompleted;
  final void Function(DetectionStatus status)?  onStatusChanged;

  DetectionStatus _status = DetectionStatus.initializing;

  // ── Public getters ──────────────────────────────────────────────────────
  String get sessionId        => _session.sessionId;
  DetectionStatus get status  => _status;
  List<LivenessAction> get completedActions => List.unmodifiable(_completed);
  List<LivenessAction> get remainingActions =>
      _sequence.where((a) => !_completed.contains(a)).toList();
  LivenessAction? get currentAction =>
      remainingActions.isNotEmpty ? remainingActions.first : null;

  double get progress =>
      _sequence.isEmpty ? 1.0 : _completed.length / _sequence.length;

  int get totalActions => _sequence.length;
  bool get isComplete  => _isComplete;

  // ── Frame processing ────────────────────────────────────────────────────

  void processFrame(List<FaceData> faces, {FrameQuality? quality}) {
    if (_isComplete) return;
    _session.incrementFrame();

    if (_checkTimeout()) return;

    // ── Duplicate / static-image detection ─────────────────────────────────
    if (_config.enableDuplicateFrameDetection && quality != null) {
      if (_frameHasher.isDuplicate(quality.frameHash)) {
        _setStatus(DetectionStatus.fakeDetected);
        return;
      }
    }

    // ── Frame quality checks ───────────────────────────────────────────────
    if (quality != null) {
      final qualIssue = _cameraValidator.validateQuality(quality);
      if (qualIssue != null) {
        _setStatus(qualIssue);
        return;
      }
    }

    // ── Face count filter ──────────────────────────────────────────────────
    final significant = faces
        .where((f) => f.faceAreaRatio >= _config.faceTooFarRatio)
        .toList();

    if (significant.isEmpty) {
      _consecutiveNoFaceFrames++;
      if (_consecutiveNoFaceFrames >= _noFaceFrameLimit) {
        _setStatus(DetectionStatus.noFace);
      }
      return;
    }
    _consecutiveNoFaceFrames = 0;

    if (significant.length > 1) {
      _setStatus(DetectionStatus.multipleFaces);
      return;
    }

    final face = significant.first;

    // ── Face geometry checks ───────────────────────────────────────────────
    final faceIssue = _cameraValidator.validateFace(face);
    if (faceIssue != null) {
      _setStatus(faceIssue);
      return;
    }

    // ── Anti-spoof ─────────────────────────────────────────────────────────
    if (_config.enableAntiSpoof) {
      final humanResult = _humanValidator.validate(face, quality: quality);
      _lastConfidenceScore = humanResult.confidence;
      if (!humanResult.isValid) {
        _setStatus(DetectionStatus.fakeDetected);
        return;
      }
    }

    // ── Active liveness challenge ──────────────────────────────────────────
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
      case LivenessAction.turnLeft:
      case LivenessAction.turnRight:
      case LivenessAction.lookUp:
      case LivenessAction.lookDown:
        final moved = _headDetector.process(face);
        detected = moved == action;
      case LivenessAction.smile:
        detected = face.smilingProbability > 0.80;
      case LivenessAction.openMouth:
        detected = _detectMouthOpen(face);
    }

    if (detected) {
      _completed.add(action);
      onActionCompleted?.call(action);
      notifyListeners();

      if (remainingActions.isEmpty) {
        _complete();
      }
    }
  }

  // ── Mouth open detection ────────────────────────────────────────────────
  // ML Kit doesn't expose lip landmarks in basic mode.
  // We approximate via bounding-box height growth and low smile probability.
  double _prevFaceHeight = 0;
  static const double _mouthOpenRatio = 1.08;

  bool _detectMouthOpen(FaceData face) {
    final h = face.boundingBox.height;
    if (_prevFaceHeight == 0) {
      _prevFaceHeight = h;
      return false;
    }
    final grown = h / _prevFaceHeight;
    _prevFaceHeight = h;
    return grown > _mouthOpenRatio && face.smilingProbability < 0.3;
  }

  // ── Completion ──────────────────────────────────────────────────────────

  bool _checkTimeout() {
    if (_session.isTimedOut(_config.sessionTimeoutMs)) {
      _isComplete = true;
      _session.close();
      _setStatus(DetectionStatus.failed);
      onAllActionsCompleted?.call(LivenessResult.failure(
        reason: 'Session timed out',
        completedActions: List.from(_completed),
        sessionId: _session.sessionId,
      ));
      return true;
    }
    return false;
  }

  void _complete() {
    _isComplete = true;
    _session.close();
    _setStatus(DetectionStatus.completed);
    onAllActionsCompleted?.call(LivenessResult.success(
      completedActions: List.from(_completed),
      confidenceScore: _lastConfidenceScore,
      sessionDurationMs: _session.elapsedMs,
      sessionId: _session.sessionId,
    ));
  }

  void _setStatus(DetectionStatus s) {
    if (_status != s) {
      _status = s;
      onStatusChanged?.call(s);
      notifyListeners();
    }
  }

  void _buildActionSequence(List<LivenessAction> actions) {
    final list = List<LivenessAction>.from(actions);
    if (_config.randomizeActions) {
      // Fisher-Yates shuffle for uniform random ordering
      final rng = math.Random();
      for (int i = list.length - 1; i > 0; i--) {
        final j = rng.nextInt(i + 1);
        final tmp = list[i];
        list[i] = list[j];
        list[j] = tmp;
      }
    }
    _sequence = list;
  }

  // ── Reset ───────────────────────────────────────────────────────────────

  void reset(List<LivenessAction> actions) {
    _completed.clear();
    _isComplete = false;
    _consecutiveNoFaceFrames = 0;
    _lastConfidenceScore = 0.0;
    _prevFaceHeight = 0;
    _humanValidator.reset();
    _blinkDetector.reset();
    _headDetector.reset();
    _frameHasher.reset();
    _session.reset();
    _buildActionSequence(actions);
    _setStatus(DetectionStatus.initializing);
  }

  @override
  void dispose() {
    _session.close();
    super.dispose();
  }
}
