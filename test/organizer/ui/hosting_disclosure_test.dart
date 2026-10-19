import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/presentation/shared/hosting_disclosure.dart';
import 'package:kanban/organizer/presentation/shared/sharing_auth.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

class PublicTransport implements CollaborationTransport {
  final requests =
      <
        ({
          String server,
          String operation,
          String? token,
          Map<String, Object?> params,
        })
      >[];
  final replies = <String, Completer<Map<String, dynamic>>>{};
  int closes = 0;

  @override
  Future<Map<String, dynamic>> call({
    required String serverUrl,
    required String operation,
    Map<String, Object?> params = const {},
    String? token,
    bool allowLocalHttp = false,
  }) {
    requests.add((
      server: serverUrl,
      operation: operation,
      token: token,
      params: params,
    ));
    return (replies[serverUrl] ??= Completer()).future;
  }

  void respond(String server, [String? name]) => replies[server]!.complete({
    'api': 'familyhub_native',
    'version': 1,
    if (name != null) 'hostingInformation': {'operatorName': name},
  });

  @override
  void close() {
    closes++;
  }
}

Widget harness(
  Widget child,
  PublicTransport transport, {
  String language = 'en',
}) => ProviderScope(
  overrides: [
    collaborationTransportFactoryProvider.overrideWithValue(() => transport),
  ],
  child: MaterialApp(
    locale: Locale(language),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  test(
    'legacy metadata, wrong types, limits and spoofing are honest unknowns',
    () {
      for (final value in [
        null,
        [],
        'claimed',
        {'operatorName': true},
        {'operatorName': 'a' * 301},
        {'operatorName': 'Name\u202eother'},
        {'operatorContact': 'line\nbreak'},
      ]) {
        final info = HostingInformation.fromCapabilities({
          'hostingInformation': value,
        });
        expect(info.operatorName, isNull);
        expect(info.operatorContact, isNull);
      }
      final info = HostingInformation.fromCapabilities({
        'hostingInformation': {
          'operatorName': ' Host ',
          'operatorContact': ' contact@example.test ',
          'adminSecret': 'not a public field',
        },
      });
      expect(info.operatorName, 'Host');
      expect(info.operatorContact, 'contact@example.test');
    },
  );

  testWidgets(
    'first connection shows disclosure beside existing connect action',
    (tester) async {
      final transport = PublicTransport();
      await tester.pumpWidget(
        harness(
          SharingAuthPanel(
            initialServer: 'https://host.test/',
            onStart: () {},
            onConnected: () {},
          ),
          transport,
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Hosting and trust'), findsOneWidget);
      expect(find.textContaining('identify users correctly'), findsOneWidget);
      expect(find.text('Operator information is unavailable.'), findsOneWidget);
      expect(transport.requests.single.operation, 'capabilities');
      expect(transport.requests.single.token, isNull);
      expect(transport.requests.single.params, isEmpty);
      transport.respond('https://host.test/', 'Synthetic Host');
      await tester.pumpAndSettle();
      expect(
        find.text('Operator (supplied by this server): Synthetic Host'),
        findsOneWidget,
      );
    },
  );

  testWidgets('late server A cannot replace server B disclosure', (
    tester,
  ) async {
    final transport = PublicTransport();
    final endpoint = ValueNotifier('https://a.test/');
    addTearDown(endpoint.dispose);
    await tester.pumpWidget(
      harness(
        ValueListenableBuilder<String>(
          valueListenable: endpoint,
          builder: (_, value, _) =>
              HostingDisclosureForServer(serverUrl: value),
        ),
        transport,
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    endpoint.value = 'https://b.test/';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    transport.respond('https://b.test/', 'B');
    await tester.pumpAndSettle();
    transport.respond('https://a.test/', 'A');
    await tester.pumpAndSettle();
    expect(find.text('https://b.test/'), findsOneWidget);
    expect(find.text('Operator (supplied by this server): B'), findsOneWidget);
    expect(find.text('Operator (supplied by this server): A'), findsNothing);
    expect(transport.closes, greaterThanOrEqualTo(1));
  });

  for (final language in ['sl', 'en']) {
    testWidgets('plain server contact fits narrow $language at large text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        harness(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: const HostingDisclosure(
              serverUrl: 'https://hosting.example.test/jivie/',
              information: HostingInformation(
                operatorName: 'Synthetic Hosting',
                operatorContact: 'https://contact.example.test/',
              ),
            ),
          ),
          PublicTransport(),
          language: language,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Synthetic Hosting'), findsOneWidget);
      expect(
        find.textContaining('https://contact.example.test/'),
        findsOneWidget,
      );
      expect(find.byType(InkWell), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('invalid and non-opted-in local HTTP send no request', (
    tester,
  ) async {
    final transport = PublicTransport();
    for (final server in [
      '',
      'not a url',
      'http://localhost/',
      'https://user:secret@example.test/',
      'https://host.test/?secret=1',
    ]) {
      await tester.pumpWidget(
        harness(HostingDisclosureForServer(serverUrl: server), transport),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(transport.requests, isEmpty);
  });

  testWidgets('typing cancels disclosure fetch until endpoint settles', (
    tester,
  ) async {
    final transport = PublicTransport();
    final endpoint = ValueNotifier('https://host.test/a');
    addTearDown(endpoint.dispose);
    await tester.pumpWidget(
      harness(
        ValueListenableBuilder<String>(
          valueListenable: endpoint,
          builder: (_, value, _) =>
              HostingDisclosureForServer(serverUrl: value),
        ),
        transport,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    endpoint.value = 'https://host.test/ab';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    endpoint.value = 'https://host.test/abc';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(transport.requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 100));
    expect(transport.requests.single.server, 'https://host.test/abc/');
    transport.respond('https://host.test/abc/');
    await tester.pumpAndSettle();
  });

  for (final offline in [false, true]) {
    testWidgets(
      '${offline ? 'unavailable' : 'legacy'} host keeps endpoint and honest status',
      (tester) async {
        final transport = PublicTransport();
        await tester.pumpWidget(
          harness(
            const HostingDisclosureForServer(serverUrl: 'https://legacy.test/'),
            transport,
          ),
        );
        await tester.pump(const Duration(milliseconds: 350));
        if (offline) {
          transport.replies['https://legacy.test/']!.completeError(
            StateError('offline'),
          );
        } else {
          transport.respond('https://legacy.test/');
        }
        await tester.pumpAndSettle();
        expect(find.text('https://legacy.test/'), findsOneWidget);
        expect(
          find.text(
            offline
                ? 'Operator information is unavailable.'
                : 'The server has not provided an operator name.',
          ),
          findsOneWidget,
        );
        expect(transport.requests.length, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
