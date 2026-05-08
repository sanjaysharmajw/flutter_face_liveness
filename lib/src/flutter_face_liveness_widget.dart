import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'liveness_controller.dart';
import 'models/liveness_action.dart';
import 'models/liveness_result.dart';
import 'models/detection_status.dart';
import 'ui/face_overlay_painter.dart';
import 'ui/liveness_instructions_widget.dart';
import 'ui/status_indicator_widget.dart';

/// The main widget that presents the full liveness verification UI.
///
/// Usage:
/// ```dart
/// FlutterFaceLiveness(
///   actions: [LivenessAction.blink, LivenessAction.turnLeft],
///   onSuccess: (result) => print('verified: $result'),
///   onFailed: (reason) => print('failed: $reason'),
/// )
/// ```
class FlutterFaceLiveness extends StatefulWidget {
  const FlutterFaceLiveness({
    super.key,
    required this.actions,
    required this.onSuccess,
    required this.onFailed,
    this.sessionTimeoutMs = 60000,
    this.cameraResolution = ResolutionPreset.high,
    this.overlayColor,
    this.backgroundColor,
    this.showDebugInfo = false,
  });

  final List<LivenessAction> actions;
  final void Function(LivenessResult result) onSuccess;
  final void Function(String reason) onFailed;
  final int sessionTimeoutMs;
  final ResolutionPreset cameraResolution;
  final Color? overlayColor;
  final Color? backgroundColor;
  final bool showDebugInfo;

  @override
  State<FlutterFaceLiveness> createState() => _FlutterFaceLivenessState();
}

class _FlutterFaceLivenessState extends State<FlutterFaceLiveness>
    with SingleTickerProviderStateMixin {
  late LivenessController _controller;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _pulseAnimation = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);

    _controller = LivenessController(
      actions: widget.actions,
      onSuccess: widget.onSuccess,
      onFailed: widget.onFailed,
      sessionTimeoutMs: widget.sessionTimeoutMs,
      cameraResolution: widget.cameraResolution,
    );

    _controller.initialize();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LivenessController>.value(
      value: _controller,
      child: Consumer<LivenessController>(
        builder: (context, ctrl, _) {
          return Scaffold(
            backgroundColor: widget.backgroundColor ?? Colors.black,
            body: _buildBody(ctrl),
          );
        },
      ),
    );
  }

  Widget _buildBody(LivenessController ctrl) {
    if (ctrl.error != null) {
      return _buildErrorView(ctrl.error!);
    }
    if (!ctrl.isInitialized) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                color: Color(0xFF4F6BF4),
                strokeWidth: 2.5,
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Starting camera…',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // Camera preview layer
        _buildCameraPreview(ctrl),

        // Overlay layer
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (_, __) => CustomPaint(
              painter: FaceOverlayPainter(
                status: ctrl.status,
                animationValue: _pulseAnimation.value,
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

        // Status badge (top center)
        Positioned(
          top: MediaQuery.of(context).padding.top + 16,
          left: 0,
          right: 0,
          child: Center(child: StatusIndicatorWidget(status: ctrl.status)),
        ),

        // Instructions (bottom)
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
          ),
        ),

        // Debug overlay
        if (widget.showDebugInfo) _buildDebugOverlay(ctrl),

        // Success overlay
        if (ctrl.status == DetectionStatus.completed) _buildSuccessOverlay(),
      ],
    );
  }

  Widget _buildCameraPreview(LivenessController ctrl) {
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

  Widget _buildErrorView(String message) {
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
                color: const Color(0xFFEF4444).withOpacity(0.1),
                border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.4)),
              ),
              child: const Icon(Icons.error_outline_rounded,
                  color: Color(0xFFEF4444), size: 40),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: () => _controller.initialize(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
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

  Widget _buildSuccessOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              const Color(0xFF10B981).withOpacity(0.18),
              Colors.transparent,
            ],
          ),
        ),
        child: const Center(
          child: Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 88),
        ),
      ),
    );
  }

  Widget _buildDebugOverlay(LivenessController ctrl) {
    final face = ctrl.currentFace;
    if (face == null) return const SizedBox.shrink();

    return Positioned(
      top: 100,
      left: 12,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Yaw: ${face.headEulerAngleY.toStringAsFixed(1)}°\n'
          'Pitch: ${face.headEulerAngleX.toStringAsFixed(1)}°\n'
          'L-Eye: ${face.leftEyeOpenProbability.toStringAsFixed(2)}\n'
          'R-Eye: ${face.rightEyeOpenProbability.toStringAsFixed(2)}\n'
          'Smile: ${face.smilingProbability.toStringAsFixed(2)}\n'
          'Area: ${(face.faceAreaRatio * 100).toStringAsFixed(1)}%',
          style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
        ),
      ),
    );
  }
}
