import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';

class LaunchPage extends ConsumerStatefulWidget {
  const LaunchPage({super.key});

  @override
  ConsumerState<LaunchPage> createState() => _LaunchPageState();
}

class _LaunchPageState extends ConsumerState<LaunchPage> {
  bool _didNavigate = false;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final credentials = await ref.read(credentialsStoreProvider).read();
    if (_didNavigate || !mounted) return;
    _didNavigate = true;

    // Schedule provider update/navigation after current build completes.
    Future<void>(() {
      if (!mounted) return;
      if (credentials != null) {
        ref.read(sessionCredentialsProvider.notifier).state = credentials;
        context.go('/projects');
      } else {
        context.go('/connect');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Restoring session...'),
          ],
        ),
      ),
    );
  }
}
