import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../data/collaboration_repository.dart';
import '../../domain/attachment_models.dart';
import '../../domain/spreadsheet_models.dart';
import '../../state/collaboration_provider.dart';
import '../attachments/attachments_panel.dart';
import '../tables/spreadsheet_tables_page.dart';
import 'sharing_errors.dart';
import 'content_moderation.dart';

/// Discoverable destinations in the selected space; never changes selection.
class SharedDocumentsEntries extends StatelessWidget {
  const SharedDocumentsEntries({super.key, required this.scope});
  final SharedScope scope;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (scope.kind == SharedScopeKind.organization)
        ListTile(
          key: ValueKey('space-tables-${scope.id}'),
          leading: const Icon(Icons.table_chart_outlined),
          title: Text(context.l10n.documentsTables),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => openSharedDocuments(context, scope, tables: true),
        ),
      ListTile(
        key: ValueKey('space-attachments-${scope.id}'),
        leading: const Icon(Icons.attach_file),
        title: Text(context.l10n.documentsAttachments),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => openSharedDocuments(context, scope),
      ),
    ],
  );
}

Future<void> openSharedDocuments(
  BuildContext context,
  SharedScope scope, {
  bool tables = false,
  AttachmentTarget? target,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) =>
        SharedDocumentsRoute(scope: scope, tables: tables, target: target),
  ),
);

class SharedDocumentsRoute extends ConsumerStatefulWidget {
  const SharedDocumentsRoute({
    super.key,
    required this.scope,
    this.tables = false,
    this.target,
  });
  final SharedScope scope;
  final bool tables;
  final AttachmentTarget? target;
  @override
  ConsumerState<SharedDocumentsRoute> createState() =>
      _SharedDocumentsRouteState();
}

class _SharedDocumentsRouteState extends ConsumerState<SharedDocumentsRoute> {
  late final _identity = ref.read(collaborationProvider).valueOrNull?.session;
  late Future<SharedDocumentsContext> _opening = _open();
  SpreadsheetGateway? _tableGateway;
  bool _accessLost = false;
  final _attachmentGateways = <AttachmentTarget, AttachmentGateway>{};
  bool get _visible {
    if (!mounted || _accessLost) return false;
    final state = ref.read(collaborationProvider).valueOrNull;
    return _identity != null &&
        state?.localAccessAllowed == true &&
        state?.session?.partition == _identity.partition &&
        state?.session?.deviceId == _identity.deviceId &&
        state?.sessionInvalid != true &&
        state?.deletionPending != true &&
        state!.scopes.any(
          (s) =>
              s.id == widget.scope.id && s.canRead && !s.deleted && !s.blocked,
        );
  }

  Future<SharedDocumentsContext> _open() async {
    final repository = await ref.read(collaborationRepositoryProvider.future);
    if (!_visible) throw const CollaborationException('session_changed');
    return repository.openDocuments(
      widget.scope.id,
      visible: () => _visible,
      localPreviewFeature: widget.tables ? 'spreadsheets' : 'attachments',
      onAccessLost: () {
        if (mounted) setState(() => _accessLost = true);
      },
    );
  }

  AttachmentGateway _attachments(
    SharedDocumentsContext context,
    AttachmentTarget target,
  ) => _attachmentGateways.putIfAbsent(
    target,
    () => context.attachments(target),
  );
  @override
  Widget build(BuildContext context) {
    ref.watch(collaborationProvider);
    final l = context.l10n;
    final title = widget.tables ? l.documentsTables : l.documentsAttachments;
    if (!_visible) {
      final revoked =
          _accessLost ||
          ref
                  .read(collaborationProvider)
                  .valueOrNull
                  ?.scopes
                  .any(
                    (s) => s.id == widget.scope.id && (s.revoked || s.deleted),
                  ) ==
              true;
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Text(
            revoked ? l.sharingAccessRevoked : l.documentsContextChanged,
          ),
        ),
      );
    }
    return FutureBuilder<SharedDocumentsContext>(
      future: _opening,
      builder: (context, result) {
        if (result.hasData) {
          final data = result.data!;
          final supported = widget.tables
              ? data.spreadsheetsSupported
              : data.attachmentsSupported;
          if (supported) {
            if (widget.tables) {
              return SpreadsheetTablesPage(
                gateway: _tableGateway ??= data.tables,
                changes: data.tableChanges(),
                changesForTable: data.tableChanges,
                onReport: (id) => showContentReport(
                  context,
                  ref,
                  scopeId: widget.scope.id,
                  targetType: 'table',
                  targetId: id,
                ),
                attachmentsBuilder: data.attachmentsSupported
                    ? (id) {
                        final target = AttachmentTarget(
                          scopeId: widget.scope.id,
                          targetType: 'table',
                          targetId: id,
                        );
                        return AttachmentsPanel(
                          gateway: _attachments(data, target),
                          changes: data.attachmentChanges(target),
                          canEdit: data.canAddAttachment(target),
                          canDelete: data.canDeleteAttachment,
                          onReport: (file) => showContentReport(
                            context,
                            ref,
                            scopeId: widget.scope.id,
                            targetType: 'attachment',
                            targetId: file.id,
                          ),
                        );
                      }
                    : null,
              );
            }
            final target =
                widget.target ??
                AttachmentTarget(
                  scopeId: widget.scope.id,
                  targetType: 'scope',
                  targetId: widget.scope.id,
                );
            return Scaffold(
              appBar: AppBar(title: Text(title)),
              body: SafeArea(
                child: AttachmentsPanel(
                  gateway: _attachments(data, target),
                  changes: data.attachmentChanges(target),
                  canEdit: data.canAddAttachment(target),
                  canDelete: data.canDeleteAttachment,
                  onReport: (file) => showContentReport(
                    context,
                    ref,
                    scopeId: widget.scope.id,
                    targetType: 'attachment',
                    targetId: file.id,
                  ),
                ),
              ),
            );
          }
        }
        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (result.connectionState != ConnectionState.done)
                    const LinearProgressIndicator()
                  else ...[
                    Text(
                      result.hasError
                          ? sharingErrorMessage(context, result.error!)
                          : l.documentsUnavailable,
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _tableGateway = null;
                        _attachmentGateways.clear();
                        _opening = _open();
                      }),
                      child: Text(l.organizerRetry),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
