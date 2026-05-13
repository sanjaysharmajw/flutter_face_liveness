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
    this.videoReplayScore,
    this.videoReplayDetected = false,
    this.failureReason,
    this.sessionDurationMs,
    this.sessionId,
    this.faceId,
    this.isFaceIdNew,
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
  final bool isRealHuman;
  final bool spoofDetected;

  /// True if the FaceAntiSpoofing TFLite model flagged potential deepfake.
  final bool deepfakeDetected;

  /// Raw FaceAntiSpoofing model score (null when TFLite disabled).
  final double? tfliteScore;

  /// Raw MiniFASNet video-replay model score (null when disabled).
  final double? videoReplayScore;

  /// True if MiniFASNet flagged a video-replay attack.
  final bool videoReplayDetected;

  // ── Meta ────────────────────────────────────────────────────────────────
  final String? failureReason;
  final int? sessionDurationMs;
  final String? sessionId;

  /// Persistent face identity — non-null only when [LivenessConfig.enableFaceId] is true.
  final String? faceId;
  final bool? isFaceIdNew;

  // ── Copy helpers ─────────────────────────────────────────────────────────

  LivenessResult withTfliteResult(double score, {required bool deepfakeDetected}) =>
      _copy(tfliteScore: score, deepfakeDetected: deepfakeDetected);

  LivenessResult withTfliteScore(double score) => _copy(tfliteScore: score);

  LivenessResult withVideoReplayResult(double score,
          {required bool videoReplayDetected}) =>
      _copy(videoReplayScore: score, videoReplayDetected: videoReplayDetected);

  LivenessResult withFaceId(String id, {required bool isNew}) =>
      _copy(faceId: id, isFaceIdNew: isNew);

  LivenessResult _copy({
    double? tfliteScore,
    bool? deepfakeDetected,
    double? videoReplayScore,
    bool? videoReplayDetected,
    String? faceId,
    bool? isFaceIdNew,
  }) =>
      LivenessResult(
        isSuccess: isSuccess,
        completedActions: completedActions,
        confidenceScore: confidenceScore,
        isRealHuman: isRealHuman,
        spoofDetected: spoofDetected,
        deepfakeDetected: deepfakeDetected ?? this.deepfakeDetected,
        tfliteScore: tfliteScore ?? this.tfliteScore,
        videoReplayScore: videoReplayScore ?? this.videoReplayScore,
        videoReplayDetected: videoReplayDetected ?? this.videoReplayDetected,
        failureReason: failureReason,
        sessionDurationMs: sessionDurationMs,
        sessionId: sessionId,
        faceId: faceId ?? this.faceId,
        isFaceIdNew: isFaceIdNew ?? this.isFaceIdNew,
      );

  @override
  String toString() => 'LivenessResult('
      'success: $isSuccess, '
      'score: ${confidenceScore.toStringAsFixed(2)}, '
      'spoof: $spoofDetected, '
      'deepfake: $deepfakeDetected, '
      'videoReplay: $videoReplayDetected, '
      'actions: $completedActions)';
}
