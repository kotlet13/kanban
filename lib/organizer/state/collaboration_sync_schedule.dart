import '../data/collaboration_sync_status.dart';

/// Chooses when to attempt delivery. It never caches authorization or content.
class CollaborationSyncSchedule {
  String? _identity;
  String? _work;
  int _completion = 0;
  int _failures = 0;
  bool _demand = true;
  int _requests = 1;
  int _attemptRequests = 0;
  DateTime? nextAt;
  DateTime? retryAt;

  void identity(String? value) {
    if (_identity == value) return;
    _identity = value;
    _work = null;
    _completion = 0;
    _failures = 0;
    _demand = true;
    _requests = 1;
    _attemptRequests = 0;
    nextAt = retryAt = null;
  }

  void work(CollaborationSyncWork value) {
    if (_work != null && _work != value.signature && value.signature != '[]') {
      localEdit();
    }
    _work = value.signature;
  }

  /// Initial and stale resumes remain pending while another attempt is busy.
  /// Recent drained focus changes retain the existing deadline without moving it.
  void resume(DateTime now) {
    if (nextAt == null || !now.isBefore(nextAt!)) {
      localEdit();
    }
  }

  void localEdit() {
    _requests++;
    _demand = true;
  }

  void beginAttempt() => _attemptRequests = _requests;

  bool due(DateTime now, {required bool busy}) =>
      _identity != null &&
      !busy &&
      (retryAt == null || !now.isBefore(retryAt!)) &&
      (_demand || nextAt == null || !now.isBefore(nextAt!));

  bool complete(CollaborationSyncCompletion value) {
    if (value.identity != _identity || value.sequence <= _completion) {
      return false;
    }
    _completion = value.sequence;
    _work = value.work.signature;
    _demand = value.work.unresolved && _requests > _attemptRequests;
    if (value.retryAt != null &&
        (retryAt == null || value.retryAt!.isAfter(retryAt!))) {
      retryAt = value.retryAt;
    }
    final drained = value.error == null && !value.work.unresolved;
    _failures = drained ? 0 : _failures + 1;
    final seconds = drained
        ? 60
        : (_failures == 1
              ? 15
              : _failures == 2
              ? 30
              : 60);
    nextAt = value.at.add(Duration(seconds: seconds));
    return true;
  }

  void failed(DateTime now) {
    _demand = false;
    _failures++;
    nextAt = now.add(
      Duration(
        seconds: _failures == 1
            ? 15
            : _failures == 2
            ? 30
            : 60,
      ),
    );
  }
}
