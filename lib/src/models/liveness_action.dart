/// All supported liveness challenge actions.
enum LivenessAction {
  blink,
  turnLeft,
  turnRight,
  lookUp,
  lookDown,
  smile,
  openMouth,
}

extension LivenessActionX on LivenessAction {
  String get instruction {
    switch (this) {
      case LivenessAction.blink:     return 'Blink your eyes';
      case LivenessAction.turnLeft:  return 'Slowly turn your head left';
      case LivenessAction.turnRight: return 'Slowly turn your head right';
      case LivenessAction.lookUp:    return 'Look up';
      case LivenessAction.lookDown:  return 'Look down';
      case LivenessAction.smile:     return 'Smile naturally';
      case LivenessAction.openMouth: return 'Open your mouth';
    }
  }

  String get shortLabel {
    switch (this) {
      case LivenessAction.blink:     return 'Blink';
      case LivenessAction.turnLeft:  return 'Turn left';
      case LivenessAction.turnRight: return 'Turn right';
      case LivenessAction.lookUp:    return 'Look up';
      case LivenessAction.lookDown:  return 'Look down';
      case LivenessAction.smile:     return 'Smile';
      case LivenessAction.openMouth: return 'Open mouth';
    }
  }

  String get iconEmoji {
    switch (this) {
      case LivenessAction.blink:     return '👁️';
      case LivenessAction.turnLeft:  return '⬅️';
      case LivenessAction.turnRight: return '➡️';
      case LivenessAction.lookUp:    return '⬆️';
      case LivenessAction.lookDown:  return '⬇️';
      case LivenessAction.smile:     return '😊';
      case LivenessAction.openMouth: return '😮';
    }
  }

  /// Icon for use in non-emoji UI contexts.
  String get iconCode {
    switch (this) {
      case LivenessAction.blink:     return 'eye';
      case LivenessAction.turnLeft:  return 'arrow_left';
      case LivenessAction.turnRight: return 'arrow_right';
      case LivenessAction.lookUp:    return 'arrow_up';
      case LivenessAction.lookDown:  return 'arrow_down';
      case LivenessAction.smile:     return 'smile';
      case LivenessAction.openMouth: return 'mouth';
    }
  }
}
