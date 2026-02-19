import '../models/kanboard_models.dart';
import 'jsonrpc_client.dart';

class KanboardApi {
  KanboardApi(this._client);

  final JsonRpcClient _client;
  static const String projectColorMetadataKey = 'ui_project_color';

  factory KanboardApi.fromCredentials(KanboardCredentials credentials) {
    return KanboardApi(
      JsonRpcClient(
        endpoint: Uri.parse(credentials.normalizedEndpoint),
        username: credentials.username,
        password: credentials.token,
      ),
    );
  }

  Future<String> getVersion() async {
    final result = await _client.call('getVersion');
    return result?.toString() ?? '';
  }

  Future<KanboardUser> getMe() async {
    final result = await _client.call('getMe');
    return KanboardUser.fromJson(result as Map<String, dynamic>);
  }

  Future<List<KanboardProject>> getMyProjects() async {
    final result = await _client.call('getMyProjects');
    final list = (result as List<dynamic>? ?? <dynamic>[]);
    final projects =
        list
            .map((e) => KanboardProject.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );

    final colors = await Future.wait<String?>(
      projects.map((project) async {
        try {
          final color = await getProjectMetadataByName(
            projectId: project.id,
            name: projectColorMetadataKey,
          );
          return _normalizeColorHex(color);
        } catch (_) {
          return null;
        }
      }),
    );

    return List<KanboardProject>.generate(projects.length, (index) {
      return projects[index].copyWith(uiColorHex: colors[index]);
    });
  }

  Future<int?> createProject({
    required String name,
    String? description,
  }) async {
    final result = await _client.call('createProject', <String, dynamic>{
      'name': name,
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
    });
    return result == false ? null : parseKanboardInt(result, -1);
  }

  Future<bool> updateProject({
    required int projectId,
    String? name,
    String? description,
  }) async {
    final result = await _client.call('updateProject', <String, dynamic>{
      'project_id': projectId,
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (description != null) 'description': description,
    });
    return result == true;
  }

  Future<bool> removeProject(int projectId) async {
    final result = await _client.call('removeProject', <String, dynamic>{
      'project_id': projectId,
    });
    return result == true;
  }

  Future<Map<String, dynamic>> getProjectMetadata(int projectId) async {
    final result = await _client.call('getProjectMetadata', <String, dynamic>{
      'project_id': projectId,
    });
    return (result as Map<String, dynamic>? ?? <String, dynamic>{});
  }

  Future<String?> getProjectMetadataByName({
    required int projectId,
    required String name,
  }) async {
    final result = await _client.call(
      'getProjectMetadataByName',
      <String, dynamic>{'project_id': projectId, 'name': name},
    );
    final text = result?.toString();
    if (text == null || text.trim().isEmpty) return null;
    return text;
  }

  Future<bool> saveProjectMetadata({
    required int projectId,
    required Map<String, String> values,
  }) async {
    final result = await _client.call('saveProjectMetadata', <String, dynamic>{
      'project_id': projectId,
      'values': values,
    });
    return result == true;
  }

  Future<bool> removeProjectMetadata({
    required int projectId,
    required String name,
  }) async {
    final result = await _client.call(
      'removeProjectMetadata',
      <String, dynamic>{'project_id': projectId, 'name': name},
    );
    return result == true;
  }

  Future<bool> saveProjectColorHex({
    required int projectId,
    String? colorHex,
  }) async {
    final normalized = _normalizeColorHex(colorHex);
    if (normalized == null) {
      return removeProjectMetadata(
        projectId: projectId,
        name: projectColorMetadataKey,
      );
    }

    return saveProjectMetadata(
      projectId: projectId,
      values: <String, String>{projectColorMetadataKey: normalized},
    );
  }

  Future<KanboardBoard> getBoard(int projectId) async {
    final result = await _client.call('getBoard', <int>[projectId]);
    return KanboardBoard.fromJson(projectId, result as List<dynamic>);
  }

  Future<List<KanboardColumn>> getColumns(int projectId) async {
    final result = await _client.call('getColumns', <int>[projectId]);
    final list = (result as List<dynamic>? ?? <dynamic>[]);
    return list
        .map((e) => KanboardColumn.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));
  }

  Future<int?> addColumn({
    required int projectId,
    required String title,
    int? taskLimit,
    String? description,
  }) async {
    final params = <dynamic>[projectId, title];
    if (taskLimit != null) params.add(taskLimit);
    final result = await _client.call('addColumn', params);
    if (result == false) return null;
    if (description != null && description.isNotEmpty) {
      final createdId = parseKanboardInt(result, -1);
      if (createdId > 0) {
        await updateColumn(
          columnId: createdId,
          title: title,
          taskLimit: taskLimit,
          description: description,
        );
      }
    }
    return parseKanboardInt(result, -1);
  }

  Future<bool> updateColumn({
    required int columnId,
    required String title,
    int? taskLimit,
    String? description,
  }) async {
    final params = <dynamic>[columnId, title];
    if (taskLimit != null) params.add(taskLimit);
    final result = await _client.call('updateColumn', params);
    if (result != true) return false;
    if (description != null && description.isNotEmpty) {
      await _client.call('updateColumn', <String, dynamic>{
        'column_id': columnId,
        'title': title,
        if (taskLimit != null) 'task_limit': taskLimit,
        'description': description,
      });
    }
    return true;
  }

  Future<bool> removeColumn(int columnId) async {
    final result = await _client.call('removeColumn', <int>[columnId]);
    return result == true;
  }

  Future<bool> changeColumnPosition({
    required int projectId,
    required int columnId,
    required int position,
  }) async {
    final result = await _client.call('changeColumnPosition', <int>[
      projectId,
      columnId,
      position,
    ]);
    return result == true;
  }

  Future<List<KanboardSwimlane>> getAllSwimlanes(int projectId) async {
    final result = await _client.call('getAllSwimlanes', <int>[projectId]);
    final list = (result as List<dynamic>? ?? <dynamic>[]);
    return list
        .map((e) => KanboardSwimlane.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));
  }

  Future<int?> addSwimlane({
    required int projectId,
    required String name,
    String? description,
  }) async {
    final params = <dynamic>[projectId, name];
    if (description != null && description.isNotEmpty) params.add(description);
    final result = await _client.call('addSwimlane', params);
    return result == false ? null : parseKanboardInt(result, -1);
  }

  Future<bool> updateSwimlane({
    required int projectId,
    required int swimlaneId,
    required String name,
    String? description,
  }) async {
    final params = <dynamic>[projectId, swimlaneId, name];
    if (description != null && description.isNotEmpty) params.add(description);
    final result = await _client.call('updateSwimlane', params);
    return result == true;
  }

  Future<bool> removeSwimlane({
    required int projectId,
    required int swimlaneId,
  }) async {
    final result = await _client.call('removeSwimlane', <int>[
      projectId,
      swimlaneId,
    ]);
    return result == true;
  }

  Future<bool> changeSwimlanePosition({
    required int projectId,
    required int swimlaneId,
    required int position,
  }) async {
    final result = await _client.call('changeSwimlanePosition', <int>[
      projectId,
      swimlaneId,
      position,
    ]);
    return result == true;
  }

  Future<KanboardTask?> getTask(int taskId) async {
    final result = await _client.call('getTask', <String, dynamic>{
      'task_id': taskId,
    });
    if (result == null) return null;
    return KanboardTask.fromJson(result as Map<String, dynamic>);
  }

  Future<List<KanboardTask>> searchTasks({
    required int projectId,
    required String query,
  }) async {
    final result = await _client.call('searchTasks', <String, dynamic>{
      'project_id': projectId,
      'query': query,
    });
    if (result is List<dynamic>) {
      return result
          .whereType<Map<String, dynamic>>()
          .map(KanboardTask.fromJson)
          .toList();
    }
    if (result is Map<String, dynamic>) {
      final tasks = result['tasks'] as List<dynamic>? ?? <dynamic>[];
      return tasks
          .whereType<Map<String, dynamic>>()
          .map(KanboardTask.fromJson)
          .toList();
    }
    return const <KanboardTask>[];
  }

  Future<List<KanboardUserReference>> getAssignableUsers(int projectId) async {
    final result = await _client.call('getAssignableUsers', <String, dynamic>{
      'project_id': projectId,
    });
    final users = <KanboardUserReference>[];
    if (result is List<dynamic>) {
      for (final item in result) {
        if (item is Map<String, dynamic>) {
          users.add(KanboardUserReference.fromJson(item));
        }
      }
    } else if (result is Map<String, dynamic>) {
      result.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          users.add(
            KanboardUserReference.fromJson(<String, dynamic>{
              ...value,
              if (value['id'] == null) 'id': key,
            }),
          );
        } else {
          users.add(
            KanboardUserReference(
              id: int.tryParse(key) ?? 0,
              name: value?.toString() ?? '',
              username: value?.toString() ?? '',
            ),
          );
        }
      });
    }
    users.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return users;
  }

  Future<int?> createTask({
    required int projectId,
    required String title,
    String? description,
    int? columnId,
    int? swimlaneId,
    int? ownerId,
    String? dateDue,
    int? priority,
    int? score,
  }) async {
    final result = await _client.call('createTask', <String, dynamic>{
      'project_id': projectId,
      'title': title,
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
      if (columnId != null) 'column_id': columnId,
      if (swimlaneId != null) 'swimlane_id': swimlaneId,
      if (ownerId != null && ownerId > 0) 'owner_id': ownerId,
      if (dateDue != null && dateDue.trim().isNotEmpty)
        'date_due': dateDue.trim(),
      if (priority != null) 'priority': priority,
      if (score != null) 'score': score,
    });
    return result == false ? null : parseKanboardInt(result, -1);
  }

  Future<bool> updateTask({
    required int id,
    String? title,
    String? description,
    int? ownerId,
    String? dateDue,
    int? priority,
    int? score,
    bool clearDateDue = false,
  }) async {
    final result = await _client.call('updateTask', <String, dynamic>{
      'id': id,
      if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      if (description != null) 'description': description,
      if (ownerId != null) 'owner_id': ownerId,
      if (dateDue != null && dateDue.trim().isNotEmpty)
        'date_due': dateDue.trim(),
      if (clearDateDue) 'date_due': 0,
      if (priority != null) 'priority': priority,
      if (score != null) 'score': score,
    });
    return result == true;
  }

  Future<bool> removeTask(int taskId) async {
    final result = await _client.call('removeTask', <String, dynamic>{
      'task_id': taskId,
    });
    return result == true;
  }

  Future<bool> closeTask(int taskId) async {
    final result = await _client.call('closeTask', <String, dynamic>{
      'task_id': taskId,
    });
    return result == true;
  }

  Future<bool> openTask(int taskId) async {
    final result = await _client.call('openTask', <String, dynamic>{
      'task_id': taskId,
    });
    return result == true;
  }

  Future<bool> moveTaskPosition({
    required int projectId,
    required int taskId,
    required int columnId,
    required int position,
    required int swimlaneId,
  }) async {
    final result = await _client.call('moveTaskPosition', <String, dynamic>{
      'project_id': projectId,
      'task_id': taskId,
      'column_id': columnId,
      'position': position,
      'swimlane_id': swimlaneId,
    });
    return result == true;
  }

  Future<List<KanboardTaskFile>> getAllTaskFiles(int taskId) async {
    final result = await _client.call('getAllTaskFiles', <String, dynamic>{
      'task_id': taskId,
    });
    return _toListOfMaps(result).map(KanboardTaskFile.fromJson).toList();
  }

  Future<int?> createTaskFile({
    required int projectId,
    required int taskId,
    required String filename,
    required String contentBase64,
  }) async {
    final payloadVariants = <Object>[
      <dynamic>[projectId, taskId, filename, contentBase64],
      <String, dynamic>{
        'project_id': projectId,
        'task_id': taskId,
        'filename': filename,
        'blob': contentBase64,
      },
      <dynamic>[taskId, filename, contentBase64],
      <String, dynamic>{
        'task_id': taskId,
        'filename': filename,
        'blob': contentBase64,
      },
    ];

    JsonRpcException? lastError;
    for (final params in payloadVariants) {
      try {
        final result = await _client.call('createTaskFile', params);
        if (result == false) {
          return null;
        }
        final parsed = parseKanboardInt(result, -1);
        return parsed > 0 ? parsed : null;
      } on JsonRpcException catch (error) {
        lastError = error;
      }
    }

    if (lastError != null) {
      throw lastError;
    }
    return null;
  }

  Future<String?> downloadTaskFile(int fileId) async {
    final result = await _client.call('downloadTaskFile', <String, dynamic>{
      'file_id': fileId,
    });
    final text = result?.toString();
    return text == null || text.isEmpty ? null : text;
  }

  Future<bool> removeTaskFile(int fileId) async {
    final result = await _client.call('removeTaskFile', <String, dynamic>{
      'file_id': fileId,
    });
    return result == true;
  }

  Future<List<KanboardProjectFile>> getAllProjectFiles(int projectId) async {
    final result = await _client.call('getAllProjectFiles', <String, dynamic>{
      'project_id': projectId,
    });
    return _toListOfMaps(result).map(KanboardProjectFile.fromJson).toList();
  }

  Future<int?> createProjectFile({
    required int projectId,
    required String filename,
    required String contentBase64,
  }) async {
    dynamic result;
    try {
      result = await _client.call('createProjectFile', <dynamic>[
        projectId,
        filename,
        contentBase64,
      ]);
    } on JsonRpcException {
      result = await _client.call('createProjectFile', <String, dynamic>{
        'project_id': projectId,
        'filename': filename,
        'blob': contentBase64,
      });
    }
    return result == false ? null : parseKanboardInt(result, -1);
  }

  Future<String?> downloadProjectFile(int fileId) async {
    final result = await _client.call('downloadProjectFile', <String, dynamic>{
      'file_id': fileId,
    });
    final text = result?.toString();
    return text == null || text.isEmpty ? null : text;
  }

  Future<bool> removeProjectFile(int fileId) async {
    final result = await _client.call('removeProjectFile', <String, dynamic>{
      'file_id': fileId,
    });
    return result == true;
  }

  Future<List<KanboardComment>> getAllComments(int taskId) async {
    final result = await _client.call('getAllComments', <String, dynamic>{
      'task_id': taskId,
    });
    final comments = _toListOfMaps(
      result,
    ).map(KanboardComment.fromJson).toList();
    comments.sort((a, b) => a.dateCreation.compareTo(b.dateCreation));
    return comments;
  }

  Future<int?> createComment({
    required int taskId,
    required String comment,
  }) async {
    final result = await _client.call('createComment', <String, dynamic>{
      'task_id': taskId,
      'comment': comment,
    });
    return result == false ? null : parseKanboardInt(result, -1);
  }

  Future<bool> updateComment({
    required int commentId,
    required String comment,
  }) async {
    final result = await _client.call('updateComment', <String, dynamic>{
      'id': commentId,
      'comment': comment,
    });
    return result == true;
  }

  Future<bool> removeComment(int commentId) async {
    final result = await _client.call('removeComment', <String, dynamic>{
      'comment_id': commentId,
    });
    return result == true;
  }

  Future<List<KanboardSubtask>> getAllSubtasks(int taskId) async {
    final result = await _client.call('getAllSubtasks', <String, dynamic>{
      'task_id': taskId,
    });
    final subtasks = _toListOfMaps(
      result,
    ).map(KanboardSubtask.fromJson).toList();
    subtasks.sort((a, b) => a.position.compareTo(b.position));
    return subtasks;
  }

  Future<int?> createSubtask({
    required int taskId,
    required String title,
    int? userId,
    double? timeEstimated,
  }) async {
    final result = await _client.call('createSubtask', <String, dynamic>{
      'task_id': taskId,
      'title': title,
      if (userId != null && userId > 0) 'user_id': userId,
      if (timeEstimated != null) 'time_estimated': timeEstimated,
    });
    return result == false ? null : parseKanboardInt(result, -1);
  }

  Future<bool> updateSubtask({
    required int id,
    String? title,
    int? userId,
    int? status,
    double? timeEstimated,
    double? timeSpent,
  }) async {
    final result = await _client.call('updateSubtask', <String, dynamic>{
      'id': id,
      if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      if (userId != null) 'user_id': userId,
      if (status != null) 'status': status,
      if (timeEstimated != null) 'time_estimated': timeEstimated,
      if (timeSpent != null) 'time_spent': timeSpent,
    });
    return result == true;
  }

  Future<bool> removeSubtask(int subtaskId) async {
    final result = await _client.call('removeSubtask', <String, dynamic>{
      'subtask_id': subtaskId,
    });
    return result == true;
  }

  Future<List<KanboardTag>> getTagsByProject(int projectId) async {
    final result = await _client.call('getTagsByProject', <String, dynamic>{
      'project_id': projectId,
    });
    if (result is List<dynamic>) {
      return result
          .whereType<Map<String, dynamic>>()
          .map(KanboardTag.fromJson)
          .toList();
    }
    if (result is Map<String, dynamic>) {
      final tags = <KanboardTag>[];
      result.forEach((key, value) {
        tags.add(
          KanboardTag(
            id: int.tryParse(key) ?? 0,
            name: value?.toString() ?? '',
          ),
        );
      });
      return tags;
    }
    return const <KanboardTag>[];
  }

  Future<List<String>> getTaskTags(int taskId) async {
    final result = await _client.call('getTaskTags', <String, dynamic>{
      'task_id': taskId,
    });
    if (result is List<dynamic>) {
      return result
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (result is Map<String, dynamic>) {
      return result.values
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const <String>[];
  }

  Future<bool> setTaskTags({
    required int taskId,
    required List<String> tags,
  }) async {
    final cleanTags = tags
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final result = await _client.call('setTaskTags', <String, dynamic>{
      'task_id': taskId,
      'tags': cleanTags,
    });
    return result == true;
  }

  Future<List<KanboardTaskLinkType>> getAllLinks() async {
    final result = await _client.call('getAllLinks');
    if (result is List<dynamic>) {
      return result
          .whereType<Map<String, dynamic>>()
          .map(KanboardTaskLinkType.fromJson)
          .toList();
    }
    if (result is Map<String, dynamic>) {
      final linkTypes = <KanboardTaskLinkType>[];
      result.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          linkTypes.add(
            KanboardTaskLinkType.fromJson(<String, dynamic>{
              ...value,
              if (value['id'] == null) 'id': key,
            }),
          );
        } else {
          linkTypes.add(
            KanboardTaskLinkType(
              id: int.tryParse(key) ?? 0,
              label: value?.toString() ?? 'linked to',
            ),
          );
        }
      });
      return linkTypes;
    }
    return const <KanboardTaskLinkType>[];
  }

  Future<List<KanboardTaskLink>> getAllTaskLinks(int taskId) async {
    final result = await _client.call('getAllTaskLinks', <String, dynamic>{
      'task_id': taskId,
    });
    return _toListOfMaps(result).map(KanboardTaskLink.fromJson).toList();
  }

  Future<int?> createTaskLink({
    required int taskId,
    required int oppositeTaskId,
    required int linkId,
  }) async {
    final result = await _client.call('createTaskLink', <String, dynamic>{
      'task_id': taskId,
      'opposite_task_id': oppositeTaskId,
      'link_id': linkId,
    });
    return result == false ? null : parseKanboardInt(result, -1);
  }

  Future<bool> removeTaskLink(int taskLinkId) async {
    final result = await _client.call('removeTaskLink', <String, dynamic>{
      'task_link_id': taskLinkId,
    });
    return result == true;
  }

  Future<Map<String, String>> getExternalTaskLinkTypes() async {
    final result = await _client.call('getExternalTaskLinkTypes');
    if (result is Map<String, dynamic>) {
      return result.map((key, value) => MapEntry(key, value.toString()));
    }
    return const <String, String>{};
  }

  Future<Map<String, String>> getExternalTaskLinkProviderDependencies({
    String provider = 'weblink',
  }) async {
    dynamic result;
    try {
      result = await _client.call(
        'getExternalTaskLinkProviderDependencies',
        <String, dynamic>{'providerName': provider},
      );
    } on JsonRpcException catch (error) {
      final requiresOldParam =
          error.code == -32602 &&
          error.message.toLowerCase().contains('missing argument: provider');
      if (!requiresOldParam) rethrow;
      result = await _client.call(
        'getExternalTaskLinkProviderDependencies',
        <String, dynamic>{'provider': provider},
      );
    }
    if (result is Map<String, dynamic>) {
      return result.map((key, value) => MapEntry(key, value.toString()));
    }
    return const <String, String>{};
  }

  Future<List<KanboardExternalTaskLink>> getAllExternalTaskLinks(
    int taskId,
  ) async {
    final result = await _client.call(
      'getAllExternalTaskLinks',
      <String, dynamic>{'task_id': taskId},
    );
    return _toListOfMaps(
      result,
    ).map(KanboardExternalTaskLink.fromJson).toList();
  }

  Future<int?> createExternalTaskLink({
    required int taskId,
    required String url,
    required String title,
    required String linkType,
    required String dependency,
    String provider = 'weblink',
  }) async {
    dynamic result;
    try {
      result = await _client.call('createExternalTaskLink', <String, dynamic>{
        'task_id': taskId,
        'url': url,
        'title': title,
        'link_type': linkType,
        'dependency': dependency,
        'providerName': provider,
      });
    } on JsonRpcException catch (error) {
      final requiresOldParam =
          error.code == -32602 &&
          error.message.toLowerCase().contains('missing argument: provider');
      if (!requiresOldParam) rethrow;
      result = await _client.call('createExternalTaskLink', <String, dynamic>{
        'task_id': taskId,
        'url': url,
        'title': title,
        'link_type': linkType,
        'dependency': dependency,
        'provider': provider,
      });
    }
    return result == false ? null : parseKanboardInt(result, -1);
  }

  Future<bool> removeExternalTaskLink({
    required int taskId,
    required int linkId,
  }) async {
    final result = await _client.call(
      'removeExternalTaskLink',
      <String, dynamic>{'task_id': taskId, 'link_id': linkId},
    );
    return result == true;
  }

  List<Map<String, dynamic>> _toListOfMaps(dynamic value) {
    if (value is List<dynamic>) {
      return value.whereType<Map<String, dynamic>>().toList();
    }
    return const <Map<String, dynamic>>[];
  }

  String? _normalizeColorHex(String? value) {
    if (value == null) return null;
    final text = value.trim().toUpperCase();
    if (text.isEmpty) return null;
    final withHash = text.startsWith('#') ? text : '#$text';
    final hex = withHash.substring(1);
    final valid = RegExp(r'^[0-9A-F]{6}$').hasMatch(hex);
    if (!valid) return null;
    return '#$hex';
  }
}
