/// Manages per-session metadata for audit trails and replay-attack prevention.
class SessionManager {
  SessionManager() : _sessionId = _generateId();

  String _sessionId;
  final int _createdAtMs = DateTime.now().millisecondsSinceEpoch;
  int _frameCount = 0;
  bool _isActive = true;

  String get sessionId => _sessionId;
  int get frameCount => _frameCount;
  bool get isActive => _isActive;

  int get elapsedMs => DateTime.now().millisecondsSinceEpoch - _createdAtMs;

  bool isTimedOut(int timeoutMs) => elapsedMs > timeoutMs;

  void incrementFrame() {
    if (_isActive) _frameCount++;
  }

  void close() {
    _isActive = false;
  }

  void reset() {
    _sessionId = _generateId();
    _frameCount = 0;
    _isActive = true;
  }

  static String _generateId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = (ts ^ (ts >> 16)) & 0xFFFFFF;
    return 'LV-${ts.toRadixString(16).toUpperCase()}-${rand.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}
