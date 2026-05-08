/// Defines the liveness challenge actions a user must perform.
enum LivenessAction {
  blink,
  turnLeft,
  turnRight,
  lookUp,
  lookDown,
  smile,
}

extension LivenessActionExtension on LivenessAction {
  String get instruction {
    switch (this) {
      case LivenessAction.blink:
        return 'Blink your eyes';
      case LivenessAction.turnLeft:
        return 'Turn your head left';
      case LivenessAction.turnRight:
        return 'Turn your head right';
      case LivenessAction.lookUp:
        return 'Look up';
      case LivenessAction.lookDown:
        return 'Look down';
      case LivenessAction.smile:
        return 'Smile';
    }
  }

  String get iconEmoji {
    switch (this) {
      case LivenessAction.blink:
        return '👁️';
      case LivenessAction.turnLeft:
        return '⬅️';
      case LivenessAction.turnRight:
        return '➡️';
      case LivenessAction.lookUp:
        return '⬆️';
      case LivenessAction.lookDown:
        return '⬇️';
      case LivenessAction.smile:
        return '😊';
    }
  }
}
