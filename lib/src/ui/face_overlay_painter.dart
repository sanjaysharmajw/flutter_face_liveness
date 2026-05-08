import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/face_data.dart';
import '../models/detection_status.dart';

class FaceOverlayPainter extends CustomPainter {
  const FaceOverlayPainter({
    required this.status,
    required this.animationValue,
    this.faceData,
    this.previewSize,
    this.isFrontCamera = true,
  });

  final DetectionStatus status;
  final double animationValue;
  final FaceData? faceData;
  final Size? previewSize;
  final bool isFrontCamera;

  @override
  void paint(Canvas canvas, Size size) {
    _drawScrim(canvas, size);
    _drawPulseRing(canvas, size);
    _drawOvalBorder(canvas, size);
    _drawCornerBrackets(canvas, size);
  }

  void _drawScrim(Canvas canvas, Size size) {
    final oval = _ovalRect(size);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(oval)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withOpacity(0.62)
        ..style = PaintingStyle.fill,
    );
  }

  void _drawPulseRing(Canvas canvas, Size size) {
    final oval = _ovalRect(size);
    final expand = 6.0 + animationValue * 14.0;
    final opacity = (1.0 - animationValue) * 0.5;
    final color = _statusColor();

    canvas.drawOval(
      oval.inflate(expand),
      Paint()
        ..color = color.withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  void _drawOvalBorder(Canvas canvas, Size size) {
    final oval = _ovalRect(size);
    final color = _statusColor();

    // Gradient stroke via shader on a rect that covers the oval
    final shader = SweepGradient(
      colors: [
        color.withOpacity(0.9),
        color.withOpacity(0.3),
        color.withOpacity(0.9),
      ],
      stops: const [0.0, 0.5, 1.0],
      transform: GradientRotation(animationValue * math.pi * 2),
    ).createShader(oval);

    canvas.drawOval(
      oval,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  void _drawCornerBrackets(Canvas canvas, Size size) {
    final oval = _ovalRect(size);
    final color = _statusColor();
    const arcSpan = math.pi / 7;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    // 4 corner accents positioned at top, right, bottom, left
    for (int i = 0; i < 4; i++) {
      final center = math.pi / 2 * i;
      canvas.drawArc(oval, center - arcSpan / 2, arcSpan, false, paint);
    }
  }

  Rect _ovalRect(Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.42;
    final rx = size.width * 0.38;
    final ry = size.height * 0.24;
    return Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2);
  }

  Color _statusColor() {
    if (status.isError) return const Color(0xFFEF4444);
    if (status.isSuccess) return const Color(0xFF10B981);
    if (status == DetectionStatus.actionInProgress) {
      return Color.lerp(
        const Color(0xFF4F6BF4),
        const Color(0xFF06B6D4),
        animationValue,
      )!;
    }
    return Colors.white;
  }

  @override
  bool shouldRepaint(FaceOverlayPainter old) =>
      old.status != status ||
      old.animationValue != animationValue ||
      old.faceData != faceData;
}
