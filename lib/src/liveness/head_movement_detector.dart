import '../models/face_data.dart';
import '../models/liveness_action.dart';

/// Detects directional head movements using Euler angle thresholds.
///
/// Expects [FaceData.headEulerAngleY] already iOS-corrected (see FaceData.fromFace).
/// Unified convention on both platforms (front camera):
///   headEulerAngleY > 0  → user turned LEFT
///   headEulerAngleY < 0  → user turned RIGHT
///   headEulerAngleX > 0  → user looked UP
///   headEulerAngleX < 0  → user looked DOWN
///
/// An action is confirmed only after:
///   1. The angle exceeds the peak threshold for at least [_holdDurationMs].
///   2. The head returns back inside the neutral zone.
class HeadMovementDetector {
  // Lowered from 15° → 12°: cheap Android devices under-report yaw/pitch via
  // ML Kit even when the user clearly turns; 12° still prevents accidental fire.
  static const double _yawThreshold   = 12.0;
  static const double _pitchThreshold = 12.0;
  static const double _neutralYaw     = 6.0;
  static const double _neutralPitch   = 6.0;
  // 50ms is one frame at 20 fps — fast enough for genuine movement, still
  // blocks single-frame noise from a shaky device.
  static const int    _holdDurationMs = 50;
  // 600ms: shorter dead zone between consecutive actions (was 800ms).
  static const int    _debounceMs     = 600;

  _MovementState _yawState   = _MovementState.neutral;
  _MovementState _pitchState = _MovementState.neutral;

  int _yawPoseStartMs   = 0;
  int _pitchPoseStartMs = 0;
  int _lastTriggerMs    = 0;

  /// Returns the completed [LivenessAction], or null if nothing was detected.
  LivenessAction? process(FaceData face) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastTriggerMs < _debounceMs) return null;

    final yawResult = _processYaw(face.headEulerAngleY, nowMs);
    if (yawResult != null) {
      _lastTriggerMs = nowMs;
      return yawResult;
    }

    final pitchResult = _processPitch(face.headEulerAngleX, nowMs);
    if (pitchResult != null) {
      _lastTriggerMs = nowMs;
      return pitchResult;
    }

    return null;
  }

  LivenessAction? _processYaw(double yaw, int nowMs) {
    switch (_yawState) {
      case _MovementState.neutral:
        if (yaw > _yawThreshold) {
          _yawState = _MovementState.positivePeak;
          _yawPoseStartMs = nowMs;
        } else if (yaw < -_yawThreshold) {
          _yawState = _MovementState.negativePeak;
          _yawPoseStartMs = nowMs;
        }

      case _MovementState.positivePeak:
        if (yaw > _yawThreshold) {
          // Still in peak — fire immediately once held long enough
          if (nowMs - _yawPoseStartMs >= _holdDurationMs) {
            _yawState = _MovementState.neutral;
            return LivenessAction.turnLeft; // front camera: positive yaw = user turned LEFT
          }
        } else if (yaw < _neutralYaw) {
          // Returned to neutral — still count it if held long enough
          _yawState = _MovementState.neutral;
          if (nowMs - _yawPoseStartMs >= _holdDurationMs) {
            return LivenessAction.turnLeft;
          }
        }
        // Between _neutralYaw and _yawThreshold → transitioning, keep waiting

      case _MovementState.negativePeak:
        if (yaw < -_yawThreshold) {
          if (nowMs - _yawPoseStartMs >= _holdDurationMs) {
            _yawState = _MovementState.neutral;
            return LivenessAction.turnRight; // front camera: negative yaw = user turned RIGHT
          }
        } else if (yaw > -_neutralYaw) {
          _yawState = _MovementState.neutral;
          if (nowMs - _yawPoseStartMs >= _holdDurationMs) {
            return LivenessAction.turnRight;
          }
        }
    }
    return null;
  }

  LivenessAction? _processPitch(double pitch, int nowMs) {
    switch (_pitchState) {
      case _MovementState.neutral:
        if (pitch > _pitchThreshold) {
          _pitchState = _MovementState.positivePeak;
          _pitchPoseStartMs = nowMs;
        } else if (pitch < -_pitchThreshold) {
          _pitchState = _MovementState.negativePeak;
          _pitchPoseStartMs = nowMs;
        }

      case _MovementState.positivePeak:
        if (pitch > _pitchThreshold) {
          if (nowMs - _pitchPoseStartMs >= _holdDurationMs) {
            _pitchState = _MovementState.neutral;
            return LivenessAction.lookUp;
          }
        } else if (pitch < _neutralPitch) {
          _pitchState = _MovementState.neutral;
          if (nowMs - _pitchPoseStartMs >= _holdDurationMs) {
            return LivenessAction.lookUp;
          }
        }

      case _MovementState.negativePeak:
        if (pitch < -_pitchThreshold) {
          if (nowMs - _pitchPoseStartMs >= _holdDurationMs) {
            _pitchState = _MovementState.neutral;
            return LivenessAction.lookDown;
          }
        } else if (pitch > -_neutralPitch) {
          _pitchState = _MovementState.neutral;
          if (nowMs - _pitchPoseStartMs >= _holdDurationMs) {
            return LivenessAction.lookDown;
          }
        }
    }
    return null;
  }

  void reset() {
    _yawState        = _MovementState.neutral;
    _pitchState      = _MovementState.neutral;
    _yawPoseStartMs  = 0;
    _pitchPoseStartMs = 0;
    _lastTriggerMs   = 0;
  }
}

enum _MovementState { neutral, positivePeak, negativePeak }
