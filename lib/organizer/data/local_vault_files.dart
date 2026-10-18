import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'local_vault.dart';

/// The journal never contains a key or user content. POSIX directory fsync is
/// required after every rename/unlink; Windows uses a write-through move.
class LocalVaultFiles {
  static final _libc = DynamicLibrary.process();
  static final _open = _libc
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Int32),
        int Function(Pointer<Utf8>, int)
      >('open');
  static final _close = _libc
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  static final _fsync = _libc
      .lookupFunction<Int32 Function(Int32), int Function(int)>('fsync');
  static final _chmod = _libc
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Uint32),
        int Function(Pointer<Utf8>, int)
      >('chmod');
  static final _flock = _libc
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
        'flock',
      );

  Future<void> privateDirectory(Directory directory) async {
    await directory.create(recursive: true);
    await rejectLink(directory.path);
    if (!Platform.isWindows) _mode(directory.path, 448);
  }

  Future<void> rejectLink(String path) async {
    if (await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const LocalVaultException('vault_unsafe_path');
    }
  }

  void _mode(String path, int mode) {
    final native = path.toNativeUtf8();
    try {
      if (_chmod(native, mode) != 0) {
        throw const LocalVaultException('vault_io');
      }
    } finally {
      malloc.free(native);
    }
  }

  Future<void> syncDirectory(Directory directory) async {
    if (Platform.isWindows) return; // MoveFileExW below flushes its metadata.
    final native = directory.path.toNativeUtf8();
    var fd = -1;
    try {
      fd = _open(native, 0);
      if (fd < 0 || _fsync(fd) != 0) {
        throw const LocalVaultException('vault_io');
      }
    } finally {
      if (fd >= 0) _close(fd);
      malloc.free(native);
    }
  }

  Future<void> flush(File file) async {
    await rejectLink(file.path);
    if (!Platform.isWindows) _mode(file.path, 384);
    final handle = await file.open(mode: FileMode.append);
    try {
      await handle.flush();
    } finally {
      await handle.close();
    }
  }

  Future<void> move(File source, File destination) async {
    await rejectLink(source.path);
    await rejectLink(destination.path);
    if (Platform.isWindows) {
      final move = DynamicLibrary.open('kernel32.dll')
          .lookupFunction<
            Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
            int Function(Pointer<Utf16>, Pointer<Utf16>, int)
          >('MoveFileExW');
      final from = source.path.toNativeUtf16(),
          to = destination.path.toNativeUtf16();
      try {
        if (move(from, to, 1 | 8) == 0) {
          throw const LocalVaultException('vault_io');
        }
      } finally {
        malloc.free(from);
        malloc.free(to);
      }
    } else {
      await source.rename(destination.path);
      await syncDirectory(destination.parent);
      if (source.parent.path != destination.parent.path) {
        await syncDirectory(source.parent);
      }
    }
  }

  Future<void> writeJournal(File file, Map<String, dynamic> value) async {
    final pending = File('${file.path}.next');
    await rejectLink(pending.path);
    await pending.writeAsString(jsonEncode(value), flush: true);
    await flush(pending);
    await move(pending, file);
  }

  Future<void> delete(File file) async {
    await rejectLink(file.path);
    if (await file.exists()) {
      await file.delete();
      await syncDirectory(file.parent);
    }
  }

  Future<LocalVaultFileLease> lock(File file, {bool shared = false}) async {
    await rejectLink(file.path);
    await file.create();
    if (Platform.isWindows) {
      final handle = await file.open(mode: FileMode.append);
      try {
        await handle.lock(shared ? FileLock.shared : FileLock.exclusive);
        return LocalVaultFileLease(() async => handle.close());
      } catch (_) {
        await handle.close();
        throw const LocalVaultException('vault_busy');
      }
    }
    _mode(file.path, 384);
    final native = file.path.toNativeUtf8();
    final fd = _open(native, 0);
    malloc.free(native);
    if (fd < 0) throw const LocalVaultException('vault_io');
    if (_flock(fd, (shared ? 1 : 2) | 4) != 0) {
      _close(fd);
      throw const LocalVaultException('vault_busy');
    }
    return LocalVaultFileLease(() async {
      _close(fd);
    });
  }
}

class LocalVaultFileLease {
  LocalVaultFileLease(this._close);
  final Future<void> Function() _close;
  bool _closed = false;
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _close();
  }
}
