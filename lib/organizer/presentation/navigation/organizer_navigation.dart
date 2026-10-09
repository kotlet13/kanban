import '../shared/sharing_workspace.dart' show SharingView;

enum OrganizerArea {
  today,
  plans,
  calendar,
  projects,
  shopping,
  finances,
  home,
  garden,
  more,
  settings,
  spaceSettings,
  sharing,
  inbox,
  people,
}

/// A UI destination, including its selected collection and workspace context.
/// It contains no data or credentials and is kept only for this shell's lifetime.
typedef OrganizerLocation = ({
  OrganizerArea area,
  OrganizerArea planArea,
  String? shoppingId,
  String? projectId,
  String? homeProjectId,
  bool sharedShopping,
  bool sharedFinance,
  String? sharedScopeId,
  String? sharedListId,
  String? sharedProjectId,
  SharingView sharingView,
  bool sharingAuth,
  String? spaceId,
  String localSpaceId,
  bool allSpaces,
});

/// Shell state is separate from widget construction so every navigation mutation
/// can be captured and restored consistently, including hidden collections.
class OrganizerNavigationState {
  OrganizerArea area = OrganizerArea.today;
  OrganizerArea planArea = OrganizerArea.plans;
  String? shoppingId, projectId, homeProjectId;
  bool sharedShopping = false, sharedFinance = false;
  String? sharedScopeId, sharedListId, sharedProjectId;
  SharingView sharingView = SharingView.shopping;
  bool sharingAuth = false;

  OrganizerLocation location({
    required String? spaceId,
    required bool allSpaces,
    String localSpaceId = 'local',
  }) => (
    area: area,
    planArea: planArea,
    shoppingId: shoppingId,
    projectId: projectId,
    homeProjectId: homeProjectId,
    sharedShopping: sharedShopping,
    sharedFinance: sharedFinance,
    sharedScopeId: sharedScopeId,
    sharedListId: sharedListId,
    sharedProjectId: sharedProjectId,
    sharingView: sharingView,
    sharingAuth: sharingAuth,
    spaceId: spaceId,
    localSpaceId: localSpaceId,
    allSpaces: allSpaces,
  );

  void restore(OrganizerLocation location) {
    area = location.area;
    planArea = location.planArea;
    shoppingId = location.shoppingId;
    projectId = location.projectId;
    homeProjectId = location.homeProjectId;
    sharedShopping = location.sharedShopping;
    sharedFinance = location.sharedFinance;
    sharedScopeId = location.sharedScopeId;
    sharedListId = location.sharedListId;
    sharedProjectId = location.sharedProjectId;
    sharingView = location.sharingView;
    sharingAuth = location.sharingAuth;
  }

  void clearSelections({required bool accountChanged}) {
    sharedScopeId = null;
    sharedListId = null;
    sharedProjectId = null;
    sharingAuth = false;
    shoppingId = null;
    projectId = null;
    homeProjectId = null;
    if (accountChanged) {
      sharedShopping = false;
      sharedFinance = false;
    }
  }
}

class OrganizerNavigationHistory {
  final List<OrganizerLocation> _previous = [];
  bool get canGoBack => _previous.isNotEmpty;

  void record(OrganizerLocation before, OrganizerLocation after) {
    if (before == after) return;
    // Returning with an in-page Back button consumes the same history entry.
    if (_previous.isNotEmpty && _previous.last == after) {
      _previous.removeLast();
    } else {
      _previous.add(before);
    }
  }

  OrganizerLocation? takePrevious() =>
      _previous.isEmpty ? null : _previous.removeLast();

  void clear() => _previous.clear();
}
