import '../models/face_data.dart';

/// Detects genuine eye blinks — fires as soon as both eyes close (not on re-open).
///
/// Firing on close instead of on re-open eliminates the 150–300 ms wait for the
/// full close→open cycle, making detection feel instant.
///
/// A "was recently open" guard prevents false positives from people with
/// naturally droopy eyelids: both eyes must have been seen clearly open
/// (probability > [_openThreshold]) within the last [_wasOpenWindowMs] before
/// a close event is accepted as a blink.
class BlinkDetector {
  // 0.60 — fires earlier in the blink motion; helps slow-camera devices that
  // never report fully closed eyes below 0.50 due to lower sensor quality.
  static const double _closedThreshold = 0.60;
  // Must stay above _closedThreshold (hysteresis gap = 0.05) to prevent rapid
  // false-positive blinks on users whose eye probability oscillates near 0.60.
  static const double _openThreshold   = 0.65;
  // How recently eyes must have been "open" (ms) — blocks droopy-eye false positives
  static const int    _wasOpenWindowMs = 1500;
  // Minimum gap between two accepted blinks — prevents double-fire on same blink
  static const int    _debounceMs      = 400;
  // L/R close events within this window count as simultaneous (4 frames at 20 fps)
  static const int    _eyeSyncWindowMs = 200;

  int _leftClosedAtMs  = 0;
  int _rightClosedAtMs = 0;
  int _leftOpenAtMs    = 0;
  int _rightOpenAtMs   = 0;
  int _lastBlinkMs     = 0;

  /// Call on every frame. Returns true exactly once per detected blink.
  bool process(FaceData face) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // Track independent timestamps for each eye
    if (face.leftEyeOpenProbability  < _closedThreshold) _leftClosedAtMs  = nowMs;
    if (face.rightEyeOpenProbability < _closedThreshold) _rightClosedAtMs = nowMs;
    if (face.leftEyeOpenProbability  > _openThreshold)   _leftOpenAtMs    = nowMs;
    if (face.rightEyeOpenProbability > _openThreshold)   _rightOpenAtMs   = nowMs;

    // Both eyes closed within the sync window (handles 1–2 frame L/R offset)
    final bothClosed = (nowMs - _leftClosedAtMs  < _eyeSyncWindowMs) &&
                       (nowMs - _rightClosedAtMs < _eyeSyncWindowMs);

    // Both eyes were clearly open recently (guards against droopy eyelids)
    final wasOpen = (nowMs - _leftOpenAtMs  < _wasOpenWindowMs) &&
                    (nowMs - _rightOpenAtMs < _wasOpenWindowMs);

    // Fire immediately on close — no waiting for re-open
    if (bothClosed && wasOpen && nowMs - _lastBlinkMs > _debounceMs) {
      _lastBlinkMs = nowMs;
      return true;
    }

    return false;
  }

  void reset() {
    _leftClosedAtMs  = 0;
    _rightClosedAtMs = 0;
    _leftOpenAtMs    = 0;
    _rightOpenAtMs   = 0;
    _lastBlinkMs     = 0;
  }
}
