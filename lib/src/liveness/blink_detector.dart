import '../models/face_data.dart';

/// Detects genuine eye blinks using a finite state machine.
///
/// A blink requires both eyes to close and then re-open within [_maxBlinkDurationMs].
/// Left and right eyes are allowed up to [_eyeSyncWindowMs] apart (ML Kit at fast
/// mode can report them 1–2 frames out of sync at 20 fps).
class BlinkDetector {
  // Raised from 0.25 → catches lighter/quicker blinks that don't fully close
  static const double _closedThreshold  = 0.35;
  // Lowered from 0.75 → re-open is confirmed sooner
  static const double _openThreshold    = 0.65;
  static const int    _maxBlinkDurationMs = 600;
  // Lowered from 800 → user can retry quickly if the first blink wasn't caught
  static const int    _debounceMs       = 400;
  // Grace window: left & right eye close events within 120 ms count as simultaneous
  static const int    _eyeSyncWindowMs  = 120;

  _BlinkState _state             = _BlinkState.open;
  int         _eyesClosedAtMs    = 0;
  int         _lastBlinkMs       = 0;
  int         _leftClosedAtMs    = 0;
  int         _rightClosedAtMs   = 0;

  /// Call on every frame. Returns true exactly once per detected blink.
  bool process(FaceData face) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // Track the last time each eye was seen as closed (independent timestamps)
    if (face.leftEyeOpenProbability  < _closedThreshold) _leftClosedAtMs  = nowMs;
    if (face.rightEyeOpenProbability < _closedThreshold) _rightClosedAtMs = nowMs;

    // Both eyes count as "closed" if each was detected closed within the sync window
    final bothClosed = (nowMs - _leftClosedAtMs  < _eyeSyncWindowMs) &&
                       (nowMs - _rightClosedAtMs < _eyeSyncWindowMs);
    final bothOpen   = face.leftEyeOpenProbability  > _openThreshold &&
                       face.rightEyeOpenProbability > _openThreshold;

    switch (_state) {
      case _BlinkState.open:
        if (bothClosed) {
          _state          = _BlinkState.closed;
          _eyesClosedAtMs = nowMs;
        }
        break;

      case _BlinkState.closed:
        final closedDuration = nowMs - _eyesClosedAtMs;
        if (closedDuration > _maxBlinkDurationMs) {
          // Held too long → looking away or photo, not a genuine blink
          _state = _BlinkState.open;
        } else if (bothOpen) {
          _state = _BlinkState.open;
          if (nowMs - _lastBlinkMs > _debounceMs) {
            _lastBlinkMs = nowMs;
            return true;
          }
        }
        break;
    }

    return false;
  }

  void reset() {
    _state           = _BlinkState.open;
    _eyesClosedAtMs  = 0;
    _lastBlinkMs     = 0;
    _leftClosedAtMs  = 0;
    _rightClosedAtMs = 0;
  }
}

enum _BlinkState { open, closed }
