/// An explicit reviewed move of an existing inline household project.
class ProjectSharingBlocker {
  const ProjectSharingBlocker({required this.code, this.recordId});
  final String code;
  final String? recordId;
  factory ProjectSharingBlocker.fromJson(Map<String, dynamic> json) =>
      ProjectSharingBlocker(
        code: json['code'] as String,
        recordId: json['recordId'] as String?,
      );
}

class ProjectSharingPreview {
  ProjectSharingPreview({
    required this.scopeId,
    required this.projectId,
    required this.projectName,
    required this.canApply,
    required this.previewHash,
    Iterable<ProjectSharingBlocker> blockers = const [],
    Iterable<String> movedRecordIds = const [],
    Iterable<String> movedFinanceRecordIds = const [],
    Iterable<String> movedReminderIds = const [],
    Iterable<Map<String, dynamic>> financeAccounts = const [],
    Iterable<Map<String, dynamic>> householdPeople = const [],
  }) : blockers = List.unmodifiable(blockers),
       movedRecordIds = List.unmodifiable(movedRecordIds),
       movedFinanceRecordIds = List.unmodifiable(movedFinanceRecordIds),
       movedReminderIds = List.unmodifiable(movedReminderIds),
       financeAccounts = List.unmodifiable(financeAccounts),
       householdPeople = List.unmodifiable(householdPeople);
  final String scopeId, projectId, projectName, previewHash;
  final bool canApply;
  final List<ProjectSharingBlocker> blockers;
  final List<String> movedRecordIds, movedFinanceRecordIds, movedReminderIds;
  final List<Map<String, dynamic>> financeAccounts, householdPeople;
  factory ProjectSharingPreview.fromJson(Map<String, dynamic> json) {
    final hash = json['previewHash'];
    if (hash is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('Invalid sharing preview');
    }
    return ProjectSharingPreview(
      scopeId: json['scopeId'] as String,
      projectId: json['projectId'] as String,
      projectName: json['projectName'] as String,
      canApply: json['canApply'] == true,
      previewHash: hash,
      blockers: (json['blockers'] as List).map(
        (v) => ProjectSharingBlocker.fromJson(v as Map<String, dynamic>),
      ),
      movedRecordIds: (json['movedRecordIds'] as List).cast<String>(),
      movedFinanceRecordIds: (json['movedFinanceRecordIds'] as List)
          .cast<String>(),
      movedReminderIds: (json['movedReminderIds'] as List).cast<String>(),
      financeAccounts: (json['financeAccounts'] as List? ?? const []).map(
        (value) => Map<String, dynamic>.unmodifiable(value as Map),
      ),
      householdPeople: (json['householdPeople'] as List? ?? const []).map(
        (value) => Map<String, dynamic>.unmodifiable(value as Map),
      ),
    );
  }
}
