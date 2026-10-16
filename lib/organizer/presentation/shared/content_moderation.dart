import '../ideas/idea_report_preview.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../state/collaboration_provider.dart';
import 'sharing_errors.dart';
import 'sharing_session_boundary.dart';

bool _onlineSession(CollaborationState state) =>
    !state.sessionInvalid &&
    state.session?.expiresAt.isAfter(DateTime.now()) == true;

bool _reportScope(CollaborationState state, String scopeId) =>
    _onlineSession(state) &&
    state.scopes.any((s) => s.id == scopeId && s.canRead);

/// Explicit server-specific consent. No acceptance is recorded by opening it.
Future<bool> showSharedContentPolicy(
  BuildContext context, {
  String? scopeId,
  bool allowOfflineDraft = false,
  bool review = false,
  bool allowReadOnly = false,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final session = container.read(collaborationProvider).valueOrNull?.session;
  if (session == null) return false;
  final cached = container.read(collaborationProvider).valueOrNull;
  if (scopeId != null &&
      cached?.scopes.where((s) => s.id == scopeId).firstOrNull?.kind ==
          SharedScopeKind.personal) {
    return true;
  }
  if (allowOfflineDraft && cached != null && !_onlineSession(cached)) {
    return true;
  }
  if (!review && cached?.sharedContentPolicy?.accepted == true) return true;
  final controller = container.read(collaborationProvider.notifier);
  try {
    final policy = await controller.sharedContentPolicy(scopeId: scopeId);
    if (!context.mounted) return false;
    final current = container.read(collaborationProvider).valueOrNull;
    if (current?.session?.partition != session.partition ||
        current?.session?.deviceId != session.deviceId ||
        current == null ||
        !_onlineSession(current)) {
      return false;
    }
    if (policy.accepted && !review) return true;
    return await Navigator.of(context, rootNavigator: true).push<bool>(
          MaterialPageRoute<bool>(
            fullscreenDialog: true,
            builder: (context) => Consumer(
              builder: (context, ref, _) {
                final guard = SharingSessionGuard(
                  context,
                  ref,
                  session: session,
                );
                return SharingSessionBoundary(
                  guard: guard,
                  visibleWhen: (state) =>
                      _onlineSession(state) &&
                      (scopeId == null || _reportScope(state, scopeId)),
                  child: SharedContentPolicyDialog(
                    policy: policy,
                    serverUrl: session.serverUrl,
                    allowReadOnly: allowReadOnly,
                    onAccept: () =>
                        guard.controller.acceptSharedContentPolicy(policy),
                  ),
                );
              },
            ),
          ),
        ) ??
        false;
  } catch (error) {
    if (!context.mounted) return false;
    final current = container.read(collaborationProvider).valueOrNull;
    if (current?.session?.partition != session.partition ||
        current?.session?.deviceId != session.deviceId) {
      return false;
    }
    final draftAllowed =
        allowOfflineDraft &&
        error is CollaborationException &&
        const {
          'network',
          'session_expired',
          'moderation_upgrade_required',
        }.contains(error.code);
    if (draftAllowed) {
      // Local drafts remain usable. The controller independently gates uploads.
      return true;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.moderationPolicyTitle),
        content: Text(sharingErrorMessage(context, error)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
    return false;
  }
}

/// Called only after a controller/server asks for explicit consent.
Future<bool> resolveSharedPolicyError(
  BuildContext context,
  Object error,
) async {
  if (error is! CollaborationException ||
      error.code != 'policy_acceptance_required') {
    return false;
  }
  return showSharedContentPolicy(context);
}

class SharedContentPolicyDialog extends StatefulWidget {
  const SharedContentPolicyDialog({
    super.key,
    required this.policy,
    required this.serverUrl,
    required this.onAccept,
    this.allowReadOnly = false,
  });
  final SharedContentPolicy policy;
  final String serverUrl;
  final Future<void> Function() onAccept;
  final bool allowReadOnly;
  @override
  State<SharedContentPolicyDialog> createState() =>
      _SharedContentPolicyDialogState();
}

class _SharedContentPolicyDialogState extends State<SharedContentPolicyDialog> {
  bool _checked = false;
  bool _busy = false;
  String? _error;
  Future<void> _accept() async {
    if (!_checked || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onAccept();
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = sharingErrorMessage(context, error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          toolbarHeight: (MediaQuery.textScalerOf(context).scale(22) * 2 + 16)
              .clamp(kToolbarHeight, 112),
          title: Text(l.moderationPolicyTitle, maxLines: 2),
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.all(16),
          child: Align(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 12,
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.pop(context, widget.policy.accepted),
                    child: Text(
                      widget.policy.accepted
                          ? l.close
                          : widget.allowReadOnly
                          ? l.moderationRulesViewOnly
                          : l.cancel,
                    ),
                  ),
                  if (!widget.policy.accepted)
                    FilledButton(
                      key: const ValueKey('shared-policy-accept'),
                      onPressed: _checked && !_busy ? _accept : null,
                      child: Text(
                        widget.allowReadOnly
                            ? l.moderationRulesAcceptContinue
                            : l.moderationPolicyAccept,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l.moderationPolicyDescription),
                    const SizedBox(height: 16),
                    Text(l.moderationRulesPermission),
                    const SizedBox(height: 12),
                    Text(l.moderationRulesRespect),
                    const SizedBox(height: 12),
                    Text(l.moderationRulesReport),
                    const SizedBox(height: 16),
                    Text(
                      l.moderationRecipient(
                        widget.policy.recipientName,
                        Uri.parse(widget.serverUrl).host,
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    ExpansionTile(
                      key: const ValueKey('shared-policy-full-rules'),
                      tilePadding: EdgeInsets.zero,
                      title: Text(l.moderationRulesFull),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SelectableText(
                            Localizations.localeOf(context).languageCode == 'sl'
                                ? widget.policy.textSl
                                : widget.policy.textEn,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(l.moderationRetention),
                        const SizedBox(height: 16),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (widget.policy.accepted)
                      Text(l.moderationPolicyAccepted),
                    if (!widget.policy.accepted)
                      CheckboxListTile(
                        key: const ValueKey('shared-policy-checkbox'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _checked,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _checked = v == true),
                        title: Text(l.moderationPolicyCheckbox),
                      ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ContentReportButton extends ConsumerWidget {
  const ContentReportButton({
    super.key,
    required this.scopeId,
    required this.targetId,
    this.targetType = 'record',
  });
  final String scopeId, targetId, targetType;
  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    key: ValueKey('report-$targetType-$scopeId-$targetId'),
    tooltip: targetType == 'user'
        ? context.l10n.moderationReportUser
        : context.l10n.moderationReportContent,
    icon: const Icon(Icons.flag_outlined, size: 20),
    onPressed: () => showContentReport(
      context,
      ref,
      scopeId: scopeId,
      targetType: targetType,
      targetId: targetId,
    ),
  );
}

final _reportDialogs = Expando<bool>();

Future<void> showContentReport(
  BuildContext context,
  WidgetRef ref, {
  required String scopeId,
  required String targetType,
  required String targetId,
}) async {
  final guard = SharingSessionGuard(context, ref);
  final session = guard.session;
  if (session == null) return;
  final current = ref.read(collaborationProvider).valueOrNull;
  if (current == null || !_onlineSession(current)) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.moderationReportContent),
        content: Text(context.l10n.moderationOffline),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
    return;
  }
  final navigator = Navigator.of(context, rootNavigator: true);
  if (_reportDialogs[navigator] == true) return;
  _reportDialogs[navigator] = true;
  try {
    final sent = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SharingSessionBoundary(
        guard: guard,
        visibleWhen: (state) => _reportScope(state, scopeId),
        child: _ReportPreviewDialog(
          preview: () => guard.controller.previewContentReport(
            scopeId: scopeId,
            targetType: targetType,
            targetId: targetId,
          ),
          serverUrl: session.serverUrl,
          onSubmit: (preview, reason, details) =>
              guard.controller.submitContentReport(
                preview: preview,
                reason: reason,
                details: details,
              ),
        ),
      ),
    );
    if (sent == true && context.mounted && guard.isCurrent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.moderationReportSent)),
      );
    }
  } finally {
    _reportDialogs[navigator] = false;
  }
}

class _ReportPreviewDialog extends StatefulWidget {
  const _ReportPreviewDialog({
    required this.preview,
    required this.serverUrl,
    required this.onSubmit,
  });
  final Future<ContentReportPreview> Function() preview;
  final String serverUrl;
  final Future<ContentReportReceipt> Function(
    ContentReportPreview,
    String,
    String,
  )
  onSubmit;
  @override
  State<_ReportPreviewDialog> createState() => _ReportPreviewDialogState();
}

class _ReportPreviewDialogState extends State<_ReportPreviewDialog> {
  late final Future<ContentReportPreview> _preview = Future.sync(
    widget.preview,
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<ContentReportPreview>(
    future: _preview,
    builder: (context, result) {
      if (result.hasData) {
        return ContentReportDialog(
          preview: result.data!,
          serverUrl: widget.serverUrl,
          onSubmit: widget.onSubmit,
        );
      }
      return AlertDialog(
        title: Text(context.l10n.moderationReportContent),
        content: result.hasError
            ? Text(
                result.error is CollaborationException &&
                        (result.error as CollaborationException).code ==
                            'network'
                    ? context.l10n.moderationOffline
                    : sharingErrorMessage(context, result.error!),
              )
            : const SizedBox(
                width: 48,
                height: 48,
                child: Center(child: CircularProgressIndicator()),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
        ],
      );
    },
  );
}

class ContentReportDialog extends StatefulWidget {
  const ContentReportDialog({
    super.key,
    required this.preview,
    required this.serverUrl,
    required this.onSubmit,
  });
  final ContentReportPreview preview;
  final String serverUrl;
  final Future<ContentReportReceipt> Function(
    ContentReportPreview,
    String,
    String,
  )
  onSubmit;
  @override
  State<ContentReportDialog> createState() => _ContentReportDialogState();
}

class _ContentReportDialogState extends State<ContentReportDialog> {
  final _details = TextEditingController();
  String? _reason;
  String? _error;
  bool _busy = false;
  bool _attempted = false;
  bool _ideaReady = false;
  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy ||
        _reason == null ||
        widget.preview.type == 'idea' && !_ideaReady) {
      return;
    }
    if (utf8.encode(_details.text.trim()).length > 2000) {
      setState(() => _error = context.l10n.moderationDetailsLimit);
      return;
    }
    setState(() {
      _busy = true;
      _attempted = true;
      _error = null;
    });
    try {
      await widget.onSubmit(widget.preview, _reason!, _details.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is CollaborationException && error.code == 'network'
              ? context.l10n.moderationReportRetry
              : sharingErrorMessage(context, error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final reasons = {
      'harassment': l.moderationReasonHarassment,
      'hate': l.moderationReasonHate,
      'sexual': l.moderationReasonSexual,
      'violence': l.moderationReasonViolence,
      'illegal': l.moderationReasonIllegal,
      'spam': l.moderationReasonSpam,
      'privacy': l.moderationReasonPrivacy,
      'other': l.moderationReasonOther,
    };
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        title: Text(
          widget.preview.targetType == 'user'
              ? l.moderationReportUser
              : l.moderationReportContent,
        ),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.preview.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  l.moderationRecipient(
                    widget.preview.recipientName,
                    Uri.parse(widget.serverUrl).host,
                  ),
                ),
                const SizedBox(height: 12),
                Text(l.moderationReportPrivacy),
                const SizedBox(height: 12),
                Text(
                  l.moderationReportedData,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                if (widget.preview.type == 'idea')
                  IdeaReportPreview(
                    preview: widget.preview,
                    onReady: (value) {
                      if (mounted) setState(() => _ideaReady = value);
                    },
                  ),
                ReportEvidenceView(
                  evidence: Map<String, dynamic>.fromEntries(
                    widget.preview.evidence.entries.where(
                      (e) =>
                          widget.preview.type != 'idea' ||
                          e.key != 'board' && e.key != 'assets',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: const ValueKey('report-reason'),
                  initialValue: _reason,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l.moderationReportReason,
                  ),
                  items: [
                    for (final reason in reasons.entries)
                      DropdownMenuItem(
                        value: reason.key,
                        child: Text(
                          reason.value,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _attempted || _busy
                      ? null
                      : (v) => setState(() => _reason = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('report-details'),
                  controller: _details,
                  readOnly: _attempted || _busy,
                  maxLines: 3,
                  maxLength: 2000,
                  decoration: InputDecoration(
                    labelText: l.moderationReportDetails,
                  ),
                ),
                Text(l.moderationRetention),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('report-send'),
            onPressed:
                _busy ||
                    _reason == null ||
                    widget.preview.type == 'idea' && !_ideaReady
                ? null
                : _send,
            child: Text(_attempted ? l.organizerRetry : l.moderationSendReport),
          ),
        ],
      ),
    );
  }
}

class ReportEvidenceView extends StatelessWidget {
  const ReportEvidenceView({super.key, required this.evidence});
  final Map<String, dynamic> evidence;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final labels = {
      'id': l.moderationRecordIdentifier,
      'accountId': l.moderationAccountIdentifier,
      'type': l.moderationReportedType,
      'revision': l.financeRevision,
      'title': l.organizerTitle,
      'name': l.peopleName,
      'displayName': l.peopleName,
      'username': l.username,
      'role': l.sharingRole,
      'notes': l.organizerNotes,
      'description': l.description,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in evidence.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SelectableText(
              '${labels[item.key] ?? item.key}: ${item.value is String ? item.value : jsonEncode(item.value)}',
            ),
          ),
      ],
    );
  }
}
