import 'dart:async';
import 'package:flutter/services.dart';
import 'account_work_coordinator.dart';
import 'collaboration_sync_diagnostics.dart';
import 'collaboration_sync_status.dart';
import '../domain/collaboration_models.dart';
import 'e2ee/crypto_sync_repository.dart' show CryptoAuthorityPending;

const _channel = MethodChannel('jivie/qa_sync_redesign');
final _site = Object();
int _sequence = 0;
bool _ackSubmitted = false;
final _counts = <String, int>{};
const _limits = {'work':1024,'sync':128,'request':1024,'error':128,'ui':128,'completion':64};

void _emit(String kind, Map<String, Object?> data) {
  try {
    final count = _counts.update(kind, (n) => n+1, ifAbsent: () => 1);
    // The extra attempt lets native persist its reserved categoryLimit marker.
    if (count > (_limits[kind] ?? 0)+1) return;
    final seq = ++_sequence;
    unawaited(_channel.invokeMapMethod<String, dynamic>('reliableEvent',
      {'v':1,'seq':seq,'kind':kind,'data':data}).then((reply) {
      final run = reply?['run'];
      if (!_ackSubmitted && reply?['v']==1 && reply?['seq']==seq &&
          reply?['accepted']==true && run is String &&
          RegExp(r'^[0-9]+-[0-9]+$').hasMatch(run)) {
        _ackSubmitted = true;
        // One receipt after validation; never ACK an ACK or retry the channel.
        unawaited(_channel.invokeMethod<void>('ackProof',
          {'v':1,'seq':seq,'run':run}).catchError((Object _) {}));
      }
    }).catchError((Object _) {}));
  } catch (_) {}
}

Future<T> qaReliableTagged<T>(String site, Future<T> Function() action) =>
  runZoned(action, zoneValues: {_site:site});

List<String> qaReliableFrames(StackTrace stack) {
  final pattern=RegExp(r'package:kanban/(organizer/[A-Za-z0-9_./]+\.dart:[0-9]+:[0-9]+)');
  return stack.toString().split('\n').map(pattern.firstMatch)
    .whereType<RegExpMatch>().map((m)=>m.group(1)!)
    .where((f)=>!f.contains('collaboration_transport.dart') && !f.contains('qa_measured_diagnostics.dart'))
    .take(4).toList();
}
String qaReliableSite() => Zone.current[_site] as String? ?? 'unclassified';
void qaReliableRequest(String operation, List<String> frames, Map<String,Object> work, String site) => _emit('request', {
  'op':AccountWorkCoordinator.readOperations.contains(operation) ? operation : 'mutationOrUnknown',
  'site':site,
  'kind':work['kind'] ?? 'unspecified','job':work['job'] ?? 0,'frames':frames,
});
void qaMeasuredWork(AccountWorkEvent e) => _emit('work', {
  'event':e.event.name,'kind':e.kind.name,'job':e.job,'priority':e.priority.name,
  'op':AccountWorkCoordinator.readOperations.contains(e.operation) ? e.operation : 'mutationOrUnknown',
  'active':e.activeReads,'pending':e.pendingReads,'waitMs':e.queueWait.inMilliseconds,
});
void qaMeasuredSync(CollaborationSyncDiagnostic e) => _emit('sync', {
  'event':e.kind.name,'scopes':e.scopeCount,'content':e.contentScopeCount,
  'finance':e.financeScopeCount,'fallback':e.recoveryFallback?.name,
});
void qaReliableUi(String event) => _emit('ui', {'event':event});
void qaReliableError(String phase,String code,List<String> frames) =>
  _emit('error',{'phase':phase,'code':code,'frames':frames});
void qaReliableCompletion(CollaborationSyncCompletion c) {
  final error=c.error;
  final code=error is CollaborationException ? error.code :
    error is CryptoAuthorityPending ? error.reason : error?.runtimeType.toString();
  _emit('completion',{'sequence':c.sequence,'unresolved':c.work.unresolved,
    'retry':c.retryAt!=null,
    'error':code==null ? null : RegExp(r'^[A-Za-z0-9_.-]{1,100}$').hasMatch(code) ? code : 'unclassified'});
}

bool qaReliableFail(bool failed,String reason) { if(failed) qaReliableUi(reason); return failed; }
bool qaReliablePass(bool passed,String reason) { if(!passed) qaReliableUi(reason); return passed; }
