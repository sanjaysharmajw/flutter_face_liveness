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
    this.brightnessMin = 0.12,
    this.brightnessMax = 0.92,
    this.blurThreshold = 80.0,

    // ── TFLite (optional) ────────────────────────────────────────────────
    this.enableTFLite = false,
    this.tfliteModelPath,
    this.tfliteModelUrl,
    this.tfliteInputSize,
    this.tfliteDeepfakeThreshold = 0.40,

    // ── Video Replay Detection (optional) ───────────────────────────────
    this.enableVideoReplayDetection = false,
    this.videoReplayModelPath,
    this.videoReplayModelUrl,
    this.videoReplayInputSize,
    this.videoReplayThreshold = 0.50,

    // ── Face geometry ────────────────────────────────────────────────────
    this.faceTooFarRatio = 0.015,
    this.faceTooCloseRatio = 0.70,

    // ── Security ─────────────────────────────────────────────────────────
    this.enableDuplicateFrameDetection = true,
    this.duplicateFrameWindowSize = 8,

    // ── Face Identity ────────────────────────────────────────────────────
    this.enableFaceId = false,
    this.faceIdSimilarityThreshold = 0.65,

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

  /// Flutter asset key (e.g. `'assets/anti_spoof.tflite'`) or absolute
  /// filesystem path for the .tflite model.
  ///
  /// When null and [tfliteModelUrl] is set, the model is auto-downloaded on
  /// first use and cached permanently — no manual file management needed.
  final String? tfliteModelPath;

  /// HTTPS URL to auto-download the TFLite model from on first use.
  ///
  /// When null the package automatically uses its bundled anti-spoof model URL —
  /// simply set [enableTFLite] to true and the model is downloaded and cached
  /// with no extra configuration. Set this only when using a custom model.
  ///
  /// Ignored when [tfliteModelPath] is already set. The downloaded file is
  /// cached permanently in the app documents directory; subsequent sessions
  /// load from cache instantly with no network activity.
  final String? tfliteModelUrl;

  /// Input image size expected by the TFLite model (square).
  /// When null the package uses the bundled model's required size (256).
  final int? tfliteInputSize;

  /// TFLite real-score below this threshold flags [LivenessResult.deepfakeDetected].
  /// Range 0.0–1.0. Default 0.40 — scores under 40% real confidence = deepfake/spoof.
  final double tfliteDeepfakeThreshold;

  // ── Video Replay Detection ────────────────────────────────────────────────
  /// Enable MiniFASNet-based video-replay attack detection (second TFLite model).
  final bool enableVideoReplayDetection;

  /// Local asset path or absolute filesystem path for the video-replay model.
  final String? videoReplayModelPath;

  /// HTTPS URL to auto-download the MiniFASNet video-replay model from.
  /// When null, the bundled MiniFASNetV2 model URL is used.
  final String? videoReplayModelUrl;

  /// Input size for the video-replay model (square). Default: 80 (MiniFASNet).
  final int? videoReplayInputSize;

  /// Real-score below this threshold flags [LivenessResult.videoReplayDetected].
  /// Default 0.50 — scores under 50% = video replay attack.
  final double videoReplayThreshold;

  // ── Face geometry ─────────────────────────────────────────────────────────
  final double faceTooFarRatio;
  final double faceTooCloseRatio;

  // ── Security ──────────────────────────────────────────────────────────────
  /// Hash consecutive frames and reject static-image replay attacks.
  final bool enableDuplicateFrameDetection;

  /// Number of recent frame hashes kept for duplicate comparison.
  final int duplicateFrameWindowSize;

  // ── Face Identity ─────────────────────────────────────────────────────────
  /// Enable MobileFaceNet-based persistent face identity.
  ///
  /// When `true`, [LivenessResult.faceId] is populated after each successful
  /// verification. The same physical person always receives the same ID,
  /// even across separate app sessions.
  ///
  /// Requires the bundled model: run `scripts/download_face_model.sh` once
  /// after adding the package to download the MobileFaceNet weights.
  final bool enableFaceId;

  /// Cosine-similarity threshold (0.0–1.0) for matching an existing face.
  /// Raise for stricter identity matching; lower to tolerate more variation.
  final double faceIdSimilarityThreshold;

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
    String? tfliteModelUrl,
    int? tfliteInputSize,
    double? tfliteDeepfakeThreshold,
    bool? enableVideoReplayDetection,
    String? videoReplayModelPath,
    String? videoReplayModelUrl,
    int? videoReplayInputSize,
    double? videoReplayThreshold,
    double? faceTooFarRatio,
    double? faceTooCloseRatio,
    bool? enableDuplicateFrameDetection,
    int? duplicateFrameWindowSize,
    bool? enableFaceId,
    double? faceIdSimilarityThreshold,
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
      tfliteModelUrl: tfliteModelUrl ?? this.tfliteModelUrl,
      tfliteInputSize: tfliteInputSize ?? this.tfliteInputSize,
      tfliteDeepfakeThreshold: tfliteDeepfakeThreshold ?? this.tfliteDeepfakeThreshold,
      enableVideoReplayDetection: enableVideoReplayDetection ?? this.enableVideoReplayDetection,
      videoReplayModelPath: videoReplayModelPath ?? this.videoReplayModelPath,
      videoReplayModelUrl: videoReplayModelUrl ?? this.videoReplayModelUrl,
      videoReplayInputSize: videoReplayInputSize ?? this.videoReplayInputSize,
      videoReplayThreshold: videoReplayThreshold ?? this.videoReplayThreshold,
      faceTooFarRatio: faceTooFarRatio ?? this.faceTooFarRatio,
      faceTooCloseRatio: faceTooCloseRatio ?? this.faceTooCloseRatio,
      enableDuplicateFrameDetection:
          enableDuplicateFrameDetection ?? this.enableDuplicateFrameDetection,
      duplicateFrameWindowSize:
          duplicateFrameWindowSize ?? this.duplicateFrameWindowSize,
      enableFaceId: enableFaceId ?? this.enableFaceId,
      faceIdSimilarityThreshold: faceIdSimilarityThreshold ?? this.faceIdSimilarityThreshold,
      themeMode: themeMode ?? this.themeMode,
      showDebugOverlay: showDebugOverlay ?? this.showDebugOverlay,
    );
  }
}
