import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_face_liveness/flutter_face_liveness.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const ExampleApp());
}

const _bg       = Color(0xFF080C14);
const _card     = Color(0xFF111827);
const _primary  = Color(0xFF4F6BF4);
const _purple   = Color(0xFF7C3AED);
const _cyan     = Color(0xFF06B6D4);
const _success  = Color(0xFF10B981);
const _error    = Color(0xFFEF4444);

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Liveness',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(primary: _primary, secondary: _cyan),
      ),
      home: const HomeScreen(),
    );
  }
}

// ─────────────────────────────────────────────
// Home Screen
// ─────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late final AnimationController _scanCtrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  late final AnimationController _pulseCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _scanCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _GridBackground(),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 52),
                AnimatedBuilder(
                  animation: Listenable.merge([_scanCtrl, _pulseCtrl]),
                  builder: (_, __) => _FaceHero(
                    scan: _scanCtrl.value,
                    pulse: CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut).value,
                  ),
                ),
                const SizedBox(height: 36),
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                    colors: [_primary, _purple],
                  ).createShader(b),
                  child: const Text(
                    'Face Liveness',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'AI-powered real presence verification\nentirely on your device',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.6),
                ),
                const SizedBox(height: 44),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _ChallengeCard(
                        icon: Icons.security_rounded,
                        title: 'Standard Verification',
                        subtitle: 'Blink  ·  Turn Left  ·  Turn Right',
                        accentColor: _primary,
                        startColor: const Color(0xFF1C2E6B),
                        endColor: const Color(0xFF0F1A3E),
                        onTap: () => _launch(context, [
                          LivenessAction.blink,
                          LivenessAction.turnLeft,
                          LivenessAction.turnRight,
                        ]),
                      ),
                      const SizedBox(height: 14),
                      _ChallengeCard(
                        icon: Icons.tune_rounded,
                        title: 'Extended Challenge',
                        subtitle: 'Blink  ·  Look Up  ·  Look Down  ·  Smile',
                        accentColor: _cyan,
                        startColor: const Color(0xFF0D2535),
                        endColor: const Color(0xFF091520),
                        onTap: () => _launch(context, [
                          LivenessAction.blink,
                          LivenessAction.lookUp,
                          LivenessAction.lookDown,
                          LivenessAction.smile,
                        ]),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline, size: 11, color: Colors.white24),
                    SizedBox(width: 5),
                    Text(
                      'On-device · No data stored or transmitted',
                      style: TextStyle(color: Colors.white24, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launch(BuildContext ctx, List<LivenessAction> actions) async {
    final status = await Permission.camera.request();
    if (!ctx.mounted) return;
    if (status.isDenied || status.isPermanentlyDenied) {
      _showPermissionSheet(ctx);
      return;
    }
    await Navigator.of(ctx).push(_fade(LivenessScreen(actions: actions)));
  }

  void _showPermissionSheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(
              color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            const Icon(Icons.camera_alt_outlined, color: _primary, size: 48),
            const SizedBox(height: 16),
            const Text('Camera Access Needed',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Grant camera permission in Settings to continue.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: _GradientButton(
                label: 'Open Settings',
                onTap: () { Navigator.pop(ctx); openAppSettings(); },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Liveness Screen
// ─────────────────────────────────────────────

class LivenessScreen extends StatelessWidget {
  const LivenessScreen({super.key, required this.actions});
  final List<LivenessAction> actions;

  @override
  Widget build(BuildContext context) {
    return FlutterFaceLiveness(
      actions: actions,
      showDebugInfo: false,
      onSuccess: (result) => Navigator.of(context).pushReplacement(
        _fade(ResultScreen(result: result, success: true)),
      ),
      onFailed: (reason) => Navigator.of(context).pushReplacement(
        _fade(ResultScreen(failureReason: reason, success: false)),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Result Screen
// ─────────────────────────────────────────────

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, this.result, this.failureReason, required this.success});
  final LivenessResult? result;
  final String? failureReason;
  final bool success;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final Animation<double> _scale =
      CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
  late final Animation<double> _fade =
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.35, 1.0, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.success ? _success : _error;
    return Scaffold(
      body: Stack(
        children: [
          const _GridBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 64),
                  ScaleTransition(
                    scale: _scale,
                    child: _ResultBadge(success: widget.success, color: color),
                  ),
                  const SizedBox(height: 28),
                  FadeTransition(
                    opacity: _fade,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0, 0.15), end: Offset.zero)
                          .animate(_fade),
                      child: Column(
                        children: [
                          Text(
                            widget.success ? 'Identity Verified' : 'Verification Failed',
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.success
                                ? 'Your liveness has been successfully confirmed'
                                : (widget.failureReason ?? 'Please try again'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white38, fontSize: 13, height: 1.6),
                          ),
                          if (widget.success && widget.result != null) ...[
                            const SizedBox(height: 28),
                            _StatsCard(result: widget.result!),
                          ],
                          const SizedBox(height: 36),
                          _GradientButton(
                            label: widget.success ? 'Done' : 'Try Again',
                            colors: widget.success
                                ? [_success, const Color(0xFF059669)]
                                : [_primary, _purple],
                            shadowColor: color,
                            onTap: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultBadge extends StatelessWidget {
  const _ResultBadge({required this.success, required this.color});
  final bool success;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 124,
      height: 124,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.35), width: 1.5),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.25), blurRadius: 48, spreadRadius: 8),
        ],
      ),
      child: Icon(
        success ? Icons.verified_rounded : Icons.cancel_rounded,
        color: color,
        size: 62,
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.result});
  final LivenessResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        children: [
          _StatTile(
            icon: Icons.shield_outlined,
            label: 'Confidence Score',
            value: '${(result.confidenceScore * 100).toStringAsFixed(1)}%',
            accent: _success,
          ),
          _divider(),
          _StatTile(
            icon: Icons.check_circle_outline,
            label: 'Completed Actions',
            value: result.completedActions.map((a) => a.name).join(' · '),
            accent: _primary,
          ),
          if (result.sessionDurationMs != null) ...[
            _divider(),
            _StatTile(
              icon: Icons.timer_outlined,
              label: 'Duration',
              value: '${(result.sessionDurationMs! / 1000).toStringAsFixed(1)}s',
              accent: _cyan,
            ),
          ],
        ],
      ),
    );
  }

  Widget _divider() =>
      const Divider(color: Colors.white10, height: 1, indent: 20, endIndent: 20);
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: accent, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Shared Widgets
// ─────────────────────────────────────────────

class _ChallengeCard extends StatefulWidget {
  const _ChallengeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.startColor,
    required this.endColor,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final Color startColor;
  final Color endColor;
  final VoidCallback onTap;

  @override
  State<_ChallengeCard> createState() => _ChallengeCardState();
}

class _ChallengeCardState extends State<_ChallengeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tap =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 80));

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _tap.forward(),
      onTapUp: (_) { _tap.reverse(); widget.onTap(); },
      onTapCancel: () => _tap.reverse(),
      child: AnimatedBuilder(
        animation: _tap,
        builder: (_, child) =>
            Transform.scale(scale: 1.0 - _tap.value * 0.025, child: child),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [widget.startColor, widget.endColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: widget.accentColor.withOpacity(0.25)),
            boxShadow: [
              BoxShadow(
                color: widget.accentColor.withOpacity(0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: widget.accentColor.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: widget.accentColor.withOpacity(0.25)),
                ),
                child: Icon(widget.icon, color: widget.accentColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(widget.subtitle,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.45), fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  color: Colors.white24, size: 13),
            ],
          ),
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.onTap,
    this.colors = const [_primary, _purple],
    this.shadowColor = _primary,
  });
  final String label;
  final VoidCallback onTap;
  final List<Color> colors;
  final Color shadowColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: shadowColor.withOpacity(0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Painters
// ─────────────────────────────────────────────

class _GridBackground extends StatelessWidget {
  const _GridBackground();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomPaint(painter: _GridPainter()),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D1117), Color(0xFF080C14)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    // Top glow
    canvas.drawCircle(
      Offset(size.width / 2, -60),
      size.width * 0.75,
      Paint()
        ..color = const Color(0xFF4F6BF4).withOpacity(0.06)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60),
    );
    // Dot grid
    final dot = Paint()..color = Colors.white.withOpacity(0.025);
    for (double x = 0; x < size.width; x += 32) {
      for (double y = 0; y < size.height; y += 32) {
        canvas.drawCircle(Offset(x, y), 1.2, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter _) => false;
}

class _FaceHero extends StatelessWidget {
  const _FaceHero({required this.scan, required this.pulse});
  final double scan;
  final double pulse;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 156,
      height: 156,
      child: CustomPaint(painter: _FaceHeroPainter(scan: scan, pulse: pulse)),
    );
  }
}

class _FaceHeroPainter extends CustomPainter {
  const _FaceHeroPainter({required this.scan, required this.pulse});
  final double scan;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.44;

    // Outer glow
    canvas.drawCircle(
      Offset(cx, cy),
      r + 10 + pulse * 10,
      Paint()
        ..color = const Color(0xFF4F6BF4).withOpacity(0.08 + pulse * 0.04)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );

    // Background circle with gradient
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [const Color(0xFF1B2E70), const Color(0xFF0A1530)],
          center: const Alignment(-0.3, -0.3),
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
    );

    // Circle border
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = const Color(0xFF4F6BF4).withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // L-shaped corner brackets
    final bracketRect = Rect.fromCircle(center: Offset(cx, cy), radius: r - 6);
    _drawBrackets(canvas, bracketRect);

    // Face oval
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 3), width: r * 0.7, height: r * 0.85),
      Paint()
        ..color = const Color(0xFF4F6BF4).withOpacity(0.15)
        ..style = PaintingStyle.fill,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 3), width: r * 0.7, height: r * 0.85),
      Paint()
        ..color = const Color(0xFF4F6BF4).withOpacity(0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Eyes
    final eyeY = cy - 10.0;
    final ep = Paint()..color = const Color(0xFF4F6BF4);
    canvas.drawCircle(Offset(cx - r * 0.15, eyeY), 4.5, ep);
    canvas.drawCircle(Offset(cx + r * 0.15, eyeY), 4.5, ep);

    // Scan line
    final top = cy - r + 14;
    final bot = cy + r - 14;
    final scanY = top + scan * (bot - top);

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r - 1)));
    canvas.drawLine(
      Offset(cx - r * 0.65, scanY),
      Offset(cx + r * 0.65, scanY),
      Paint()
        ..color = const Color(0xFF4F6BF4).withOpacity(0.75)
        ..strokeWidth = 1.2,
    );
    canvas.drawRect(
      Rect.fromLTRB(cx - r * 0.65, scanY - 10, cx + r * 0.65, scanY + 10),
      Paint()
        ..color = const Color(0xFF4F6BF4).withOpacity(0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.restore();
  }

  void _drawBrackets(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = const Color(0xFF4F6BF4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    const arcSpan = math.pi / 6;
    canvas.drawArc(rect, math.pi,           arcSpan, false, paint); // top-left
    canvas.drawArc(rect, math.pi * 5 / 3,  arcSpan, false, paint); // top-right
    canvas.drawArc(rect, 0,                 arcSpan, false, paint); // bottom-right
    canvas.drawArc(rect, math.pi * 2 / 3,  arcSpan, false, paint); // bottom-left
  }

  @override
  bool shouldRepaint(_FaceHeroPainter old) =>
      old.scan != scan || old.pulse != pulse;
}

PageRouteBuilder _fade(Widget page) => PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
      transitionDuration: const Duration(milliseconds: 380),
    );
