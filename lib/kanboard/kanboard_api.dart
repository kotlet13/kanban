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
    final projects = list
        .map((e) => KanboardProject.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

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
    final result =
        await _client.call('removeProject', <String, dynamic>{'project_id': projectId});
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
    final result = await _client.call('getProjectMetadataByName', <String, dynamic>{
      'project_id': projectId,
      'name': name,
    });
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
    final result = await _client.call('removeProjectMetadata', <String, dynamic>{
      'project_id': projectId,
      'name': name,
    });
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
      // API allows description but in most versions not in positional example.
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
    final result =
        await _client.call('changeColumnPosition', <int>[projectId, columnId, position]);
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
    final result = await _client.call('removeSwimlane', <int>[projectId, swimlaneId]);
    return result == true;
  }

  Future<bool> changeSwimlanePosition({
    required int projectId,
    required int swimlaneId,
    required int position,
  }) async {
    final result = await _client.call(
      'changeSwimlanePosition',
      <int>[projectId, swimlaneId, position],
    );
    return result == true;
  }

  Future<KanboardTask?> getTask(int taskId) async {
    final result = await _client.call('getTask', <String, dynamic>{'task_id': taskId});
    if (result == null) return null;
    return KanboardTask.fromJson(result as Map<String, dynamic>);
  }

  Future<int?> createTask({
    required int projectId,
    required String title,
    String? description,
    int? columnId,
    int? swimlaneId,
  }) async {
    final result = await _client.call('createTask', <String, dynamic>{
      'project_id': projectId,
      'title': title,
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
      if (columnId != null) 'column_id': columnId,
      if (swimlaneId != null) 'swimlane_id': swimlaneId,
    });
    return result == false ? null : parseKanboardInt(result, -1);
  }

  Future<bool> updateTask({
    required int id,
    String? title,
    String? description,
  }) async {
    final result = await _client.call('updateTask', <String, dynamic>{
      'id': id,
      if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      if (description != null) 'description': description,
    });
    return result == true;
  }

  Future<bool> removeTask(int taskId) async {
    final result = await _client.call('removeTask', <String, dynamic>{
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
