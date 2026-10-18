import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/l10n.dart';
import '../../data/e2ee/account_crypto_v2_workflow.dart';
import '../../data/e2ee/account_directory_v2.dart';
import '../../data/e2ee/crypto_identity_verification.dart';
import '../../data/e2ee/session_crypto_access.dart';
import 'account_root_replacement_page.dart';

class AccountDevicesPage extends StatefulWidget {
  const AccountDevicesPage({required this.workflow, super.key});
  final AccountCryptoV2Workflow workflow;
  @override
  State<AccountDevicesPage> createState() => _AccountDevicesPageState();
}

class _AccountDevicesPageState extends State<AccountDevicesPage> {
  final _received = TextEditingController();
  VerifiedAccountDirectory? _directory;
  String? _output;
  bool _busy = false, _failed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _received.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final directory = await widget.workflow.directory
          .cachedVerifiedDirectory();
      if (mounted) setState(() => _directory = directory);
    } catch (_) {
      /* Unapproved devices intentionally have no local authority. */
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await action();
      await _load();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _outputSummary(BuildContext context) {
    try {
      final card = jsonDecode(_output!) as Map;
      final code = card['safetyCode'];
      if (code is String) return code;
      return card['purpose'] == 'deviceApprovalRequest'
          ? context.l10n.cryptoCreateDeviceRequest
          : context.l10n.cryptoDeviceApproved;
    } catch (_) {
      return context.l10n.cryptoPublicCardExplanation;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n, workflow = widget.workflow;
    final approved =
        _directory?.devices.any(
          (d) =>
              d['deviceId'] == workflow.deviceId &&
              d['revokedGeneration'] == null,
        ) ==
        true;
    return Scaffold(
      appBar: AppBar(title: Text(l.cryptoDevicesTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(l.cryptoDevicePairingExplanation),
                const SizedBox(height: 16),
                if (_busy) const LinearProgressIndicator(),
                if (_failed)
                  Text(
                    l.accountRecoveryFailed,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (approved) ...[
                  Text(
                    l.cryptoDevicesTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  for (final device in _directory!.devices)
                    ListTile(
                      leading: Icon(
                        device['revokedGeneration'] == null
                            ? Icons.devices_outlined
                            : Icons.block,
                      ),
                      title: Text(
                        (device['deviceId'] as String).substring(0, 8),
                      ),
                      subtitle: Text(
                        device['revokedGeneration'] == null
                            ? l.cryptoDeviceApproved
                            : l.cryptoDeviceRevoked,
                      ),
                      trailing: device['deviceId'] == workflow.deviceId
                          ? const Icon(Icons.check_circle_outline)
                          : device['revokedGeneration'] == null
                          ? IconButton(
                              icon: const Icon(Icons.block),
                              tooltip: l.cryptoRevokeDevice,
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: Text(l.cryptoRevokeDevice),
                                          content: Text(
                                            l.cryptoRevokeDeviceExplanation,
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: Text(l.cancel),
                                            ),
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: Text(l.cryptoRevokeDevice),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmed == true && mounted)
                                        await _run(
                                          () => workflow.revokeDevice(
                                            device['deviceId'] as String,
                                          ),
                                        );
                                    },
                            )
                          : null,
                    ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            final verifier = CryptoIdentityVerification(
                              workflow.directory.reducer.crypto,
                              workflow.store,
                            );
                            final card = await verifier.publicCard(
                              (await workflow.directory
                                  .cachedVerifiedDirectory()),
                            );
                            if (mounted) setState(() => _output = card);
                          }),
                    child: Text(l.cryptoShowPublicIdentity),
                  ),
                ] else
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            final card = await workflow.prepareDeviceRequest();
                            if (mounted) setState(() => _output = card);
                          }),
                    child: Text(l.cryptoCreateDeviceRequest),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _received,
                  minLines: 3,
                  maxLines: 8,
                  decoration: InputDecoration(
                    labelText: l.cryptoPastePublicCard,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          if (approved) {
                            final confirmation = await workflow
                                .authorizeDeviceRequest(_received.text.trim());
                            if (mounted) setState(() => _output = confirmation);
                          } else {
                            await workflow.acceptDeviceConfirmation(
                              _received.text.trim(),
                            );
                          }
                          _received.clear();
                        }),
                  child: Text(
                    approved
                        ? l.cryptoApproveExactDevice
                        : l.cryptoAcceptDeviceConfirmation,
                  ),
                ),
                if (_output != null) ...[
                  const SizedBox(height: 20),
                  Text(l.cryptoPublicCardExplanation),
                  const SizedBox(height: 12),
                  SelectableText(_outputSummary(context)),
                  TextButton.icon(
                    icon: const Icon(Icons.copy),
                    label: Text(l.cryptoCopyPublicCard),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: _output!)),
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.key_outlined),
                  label: Text(l.cryptoReplaceRecoveryTitle),
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) =>
                                AccountRootReplacementPage(workflow: workflow),
                          ),
                        ),
                ),
                Text(l.cryptoHistoryPendingExplanation),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ContactIdentityVerificationPage extends StatefulWidget {
  const ContactIdentityVerificationPage({
    required this.access,
    required this.scopeId,
    required this.accountId,
    required this.displayName,
    super.key,
  });
  final SessionCryptoAccess access;
  final String scopeId, accountId, displayName;
  @override
  State<ContactIdentityVerificationPage> createState() =>
      _ContactIdentityVerificationPageState();
}

class _ContactIdentityVerificationPageState
    extends State<ContactIdentityVerificationPage> {
  final _card = TextEditingController();
  bool _busy = false, _failed = false, _verified = false;
  @override
  void dispose() {
    _card.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.access.verifyContactCard(
        widget.scopeId,
        widget.accountId,
        _card.text.trim(),
      );
      if (mounted) setState(() => _verified = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(widget.displayName)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(l.cryptoVerifyContactExplanation),
                const SizedBox(height: 20),
                if (_busy) const LinearProgressIndicator(),
                if (_failed) Text(l.accountRecoveryFailed),
                if (_verified)
                  Text(l.cryptoContactVerified)
                else ...[
                  TextField(
                    controller: _card,
                    minLines: 4,
                    maxLines: 10,
                    decoration: InputDecoration(
                      labelText: l.cryptoPastePublicCard,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _verify,
                    child: Text(l.cryptoCompareContact),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
