import 'dart:convert';

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

class AiChatStore {
  const AiChatStore();

  static const String _threadsKey = 'ai_chat_threads_v1';

  Future<List<AiChatThread>> readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_threadsKey);
    if (raw == null || raw.trim().isEmpty) return const <AiChatThread>[];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(AiChatThread.fromJson)
          .where((t) => t.id.isNotEmpty)
          .toList()
        ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    } catch (_) {
      return const <AiChatThread>[];
    }
  }

  Future<List<AiChatThread>> readByProject(int projectId) async {
    final all = await readAll();
    return all.where((t) => t.projectId == projectId).toList()
      ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
  }

  Future<void> saveThread(AiChatThread thread) async {
    final all = await readAll();
    final next = <AiChatThread>[thread, ...all.where((t) => t.id != thread.id)];
    await _writeAll(next);
  }

  Future<void> deleteThread(String id) async {
    final all = await readAll();
    final next = all.where((t) => t.id != id).toList();
    await _writeAll(next);
  }

  Future<void> _writeAll(List<AiChatThread> threads) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(threads.map((t) => t.toJson()).toList());
    await prefs.setString(_threadsKey, encoded);
  }
}
