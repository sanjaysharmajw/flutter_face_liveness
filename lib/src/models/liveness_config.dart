import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Full configuration for the liveness verification session.
///
/// Pass to [FlutterFaceLiveness] or [LivenessController] to customise
/// detection thresholds, enabled features, UI appearance, and timeouts.
class LivenessConfig {
  const LivenessConfig({
    // ── Session ─────────────────────────────────────────────────────────
    this.sessionTimeoutMs = 60000,
    this.randomizeActions = true,

    // ── Camera ───────────────────────────────────────────────────────────
    this.cameraResolution = ResolutionPreset.high,
    this.targetFps = 20,

    // ── Anti-spoof ───────────────────────────────────────────────────────
    this.enableAntiSpoof = true,
    this.antiSpoofThreshold = 0.45,

    // ── Frame quality ────────────────────────────────────────────────────
    this.enableBrightnessCheck = true,
    this.enableBlurDetection = true,
    this.brightnessMin = 0.20,
    this.brightnessMax = 0.90,
    this.blurThreshold = 80.0,

    // ── TFLite (optional) ────────────────────────────────────────────────
    this.enableTFLite = false,
    this.tfliteModelPath,
    this.tfliteInputSize = 128,

    // ── Face geometry ────────────────────────────────────────────────────
    this.faceTooFarRatio = 0.015,
    this.faceTooCloseRatio = 0.70,

    // ── Security ─────────────────────────────────────────────────────────
    this.enableDuplicateFrameDetection = true,
    this.duplicateFrameWindowSize = 8,

    // ── UI ───────────────────────────────────────────────────────────────
    this.themeMode = ThemeMode.dark,
    this.showDebugOverlay = false,
  });

  // ── Session ──────────────────────────────────────────────────────────────
  /// Maximum session duration in milliseconds before automatic failure.
  final int sessionTimeoutMs;

  /// Shuffle the action sequence each session to prevent replay attacks.
  final bool randomizeActions;

  // ── Camera ───────────────────────────────────────────────────────────────
  final ResolutionPreset cameraResolution;

  /// Target frame processing rate (1–30). Higher = more responsive but more CPU.
  final int targetFps;

  // ── Anti-spoof ───────────────────────────────────────────────────────────
  /// Enable heuristic + ML-based anti-spoof validation.
  final bool enableAntiSpoof;

  /// Minimum composite confidence score (0.0–1.0) to accept a real face.
  final double antiSpoofThreshold;

  // ── Frame quality ─────────────────────────────────────────────────────────
  final bool enableBrightnessCheck;
  final bool enableBlurDetection;

  /// Normalised luminance below this triggers [DetectionStatus.lowLight].
  final double brightnessMin;

  /// Normalised luminance above this triggers [DetectionStatus.overExposed].
  final double brightnessMax;

  /// Y-plane variance below this triggers [DetectionStatus.blurry].
  final double blurThreshold;

  // ── TFLite ────────────────────────────────────────────────────────────────
  /// Enable TensorFlow Lite model for advanced anti-spoof inference.
  final bool enableTFLite;

  /// Absolute path to a .tflite model file on the device.
  /// Required when [enableTFLite] is true.
  final String? tfliteModelPath;

  /// Input image size expected by the TFLite model (square).
  final int tfliteInputSize;

  // ── Face geometry ─────────────────────────────────────────────────────────
  final double faceTooFarRatio;
  final double faceTooCloseRatio;

  // ── Security ──────────────────────────────────────────────────────────────
  /// Hash consecutive frames and reject static-image replay attacks.
  final bool enableDuplicateFrameDetection;

  /// Number of recent frame hashes kept for duplicate comparison.
  final int duplicateFrameWindowSize;

  // ── UI ────────────────────────────────────────────────────────────────────
  final ThemeMode themeMode;
  final bool showDebugOverlay;

  // ── Derived helpers ───────────────────────────────────────────────────────
  int get frameThrottleMs => (1000 / targetFps.clamp(1, 60)).round();

  bool get isDark => themeMode == ThemeMode.dark ||
      (themeMode == ThemeMode.system &&
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark);

  LivenessConfig copyWith({
    int? sessionTimeoutMs,
    bool? randomizeActions,
    ResolutionPreset? cameraResolution,
    int? targetFps,
    bool? enableAntiSpoof,
    double? antiSpoofThreshold,
    bool? enableBrightnessCheck,
    bool? enableBlurDetection,
    double? brightnessMin,
    double? brightnessMax,
    double? blurThreshold,
    bool? enableTFLite,
    String? tfliteModelPath,
    int? tfliteInputSize,
    double? faceTooFarRatio,
    double? faceTooCloseRatio,
    bool? enableDuplicateFrameDetection,
    int? duplicateFrameWindowSize,
    ThemeMode? themeMode,
    bool? showDebugOverlay,
  }) {
    return LivenessConfig(
      sessionTimeoutMs: sessionTimeoutMs ?? this.sessionTimeoutMs,
      randomizeActions: randomizeActions ?? this.randomizeActions,
      cameraResolution: cameraResolution ?? this.cameraResolution,
      targetFps: targetFps ?? this.targetFps,
      enableAntiSpoof: enableAntiSpoof ?? this.enableAntiSpoof,
      antiSpoofThreshold: antiSpoofThreshold ?? this.antiSpoofThreshold,
      enableBrightnessCheck: enableBrightnessCheck ?? this.enableBrightnessCheck,
      enableBlurDetection: enableBlurDetection ?? this.enableBlurDetection,
      brightnessMin: brightnessMin ?? this.brightnessMin,
      brightnessMax: brightnessMax ?? this.brightnessMax,
      blurThreshold: blurThreshold ?? this.blurThreshold,
      enableTFLite: enableTFLite ?? this.enableTFLite,
      tfliteModelPath: tfliteModelPath ?? this.tfliteModelPath,
      tfliteInputSize: tfliteInputSize ?? this.tfliteInputSize,
      faceTooFarRatio: faceTooFarRatio ?? this.faceTooFarRatio,
      faceTooCloseRatio: faceTooCloseRatio ?? this.faceTooCloseRatio,
      enableDuplicateFrameDetection:
          enableDuplicateFrameDetection ?? this.enableDuplicateFrameDetection,
      duplicateFrameWindowSize:
          duplicateFrameWindowSize ?? this.duplicateFrameWindowSize,
      themeMode: themeMode ?? this.themeMode,
      showDebugOverlay: showDebugOverlay ?? this.showDebugOverlay,
    );
  }
}
