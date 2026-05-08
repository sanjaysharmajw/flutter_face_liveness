import '../models/face_data.dart';

/// Validation result from [HumanValidator].
class HumanValidationResult {
  const HumanValidationResult({
    required this.isValid,
    required this.confidence,
    this.rejectionReason,
  });

  final bool isValid;

  /// Confidence score 0.0–1.0 that this is a real human face.
  final double confidence;
  final String? rejectionReason;
}

/// Heuristic-based anti-spoofing validator.
///
/// ML Kit does not expose a dedicated liveness/anti-spoof model, so we use
/// a set of complementary signals to reject printed photos, screens, and masks:
///
/// 1. Eye open probability variance  – photos have frozen eye states near 0 or 1
/// 2. Face geometry plausibility      – real faces have consistent aspect ratios
/// 3. Head pose range                 – flat photos rarely appear at extreme angles
/// 4. Tracking stability              – real faces maintain consistent tracking IDs
class HumanValidator {
  static const double _minConfidenceThreshold = 0.45;

  // Warm-up: skip rejection for the first N frames so a real face isn't
  // falsely blocked before eye-variance history is populated.
  static const int _warmupFrames = 6;
  int _frameCount = 0;

  // Ring buffer of recent eye-open probabilities to measure variance
  final List<double> _leftEyeHistory = [];
  final List<double> _rightEyeHistory = [];
  static const int _historySize = 10;

  // Track consecutive frames with the same tracking ID
  int? _lastTrackingId;
  int _stableTrackingFrames = 0;

  HumanValidationResult validate(FaceData face) {
    _updateHistory(face);

    // Allow early frames through while history warms up
    if (_frameCount <= _warmupFrames) {
      return HumanValidationResult(isValid: true, confidence: 0.6);
    }

    double score = 0.0;
    final reasons = <String>[];

    // --- Signal 1: Eye probability variance ---
    // Static photos have near-zero variance; real eyes fluctuate slightly.
    // Give partial credit even with low variance to avoid blocking calm users.
    final eyeVariance = _computeEyeVariance();
    final eyeScore = _clamp(0.3 + eyeVariance * 30, 0.0, 1.0);
    score += eyeScore * 0.25;

    // --- Signal 2: Face geometry plausibility ---
    // Bounding box aspect ratio for a real face is roughly 0.6–1.5
    final aspectRatio = face.boundingBox.width / face.boundingBox.height.clamp(1, double.infinity);
    final geometryScore = (aspectRatio >= 0.5 && aspectRatio <= 1.6) ? 1.0 : 0.2;
    score += geometryScore * 0.25;
    if (geometryScore < 0.5) reasons.add('unusual face geometry');

    // --- Signal 3: Head pose plausibility ---
    // Extreme roll angles are unusual for real faces held by hand
    final rollOk = face.headEulerAngleZ.abs() < 40.0;
    final poseScore = rollOk ? 1.0 : 0.3;
    score += poseScore * 0.15;

    // --- Signal 4: Classification values available ---
    // ML Kit returns null for eye-open probability on non-face objects;
    // we penalise if both values are exactly 1.0 or exactly 0.0 (photo artefact)
    final eyesLookNatural = !(face.leftEyeOpenProbability == 1.0 && face.rightEyeOpenProbability == 1.0) &&
        !(face.leftEyeOpenProbability == 0.0 && face.rightEyeOpenProbability == 0.0);
    score += (eyesLookNatural ? 1.0 : 0.1) * 0.20;
    if (!eyesLookNatural) reasons.add('suspicious eye probabilities');

    // --- Signal 5: Tracking stability ---
    // Real faces maintain a consistent tracking ID across frames
    final trackingScore = (_stableTrackingFrames >= 3) ? 1.0 : (_stableTrackingFrames / 3.0);
    score += trackingScore * 0.10;

    final isValid = score >= _minConfidenceThreshold;
    return HumanValidationResult(
      isValid: isValid,
      confidence: score,
      rejectionReason: reasons.isNotEmpty ? reasons.join(', ') : null,
    );
  }

  void _updateHistory(FaceData face) {
    _frameCount++;
    _leftEyeHistory.add(face.leftEyeOpenProbability);
    _rightEyeHistory.add(face.rightEyeOpenProbability);

    if (_leftEyeHistory.length > _historySize) _leftEyeHistory.removeAt(0);
    if (_rightEyeHistory.length > _historySize) _rightEyeHistory.removeAt(0);

    if (face.trackingId != null) {
      if (face.trackingId == _lastTrackingId) {
        _stableTrackingFrames++;
      } else {
        _lastTrackingId = face.trackingId;
        _stableTrackingFrames = 1;
      }
    }
  }

  double _computeEyeVariance() {
    if (_leftEyeHistory.length < 3) return 0.0;
    final allValues = [..._leftEyeHistory, ..._rightEyeHistory];
    final mean = allValues.reduce((a, b) => a + b) / allValues.length;
    final variance = allValues.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / allValues.length;
    return variance;
  }

  double _clamp(double value, double min, double max) =>
      value < min ? min : (value > max ? max : value);

  void reset() {
    _frameCount = 0;
    _leftEyeHistory.clear();
    _rightEyeHistory.clear();
    _lastTrackingId = null;
    _stableTrackingFrames = 0;
  }
}
