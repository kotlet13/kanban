int parseKanboardInt(dynamic value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

class KanboardCredentials {
  const KanboardCredentials({
    required this.serverUrl,
    required this.username,
    required this.token,
  });

  final String serverUrl;
  final String username;
  final String token;

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
  });

  final int id;
  final String name;
  final String? description;
  final String? identifier;
  final bool isActive;
  final String? uiColorHex;

  factory KanboardProject.fromJson(Map<String, dynamic> json) {
    return KanboardProject(
      id: parseKanboardInt(json['id']),
      name: json['name']?.toString() ?? 'Untitled',
      description: json['description']?.toString(),
      identifier: json['identifier']?.toString(),
      isActive: parseKanboardInt(json['is_active'], 1) == 1,
      uiColorHex: json['ui_color_hex']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'identifier': identifier,
        'is_active': isActive ? 1 : 0,
        'ui_color_hex': uiColorHex,
      };

  KanboardProject copyWith({
    String? name,
    String? description,
    String? identifier,
    bool? isActive,
    String? uiColorHex,
    bool clearUiColorHex = false,
  }) {
    return KanboardProject(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      identifier: identifier ?? this.identifier,
      isActive: isActive ?? this.isActive,
      uiColorHex: clearUiColorHex ? null : (uiColorHex ?? this.uiColorHex),
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
  });

  final int id;
  final int projectId;
  final int columnId;
  final int swimlaneId;
  final int position;
  final String title;
  final String? description;

  factory KanboardTask.fromJson(Map<String, dynamic> json) {
    return KanboardTask(
      id: parseKanboardInt(json['id']),
      projectId: parseKanboardInt(json['project_id']),
      columnId: parseKanboardInt(json['column_id']),
      swimlaneId: parseKanboardInt(json['swimlane_id']),
      position: parseKanboardInt(json['position'], 1),
      title: json['title']?.toString() ?? 'Untitled task',
      description: json['description']?.toString(),
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
      };
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
      tasks: rawTasks
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
      columns: rawColumns
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
  const KanboardBoard({
    required this.projectId,
    required this.swimlanes,
  });

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
