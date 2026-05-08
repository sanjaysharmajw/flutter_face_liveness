import 'package:flutter/material.dart';
import '../models/detection_status.dart';
import '../models/liveness_action.dart';

class LivenessInstructionsWidget extends StatelessWidget {
  const LivenessInstructionsWidget({
    super.key,
    required this.status,
    this.currentAction,
    this.progress = 0.0,
    this.totalActions = 0,
    this.completedCount = 0,
  });

  final DetectionStatus status;
  final LivenessAction? currentAction;
  final double progress;
  final int totalActions;
  final int completedCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (totalActions > 0) ...[
              _ProgressHeader(
                completed: completedCount,
                total: totalActions,
                progress: progress,
                isSuccess: status.isSuccess,
              ),
              const SizedBox(height: 14),
            ],
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position:
                      Tween(begin: const Offset(0, 0.15), end: Offset.zero)
                          .animate(anim),
                  child: child,
                ),
              ),
              child: _InstructionRow(
                key: ValueKey('$status-$currentAction'),
                status: status,
                action: currentAction,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.completed,
    required this.total,
    required this.progress,
    required this.isSuccess,
  });
  final int completed;
  final int total;
  final double progress;
  final bool isSuccess;

  @override
  Widget build(BuildContext context) {
    final trackColor = isSuccess
        ? const Color(0xFF10B981)
        : const Color(0xFF4F6BF4);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Step $completed of $total',
              style: const TextStyle(
                  color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500),
            ),
            Text(
              '${(progress * 100).toInt()}%',
              style: TextStyle(
                  color: trackColor, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            builder: (_, v, __) => LinearProgressIndicator(
              value: v,
              minHeight: 5,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(trackColor),
            ),
          ),
        ),
      ],
    );
  }
}

class _InstructionRow extends StatelessWidget {
  const _InstructionRow({super.key, required this.status, this.action});
  final DetectionStatus status;
  final LivenessAction? action;

  @override
  Widget build(BuildContext context) {
    final (emoji, text, color) = _resolve();

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.22)),
          ),
          child: Center(
            child: Text(emoji, style: const TextStyle(fontSize: 22)),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  (String emoji, String text, Color color) _resolve() {
    if (status == DetectionStatus.actionInProgress && action != null) {
      return (action!.iconEmoji, action!.instruction, const Color(0xFF4F6BF4));
    }
    if (status.isSuccess) {
      return ('✅', 'Verification complete!', const Color(0xFF10B981));
    }
    if (status.isError) {
      return ('⚠️', status.message, const Color(0xFFEF4444));
    }
    return ('ℹ️', status.message, Colors.white54);
  }
}
