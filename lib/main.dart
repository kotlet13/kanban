import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';

final _desktopWindowPersistence = _DesktopWindowPersistence();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await _desktopWindowPersistence.init();
  }
  runApp(const ProviderScope(child: KanbanApp()));
}

class _DesktopWindowPersistence extends WindowListener {
  static const String _widthKey = 'window_width';
  static const String _heightKey = 'window_height';

  bool _initialized = false;
  Timer? _saveDebounce;

  Future<void> init() async {
    if (_initialized) return;

    await windowManager.ensureInitialized();
    final options = WindowOptions(
      size: await _readSavedSize(),
      center: true,
      minimumSize: const Size(920, 680),
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    windowManager.addListener(this);
    _initialized = true;
  }

  Future<Size> _readSavedSize() async {
    final prefs = await SharedPreferences.getInstance();
    final width = prefs.getDouble(_widthKey);
    final height = prefs.getDouble(_heightKey);

    if (width == null || height == null) {
      return const Size(1280, 860);
    }
    return Size(width, height);
  }

  Future<void> _saveCurrentWindowSize() async {
    final size = await windowManager.getSize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_widthKey, size.width);
    await prefs.setDouble(_heightKey, size.height);
  }

  void _debouncedSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(
      const Duration(milliseconds: 260),
      () => _saveCurrentWindowSize(),
    );
  }

  @override
  void onWindowResize() {
    _debouncedSave();
  }

  @override
  void onWindowClose() {
    _saveDebounce?.cancel();
    unawaited(_saveCurrentWindowSize());
  }
}
