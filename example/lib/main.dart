import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_face_liveness/flutter_face_liveness.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const ExampleApp());
}

// Light palette
const _bg       = Color(0xFFF4F6FF);
const _surface  = Colors.white;
const _primary  = Color(0xFF4F6BF4);
const _purple   = Color(0xFF7C3AED);
const _cyan     = Color(0xFF06B6D4);
const _success  = Color(0xFF10B981);
const _error    = Color(0xFFEF4444);
const _textPrimary   = Color(0xFF0F172A);
const _textSecondary = Color(0xFF64748B);

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Liveness',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.light(primary: _primary, secondary: _cyan),
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

  List<String> _registeredFaceIds = [];

  @override
  void initState() {
    super.initState();
    _loadFaceIds();
  }

  Future<void> _loadFaceIds() async {
    try {
      final service = FaceIdentityService();
      await service.initialize();
      if (!mounted) { service.dispose(); return; }
      setState(() => _registeredFaceIds = service.registeredFaceIds.toList());
      service.dispose();
    } catch (_) {}
  }

  @override
  void dispose() {
    _scanCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          const _LightBackground(),
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
              children: [
                const SizedBox(height: 48),
                AnimatedBuilder(
                  animation: Listenable.merge([_scanCtrl, _pulseCtrl]),
                  builder: (_, __) => _FaceHero(
                    scan: _scanCtrl.value,
                    pulse: CurvedAnimation(
                            parent: _pulseCtrl, curve: Curves.easeInOut)
                        .value,
                  ),
                ),
                const SizedBox(height: 32),
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                    colors: [_primary, _purple],
                  ).createShader(b),
                  child: const Text(
                    'Face Liveness',
                    style: TextStyle(
                      fontSize: 32,
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
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 40),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _ChallengeCard(
                        icon: Icons.security_rounded,
                        title: 'Standard Verification',
                        subtitle: 'Blink  ·  Turn Left  ·  Turn Right',
                        accentColor: _primary,
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
                        onTap: () => _launch(context, [
                          LivenessAction.blink,
                          LivenessAction.lookUp,
                          LivenessAction.lookDown,
                          LivenessAction.smile,
                        ]),
                      ),
                      const SizedBox(height: 14),
                      _ChallengeCard(
                        icon: Icons.face_retouching_natural_rounded,
                        title: 'Full Challenge',
                        subtitle: 'Blink  ·  Turn Left  ·  Turn Right  ·  Open Mouth',
                        accentColor: _purple,
                        onTap: () => _launch(context, [
                          LivenessAction.blink,
                          LivenessAction.turnLeft,
                          LivenessAction.turnRight,
                          LivenessAction.openMouth,
                        ]),
                      ),
                      const SizedBox(height: 14),
                      _ChallengeCard(
                        icon: Icons.fingerprint_rounded,
                        title: 'Face ID — Auto',
                        subtitle: 'Same face → same ID across sessions',
                        accentColor: _success,
                        onTap: () => _launchWithFaceId(context),
                      ),
                      const SizedBox(height: 14),
                      _ChallengeCard(
                        icon: Icons.person_add_alt_1_rounded,
                        title: 'Register Face',
                        subtitle: 'One-time enrolment · Rejects duplicates',
                        accentColor: _cyan,
                        onTap: () => _launchRegisterFace(context),
                      ),
                      const SizedBox(height: 14),
                      _ChallengeCard(
                        icon: Icons.how_to_reg_rounded,
                        title: 'Verify Face',
                        subtitle: 'Login-only · Never registers unknown faces',
                        accentColor: _purple,
                        onTap: () => _launchVerifyFace(context),
                      ),
                      const SizedBox(height: 14),
                      _ChallengeCard(
                        icon: Icons.psychology_outlined,
                        title: 'With TFLite Anti-Spoof',
                        subtitle: 'TFLite anti-spoof + video replay detection',
                        accentColor: _error,
                        onTap: () => _launchWithTFLite(context),
                      ),
                    ],
                  ),
                ),
                if (_registeredFaceIds.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _FaceIdHistoryCard(
                      faceIds: _registeredFaceIds,
                      onClear: () async {
                        final service = FaceIdentityService();
                        await service.initialize();
                        await service.clearAllFaces();
                        service.dispose();
                        if (mounted) setState(() => _registeredFaceIds = []);
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline, size: 11, color: _textSecondary.withValues(alpha:0.5)),
                    const SizedBox(width: 5),
                    Text(
                      'On-device · No data stored or transmitted',
                      style: TextStyle(
                          color: _textSecondary.withValues(alpha:0.5), fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
              ],
            ),
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

  Future<void> _launchWithTFLite(BuildContext ctx) async {
    final status = await Permission.camera.request();
    if (!ctx.mounted) return;
    if (status.isDenied || status.isPermanentlyDenied) {
      _showPermissionSheet(ctx);
      return;
    }
    await Navigator.of(ctx).push(_fade(const LivenessScreen(
      actions: [LivenessAction.blink, LivenessAction.turnLeft],
      enableTFLite: true,
      enableVideoReplay: true,
    )));
  }

  Future<void> _launchWithFaceId(BuildContext ctx) async {
    final status = await Permission.camera.request();
    if (!ctx.mounted) return;
    if (status.isDenied || status.isPermanentlyDenied) {
      _showPermissionSheet(ctx);
      return;
    }
    await Navigator.of(ctx).push(_fade(const LivenessScreen(
      actions: [LivenessAction.blink, LivenessAction.turnLeft],
      enableFaceId: true,
      faceIdMode: FaceIdMode.auto,
    )));
    if (mounted) await _loadFaceIds();
  }

  Future<void> _launchRegisterFace(BuildContext ctx) async {
    final status = await Permission.camera.request();
    if (!ctx.mounted) return;
    if (status.isDenied || status.isPermanentlyDenied) {
      _showPermissionSheet(ctx);
      return;
    }
    await Navigator.of(ctx).push(_fade(const LivenessScreen(
      actions: [LivenessAction.blink, LivenessAction.turnLeft],
      enableFaceId: true,
      faceIdMode: FaceIdMode.registrationOnly,
    )));
    if (mounted) await _loadFaceIds();
  }

  Future<void> _launchVerifyFace(BuildContext ctx) async {
    final status = await Permission.camera.request();
    if (!ctx.mounted) return;
    if (status.isDenied || status.isPermanentlyDenied) {
      _showPermissionSheet(ctx);
      return;
    }
    await Navigator.of(ctx).push(_fade(const LivenessScreen(
      actions: [LivenessAction.blink, LivenessAction.turnLeft],
      enableFaceId: true,
      faceIdMode: FaceIdMode.verificationOnly,
    )));
  }

  void _showPermissionSheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _primary.withValues(alpha:0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.camera_alt_outlined, color: _primary, size: 30),
            ),
            const SizedBox(height: 16),
            const Text(
              'Camera Access Needed',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Grant camera permission in Settings to continue.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _textSecondary, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: _GradientButton(
                label: 'Open Settings',
                onTap: () {
                  Navigator.pop(ctx);
                  openAppSettings();
                },
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
  const LivenessScreen({
    super.key,
    required this.actions,
    this.enableFaceId = false,
    this.faceIdMode = FaceIdMode.auto,
    this.enableTFLite = true,
    this.enableVideoReplay = false,
  });
  final List<LivenessAction> actions;
  final bool enableFaceId;
  final FaceIdMode faceIdMode;
  final bool enableTFLite;
  final bool enableVideoReplay;

  @override
  Widget build(BuildContext context) {
    return FlutterFaceLiveness(
      actions: actions,
      config: LivenessConfig(
        randomizeActions: true,
        enableAntiSpoof: true,
        enableBrightnessCheck: true,
        enableDuplicateFrameDetection: true,
        enableFaceMesh: true,
        enableBlurDetection: true,
        enableFaceId: enableFaceId,
        faceIdMode: faceIdMode,
        enableTFLite: enableTFLite,
        enableVideoReplayDetection: enableVideoReplay,
        showDebugOverlay: true,
      ),
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
  const ResultScreen(
      {super.key, this.result, this.failureReason, required this.success});
  final LivenessResult? result;
  final String? failureReason;
  final bool success;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final Animation<double> _scale =
      CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
  late final Animation<double> _fadeAnim =
      CurvedAnimation(
          parent: _ctrl, curve: const Interval(0.35, 1.0, curve: Curves.easeOut));

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
      backgroundColor: _bg,
      body: Stack(
        children: [
          const _LightBackground(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 60),
                  ScaleTransition(
                    scale: _scale,
                    child: _ResultBadge(success: widget.success, color: color),
                  ),
                  const SizedBox(height: 28),
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position:
                          Tween(begin: const Offset(0, 0.12), end: Offset.zero)
                              .animate(_fadeAnim),
                      child: Column(
                        children: [
                          Text(
                            widget.success
                                ? 'Identity Verified'
                                : 'Verification Failed',
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: _textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.success
                                ? 'Your liveness has been successfully confirmed'
                                : (widget.failureReason?.isNotEmpty == true
                                    ? widget.failureReason!
                                    : 'Verification could not be completed. Please try again.'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: widget.success
                                  ? _textSecondary
                                  : _error,
                              fontSize: widget.success ? 13 : 14,
                              height: 1.6,
                              fontWeight: widget.success
                                  ? FontWeight.normal
                                  : FontWeight.w600,
                            ),
                          ),
                          if (widget.result != null) ...[
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
                          const SizedBox(height: 32),
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
        color: color.withValues(alpha:0.1),
        border: Border.all(color: color.withValues(alpha:0.3), width: 1.5),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha:0.2), blurRadius: 40, spreadRadius: 4),
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
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.black.withValues(alpha:0.05)),
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
          _divider(),
          _StatTile(
            icon: result.spoofDetected
                ? Icons.warning_amber_rounded
                : Icons.verified_user_outlined,
            label: 'Anti-Spoof',
            value: result.spoofDetected ? 'Spoof Detected' : 'Passed',
            accent: result.spoofDetected ? _error : _success,
          ),
          _divider(),
          result.tfliteScore != null
              ? _ScoreBarTile(
                  icon: result.deepfakeDetected
                      ? Icons.warning_amber_rounded
                      : Icons.security_rounded,
                  label: 'Deepfake / Anti-Spoof',
                  status: result.deepfakeDetected
                      ? 'Spoofed / Deepfake'
                      : 'Genuine Face',
                  realScore: result.tfliteScore!,
                  accent: result.deepfakeDetected ? _error : _success,
                )
              : const _StatTile(
                  icon: Icons.help_outline_rounded,
                  label: 'Deepfake / Anti-Spoof',
                  value: 'N/A — TFLite not enabled',
                  accent: _textSecondary,
                ),
          _divider(),
          result.videoReplayScore != null
              ? _ScoreBarTile(
                  icon: result.videoReplayDetected
                      ? Icons.videocam_off_rounded
                      : Icons.videocam_rounded,
                  label: 'Video Replay Detection',
                  status: result.videoReplayDetected
                      ? 'Video Replay Attack!'
                      : 'Live Face',
                  realScore: result.videoReplayScore!,
                  accent: result.videoReplayDetected ? _error : _success,
                )
              : const _StatTile(
                  icon: Icons.help_outline_rounded,
                  label: 'Video Replay Detection',
                  value: 'N/A — Video Replay model not enabled',
                  accent: _textSecondary,
                ),
          if (result.faceId != null) ...[
            _divider(),
            _FaceIdMatchCard(
              faceId:           result.faceId!,
              isNew:            result.isFaceIdNew ?? true,
              alreadyRegistered: result.faceAlreadyRegistered ?? false,
            ),
          ],
          if (result.faceMatchScore != null) ...[
            _divider(),
            _ScoreBarTile(
              icon: Icons.people_alt_outlined,
              label: 'Face Match Score',
              status: '${(result.faceMatchScore! * 100).toStringAsFixed(1)}% similarity',
              realScore: result.faceMatchScore!,
              accent: _success,
            ),
          ],
          if (result.sessionId != null) ...[
            _divider(),
            _StatTile(
              icon: Icons.fingerprint_rounded,
              label: 'Session ID',
              value: result.sessionId!,
              accent: _cyan,
            ),
          ],
          if (result.sessionDurationMs != null) ...[
            _divider(),
            _StatTile(
              icon: Icons.timer_outlined,
              label: 'Duration',
              value: '${(result.sessionDurationMs! / 1000).toStringAsFixed(1)}s',
              accent: _purple,
            ),
          ],
        ],
      ),
    );
  }

  Widget _divider() => const Divider(
      color: Color(0xFFE2E8F0), height: 1, indent: 20, endIndent: 20);
}

class _FaceIdMatchCard extends StatelessWidget {
  const _FaceIdMatchCard({
    required this.faceId,
    required this.isNew,
    this.alreadyRegistered = false,
  });
  final String faceId;
  final bool   isNew;
  final bool   alreadyRegistered;

  @override
  Widget build(BuildContext context) {
    final Color accent;
    final String label;
    final String sub;
    final IconData icon;
    if (alreadyRegistered) {
      accent = const Color(0xFFF59E0B);
      label  = 'Face Already Registered';
      sub    = 'This face is already enrolled. Please use Verify Face to log in.';
      icon   = Icons.warning_amber_rounded;
    } else if (isNew) {
      accent = _primary;
      label  = 'New Face Registered';
      sub    = 'Your unique Face ID has been created. It persists across sessions.';
      icon   = Icons.person_add_alt_1_rounded;
    } else {
      accent = _success;
      label  = 'Face Recognised — Welcome Back!';
      sub    = 'This face was matched to an existing ID stored on this device.';
      icon   = Icons.how_to_reg_rounded;
    }

    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: faceId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Face ID copied: $faceId'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: accent,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: accent.withValues(alpha:0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.withValues(alpha:0.25)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha:0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: accent, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            color: accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          sub,
                          style: TextStyle(
                            color: accent.withValues(alpha:0.75),
                            fontSize: 10,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Face ID row
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.fingerprint_rounded, color: accent, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Face ID  (tap to copy)',
                          style: TextStyle(color: _textSecondary, fontSize: 10)),
                      const SizedBox(height: 2),
                      Text(
                        faceId,
                        style: const TextStyle(
                          color: _textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.copy_rounded, color: _textSecondary.withValues(alpha:0.5), size: 13),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
              color: accent.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: accent, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: _textSecondary, fontSize: 11)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
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
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
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
      onTapUp: (_) {
        _tap.reverse();
        widget.onTap();
      },
      onTapCancel: () => _tap.reverse(),
      child: AnimatedBuilder(
        animation: _tap,
        builder: (_, child) =>
            Transform.scale(scale: 1.0 - _tap.value * 0.025, child: child),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: widget.accentColor.withValues(alpha:0.18)),
            boxShadow: [
              BoxShadow(
                color: widget.accentColor.withValues(alpha:0.10),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha:0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: widget.accentColor.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                      color: widget.accentColor.withValues(alpha:0.2)),
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
                            color: _textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(widget.subtitle,
                        style: const TextStyle(
                            color: _textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                  color: _textSecondary.withValues(alpha:0.4), size: 13),
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
              color: shadowColor.withValues(alpha:0.3),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _ScoreBarTile extends StatelessWidget {
  const _ScoreBarTile({
    required this.icon,
    required this.label,
    required this.status,
    required this.realScore,
    required this.accent,
  });
  final IconData icon;
  final String label;
  final String status;
  final double realScore;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final real = realScore.clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: accent, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(color: _textSecondary, fontSize: 11)),
                const SizedBox(height: 2),
                Text(status,
                    style: TextStyle(
                        color: accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text('${(real * 100).toStringAsFixed(1)}% real',
                    style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Painters
// ─────────────────────────────────────────────

class _LightBackground extends StatelessWidget {
  const _LightBackground();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomPaint(painter: _LightBgPainter()),
    );
  }
}

class _LightBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Base fill
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = _bg,
    );

    // Soft top gradient blot
    canvas.drawCircle(
      Offset(size.width / 2, -40),
      size.width * 0.75,
      Paint()
        ..color = _primary.withValues(alpha:0.07)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60),
    );

    // Bottom accent
    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.85),
      size.width * 0.45,
      Paint()
        ..color = _cyan.withValues(alpha:0.05)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50),
    );

    // Subtle dot grid
    final dot = Paint()..color = _primary.withValues(alpha:0.055);
    for (double x = 0; x < size.width; x += 32) {
      for (double y = 0; y < size.height; y += 32) {
        canvas.drawCircle(Offset(x, y), 1.2, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_LightBgPainter _) => false;
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
      child:
          CustomPaint(painter: _FaceHeroPainter(scan: scan, pulse: pulse)),
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

    // Outer soft glow (light-friendly — lower opacity)
    canvas.drawCircle(
      Offset(cx, cy),
      r + 10 + pulse * 10,
      Paint()
        ..color = _primary.withValues(alpha:0.1 + pulse * 0.05)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );

    // White circle background with shadow
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = Colors.white
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = Colors.white);

    // Circle border
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = _primary.withValues(alpha:0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Corner arc brackets
    final bracketRect =
        Rect.fromCircle(center: Offset(cx, cy), radius: r - 6);
    const arcSpan = math.pi / 6;
    final arcPaint = Paint()
      ..color = _primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(bracketRect, math.pi,          arcSpan, false, arcPaint);
    canvas.drawArc(bracketRect, math.pi * 5 / 3,  arcSpan, false, arcPaint);
    canvas.drawArc(bracketRect, 0,                 arcSpan, false, arcPaint);
    canvas.drawArc(bracketRect, math.pi * 2 / 3,  arcSpan, false, arcPaint);

    // Face oval
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, cy - 3), width: r * 0.7, height: r * 0.85),
      Paint()
        ..color = _primary.withValues(alpha:0.07)
        ..style = PaintingStyle.fill,
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, cy - 3), width: r * 0.7, height: r * 0.85),
      Paint()
        ..color = _primary.withValues(alpha:0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Eyes
    final eyeY = cy - 10.0;
    final eyePaint = Paint()..color = _primary.withValues(alpha:0.7);
    canvas.drawCircle(Offset(cx - r * 0.15, eyeY), 4.0, eyePaint);
    canvas.drawCircle(Offset(cx + r * 0.15, eyeY), 4.0, eyePaint);

    // Scan line
    final top = cy - r + 14;
    final bot = cy + r - 14;
    final scanY = top + scan * (bot - top);

    canvas.save();
    canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r - 1)));
    canvas.drawLine(
      Offset(cx - r * 0.65, scanY),
      Offset(cx + r * 0.65, scanY),
      Paint()
        ..color = _primary.withValues(alpha:0.55)
        ..strokeWidth = 1.2,
    );
    canvas.drawRect(
      Rect.fromLTRB(
          cx - r * 0.65, scanY - 10, cx + r * 0.65, scanY + 10),
      Paint()
        ..color = _primary.withValues(alpha:0.06)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FaceHeroPainter old) =>
      old.scan != scan || old.pulse != pulse;
}

// ─────────────────────────────────────────────
// Face ID History Card  (home screen)
// ─────────────────────────────────────────────

class _FaceIdHistoryCard extends StatelessWidget {
  const _FaceIdHistoryCard({required this.faceIds, required this.onClear});
  final List<String> faceIds;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _success.withValues(alpha:0.2)),
        boxShadow: [
          BoxShadow(
            color: _success.withValues(alpha:0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _success.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.face_rounded, color: _success, size: 16),
              ),
              const SizedBox(width: 10),
              Text(
                'Registered Faces (${faceIds.length})',
                style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onClear,
                child: Text(
                  'Clear all',
                  style: TextStyle(
                    color: _error.withValues(alpha:0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...faceIds.map((id) => _FaceIdRow(faceId: id)),
        ],
      ),
    );
  }
}

class _FaceIdRow extends StatelessWidget {
  const _FaceIdRow({required this.faceId});
  final String faceId;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: faceId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copied: $faceId'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: _success,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            const Icon(Icons.fingerprint_rounded, color: _success, size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                faceId,
                style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(Icons.copy_rounded, color: _textSecondary, size: 13),
          ],
        ),
      ),
    );
  }
}

PageRouteBuilder _fade(Widget page) => PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
      transitionDuration: const Duration(milliseconds: 380),
    );
