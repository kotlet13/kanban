import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai/ai_models.dart';
import '../models/kanboard_models.dart';
import 'jsonrpc_client.dart';

class KanboardApi {
  KanboardApi(this._client);

  final JsonRpcClient _client;
  String? _webSessionCookie;
  static const String taskHoursTrackerSubtaskTitle =
      '__APP_TASK_HOURS_TRACKER__';
  static const String projectColorMetadataKey = 'ui_project_color';
  static const String projectTypeMetadataKey = 'ui_project_type';
  static const String financeProjectTypeValue = 'finance';
  static const String expenseCurrencyMetadataKey = 'ui_expense_currency';
  static const String expenseBudgetCentsMetadataKey = 'ui_expense_budget_cents';
  static const String financeTableMetadataKey = 'ui_finance_table_v1';
  static const String _financeTableChunkPrefix = 'ui_finance_table_v1_chunk_';
  static const String _financeTableChunkMarkerPrefix = '@chunked:';
  static const int _financeTableChunkMaxBytes = 220;
  static const String aiEnabledMetadataKey = 'ui_ai_enabled';
  static const String aiKeyModeMetadataKey = 'ui_ai_key_mode';
  static const String aiOwnerUsernameMetadataKey = 'ui_ai_owner_username';

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

    final metadataRows = await Future.wait<(String?, String?)>(
      projects.map((project) async {
        try {
          final metadata = await getProjectMetadata(project.id);
          final color = _normalizeColorHex(
            metadata[projectColorMetadataKey]?.toString(),
          );
          final projectType = metadata[projectTypeMetadataKey]
              ?.toString()
              .trim()
              .toLowerCase();
          return (color, projectType);
        } catch (_) {
          return (null, null);
        }
      }),
    );

    return List<KanboardProject>.generate(projects.length, (index) {
      return projects[index].copyWith(
        uiColorHex: metadataRows[index].$1,
        uiProjectType: metadataRows[index].$2,
      );
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

  Future<bool> saveProjectType({
    required int projectId,
    String? projectType,
  }) async {
    final normalized = projectType?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return removeProjectMetadata(
        projectId: projectId,
        name: projectTypeMetadataKey,
      );
    }
    return saveProjectMetadata(
      projectId: projectId,
      values: <String, String>{projectTypeMetadataKey: normalized},
    );
  }

  Future<String?> getProjectExpenseCurrency(int projectId) async {
    final raw = await getProjectMetadataByName(
      projectId: projectId,
      name: expenseCurrencyMetadataKey,
    );
    return _normalizeCurrency(raw);
  }

  Future<int?> getProjectExpenseBudgetCents(int projectId) async {
    final raw = await getProjectMetadataByName(
      projectId: projectId,
      name: expenseBudgetCentsMetadataKey,
    );
    if (raw == null) return null;
    final parsed = int.tryParse(raw.trim());
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }

  Future<bool> saveProjectExpenseSettings({
    required int projectId,
    required String currency,
    int? budgetCents,
  }) async {
    final normalizedCurrency = _normalizeCurrency(currency);
    if (normalizedCurrency == null) {
      throw ArgumentError.value(
        currency,
        'currency',
        'Currency must be a 3-letter code.',
      );
    }

    final values = <String, String>{
      expenseCurrencyMetadataKey: normalizedCurrency,
    };
    if (budgetCents != null) {
      if (budgetCents < 0) {
        throw ArgumentError.value(
          budgetCents,
          'budgetCents',
          'Budget cannot be negative.',
        );
      }
      values[expenseBudgetCentsMetadataKey] = '$budgetCents';
    }

    final saved = await saveProjectMetadata(
      projectId: projectId,
      values: values,
    );
    if (!saved) return false;
    if (budgetCents == null) {
      await removeProjectMetadata(
        projectId: projectId,
        name: expenseBudgetCentsMetadataKey,
      );
    }
    return true;
  }

  Future<String?> getProjectFinanceTableRaw(int projectId) async {
    final marker = await getProjectMetadataByName(
      projectId: projectId,
      name: financeTableMetadataKey,
    );
    if (marker == null || marker.trim().isEmpty) return null;

    final normalizedMarker = marker.trim();
    if (!normalizedMarker.startsWith(_financeTableChunkMarkerPrefix)) {
      return marker;
    }

    final countText = normalizedMarker.substring(
      _financeTableChunkMarkerPrefix.length,
    );
    final chunkCount = int.tryParse(countText) ?? 0;
    if (chunkCount <= 0) return null;

    final chunks = await Future.wait<String?>(
      List<String>.generate(
        chunkCount,
        (index) => _financeChunkKey(index),
      ).map((key) => getProjectMetadataByName(projectId: projectId, name: key)),
    );
    if (chunks.any((chunk) => chunk == null)) return null;
    return chunks.join();
  }

  Future<Map<String, dynamic>?> getProjectFinanceTableData(
    int projectId,
  ) async {
    final raw = await getProjectFinanceTableRaw(projectId);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<bool> saveProjectFinanceTableRaw({
    required int projectId,
    required String rawJson,
  }) async {
    final normalized = rawJson.trim();
    if (normalized.isEmpty) {
      await removeProjectMetadata(
        projectId: projectId,
        name: financeTableMetadataKey,
      );
      await _removeStaleFinanceChunkKeys(
        projectId: projectId,
        keepKeys: const <String>{},
      );
      return true;
    }

    final rawBytes = utf8.encode(normalized);
    if (rawBytes.length <= _financeTableChunkMaxBytes) {
      final saved = await saveProjectMetadata(
        projectId: projectId,
        values: <String, String>{financeTableMetadataKey: normalized},
      );
      if (!saved) return false;
      await _removeStaleFinanceChunkKeys(
        projectId: projectId,
        keepKeys: const <String>{},
      );
      return true;
    }

    final chunks = _chunkByUtf8Bytes(normalized, _financeTableChunkMaxBytes);
    final values = <String, String>{
      financeTableMetadataKey:
          '$_financeTableChunkMarkerPrefix${chunks.length}',
    };
    for (var index = 0; index < chunks.length; index++) {
      values[_financeChunkKey(index)] = chunks[index];
    }

    final saved = await saveProjectMetadata(
      projectId: projectId,
      values: values,
    );
    if (!saved) return false;
    await _removeStaleFinanceChunkKeys(
      projectId: projectId,
      keepKeys: values.keys
          .where((key) => key.startsWith(_financeTableChunkPrefix))
          .toSet(),
    );
    return true;
  }

  Future<bool> saveProjectFinanceTableData({
    required int projectId,
    required Map<String, dynamic> data,
  }) {
    return saveProjectFinanceTableRaw(
      projectId: projectId,
      rawJson: jsonEncode(data),
    );
  }

  String _financeChunkKey(int index) => '$_financeTableChunkPrefix$index';

  List<String> _chunkByUtf8Bytes(String input, int maxBytes) {
    final chunks = <String>[];
    final buffer = StringBuffer();
    var bufferBytes = 0;

    for (final rune in input.runes) {
      final chunkPart = String.fromCharCode(rune);
      final partBytes = utf8.encode(chunkPart).length;
      if (bufferBytes > 0 && bufferBytes + partBytes > maxBytes) {
        chunks.add(buffer.toString());
        buffer.clear();
        bufferBytes = 0;
      }
      buffer.write(chunkPart);
      bufferBytes += partBytes;
    }
    if (bufferBytes > 0) {
      chunks.add(buffer.toString());
    }
    return chunks;
  }

  Future<void> _removeStaleFinanceChunkKeys({
    required int projectId,
    required Set<String> keepKeys,
  }) async {
    try {
      final metadata = await getProjectMetadata(projectId);
      final chunkKeys = metadata.keys
          .where((key) => key.startsWith(_financeTableChunkPrefix))
          .where((key) => !keepKeys.contains(key))
          .toList();
      for (final key in chunkKeys) {
        await removeProjectMetadata(projectId: projectId, name: key);
      }
    } catch (_) {
      // Ignore cleanup failures; core payload save already succeeded.
    }
  }

  Future<AiProjectPolicy> getProjectAiPolicy(int projectId) async {
    final enabledRaw = await getProjectMetadataByName(
      projectId: projectId,
      name: aiEnabledMetadataKey,
    );
    final keyModeRaw = await getProjectMetadataByName(
      projectId: projectId,
      name: aiKeyModeMetadataKey,
    );
    final ownerUsername = await getProjectMetadataByName(
      projectId: projectId,
      name: aiOwnerUsernameMetadataKey,
    );
    final enabled = (enabledRaw?.trim() ?? '').toLowerCase() == '1';
    final keyMode =
        (keyModeRaw?.trim() ?? '').toLowerCase() == 'user_key_required'
        ? AiKeyMode.userKeyRequired
        : AiKeyMode.ownerKey;
    return AiProjectPolicy(
      enabled: enabled,
      keyMode: keyMode,
      ownerUsername: ownerUsername?.trim().isEmpty == true
          ? null
          : ownerUsername?.trim(),
    );
  }

  Future<bool> saveProjectAiPolicy({
    required int projectId,
    required AiProjectPolicy policy,
  }) async {
    final values = <String, String>{
      aiEnabledMetadataKey: policy.enabled ? '1' : '0',
      aiKeyModeMetadataKey: policy.keyMode == AiKeyMode.userKeyRequired
          ? 'user_key_required'
          : 'owner_key',
    };
    final owner = policy.ownerUsername?.trim();
    if (owner != null && owner.isNotEmpty) {
      values[aiOwnerUsernameMetadataKey] = owner;
    }
    final saved = await saveProjectMetadata(
      projectId: projectId,
      values: values,
    );
    if (!saved) return false;
    if (owner == null || owner.isEmpty) {
      await removeProjectMetadata(
        projectId: projectId,
        name: aiOwnerUsernameMetadataKey,
      );
    }
    return true;
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
    return _toUserReferences(result);
  }

  Future<List<KanboardUserReference>> getAllUsers() async {
    final result = await _client.call('getAllUsers');
    return _toUserReferences(result);
  }

  Future<List<KanboardUserReference>> searchUsersByAutocomplete(
    String query,
  ) async {
    final term = query.trim();
    if (term.isEmpty) return const <KanboardUserReference>[];

    final endpoint = _buildWebControllerUri(
      controller: 'UserAjaxController',
      action: 'autocomplete',
      params: <String, String>{'term': term},
    );

    // Attempt 1: basic-auth request (works on some Kanboard setups).
    final auth = base64Encode(
      utf8.encode('${_client.username}:${_client.password}'),
    );
    final directResponse = await http
        .get(
          endpoint,
          headers: <String, String>{
            'Authorization': 'Basic $auth',
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
          },
        )
        .timeout(const Duration(seconds: 12));
    final directUsers = _decodeAutocompleteUsersOrNull(directResponse.body);
    if (directUsers != null) {
      return _dedupeAndSortUsers(directUsers);
    }

    // Attempt 2: establish a web session and call the same endpoint.
    final viaSession = await _searchUsersViaWebSession(term);
    if (viaSession != null) {
      return _dedupeAndSortUsers(viaSession);
    }

    throw JsonRpcException(
      'Autocomplete returned login/non-JSON response. '
      'Use password login mode or grant API access to list users.',
    );
  }

  Future<List<KanboardProjectPermission>> getProjectUsers(int projectId) async {
    final result = await _client.call('getProjectUsers', <String, dynamic>{
      'project_id': projectId,
    });
    final users = <KanboardProjectPermission>[];
    if (result is List<dynamic>) {
      for (final item in result) {
        if (item is Map<String, dynamic>) {
          users.add(KanboardProjectPermission.fromJson(item));
        }
      }
    } else if (result is Map<String, dynamic>) {
      result.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          users.add(
            KanboardProjectPermission.fromJson(<String, dynamic>{
              ...value,
              if (value['id'] == null && value['user_id'] == null) 'id': key,
            }),
          );
          return;
        }
        final userId = int.tryParse(key) ?? 0;
        final username = value?.toString() ?? '';
        users.add(
          KanboardProjectPermission(
            userId: userId,
            username: username,
            name: username,
          ),
        );
      });
    }
    users.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return users;
  }

  Future<bool> addProjectUser({
    required int projectId,
    required int userId,
    String? role,
  }) async {
    final roleText = role?.trim();
    final payloadVariants = <Object>[
      <String, dynamic>{
        'project_id': projectId,
        'user_id': userId,
        if (roleText != null && roleText.isNotEmpty) 'role': roleText,
      },
      <dynamic>[
        projectId,
        userId,
        if (roleText != null && roleText.isNotEmpty) roleText,
      ],
      <String, dynamic>{'project_id': projectId, 'user_id': userId},
      <dynamic>[projectId, userId],
    ];
    JsonRpcException? lastError;
    var sawFalseResult = false;
    for (final params in payloadVariants) {
      try {
        final result = await _client.call('addProjectUser', params);
        if (result == true) return true;
        sawFalseResult = true;
      } on JsonRpcException catch (error) {
        lastError = error;
      }
    }
    if (lastError != null && !sawFalseResult) throw lastError;
    return false;
  }

  Future<String?> getProjectUserRole({
    required int projectId,
    required int userId,
  }) async {
    final payloadVariants = <Object>[
      <String, dynamic>{'project_id': projectId, 'user_id': userId},
      <dynamic>[projectId, userId],
    ];
    JsonRpcException? lastError;
    var sawFalseResult = false;
    for (final params in payloadVariants) {
      try {
        final result = await _client.call('getProjectUserRole', params);
        if (result == false || result == null) {
          sawFalseResult = true;
          continue;
        }
        final role = result?.toString().trim();
        if (role == null || role.isEmpty) {
          sawFalseResult = true;
          continue;
        }
        return role;
      } on JsonRpcException catch (error) {
        lastError = error;
      }
    }
    if (lastError != null && !sawFalseResult) throw lastError;
    return null;
  }

  Future<bool> changeProjectUserRole({
    required int projectId,
    required int userId,
    required String role,
  }) async {
    final roleText = role.trim();
    final payloadVariants = <Object>[
      <String, dynamic>{
        'project_id': projectId,
        'user_id': userId,
        'role': roleText,
      },
      <dynamic>[projectId, userId, roleText],
    ];
    JsonRpcException? lastError;
    var sawFalseResult = false;
    for (final params in payloadVariants) {
      try {
        final result = await _client.call('changeProjectUserRole', params);
        if (result == true) return true;
        sawFalseResult = true;
      } on JsonRpcException catch (error) {
        lastError = error;
      }
    }
    if (lastError != null && !sawFalseResult) throw lastError;
    return false;
  }

  Future<bool> removeProjectUser({
    required int projectId,
    required int userId,
  }) async {
    final payloadVariants = <Object>[
      <String, dynamic>{'project_id': projectId, 'user_id': userId},
      <dynamic>[projectId, userId],
    ];
    JsonRpcException? lastError;
    var sawFalseResult = false;
    for (final params in payloadVariants) {
      try {
        final result = await _client.call('removeProjectUser', params);
        if (result == true) return true;
        sawFalseResult = true;
      } on JsonRpcException catch (error) {
        lastError = error;
      }
    }
    if (lastError != null && !sawFalseResult) throw lastError;
    return false;
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
    double? timeEstimated,
    double? timeSpent,
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
    if (result == false) return null;
    final taskId = parseKanboardInt(result, -1);
    if (taskId <= 0) return null;
    if (timeEstimated != null || timeSpent != null) {
      await updateTask(
        id: taskId,
        timeEstimated: timeEstimated,
        timeSpent: timeSpent,
      );
    }
    return taskId;
  }

  Future<bool> updateTask({
    required int id,
    String? title,
    String? description,
    int? columnId,
    int? swimlaneId,
    int? ownerId,
    String? dateDue,
    int? priority,
    int? score,
    double? timeEstimated,
    double? timeSpent,
    bool clearDateDue = false,
  }) async {
    final titleValue = title?.trim();
    final dateDueValue = dateDue?.trim();
    final hasTitle = titleValue != null && titleValue.isNotEmpty;
    final hasDateDue = dateDueValue != null && dateDueValue.isNotEmpty;
    final hasBaseFields =
        hasTitle ||
        description != null ||
        columnId != null ||
        swimlaneId != null ||
        ownerId != null ||
        hasDateDue ||
        clearDateDue ||
        priority != null ||
        score != null;

    if (hasBaseFields) {
      final result = await _client.call('updateTask', <String, dynamic>{
        'id': id,
        if (hasTitle) 'title': titleValue,
        if (description != null) 'description': description,
        if (columnId != null) 'column_id': columnId,
        if (swimlaneId != null) 'swimlane_id': swimlaneId,
        if (ownerId != null) 'owner_id': ownerId,
        if (hasDateDue) 'date_due': dateDueValue,
        if (clearDateDue) 'date_due': 0,
        if (priority != null) 'priority': priority,
        if (score != null) 'score': score,
      });
      if (result != true) {
        return false;
      }
    }

    if (timeEstimated == null && timeSpent == null) {
      return true;
    }

    try {
      final directTimeUpdate = await _client
          .call('updateTask', <String, dynamic>{
            'id': id,
            if (timeEstimated != null) 'time_estimated': timeEstimated,
            if (timeSpent != null) 'time_spent': timeSpent,
          });
      if (directTimeUpdate == true) {
        return true;
      }
    } on JsonRpcException {
      // Fall back to subtask-based syncing below for older/strict servers.
    }

    return _syncTaskHoursWithTrackerSubtask(
      taskId: id,
      timeEstimated: timeEstimated,
      timeSpent: timeSpent,
    );
  }

  Future<bool> _syncTaskHoursWithTrackerSubtask({
    required int taskId,
    double? timeEstimated,
    double? timeSpent,
  }) async {
    final subtasks = await getAllSubtasks(taskId);

    KanboardSubtask? tracker;
    var otherEstimated = 0.0;
    var otherSpent = 0.0;

    for (final subtask in subtasks) {
      if (subtask.title == taskHoursTrackerSubtaskTitle) {
        tracker = subtask;
      } else {
        otherEstimated += subtask.timeEstimated;
        otherSpent += subtask.timeSpent;
      }
    }

    final desiredEstimated = timeEstimated ?? 0.0;
    final desiredSpent = timeSpent ?? 0.0;
    final trackerEstimated = (desiredEstimated - otherEstimated)
        .clamp(0.0, double.infinity)
        .toDouble();
    final trackerSpent = (desiredSpent - otherSpent)
        .clamp(0.0, double.infinity)
        .toDouble();

    if (tracker == null && trackerEstimated == 0 && trackerSpent == 0) {
      return true;
    }

    var trackerId = tracker?.id;
    if (trackerId == null) {
      trackerId = await createSubtask(
        taskId: taskId,
        title: taskHoursTrackerSubtaskTitle,
      );
      if (trackerId == null || trackerId <= 0) {
        return false;
      }
    }

    return updateSubtask(
      id: trackerId,
      taskId: taskId,
      title: taskHoursTrackerSubtaskTitle,
      timeEstimated: trackerEstimated,
      timeSpent: trackerSpent,
    );
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
    dynamic result;
    try {
      result = await _client.call('downloadTaskFile', <dynamic>[fileId]);
    } on JsonRpcException {
      result = await _client.call('downloadTaskFile', <String, dynamic>{
        'file_id': fileId,
      });
    }
    final text = result?.toString();
    return text == null || text.isEmpty ? null : text;
  }

  Future<bool> removeTaskFile(int fileId) async {
    dynamic result;
    try {
      result = await _client.call('removeTaskFile', <dynamic>[fileId]);
    } on JsonRpcException {
      result = await _client.call('removeTaskFile', <String, dynamic>{
        'file_id': fileId,
      });
    }
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

  Future<String?> downloadProjectFile(int fileId, {int? projectId}) async {
    final payloadVariants = <Object>[
      if (projectId != null) <dynamic>[projectId, fileId],
      if (projectId != null)
        <String, dynamic>{'project_id': projectId, 'file_id': fileId},
      <dynamic>[fileId],
      <String, dynamic>{'file_id': fileId},
    ];
    JsonRpcException? lastError;
    for (final params in payloadVariants) {
      try {
        final result = await _client.call('downloadProjectFile', params);
        final text = result?.toString();
        return text == null || text.isEmpty ? null : text;
      } on JsonRpcException catch (error) {
        lastError = error;
      }
    }
    if (lastError != null) {
      throw lastError;
    }
    return null;
  }

  Future<bool> removeProjectFile(int fileId, {int? projectId}) async {
    final payloadVariants = <Object>[
      if (projectId != null) <dynamic>[projectId, fileId],
      if (projectId != null)
        <String, dynamic>{'project_id': projectId, 'file_id': fileId},
      <dynamic>[fileId],
      <String, dynamic>{'file_id': fileId},
    ];
    JsonRpcException? lastError;
    for (final params in payloadVariants) {
      try {
        final result = await _client.call('removeProjectFile', params);
        return result == true;
      } on JsonRpcException catch (error) {
        lastError = error;
      }
    }
    if (lastError != null) {
      throw lastError;
    }
    return false;
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
    int? taskId,
    String? title,
    int? userId,
    int? status,
    double? timeEstimated,
    double? timeSpent,
  }) async {
    final payload = <String, dynamic>{
      'id': id,
      if (taskId != null && taskId > 0) 'task_id': taskId,
      if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      if (userId != null) 'user_id': userId,
      if (status != null) 'status': status,
      if (timeEstimated != null) 'time_estimated': timeEstimated,
      if (timeSpent != null) 'time_spent': timeSpent,
    };
    try {
      final result = await _client.call('updateSubtask', payload);
      return result == true;
    } on JsonRpcException catch (error) {
      final missingTaskId =
          error.code == -32602 &&
          error.message.toLowerCase().contains('missing argument: task_id');
      if (!missingTaskId || taskId == null || taskId <= 0) rethrow;
      final retry = await _client.call('updateSubtask', <String, dynamic>{
        ...payload,
        'task_id': taskId,
      });
      return retry == true;
    }
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
    dynamic result;
    try {
      result = await _client.call('getTaskTags', <String, dynamic>{
        'task_id': taskId,
      });
    } on JsonRpcException {
      result = await _client.call('getTaskTags', <dynamic>[taskId]);
    }
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
        .toSet()
        .toList();
    final payloadVariants = <Object>[
      <String, dynamic>{'task_id': taskId, 'tags': cleanTags},
      <dynamic>[taskId, cleanTags],
      <String, dynamic>{'task_id': taskId, 'tags': cleanTags.join(',')},
      <dynamic>[taskId, cleanTags.join(',')],
    ];

    JsonRpcException? lastError;
    for (final params in payloadVariants) {
      try {
        final result = await _client.call('setTaskTags', params);
        return result == true;
      } on JsonRpcException catch (error) {
        lastError = error;
      }
    }

    // Some Kanboard versions reject setTaskTags and only allow per-tag methods.
    try {
      final currentTags = (await getTaskTags(taskId)).toSet();
      final nextTags = cleanTags.toSet();
      final toAdd = nextTags.difference(currentTags);
      final toRemove = currentTags.difference(nextTags);

      for (final tag in toAdd) {
        await _createTaskTag(taskId: taskId, tag: tag);
      }
      for (final tag in toRemove) {
        await _removeTaskTag(taskId: taskId, tag: tag);
      }
      return true;
    } on JsonRpcException catch (error) {
      lastError = error;
    }

    throw lastError;
  }

  Future<void> _createTaskTag({
    required int taskId,
    required String tag,
  }) async {
    final payloadVariants = <Object>[
      <String, dynamic>{'task_id': taskId, 'tag': tag},
      <dynamic>[taskId, tag],
    ];
    JsonRpcException? lastError;
    for (final params in payloadVariants) {
      try {
        await _client.call('createTaskTag', params);
        return;
      } on JsonRpcException catch (error) {
        lastError = error;
      }
    }
    if (lastError != null) throw lastError;
  }

  Future<void> _removeTaskTag({
    required int taskId,
    required String tag,
  }) async {
    final payloadVariants = <Object>[
      <String, dynamic>{'task_id': taskId, 'tag': tag},
      <dynamic>[taskId, tag],
    ];
    JsonRpcException? lastError;
    for (final params in payloadVariants) {
      try {
        await _client.call('removeTaskTag', params);
        return;
      } on JsonRpcException catch (error) {
        lastError = error;
      }
    }
    if (lastError != null) throw lastError;
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

  List<KanboardUserReference> _toUserReferences(dynamic result) {
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
          final userId = int.tryParse(key) ?? 0;
          final label = value?.toString() ?? '';
          users.add(
            KanboardUserReference(id: userId, name: label, username: label),
          );
        }
      });
    }

    return _dedupeAndSortUsers(users);
  }

  List<KanboardUserReference> _dedupeAndSortUsers(
    List<KanboardUserReference> users,
  ) {
    final uniqueById = <int, KanboardUserReference>{};
    for (final user in users) {
      if (user.id <= 0) continue;
      uniqueById[user.id] = user;
    }
    final normalized = uniqueById.values.toList()
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    return normalized;
  }

  Uri _buildWebControllerUri({
    required String controller,
    required String action,
    Map<String, String> params = const <String, String>{},
  }) {
    var path = _client.endpoint.path;
    if (path.endsWith('/jsonrpc.php')) {
      path = path.substring(0, path.length - '/jsonrpc.php'.length);
    } else if (path.endsWith('jsonrpc.php')) {
      path = path.substring(0, path.length - 'jsonrpc.php'.length);
    }
    if (path.isEmpty) {
      path = '/';
    }
    return _client.endpoint.replace(
      path: path,
      queryParameters: <String, String>{
        'controller': controller,
        'action': action,
        ...params,
      },
    );
  }

  Future<List<KanboardUserReference>?> _searchUsersViaWebSession(
    String term,
  ) async {
    final loginUri = _buildWebControllerUri(
      controller: 'AuthController',
      action: 'login',
    );
    final checkUri = _buildWebControllerUri(
      controller: 'AuthController',
      action: 'check',
    );
    final autocompleteUri = _buildWebControllerUri(
      controller: 'UserAjaxController',
      action: 'autocomplete',
      params: <String, String>{'term': term},
    );

    try {
      var cookie = _webSessionCookie;
      if (cookie == null || cookie.isEmpty) {
        final loginPage = await _sendWebRequest(
          loginUri,
          headers: const <String, String>{'Accept': 'text/html'},
        );
        cookie = _extractCookiePair(loginPage.headers['set-cookie']);
        final csrfToken = _extractCsrfToken(loginPage.body);
        if (csrfToken == null || csrfToken.isEmpty) {
          return null;
        }

        final loginCheck = await _sendWebRequest(
          checkUri,
          method: 'POST',
          headers: <String, String>{
            if (cookie != null) 'Cookie': cookie,
            'Accept': 'text/html',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          bodyFields: <String, String>{
            'csrf_token': csrfToken,
            'username': _client.username,
            'password': _client.password,
            'remember_me': '1',
          },
        );
        cookie = _extractCookiePair(loginCheck.headers['set-cookie']) ?? cookie;
        if (_looksLikeLoginPage(loginCheck.body)) {
          return null;
        }
      }

      final autocompleteResponse = await _sendWebRequest(
        autocompleteUri,
        headers: <String, String>{
          if (cookie != null) 'Cookie': cookie,
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest',
        },
      );
      final users = _decodeAutocompleteUsersOrNull(autocompleteResponse.body);
      if (users != null) {
        _webSessionCookie = cookie;
      }
      return users;
    } catch (_) {
      return null;
    }
  }

  Future<http.Response> _sendWebRequest(
    Uri uri, {
    String method = 'GET',
    Map<String, String>? headers,
    Map<String, String>? bodyFields,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request(method, uri);
      request.followRedirects = true;
      request.maxRedirects = 5;
      if (headers != null) {
        request.headers.addAll(headers);
      }
      if (bodyFields != null) {
        request.bodyFields = bodyFields;
      }
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 12));
      return http.Response.fromStream(streamed);
    } finally {
      client.close();
    }
  }

  List<KanboardUserReference>? _decodeAutocompleteUsersOrNull(String body) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (decoded is! List<dynamic>) return null;
    final users = <KanboardUserReference>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      final userId = parseKanboardInt(item['id']);
      final username = parseKanboardString(item['username']) ?? '';
      final name =
          parseKanboardString(item['value']) ??
          parseKanboardString(item['label']) ??
          username;
      users.add(
        KanboardUserReference(id: userId, name: name, username: username),
      );
    }
    return users;
  }

  String? _extractCookiePair(String? setCookieHeader) {
    if (setCookieHeader == null || setCookieHeader.trim().isEmpty) {
      return null;
    }
    final entries = setCookieHeader.split(',');
    for (final entry in entries) {
      final trimmed = entry.trim();
      if (trimmed.isEmpty) continue;
      final firstPart = trimmed.split(';').first.trim();
      final equalIndex = firstPart.indexOf('=');
      if (equalIndex <= 0) continue;
      final key = firstPart.substring(0, equalIndex).trim();
      final value = firstPart.substring(equalIndex + 1).trim();
      if (key.isEmpty || value.isEmpty) continue;
      return '$key=$value';
    }
    return null;
  }

  String? _extractCsrfToken(String html) {
    final match = RegExp(
      r'''name=["']csrf_token["'][^>]*value=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    return match?.group(1);
  }

  bool _looksLikeLoginPage(String body) {
    final normalized = body.toLowerCase();
    return normalized.contains('authcontroller') &&
        normalized.contains('action=check') &&
        normalized.contains('forgot password');
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

  String? _normalizeCurrency(String? value) {
    if (value == null) return null;
    final text = value.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(text)) return null;
    return text;
  }
}
