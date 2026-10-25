import '../device_session_store.dart';
import 'account_crypto_v2_workflow.dart';
import 'crypto_inventory_json.dart';
import 'session_crypto_access.dart';

/// One sequential metadata/preparation batch. The retained authority handle owns its
/// original five-second clock; closing or expiring it never starts a new lease.
class CryptoVerifiedDispatchReads {
  CryptoVerifiedDispatchReads({
    required this.session,
    required this.accountFor,
    SessionCryptoAccess Function(AccountCryptoV2Workflow)? createAccess,
  }) : _profile = CryptoInventoryJson.canonical(session.profile.toJson()),
       _createAccess =
           createAccess ?? ((account) => SessionCryptoAccess(account: account));

  static const operations = {'scopes.list', 'scopes.members'};
  final DeviceSession session;
  final Future<AccountCryptoV2Workflow> Function(DeviceSession) accountFor;
  final String _profile;
  final SessionCryptoAccess Function(AccountCryptoV2Workflow) _createAccess;
  AccountCryptoV2Workflow? _account;
  SessionCryptoAccess? _access;
  CryptoVerifiedReadOperation? _authority;
  bool _active = true, _running = false;

  bool matches(DeviceSession current) =>
      _active &&
      (_authority?.isActive ?? true) &&
      current.token == session.token &&
      CryptoInventoryJson.canonical(current.profile.toJson()) == _profile &&
      (_account?.directory.isCurrent() ?? true);

  void close() {
    _active = false;
    _authority?.close();
  }

  Future<T> run<T>(
    String operation,
    DeviceSession current,
    Future<T> Function(SessionCryptoAccess? shared) read,
  ) => _run(operations.contains(operation), current, read);

  /// Internal preparation API, never a public dispatch/transport operation.
  /// The normal metadata allowlist above deliberately stays unchanged.
  Future<T> runProjectionCursorOrigin<T>(
    DeviceSession current,
    Future<T> Function(SessionCryptoAccess? shared) read,
  ) => _run(true, current, read);

  Future<T> _run<T>(
    bool compatible,
    DeviceSession current,
    Future<T> Function(SessionCryptoAccess? shared) read,
  ) async {
    if (!compatible || _running || !matches(current)) {
      close();
      return read(null);
    }
    _running = true;
    try {
      final account = _account ??= await accountFor(session);
      if (!matches(current)) {
        close();
        return await read(null);
      }
      final access = _access ??= _createAccess(account);
      final authority = _authority ??= access.createReadOperation();
      return await authority.run(() => read(access));
    } catch (_) {
      close();
      rethrow;
    } finally {
      if (_authority?.isActive == false) close();
      _running = false;
    }
  }
}
