import 'package:flutter/material.dart';
import '../models/detection_status.dart';

class StatusIndicatorWidget extends StatelessWidget {
  const StatusIndicatorWidget({super.key, required this.status});
  final DetectionStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color, emoji) = _resolve();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: Container(
        key: ValueKey(status),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withOpacity(0.4)),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.25), blurRadius: 12, spreadRadius: 0),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status == DetectionStatus.initializing)
              SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              )
            else
              _Dot(color: color),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            if (emoji.isNotEmpty) ...[
              const SizedBox(width: 5),
              Text(emoji, style: const TextStyle(fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }

  (String label, Color color, String emoji) _resolve() {
    switch (status) {
      case DetectionStatus.initializing:
        return ('STARTING', Colors.white54, '');
      case DetectionStatus.noFace:
        return ('NO FACE', const Color(0xFFF59E0B), '');
      case DetectionStatus.multipleFaces:
        return ('ONE FACE ONLY', const Color(0xFFF59E0B), '');
      case DetectionStatus.faceTooFar:
        return ('MOVE CLOSER', const Color(0xFFF59E0B), '');
      case DetectionStatus.faceTooClose:
        return ('TOO CLOSE', const Color(0xFFF59E0B), '');
      case DetectionStatus.fakeDetected:
        return ('FAKE DETECTED', const Color(0xFFEF4444), '');
      case DetectionStatus.lowLight:
        return ('LOW LIGHT', const Color(0xFFF59E0B), '');
      case DetectionStatus.faceNotCentered:
        return ('CENTER FACE', const Color(0xFFF59E0B), '');
      case DetectionStatus.ready:
        return ('READY', const Color(0xFF4F6BF4), '');
      case DetectionStatus.actionInProgress:
        return ('DETECTING', const Color(0xFF4F6BF4), '');
      case DetectionStatus.completed:
        return ('VERIFIED', const Color(0xFF10B981), '');
      case DetectionStatus.failed:
        return ('FAILED', const Color(0xFFEF4444), '');
    }
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
