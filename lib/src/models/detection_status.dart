/// Describes the current face detection state for UI feedback.
enum DetectionStatus {
  initializing,
  noFace,
  multipleFaces,
  faceTooFar,
  faceTooClose,
  fakeDetected,
  lowLight,
  faceNotCentered,
  ready,
  actionInProgress,
  completed,
  failed,
}

extension DetectionStatusExtension on DetectionStatus {
  String get message {
    switch (this) {
      case DetectionStatus.initializing:
        return 'Starting camera...';
      case DetectionStatus.noFace:
        return 'No face detected. Please position your face in the frame.';
      case DetectionStatus.multipleFaces:
        return 'Multiple faces detected. Please ensure only one person is visible.';
      case DetectionStatus.faceTooFar:
        return 'Too far away. Please move closer to the camera.';
      case DetectionStatus.faceTooClose:
        return 'Too close. Please move back a little.';
      case DetectionStatus.fakeDetected:
        return 'Real face required. Please use your actual face.';
      case DetectionStatus.lowLight:
        return 'Low light detected. Please move to a well-lit area.';
      case DetectionStatus.faceNotCentered:
        return 'Center your face in the oval.';
      case DetectionStatus.ready:
        return 'Hold still...';
      case DetectionStatus.actionInProgress:
        return '';
      case DetectionStatus.completed:
        return 'Verification complete!';
      case DetectionStatus.failed:
        return 'Verification failed. Please try again.';
    }
  }

  bool get isError {
    switch (this) {
      case DetectionStatus.noFace:
      case DetectionStatus.multipleFaces:
      case DetectionStatus.faceTooFar:
      case DetectionStatus.faceTooClose:
      case DetectionStatus.fakeDetected:
      case DetectionStatus.lowLight:
      case DetectionStatus.faceNotCentered:
      case DetectionStatus.failed:
        return true;
      default:
        return false;
    }
  }

  bool get isSuccess => this == DetectionStatus.completed;
  bool get isProcessing => this == DetectionStatus.actionInProgress || this == DetectionStatus.ready;
}
