## 1.0.0

* Initial release
* Real-time face detection via Google ML Kit Face Detection
* Liveness actions: blink, turnLeft, turnRight, lookUp, lookDown, smile
* Anti-spoofing heuristic validator (5-signal composite score)
* Animated face overlay with status indicator and progress bar
* Clean architecture: Camera → ML → Liveness engine → UI layers
* Full null-safety support (Dart 3 / Flutter 3.10+)
* Android API 21+ and iOS 13+ support
* Example app with standard and custom challenge modes
