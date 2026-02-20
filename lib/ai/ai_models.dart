enum AiKeyMode { ownerKey, userKeyRequired }

class AiProjectPolicy {
  const AiProjectPolicy({
    this.enabled = false,
    this.keyMode = AiKeyMode.ownerKey,
    this.ownerUsername,
  });

  final bool enabled;
  final AiKeyMode keyMode;
  final String? ownerUsername;
}

class AiChatMessage {
  const AiChatMessage({
    required this.role,
    required this.content,
    this.createdAtMs = 0,
  });

  final String role;
  final String content;
  final int createdAtMs;

  AiChatMessage copyWith({String? role, String? content, int? createdAtMs}) {
    return AiChatMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }
}

class AiTaskAssistRequest {
  const AiTaskAssistRequest({
    required this.projectName,
    required this.title,
    required this.description,
  });

  final String projectName;
  final String title;
  final String description;
}
