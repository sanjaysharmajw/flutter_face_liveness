/// All possible states the liveness engine can be in.
enum DetectionStatus {
  initializing,
  noFace,
  multipleFaces,
  faceTooFar,
  faceTooClose,
  faceNotCentered,
  lowLight,
  overExposed,
  blurry,
  fakeDetected,
  ready,
  actionInProgress,
  completed,
  failed,
}

extension DetectionStatusX on DetectionStatus {
  String get message {
    switch (this) {
      case DetectionStatus.initializing:    return 'Starting camera…';
      case DetectionStatus.noFace:          return 'No face detected — position your face in the oval.';
      case DetectionStatus.multipleFaces:   return 'Multiple faces detected — ensure only one person is visible.';
      case DetectionStatus.faceTooFar:      return 'Move closer to the camera.';
      case DetectionStatus.faceTooClose:    return 'Move back a little.';
      case DetectionStatus.faceNotCentered: return 'Center your face in the oval.';
      case DetectionStatus.lowLight:        return 'Too dark — move to a well-lit area.';
      case DetectionStatus.overExposed:     return 'Too bright — avoid direct light behind you.';
      case DetectionStatus.blurry:          return 'Camera blurry — hold your device steady.';
      case DetectionStatus.fakeDetected:     return 'Real face required — do not use a photo or screen.';
      case DetectionStatus.ready:            return 'Hold still…';
      case DetectionStatus.actionInProgress:return '';
      case DetectionStatus.completed:       return 'Verification complete!';
      case DetectionStatus.failed:          return 'Verification failed. Please try again.';
    }
  }

  bool get isError {
    switch (this) {
      case DetectionStatus.noFace:
      case DetectionStatus.multipleFaces:
      case DetectionStatus.faceTooFar:
      case DetectionStatus.faceTooClose:
      case DetectionStatus.faceNotCentered:
      case DetectionStatus.lowLight:
      case DetectionStatus.overExposed:
      case DetectionStatus.blurry:
      case DetectionStatus.fakeDetected:
      case DetectionStatus.failed:
        return true;
      default:
        return false;
    }
  }

  bool get isSuccess    => this == DetectionStatus.completed;
  bool get isProcessing => this == DetectionStatus.actionInProgress ||
                           this == DetectionStatus.ready;
  bool get isQualityIssue => this == DetectionStatus.lowLight ||
                              this == DetectionStatus.overExposed ||
                              this == DetectionStatus.blurry;
}
