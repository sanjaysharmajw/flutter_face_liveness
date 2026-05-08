import '../models/face_data.dart';

/// Detects genuine eye blinks using a finite state machine.
///
/// A blink requires both eyes to close (probability < [_closedThreshold])
/// and then re-open (probability > [_openThreshold]) within [_maxBlinkDurationMs].
/// Debounce logic prevents a single blink from being counted multiple times.
class BlinkDetector {
  static const double _closedThreshold = 0.25;
  static const double _openThreshold = 0.75;
  static const int _maxBlinkDurationMs = 600;
  static const int _debounceMs = 800;

  _BlinkState _state = _BlinkState.open;
  int _eyesClosedAtMs = 0;
  int _lastBlinkDetectedMs = 0;

  /// Call on every frame. Returns true exactly once per detected blink.
  bool process(FaceData face) {
    final leftClosed = face.leftEyeOpenProbability < _closedThreshold;
    final rightClosed = face.rightEyeOpenProbability < _closedThreshold;
    final leftOpen = face.leftEyeOpenProbability > _openThreshold;
    final rightOpen = face.rightEyeOpenProbability > _openThreshold;

    final bothClosed = leftClosed && rightClosed;
    final bothOpen = leftOpen && rightOpen;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    switch (_state) {
      case _BlinkState.open:
        if (bothClosed) {
          _state = _BlinkState.closed;
          _eyesClosedAtMs = nowMs;
        }
        break;

      case _BlinkState.closed:
        final closedDuration = nowMs - _eyesClosedAtMs;
        if (closedDuration > _maxBlinkDurationMs) {
          // Held too long → not a blink (e.g., looking away or photo)
          _state = _BlinkState.open;
        } else if (bothOpen) {
          _state = _BlinkState.open;
          final sinceLast = nowMs - _lastBlinkDetectedMs;
          if (sinceLast > _debounceMs) {
            _lastBlinkDetectedMs = nowMs;
            return true;
          }
        }
        break;
    }

    return false;
  }

  void reset() {
    _state = _BlinkState.open;
    _eyesClosedAtMs = 0;
    _lastBlinkDetectedMs = 0;
  }
}

enum _BlinkState { open, closed }
