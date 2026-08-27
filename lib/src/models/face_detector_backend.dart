/// Selects which model powers face *detection* for the identity/recognition
/// pipeline (embedding + matching always run through [FaceEmbeddingModel]
/// regardless of this choice).
///
/// Liveness actions (blink, smile, head pose) always use Google ML Kit
/// because only ML Kit exposes eye-open/smiling classification — this enum
/// only affects which detector supplies the face box + eye positions that
/// get cropped and fed to the embedding model.
enum FaceDetectorBackend {
  /// Google ML Kit face detector (default). Already running every frame for
  /// liveness actions, so selecting this backend for identity adds no extra
  /// per-frame cost — its own landmarks are reused.
  mlkit,

  /// YOLOv8n-face (TFLite, downloaded on first use). Runs as a second model
  /// alongside ML Kit specifically for identity-eligible frames — more
  /// accurate face boxes/keypoints in some conditions, at the cost of extra
  /// inference time per frame.
  yolov8,

  /// SCRFD-2.5G-KPS (TFLite, downloaded on first use). Runs as a second model
  /// alongside ML Kit specifically for identity-eligible frames — an
  /// anchor-based detector (InsightFace) generally more accurate than
  /// YOLOv8n-face at small/angled faces, at a similar extra inference cost
  /// per frame.
  scrfd,
}
