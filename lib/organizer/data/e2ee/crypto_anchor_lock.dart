import 'dart:async';

/// Shared across repositories and sessions. Critical sections contain only
/// local anchor/cache I/O; recursive network verification happens beforehand.
final _anchorQueues = <String, Future<void>>{};
final _anchorZone = Object();

class _AnchorLease {
  bool active = true;
}

Future<T> withCryptoAnchorLock<T>(
  String partition,
  Future<T> Function() body,
) async {
  final held =
      Zone.current[_anchorZone] as Map<String, _AnchorLease>? ?? const {};
  if (held[partition]?.active == true) return body();
  final previous = _anchorQueues[partition] ?? Future<void>.value();
  final task = previous.then((_) async {
    final lease = _AnchorLease();
    try {
      return await runZoned(
        body,
        zoneValues: {
          _anchorZone: {...held, partition: lease},
        },
      );
    } finally {
      lease.active = false;
    }
  });
  final marker = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
  _anchorQueues[partition] = marker;
  try {
    return await task;
  } finally {
    if (identical(_anchorQueues[partition], marker))
      _anchorQueues.remove(partition);
  }
}
