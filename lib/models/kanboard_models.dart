int parseKanboardInt(dynamic value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double parseKanboardDouble(dynamic value, [double fallback = 0]) {
  if (value == null) return fallback;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

String? parseKanboardString(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

enum KanboardAuthMode { apiToken, password }

class KanboardCredentials {
  const KanboardCredentials({
    required this.serverUrl,
    required this.username,
    required this.token,
    this.authMode = KanboardAuthMode.apiToken,
  });

  final String serverUrl;
  final String username;
  final String token;
  final KanboardAuthMode authMode;

  String get normalizedEndpoint {
    final trimmed = serverUrl.trim();
    if (trimmed.endsWith('/jsonrpc.php')) return trimmed;
    if (trimmed.endsWith('/')) return '${trimmed}jsonrpc.php';
    return '$trimmed/jsonrpc.php';
  }
}

class KanboardUser {
  const KanboardUser({
    required this.id,
    required this.username,
    required this.name,
    required this.email,
  });

  final int id;
  final String username;
  final String? name;
  final String? email;

  factory KanboardUser.fromJson(Map<String, dynamic> json) {
    return KanboardUser(
      id: parseKanboardInt(json['id']),
      username: json['username']?.toString() ?? '',
      name: json['name']?.toString(),
      email: json['email']?.toString(),
    );
  }
}

class KanboardProject {
  const KanboardProject({
    required this.id,
    required this.name,
    this.description,
    this.identifier,
    this.isActive = true,
    this.uiColorHex,
    this.uiProjectType,
  });

  final int id;
  final String name;
  final String? description;
  final String? identifier;
  final bool isActive;
  final String? uiColorHex;
  final String? uiProjectType;

  factory KanboardProject.fromJson(Map<String, dynamic> json) {
    return KanboardProject(
      id: parseKanboardInt(json['id']),
      name: json['name']?.toString() ?? 'Untitled',
      description: json['description']?.toString(),
      identifier: json['identifier']?.toString(),
      isActive: parseKanboardInt(json['is_active'], 1) == 1,
      uiColorHex: json['ui_color_hex']?.toString(),
      uiProjectType: parseKanboardString(json['ui_project_type']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'identifier': identifier,
    'is_active': isActive ? 1 : 0,
    'ui_color_hex': uiColorHex,
    'ui_project_type': uiProjectType,
  };

  KanboardProject copyWith({
    String? name,
    String? description,
    String? identifier,
    bool? isActive,
    String? uiColorHex,
    String? uiProjectType,
    bool clearUiColorHex = false,
    bool clearUiProjectType = false,
  }) {
    return KanboardProject(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      identifier: identifier ?? this.identifier,
      isActive: isActive ?? this.isActive,
      uiColorHex: clearUiColorHex ? null : (uiColorHex ?? this.uiColorHex),
      uiProjectType: clearUiProjectType
          ? null
          : (uiProjectType ?? this.uiProjectType),
    );
  }
}

class KanboardTask {
  const KanboardTask({
    required this.id,
    required this.projectId,
    required this.columnId,
    required this.swimlaneId,
    required this.position,
    required this.title,
    this.description,
    this.ownerId = 0,
    this.creatorId = 0,
    this.isActive = true,
    this.priority = 0,
    this.score = 0,
    this.dateDueRaw,
    this.timeEstimated = 0,
    this.timeSpent = 0,
    this.colorId,
  });

  final int id;
  final int projectId;
  final int columnId;
  final int swimlaneId;
  final int position;
  final String title;
  final String? description;
  final int ownerId;
  final int creatorId;
  final bool isActive;
  final int priority;
  final int score;
  final String? dateDueRaw;
  final double timeEstimated;
  final double timeSpent;
  final String? colorId;

  String? get dateDueForInput {
    final raw = dateDueRaw;
    if (raw == null || raw == '0') return null;
    final unix = int.tryParse(raw);
    if (unix == null || unix <= 0) return raw;
    final dateTime = DateTime.fromMillisecondsSinceEpoch(unix * 1000).toLocal();
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '${dateTime.year}-$month-$day $hour:$minute';
  }

  factory KanboardTask.fromJson(Map<String, dynamic> json) {
    return KanboardTask(
      id: parseKanboardInt(json['id']),
      projectId: parseKanboardInt(json['project_id']),
      columnId: parseKanboardInt(json['column_id']),
      swimlaneId: parseKanboardInt(json['swimlane_id']),
      position: parseKanboardInt(json['position'], 1),
      title: json['title']?.toString() ?? 'Untitled task',
      description: json['description']?.toString(),
      ownerId: parseKanboardInt(json['owner_id']),
      creatorId: parseKanboardInt(json['creator_id']),
      isActive: parseKanboardInt(json['is_active'], 1) == 1,
      priority: parseKanboardInt(json['priority']),
      score: parseKanboardInt(json['score']),
      dateDueRaw: parseKanboardString(json['date_due']),
      timeEstimated: parseKanboardDouble(json['time_estimated']),
      timeSpent: parseKanboardDouble(json['time_spent']),
      colorId: parseKanboardString(json['color_id']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'project_id': projectId,
    'column_id': columnId,
    'swimlane_id': swimlaneId,
    'position': position,
    'title': title,
    'description': description,
    'owner_id': ownerId,
    'creator_id': creatorId,
    'is_active': isActive ? 1 : 0,
    'priority': priority,
    'score': score,
    'date_due': dateDueRaw,
    'time_estimated': timeEstimated,
    'time_spent': timeSpent,
    'color_id': colorId,
  };
}

class KanboardUserReference {
  const KanboardUserReference({
    required this.id,
    required this.name,
    required this.username,
  });

  final int id;
  final String name;
  final String username;

  String get displayName => name.isNotEmpty ? name : username;

  factory KanboardUserReference.fromJson(Map<String, dynamic> json) {
    return KanboardUserReference(
      id: parseKanboardInt(json['id']),
      name: parseKanboardString(json['name']) ?? '',
      username: parseKanboardString(json['username']) ?? '',
    );
  }
}

class KanboardProjectPermission {
  const KanboardProjectPermission({
    required this.userId,
    required this.username,
    this.name,
    this.role,
  });

  final int userId;
  final String username;
  final String? name;
  final String? role;

  String get displayName {
    final trimmedName = name?.trim() ?? '';
    if (trimmedName.isNotEmpty) return trimmedName;
    final trimmedUsername = username.trim();
    if (trimmedUsername.isNotEmpty) return trimmedUsername;
    return 'User #$userId';
  }

  factory KanboardProjectPermission.fromJson(Map<String, dynamic> json) {
    final resolvedUserId = parseKanboardInt(
      json['user_id'] ?? json['id'] ?? json['userId'],
    );
    return KanboardProjectPermission(
      userId: resolvedUserId,
      username:
          parseKanboardString(json['username']) ??
          parseKanboardString(json['user_name']) ??
          '',
      name:
          parseKanboardString(json['name']) ??
          parseKanboardString(json['fullname']),
      role:
          parseKanboardString(json['role']) ??
          parseKanboardString(json['role_name']),
    );
  }
}

class KanboardTaskFile {
  const KanboardTaskFile({
    required this.id,
    required this.taskId,
    required this.projectId,
    required this.name,
    required this.size,
    this.userId = 0,
    this.dateCreation = 0,
  });

  final int id;
  final int taskId;
  final int projectId;
  final String name;
  final int size;
  final int userId;
  final int dateCreation;

  String get sizeLabel {
    if (size < 1024) return '$size B';
    final kb = size / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  factory KanboardTaskFile.fromJson(Map<String, dynamic> json) {
    return KanboardTaskFile(
      id: parseKanboardInt(json['id']),
      taskId: parseKanboardInt(json['task_id']),
      projectId: parseKanboardInt(json['project_id']),
      name: parseKanboardString(json['name']) ?? 'file',
      size: parseKanboardInt(json['size']),
      userId: parseKanboardInt(json['user_id']),
      dateCreation: parseKanboardInt(json['date_creation'] ?? json['date']),
    );
  }
}

class KanboardProjectFile {
  const KanboardProjectFile({
    required this.id,
    required this.projectId,
    required this.name,
    required this.size,
    this.userId = 0,
    this.dateCreation = 0,
  });

  final int id;
  final int projectId;
  final String name;
  final int size;
  final int userId;
  final int dateCreation;

  String get sizeLabel {
    if (size < 1024) return '$size B';
    final kb = size / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  factory KanboardProjectFile.fromJson(Map<String, dynamic> json) {
    return KanboardProjectFile(
      id: parseKanboardInt(json['id']),
      projectId: parseKanboardInt(json['project_id']),
      name: parseKanboardString(json['name']) ?? 'file',
      size: parseKanboardInt(json['size']),
      userId: parseKanboardInt(json['user_id']),
      dateCreation: parseKanboardInt(json['date_creation'] ?? json['date']),
    );
  }
}

class KanboardComment {
  const KanboardComment({
    required this.id,
    required this.taskId,
    required this.comment,
    this.userId = 0,
    this.username,
    this.dateCreation = 0,
    this.dateModification = 0,
  });

  final int id;
  final int taskId;
  final String comment;
  final int userId;
  final String? username;
  final int dateCreation;
  final int dateModification;

  factory KanboardComment.fromJson(Map<String, dynamic> json) {
    return KanboardComment(
      id: parseKanboardInt(json['id']),
      taskId: parseKanboardInt(json['task_id']),
      comment: parseKanboardString(json['comment']) ?? '',
      userId: parseKanboardInt(json['user_id']),
      username: parseKanboardString(json['username']),
      dateCreation: parseKanboardInt(json['date_creation']),
      dateModification: parseKanboardInt(json['date_modification']),
    );
  }
}

class KanboardSubtask {
  const KanboardSubtask({
    required this.id,
    required this.taskId,
    required this.title,
    this.userId = 0,
    this.status = 0,
    this.position = 0,
    this.timeEstimated = 0,
    this.timeSpent = 0,
  });

  final int id;
  final int taskId;
  final String title;
  final int userId;
  final int status;
  final int position;
  final double timeEstimated;
  final double timeSpent;

  bool get isDone => status == 1;

  factory KanboardSubtask.fromJson(Map<String, dynamic> json) {
    return KanboardSubtask(
      id: parseKanboardInt(json['id']),
      taskId: parseKanboardInt(json['task_id']),
      title: parseKanboardString(json['title']) ?? 'Subtask',
      userId: parseKanboardInt(json['user_id']),
      status: parseKanboardInt(json['status']),
      position: parseKanboardInt(json['position']),
      timeEstimated: parseKanboardDouble(json['time_estimated']),
      timeSpent: parseKanboardDouble(json['time_spent']),
    );
  }
}

class KanboardTag {
  const KanboardTag({required this.id, required this.name, this.color});

  final int id;
  final String name;
  final String? color;

  factory KanboardTag.fromJson(Map<String, dynamic> json) {
    return KanboardTag(
      id: parseKanboardInt(json['id']),
      name: parseKanboardString(json['name']) ?? '',
      color: parseKanboardString(json['color']),
    );
  }
}

class KanboardTaskLinkType {
  const KanboardTaskLinkType({
    required this.id,
    required this.label,
    this.oppositeLabel,
  });

  final int id;
  final String label;
  final String? oppositeLabel;

  factory KanboardTaskLinkType.fromJson(Map<String, dynamic> json) {
    return KanboardTaskLinkType(
      id: parseKanboardInt(json['id']),
      label: parseKanboardString(json['label']) ?? 'linked to',
      oppositeLabel: parseKanboardString(json['opposite_label']),
    );
  }
}

class KanboardTaskLink {
  const KanboardTaskLink({
    required this.id,
    required this.taskId,
    required this.oppositeTaskId,
    required this.linkId,
    this.label,
    this.oppositeLabel,
    this.oppositeTaskTitle,
  });

  final int id;
  final int taskId;
  final int oppositeTaskId;
  final int linkId;
  final String? label;
  final String? oppositeLabel;
  final String? oppositeTaskTitle;

  factory KanboardTaskLink.fromJson(Map<String, dynamic> json) {
    return KanboardTaskLink(
      id: parseKanboardInt(json['id']),
      taskId: parseKanboardInt(json['task_id']),
      oppositeTaskId: parseKanboardInt(json['opposite_task_id']),
      linkId: parseKanboardInt(json['link_id']),
      label: parseKanboardString(json['label']),
      oppositeLabel: parseKanboardString(json['opposite_label']),
      oppositeTaskTitle: parseKanboardString(json['title']),
    );
  }
}

class KanboardExternalTaskLink {
  const KanboardExternalTaskLink({
    required this.id,
    required this.taskId,
    required this.title,
    required this.url,
    this.linkType,
    this.dependency,
  });

  final int id;
  final int taskId;
  final String title;
  final String url;
  final String? linkType;
  final String? dependency;

  factory KanboardExternalTaskLink.fromJson(Map<String, dynamic> json) {
    return KanboardExternalTaskLink(
      id: parseKanboardInt(json['id']),
      taskId: parseKanboardInt(json['task_id']),
      title: parseKanboardString(json['title']) ?? 'External link',
      url: parseKanboardString(json['url']) ?? '',
      linkType: parseKanboardString(json['link_type']),
      dependency: parseKanboardString(json['dependency']),
    );
  }
}

class KanboardColumn {
  const KanboardColumn({
    required this.id,
    required this.projectId,
    required this.title,
    required this.position,
    this.taskLimit = 0,
    this.description,
    this.tasks = const [],
  });

  final int id;
  final int projectId;
  final String title;
  final int position;
  final int taskLimit;
  final String? description;
  final List<KanboardTask> tasks;

  factory KanboardColumn.fromJson(Map<String, dynamic> json) {
    final rawTasks = (json['tasks'] as List<dynamic>? ?? <dynamic>[]);
    return KanboardColumn(
      id: parseKanboardInt(json['id']),
      projectId: parseKanboardInt(json['project_id']),
      title: json['title']?.toString() ?? 'Column',
      position: parseKanboardInt(json['position'], 1),
      taskLimit: parseKanboardInt(json['task_limit']),
      description: json['description']?.toString(),
      tasks:
          rawTasks
              .map((e) => KanboardTask.fromJson(e as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => a.position.compareTo(b.position)),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'project_id': projectId,
    'title': title,
    'position': position,
    'task_limit': taskLimit,
    'description': description,
    'tasks': tasks.map((t) => t.toJson()).toList(),
  };
}

class KanboardSwimlane {
  const KanboardSwimlane({
    required this.id,
    required this.name,
    required this.columns,
    this.position = 0,
    this.isActive = true,
    this.projectId = 0,
  });

  final int id;
  final String name;
  final List<KanboardColumn> columns;
  final int position;
  final bool isActive;
  final int projectId;

  factory KanboardSwimlane.fromBoardJson(Map<String, dynamic> json) {
    final rawColumns = (json['columns'] as List<dynamic>? ?? <dynamic>[]);
    return KanboardSwimlane(
      id: parseKanboardInt(json['id']),
      name: json['name']?.toString() ?? 'Swimlane',
      columns:
          rawColumns
              .map((e) => KanboardColumn.fromJson(e as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => a.position.compareTo(b.position)),
      position: parseKanboardInt(json['position']),
      isActive: parseKanboardInt(json['is_active'], 1) == 1,
      projectId: parseKanboardInt(json['project_id']),
    );
  }

  factory KanboardSwimlane.fromJson(Map<String, dynamic> json) {
    return KanboardSwimlane(
      id: parseKanboardInt(json['id']),
      name: json['name']?.toString() ?? 'Swimlane',
      columns: const [],
      position: parseKanboardInt(json['position']),
      isActive: parseKanboardInt(json['is_active'], 1) == 1,
      projectId: parseKanboardInt(json['project_id']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'columns': columns.map((c) => c.toJson()).toList(),
    'position': position,
    'is_active': isActive ? 1 : 0,
    'project_id': projectId,
  };
}

class KanboardBoard {
  const KanboardBoard({required this.projectId, required this.swimlanes});

  final int projectId;
  final List<KanboardSwimlane> swimlanes;

  factory KanboardBoard.fromJson(int projectId, List<dynamic> result) {
    return KanboardBoard(
      projectId: projectId,
      swimlanes: result
          .map((e) => KanboardSwimlane.fromBoardJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'project_id': projectId,
    'swimlanes': swimlanes.map((s) => s.toJson()).toList(),
  };

  factory KanboardBoard.fromCachedJson(Map<String, dynamic> json) {
    final rawSwimlanes = json['swimlanes'] as List<dynamic>? ?? <dynamic>[];
    return KanboardBoard(
      projectId: parseKanboardInt(json['project_id']),
      swimlanes: rawSwimlanes
          .map((e) => KanboardSwimlane.fromBoardJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
