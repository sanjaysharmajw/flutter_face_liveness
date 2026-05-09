import '../models/face_data.dart';
import '../models/frame_quality.dart';

/// Composite anti-spoofing result.
class AntiSpoofResult {
  const AntiSpoofResult({
    required this.isReal,
    required this.confidence,
    required this.signalScores,
    this.rejectionReason,
  });

  final bool isReal;

  /// Composite confidence: 0.0 (fake) – 1.0 (real).
  final double confidence;

  /// Per-signal breakdown for diagnostics.
  final Map<String, double> signalScores;
  final String? rejectionReason;

  @override
  String toString() =>
      'AntiSpoofResult(real: $isReal, confidence: ${confidence.toStringAsFixed(2)})';
}

/// Multi-signal heuristic anti-spoof engine.
///
/// Signals and weights:
///   1. Eye probability variance   (0.25) — static photos have ~0 variance
///   2. Face geometry plausibility (0.20) — real faces have expected aspect ratio
///   3. Head pose naturalness      (0.15) — flat photos rarely show extreme angles
///   4. Natural eye values         (0.15) — exact 0.0/1.0 pairs are photo artifacts
///   5. Tracking stability         (0.10) — real faces maintain consistent IDs
///   6. Motion signal              (0.10) — real users shift slightly between frames
///   7. Frame quality bonus        (0.05) — very low blur = possible static image
class AntiSpoofEngine {
  static const int _warmupFrames = 6;
  static const int _historySize  = 12;

  int _frameCount = 0;

  final List<double> _leftEyeHistory  = [];
  final List<double> _rightEyeHistory = [];

  // Motion tracking
  final List<double> _yawHistory   = [];
  final List<double> _pitchHistory = [];
  final List<double> _rollHistory  = [];

  int? _lastTrackingId;
  int  _stableTrackingFrames = 0;

  AntiSpoofResult validate(FaceData face, {FrameQuality? quality}) {
    _updateHistory(face);

    // Allow early frames through while history builds
    if (_frameCount <= _warmupFrames) {
      return const AntiSpoofResult(
        isReal: true,
        confidence: 0.65,
        signalScores: {'warmup': 1.0},
      );
    }

    final scores = <String, double>{};
    final reasons = <String>[];

    // ── Signal 1: Eye variance ──────────────────────────────────────────────
    final eyeVar = _eyeVariance();
    final eyeScore = _clamp(0.3 + eyeVar * 28.0, 0.0, 1.0);
    scores['eye_variance'] = eyeScore;

    // ── Signal 2: Face geometry ─────────────────────────────────────────────
    final ar = face.boundingBox.width /
        face.boundingBox.height.clamp(1.0, double.infinity);
    final geoScore = (ar >= 0.45 && ar <= 1.65) ? 1.0 : 0.2;
    scores['geometry'] = geoScore;
    if (geoScore < 0.5) reasons.add('unusual face geometry');

    // ── Signal 3: Head pose naturalness ─────────────────────────────────────
    final rollOk  = face.headEulerAngleZ.abs() < 38.0;
    final pitchOk = face.headEulerAngleX.abs() < 50.0;
    final poseScore = (rollOk && pitchOk) ? 1.0 : 0.3;
    scores['pose'] = poseScore;

    // ── Signal 4: Natural eye probabilities ─────────────────────────────────
    final lp = face.leftEyeOpenProbability;
    final rp = face.rightEyeOpenProbability;
    final bothExact0 = lp == 0.0 && rp == 0.0;
    final bothExact1 = lp == 1.0 && rp == 1.0;
    final naturalEyes = !(bothExact0 || bothExact1);
    final naturalScore = naturalEyes ? 1.0 : 0.1;
    scores['natural_eyes'] = naturalScore;
    if (!naturalEyes) reasons.add('suspicious eye probabilities');

    // ── Signal 5: Tracking stability ────────────────────────────────────────
    final trackScore = (_stableTrackingFrames >= 3)
        ? 1.0
        : _stableTrackingFrames / 3.0;
    scores['tracking'] = trackScore;

    // ── Signal 6: Motion signal ─────────────────────────────────────────────
    // Real humans have subtle natural micro-movement between frames.
    // A replay or photo shows near-zero variance across all Euler angles.
    final motionScore = _motionScore();
    scores['motion'] = motionScore;
    if (motionScore < 0.15) reasons.add('no motion detected — possible replay');

    // ── Signal 7: Frame quality ─────────────────────────────────────────────
    double qualScore = 1.0;
    if (quality != null) {
      // Printed photos often appear in very sharp, perfectly lit conditions
      // with extremely high blur score. We give a mild penalty for unusually
      // perfect frame quality combined with no motion signal.
      if (quality.blurScore > 2500 && motionScore < 0.2) {
        qualScore = 0.5;
        reasons.add('suspiciously perfect frame quality with no motion');
      }
    }
    scores['quality_bonus'] = qualScore;

    // ── Weighted composite ──────────────────────────────────────────────────
    final composite = eyeScore      * 0.25 +
                      geoScore      * 0.20 +
                      poseScore     * 0.15 +
                      naturalScore  * 0.15 +
                      trackScore    * 0.10 +
                      motionScore   * 0.10 +
                      qualScore     * 0.05;

    return AntiSpoofResult(
      isReal: composite >= 0.45,
      confidence: composite,
      signalScores: scores,
      rejectionReason: reasons.isNotEmpty ? reasons.join('; ') : null,
    );
  }

  void _updateHistory(FaceData face) {
    _frameCount++;

    _leftEyeHistory.add(face.leftEyeOpenProbability);
    _rightEyeHistory.add(face.rightEyeOpenProbability);
    if (_leftEyeHistory.length > _historySize) _leftEyeHistory.removeAt(0);
    if (_rightEyeHistory.length > _historySize) _rightEyeHistory.removeAt(0);

    _yawHistory.add(face.headEulerAngleY);
    _pitchHistory.add(face.headEulerAngleX);
    _rollHistory.add(face.headEulerAngleZ);
    if (_yawHistory.length > _historySize) _yawHistory.removeAt(0);
    if (_pitchHistory.length > _historySize) _pitchHistory.removeAt(0);
    if (_rollHistory.length > _historySize) _rollHistory.removeAt(0);

    if (face.trackingId != null) {
      if (face.trackingId == _lastTrackingId) {
        _stableTrackingFrames++;
      } else {
        _lastTrackingId = face.trackingId;
        _stableTrackingFrames = 1;
      }
    }
  }

  double _eyeVariance() {
    if (_leftEyeHistory.length < 3) return 0.0;
    final all = [..._leftEyeHistory, ..._rightEyeHistory];
    final mean = all.reduce((a, b) => a + b) / all.length;
    final variance = all.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / all.length;
    return variance;
  }

  double _motionScore() {
    if (_yawHistory.length < 4) return 0.5;
    double var_ = _variance(_yawHistory) + _variance(_pitchHistory) + _variance(_rollHistory);
    return _clamp(var_ / 3.0, 0.0, 1.0);
  }

  double _variance(List<double> values) {
    if (values.length < 2) return 0.0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final v = values.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / values.length;
    return _clamp(v / 10.0, 0.0, 1.0);
  }

  static double _clamp(double v, double min, double max) =>
      v < min ? min : (v > max ? max : v);

  void reset() {
    _frameCount = 0;
    _leftEyeHistory.clear();
    _rightEyeHistory.clear();
    _yawHistory.clear();
    _pitchHistory.clear();
    _rollHistory.clear();
    _lastTrackingId = null;
    _stableTrackingFrames = 0;
  }
}
