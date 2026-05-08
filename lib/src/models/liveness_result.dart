import 'package:flutter/foundation.dart';
import 'liveness_action.dart';

/// Result returned when a liveness verification session ends.
@immutable
class LivenessResult {
  const LivenessResult({
    required this.isSuccess,
    required this.completedActions,
    required this.confidenceScore,
    this.isRealHuman = true,
    this.spoofDetected = false,
    this.deepfakeDetected = false,
    this.tfliteScore,
    this.failureReason,
    this.sessionDurationMs,
    this.sessionId,
    this.faceId,
  });

  /// Convenience constructor for a successful result.
  const LivenessResult.success({
    required List<LivenessAction> completedActions,
    required double confidenceScore,
    int? sessionDurationMs,
    String? sessionId,
    double? tfliteScore,
  }) : this(
          isSuccess: true,
          completedActions: completedActions,
          confidenceScore: confidenceScore,
          isRealHuman: true,
          spoofDetected: false,
          deepfakeDetected: false,
          sessionDurationMs: sessionDurationMs,
          sessionId: sessionId,
          tfliteScore: tfliteScore,
        );

  /// Convenience constructor for a failed result.
  const LivenessResult.failure({
    required String reason,
    List<LivenessAction> completedActions = const [],
    double confidenceScore = 0.0,
    bool spoofDetected = false,
    bool deepfakeDetected = false,
    String? sessionId,
  }) : this(
          isSuccess: false,
          completedActions: completedActions,
          confidenceScore: confidenceScore,
          isRealHuman: false,
          spoofDetected: spoofDetected,
          deepfakeDetected: deepfakeDetected,
          failureReason: reason,
          sessionId: sessionId,
        );

  // ── Core ────────────────────────────────────────────────────────────────
  final bool isSuccess;
  final List<LivenessAction> completedActions;

  /// Heuristic anti-spoof confidence: 0.0 (definitely fake) – 1.0 (real).
  final double confidenceScore;

  // ── Anti-spoof ──────────────────────────────────────────────────────────
  /// Overall human-presence verdict.
  final bool isRealHuman;

  /// True if heuristic signals detected a printed photo / screen replay.
  final bool spoofDetected;

  /// True if TFLite model flagged potential deepfake content.
  final bool deepfakeDetected;

  /// Raw TFLite model output score (null when TFLite is disabled).
  final double? tfliteScore;

  // ── Meta ────────────────────────────────────────────────────────────────
  final String? failureReason;
  final int? sessionDurationMs;

  /// Unique session identifier for audit trails.
  final String? sessionId;

  /// Persistent face identity — same physical person always gets the same ID,
  /// even across separate app sessions.
  ///
  /// Non-null only when [LivenessConfig.enableFaceId] is `true`.
  /// Format: `FID-3A9F2B1C4E8D…` (24 hex chars).
  final String? faceId;

  /// Returns a copy with [faceId] set (used by LivenessController after
  /// the identity service resolves the ID asynchronously).
  LivenessResult withFaceId(String id) => LivenessResult(
        isSuccess: isSuccess,
        completedActions: completedActions,
        confidenceScore: confidenceScore,
        isRealHuman: isRealHuman,
        spoofDetected: spoofDetected,
        deepfakeDetected: deepfakeDetected,
        tfliteScore: tfliteScore,
        failureReason: failureReason,
        sessionDurationMs: sessionDurationMs,
        sessionId: sessionId,
        faceId: id,
      );

  @override
  String toString() => 'LivenessResult('
      'success: $isSuccess, '
      'score: ${confidenceScore.toStringAsFixed(2)}, '
      'spoof: $spoofDetected, '
      'deepfake: $deepfakeDetected, '
      'actions: $completedActions)';
}
