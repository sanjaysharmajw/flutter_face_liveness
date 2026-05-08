/// Flutter Face Liveness — real-time face detection and liveness verification
/// using Google ML Kit.
///
/// ## Quick start
/// ```dart
/// import 'package:flutter_face_liveness/flutter_face_liveness.dart';
///
/// FlutterFaceLiveness(
///   actions: [
///     LivenessAction.blink,
///     LivenessAction.turnLeft,
///     LivenessAction.turnRight,
///   ],
///   onSuccess: (result) {
///     print('Verified with confidence ${result.confidenceScore}');
///   },
///   onFailed: (reason) {
///     print('Failed: $reason');
///   },
/// )
/// ```
library flutter_face_liveness;

export 'src/flutter_face_liveness_widget.dart';
export 'src/liveness_controller.dart';
export 'src/models/liveness_action.dart';
export 'src/models/liveness_result.dart';
export 'src/models/face_data.dart';
export 'src/models/detection_status.dart';
