import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'liveness_controller.dart';
import 'models/liveness_action.dart';
import 'models/liveness_result.dart';
import 'models/liveness_config.dart';
import 'models/detection_status.dart';
import 'models/face_detector_backend.dart';
import 'ui/face_overlay_painter.dart';
import 'ui/liveness_instructions_widget.dart';
import 'ui/status_indicator_widget.dart';
import 'ui/liveness_step_indicator.dart';

/// Top-level widget for face liveness verification.
///
/// ```dart
/// FlutterFaceLiveness(
///   actions: [LivenessAction.blink, LivenessAction.turnLeft],
///   config: LivenessConfig(randomizeActions: true, enableAntiSpoof: true),
///   onSuccess: (result) => print('verified: ${result.confidenceScore}'),
///   onFailed:  (reason) => print('failed: $reason'),
/// )
/// ```
class FlutterFaceLiveness extends StatefulWidget {
  const FlutterFaceLiveness({
    super.key,
    required this.actions,
    required this.onSuccess,
    required this.onFailed,
    this.config = const LivenessConfig(),
    // Deprecated — use config.showDebugOverlay
    this.showDebugInfo = false,
  });

  final List<LivenessAction> actions;
  final void Function(LivenessResult result) onSuccess;
  final void Function(String reason)          onFailed;
  final LivenessConfig config;

  @Deprecated('Use LivenessConfig.showDebugOverlay')
  final bool showDebugInfo;

  @override
  State<FlutterFaceLiveness> createState() => _FlutterFaceLivenessState();
}

class _FlutterFaceLivenessState extends State<FlutterFaceLiveness>
    with SingleTickerProviderStateMixin {
  late LivenessController _controller;
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

    _controller = LivenessController(
      actions:   widget.actions,
      config:    widget.config,
      onSuccess: widget.onSuccess,
      onFailed:  widget.onFailed,
    );
    _controller.initialize();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _controller.dispose();
    super.dispose();
  }

  bool get _isDark => widget.config.isDark;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LivenessController>.value(
      value: _controller,
      child: Consumer<LivenessController>(
        builder: (_, ctrl, __) => Scaffold(
          backgroundColor: _isDark ? Colors.black : Colors.white,
          body: _buildBody(ctrl),
        ),
      ),
    );
  }

  Widget _buildBody(LivenessController ctrl) {
    if (ctrl.error != null) return _errorView(ctrl.error!);
    if (!ctrl.isInitialized) return _loadingView();
    return _cameraView(ctrl);
  }

  // ── Loading ─────────────────────────────────────────────────────────────

  Widget _loadingView() {
    return Consumer<LivenessController>(
      builder: (_, ctrl, __) {
        // All models (TFLite anti-spoof/video-replay, FaceNet, and the
        // selected identity-pipeline backend — YOLOv8n-face or SCRFD-2.5G-KPS)
        // download sequentially in LivenessController.initialize(), entirely
        // before the camera opens — this view is shown for the whole
        // duration, so every one of them needs its own progress label here,
        // not just TFLite/FaceNet. Only one is ever active at a time.
        final entries = <(double? progress, String label)>[
          (ctrl.tfliteModelDownloadProgress, 'Downloading Anti-Spoof model…'),
          (ctrl.faceIdModelDownloadProgress, 'Downloading Face ID model…'),
          (ctrl.yoloModelDownloadProgress,   'Downloading YOLOv8n-face model…'),
          (ctrl.scrfdModelDownloadProgress,  'Downloading SCRFD-2.5G-KPS model…'),
        ];
        (double? progress, String label)? active;
        for (final e in entries) {
          if (e.$1 != null) { active = e; break; }
        }
        final dlProgress = active?.$1;
        final label = active?.$2;
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  value: dlProgress,
                  color: const Color(0xFF4F6BF4),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                dlProgress != null
                    ? '$label ${(dlProgress * 100).toInt()}%'
                    : 'Starting camera…',
                style: TextStyle(
                  color: _isDark ? Colors.white54 : Colors.black45,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (dlProgress != null) ...[
                const SizedBox(height: 10),
                Text(
                  'One-time download — cached for future sessions',
                  style: TextStyle(
                    color: _isDark ? Colors.white30 : Colors.black26,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── Error ───────────────────────────────────────────────────────────────

  Widget _errorView(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
              ),
              child: const Icon(Icons.error_outline_rounded,
                  color: Color(0xFFEF4444), size: 40),
            ),
            const SizedBox(height: 20),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _isDark ? Colors.white70 : Colors.black54,
                    fontSize: 14,
                    height: 1.5)),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: () => _controller.initialize(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4F6BF4), Color(0xFF7C3AED)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text('Retry',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Camera view ─────────────────────────────────────────────────────────

  Widget _cameraView(LivenessController ctrl) {
    return Stack(
      children: [
        // Camera preview
        _cameraPreview(ctrl),

        // Dark/light scrim + animated oval overlay
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => CustomPaint(
              painter: FaceOverlayPainter(
                status: ctrl.status,
                animationValue: _pulseAnim.value,
                isDark: _isDark,
                faceData: ctrl.currentFace,
                previewSize: ctrl.cameraController != null
                    ? Size(
                        ctrl.cameraController!.value.previewSize!.height,
                        ctrl.cameraController!.value.previewSize!.width,
                      )
                    : null,
                isFrontCamera: true,
              ),
            ),
          ),
        ),

        // Status pill (top center)
        Positioned(
          top: MediaQuery.of(context).padding.top + 14,
          left: 0,
          right: 0,
          child: Center(child: StatusIndicatorWidget(status: ctrl.status)),
        ),

        // Secondary-detector badge (top right) — live proof that
        // faceDetectorBackend: yolov8/scrfd is actually running, since its
        // result never reaches the face overlay above (that always reflects
        // ML Kit, which drives liveness actions regardless of this setting).
        if (ctrl.isSecondaryDetectorActive)
          Positioned(
            top: MediaQuery.of(context).padding.top + 14,
            right: 14,
            child: _SecondaryDetectorBadge(
              backendLabel: widget.config.faceDetectorBackend == FaceDetectorBackend.yolov8
                  ? 'YOLOv8n-face'
                  : 'SCRFD-2.5G-KPS',
              runCount: ctrl.secondaryDetectorRunCount,
              lastDetectionCount: ctrl.lastSecondaryDetectionCount,
              isDark: _isDark,
            ),
          ),

        // Step indicator (below oval)
        Positioned(
          top: MediaQuery.of(context).padding.top + 56,
          left: 0,
          right: 0,
          child: Center(
            child: LivenessStepIndicator(
              actions: [...ctrl.completedActions, ...ctrl.remainingActions],
              completedCount: ctrl.completedCount,
              isDark: _isDark,
            ),
          ),
        ),

        // Instructions panel (bottom)
        Positioned(
          bottom: MediaQuery.of(context).padding.bottom + 24,
          left: 0,
          right: 0,
          child: LivenessInstructionsWidget(
            status: ctrl.status,
            currentAction: ctrl.currentAction,
            progress: ctrl.progress,
            totalActions: ctrl.totalActions,
            completedCount: ctrl.completedCount,
            isDark: _isDark,
          ),
        ),

        // TFLite warning banner
        if (ctrl.tfliteWarning != null)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 130,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ctrl.tfliteWarning!,
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Debug overlay
        if (widget.config.showDebugOverlay || widget.showDebugInfo)
          _debugOverlay(ctrl),

        // Success overlay
        if (ctrl.status == DetectionStatus.completed) _successOverlay(),
      ],
    );
  }

  Widget _cameraPreview(LivenessController ctrl) {
    final camCtrl = ctrl.cameraController!;
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: camCtrl.value.previewSize!.height,
          height: camCtrl.value.previewSize!.width,
          child: CameraPreview(camCtrl),
        ),
      ),
    );
  }

  Widget _successOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              const Color(0xFF10B981).withValues(alpha:0.18),
              Colors.transparent,
            ],
          ),
        ),
        child: const Center(
          child: Icon(Icons.verified_rounded,
              color: Color(0xFF10B981), size: 90),
        ),
      ),
    );
  }

  Widget _debugOverlay(LivenessController ctrl) {
    final face    = ctrl.currentFace;
    final quality = ctrl.lastQuality;
    final vr      = ctrl.liveHeuristicScore;
    final lap     = ctrl.liveLaplacianScore;
    final het     = ctrl.liveHetScore;
    final tf      = ctrl.lastTfliteScore;
    final ra      = ctrl.liveReplayScore;
    final scr     = ctrl.liveScreenScore;
    final flow    = ctrl.liveFlowScore;
    final geo     = ctrl.liveGeoScore;

    final vrLine = vr != null
        ? 'VR-B:  ${(vr * 100).toStringAsFixed(1)}%${vr < 0.5 ? " ⚠" : " ok"}\n'
        : '';
    final lapLine = lap != null
        ? 'LAP:   ${lap.toStringAsFixed(0)}${lap < 200 ? " ⚠LOW" : " ok"}\n'
        : '';
    final hetLine = het != null
        ? 'HET:   ${het.toStringAsFixed(4)}${het < 0.01 ? " ⚠SCREEN" : " ok"}\n'
        : '';
    final tfLine = tf != null
        ? 'TF:    ${(tf * 100).toStringAsFixed(1)}% real\n'
        : '';
    final raLine = ra != null
        ? 'RA:    ${(ra * 100).toStringAsFixed(1)}%${ra < 0.5 ? " ⚠" : " ok"}\n'
        : '';
    final scrLine = scr != null
        ? 'SCR:   ${(scr * 100).toStringAsFixed(1)}%${scr < 0.5 ? " ⚠SCREEN" : " ok"}\n'
        : '';
    final flowLine = flow != null
        ? 'FLOW:  ${(flow * 100).toStringAsFixed(1)}%${flow < 0.4 ? " ⚠STATIC" : " ok"}\n'
        : '';
    final geoLine = geo != null
        ? 'GEO:   ${(geo * 100).toStringAsFixed(1)}%${geo < 0.4 ? " ⚠FLAT" : " ok"}\n'
        : '';

    final faceLines = face == null ? 'No face\n' :
        'Yaw:   ${face.headEulerAngleY.toStringAsFixed(1)}°\n'
        'Pitch: ${face.headEulerAngleX.toStringAsFixed(1)}°\n'
        'L-Eye: ${face.leftEyeOpenProbability.toStringAsFixed(2)}\n'
        'R-Eye: ${face.rightEyeOpenProbability.toStringAsFixed(2)}\n'
        'Smile: ${face.smilingProbability.toStringAsFixed(2)}\n'
        'Area:  ${(face.faceAreaRatio * 100).toStringAsFixed(1)}%\n';

    final qualityLine = 'Light: ${quality?.brightness.toStringAsFixed(2) ?? '--'}\n'
        'Blur:  ${quality?.blurScore.toStringAsFixed(0) ?? '--'}';

    return Positioned(
      top: MediaQuery.of(context).padding.top + 100,
      left: 12,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha:0.65),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$vrLine$lapLine$hetLine$tfLine$raLine$scrLine$flowLine$geoLine$faceLines$qualityLine',
          style: const TextStyle(
              color: Colors.white, fontSize: 10, fontFamily: 'monospace'),
        ),
      ),
    );
  }
}

/// Small always-visible pill confirming the selected secondary detector
/// (YOLOv8n-face / SCRFD-2.5G-KPS) is actually executing — shown only when
/// [LivenessController.isSecondaryDetectorActive] is true, i.e.
/// `enableFaceId: true` and `faceDetectorBackend` is not `.mlkit`.
///
/// Necessary because that backend's output never reaches the face-tracking
/// oval overlay (which always reflects ML Kit — the detector that drives
/// liveness actions regardless of this setting) — without this, there is no
/// visible way to confirm the alternate backend ran at all.
class _SecondaryDetectorBadge extends StatelessWidget {
  const _SecondaryDetectorBadge({
    required this.backendLabel,
    required this.runCount,
    required this.lastDetectionCount,
    required this.isDark,
  });

  final String backendLabel;
  final int runCount;
  final int? lastDetectionCount;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final Color dotColor;
    final String statusText;
    if (runCount == 0) {
      dotColor = Colors.amber;
      statusText = 'starting…';
    } else if ((lastDetectionCount ?? 0) > 0) {
      dotColor = const Color(0xFF10B981);
      statusText = 'face detected';
    } else {
      dotColor = Colors.amber;
      statusText = 'no face yet';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$backendLabel · $statusText'
            '${runCount > 0 ? ' (${runCount}x)' : ''}',
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
