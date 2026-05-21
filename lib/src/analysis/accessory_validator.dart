import '../models/detection_status.dart';
import '../models/face_data.dart';

/// Detects common face accessories that can interfere with liveness verification.
///
/// Uses two heuristics derived from ML Kit output — no extra model required:
///  - [FaceData.likelySunglasses]: both eye-open probabilities < 0.25 → sunglasses/goggles.
///  - [FaceData.likelyCap]: forehead gap above eyes < 12 % of face height → cap/hat.
///
/// Call [check] each frame while a face is present; it returns a blocking
/// [DetectionStatus] when an accessory is detected, or null when the face is clear.
class AccessoryValidator {
  // Require the condition to persist for this many consecutive frames before
  // flagging, to avoid false positives from momentary eye-close events.
  static const int _frameThreshold = 6;

  int _sunglassesCount = 0;
  int _capCount        = 0;

  /// Returns [DetectionStatus.wearingSunglasses], [DetectionStatus.wearingCap],
  /// or null if no accessory detected.
  ///
  /// Set [skipSunglasses] to true during blink actions — both eyes are
  /// intentionally closed then, which would otherwise cause a false positive.
  DetectionStatus? check(FaceData face, {bool skipSunglasses = false}) {
    // ── Sunglasses / goggles ──────────────────────────────────────────────
    if (!skipSunglasses && face.likelySunglasses) {
      _sunglassesCount++;
    } else {
      _sunglassesCount = 0;
    }

    // ── Cap / hat ─────────────────────────────────────────────────────────
    if (face.likelyCap) {
      _capCount++;
    } else {
      _capCount = 0;
    }

    if (_sunglassesCount >= _frameThreshold) return DetectionStatus.wearingSunglasses;
    if (_capCount        >= _frameThreshold) return DetectionStatus.wearingCap;
    return null;
  }

  void reset() {
    _sunglassesCount = 0;
    _capCount        = 0;
  }
}
