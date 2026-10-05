import 'dart:convert';
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../ai/ai_models.dart';

class AiChatThread {
  const AiChatThread({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.messages,
  });

  final String id;
  final int projectId;
  final String projectName;
  final int createdAtMs;
  final int updatedAtMs;
  final List<AiChatMessage> messages;

  String get title {
    for (final message in messages) {
      if (message.role == 'user' && message.content.trim().isNotEmpty) {
        final text = message.content.trim().replaceAll(RegExp(r'\s+'), ' ');
        return text.length > 64 ? '${text.substring(0, 64)}...' : text;
      }
    }
    return 'Untitled chat';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'project_id': projectId,
    'project_name': projectName,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
    'messages': messages
        .map(
          (m) => <String, dynamic>{
            'role': m.role,
            'content': m.content,
            'created_at_ms': m.createdAtMs,
          },
        )
        .toList(),
  };

  factory AiChatThread.fromJson(Map<String, dynamic> json) {
    final createdAtMs =
        int.tryParse(json['created_at_ms']?.toString() ?? '') ?? 0;
    final updatedAtMs =
        int.tryParse(json['updated_at_ms']?.toString() ?? '') ?? 0;
    final rawMessages = json['messages'] as List<dynamic>? ?? const <dynamic>[];
    final messages = <AiChatMessage>[];
    for (var i = 0; i < rawMessages.length; i += 1) {
      final raw = rawMessages[i];
      if (raw is! Map<String, dynamic>) continue;
      final fallbackTs = createdAtMs > 0
          ? createdAtMs + i
          : (updatedAtMs > 0 ? updatedAtMs + i : 0);
      messages.add(
        AiChatMessage(
          role: raw['role']?.toString() ?? 'assistant',
          content: raw['content']?.toString() ?? '',
          createdAtMs:
              int.tryParse(raw['created_at_ms']?.toString() ?? '') ??
              fallbackTs,
        ),
      );
    }
    return AiChatThread(
      id: json['id']?.toString() ?? '',
      projectId: int.tryParse(json['project_id']?.toString() ?? '') ?? 0,
      projectName: json['project_name']?.toString() ?? 'Project',
      createdAtMs: createdAtMs,
      updatedAtMs: updatedAtMs,
      messages: messages,
    );
  }
}

/// Account-bound local history. Unscoped v1 records remain on disk but are
/// deliberately not claimed by any account; migrating them requires ownership.
class AiChatStore {
  AiChatStore({this.scope}) : _generation = _generations[scope] ?? 0;

  final String? scope;
  final int _generation;
  static final Map<String?, int> _generations = {};
  static final Map<String, Future<void>> _pending = {};
  String get _threadsKey => 'ai_chat_threads_v2_$scope';
  bool get _active =>
      scope != null && _generation == (_generations[scope] ?? 0);

  void _requireActive() {
    if (!_active) {
      throw StateError('AI history requires an active account scope');
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final key = scope ?? '';
    final result = Completer<T>();
    _pending[key] = (_pending[key] ?? Future<void>.value()).then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<List<AiChatThread>> readAll() =>
      _enqueue(() async => _active ? _readAll() : const <AiChatThread>[]);

  Future<List<AiChatThread>> _readAll() async {
    _requireActive();
    final prefs = await SharedPreferences.getInstance();
    if (!_active) return const [];
    final raw = prefs.getString(_threadsKey);
    if (raw == null || raw.trim().isEmpty) return const <AiChatThread>[];
    // Malformed account data must not be silently overwritten as empty history.
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(AiChatThread.fromJson)
        .where((t) => t.id.isNotEmpty)
        .toList()
      ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
  }

  Future<List<AiChatThread>> readByProject(int projectId) async {
    final all = await readAll();
    return all.where((t) => t.projectId == projectId).toList()
      ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
  }

  Future<void> saveThread(AiChatThread thread) => _enqueue(() async {
    _requireActive();
    final all = await _readAll();
    _requireActive();
    await _writeAll([thread, ...all.where((t) => t.id != thread.id)]);
  });

  Future<void> deleteThread(String id) => _enqueue(() async {
    _requireActive();
    final all = await _readAll();
    _requireActive();
    await _writeAll(all.where((t) => t.id != id).toList());
  });

  Future<void> _writeAll(List<AiChatThread> threads) async {
    final prefs = await SharedPreferences.getInstance();
    _requireActive();
    if (!await prefs.setString(
      _threadsKey,
      jsonEncode(threads.map((t) => t.toJson()).toList()),
    )) {
      throw StateError('AI history could not be saved');
    }
  }

  /// Invalidates in-flight writers from this account before queued cleanup.
  /// New store instances created after sign-in can use this scope again.
  Future<void> clearScope() {
    if (scope == null) return Future.value();
    _generations[scope] = (_generations[scope] ?? 0) + 1;
    return _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.remove(_threadsKey)) {
        throw StateError('AI history could not be cleared');
      }
    });
  }
}
