// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get kanbanConnect => 'Kanban Connect';

  @override
  String get routeError => 'Route error';

  @override
  String get unknownError => 'Unknown error';

  @override
  String get kanboardWorkspace => 'Kanboard Workspace';

  @override
  String get restoringSession => 'Restoring session...';

  @override
  String get connectToKanboard => 'Connect to Kanboard';

  @override
  String get projects => 'Projects';

  @override
  String get projectDefaults => 'Project defaults';

  @override
  String get aiSettings => 'AI settings';

  @override
  String get aiChat => 'AI chat';

  @override
  String get connectionSettings => 'Connection settings';

  @override
  String get refresh => 'Refresh';

  @override
  String get logout => 'Logout';

  @override
  String get newProject => 'New project';

  @override
  String get couldNotLoadProjects => 'Could not load projects';

  @override
  String get retry => 'Retry';

  @override
  String get noActiveSession => 'No active session';

  @override
  String get noActiveSessionConnectFirst => 'No active session. Connect first.';

  @override
  String get connectToKanboardToContinue => 'Connect to Kanboard to continue.';

  @override
  String get connect => 'Connect';

  @override
  String get projectsWorkspace => 'Projects Workspace';

  @override
  String get trackOrganizeAndOpenYourKanboardProjects =>
      'Track, organize, and open your Kanboard projects.';

  @override
  String get connectYourKanboardAccountToLoadProjectData =>
      'Connect your Kanboard account to load project data.';

  @override
  String get total => 'Total';

  @override
  String get active => 'Active';

  @override
  String get inactive => 'Inactive';

  @override
  String get noProjectsYet => 'No projects yet';

  @override
  String
  get createYourFirstProjectFromTheActionButtonAndStartOrganizingYourBoard =>
      'Create your first project from the action button and start organizing your board.';

  @override
  String get openBoard => 'Open board';

  @override
  String get projectAttachments => 'Project attachments';

  @override
  String get deleteProject => 'Delete project';

  @override
  String get noDescriptionYetOpenTheProjectToAddContext =>
      'No description yet. Open the project to add context.';

  @override
  String get deleteProject2 => 'Delete project?';

  @override
  String thisWillRemovePermanently(Object name) {
    return 'This will remove \"$name\" permanently.';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get createProject => 'Create project';

  @override
  String get editProject => 'Edit project';

  @override
  String get projectName => 'Project name';

  @override
  String get description => 'Description';

  @override
  String get projectColorSyncedViaMetadata =>
      'Project color (synced via metadata)';

  @override
  String get noColor => 'No color';

  @override
  String get save => 'Save';

  @override
  String get stop => 'Stop';

  @override
  String get send => 'Send';

  @override
  String attachments(Object name) {
    return 'Attachments · $name';
  }

  @override
  String get noProjectAttachmentsYet => 'No project attachments yet.';

  @override
  String get download => 'Download';

  @override
  String get addFiles => 'Add files';

  @override
  String get close => 'Close';

  @override
  String get projectDefaults2 => 'Project Defaults';

  @override
  String get appLanguage => 'App language';

  @override
  String get followSystemKeepsLocaleAutomatic =>
      'Follow system keeps locale automatic.';

  @override
  String get language => 'Language';

  @override
  String get followSystemDefault => 'Follow system (default)';

  @override
  String get english => 'English';

  @override
  String get slovene => 'Slovene';

  @override
  String get templateAppliedToEveryNewProjectCreatedFromThisApp =>
      'Template applied to every new project created from this app.';

  @override
  String get leaveFieldsEmptyToKeepServerDefaults =>
      'Leave fields empty to keep server defaults.';

  @override
  String get savingADefaultCurrencyAlsoAppliesItToAllExistingProjects =>
      'Saving a default currency also applies it to all existing projects.';

  @override
  String get defaultBoardColumns => 'Default Board Columns';

  @override
  String get defaultBoardColumnsHint =>
      'One per line, e.g.\\nBacklog\\nReady\\nIn Progress\\nDone';

  @override
  String get defaultSwimlane => 'Default Swimlane';

  @override
  String get exampleMain => 'Example: Main';

  @override
  String get exampleUSD => 'Example: USD';

  @override
  String get defaultExpenseCurrency => 'Default Expense Currency';

  @override
  String get reset => 'Reset';

  @override
  String get enableAI => 'Enable AI';

  @override
  String get instantResponse => 'Instant response';

  @override
  String get thinkingResponse => 'Thinking response';

  @override
  String get thinkingEffort => 'Thinking effort';

  @override
  String get effortLow => 'Low';

  @override
  String get effortMedium => 'Medium';

  @override
  String get effortHigh => 'High';

  @override
  String get aiModel => 'AI model';

  @override
  String get openAiApiKey => 'OpenAI API key';

  @override
  String get openAiApiKeyIsRequired => 'OpenAI API key is required.';

  @override
  String get testAIConnection => 'Test AI connection';

  @override
  String get fetchAvailableModels => 'Fetch available models';

  @override
  String availableModelsFetched(Object count) {
    return 'Fetched $count models.';
  }

  @override
  String availableModelsFetchFailed(Object error) {
    return 'Fetching models failed: $error';
  }

  @override
  String get aiSettingsSaved => 'AI settings saved.';

  @override
  String aiConnectionTestSucceeded(Object result) {
    return 'AI test succeeded: $result';
  }

  @override
  String aiConnectionTestFailed(Object error) {
    return 'AI test failed: $error';
  }

  @override
  String get aiSettingsSecurityNotice =>
      'Security notice: local key mode is less secure. Anyone with device/app access may extract this key.';

  @override
  String get saving => 'Saving...';

  @override
  String get saveDefaults => 'Save defaults';

  @override
  String get configureAiInSettings =>
      'Configure AI in settings before using assistant features.';

  @override
  String get aiNotEnabledForThisProject =>
      'AI is not enabled for this project.';

  @override
  String get aiProjectPolicySaved => 'Project AI policy saved.';

  @override
  String get aiActionPlanDetected => 'AI action plan detected';

  @override
  String aiActionsApplied(Object swimlanes, Object tasks) {
    return 'Applied actions: swimlanes $swimlanes, tasks $tasks.';
  }

  @override
  String aiActionsAppliedDetailed(
    Object swimlanes,
    Object columns,
    Object tasks,
    Object moved,
    Object skipped,
  ) {
    return 'Applied actions: swimlanes $swimlanes, columns $columns, new tasks $tasks, moved tasks $moved, skipped moves $skipped.';
  }

  @override
  String get enableAIForProject => 'Enable AI for this project';

  @override
  String get aiKeyMode => 'AI key mode';

  @override
  String get ownerKeyMode => 'Owner key (shared costs)';

  @override
  String get userKeyRequiredMode => 'Each user needs own key';

  @override
  String get aiCostNoticeTitle => 'AI usage cost notice';

  @override
  String aiCostNoticeBody(Object owner) {
    return 'This project uses owner key mode. AI usage here is billed to $owner.';
  }

  @override
  String get iUnderstand => 'I understand';

  @override
  String aiChatForProject(Object name) {
    return 'AI chat · $name';
  }

  @override
  String get newChat => 'New chat';

  @override
  String get continueChat => 'Continue chat';

  @override
  String get exportChat => 'Export chat';

  @override
  String currentChatId(Object id) {
    return 'Current chat: $id';
  }

  @override
  String get noSavedChatsForProject => 'No saved chats for this project yet.';

  @override
  String get noMessagesToExport => 'No messages to export.';

  @override
  String chatExportFailed(Object error) {
    return 'Chat export failed: $error';
  }

  @override
  String aiRequestFailed(Object error) {
    return 'AI request failed: $error';
  }

  @override
  String get aiIsTyping => 'AI is typing...';

  @override
  String get aiSuggestedTitle => 'AI-suggested title';

  @override
  String get aiSuggestedDescription => 'AI-suggested description';

  @override
  String get aiImproveTitle => 'Improve title with AI';

  @override
  String get aiImproveDescription => 'Improve description with AI';

  @override
  String get message => 'Message';

  @override
  String get projectDefaultsReset => 'Project defaults reset.';

  @override
  String get resetDefaults => 'Reset defaults?';

  @override
  String
  get thisClearsCustomDefaultsAndUsesKanboardServerDefaultsForNewProjects =>
      'This clears custom defaults and uses Kanboard server defaults for new projects.';

  @override
  String get connectYourKanboardInstance => 'Connect Your Kanboard Instance';

  @override
  String get loadedSavedCredentials => 'Loaded saved credentials.';

  @override
  String connectedViaJsonrpcTokenAuthServerVersion(Object version) {
    return 'Connected via jsonrpc token auth. Server version: $version';
  }

  @override
  String connectedAsVersion(Object username, Object version) {
    return 'Connected as $username. Version: $version';
  }

  @override
  String connectedSuccessfullyButServerVersionIsTarget1250(Object version) {
    return 'Connected successfully, but server version is $version (target: 1.2.50).';
  }

  @override
  String
  connectionFailedTipIfYouCopiedAPIUserAccessTryUsernameJsonrpcWithThatToken(
    Object error,
  ) {
    return 'Connection failed: $error\nTip: if you copied \"API User Access\", try username \"jsonrpc\" with that token.';
  }

  @override
  String get usePersonalTokenUsernameOrUseApplicationTokenWithUsernameJsonrpc =>
      'Use personal token + username, or use application token with username \"jsonrpc\".';

  @override
  String get nothingToExportYetConnectOnceOrFillAllFieldsFirst =>
      'Nothing to export yet. Connect once or fill all fields first.';

  @override
  String get scanThisCodeWithYourPhoneInTheConnectScreen =>
      'Scan this code with your phone in the Connect screen.';

  @override
  String get couldNotRenderQRError => 'Could not render QR.\n\$error';

  @override
  String get credentialsTransferQR => 'Credentials transfer QR';

  @override
  String get ifQRRenderingFailsCopyPasteTheTransferCode =>
      'If QR rendering fails, copy/paste the transfer code.';

  @override
  String get securityNoteThisQRContainsYourAPITokenInPlainText =>
      'Security note: this QR contains your API token in plain text.';

  @override
  String get transferCodeCopied => 'Transfer code copied.';

  @override
  String get importedCredentialsFromTransferCode =>
      'Imported credentials from transfer code.';

  @override
  String get credentialsImportedTapConnect =>
      'Credentials imported. Tap Connect.';

  @override
  String get clipboardIsEmpty => 'Clipboard is empty.';

  @override
  String invalidTransferCode(Object error) {
    return 'Invalid transfer code: $error';
  }

  @override
  String get qrScanningIsAvailableOnIOSAndroidUsePasteTransferCodeHere =>
      'QR scanning is available on iOS/Android. Use \"Paste transfer code\" here.';

  @override
  String get serverURLIsRequired => 'Server URL is required.';

  @override
  String get enterAValidURL => 'Enter a valid URL.';

  @override
  String get usernameIsRequired => 'Username is required.';

  @override
  String get tokenIsRequired => 'Token is required.';

  @override
  String get passwordIsRequired => 'Password is required.';

  @override
  String get credentials => 'Credentials';

  @override
  String get authMode => 'Auth mode';

  @override
  String get apiTokenMode => 'API token';

  @override
  String get passwordMode => 'Password';

  @override
  String get showTransferQR => 'Show transfer QR';

  @override
  String get pasteTransferCode => 'Paste transfer code';

  @override
  String get serverURL => 'Server URL';

  @override
  String get serverURLExample => 'https://kanboard.example.com';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get personalAccessToken => 'Personal access token';

  @override
  String get useYourKanboardUsernameAndPassword =>
      'Use your Kanboard username and password.';

  @override
  String get testConnectionContinue => 'Test connection & continue';

  @override
  String get openProjects => 'Open projects';

  @override
  String
  get authNotePersonalTokenUsuallyUsesYourUsernameApplicationTokenUsuallyUsesUsernameJsonrpc =>
      'Auth note: personal token usually uses your username; application token usually uses username \"jsonrpc\".';

  @override
  String get authNotePasswordModeUsesYourKanboardLoginCredentials =>
      'Auth note: password mode uses your Kanboard login credentials.';

  @override
  String get scanTransferQR => 'Scan transfer QR';

  @override
  String get transferCredentials => 'Transfer credentials';

  @override
  String get copyCode => 'Copy code';

  @override
  String get done => 'Done';

  @override
  String get boardStructure => 'Board structure';

  @override
  String get searchTasks => 'Search tasks';

  @override
  String get newGroceryList => 'New grocery list';

  @override
  String get refreshBoard => 'Refresh board';

  @override
  String get lockTaskDrag => 'Lock task drag';

  @override
  String get unlockTaskDrag => 'Unlock task drag';

  @override
  String get newTask => 'New task';

  @override
  String get groceryList => 'Grocery list';

  @override
  String get expenses => 'Expenses';

  @override
  String get search => 'Search';

  @override
  String get structure => 'Structure';

  @override
  String get swimlanes => 'Swimlanes';

  @override
  String get columns => 'Columns';

  @override
  String get tasks => 'Tasks';

  @override
  String get planned => 'Planned';

  @override
  String get spent => 'Spent';

  @override
  String get remaining => 'Remaining';

  @override
  String get noBudget => 'No budget';

  @override
  String get dropATaskHere => 'Drop a task here';

  @override
  String get unlockDragToMoveTasks => 'Unlock drag to move tasks';

  @override
  String get edit => 'Edit';

  @override
  String get markDone => 'Mark done';

  @override
  String get reopen => 'Reopen';

  @override
  String get taskSearch => 'Task Search';

  @override
  String deleteFailed(Object error) {
    return 'Delete failed: $error';
  }

  @override
  String statusUpdateFailed(Object error) {
    return 'Status update failed: $error';
  }

  @override
  String moveFailed(Object error) {
    return 'Move failed: $error';
  }

  @override
  String get addColumn => 'Add column';

  @override
  String get editColumn => 'Edit column';

  @override
  String get deleteColumn => 'Delete column?';

  @override
  String deleteColumn2(Object name) {
    return 'Delete column \"$name\"?';
  }

  @override
  String get taskLimit => 'Task limit';

  @override
  String get addSwimlane => 'Add swimlane';

  @override
  String get editSwimlane => 'Edit swimlane';

  @override
  String get deleteSwimlane => 'Delete swimlane?';

  @override
  String deleteSwimlane2(Object name) {
    return 'Delete swimlane \"$name\"?';
  }

  @override
  String get name => 'Name';

  @override
  String structure2(Object name) {
    return '$name structure';
  }

  @override
  String get query => 'Query';

  @override
  String get queryExampleStatusOpenCategoryBug => 'status:open category:bug';

  @override
  String get noResultsYet => 'No results yet.';

  @override
  String get projectExpenses => 'Project expenses';

  @override
  String get expenseSettingsSaved => 'Expense settings saved.';

  @override
  String expenseSettingsFailed(Object error) {
    return 'Expense settings failed: $error';
  }

  @override
  String get deleteTask => 'Delete task?';

  @override
  String deletePermanently(Object name) {
    return 'Delete \"$name\" permanently?';
  }

  @override
  String get currencyCode => 'Currency code';

  @override
  String get budget => 'Budget';

  @override
  String get leaveEmptyForNoBudget => 'Leave empty for no budget';

  @override
  String get task => 'Task';

  @override
  String get newLabel => 'New';

  @override
  String get openStructure => 'Open structure';

  @override
  String get noBoardDataYet => 'No board data yet';

  @override
  String get pullToRefreshOrOpenStructureToConfigureColumnsAndSwimlanes =>
      'Pull to refresh or open structure to configure columns and swimlanes.';

  @override
  String get themeMode => 'Theme mode';

  @override
  String get systemTheme => 'System theme';

  @override
  String get lightTheme => 'Light theme';

  @override
  String get darkTheme => 'Dark theme';

  @override
  String get add => 'Add';

  @override
  String get additionalDetails => 'Additional details';

  @override
  String get attachments2 => 'Attachments';

  @override
  String get comments => 'Comments';

  @override
  String get subtasks => 'Subtasks';

  @override
  String get tags => 'Tags';

  @override
  String get taskLinks => 'Task Links';

  @override
  String get externalLinks => 'External Links';

  @override
  String get link => 'Link';

  @override
  String get linkTitle => 'Link title';

  @override
  String get type => 'Type';

  @override
  String get dependency => 'Dependency';

  @override
  String get url => 'URL';

  @override
  String columnSaveFailed(Object error) {
    return 'Column save failed: $error';
  }

  @override
  String columnDeletionFailed(Object error) {
    return 'Column deletion failed: $error';
  }

  @override
  String swimlaneSaveFailed(Object error) {
    return 'Swimlane save failed: $error';
  }

  @override
  String swimlaneDeletionFailed(Object error) {
    return 'Swimlane deletion failed: $error';
  }

  @override
  String projectSaveFailed(Object error) {
    return 'Project save failed: $error';
  }

  @override
  String projectDeletionFailed(Object error) {
    return 'Project deletion failed: $error';
  }

  @override
  String get apply => 'Apply';

  @override
  String get post => 'Post';

  @override
  String get noAttachmentsYet => 'No attachments yet.';

  @override
  String get noCommentsYet => 'No comments yet.';

  @override
  String get noSubtasksYet => 'No subtasks yet.';

  @override
  String get noTagsAssigned => 'No tags assigned.';

  @override
  String get noTaskLinks => 'No task links.';

  @override
  String get noExternalLinks => 'No external links.';

  @override
  String get newTask2 => 'New Task';

  @override
  String get editTask => 'Edit Task';

  @override
  String get title => 'Title';

  @override
  String get column => 'Column';

  @override
  String get swimlane => 'Swimlane';

  @override
  String get assignee => 'Assignee';

  @override
  String get unassigned => 'Unassigned';

  @override
  String get priority => 'Priority';

  @override
  String get dueDate => 'Due date';

  @override
  String get pickDateTime => 'Pick date/time';

  @override
  String get expense => 'Expense';

  @override
  String get score => 'Score';

  @override
  String get pickDueDate => 'Pick due date';

  @override
  String get clearDueDate => 'Clear due date';

  @override
  String get newComment => 'New comment';

  @override
  String get comment => 'Comment';

  @override
  String get editComment => 'Edit comment';

  @override
  String get editSubtask => 'Edit subtask';

  @override
  String get estimateH => 'Estimate (h)';

  @override
  String get spentH => 'Spent (h)';

  @override
  String get newGroceryItem => 'New grocery item';

  @override
  String get newSubtask => 'New subtask';

  @override
  String get addTagsCommaSeparated => 'Add tags (comma separated)';

  @override
  String get relation => 'Relation';

  @override
  String get linkedTaskID => 'Linked task ID';

  @override
  String get export => 'Export';

  @override
  String get remove => 'Remove';

  @override
  String get project => 'Project';

  @override
  String projectCreatedButDefaultsFailedToApply(Object error) {
    return 'Project created, but defaults failed to apply: $error';
  }

  @override
  String get projectAttachmentsUploaded => 'Project attachments uploaded.';

  @override
  String uploadFailed(Object error) {
    return 'Upload failed: $error';
  }

  @override
  String get attachmentContentMissing => 'Attachment content missing.';

  @override
  String downloadFailed(Object error) {
    return 'Download failed: $error';
  }

  @override
  String filePickerFailed(Object error) {
    return 'File picker failed: $error';
  }

  @override
  String attachmentPickerFailed(Object error) {
    return 'Attachment picker failed: $error';
  }

  @override
  String get attachmentUploadComplete => 'Attachment upload complete.';

  @override
  String attachmentUploadFailed(Object error) {
    return 'Attachment upload failed: $error';
  }

  @override
  String get attachmentHasNoDownloadableContent =>
      'Attachment has no downloadable content.';

  @override
  String attachmentExportFailed(Object error) {
    return 'Attachment export failed: $error';
  }

  @override
  String attachmentDeleteFailed(Object error) {
    return 'Attachment delete failed: $error';
  }

  @override
  String commentSaveFailed(Object error) {
    return 'Comment save failed: $error';
  }

  @override
  String commentUpdateFailed(Object error) {
    return 'Comment update failed: $error';
  }

  @override
  String commentDeleteFailed(Object error) {
    return 'Comment delete failed: $error';
  }

  @override
  String subtaskCreateFailed(Object error) {
    return 'Subtask create failed: $error';
  }

  @override
  String subtaskUpdateFailed(Object error) {
    return 'Subtask update failed: $error';
  }

  @override
  String subtaskDeleteFailed(Object error) {
    return 'Subtask delete failed: $error';
  }

  @override
  String tagUpdateFailed(Object error) {
    return 'Tag update failed: $error';
  }

  @override
  String get theGroceryListTagIsReservedForGroceryTasks =>
      'The grocery-list tag is reserved for grocery tasks.';

  @override
  String taskLinkFailed(Object error) {
    return 'Task link failed: $error';
  }

  @override
  String linkDeleteFailed(Object error) {
    return 'Link delete failed: $error';
  }

  @override
  String externalLinkFailed(Object error) {
    return 'External link failed: $error';
  }

  @override
  String externalLinkDeleteFailed(Object error) {
    return 'External link delete failed: $error';
  }

  @override
  String taskStatusUpdateFailed(Object error) {
    return 'Task status update failed: $error';
  }

  @override
  String get serverRejectedTaskStatusUpdate =>
      'Server rejected task status update.';

  @override
  String taskNumber(Object id) {
    return 'Task #$id';
  }

  @override
  String get taskMarkedDone => 'Task marked done.';

  @override
  String get taskReopened => 'Task reopened.';

  @override
  String get open => 'Open';

  @override
  String get reopenTask => 'Reopen task';

  @override
  String get markAsDone => 'Mark as done';

  @override
  String get editTask2 => 'Edit task';

  @override
  String get createTask => 'Create task';

  @override
  String get editGroceryList => 'Edit grocery list';

  @override
  String get createGroceryList => 'Create grocery list';

  @override
  String get groceryListTitle => 'Grocery list title';

  @override
  String get noGroceryItemsYet => 'No grocery items yet.';

  @override
  String get addItemsNowTheyWillBeCreatedWhenYouSave =>
      'Add items now. They will be created when you save.';

  @override
  String get titleIsRequired => 'Title is required.';

  @override
  String get scoreMustBeAnInteger => 'Score must be an integer.';

  @override
  String serverRejectedAttachmentName(Object name) {
    return 'Server rejected attachment \"$name\".';
  }

  @override
  String get amountMustBeAValidNumber => 'Amount must be a valid number.';

  @override
  String get taskWasNotCreated => 'Task was not created.';

  @override
  String get enterATitleBeforeOpeningAdditionalDetails =>
      'Enter a title before opening additional details.';

  @override
  String get taskMustBeSavedFirst => 'Task must be saved first.';

  @override
  String get saveTaskFirstToManageAttachmentsCommentsSubtasksTagsAndLinks =>
      'Save this task first to manage attachments, comments, subtasks, tags, and links.';

  @override
  String get externalLinkTitleAndURLAreRequired =>
      'External link title and URL are required.';

  @override
  String get enterAValidLinkedTaskID => 'Enter a valid linked task ID.';

  @override
  String get invalidURL => 'Invalid URL.';

  @override
  String get couldNotOpenURLCopiedToClipboard =>
      'Could not open URL. Copied to clipboard.';

  @override
  String get attachmentsCommentsSubtasksTagsAndLinks =>
      'Attachments, comments, subtasks, tags and links';

  @override
  String get tapToExpandAdvancedTaskDetails =>
      'Tap to expand advanced task details';

  @override
  String get advancedSectionsAreHidden => 'Advanced sections are hidden.';

  @override
  String get forNewTasksTheAppSavesFirstThenOpensAdvancedSections =>
      'For new tasks, the app saves first, then opens advanced sections.';

  @override
  String get internalLinkTypesUnavailableForThisUserProject =>
      'Internal link types unavailable for this user/project.';

  @override
  String get noPermissionForInternalTaskLinksGetAllLinks =>
      'No permission for internal task links (`getAllLinks`).';

  @override
  String get linkedTo => 'linked to';

  @override
  String userNumber(Object id) {
    return 'User #$id';
  }

  @override
  String estHSpentH(Object est, Object spent) {
    return 'Est ${est}h · Spent ${spent}h';
  }

  @override
  String get eG1250 => 'e.g. 12.50';

  @override
  String
  get macosFileAccessEntitlementMissingRebuildTheAppAfterEnablingUserSelectedFileReadEntitlement =>
      'macOS file access entitlement missing. Rebuild the app after enabling user-selected file read entitlement.';

  @override
  String tasks2(Object count) {
    return 'Tasks: $count';
  }

  @override
  String columns2(Object count) {
    return 'Columns: $count';
  }

  @override
  String get noColumnsConfiguredForThisSwimlaneUseStructureToAddColumns =>
      'No columns configured for this swimlane. Use Structure to add columns.';

  @override
  String
  get taskDragIsUnlockedMoveTasksCarefullyWhileScrollingOrTapLockToPreventAccidentalMoves =>
      'Task drag is unlocked. Move tasks carefully while scrolling, or tap lock to prevent accidental moves.';

  @override
  String
  get taskDragIsLockedSoYouCanScrollSafelyTapUnlockInTheTopBarWhenYouWantToMoveTasks =>
      'Task drag is locked so you can scroll safely. Tap unlock in the top bar when you want to move tasks.';

  @override
  String
  get dragAndDropTasksAcrossSwimlanesAndColumnsUseSearchForAdvancedQuerySyntax =>
      'Drag and drop tasks across swimlanes and columns. Use Search for advanced query syntax.';

  @override
  String get currencyMustBeA3LetterCode => 'Currency must be a 3-letter code.';

  @override
  String get budgetMustBeAPositiveNumber => 'Budget must be a positive number.';

  @override
  String get useKanboardQuerySyntaxExampleStatusOpenAssigneeMeDueTomorrow =>
      'Use Kanboard query syntax. Example: `status:open assignee:me due:tomorrow`';

  @override
  String get enterASearchQuery => 'Enter a search query.';

  @override
  String boardStructure2(Object name) {
    return '$name Board Structure';
  }

  @override
  String get dragRowsToReorderChangesAreSavedImmediately =>
      'Drag rows to reorder. Changes are saved immediately.';

  @override
  String get noColumnsYetAddOne => 'No columns yet. Add one.';

  @override
  String get noSwimlanesYetAddOne => 'No swimlanes yet. Add one.';

  @override
  String positionLimit(Object position, Object limit) {
    return 'Position $position · Limit $limit';
  }

  @override
  String position(Object position) {
    return 'Position $position';
  }

  @override
  String get horizontalStructureOfTheBoard =>
      'Horizontal structure of the board';

  @override
  String get verticalWorkGrouping => 'Vertical work grouping';
}
