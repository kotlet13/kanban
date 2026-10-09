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
  String get showDoneTasks => 'Show done tasks';

  @override
  String get hideDoneTasks => 'Hide done tasks';

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
  String get financeTable => 'Finance table';

  @override
  String get financeProject => 'Finance project';

  @override
  String get financeProjectDescription =>
      'Open this project directly in Finance table.';

  @override
  String get sharedFinanceTable => 'Shared finance table';

  @override
  String get currentBalance => 'Current balance';

  @override
  String get projectionHorizon => 'Projection horizon';

  @override
  String get showPastMonths => 'Show past months';

  @override
  String get includeSpentExternalExpensesInProjection =>
      'Include spent external expenses in projection';

  @override
  String get unsavedFinanceChangesTitle => 'Unsaved finance changes';

  @override
  String get unsavedFinanceChangesMessage =>
      'Some finance data is not saved yet. Leave this page anyway?';

  @override
  String get leaveWithoutSaving => 'Leave without saving';

  @override
  String get summedMonthlyIncome => 'Summed monthly income';

  @override
  String get summedMonthlyExpenses => 'Summed monthly expenses';

  @override
  String get totalBalance => 'Total balance';

  @override
  String get biggestIncomeExpenseGap =>
      'Lowest monthly net (income - expenses)';

  @override
  String get months3 => '3 months';

  @override
  String get months6 => '6 months';

  @override
  String get months12 => '12 months';

  @override
  String get lowestProjectedBalance => 'Lowest projected balance';

  @override
  String get firstNegativeMonth => 'First negative month';

  @override
  String get endBalance => 'End balance';

  @override
  String get recurringMonthlyEnabled => 'Recurring monthly (enabled)';

  @override
  String get recurringIncomeMonthlyEnabled =>
      'Recurring income monthly (enabled)';

  @override
  String get monthlyIncomesAndProjections => 'Monthly incomes & projections';

  @override
  String get month => 'Month';

  @override
  String get incomeTotal => 'Income total';

  @override
  String get expensesTotal => 'Expenses total';

  @override
  String get net => 'Net';

  @override
  String get closing => 'Closing';

  @override
  String get contributor => 'Contributor';

  @override
  String get contributorOptional => 'Contributor (optional)';

  @override
  String get source => 'Source';

  @override
  String get otherIncome => 'Other income';

  @override
  String get otherExpense => 'Other expense';

  @override
  String get recurringIncomes => 'Recurring incomes';

  @override
  String get recurringExpenses => 'Recurring expenses';

  @override
  String get plannedIncomes => 'Planned incomes';

  @override
  String get plannedExpenses => 'Planned expenses';

  @override
  String get expensesFromOtherProjects => 'Expenses from other projects';

  @override
  String get ongoing => 'ongoing';

  @override
  String get enabled => 'Enabled';

  @override
  String get category => 'Category';

  @override
  String get monthlyAmount => 'Monthly amount';

  @override
  String get startMonthYYYYMM => 'Start month (YYYY-MM)';

  @override
  String get endMonthOptionalYYYYMM => 'End month (YYYY-MM, optional)';

  @override
  String get addRecurringExpense => 'Add recurring expense';

  @override
  String get editRecurringExpense => 'Edit recurring expense';

  @override
  String get recurringExpenseFieldsNotValid =>
      'Recurring expense fields are not valid.';

  @override
  String get addRecurringIncome => 'Add recurring income';

  @override
  String get editRecurringIncome => 'Edit recurring income';

  @override
  String get recurringIncomeFieldsNotValid =>
      'Recurring income fields are not valid.';

  @override
  String get addPlannedExpense => 'Add planned expense';

  @override
  String get editPlannedExpense => 'Edit planned expense';

  @override
  String get plannedExpenseFieldsNotValid =>
      'Planned expense fields are not valid.';

  @override
  String get addPlannedIncome => 'Add planned income';

  @override
  String get editPlannedIncome => 'Edit planned income';

  @override
  String get plannedIncomeFieldsNotValid =>
      'Planned income fields are not valid.';

  @override
  String get amount => 'Amount';

  @override
  String get amountHint => '0.00';

  @override
  String get monthYYYYMM => 'Month (YYYY-MM)';

  @override
  String get financeContributorMe => 'Me';

  @override
  String incomeForPerson(Object name) {
    return 'Income - $name';
  }

  @override
  String get currentBalanceMustBeValidNumber =>
      'Current balance must be a valid number.';

  @override
  String get financeTableSaved => 'Finance table saved.';

  @override
  String financeTableSaveFailed(Object error) {
    return 'Finance table save failed: $error';
  }

  @override
  String get serverRejectedFinanceTableSave =>
      'Server rejected finance table save.';

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

  @override
  String get organizerAppName => 'Jivie';

  @override
  String get jivieAbout => 'About Jivie';

  @override
  String get jivieDescription =>
      'A free personal and family organizer for tasks, plans, shopping and finances. Create and edit personal data on your device without an account or connection. Enable synchronization and sharing when you choose.';

  @override
  String get organizerToday => 'Today';

  @override
  String get organizerPlans => 'Plans';

  @override
  String get organizerShopping => 'Shopping';

  @override
  String get organizerMore => 'More';

  @override
  String get organizerCalendar => 'Calendar';

  @override
  String get organizerProjects => 'Projects';

  @override
  String get organizerFinances => 'Finances';

  @override
  String get organizerHome => 'Home';

  @override
  String get organizerSettings => 'Settings';

  @override
  String get organizerLocalSpace => 'Personal space';

  @override
  String get organizerLocalOnly => 'Saved on this device';

  @override
  String get organizerLocalDescription =>
      'Tasks and plans live on this device. No account needed.';

  @override
  String get organizerTodayIntro => 'Room for what matters today.';

  @override
  String get organizerNextEvent => 'Next on your calendar';

  @override
  String get organizerNoEvents => 'Your calendar is empty.';

  @override
  String get organizerNoEventsDescription =>
      'Add an event to keep your next step in sight.';

  @override
  String get organizerNextTasks => 'Next steps';

  @override
  String get organizerNoTasks => 'Start with one task.';

  @override
  String get organizerNoTasksDescription =>
      'Small tasks, bigger plans. Everything in its place.';

  @override
  String get organizerAddTask => 'Add task';

  @override
  String get organizerEditTask => 'Edit task';

  @override
  String get organizerAddEvent => 'Add event';

  @override
  String get organizerEditEvent => 'Edit event';

  @override
  String get organizerAddProject => 'New project';

  @override
  String get organizerEditProject => 'Edit project';

  @override
  String get organizerNoProjects => 'What would you like to plan?';

  @override
  String get organizerNoProjectsDescription =>
      'Create a project for a trip, renovation or everyday tasks.';

  @override
  String get organizerShoppingShortcut => 'Open shopping lists';

  @override
  String get organizerShoppingIntro =>
      'Write down what you need. Check it off when it is in your basket.';

  @override
  String get organizerAddList => 'New list';

  @override
  String get organizerEditList => 'Edit list';

  @override
  String get organizerNoLists => 'A list for your next shop.';

  @override
  String get organizerNoListsDescription =>
      'Create a list and add the first thing you need.';

  @override
  String get organizerAddItem => 'Add item';

  @override
  String get organizerEditItem => 'Edit item';

  @override
  String get organizerItemHint => 'What do you need?';

  @override
  String get organizerQuantity => 'Quantity';

  @override
  String get organizerBought => 'Purchased';

  @override
  String get organizerEmptyList => 'There are no items on this list yet.';

  @override
  String get organizerTasks => 'Tasks';

  @override
  String get organizerAllTasks => 'All tasks';

  @override
  String get organizerNoProject => 'No project';

  @override
  String get organizerCompleted => 'Completed';

  @override
  String get organizerTitle => 'Title';

  @override
  String get organizerNotes => 'Notes';

  @override
  String get organizerDescription => 'Description';

  @override
  String get organizerRequired => 'Enter a title.';

  @override
  String get organizerSaveError =>
      'Could not save the change. Please try again.';

  @override
  String get organizerLoadError => 'Could not open local data.';

  @override
  String get organizerRetry => 'Try again';

  @override
  String get organizerDate => 'Date';

  @override
  String get organizerTime => 'Time';

  @override
  String get organizerNoDate => 'No due date';

  @override
  String get organizerRemoveDate => 'Remove date';

  @override
  String get organizerUpcoming => 'Upcoming';

  @override
  String get organizerCalendarIntro =>
      'Events and task deadlines in one place.';

  @override
  String get organizerFinanceIntro => 'Income, expenses and planned costs.';

  @override
  String get organizerAddFinance => 'Add entry';

  @override
  String get organizerEditFinance => 'Edit entry';

  @override
  String get organizerNoFinance => 'Your overview starts with the first entry.';

  @override
  String get organizerIncome => 'Income';

  @override
  String get organizerExpense => 'Expense';

  @override
  String get organizerCurrency => 'Currency';

  @override
  String get organizerInvalidMoney =>
      'Enter a positive amount with at most two decimal places.';

  @override
  String get organizerBalance => 'Income minus expenses';

  @override
  String get organizerConnection => 'Existing Kanboard';

  @override
  String get organizerConnectionDescription =>
      'Your existing projects are still on your Kanboard server. Connect your account to open them. The local organizer does not import or sync them yet.';

  @override
  String get organizerConnect => 'Connect account';

  @override
  String get organizerOpenKanboard => 'Open Kanboard';

  @override
  String get organizerBackup => 'Backup';

  @override
  String get organizerBackupDescription =>
      'Export local records to a JSON file or restore them from a backup. The file is not encrypted; store it in a safe place.';

  @override
  String get organizerExport => 'Export backup';

  @override
  String get organizerImport => 'Restore backup';

  @override
  String get organizerRestoreWarning =>
      'Restoring adds records from the backup. If the backup contains records that already exist, the entire import is rejected. Export your current backup first.';

  @override
  String get organizerRestoreConfirm => 'Restore';

  @override
  String get organizerRestored => 'Local data restored.';

  @override
  String get organizerReminders => 'Reminders';

  @override
  String get organizerNoReminders => 'No new reminders.';

  @override
  String get organizerRemindersDescription =>
      'Task deadline reminders appear when you open the app.';

  @override
  String get organizerHomeIntro =>
      'Organize home plans with projects and tasks in your personal space.';

  @override
  String get organizerBackToday => 'Back to Today';

  @override
  String get organizerDeleteConfirm => 'Delete this entry?';

  @override
  String get organizerDeleteProjectNote =>
      'Tasks, events and finance entries are kept without a project.';

  @override
  String organizerProjectProgress(int done, int total) {
    return '$done of $total completed';
  }

  @override
  String organizerShoppingCount(int count) {
    return '$count items on your lists';
  }

  @override
  String organizerTasksCount(int count) {
    return '$count tasks';
  }

  @override
  String get organizerNoMatchingTasks =>
      'There are no tasks in this project yet.';

  @override
  String get organizerPersonal => 'Personal';

  @override
  String get organizerSystemLanguage => 'Device language';

  @override
  String get organizerRead => 'Read';

  @override
  String get organizerWithoutDate => 'Without a deadline';

  @override
  String get organizerOverdue => 'Overdue';

  @override
  String get organizerHomeProjects => 'Home projects';

  @override
  String get organizerProjectArea => 'Area';

  @override
  String get organizerPersonalArea => 'Personal';

  @override
  String get organizerHomeArea => 'Home';

  @override
  String get organizerConflict =>
      'The record changed or the backup contains existing records. Open the latest version of the record; a conflicting import is rejected.';

  @override
  String get organizerInvalidData =>
      'The data is invalid or the backup format is unsupported.';

  @override
  String get secureStorageUnavailable =>
      'Secure storage is unavailable. Credentials were not saved; check this device’s secure storage settings.';

  @override
  String get credentialsSharingDisabled =>
      'Passwords and personal API keys are not shared. Project invitations will be available when the secure flow is ready.';

  @override
  String get personalTokenHint =>
      'Use your username and personal API token. The global jsonrpc key is not supported.';

  @override
  String get secureConnectionRequired =>
      'Use HTTPS. HTTP is allowed only for an explicit local development connection.';

  @override
  String get localDevelopmentConnection =>
      'Local development connection (HTTP on this computer)';

  @override
  String get aiSessionChanged =>
      'The account changed. This chat belongs to the previous session; reopen AI help from your project.';

  @override
  String get connectionFailed =>
      'Connection failed. Check the server address, username and password or personal API token.';

  @override
  String get sharingAccount => 'Account and sharing';

  @override
  String get sharingIntro =>
      'Personal data stays on this device. Connect an account when you want to use shared lists and projects.';

  @override
  String get sharingPersonal => 'Personal';

  @override
  String get sharingShared => 'Shared';

  @override
  String get sharingConnect => 'Connect for sharing';

  @override
  String get sharingLogin => 'Sign in';

  @override
  String get sharingLoginAction => 'Sign in';

  @override
  String get sharingHaveInvite => 'I have an invitation';

  @override
  String get sharingInvitation => 'Invitation';

  @override
  String get sharingInvitationCode => 'Invitation code';

  @override
  String get sharingInvitationHint =>
      'Paste the code sent by the person you want to collaborate with.';

  @override
  String get sharingPreviewInvite => 'Check invitation';

  @override
  String get sharingAcceptInvite => 'Accept invitation';

  @override
  String get sharingRegister => 'Create an account with an invitation';

  @override
  String get sharingRegisterAction => 'Create account and accept';

  @override
  String get sharingDisplayName => 'Display name';

  @override
  String get sharingEmail => 'Email';

  @override
  String get sharingConfirmPassword => 'Confirm password';

  @override
  String get sharingPasswordMismatch => 'Passwords do not match.';

  @override
  String get sharingTwoFactorCode => 'Two-factor authentication code';

  @override
  String get sharingDeviceName => 'This device’s name';

  @override
  String get sharingDeviceSession => 'This device’s session';

  @override
  String get sharingSpaces => 'Shared spaces';

  @override
  String get sharingCreateSpace => 'New shared space';

  @override
  String get sharingSpaceName => 'Space name';

  @override
  String get sharingScopeType => 'Space type';

  @override
  String get sharingHousehold => 'Household';

  @override
  String get sharingProject => 'Project';

  @override
  String get sharingScopeDescription =>
      'In this version you share lists, projects, and tasks. Shared finances will follow in the finance redesign.';

  @override
  String get sharingNoSpaces => 'No shared spaces yet.';

  @override
  String get sharingChooseSpace => 'Choose a shared space';

  @override
  String get sharingMembers => 'Members';

  @override
  String get sharingOwner => 'Owner';

  @override
  String get sharingEditor => 'Can edit';

  @override
  String get sharingViewer => 'Can view';

  @override
  String get sharingRole => 'Role';

  @override
  String get sharingInvitePerson => 'Invite someone';

  @override
  String get sharingCreateInvite => 'Create invitation';

  @override
  String get sharingInvitations => 'Invitations';

  @override
  String get sharingCopyInvite => 'Copy code';

  @override
  String get sharingInviteCopied => 'Invitation code copied.';

  @override
  String get sharingInviteCodeOnce =>
      'Save or send the code now. It cannot be displayed again later.';

  @override
  String get sharingRevokeInvite => 'Revoke invitation';

  @override
  String get sharingRemoveMember => 'Remove member';

  @override
  String get sharingRemoveMemberConfirm =>
      'Once removed, this member can no longer access this space. Previously downloaded copies cannot be erased remotely.';

  @override
  String get sharingSignOutDescription =>
      'Personal data stays on this device. Check pending shared changes before signing out.';

  @override
  String get sharingSyncNow => 'Sync now';

  @override
  String get sharingSynced => 'Synced';

  @override
  String get sharingSyncing => 'Syncing …';

  @override
  String get sharingPending => 'Waiting to sync';

  @override
  String get sharingOffline => 'Connection unavailable';

  @override
  String get sharingSyncFailed => 'Sync failed. Local changes have been kept.';

  @override
  String get sharingConflicts => 'Changes need a decision';

  @override
  String get sharingConflictDescription =>
      'The same record also changed elsewhere. Compare both versions and choose which to keep.';

  @override
  String get sharingLocalVersion => 'On this device';

  @override
  String get sharingRemoteVersion => 'On the server';

  @override
  String get sharingKeepLocal => 'Keep my version';

  @override
  String get sharingKeepRemote => 'Keep server version';

  @override
  String get sharingAccessRevoked =>
      'Access was revoked. Pending changes have not been sent.';

  @override
  String get sharingUnsupported =>
      'This server does not support the required sharing features yet.';

  @override
  String get sharingOperationFailed =>
      'The action failed. Check the connection and try again.';

  @override
  String get sharingInvalidInvite =>
      'The invitation is invalid, expired, or already used.';

  @override
  String get sharingSessionExpired =>
      'Your session expired. Sign in again; personal data stays on this device.';

  @override
  String get sharingPermissionDenied =>
      'You do not have permission for this action.';

  @override
  String get sharingNoSharedLists => 'This space has no shared list yet.';

  @override
  String get sharingNoSharedListsDescription =>
      'Create a list to collaborate. Personal lists are not shared automatically.';

  @override
  String get sharingCreateSharedList => 'New shared list';

  @override
  String get sharingReadOnly => 'Read only';

  @override
  String get sharingQuietShopping =>
      'Shopping list changes are quiet; they do not send email.';

  @override
  String get sharingShareList => 'Share this list';

  @override
  String get sharingShareProject => 'Share project and tasks';

  @override
  String get sharingShareConfirm =>
      'A shared copy will be created in the selected space. Personal content and finances are not shared automatically.';

  @override
  String get sharingNoMembers => 'No member information available.';

  @override
  String get sharingNoInvitations => 'No active invitations.';

  @override
  String get sharingGoToAccount => 'Open account and sharing';

  @override
  String get sharingConnectBeforeShared =>
      'Connect an account or accept an invitation to use shared lists.';

  @override
  String get sharingSaveBeforeSync =>
      'Changes are saved on this device first, then synced with the space.';

  @override
  String get sharingMember => 'Member';

  @override
  String get sharingRequired => 'Complete this field.';

  @override
  String get sharingSaveDrafts => 'Save my unsynced changes';

  @override
  String get sharingSaveDraftsDescription =>
      'The export contains your pending shared changes, without credentials. The JSON file is not encrypted.';

  @override
  String get sharingCopyAction => 'Create a shared copy';

  @override
  String get sharingCopyDone =>
      'Shared copy created. Your personal original is unchanged.';

  @override
  String get sharingCopyDescription =>
      'This version copies only this list or the project with its tasks. Finances and events are not transferred in this action. Later edits to the personal original are not sent to the shared copy.';

  @override
  String get sharingLoginNeedsOtp =>
      'Enter the code from your two-factor authentication app.';

  @override
  String get sharingInvalidCredentials =>
      'Sign-in failed. Check your username, password, and any two-factor code.';

  @override
  String get sharingSelectDestination =>
      'Where should the shared copy be created?';

  @override
  String get sharingPendingSignOut =>
      'The shared view will be hidden after signing out. Personal data remains. Unsynced shared changes are not sent under another account; you can export them before signing out.';

  @override
  String get sharingNoPending => 'No pending changes';

  @override
  String get sharingResumeBlocked => 'Resume syncing my changes';

  @override
  String get sharingResumeBlockedDescription =>
      'Access has been restored. Previously blocked changes are sent only when you explicitly resume syncing.';

  @override
  String get sharingOfflineSignOut =>
      'Signed out on this device. Server session revocation could not be confirmed; that session remains valid until revoked or expired.';

  @override
  String get sharingExpires => 'Expires';

  @override
  String get sharingAccepted => 'Accepted';

  @override
  String get sharingRevoked => 'Revoked';

  @override
  String get sharingExpired => 'Expired';

  @override
  String get sharingSessionEnds => 'Session expires';

  @override
  String get sharingSharedTasks => 'Shared tasks';

  @override
  String get sharingConflictsButton => 'Review changes';

  @override
  String get sharingDeletedVersion =>
      'This version is absent or the record has been deleted.';

  @override
  String get sharingNetworkError =>
      'Connection unavailable. Unsynced changes stay on this device; try syncing again.';

  @override
  String get sharingSessionRevoked =>
      'This device’s session was revoked. Sign in again; unsynced changes are not sent under another account.';

  @override
  String get sharingStorageUnavailable =>
      'Durable storage for shared data is unavailable. The action was not confirmed; check this device’s storage and try again.';

  @override
  String get sharingInvalidServer =>
      'Check the server address. Use HTTPS for a normal connection.';

  @override
  String get sharingRateLimited =>
      'Too many attempts. Wait a while, then try again.';

  @override
  String get sharingUnsupportedAuth =>
      'This sign-in method is not supported. Use a supported local user account on the server for sharing.';

  @override
  String get sharingIncompatibleServer =>
      'The server version is not compatible with sharing in this app. Check the server plugin; local data stays on this device.';

  @override
  String get sharingValidationError =>
      'The data is invalid. Check your input and try again.';

  @override
  String get sharingRegistrationPasswordHint =>
      'A new password needs at least 12 characters (at most 72 bytes).';

  @override
  String get sharingBlockedDescription =>
      'These changes are blocked because access was revoked. You can export them. Restored access requires an explicit choice to resume them.';

  @override
  String get sharingAdvancedLogin => 'Additional sign-in options';

  @override
  String get sharingMoreDetails => 'Record details';

  @override
  String get sharingNoConflicts => 'No changes need a decision.';

  @override
  String get sharingRefreshMembers => 'Refresh members';

  @override
  String get sharingDeletedConflict =>
      'This record was deleted on the server. You can save your version in an export; accepting the server state does not restore it.';

  @override
  String get sharingRelatedConflict =>
      'Related records have changed. First save your version, accept the server state, and review related records. You can then explicitly create a copy or choose deletion again.';

  @override
  String get sharingStaleEditor =>
      'This record changed while you were editing it. Close the editor and open the latest version; you can copy your text first.';

  @override
  String get sharingInvalidResponse =>
      'The server response cannot be used safely. Check plugin compatibility. Local changes remain on this device.';

  @override
  String get sharingRequestMismatch =>
      'The server rejected a repeated request with different content. Save your changes in an export and review the state; do not blindly resend the request.';

  @override
  String get planningAssignees => 'Assigned to';

  @override
  String get planningUnassigned => 'Not assigned yet';

  @override
  String get planningFormerMember => 'Former member';

  @override
  String get planningSchedule => 'Planned schedule';

  @override
  String get planningStart => 'Start';

  @override
  String get planningEnd => 'End';

  @override
  String get planningDue => 'Due';

  @override
  String get planningCreatedBy => 'Created by';

  @override
  String get planningUpdatedBy => 'Last updated by';

  @override
  String get planningInvalidSchedule => 'The end cannot be before the start.';

  @override
  String get planningSharedToday => 'Today in this shared space';

  @override
  String get planningTimeline => 'Timeline';

  @override
  String get planningNoAgenda =>
      'There are no shared scheduled items for this day.';

  @override
  String get planningNoTimeline =>
      'Add a schedule to a task or project to see the timeline.';

  @override
  String get planningAllPeople => 'Everyone';

  @override
  String get planningNoTime => 'No schedule';

  @override
  String get planningPreviousDay => 'Previous day';

  @override
  String get planningNextDay => 'Next day';

  @override
  String get financeMinorUnits => 'minor units';

  @override
  String get financeUnspecifiedPerson => 'Not specified';

  @override
  String get financeUnavailableAccount => 'Account unavailable';

  @override
  String get financePosted => 'Posted';

  @override
  String get financePlanned => 'Planned';

  @override
  String get financeAddTransfer => 'Add transfer';

  @override
  String get financeTransfer => 'Transfer';

  @override
  String get financeInternalTransfer => 'Transfer between accounts';

  @override
  String get financeAddAccount => 'Add account';

  @override
  String get financeNoAccounts =>
      'Create the first financial account in this space.';

  @override
  String get financeAccounts => 'Financial accounts';

  @override
  String get financeAccount => 'Financial account';

  @override
  String get financeAllAccounts => 'All accounts';

  @override
  String get financePayerRecipient => 'Payer / recipient';

  @override
  String get financeEnteredBy => 'Entered by';

  @override
  String get financeStatus => 'Entry status';

  @override
  String get financeAllStatuses => 'All statuses';

  @override
  String get financeNoMatchingEntries => 'No entries match these filters.';

  @override
  String get financeCategory => 'Category';

  @override
  String get financePayer => 'Payer';

  @override
  String get financeRecipient => 'Recipient';

  @override
  String get financeJointAccount => 'Joint account';

  @override
  String get financeAudit => 'Change history';

  @override
  String get financeScopeTotals => 'Entire financial space';

  @override
  String get financeTransfersExcluded =>
      'Totals include posted entries. Transfers between accounts are not new income or expenses. The filters below apply to the table.';

  @override
  String get financeSharedAccountsDescription =>
      'These accounts are shared in this space. Private local accounts are not connected automatically.';

  @override
  String get financeDate => 'Date and time';

  @override
  String get planningAllProjects => 'All projects';

  @override
  String get inboxDeviceReminder =>
      'It is time for your reminder. Open the app for details.';

  @override
  String get inboxDeviceEventReminder =>
      'Your event is approaching. Open the app for details.';

  @override
  String get inboxTitle => 'Notifications';

  @override
  String get inboxForMe => 'For me';

  @override
  String get inboxInSharedSpace => 'In a shared space';

  @override
  String get inboxAll => 'All';

  @override
  String get inboxRead => 'Read';

  @override
  String get inboxMarkRead => 'Mark as read';

  @override
  String get inboxMarkUnread => 'Mark as unread';

  @override
  String get inboxEmpty => 'There are no notifications in this view yet.';

  @override
  String get inboxSettings => 'Notification settings';

  @override
  String get inboxDeviceSettings => 'Reminders on this device';

  @override
  String get inboxDevicePrivacy =>
      'System notifications show a generic reminder only. Open the app for details. Enabling applies to personal and accessible shared reminders on this device.';

  @override
  String get inboxDeviceEnable => 'Enable system reminders';

  @override
  String get inboxSound => 'Sound';

  @override
  String get inboxDeviceUnsupported =>
      'Timed system notifications are not supported here. The in-app notification center remains available.';

  @override
  String get inboxDeviceDenied =>
      'System permission is not enabled. Change it in device settings and return to the app.';

  @override
  String get inboxDeviceGranted => 'Device permission is enabled.';

  @override
  String get inboxDeviceUnknown =>
      'System permission status has not been confirmed yet.';

  @override
  String get inboxDeviceError =>
      'System reminders could not be prepared. Check device permissions and try again; your data remains saved.';

  @override
  String get inboxDeviceInexact =>
      'Android may deliver the notification later, especially in battery-saving mode.';

  @override
  String inboxDeviceLimit(int count) {
    return '$count later reminders are waiting. The nearest 60 are scheduled; the list is replenished when the app opens or refreshes.';
  }

  @override
  String inboxDeviceScheduled(int count) {
    return 'Scheduled reminders: $count.';
  }

  @override
  String get inboxDeleted => 'The source record was deleted.';

  @override
  String get inboxNeedsConnection =>
      'A connection is needed to verify access and open this notification.';

  @override
  String get inboxWrongAccount =>
      'This notification belongs to another account. Sign in with the correct account.';

  @override
  String get inboxOfflineView =>
      'Offline · last accessible copy. Current server permissions cannot be checked.';

  @override
  String inboxPersonalReminders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Reminders for $count tasks',
      one: 'Reminder for $count task',
    );
    return '$_temp0';
  }

  @override
  String inboxTasksAssigned(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tasks were assigned to you',
      one: '$count task was assigned to you',
    );
    return '$_temp0';
  }

  @override
  String inboxTaskCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tasks were added',
      one: '$count task was added',
    );
    return '$_temp0';
  }

  @override
  String get inboxEventCreated => 'An event was added';

  @override
  String get inboxEventAssigned => 'An event was assigned to you';

  @override
  String get inboxShoppingListCreated => 'A shopping list was added';

  @override
  String inboxShoppingItemsCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items were added',
      one: '$count item was added',
    );
    return '$_temp0';
  }

  @override
  String get inboxMemberJoined => 'A member joined';

  @override
  String get inboxRecordUpdated => 'A record was updated';

  @override
  String get inboxRecordDeleted => 'A record was deleted';

  @override
  String get inboxTaskCompleted => 'A task was completed';

  @override
  String get inboxShoppingChecked => 'An item was marked as bought';

  @override
  String get inboxFinanceChanged => 'A shared finance change';

  @override
  String get inboxProjectChanged => 'A project change';

  @override
  String get inboxReminderDue => 'It is time for a reminder';

  @override
  String get inboxOpenToView => 'Open for details';

  @override
  String get inboxSharedPreferencesUnavailable =>
      'This server does not support notification preferences yet.';

  @override
  String get planningFullDay => 'Full shared day';

  @override
  String get sharingView => 'View';

  @override
  String get financeEditAccount => 'Edit account';

  @override
  String get financeOpeningBalance => 'Opening balance';

  @override
  String get financeDeleteAccountDescription =>
      'You can delete an account when it has no linked entries or transfers.';

  @override
  String get financeEditEntry => 'Edit financial entry';

  @override
  String get financeAccountCurrencyAmount =>
      'Amount in selected account currency';

  @override
  String get financeEditTransfer => 'Edit transfer';

  @override
  String get financeTransferDescription =>
      'A transfer moves funds between shared accounts in the same currency within this space. It does not count as income or expense.';

  @override
  String get financeFromAccount => 'From account';

  @override
  String get financeToAccount => 'To account';

  @override
  String get financeInvalidTransfer =>
      'Choose two different accounts in the same currency.';

  @override
  String get financeNoAudit => 'No financial audit yet.';

  @override
  String get financeRevision => 'Revision';

  @override
  String get financeBefore => 'Before change';

  @override
  String get financeAfter => 'After change';

  @override
  String get financeEnable => 'Enable shared finances';

  @override
  String get financeDisabled => 'Finances are not enabled in this space yet.';

  @override
  String get financeNoAccess =>
      'You do not have finance access in this space. The owner can grant viewing or editing rights.';

  @override
  String get financePermissions => 'Finance access';

  @override
  String get financeGrantNone => 'No access';

  @override
  String get financeGrantRead => 'View';

  @override
  String get financeGrantWrite => 'Edit';

  @override
  String get financeLoadingSnapshot =>
      'Preparing the complete financial overview.';

  @override
  String get financeUnsupported =>
      'This server does not support shared finances yet.';

  @override
  String get financeDisable => 'Disable finances';

  @override
  String get financeDisableDescription =>
      'Finances will be hidden from members. Records and my unsynced changes are retained.';

  @override
  String get financePending => 'Financial changes are waiting to sync.';

  @override
  String get financeBlocked =>
      'Financial changes are blocked. Save a copy before resolving access.';

  @override
  String get financeConflicts => 'Conflicting financial changes';

  @override
  String get inboxPreferencesDescription =>
      'Preferences apply to the selected shared space and notification type. System reminders on this device are a separate setting.';

  @override
  String get inboxChannelInApp => 'In notification center';

  @override
  String get inboxChannelSound => 'Reminder sound';

  @override
  String get inboxChannelPush => 'Remote system notifications';

  @override
  String get inboxChannelEmail => 'Email';

  @override
  String get inboxChannelUnavailable =>
      'This channel is unavailable on this server.';

  @override
  String get inboxPreferencesUnsupported =>
      'This server does not support notification preferences yet.';

  @override
  String get inboxCategoryAssignments => 'Assignments';

  @override
  String get inboxCategoryTasks => 'Tasks and plans';

  @override
  String get inboxCategoryShopping => 'Shopping';

  @override
  String get inboxCategoryMembers => 'Members';

  @override
  String get inboxCategoryReminders => 'Reminders';

  @override
  String get inboxCategoryFinance => 'Finances';

  @override
  String get financeHolder => 'Account holder';

  @override
  String get inboxScope => 'Shared space';

  @override
  String get inboxCategoryEvents => 'Events';

  @override
  String get inboxJoinedScope => 'You joined the space';

  @override
  String get financeUnsupportedCurrency =>
      'Editing this currency is not supported yet. The amount remains preserved in minor units.';

  @override
  String get financeTotalBalance => 'Total balance';

  @override
  String inboxPushCategoriesNone(String space) {
    return 'No remote notification types are selected for “$space”.';
  }

  @override
  String inboxPushCategoriesSelected(String space, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count remote notification types selected.',
      one: '1 remote notification type selected.',
    );
    return 'Space “$space”: $_temp0';
  }

  @override
  String get inboxPushCategoriesDescription =>
      'Choose notification types separately for each space. For scheduled reminders, enable the channel you want in Reminders below.';

  @override
  String get remotePushRegistrationOnly =>
      'Registration connects this device to your account. Choose notification types for individual spaces separately.';

  @override
  String get remoteReminderTitle => 'Remote reminder';

  @override
  String get remoteReminderDescription =>
      'This reminder is only for your account. The server saves it in your inbox; phone or email delivery depends on your settings and connection.';

  @override
  String get remoteReminderDate => 'Reminder date';

  @override
  String get remoteReminderTime => 'Reminder time';

  @override
  String get remoteReminderAdd => 'Add remote reminder';

  @override
  String get remoteReminderEdit => 'Edit remote reminder';

  @override
  String get remoteReminderCancel => 'Cancel reminder';

  @override
  String get remoteReminderQueued =>
      'Waiting for server confirmation. Delivery is not confirmed yet.';

  @override
  String get remoteReminderScheduled => 'The schedule is saved on the server.';

  @override
  String get remoteReminderDelivered => 'The reminder was added to your inbox.';

  @override
  String get remoteReminderCancelled => 'The reminder is cancelled.';

  @override
  String get remoteReminderBlocked =>
      'The change was not accepted. Check your access and refresh the data.';

  @override
  String get remoteReminderFuture => 'Choose a future time.';

  @override
  String get remoteReminderUnavailable =>
      'A remote reminder is unavailable for this record.';

  @override
  String get remoteReminderSaved =>
      'The reminder is saved on this device and waiting for the server.';

  @override
  String get remoteReminderCancelQueued =>
      'Cancellation is saved on this device and waiting for the server.';

  @override
  String get remotePushTitle => 'Remote notifications on this device';

  @override
  String get remotePushPrivacy =>
      'Notifications show generic text. Content opens only after checking the account and access.';

  @override
  String get remotePushEnable => 'Enable remote notifications';

  @override
  String get remotePushUnsupported =>
      'Remote notifications are prepared for Android and iPhone. Use the inbox on this platform.';

  @override
  String get remotePushUnconfigured =>
      'This build has no Firebase configuration yet. The inbox and local reminders remain available.';

  @override
  String get remotePushInvalidConfiguration =>
      'Notification configuration does not match this app. An updated installation is required.';

  @override
  String get remotePushNeedsAccount =>
      'Sign in to receive remote notifications. Personal use remains available without an account.';

  @override
  String get remotePushDisabled =>
      'Remote notifications on this device are disabled.';

  @override
  String get remotePushPreparing =>
      'Preparing permission and device registration…';

  @override
  String get remotePushDenied =>
      'Notifications are blocked by the system. Enable them in device settings and try again.';

  @override
  String get remotePushWaitingApns =>
      'Waiting for Apple to register this device. Check the connection and push-enabled signing.';

  @override
  String get remotePushRegistered =>
      'This device is registered. Choose notification types for each shared space.';

  @override
  String get remotePushOffline =>
      'Registration is waiting for a connection. App changes remain saved.';

  @override
  String get remotePushServerUnavailable =>
      'The server has no compatible remote notification configuration. The inbox remains available.';

  @override
  String get remotePushProjectMismatch =>
      'The app and server use different Firebase projects. This device is not registered.';

  @override
  String get remotePushCleanupRequired =>
      'The previous device registration could not be removed. Retry before enabling another account.';

  @override
  String get remotePushError =>
      'Remote notifications could not be prepared. Retry; the inbox remains available.';

  @override
  String get remotePushRetry => 'Check notifications again';

  @override
  String get remotePushLoginForOpen =>
      'Sign in to the account that received this notification.';

  @override
  String get remotePushDeviceUnavailable =>
      'First enable and register remote notifications on this device.';

  @override
  String get setupTitle => 'How would you like to start?';

  @override
  String get setupIntro =>
      'Choose how you want to use Jivie. You can change how you use the app in settings later.';

  @override
  String get setupHint =>
      'Your personal space already works without an account. Optionally connect your devices or create a shared home.';

  @override
  String get setupChoose => 'Choose your starting point';

  @override
  String get setupDeviceOnly => 'Only on this device';

  @override
  String get setupDeviceOnlyDescription =>
      'No account or server. Protect your data with a backup.';

  @override
  String get setupPrivateDevices => 'Connect my devices';

  @override
  String get setupPrivateDevicesDescription =>
      'Private synchronization of my data. Enable upload separately after signing in.';

  @override
  String get setupHousehold => 'Shared home';

  @override
  String get setupHouseholdDescription =>
      'Create a home and invite another person. Your personal space stays separate.';

  @override
  String get setupOpen => 'Getting started';

  @override
  String get inviteOpenTitle => 'Open invitation';

  @override
  String get inviteOpenWarning =>
      'Check the server address. Invitations are not accepted automatically; preview it first.';

  @override
  String get inviteOpenContinue => 'Continue to invitation';

  @override
  String get inviteLinkInvalid =>
      'This link is not a valid invitation. You can enter the server and code manually in the app.';

  @override
  String get inviteCopyLink => 'Copy invitation link';

  @override
  String get inviteLinkPrepared =>
      'The link opens the invitation in the installed Jivie app. If the app does not open, enter the server and code manually in the app.';

  @override
  String get accountFirstTitle => 'First account with a code';

  @override
  String get accountFirstDescription =>
      'The server operator provides a one-use setup code. This creates a regular user account. Once the first account exists, others join by invitation.';

  @override
  String get accountBootstrapCode => 'Operator setup code';

  @override
  String get accountCreate => 'Create account';

  @override
  String accountCreatedSignedIn(String username) {
    return 'Your account is created. You are signed in as $username.';
  }

  @override
  String accountCreatedSignInRequired(String username) {
    return 'Account $username is created, but sign-in could not be saved on this device. Sign in with this username and the password you chose. Do not use the setup code or invitation again.';
  }

  @override
  String get accountEmailConfirmed => 'Your email address is verified.';

  @override
  String get accountSessionAutoRenew =>
      'Sign-in on this device renews automatically while you use the app.';

  @override
  String get accountPasswordRule => 'Password must contain 12 to 72 bytes.';

  @override
  String get accountForgotPassword => 'Forgot password';

  @override
  String get accountResetRequestDescription =>
      'A code is sent only to an already verified email address. For privacy, we do not reveal whether a username exists.';

  @override
  String get accountSendReset => 'Request recovery code';

  @override
  String get accountResetGeneric =>
      'If this account supports recovery, a code was sent to its verified address.';

  @override
  String get accountResetConfirm => 'I have a recovery code';

  @override
  String get accountResetConfirmDescription =>
      'Enter the received code and a new password. Two-factor accounts also require a TOTP code. Sign in again afterward; old device sessions are revoked.';

  @override
  String get accountEmailCode => 'Email code';

  @override
  String get accountResetPassword => 'Reset password';

  @override
  String get accountResetDone =>
      'Password reset. Sign in with the new password.';

  @override
  String get accountEmailTitle => 'Email and account recovery';

  @override
  String get accountEmailNone => 'No email address is set yet.';

  @override
  String get accountEmailVerified => 'Verified address';

  @override
  String get accountEmailUnverified => 'Address is not verified yet';

  @override
  String get accountEmailPending => 'Awaiting verification';

  @override
  String get accountEmailChange => 'Set or change email';

  @override
  String get accountEmailRequestDescription =>
      'Confirm your password again and TOTP if required. Your current verified address stays active until you verify the new one.';

  @override
  String get accountEmail => 'Email address';

  @override
  String get accountEmailSend => 'Send verification code';

  @override
  String get accountEmailConfirm => 'Confirm email code';

  @override
  String get accountEmailSent =>
      'A verification code was requested. Enter it after receiving the email.';

  @override
  String get accountEmailUnavailable =>
      'The server has not configured account security email yet.';

  @override
  String get accountCodeInvalid =>
      'The code is invalid, expired or already used. Request a new one.';

  @override
  String get accountEnrollmentUnavailable =>
      'First-account setup is no longer available here. Sign in or use an invitation.';

  @override
  String get planningPhases => 'Phases and milestones';

  @override
  String get planningAddPhase => 'Add phase';

  @override
  String get planningPhaseTitle => 'Phase name';

  @override
  String get planningMilestone => 'Milestone';

  @override
  String get planningRemovePhase => 'Remove phase';

  @override
  String get planningNoPhase => 'No phase';

  @override
  String get planningEstimateMinutes => 'Estimated work in minutes';

  @override
  String get planningAvailabilityMinutes => 'Available minutes';

  @override
  String get planningAvailabilityPeriod => 'Availability period';

  @override
  String get planningPerDay => 'Per day';

  @override
  String get planningPerWeek => 'Per week';

  @override
  String get planningTimerStart => 'Start timer';

  @override
  String get planningTimerPause => 'Pause';

  @override
  String get planningElapsed => 'Elapsed time';

  @override
  String get planningRemaining => 'Remaining time';

  @override
  String get planningEstimated => 'Estimated time';

  @override
  String get planningCalendar => 'Calendar dates';

  @override
  String get taskCostTitle => 'Task cost';

  @override
  String get taskCostEnabled => 'Add cost';

  @override
  String get taskCostPaid => 'Paid';

  @override
  String get taskCostPlanned => 'Planned';

  @override
  String get taskCostAccount => 'Financial account';

  @override
  String get taskCostUnassignedAccount => 'No account selected';

  @override
  String get taskCostPayer => 'Payer';

  @override
  String get taskCostRecipient => 'Recipient';

  @override
  String get taskCostAuthor => 'Entry author';

  @override
  String get taskCostNoDue =>
      'Without a task due date, the cost has no planned date.';

  @override
  String get taskCostDetachHint =>
      'Removing the link preserves the financial entry.';

  @override
  String get spacePickerTitle => 'Space';

  @override
  String get organizationTitle => 'Organization';

  @override
  String get organizationCreate => 'Create organization';

  @override
  String get organizationProjects => 'Organization projects';

  @override
  String get organizationCreateProject => 'Add organization project';

  @override
  String get organizationAccessDescription =>
      'Membership does not grant access to every project or finances. Set access for each project separately.';

  @override
  String get peopleTitle => 'People';

  @override
  String get peopleAdd => 'Add person';

  @override
  String get peopleName => 'Name';

  @override
  String get peopleNotes => 'Notes';

  @override
  String get peopleArchive => 'Archive';

  @override
  String get peopleRestore => 'Restore';

  @override
  String get peopleWithoutAccountDescription =>
      'A person profile has no login or access rights.';

  @override
  String get peopleEmpty => 'Add people whose tasks you want to manage.';

  @override
  String get peopleArchived => 'Archived person';

  @override
  String get financePlanTitle => 'Monthly plan';

  @override
  String get financePlanWizard => 'Set up a financial plan';

  @override
  String get financePlanDescription =>
      'Estimates stay expected until you confirm actual receipt or payment.';

  @override
  String get financePlanLocal =>
      'The plan is saved on this device and in portable backups.';

  @override
  String get financePlanPrivate =>
      'The plan is saved in your selected private space with sync enabled.';

  @override
  String get financePlanUpgrade =>
      'Planning in a synced space requires the newer server finance contract.';

  @override
  String get financePlanMonthEnd =>
      'If the day does not exist in a month, its last day is used.';

  @override
  String get financePlanWeekend =>
      'Weekend salary checks occur on Friday and Monday for the same income. Holidays are not adjusted automatically.';

  @override
  String get financePlanSalary => 'When do you expect your monthly salary?';

  @override
  String get financePlanNoSalary => 'No regular salary';

  @override
  String get financePlanLoan => 'Do you have a loan?';

  @override
  String get financePlanLoanPrincipal => 'Total loan amount (optional)';

  @override
  String get financePlanInstallment => 'Estimated monthly installment';

  @override
  String get financePlanCard => 'Do you have a deferred payment card?';

  @override
  String get financePlanCardEstimate => 'Estimated monthly settlement';

  @override
  String get financePlanOtherIncome => 'Other monthly income';

  @override
  String get financePlanOtherExpenses => 'Monthly expenses';

  @override
  String get financePlanAddIncome => 'Add income';

  @override
  String get financePlanAddExpense => 'Add expense';

  @override
  String get financePlanEstimatedAmount => 'Estimated amount';

  @override
  String get financePlanDay => 'Day of month';

  @override
  String get financePlanFirstDate => 'First expected date';

  @override
  String get financePlanSalaryLabel => 'Salary';

  @override
  String get financePlanLoanLabel => 'Loan installment';

  @override
  String get financePlanCardLabel => 'Card settlement';

  @override
  String get financePlanReview => 'Review plan';

  @override
  String get financePlanSave => 'Save plan';

  @override
  String get financePlanRules => 'Monthly recurrences';

  @override
  String get financePlanAddRule => 'Add monthly rule';

  @override
  String get financePlanEditRule => 'Edit monthly rule';

  @override
  String get financePlanRuleActive => 'Rule is active';

  @override
  String get financePlanReminders => 'Reminders for this plan';

  @override
  String get financePlanReminderTime => 'Reminder time';

  @override
  String get financePlanReminderOptIn =>
      'This does not enable phone permission. Enable device reminders in notification settings.';

  @override
  String get financePlanSalaryQuestion => 'Have you received your salary?';

  @override
  String get financePlanConfirm => 'Confirm actual amount';

  @override
  String get financePlanActualAmount => 'Actual amount';

  @override
  String get financePlanActualDate => 'Receipt or payment date';

  @override
  String get financePlanConfirmed => 'The actual amount is confirmed.';

  @override
  String get financePlanForecast => 'Forecast by date';

  @override
  String get financePlanNetChange => 'Expected net change';

  @override
  String get financePlanProjectedBalance => 'Projected balance';

  @override
  String get financePlanOpeningBalance => 'Opening balance (optional)';

  @override
  String get financePlanOpeningDate => 'Opening balance at the start of day';

  @override
  String get financePlanNoOpening =>
      'No opening balance is set; net change is shown.';

  @override
  String get financePlanUndated =>
      'Undated entries are excluded from the dated forecast.';

  @override
  String get financePlanSymbolicAccount =>
      'This is a named ledger account; it does not move money or connect to a bank.';

  @override
  String get financePlanEmpty => 'No dated entries in the selected period.';

  @override
  String get financePlanRuleType => 'Recurrence type';

  @override
  String get financePlanSaved => 'The financial plan is saved.';

  @override
  String get financePlanOverdue => 'Still unconfirmed';

  @override
  String get financePlanBack => 'Back';

  @override
  String get financePlanNext => 'Next';

  @override
  String get financePlanDateNeeded => 'Choose a date.';

  @override
  String get financePlanNoItems => 'No additional entries.';

  @override
  String get financePlanAccountName => 'Financial account name';

  @override
  String get financePlanAccountArchived => 'Archived account';

  @override
  String get financePlanReminderBody =>
      'Have you received your salary? Open the expected income and confirm the actual amount.';

  @override
  String get peopleTaskSubjects => 'Who this task concerns';

  @override
  String get financePlanYes => 'Yes';

  @override
  String get financePlanNo => 'No';

  @override
  String get financePlanRecordedChange => 'Recorded net change';

  @override
  String get financePairedConflict =>
      'Review the task and cost conflict in finances.';

  @override
  String get deletionDetachOrganization =>
      'Keep this project as an independent space when the organization is deleted. Its members and finances remain unchanged.';

  @override
  String get deletionOrganizationLinks =>
      'Projects detached from an organization';

  @override
  String get financePlanIncomeQuestion => 'Have you received this income?';

  @override
  String get financePlanExpenseQuestion => 'Has this obligation been paid?';

  @override
  String get financePlanIncomeReminderBody =>
      'Have you received this income? Open the expected entry and confirm the actual amount.';

  @override
  String get financePlanExpenseReminderBody =>
      'Has this obligation been paid? Open the planned entry and confirm the actual amount.';

  @override
  String get financePlanManageRule =>
      'Manage a recurring entry through its monthly rule. Disabling the rule stops future entries and preserves confirmed history.';

  @override
  String get scopeArchivedProjects => 'Archived projects';

  @override
  String get scopeArchivedDescription =>
      'This project is archived. Data and financial history remain available according to your permissions; tasks do not contribute to the daily overview or reminders.';

  @override
  String get peopleCopyDescription =>
      'Related person profiles (names and notes) will also be copied into the selected space.';

  @override
  String get financePlanPrincipalOnlyLoan =>
      'The total loan amount can only be entered for a loan installment.';

  @override
  String get financePlanOpeningUndated => 'No reference date';

  @override
  String planningInvalidMinutes(int max) {
    return 'Enter a positive number of minutes, up to $max.';
  }

  @override
  String get taskCostSelectAccount => 'Choose a financial account.';

  @override
  String get financeDuplicateOccurrence =>
      'Another device already created the canonical entry for this month. Your local version is kept for comparison; the same income or expense is not counted twice.';

  @override
  String get financePairedTaskReview =>
      'Linked task: these changes and the cost will be reviewed together.';

  @override
  String get privateSyncTitle => 'My devices';

  @override
  String get privateSyncDescription =>
      'A private space for this account only. Other people cannot be invited.';

  @override
  String get privateSyncOff =>
      'Personal data currently stays on this device. Signing in does not upload it automatically.';

  @override
  String get privateSyncReview => 'Review before enabling';

  @override
  String get privateSyncEnable => 'Enable private synchronization';

  @override
  String get privateSyncUploadWarning =>
      'This uploads the reviewed personal records, including personal finances, to your account’s private space. Server synchronization is not a backup.';

  @override
  String get privateSyncRemoteCount => 'Existing records in private space';

  @override
  String get privateSyncOn => 'Private synchronization is enabled.';

  @override
  String get privateSyncPaused =>
      'Synchronization is paused. Local work remains saved.';

  @override
  String get privateSyncPause => 'Pause synchronization';

  @override
  String get privateSyncResume => 'Resume synchronization';

  @override
  String get privateSyncUnavailable =>
      'Private synchronization requires sign-in and a supported server.';

  @override
  String get privateSyncPending => 'Pending changes';

  @override
  String get privateSyncIssue =>
      'Resolve incompatible or conflicting records before enabling. Personal data stays on this device.';

  @override
  String get backupTitle => 'Encrypted backup';

  @override
  String get backupDescription =>
      'A password protects this copy of personal records, settings and authorized shared work. Credentials are excluded. This does not add encryption to the active database.';

  @override
  String get backupCreate => 'Create backup';

  @override
  String get backupRestore => 'Restore backup';

  @override
  String get backupPassword => 'Backup password';

  @override
  String get backupPasswordHint =>
      'The password is not saved. If you forget it, we cannot open the backup.';

  @override
  String get backupPasswordRule =>
      'Use at least 12 characters and no more than 1024 UTF-8 bytes.';

  @override
  String get backupPrepare => 'Prepare encrypted backup';

  @override
  String get backupPick => 'Choose encrypted backup';

  @override
  String get backupOpen => 'Open and review backup';

  @override
  String get backupReview => 'Content review';

  @override
  String get backupSave => 'Save backup file';

  @override
  String get backupSaved => 'Backup file saved.';

  @override
  String get backupCreatedAt => 'Created';

  @override
  String get backupScopes => 'Shared spaces in backup';

  @override
  String get backupPending => 'Unsent operations in backup';

  @override
  String get backupCredentialsExcluded =>
      'Passwords, device sessions and notification tokens are excluded.';

  @override
  String get backupRemoteQuarantine =>
      'Restored shared work stays protected and separate. After signing in to the matching account, review it and explicitly allow recovery; nothing is sent automatically.';

  @override
  String get backupMerge => 'Merge with personal records';

  @override
  String get backupReplace => 'Replace personal records';

  @override
  String get backupMergeDescription =>
      'Add missing personal records. Different content with the same ID rejects the entire merge.';

  @override
  String get backupReplaceDescription =>
      'The backup replaces current personal records. Save a current backup first.';

  @override
  String get backupRestoreConfirm => 'Confirm restore';

  @override
  String get backupRestored =>
      'Backup restored. Shared work is not sent automatically.';

  @override
  String get backupWrongPassword =>
      'The password is incorrect or the backup is damaged. Data was not changed.';

  @override
  String get backupUnsupported =>
      'This backup version cannot be opened. Use a compatible app.';

  @override
  String get backupChanged =>
      'This preview is no longer current. Prepare the backup again or review the contents before restoring.';

  @override
  String get backupRecoveryTitle => 'Restored shared work';

  @override
  String get backupRecoveryReview => 'Review restored work';

  @override
  String get backupRecoveryResume => 'Allow restored work to resume';

  @override
  String get backupRecoveryBlocked =>
      'This work requires the matching account and current access. The copy remains protected.';

  @override
  String get backupRecoveryNone => 'No restored shared-work packages.';

  @override
  String get backupReadError =>
      'The backup could not be opened or saved. Try again.';

  @override
  String get backupShoppingItems => 'Shopping items';

  @override
  String get backupOtherRecords => 'Other records';

  @override
  String get backupSaveCancelled => 'Saving cancelled. The file was not saved.';

  @override
  String get backupDownloadStarted =>
      'Backup download started. Check your browser downloads.';

  @override
  String get backupSourceAccount => 'Backup account';

  @override
  String get backupSourceServer => 'Backup server';

  @override
  String get backupLocalOnly => 'Device only';

  @override
  String get backupAccountMatches =>
      'Personal records can be restored locally. Resuming shared work checks the account and permissions again.';

  @override
  String get backupAccountDifferent =>
      'The backup belongs to another account. Shared work stays protected until you sign in to the matching account.';

  @override
  String get backupCompleteness =>
      'The backup includes personal content, permitted cached records and unsynced work. Server data that has not been downloaded to this device is excluded. Reminder snoozes apply only on this device and are not included.';

  @override
  String get backupTooLarge =>
      'The backup exceeds the 64 MiB limit. Your data was not changed.';

  @override
  String get backupMergeConflict =>
      'The backup contains different content with an existing ID. Merge was rejected; your data was not changed.';

  @override
  String get privateSyncLocalPending =>
      'New local records are awaiting your review.';

  @override
  String get backupRecoveryState => 'Recovered work status';

  @override
  String get backupRecoveryReady => 'Ready to review and resume';

  @override
  String get backupLegacyJson => 'Legacy unencrypted JSON export';

  @override
  String get backupIncomplete =>
      'Some cached spaces in this backup are incomplete. They need to sync again after restoration.';

  @override
  String get backupArchiveReview =>
      'Separate unlocked backup preview. These records do not enter the active account until you explicitly resume permitted work.';

  @override
  String get backupCached => 'Cached record; no pending change';

  @override
  String get backupSettingsRetry =>
      'Restored settings have not been applied yet. Your records are preserved; try again.';

  @override
  String get privateFinanceIncomplete =>
      'The private financial view has not fully downloaded. Visible records and pending changes are preserved; totals appear after a complete sync.';

  @override
  String get guideTitle => 'Welcome to Jivie';

  @override
  String get guideOpen => 'A quick guide to Jivie';

  @override
  String get guideLocalTitle => 'Start on your device';

  @override
  String get guideLocalBody =>
      'Start with a task or event in your personal space. Create households and organizations without an account; select a household for shopping lists, gardens and people. Data stays on your device; explicitly enable connection and synchronization.';

  @override
  String get guideTodayBody =>
      'Today shows your next tasks and events. Add a task or event here and see what is coming up. A shared daily overview is available for spaces you can access.';

  @override
  String get guidePlansBody =>
      'Organize tasks and dates in Tasks. Open Projects and Calendar directly from the menu. The space selected above determines whose content you edit.';

  @override
  String get guideShoppingBody =>
      'A household has its own shopping lists, gardens and people. Add items and mark purchases. Existing personal lists and gardens remain available; choose a household before assigning them.';

  @override
  String get guideMoreBody =>
      'On a phone, use the ☰ menu; on a tablet, More; on a computer, the sidebar. Areas follow the selected space: Personal, Household or Organization. All shows permitted contents together; create records in a concrete space. Work locally without an account. Connect an account separately; Connect and synchronize reviews the space, account and server before uploading. Manage members, invitations and roles in Space settings.';

  @override
  String get guideSkip => 'Skip';

  @override
  String get guideBack => 'Back';

  @override
  String get guideNext => 'Next';

  @override
  String get guideDone => 'Get started';

  @override
  String guideProgress(int step, int total) {
    return '$step of $total';
  }

  @override
  String get deletionAccountSettings => 'Account settings';

  @override
  String get deletionTitle => 'Permanently delete account';

  @override
  String get deletionLocalOnly =>
      'You are using local mode. There is no server account to delete. Local work stays on your device.';

  @override
  String get deletionWarning =>
      'Deletion affects the displayed account on this self-hosted server, including the same Kanboard account. It is permanent. Copies already obtained by other members cannot be recalled.';

  @override
  String get deletionPreview => 'Review account deletion';

  @override
  String get deletionLocalConsequences =>
      'Deletion also removes this account’s private SYNCED data, its local server copy, pending changes, reminders, sync binding and staged recovery work. Independent personal data in the local workspace remains. Synced data is not automatically copied back to local mode.';

  @override
  String get deletionExportLimit =>
      'An encrypted .vsakdan backup is not a complete Kanboard or attachment archive. It cannot resume this account’s server work after deletion. To retain private synced personal records for standalone use, use the explicit JSON export below. Contact the administrator for a full Kanboard archive before deleting.';

  @override
  String get deletionImpact => 'Server impact';

  @override
  String get deletionSharedRemains => 'shared space remains';

  @override
  String get deletionBlocked =>
      'Resolve the requirements below before deletion, then review the impact again.';

  @override
  String get deletionAcknowledge =>
      'I understand the permanent deletion of this account, its synced data and the described effects on shared work.';

  @override
  String get deletionTypeDelete => 'Type DELETE to confirm';

  @override
  String get deletionConfirm => 'Delete permanently';

  @override
  String get deletionUnknown =>
      'Deletion is not confirmed. The connection was interrupted or the response was inconclusive. Check the status of this same request in Account settings; your password is not stored.';

  @override
  String get deletionNotConfirmed =>
      'The server has not confirmed deletion. The account may still be active. Retry with the same decisions and a fresh password/TOTP.';

  @override
  String get deletionSuccess =>
      'The server confirmed deletion. You can continue in local mode.';

  @override
  String get deletionCheckStatus => 'Check deletion status';

  @override
  String get deletionUnavailable =>
      'This server does not support account deletion in Jivie. Its administrator must enable deletion. Deletion cannot be confirmed offline.';

  @override
  String get deletionStale =>
      'Data has changed. Review the impact again and confirm your decisions.';

  @override
  String get deletionPersonalScopes => 'Private spaces to delete';

  @override
  String get deletionPersonalRecords => 'Private records to delete';

  @override
  String get deletionPersonalFinance => 'Private finance records to delete';

  @override
  String get deletionMemberships => 'Memberships to remove';

  @override
  String get deletionDevices => 'Devices and sessions to revoke';

  @override
  String get deletionPush => 'Push registrations to remove';

  @override
  String get deletionEmailTokens => 'Email codes to revoke';

  @override
  String get deletionRelatedData => 'Related records to remove';

  @override
  String get deletionOwnedScopes => 'Choose a new owner for the shared space';

  @override
  String get deletionLastAdmin => 'Assign another Kanboard administrator first';

  @override
  String get deletionContributions =>
      'Resolve your contributions and their shared references';

  @override
  String get deletionStructure =>
      'Keep only a generic structure for other members’ records. The original name and owner are removed; a finance account retains its currency and opening balance. My entries are deleted and shared totals may change.';

  @override
  String get deletionSharedRecordsDeleted => 'Own shared records to delete';

  @override
  String get deletionSharedRecordsUpdated => 'Shared records to detach';

  @override
  String get deletionSharedFinanceDeleted =>
      'Own shared finance records to delete';

  @override
  String get deletionSharedFinanceUpdated => 'Shared finance records to detach';

  @override
  String get deletionLegacyTasks => 'Own Kanboard tasks to delete';

  @override
  String get deletionLegacyComments => 'Own Kanboard comments to delete';

  @override
  String get deletionLegacyFiles => 'Own Kanboard attachments to delete';

  @override
  String get deletionAssignedTasks => 'Kanboard tasks to unassign';

  @override
  String get deletionAssignedSubtasks => 'Kanboard subtasks to unassign';

  @override
  String get deletionLegacyPrivate =>
      'Resolve the private Kanboard project first';

  @override
  String get deletionServerCleanup =>
      'The account and database records have been removed. The server is still deleting attachments; check status until completion is confirmed.';

  @override
  String get deletionRetry => 'Retry the same request';

  @override
  String get deletionRetryReview =>
      'This retry uses the same decisions and the same preview below. Enter your password and TOTP again. If the preview is stale, the server rejects deletion and requires a new review.';

  @override
  String get deletionDeleteOwnedScope =>
      'Permanently delete this space and its content too';

  @override
  String get deletionUnnamedStructure =>
      'Shared structure without permission to view details';

  @override
  String get deletionMinorUnits => 'minor currency units';

  @override
  String get deletionRetainedEdits =>
      'Server records created by your account are deleted. Records created by others remain, including your edits to their content. Your identity references are removed; individual field edits cannot be separated by author.';

  @override
  String get jiviePrivacyLink => 'Privacy';

  @override
  String get jivieHelpLink => 'Help and support';

  @override
  String get jivieDeletionLink => 'Account deletion website';

  @override
  String get jivieLinkFailed => 'Could not open the link.';

  @override
  String get deletionSpaceDeleted =>
      'This shared space and its content will be permanently deleted.';

  @override
  String get deletionCancelPending => 'Cancel pending request';

  @override
  String get deletionCancelled =>
      'The server confirmed cancellation. This request can no longer delete the account. Review the impact again to delete it.';

  @override
  String get deletionLegacyLocal =>
      'Separately stored legacy Kanboard connections, caches and AI conversations are not removed by this action. A legacy connection to the deleted account will no longer work.';

  @override
  String get deletionPersonalExport =>
      'Export personal data for local recovery';

  @override
  String get deletionJsonWarning =>
      'This standalone copy contains currently accessible personal records, including private synced records. JSON is not encrypted; save it securely. It contains no shared work, sessions or sync bindings. After deletion, explicitly import it in local mode through Settings. Do not upload recovered data to another account without your explicit choice.';

  @override
  String get gardenTitle => 'Garden';

  @override
  String get gardenIntro =>
      'Keep planting notes and arrange beds, plants or other areas by hand.';

  @override
  String get gardenLocalOnly => 'On this device · no sync or sharing';

  @override
  String get gardenNew => 'New garden';

  @override
  String get gardenEdit => 'Edit garden';

  @override
  String get gardenName => 'Garden name';

  @override
  String get gardenNameRequired => 'Enter a garden name.';

  @override
  String get gardenEmptyTitle => 'Your first garden';

  @override
  String get gardenEmptyBody =>
      'Name your garden, add notes and draw its layout. You can edit everything without an account or connection.';

  @override
  String get gardenLayout => 'Layout';

  @override
  String get gardenSelectTool => 'Select / move';

  @override
  String get gardenDrawTool => 'Draw area';

  @override
  String get gardenUndo => 'Undo layout change';

  @override
  String get gardenDrawHelp =>
      'Drag from one corner to another to draw a rectangular area.';

  @override
  String get gardenSelectHelp =>
      'Tap a bed to select it. Drag it to move or drag a corner handle to resize. The form remains available in the list.';

  @override
  String get gardenCanvasDescription =>
      'Garden layout sketch. Areas can also be edited in the list.';

  @override
  String get gardenSketchDisclaimer =>
      'This is a layout sketch, without a physical scale or real distances. Confirm your changes with Save.';

  @override
  String get gardenAreas => 'Areas';

  @override
  String get gardenAreaListHelp =>
      'You can also add and edit areas using a form, without drawing.';

  @override
  String get gardenAddArea => 'Add area';

  @override
  String get gardenNoAreas =>
      'No areas yet. Draw the first one or add it using the form.';

  @override
  String get gardenEditArea => 'Edit area';

  @override
  String get gardenAreaLabel => 'What goes here?';

  @override
  String get gardenLabelRequired => 'Enter an area label.';

  @override
  String get gardenPositionX => 'From left';

  @override
  String get gardenPositionY => 'From top';

  @override
  String get gardenWidth => 'Width';

  @override
  String get gardenHeight => 'Height';

  @override
  String get gardenGeometryHelp =>
      'Position and size are percentages of the whole sketch.';

  @override
  String get gardenNumberError => 'Enter 0–100; size must be greater than 0.';

  @override
  String get gardenGeometryError =>
      'The whole area must stay inside the sketch. Reduce its size or adjust its position.';

  @override
  String get gardenUnsavedTitle => 'Unsaved changes';

  @override
  String get gardenUnsavedBody =>
      'Your garden changes have not been saved. Leaving the editor discards them.';

  @override
  String get gardenKeepEditing => 'Keep editing';

  @override
  String get gardenDiscard => 'Discard changes';

  @override
  String get gardenSaveError =>
      'Could not save changes. Your draft is still open. Try again; if the saved garden changed, reopen it.';

  @override
  String get gardenDeleteTitle => 'Delete garden?';

  @override
  String gardenDeleteBody(String name) {
    return 'The garden “$name”, its notes and all areas will be deleted from this device.';
  }

  @override
  String gardenDefaultArea(int number) {
    return 'Area $number';
  }

  @override
  String gardenAreaCount(int count) {
    return '$count areas';
  }

  @override
  String gardenAreaPosition(int x, int y, int width, int height) {
    return 'Left $x%, top $y% · $width × $height%';
  }

  @override
  String get financePlanPendingEntries => 'Unconfirmed entries';

  @override
  String get financePlanPendingDescription =>
      'All expected income and expenses, including undated entries and entries beyond the forecast. Open an entry to confirm the actual amount.';

  @override
  String get financePlanUndatedEntry => 'No date set';

  @override
  String financePlanForecastPeriod(String date) {
    return 'Dated entries through $date, showing the closing total for each day.';
  }

  @override
  String get organizerMenuOpen => 'Open menu';

  @override
  String get organizerMenuClose => 'Close menu';

  @override
  String get planningCapacityTitle => 'Approximate duration';

  @override
  String get planningCapacityRule =>
      'We use remaining estimated work and assume tasks are done in sequence. A task uses its own availability, otherwise the project’s; tasks share project capacity. Weekly capacity is averaged over seven days. This is an approximate amount of time, not a promised date; weekends and actual working days are not scheduled.';

  @override
  String planningCapacityDuration(String days) {
    return 'Approximate duration in days: $days';
  }

  @override
  String planningCapacityMissingEstimates(int count) {
    return 'Open tasks without an effort estimate: $count.';
  }

  @override
  String planningCapacityMissingAvailability(int count) {
    return 'Open tasks without daily or weekly availability: $count.';
  }

  @override
  String get planningCapacityNoTasks => 'No tasks to estimate duration.';

  @override
  String get planningCapacityComplete => 'All tasks are complete.';

  @override
  String organizationProjectPreview(String name) {
    return 'Organization: $name';
  }

  @override
  String get organizationProjectInitialVisibility =>
      'Initially only the creator can access this project. Other organization members and external collaborators gain access only through an explicit project invitation.';

  @override
  String get organizationProjectCreated =>
      'Project created. You can now invite collaborators or open the project.';

  @override
  String get organizationProjectOpen => 'Open project';

  @override
  String get reminderSnooze => 'Snooze reminder';

  @override
  String get reminderSnooze15Minutes => 'In 15 minutes';

  @override
  String get reminderSnooze1Hour => 'In one hour';

  @override
  String get reminderSnoozeTomorrow => 'Tomorrow at this time';

  @override
  String get reminderSnoozeChooseTime => 'Choose date and time';

  @override
  String get reminderSnoozeSaved => 'Reminder snoozed.';

  @override
  String get reminderSnoozeFutureRequired => 'Choose a future time.';

  @override
  String get reminderSnoozeNeedsConnection =>
      'Connect to the server to snooze a shared reminder.';

  @override
  String reminderSnoozedUntil(String until) {
    return 'Snoozed until $until';
  }

  @override
  String financeSourceTask(String title) {
    return 'Linked task: $title';
  }

  @override
  String financeSourceProject(String title) {
    return 'Project: $title';
  }

  @override
  String get financeSourceUnlinked => 'No linked task';

  @override
  String get financeSourceUnavailable =>
      'The linked task is no longer available.';

  @override
  String get financeAccountUnavailable =>
      'The financial account is no longer available.';

  @override
  String get financeNoFilterResults => 'No entries for the selected account.';

  @override
  String get reminderSnoozeDeviceOnly =>
      'Snoozing applies on this device. The task or payment due date stays the same.';

  @override
  String get guideMenuTitle => 'Menu and settings';

  @override
  String get spacePickerCreateAction => 'New space';

  @override
  String get spacePickerNewSpace => '+ New space';

  @override
  String get spacePickerInitialVisibility =>
      'Initially only the creator can access this space. Choose its type and name; other people gain access only through an explicit invitation. Personal data is never moved or shared automatically.';

  @override
  String get spacePickerSharedProject => 'Shared project';

  @override
  String get gardenSeason => 'Season';

  @override
  String get gardenNewSeason => 'New season';

  @override
  String get gardenNoSeasons =>
      'Start with a new season. Your existing bed layout is preserved.';

  @override
  String get gardenSeasonYear => 'Year';

  @override
  String get gardenSeasonYearError => 'Enter a new year between 1900 and 9999.';

  @override
  String get gardenSeasonEmpty => 'Empty season';

  @override
  String get gardenSeasonCopy => 'Copy crops from season';

  @override
  String get gardenSeasonCopyHelp =>
      'Copied crops form a new plan with new entries and no dates. Actual plantings and history in the source season are preserved.';

  @override
  String get gardenSharedGeometry =>
      'The bed layout is shared across seasons. Moving or resizing a bed applies to every year; crops and dates belong to individual seasons.';

  @override
  String get gardenPanTool => 'Pan / zoom';

  @override
  String get gardenPanHelp =>
      'Drag to pan and pinch or use the buttons to zoom. Choose Select / move to edit beds.';

  @override
  String get gardenZoomIn => 'Zoom in';

  @override
  String get gardenZoomOut => 'Zoom out';

  @override
  String get gardenResetView => 'Fit plan';

  @override
  String get gardenBed => 'Bed';

  @override
  String get gardenZone => 'Other area';

  @override
  String get gardenAreaKind => 'Area type';

  @override
  String get gardenArchiveArea => 'Retire bed';

  @override
  String get gardenRestoreArea => 'Restore bed';

  @override
  String get gardenArchivedArea => 'Retired bed · history preserved';

  @override
  String get gardenArchiveHelp =>
      'A retired bed is hidden from the plan. Its plantings and history remain in the list.';

  @override
  String get gardenSelectBed => 'Select a bed on the plan or in the list.';

  @override
  String get gardenSeasonPlantings => 'Crops in selected season';

  @override
  String get gardenNoPlantings =>
      'This bed has no crops in the selected season yet.';

  @override
  String get gardenAddPlanting => 'Add crop';

  @override
  String get gardenEditPlanting => 'Edit crop';

  @override
  String get gardenCrop => 'Crop';

  @override
  String get gardenCropRequired => 'Enter a crop.';

  @override
  String get gardenVariety => 'Variety';

  @override
  String get gardenFamily => 'Plant family';

  @override
  String get gardenFamilyHelp =>
      'Choose a known family or enter your own. We do not infer a family from the crop name.';

  @override
  String get gardenPlantingPlanned => 'Planned';

  @override
  String get gardenPlantingActual => 'Actual planting';

  @override
  String get gardenPlantingStatus => 'Planting status';

  @override
  String get gardenSowDate => 'Sowing';

  @override
  String get gardenPlantDate => 'Planting';

  @override
  String get gardenHarvestDate => 'Harvest';

  @override
  String get gardenChooseDate => 'Choose date';

  @override
  String get gardenClearDate => 'Clear date';

  @override
  String get gardenPlantingDatesError =>
      'Dates must follow the order sowing, planting, harvest.';

  @override
  String get gardenHistory => 'Bed history';

  @override
  String get gardenNoHistory =>
      'No seasons have been recorded for this bed yet.';

  @override
  String get gardenRotationInfo =>
      'We compare entered known families with actual plantings on the same bed during the previous three years. An unknown family or missing history does not mean the rotation is suitable.';

  @override
  String gardenRotationRepeated(String family, String years) {
    return 'The same recorded family $family was planted in this bed in $years.';
  }

  @override
  String get gardenDetails => 'Garden name and notes';

  @override
  String get gardenSeasonNotes => 'Season notes';

  @override
  String get gardenDeletePlanting => 'Delete crop?';

  @override
  String get gardenDeletePlantingBody =>
      'The selected crop entry will be removed from this season.';

  @override
  String get gardenDeleteSeason => 'Delete season?';

  @override
  String get gardenDeleteSeasonBody =>
      'The selected season’s plantings and notes will be removed. The bed layout is preserved.';

  @override
  String get gardenDeleteSeasonAction => 'Delete season';

  @override
  String get gardenConfirmDraft =>
      'After closing this form, save the garden too.';

  @override
  String get gardenSave => 'Save garden';

  @override
  String get gardenUndoPreserved =>
      'The bed with plantings is preserved as retired. Its history is available in the list.';

  @override
  String get gardenFamilySolanaceae => 'Nightshades (Solanaceae)';

  @override
  String get gardenFamilyFabaceae => 'Legumes (Fabaceae)';

  @override
  String get gardenFamilyBrassicaceae => 'Brassicas (Brassicaceae)';

  @override
  String get gardenFamilyApiaceae => 'Umbellifers (Apiaceae)';

  @override
  String get gardenFamilyAsteraceae => 'Composites (Asteraceae)';

  @override
  String get gardenFamilyCucurbitaceae => 'Cucurbits (Cucurbitaceae)';

  @override
  String get gardenFamilyAmaryllidaceae => 'Amaryllis family (Amaryllidaceae)';

  @override
  String get gardenFamilyAmaranthaceae => 'Amaranths (Amaranthaceae)';

  @override
  String get gardenFamilyPoaceae => 'Grasses (Poaceae)';

  @override
  String get allSpacesSources => 'Space overview';

  @override
  String get allSpacesTitle => 'All';

  @override
  String get allSpacesDescription =>
      'Your personal space and all accessible shared spaces. Every entry keeps its source.';

  @override
  String get allSpacesEmpty => 'There are no entries in this view yet.';

  @override
  String get allSpacesChooseTarget => 'Choose a space to add to';

  @override
  String get allSpacesChooseTargetDescription =>
      'Open the intended space and add the entry there.';

  @override
  String get allSpacesOpenSource => 'Open source space';

  @override
  String get allSpacesAdd => 'Add to a space';

  @override
  String get allSpacesFinanceDescription =>
      'Currency summaries include posted income and expenses from permitted, complete data. Transfers are not income or expenses.';

  @override
  String get allSpacesFinanceIncomplete =>
      'Some spaces do not yet have a complete finance snapshot. Totals include only complete sources.';

  @override
  String get allSpacesAllDates => 'All dates';

  @override
  String get allSpacesTodayEmpty =>
      'No open tasks, events or expected payments for today.';

  @override
  String get allSpacesUpcoming => 'Today and overdue';

  @override
  String get organizerPressBackAgainToExit => 'Press back again to exit';

  @override
  String get spaceSettingsTitle => 'Space settings';

  @override
  String get spaceSettingsChoose =>
      'Choose a shared space to manage members and invitations.';

  @override
  String get spaceSettingsConnect =>
      'Connect an account to manage shared spaces.';

  @override
  String get spaceSettingsUnavailable =>
      'This space is currently unavailable. Choose another shared space.';

  @override
  String get localSpaceDescription =>
      'This device stores the space and its records. You explicitly enable connection and sharing later.';

  @override
  String get localSpaceState => 'Local · not synchronized';

  @override
  String get localSpaceAddress => 'Address (optional)';

  @override
  String get localSpaceRename => 'Edit space';

  @override
  String get localSpaceMembersDescription =>
      'People are a record of persons. Account access and invitations require a server connection for the space.';

  @override
  String get localSpaceLinkAction => 'Connect and synchronize';

  @override
  String get legacyLocalData => 'Unassigned data';

  @override
  String get legacyLocalDescription =>
      'These records remain on this device. Choose a household before moving them; connecting a server does not automatically share them.';

  @override
  String get localSpaceMoveToHousehold => 'Assign to household';

  @override
  String localSpaceMovePreview(String name, String household) {
    return 'Move “$name” to household “$household”? The data becomes part of this space. If you later enable sharing, its permissions apply.';
  }

  @override
  String get localSpaceChooseHousehold => 'Choose a household';

  @override
  String get localSpaceNoHouseholds =>
      'First create a local household using the space picker.';

  @override
  String get localSpaceOfflineWork =>
      'Your data remains on this device. Local work continues; invitations and server permission changes require a connection.';

  @override
  String get organizationAggregateDescription =>
      'Activity from permitted projects. Each record retains its source space.';

  @override
  String get organizationLeader => 'Organization leader';

  @override
  String get organizationLeaderGrant => 'Grant leader role';

  @override
  String get organizationLeaderRemove => 'Remove leader role';

  @override
  String get organizationProjectFinanceVisibility =>
      'Accepting this invitation includes access to all finances of this project. Private finances in other spaces remain separate.';

  @override
  String get localSpaceCreate => 'Create space';

  @override
  String get organizationAccessReview => 'Review project finance visibility';

  @override
  String get organizationAccessReviewDescription =>
      'Project members will see all of their project finances. Organization leaders will see all existing and future projects and finances. Review who gains broader access before confirming.';

  @override
  String get organizationAccessApply => 'Confirm new visibility';

  @override
  String get organizationAccessCurrent =>
      'Members see all finances of their projects. Leaders see all organization projects and their finances.';

  @override
  String get organizationAccessNoReaders =>
      'No one gains additional access in this project.';

  @override
  String get organizationAccessPending =>
      'The previous change has no confirmed result. Retry with the same request.';

  @override
  String get organizationAccessResume => 'Check change result';

  @override
  String get organizationAccessPreviewStale =>
      'Visibility changed. Open a new preview.';

  @override
  String get organizationLeaderConfirm =>
      'A leader sees all organization projects and their finances, including future projects. Editing remains controlled by separate permissions.';

  @override
  String get localSpaceConnectionChoose =>
      'Select existing local spaces. Review the account, server and contents before uploading.';

  @override
  String get localSpaceConnectionPreview =>
      'The listed spaces and their records will be connected. Signing in did not enable uploading. Invite members separately in space settings.';

  @override
  String localSpaceConnectionCounts(int records, int gardens) {
    String _temp0 = intl.Intl.pluralLogic(
      records,
      locale: localeName,
      other: '$records records',
      one: '$records record',
    );
    String _temp1 = intl.Intl.pluralLogic(
      gardens,
      locale: localeName,
      other: '$gardens gardens',
      one: '$gardens garden',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get localSpaceConnectionOtherAccount =>
      'The space is linked to another account. Moving it to a new identity requires a separate review.';

  @override
  String get localSpaceConnectionUnsupported =>
      'The server does not yet support uploading this content. The data remains on this device.';

  @override
  String get financeMembershipRead =>
      'Read access from membership · no extra editing';

  @override
  String get financeMembershipReadDescription =>
      'Members see all finances of their project. Here you grant only extra editing access; read access follows membership and leader roles.';

  @override
  String get privateSyncSourceDefault =>
      'This option connects the default personal space. Select households and organizations separately.';

  @override
  String get localFinanceRecoveryIncomplete =>
      'The finance view is incomplete. Some transfers and linked payments remain only in the original backup.';

  @override
  String localSpaceConnectionProjectCounts(
    int tasks,
    int finances,
    int people,
    int accounts,
  ) {
    return '$tasks tasks · $finances financial records · $people people · $accounts accounts';
  }

  @override
  String get offlineRecoveryAction => 'Continue locally';

  @override
  String get offlineRecoveryIntro =>
      'Create new local spaces from the available backup contents. Viewing and editing do not require the old server. Review the contents and limits before confirming.';

  @override
  String get offlineRecoveryArchive =>
      'The original encrypted backup retains its source, pending server work, history and permissions. Some information is not converted into new editable records.';

  @override
  String get offlineRecoveryNoServerAccess =>
      'The new local copy does not grant access to the old server or make you a manager of the original shared spaces.';

  @override
  String get offlineRecoveryFinanceUnavailable =>
      'Finances without known read permission are excluded from the local copy.';

  @override
  String get offlineRecoveryBlocked =>
      'Content with confirmed revoked access remains blocked. Disconnecting does not unlock it.';

  @override
  String get offlineRecoveryNothingAvailable =>
      'This backup has no content available for recovery into a local space.';

  @override
  String get offlineRecoveryAcknowledge =>
      'I understand the limits and want to create new local copies.';

  @override
  String get offlineRecoverySuccess =>
      'Local spaces are ready. Select them above; the original encrypted backup is preserved.';

  @override
  String get paymentPaidPersonally => 'I paid personally';

  @override
  String get paymentMyAccount => 'My account or card';

  @override
  String get paymentChooseAccount => 'Choose an account';

  @override
  String get paymentNeedsPersonalAccount =>
      'First add your account or card in the same currency in your personal space.';

  @override
  String get paymentNeedsRefundAccount =>
      'First add an organization account in the same currency for reimbursement.';

  @override
  String get paymentPaidAt => 'Date of personal payment';

  @override
  String get paymentExpectRefund => 'I expect reimbursement';

  @override
  String get paymentExpectRefundYes => 'Yes, I expect reimbursement';

  @override
  String get paymentExpectRefundNo => 'No reimbursement expected';

  @override
  String get paymentHouseholdInclusion => 'Include in household view';

  @override
  String get paymentNoHousehold => 'Do not include in a household';

  @override
  String get paymentSourceExpenseOnly =>
      'The expense stays in the organization. The selected account records the payment; other personal transactions are not shared.';

  @override
  String get paymentRecord => 'Record personal payment';

  @override
  String get paymentLinkedPayments => 'Personal payments and reimbursements';

  @override
  String get paymentLinkedExpense => 'Payment for an organization';

  @override
  String get paymentRemaining => 'Remaining reimbursement';

  @override
  String get paymentCashBurden => 'Cash burden after reimbursements';

  @override
  String get paymentNoRefundExpected => 'No reimbursement is expected.';

  @override
  String get paymentRefundAction => 'Record reimbursement';

  @override
  String paymentRefundDescription(String amount) {
    return 'Remaining amount: $amount. Reimbursement reduces the payment burden and does not create new income.';
  }

  @override
  String get paymentRefundReceived => 'Reimbursement';

  @override
  String get paymentRefundPaid => 'Reimbursement paid';

  @override
  String get paymentRefundAt => 'Reimbursement date';

  @override
  String get paymentRefundTooHigh =>
      'The amount exceeds the remaining reimbursement.';

  @override
  String get paymentRefundAfterPayment =>
      'Reimbursement cannot precede the personal payment.';

  @override
  String get paymentPending =>
      'The payment is saved. Synchronization across the linked spaces is pending.';

  @override
  String get paymentWaitingSource =>
      'The payment is saved locally. Explicitly connect the organization before sharing it.';

  @override
  String get paymentBlocked =>
      'Synchronization was rejected. The data is preserved; these amounts are not confirmed totals.';

  @override
  String get paymentSourceRemoved => 'Payment history';

  @override
  String get paymentSourceRemovedDescription =>
      'The original shared record is unavailable. Retained payments and reimbursements are history, not evidence of current access or a new receivable.';

  @override
  String get paymentProjectionDescription =>
      'Personal payment view. The expense remains in the organization; reimbursement is not new income.';

  @override
  String get paymentRetry => 'Retry synchronization';

  @override
  String get paymentRefresh => 'Refresh linked payments';

  @override
  String get paymentIncompleteBalance =>
      'A complete account balance also needs linked payment information.';

  @override
  String get paymentAlreadyLinked =>
      'This expense already has a linked personal payment.';

  @override
  String paymentPublicationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count linked payments',
      one: '$count linked payment',
    );
    return '$_temp0';
  }

  @override
  String get paymentPersonalDisplay => 'Personal payment';

  @override
  String get deletionLinkedFinancialFacts =>
      'Linked payments and reimbursements';

  @override
  String get deletionLinkedFinancialRetention =>
      'Keeping or transferring a space retains shared payment and reimbursement amounts, dates and historical references. Private projections and account links are removed. This cannot erase copies already downloaded.';

  @override
  String deletionLinkedScopeCounts(
    String scope,
    int retained,
    int deleted,
    int refunds,
  ) {
    return '$scope: $retained payments if kept; $deleted payments if deleted; $refunds approved reimbursements.';
  }

  @override
  String get deletionRetainedExpenseResolution =>
      'Retain the shared expense and approved payment and reimbursement history, removing my personal notes and title.';

  @override
  String get deletionPrivatePaymentProjections =>
      'Private payment projections to remove';

  @override
  String get deletionSharedPaymentReceipts => 'Already shared payment history';

  @override
  String get deletionLinkedUnavailableScope => 'Previously shared space';

  @override
  String get spaceFinanceIntro => 'Income, expenses and planned costs.';

  @override
  String get spaceLocalShort => 'Local';

  @override
  String get spaceConnectedShort => 'Connected';
}
