import 'package:flutter/foundation.dart';
import 'liveness_action.dart';

/// Result returned when liveness verification succeeds or fails.
@immutable
class LivenessResult {
  const LivenessResult({
    required this.isSuccess,
    required this.completedActions,
    required this.confidenceScore,
    this.failureReason,
    this.sessionDurationMs,
  });

  const LivenessResult.success({
    required List<LivenessAction> completedActions,
    required double confidenceScore,
    int? sessionDurationMs,
  }) : this(
          isSuccess: true,
          completedActions: completedActions,
          confidenceScore: confidenceScore,
          sessionDurationMs: sessionDurationMs,
        );

  const LivenessResult.failure({
    required String reason,
    List<LivenessAction> completedActions = const [],
    double confidenceScore = 0.0,
  }) : this(
          isSuccess: false,
          completedActions: completedActions,
          confidenceScore: confidenceScore,
          failureReason: reason,
        );

  final bool isSuccess;
  final List<LivenessAction> completedActions;

  /// Overall liveness confidence score from 0.0 to 1.0
  final double confidenceScore;
  final String? failureReason;
  final int? sessionDurationMs;

  @override
  String toString() => 'LivenessResult(success: $isSuccess, '
      'score: ${confidenceScore.toStringAsFixed(2)}, '
      'actions: $completedActions)';
}
