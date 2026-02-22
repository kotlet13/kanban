import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_sl.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('sl'),
  ];

  /// No description provided for @kanbanConnect.
  ///
  /// In en, this message translates to:
  /// **'Kanban Connect'**
  String get kanbanConnect;

  /// No description provided for @routeError.
  ///
  /// In en, this message translates to:
  /// **'Route error'**
  String get routeError;

  /// No description provided for @unknownError.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get unknownError;

  /// No description provided for @kanboardWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Kanboard Workspace'**
  String get kanboardWorkspace;

  /// No description provided for @restoringSession.
  ///
  /// In en, this message translates to:
  /// **'Restoring session...'**
  String get restoringSession;

  /// No description provided for @connectToKanboard.
  ///
  /// In en, this message translates to:
  /// **'Connect to Kanboard'**
  String get connectToKanboard;

  /// No description provided for @projects.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get projects;

  /// No description provided for @projectDefaults.
  ///
  /// In en, this message translates to:
  /// **'Project defaults'**
  String get projectDefaults;

  /// No description provided for @aiSettings.
  ///
  /// In en, this message translates to:
  /// **'AI settings'**
  String get aiSettings;

  /// No description provided for @aiChat.
  ///
  /// In en, this message translates to:
  /// **'AI chat'**
  String get aiChat;

  /// No description provided for @connectionSettings.
  ///
  /// In en, this message translates to:
  /// **'Connection settings'**
  String get connectionSettings;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @newProject.
  ///
  /// In en, this message translates to:
  /// **'New project'**
  String get newProject;

  /// No description provided for @couldNotLoadProjects.
  ///
  /// In en, this message translates to:
  /// **'Could not load projects'**
  String get couldNotLoadProjects;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @noActiveSession.
  ///
  /// In en, this message translates to:
  /// **'No active session'**
  String get noActiveSession;

  /// No description provided for @noActiveSessionConnectFirst.
  ///
  /// In en, this message translates to:
  /// **'No active session. Connect first.'**
  String get noActiveSessionConnectFirst;

  /// No description provided for @connectToKanboardToContinue.
  ///
  /// In en, this message translates to:
  /// **'Connect to Kanboard to continue.'**
  String get connectToKanboardToContinue;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @projectsWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Projects Workspace'**
  String get projectsWorkspace;

  /// No description provided for @trackOrganizeAndOpenYourKanboardProjects.
  ///
  /// In en, this message translates to:
  /// **'Track, organize, and open your Kanboard projects.'**
  String get trackOrganizeAndOpenYourKanboardProjects;

  /// No description provided for @connectYourKanboardAccountToLoadProjectData.
  ///
  /// In en, this message translates to:
  /// **'Connect your Kanboard account to load project data.'**
  String get connectYourKanboardAccountToLoadProjectData;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @inactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get inactive;

  /// No description provided for @noProjectsYet.
  ///
  /// In en, this message translates to:
  /// **'No projects yet'**
  String get noProjectsYet;

  /// No description provided for @createYourFirstProjectFromTheActionButtonAndStartOrganizingYourBoard.
  ///
  /// In en, this message translates to:
  /// **'Create your first project from the action button and start organizing your board.'**
  String
  get createYourFirstProjectFromTheActionButtonAndStartOrganizingYourBoard;

  /// No description provided for @openBoard.
  ///
  /// In en, this message translates to:
  /// **'Open board'**
  String get openBoard;

  /// No description provided for @projectAttachments.
  ///
  /// In en, this message translates to:
  /// **'Project attachments'**
  String get projectAttachments;

  /// No description provided for @deleteProject.
  ///
  /// In en, this message translates to:
  /// **'Delete project'**
  String get deleteProject;

  /// No description provided for @noDescriptionYetOpenTheProjectToAddContext.
  ///
  /// In en, this message translates to:
  /// **'No description yet. Open the project to add context.'**
  String get noDescriptionYetOpenTheProjectToAddContext;

  /// No description provided for @deleteProject2.
  ///
  /// In en, this message translates to:
  /// **'Delete project?'**
  String get deleteProject2;

  /// No description provided for @thisWillRemovePermanently.
  ///
  /// In en, this message translates to:
  /// **'This will remove \"{name}\" permanently.'**
  String thisWillRemovePermanently(Object name);

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @createProject.
  ///
  /// In en, this message translates to:
  /// **'Create project'**
  String get createProject;

  /// No description provided for @editProject.
  ///
  /// In en, this message translates to:
  /// **'Edit project'**
  String get editProject;

  /// No description provided for @projectName.
  ///
  /// In en, this message translates to:
  /// **'Project name'**
  String get projectName;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @projectColorSyncedViaMetadata.
  ///
  /// In en, this message translates to:
  /// **'Project color (synced via metadata)'**
  String get projectColorSyncedViaMetadata;

  /// No description provided for @noColor.
  ///
  /// In en, this message translates to:
  /// **'No color'**
  String get noColor;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @attachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments · {name}'**
  String attachments(Object name);

  /// No description provided for @noProjectAttachmentsYet.
  ///
  /// In en, this message translates to:
  /// **'No project attachments yet.'**
  String get noProjectAttachmentsYet;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @addFiles.
  ///
  /// In en, this message translates to:
  /// **'Add files'**
  String get addFiles;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @projectDefaults2.
  ///
  /// In en, this message translates to:
  /// **'Project Defaults'**
  String get projectDefaults2;

  /// No description provided for @appLanguage.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get appLanguage;

  /// No description provided for @followSystemKeepsLocaleAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Follow system keeps locale automatic.'**
  String get followSystemKeepsLocaleAutomatic;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @followSystemDefault.
  ///
  /// In en, this message translates to:
  /// **'Follow system (default)'**
  String get followSystemDefault;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @slovene.
  ///
  /// In en, this message translates to:
  /// **'Slovene'**
  String get slovene;

  /// No description provided for @templateAppliedToEveryNewProjectCreatedFromThisApp.
  ///
  /// In en, this message translates to:
  /// **'Template applied to every new project created from this app.'**
  String get templateAppliedToEveryNewProjectCreatedFromThisApp;

  /// No description provided for @leaveFieldsEmptyToKeepServerDefaults.
  ///
  /// In en, this message translates to:
  /// **'Leave fields empty to keep server defaults.'**
  String get leaveFieldsEmptyToKeepServerDefaults;

  /// No description provided for @savingADefaultCurrencyAlsoAppliesItToAllExistingProjects.
  ///
  /// In en, this message translates to:
  /// **'Saving a default currency also applies it to all existing projects.'**
  String get savingADefaultCurrencyAlsoAppliesItToAllExistingProjects;

  /// No description provided for @defaultBoardColumns.
  ///
  /// In en, this message translates to:
  /// **'Default Board Columns'**
  String get defaultBoardColumns;

  /// No description provided for @defaultBoardColumnsHint.
  ///
  /// In en, this message translates to:
  /// **'One per line, e.g.\\nBacklog\\nReady\\nIn Progress\\nDone'**
  String get defaultBoardColumnsHint;

  /// No description provided for @defaultSwimlane.
  ///
  /// In en, this message translates to:
  /// **'Default Swimlane'**
  String get defaultSwimlane;

  /// No description provided for @exampleMain.
  ///
  /// In en, this message translates to:
  /// **'Example: Main'**
  String get exampleMain;

  /// No description provided for @exampleUSD.
  ///
  /// In en, this message translates to:
  /// **'Example: USD'**
  String get exampleUSD;

  /// No description provided for @defaultExpenseCurrency.
  ///
  /// In en, this message translates to:
  /// **'Default Expense Currency'**
  String get defaultExpenseCurrency;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @enableAI.
  ///
  /// In en, this message translates to:
  /// **'Enable AI'**
  String get enableAI;

  /// No description provided for @instantResponse.
  ///
  /// In en, this message translates to:
  /// **'Instant response'**
  String get instantResponse;

  /// No description provided for @thinkingResponse.
  ///
  /// In en, this message translates to:
  /// **'Thinking response'**
  String get thinkingResponse;

  /// No description provided for @thinkingEffort.
  ///
  /// In en, this message translates to:
  /// **'Thinking effort'**
  String get thinkingEffort;

  /// No description provided for @effortLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get effortLow;

  /// No description provided for @effortMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get effortMedium;

  /// No description provided for @effortHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get effortHigh;

  /// No description provided for @aiModel.
  ///
  /// In en, this message translates to:
  /// **'AI model'**
  String get aiModel;

  /// No description provided for @openAiApiKey.
  ///
  /// In en, this message translates to:
  /// **'OpenAI API key'**
  String get openAiApiKey;

  /// No description provided for @openAiApiKeyIsRequired.
  ///
  /// In en, this message translates to:
  /// **'OpenAI API key is required.'**
  String get openAiApiKeyIsRequired;

  /// No description provided for @testAIConnection.
  ///
  /// In en, this message translates to:
  /// **'Test AI connection'**
  String get testAIConnection;

  /// No description provided for @fetchAvailableModels.
  ///
  /// In en, this message translates to:
  /// **'Fetch available models'**
  String get fetchAvailableModels;

  /// No description provided for @availableModelsFetched.
  ///
  /// In en, this message translates to:
  /// **'Fetched {count} models.'**
  String availableModelsFetched(Object count);

  /// No description provided for @availableModelsFetchFailed.
  ///
  /// In en, this message translates to:
  /// **'Fetching models failed: {error}'**
  String availableModelsFetchFailed(Object error);

  /// No description provided for @aiSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'AI settings saved.'**
  String get aiSettingsSaved;

  /// No description provided for @aiConnectionTestSucceeded.
  ///
  /// In en, this message translates to:
  /// **'AI test succeeded: {result}'**
  String aiConnectionTestSucceeded(Object result);

  /// No description provided for @aiConnectionTestFailed.
  ///
  /// In en, this message translates to:
  /// **'AI test failed: {error}'**
  String aiConnectionTestFailed(Object error);

  /// No description provided for @aiSettingsSecurityNotice.
  ///
  /// In en, this message translates to:
  /// **'Security notice: local key mode is less secure. Anyone with device/app access may extract this key.'**
  String get aiSettingsSecurityNotice;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get saving;

  /// No description provided for @saveDefaults.
  ///
  /// In en, this message translates to:
  /// **'Save defaults'**
  String get saveDefaults;

  /// No description provided for @configureAiInSettings.
  ///
  /// In en, this message translates to:
  /// **'Configure AI in settings before using assistant features.'**
  String get configureAiInSettings;

  /// No description provided for @aiNotEnabledForThisProject.
  ///
  /// In en, this message translates to:
  /// **'AI is not enabled for this project.'**
  String get aiNotEnabledForThisProject;

  /// No description provided for @aiProjectPolicySaved.
  ///
  /// In en, this message translates to:
  /// **'Project AI policy saved.'**
  String get aiProjectPolicySaved;

  /// No description provided for @aiActionPlanDetected.
  ///
  /// In en, this message translates to:
  /// **'AI action plan detected'**
  String get aiActionPlanDetected;

  /// No description provided for @aiActionsApplied.
  ///
  /// In en, this message translates to:
  /// **'Applied actions: swimlanes {swimlanes}, tasks {tasks}.'**
  String aiActionsApplied(Object swimlanes, Object tasks);

  /// No description provided for @aiActionsAppliedDetailed.
  ///
  /// In en, this message translates to:
  /// **'Applied actions: swimlanes {swimlanes}, columns {columns}, new tasks {tasks}, moved tasks {moved}, skipped moves {skipped}.'**
  String aiActionsAppliedDetailed(
    Object swimlanes,
    Object columns,
    Object tasks,
    Object moved,
    Object skipped,
  );

  /// No description provided for @enableAIForProject.
  ///
  /// In en, this message translates to:
  /// **'Enable AI for this project'**
  String get enableAIForProject;

  /// No description provided for @aiKeyMode.
  ///
  /// In en, this message translates to:
  /// **'AI key mode'**
  String get aiKeyMode;

  /// No description provided for @ownerKeyMode.
  ///
  /// In en, this message translates to:
  /// **'Owner key (shared costs)'**
  String get ownerKeyMode;

  /// No description provided for @userKeyRequiredMode.
  ///
  /// In en, this message translates to:
  /// **'Each user needs own key'**
  String get userKeyRequiredMode;

  /// No description provided for @aiCostNoticeTitle.
  ///
  /// In en, this message translates to:
  /// **'AI usage cost notice'**
  String get aiCostNoticeTitle;

  /// No description provided for @aiCostNoticeBody.
  ///
  /// In en, this message translates to:
  /// **'This project uses owner key mode. AI usage here is billed to {owner}.'**
  String aiCostNoticeBody(Object owner);

  /// No description provided for @iUnderstand.
  ///
  /// In en, this message translates to:
  /// **'I understand'**
  String get iUnderstand;

  /// No description provided for @aiChatForProject.
  ///
  /// In en, this message translates to:
  /// **'AI chat · {name}'**
  String aiChatForProject(Object name);

  /// No description provided for @newChat.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get newChat;

  /// No description provided for @continueChat.
  ///
  /// In en, this message translates to:
  /// **'Continue chat'**
  String get continueChat;

  /// No description provided for @exportChat.
  ///
  /// In en, this message translates to:
  /// **'Export chat'**
  String get exportChat;

  /// No description provided for @currentChatId.
  ///
  /// In en, this message translates to:
  /// **'Current chat: {id}'**
  String currentChatId(Object id);

  /// No description provided for @noSavedChatsForProject.
  ///
  /// In en, this message translates to:
  /// **'No saved chats for this project yet.'**
  String get noSavedChatsForProject;

  /// No description provided for @noMessagesToExport.
  ///
  /// In en, this message translates to:
  /// **'No messages to export.'**
  String get noMessagesToExport;

  /// No description provided for @chatExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Chat export failed: {error}'**
  String chatExportFailed(Object error);

  /// No description provided for @aiRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'AI request failed: {error}'**
  String aiRequestFailed(Object error);

  /// No description provided for @aiIsTyping.
  ///
  /// In en, this message translates to:
  /// **'AI is typing...'**
  String get aiIsTyping;

  /// No description provided for @aiSuggestedTitle.
  ///
  /// In en, this message translates to:
  /// **'AI-suggested title'**
  String get aiSuggestedTitle;

  /// No description provided for @aiSuggestedDescription.
  ///
  /// In en, this message translates to:
  /// **'AI-suggested description'**
  String get aiSuggestedDescription;

  /// No description provided for @aiImproveTitle.
  ///
  /// In en, this message translates to:
  /// **'Improve title with AI'**
  String get aiImproveTitle;

  /// No description provided for @aiImproveDescription.
  ///
  /// In en, this message translates to:
  /// **'Improve description with AI'**
  String get aiImproveDescription;

  /// No description provided for @message.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get message;

  /// No description provided for @projectDefaultsReset.
  ///
  /// In en, this message translates to:
  /// **'Project defaults reset.'**
  String get projectDefaultsReset;

  /// No description provided for @resetDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reset defaults?'**
  String get resetDefaults;

  /// No description provided for @thisClearsCustomDefaultsAndUsesKanboardServerDefaultsForNewProjects.
  ///
  /// In en, this message translates to:
  /// **'This clears custom defaults and uses Kanboard server defaults for new projects.'**
  String
  get thisClearsCustomDefaultsAndUsesKanboardServerDefaultsForNewProjects;

  /// No description provided for @connectYourKanboardInstance.
  ///
  /// In en, this message translates to:
  /// **'Connect Your Kanboard Instance'**
  String get connectYourKanboardInstance;

  /// No description provided for @loadedSavedCredentials.
  ///
  /// In en, this message translates to:
  /// **'Loaded saved credentials.'**
  String get loadedSavedCredentials;

  /// No description provided for @connectedViaJsonrpcTokenAuthServerVersion.
  ///
  /// In en, this message translates to:
  /// **'Connected via jsonrpc token auth. Server version: {version}'**
  String connectedViaJsonrpcTokenAuthServerVersion(Object version);

  /// No description provided for @connectedAsVersion.
  ///
  /// In en, this message translates to:
  /// **'Connected as {username}. Version: {version}'**
  String connectedAsVersion(Object username, Object version);

  /// No description provided for @connectedSuccessfullyButServerVersionIsTarget1250.
  ///
  /// In en, this message translates to:
  /// **'Connected successfully, but server version is {version} (target: 1.2.50).'**
  String connectedSuccessfullyButServerVersionIsTarget1250(Object version);

  /// No description provided for @connectionFailedTipIfYouCopiedAPIUserAccessTryUsernameJsonrpcWithThatToken.
  ///
  /// In en, this message translates to:
  /// **'Connection failed: {error}\nTip: if you copied \"API User Access\", try username \"jsonrpc\" with that token.'**
  String
  connectionFailedTipIfYouCopiedAPIUserAccessTryUsernameJsonrpcWithThatToken(
    Object error,
  );

  /// No description provided for @usePersonalTokenUsernameOrUseApplicationTokenWithUsernameJsonrpc.
  ///
  /// In en, this message translates to:
  /// **'Use personal token + username, or use application token with username \"jsonrpc\".'**
  String get usePersonalTokenUsernameOrUseApplicationTokenWithUsernameJsonrpc;

  /// No description provided for @nothingToExportYetConnectOnceOrFillAllFieldsFirst.
  ///
  /// In en, this message translates to:
  /// **'Nothing to export yet. Connect once or fill all fields first.'**
  String get nothingToExportYetConnectOnceOrFillAllFieldsFirst;

  /// No description provided for @scanThisCodeWithYourPhoneInTheConnectScreen.
  ///
  /// In en, this message translates to:
  /// **'Scan this code with your phone in the Connect screen.'**
  String get scanThisCodeWithYourPhoneInTheConnectScreen;

  /// No description provided for @couldNotRenderQRError.
  ///
  /// In en, this message translates to:
  /// **'Could not render QR.\n\$error'**
  String get couldNotRenderQRError;

  /// No description provided for @credentialsTransferQR.
  ///
  /// In en, this message translates to:
  /// **'Credentials transfer QR'**
  String get credentialsTransferQR;

  /// No description provided for @ifQRRenderingFailsCopyPasteTheTransferCode.
  ///
  /// In en, this message translates to:
  /// **'If QR rendering fails, copy/paste the transfer code.'**
  String get ifQRRenderingFailsCopyPasteTheTransferCode;

  /// No description provided for @securityNoteThisQRContainsYourAPITokenInPlainText.
  ///
  /// In en, this message translates to:
  /// **'Security note: this QR contains your API token in plain text.'**
  String get securityNoteThisQRContainsYourAPITokenInPlainText;

  /// No description provided for @transferCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Transfer code copied.'**
  String get transferCodeCopied;

  /// No description provided for @importedCredentialsFromTransferCode.
  ///
  /// In en, this message translates to:
  /// **'Imported credentials from transfer code.'**
  String get importedCredentialsFromTransferCode;

  /// No description provided for @credentialsImportedTapConnect.
  ///
  /// In en, this message translates to:
  /// **'Credentials imported. Tap Connect.'**
  String get credentialsImportedTapConnect;

  /// No description provided for @clipboardIsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Clipboard is empty.'**
  String get clipboardIsEmpty;

  /// No description provided for @invalidTransferCode.
  ///
  /// In en, this message translates to:
  /// **'Invalid transfer code: {error}'**
  String invalidTransferCode(Object error);

  /// No description provided for @qrScanningIsAvailableOnIOSAndroidUsePasteTransferCodeHere.
  ///
  /// In en, this message translates to:
  /// **'QR scanning is available on iOS/Android. Use \"Paste transfer code\" here.'**
  String get qrScanningIsAvailableOnIOSAndroidUsePasteTransferCodeHere;

  /// No description provided for @serverURLIsRequired.
  ///
  /// In en, this message translates to:
  /// **'Server URL is required.'**
  String get serverURLIsRequired;

  /// No description provided for @enterAValidURL.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid URL.'**
  String get enterAValidURL;

  /// No description provided for @usernameIsRequired.
  ///
  /// In en, this message translates to:
  /// **'Username is required.'**
  String get usernameIsRequired;

  /// No description provided for @tokenIsRequired.
  ///
  /// In en, this message translates to:
  /// **'Token is required.'**
  String get tokenIsRequired;

  /// No description provided for @passwordIsRequired.
  ///
  /// In en, this message translates to:
  /// **'Password is required.'**
  String get passwordIsRequired;

  /// No description provided for @credentials.
  ///
  /// In en, this message translates to:
  /// **'Credentials'**
  String get credentials;

  /// No description provided for @authMode.
  ///
  /// In en, this message translates to:
  /// **'Auth mode'**
  String get authMode;

  /// No description provided for @apiTokenMode.
  ///
  /// In en, this message translates to:
  /// **'API token'**
  String get apiTokenMode;

  /// No description provided for @passwordMode.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordMode;

  /// No description provided for @showTransferQR.
  ///
  /// In en, this message translates to:
  /// **'Show transfer QR'**
  String get showTransferQR;

  /// No description provided for @pasteTransferCode.
  ///
  /// In en, this message translates to:
  /// **'Paste transfer code'**
  String get pasteTransferCode;

  /// No description provided for @serverURL.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get serverURL;

  /// No description provided for @serverURLExample.
  ///
  /// In en, this message translates to:
  /// **'https://kanboard.example.com'**
  String get serverURLExample;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @personalAccessToken.
  ///
  /// In en, this message translates to:
  /// **'Personal access token'**
  String get personalAccessToken;

  /// No description provided for @useYourKanboardUsernameAndPassword.
  ///
  /// In en, this message translates to:
  /// **'Use your Kanboard username and password.'**
  String get useYourKanboardUsernameAndPassword;

  /// No description provided for @testConnectionContinue.
  ///
  /// In en, this message translates to:
  /// **'Test connection & continue'**
  String get testConnectionContinue;

  /// No description provided for @openProjects.
  ///
  /// In en, this message translates to:
  /// **'Open projects'**
  String get openProjects;

  /// No description provided for @authNotePersonalTokenUsuallyUsesYourUsernameApplicationTokenUsuallyUsesUsernameJsonrpc.
  ///
  /// In en, this message translates to:
  /// **'Auth note: personal token usually uses your username; application token usually uses username \"jsonrpc\".'**
  String
  get authNotePersonalTokenUsuallyUsesYourUsernameApplicationTokenUsuallyUsesUsernameJsonrpc;

  /// No description provided for @authNotePasswordModeUsesYourKanboardLoginCredentials.
  ///
  /// In en, this message translates to:
  /// **'Auth note: password mode uses your Kanboard login credentials.'**
  String get authNotePasswordModeUsesYourKanboardLoginCredentials;

  /// No description provided for @scanTransferQR.
  ///
  /// In en, this message translates to:
  /// **'Scan transfer QR'**
  String get scanTransferQR;

  /// No description provided for @transferCredentials.
  ///
  /// In en, this message translates to:
  /// **'Transfer credentials'**
  String get transferCredentials;

  /// No description provided for @copyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get copyCode;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @boardStructure.
  ///
  /// In en, this message translates to:
  /// **'Board structure'**
  String get boardStructure;

  /// No description provided for @searchTasks.
  ///
  /// In en, this message translates to:
  /// **'Search tasks'**
  String get searchTasks;

  /// No description provided for @newGroceryList.
  ///
  /// In en, this message translates to:
  /// **'New grocery list'**
  String get newGroceryList;

  /// No description provided for @refreshBoard.
  ///
  /// In en, this message translates to:
  /// **'Refresh board'**
  String get refreshBoard;

  /// No description provided for @lockTaskDrag.
  ///
  /// In en, this message translates to:
  /// **'Lock task drag'**
  String get lockTaskDrag;

  /// No description provided for @unlockTaskDrag.
  ///
  /// In en, this message translates to:
  /// **'Unlock task drag'**
  String get unlockTaskDrag;

  /// No description provided for @newTask.
  ///
  /// In en, this message translates to:
  /// **'New task'**
  String get newTask;

  /// No description provided for @groceryList.
  ///
  /// In en, this message translates to:
  /// **'Grocery list'**
  String get groceryList;

  /// No description provided for @expenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expenses;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @structure.
  ///
  /// In en, this message translates to:
  /// **'Structure'**
  String get structure;

  /// No description provided for @swimlanes.
  ///
  /// In en, this message translates to:
  /// **'Swimlanes'**
  String get swimlanes;

  /// No description provided for @columns.
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get columns;

  /// No description provided for @tasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get tasks;

  /// No description provided for @planned.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get planned;

  /// No description provided for @spent.
  ///
  /// In en, this message translates to:
  /// **'Spent'**
  String get spent;

  /// No description provided for @remaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining'**
  String get remaining;

  /// No description provided for @noBudget.
  ///
  /// In en, this message translates to:
  /// **'No budget'**
  String get noBudget;

  /// No description provided for @dropATaskHere.
  ///
  /// In en, this message translates to:
  /// **'Drop a task here'**
  String get dropATaskHere;

  /// No description provided for @unlockDragToMoveTasks.
  ///
  /// In en, this message translates to:
  /// **'Unlock drag to move tasks'**
  String get unlockDragToMoveTasks;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @markDone.
  ///
  /// In en, this message translates to:
  /// **'Mark done'**
  String get markDone;

  /// No description provided for @reopen.
  ///
  /// In en, this message translates to:
  /// **'Reopen'**
  String get reopen;

  /// No description provided for @taskSearch.
  ///
  /// In en, this message translates to:
  /// **'Task Search'**
  String get taskSearch;

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String deleteFailed(Object error);

  /// No description provided for @statusUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Status update failed: {error}'**
  String statusUpdateFailed(Object error);

  /// No description provided for @moveFailed.
  ///
  /// In en, this message translates to:
  /// **'Move failed: {error}'**
  String moveFailed(Object error);

  /// No description provided for @addColumn.
  ///
  /// In en, this message translates to:
  /// **'Add column'**
  String get addColumn;

  /// No description provided for @editColumn.
  ///
  /// In en, this message translates to:
  /// **'Edit column'**
  String get editColumn;

  /// No description provided for @deleteColumn.
  ///
  /// In en, this message translates to:
  /// **'Delete column?'**
  String get deleteColumn;

  /// No description provided for @deleteColumn2.
  ///
  /// In en, this message translates to:
  /// **'Delete column \"{name}\"?'**
  String deleteColumn2(Object name);

  /// No description provided for @taskLimit.
  ///
  /// In en, this message translates to:
  /// **'Task limit'**
  String get taskLimit;

  /// No description provided for @addSwimlane.
  ///
  /// In en, this message translates to:
  /// **'Add swimlane'**
  String get addSwimlane;

  /// No description provided for @editSwimlane.
  ///
  /// In en, this message translates to:
  /// **'Edit swimlane'**
  String get editSwimlane;

  /// No description provided for @deleteSwimlane.
  ///
  /// In en, this message translates to:
  /// **'Delete swimlane?'**
  String get deleteSwimlane;

  /// No description provided for @deleteSwimlane2.
  ///
  /// In en, this message translates to:
  /// **'Delete swimlane \"{name}\"?'**
  String deleteSwimlane2(Object name);

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @structure2.
  ///
  /// In en, this message translates to:
  /// **'{name} structure'**
  String structure2(Object name);

  /// No description provided for @query.
  ///
  /// In en, this message translates to:
  /// **'Query'**
  String get query;

  /// No description provided for @queryExampleStatusOpenCategoryBug.
  ///
  /// In en, this message translates to:
  /// **'status:open category:bug'**
  String get queryExampleStatusOpenCategoryBug;

  /// No description provided for @noResultsYet.
  ///
  /// In en, this message translates to:
  /// **'No results yet.'**
  String get noResultsYet;

  /// No description provided for @projectExpenses.
  ///
  /// In en, this message translates to:
  /// **'Project expenses'**
  String get projectExpenses;

  /// No description provided for @financeTable.
  ///
  /// In en, this message translates to:
  /// **'Finance table'**
  String get financeTable;

  /// No description provided for @financeProject.
  ///
  /// In en, this message translates to:
  /// **'Finance project'**
  String get financeProject;

  /// No description provided for @financeProjectDescription.
  ///
  /// In en, this message translates to:
  /// **'Open this project directly in Finance table.'**
  String get financeProjectDescription;

  /// No description provided for @sharedFinanceTable.
  ///
  /// In en, this message translates to:
  /// **'Shared finance table'**
  String get sharedFinanceTable;

  /// No description provided for @currentBalance.
  ///
  /// In en, this message translates to:
  /// **'Current balance'**
  String get currentBalance;

  /// No description provided for @projectionHorizon.
  ///
  /// In en, this message translates to:
  /// **'Projection horizon'**
  String get projectionHorizon;

  /// No description provided for @showPastMonths.
  ///
  /// In en, this message translates to:
  /// **'Show past months'**
  String get showPastMonths;

  /// No description provided for @includeSpentExternalExpensesInProjection.
  ///
  /// In en, this message translates to:
  /// **'Include spent external expenses in projection'**
  String get includeSpentExternalExpensesInProjection;

  /// No description provided for @unsavedFinanceChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsaved finance changes'**
  String get unsavedFinanceChangesTitle;

  /// No description provided for @unsavedFinanceChangesMessage.
  ///
  /// In en, this message translates to:
  /// **'Some finance data is not saved yet. Leave this page anyway?'**
  String get unsavedFinanceChangesMessage;

  /// No description provided for @leaveWithoutSaving.
  ///
  /// In en, this message translates to:
  /// **'Leave without saving'**
  String get leaveWithoutSaving;

  /// No description provided for @summedMonthlyIncome.
  ///
  /// In en, this message translates to:
  /// **'Summed monthly income'**
  String get summedMonthlyIncome;

  /// No description provided for @summedMonthlyExpenses.
  ///
  /// In en, this message translates to:
  /// **'Summed monthly expenses'**
  String get summedMonthlyExpenses;

  /// No description provided for @totalBalance.
  ///
  /// In en, this message translates to:
  /// **'Total balance'**
  String get totalBalance;

  /// No description provided for @biggestIncomeExpenseGap.
  ///
  /// In en, this message translates to:
  /// **'Lowest monthly net (income - expenses)'**
  String get biggestIncomeExpenseGap;

  /// No description provided for @months3.
  ///
  /// In en, this message translates to:
  /// **'3 months'**
  String get months3;

  /// No description provided for @months6.
  ///
  /// In en, this message translates to:
  /// **'6 months'**
  String get months6;

  /// No description provided for @months12.
  ///
  /// In en, this message translates to:
  /// **'12 months'**
  String get months12;

  /// No description provided for @lowestProjectedBalance.
  ///
  /// In en, this message translates to:
  /// **'Lowest projected balance'**
  String get lowestProjectedBalance;

  /// No description provided for @firstNegativeMonth.
  ///
  /// In en, this message translates to:
  /// **'First negative month'**
  String get firstNegativeMonth;

  /// No description provided for @endBalance.
  ///
  /// In en, this message translates to:
  /// **'End balance'**
  String get endBalance;

  /// No description provided for @recurringMonthlyEnabled.
  ///
  /// In en, this message translates to:
  /// **'Recurring monthly (enabled)'**
  String get recurringMonthlyEnabled;

  /// No description provided for @recurringIncomeMonthlyEnabled.
  ///
  /// In en, this message translates to:
  /// **'Recurring income monthly (enabled)'**
  String get recurringIncomeMonthlyEnabled;

  /// No description provided for @monthlyIncomesAndProjections.
  ///
  /// In en, this message translates to:
  /// **'Monthly incomes & projections'**
  String get monthlyIncomesAndProjections;

  /// No description provided for @month.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get month;

  /// No description provided for @incomeTotal.
  ///
  /// In en, this message translates to:
  /// **'Income total'**
  String get incomeTotal;

  /// No description provided for @expensesTotal.
  ///
  /// In en, this message translates to:
  /// **'Expenses total'**
  String get expensesTotal;

  /// No description provided for @net.
  ///
  /// In en, this message translates to:
  /// **'Net'**
  String get net;

  /// No description provided for @closing.
  ///
  /// In en, this message translates to:
  /// **'Closing'**
  String get closing;

  /// No description provided for @contributor.
  ///
  /// In en, this message translates to:
  /// **'Contributor'**
  String get contributor;

  /// No description provided for @contributorOptional.
  ///
  /// In en, this message translates to:
  /// **'Contributor (optional)'**
  String get contributorOptional;

  /// No description provided for @source.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get source;

  /// No description provided for @otherIncome.
  ///
  /// In en, this message translates to:
  /// **'Other income'**
  String get otherIncome;

  /// No description provided for @otherExpense.
  ///
  /// In en, this message translates to:
  /// **'Other expense'**
  String get otherExpense;

  /// No description provided for @recurringIncomes.
  ///
  /// In en, this message translates to:
  /// **'Recurring incomes'**
  String get recurringIncomes;

  /// No description provided for @recurringExpenses.
  ///
  /// In en, this message translates to:
  /// **'Recurring expenses'**
  String get recurringExpenses;

  /// No description provided for @plannedIncomes.
  ///
  /// In en, this message translates to:
  /// **'Planned incomes'**
  String get plannedIncomes;

  /// No description provided for @plannedExpenses.
  ///
  /// In en, this message translates to:
  /// **'Planned expenses'**
  String get plannedExpenses;

  /// No description provided for @expensesFromOtherProjects.
  ///
  /// In en, this message translates to:
  /// **'Expenses from other projects'**
  String get expensesFromOtherProjects;

  /// No description provided for @ongoing.
  ///
  /// In en, this message translates to:
  /// **'ongoing'**
  String get ongoing;

  /// No description provided for @enabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get enabled;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @monthlyAmount.
  ///
  /// In en, this message translates to:
  /// **'Monthly amount'**
  String get monthlyAmount;

  /// No description provided for @startMonthYYYYMM.
  ///
  /// In en, this message translates to:
  /// **'Start month (YYYY-MM)'**
  String get startMonthYYYYMM;

  /// No description provided for @endMonthOptionalYYYYMM.
  ///
  /// In en, this message translates to:
  /// **'End month (YYYY-MM, optional)'**
  String get endMonthOptionalYYYYMM;

  /// No description provided for @addRecurringExpense.
  ///
  /// In en, this message translates to:
  /// **'Add recurring expense'**
  String get addRecurringExpense;

  /// No description provided for @editRecurringExpense.
  ///
  /// In en, this message translates to:
  /// **'Edit recurring expense'**
  String get editRecurringExpense;

  /// No description provided for @recurringExpenseFieldsNotValid.
  ///
  /// In en, this message translates to:
  /// **'Recurring expense fields are not valid.'**
  String get recurringExpenseFieldsNotValid;

  /// No description provided for @addRecurringIncome.
  ///
  /// In en, this message translates to:
  /// **'Add recurring income'**
  String get addRecurringIncome;

  /// No description provided for @editRecurringIncome.
  ///
  /// In en, this message translates to:
  /// **'Edit recurring income'**
  String get editRecurringIncome;

  /// No description provided for @recurringIncomeFieldsNotValid.
  ///
  /// In en, this message translates to:
  /// **'Recurring income fields are not valid.'**
  String get recurringIncomeFieldsNotValid;

  /// No description provided for @addPlannedExpense.
  ///
  /// In en, this message translates to:
  /// **'Add planned expense'**
  String get addPlannedExpense;

  /// No description provided for @editPlannedExpense.
  ///
  /// In en, this message translates to:
  /// **'Edit planned expense'**
  String get editPlannedExpense;

  /// No description provided for @plannedExpenseFieldsNotValid.
  ///
  /// In en, this message translates to:
  /// **'Planned expense fields are not valid.'**
  String get plannedExpenseFieldsNotValid;

  /// No description provided for @addPlannedIncome.
  ///
  /// In en, this message translates to:
  /// **'Add planned income'**
  String get addPlannedIncome;

  /// No description provided for @editPlannedIncome.
  ///
  /// In en, this message translates to:
  /// **'Edit planned income'**
  String get editPlannedIncome;

  /// No description provided for @plannedIncomeFieldsNotValid.
  ///
  /// In en, this message translates to:
  /// **'Planned income fields are not valid.'**
  String get plannedIncomeFieldsNotValid;

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// No description provided for @amountHint.
  ///
  /// In en, this message translates to:
  /// **'0.00'**
  String get amountHint;

  /// No description provided for @monthYYYYMM.
  ///
  /// In en, this message translates to:
  /// **'Month (YYYY-MM)'**
  String get monthYYYYMM;

  /// No description provided for @financeContributorMe.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get financeContributorMe;

  /// No description provided for @incomeForPerson.
  ///
  /// In en, this message translates to:
  /// **'Income - {name}'**
  String incomeForPerson(Object name);

  /// No description provided for @currentBalanceMustBeValidNumber.
  ///
  /// In en, this message translates to:
  /// **'Current balance must be a valid number.'**
  String get currentBalanceMustBeValidNumber;

  /// No description provided for @financeTableSaved.
  ///
  /// In en, this message translates to:
  /// **'Finance table saved.'**
  String get financeTableSaved;

  /// No description provided for @financeTableSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Finance table save failed: {error}'**
  String financeTableSaveFailed(Object error);

  /// No description provided for @serverRejectedFinanceTableSave.
  ///
  /// In en, this message translates to:
  /// **'Server rejected finance table save.'**
  String get serverRejectedFinanceTableSave;

  /// No description provided for @expenseSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Expense settings saved.'**
  String get expenseSettingsSaved;

  /// No description provided for @expenseSettingsFailed.
  ///
  /// In en, this message translates to:
  /// **'Expense settings failed: {error}'**
  String expenseSettingsFailed(Object error);

  /// No description provided for @deleteTask.
  ///
  /// In en, this message translates to:
  /// **'Delete task?'**
  String get deleteTask;

  /// No description provided for @deletePermanently.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\" permanently?'**
  String deletePermanently(Object name);

  /// No description provided for @currencyCode.
  ///
  /// In en, this message translates to:
  /// **'Currency code'**
  String get currencyCode;

  /// No description provided for @budget.
  ///
  /// In en, this message translates to:
  /// **'Budget'**
  String get budget;

  /// No description provided for @leaveEmptyForNoBudget.
  ///
  /// In en, this message translates to:
  /// **'Leave empty for no budget'**
  String get leaveEmptyForNoBudget;

  /// No description provided for @task.
  ///
  /// In en, this message translates to:
  /// **'Task'**
  String get task;

  /// No description provided for @newLabel.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newLabel;

  /// No description provided for @openStructure.
  ///
  /// In en, this message translates to:
  /// **'Open structure'**
  String get openStructure;

  /// No description provided for @noBoardDataYet.
  ///
  /// In en, this message translates to:
  /// **'No board data yet'**
  String get noBoardDataYet;

  /// No description provided for @pullToRefreshOrOpenStructureToConfigureColumnsAndSwimlanes.
  ///
  /// In en, this message translates to:
  /// **'Pull to refresh or open structure to configure columns and swimlanes.'**
  String get pullToRefreshOrOpenStructureToConfigureColumnsAndSwimlanes;

  /// No description provided for @themeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme mode'**
  String get themeMode;

  /// No description provided for @systemTheme.
  ///
  /// In en, this message translates to:
  /// **'System theme'**
  String get systemTheme;

  /// No description provided for @lightTheme.
  ///
  /// In en, this message translates to:
  /// **'Light theme'**
  String get lightTheme;

  /// No description provided for @darkTheme.
  ///
  /// In en, this message translates to:
  /// **'Dark theme'**
  String get darkTheme;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @additionalDetails.
  ///
  /// In en, this message translates to:
  /// **'Additional details'**
  String get additionalDetails;

  /// No description provided for @attachments2.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get attachments2;

  /// No description provided for @comments.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get comments;

  /// No description provided for @subtasks.
  ///
  /// In en, this message translates to:
  /// **'Subtasks'**
  String get subtasks;

  /// No description provided for @tags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tags;

  /// No description provided for @taskLinks.
  ///
  /// In en, this message translates to:
  /// **'Task Links'**
  String get taskLinks;

  /// No description provided for @externalLinks.
  ///
  /// In en, this message translates to:
  /// **'External Links'**
  String get externalLinks;

  /// No description provided for @link.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get link;

  /// No description provided for @linkTitle.
  ///
  /// In en, this message translates to:
  /// **'Link title'**
  String get linkTitle;

  /// No description provided for @type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get type;

  /// No description provided for @dependency.
  ///
  /// In en, this message translates to:
  /// **'Dependency'**
  String get dependency;

  /// No description provided for @url.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get url;

  /// No description provided for @columnSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Column save failed: {error}'**
  String columnSaveFailed(Object error);

  /// No description provided for @columnDeletionFailed.
  ///
  /// In en, this message translates to:
  /// **'Column deletion failed: {error}'**
  String columnDeletionFailed(Object error);

  /// No description provided for @swimlaneSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Swimlane save failed: {error}'**
  String swimlaneSaveFailed(Object error);

  /// No description provided for @swimlaneDeletionFailed.
  ///
  /// In en, this message translates to:
  /// **'Swimlane deletion failed: {error}'**
  String swimlaneDeletionFailed(Object error);

  /// No description provided for @projectSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Project save failed: {error}'**
  String projectSaveFailed(Object error);

  /// No description provided for @projectDeletionFailed.
  ///
  /// In en, this message translates to:
  /// **'Project deletion failed: {error}'**
  String projectDeletionFailed(Object error);

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @post.
  ///
  /// In en, this message translates to:
  /// **'Post'**
  String get post;

  /// No description provided for @noAttachmentsYet.
  ///
  /// In en, this message translates to:
  /// **'No attachments yet.'**
  String get noAttachmentsYet;

  /// No description provided for @noCommentsYet.
  ///
  /// In en, this message translates to:
  /// **'No comments yet.'**
  String get noCommentsYet;

  /// No description provided for @noSubtasksYet.
  ///
  /// In en, this message translates to:
  /// **'No subtasks yet.'**
  String get noSubtasksYet;

  /// No description provided for @noTagsAssigned.
  ///
  /// In en, this message translates to:
  /// **'No tags assigned.'**
  String get noTagsAssigned;

  /// No description provided for @noTaskLinks.
  ///
  /// In en, this message translates to:
  /// **'No task links.'**
  String get noTaskLinks;

  /// No description provided for @noExternalLinks.
  ///
  /// In en, this message translates to:
  /// **'No external links.'**
  String get noExternalLinks;

  /// No description provided for @newTask2.
  ///
  /// In en, this message translates to:
  /// **'New Task'**
  String get newTask2;

  /// No description provided for @editTask.
  ///
  /// In en, this message translates to:
  /// **'Edit Task'**
  String get editTask;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @column.
  ///
  /// In en, this message translates to:
  /// **'Column'**
  String get column;

  /// No description provided for @swimlane.
  ///
  /// In en, this message translates to:
  /// **'Swimlane'**
  String get swimlane;

  /// No description provided for @assignee.
  ///
  /// In en, this message translates to:
  /// **'Assignee'**
  String get assignee;

  /// No description provided for @unassigned.
  ///
  /// In en, this message translates to:
  /// **'Unassigned'**
  String get unassigned;

  /// No description provided for @priority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get priority;

  /// No description provided for @dueDate.
  ///
  /// In en, this message translates to:
  /// **'Due date'**
  String get dueDate;

  /// No description provided for @pickDateTime.
  ///
  /// In en, this message translates to:
  /// **'Pick date/time'**
  String get pickDateTime;

  /// No description provided for @expense.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get expense;

  /// No description provided for @score.
  ///
  /// In en, this message translates to:
  /// **'Score'**
  String get score;

  /// No description provided for @pickDueDate.
  ///
  /// In en, this message translates to:
  /// **'Pick due date'**
  String get pickDueDate;

  /// No description provided for @clearDueDate.
  ///
  /// In en, this message translates to:
  /// **'Clear due date'**
  String get clearDueDate;

  /// No description provided for @newComment.
  ///
  /// In en, this message translates to:
  /// **'New comment'**
  String get newComment;

  /// No description provided for @comment.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get comment;

  /// No description provided for @editComment.
  ///
  /// In en, this message translates to:
  /// **'Edit comment'**
  String get editComment;

  /// No description provided for @editSubtask.
  ///
  /// In en, this message translates to:
  /// **'Edit subtask'**
  String get editSubtask;

  /// No description provided for @estimateH.
  ///
  /// In en, this message translates to:
  /// **'Estimate (h)'**
  String get estimateH;

  /// No description provided for @spentH.
  ///
  /// In en, this message translates to:
  /// **'Spent (h)'**
  String get spentH;

  /// No description provided for @newGroceryItem.
  ///
  /// In en, this message translates to:
  /// **'New grocery item'**
  String get newGroceryItem;

  /// No description provided for @newSubtask.
  ///
  /// In en, this message translates to:
  /// **'New subtask'**
  String get newSubtask;

  /// No description provided for @addTagsCommaSeparated.
  ///
  /// In en, this message translates to:
  /// **'Add tags (comma separated)'**
  String get addTagsCommaSeparated;

  /// No description provided for @relation.
  ///
  /// In en, this message translates to:
  /// **'Relation'**
  String get relation;

  /// No description provided for @linkedTaskID.
  ///
  /// In en, this message translates to:
  /// **'Linked task ID'**
  String get linkedTaskID;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @project.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get project;

  /// No description provided for @projectCreatedButDefaultsFailedToApply.
  ///
  /// In en, this message translates to:
  /// **'Project created, but defaults failed to apply: {error}'**
  String projectCreatedButDefaultsFailedToApply(Object error);

  /// No description provided for @projectAttachmentsUploaded.
  ///
  /// In en, this message translates to:
  /// **'Project attachments uploaded.'**
  String get projectAttachmentsUploaded;

  /// No description provided for @uploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed: {error}'**
  String uploadFailed(Object error);

  /// No description provided for @attachmentContentMissing.
  ///
  /// In en, this message translates to:
  /// **'Attachment content missing.'**
  String get attachmentContentMissing;

  /// No description provided for @downloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {error}'**
  String downloadFailed(Object error);

  /// No description provided for @filePickerFailed.
  ///
  /// In en, this message translates to:
  /// **'File picker failed: {error}'**
  String filePickerFailed(Object error);

  /// No description provided for @attachmentPickerFailed.
  ///
  /// In en, this message translates to:
  /// **'Attachment picker failed: {error}'**
  String attachmentPickerFailed(Object error);

  /// No description provided for @attachmentUploadComplete.
  ///
  /// In en, this message translates to:
  /// **'Attachment upload complete.'**
  String get attachmentUploadComplete;

  /// No description provided for @attachmentUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Attachment upload failed: {error}'**
  String attachmentUploadFailed(Object error);

  /// No description provided for @attachmentHasNoDownloadableContent.
  ///
  /// In en, this message translates to:
  /// **'Attachment has no downloadable content.'**
  String get attachmentHasNoDownloadableContent;

  /// No description provided for @attachmentExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Attachment export failed: {error}'**
  String attachmentExportFailed(Object error);

  /// No description provided for @attachmentDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Attachment delete failed: {error}'**
  String attachmentDeleteFailed(Object error);

  /// No description provided for @commentSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Comment save failed: {error}'**
  String commentSaveFailed(Object error);

  /// No description provided for @commentUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Comment update failed: {error}'**
  String commentUpdateFailed(Object error);

  /// No description provided for @commentDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Comment delete failed: {error}'**
  String commentDeleteFailed(Object error);

  /// No description provided for @subtaskCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Subtask create failed: {error}'**
  String subtaskCreateFailed(Object error);

  /// No description provided for @subtaskUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Subtask update failed: {error}'**
  String subtaskUpdateFailed(Object error);

  /// No description provided for @subtaskDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Subtask delete failed: {error}'**
  String subtaskDeleteFailed(Object error);

  /// No description provided for @tagUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Tag update failed: {error}'**
  String tagUpdateFailed(Object error);

  /// No description provided for @theGroceryListTagIsReservedForGroceryTasks.
  ///
  /// In en, this message translates to:
  /// **'The grocery-list tag is reserved for grocery tasks.'**
  String get theGroceryListTagIsReservedForGroceryTasks;

  /// No description provided for @taskLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Task link failed: {error}'**
  String taskLinkFailed(Object error);

  /// No description provided for @linkDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Link delete failed: {error}'**
  String linkDeleteFailed(Object error);

  /// No description provided for @externalLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'External link failed: {error}'**
  String externalLinkFailed(Object error);

  /// No description provided for @externalLinkDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'External link delete failed: {error}'**
  String externalLinkDeleteFailed(Object error);

  /// No description provided for @taskStatusUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Task status update failed: {error}'**
  String taskStatusUpdateFailed(Object error);

  /// No description provided for @serverRejectedTaskStatusUpdate.
  ///
  /// In en, this message translates to:
  /// **'Server rejected task status update.'**
  String get serverRejectedTaskStatusUpdate;

  /// No description provided for @taskNumber.
  ///
  /// In en, this message translates to:
  /// **'Task #{id}'**
  String taskNumber(Object id);

  /// No description provided for @taskMarkedDone.
  ///
  /// In en, this message translates to:
  /// **'Task marked done.'**
  String get taskMarkedDone;

  /// No description provided for @taskReopened.
  ///
  /// In en, this message translates to:
  /// **'Task reopened.'**
  String get taskReopened;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @reopenTask.
  ///
  /// In en, this message translates to:
  /// **'Reopen task'**
  String get reopenTask;

  /// No description provided for @markAsDone.
  ///
  /// In en, this message translates to:
  /// **'Mark as done'**
  String get markAsDone;

  /// No description provided for @editTask2.
  ///
  /// In en, this message translates to:
  /// **'Edit task'**
  String get editTask2;

  /// No description provided for @createTask.
  ///
  /// In en, this message translates to:
  /// **'Create task'**
  String get createTask;

  /// No description provided for @editGroceryList.
  ///
  /// In en, this message translates to:
  /// **'Edit grocery list'**
  String get editGroceryList;

  /// No description provided for @createGroceryList.
  ///
  /// In en, this message translates to:
  /// **'Create grocery list'**
  String get createGroceryList;

  /// No description provided for @groceryListTitle.
  ///
  /// In en, this message translates to:
  /// **'Grocery list title'**
  String get groceryListTitle;

  /// No description provided for @noGroceryItemsYet.
  ///
  /// In en, this message translates to:
  /// **'No grocery items yet.'**
  String get noGroceryItemsYet;

  /// No description provided for @addItemsNowTheyWillBeCreatedWhenYouSave.
  ///
  /// In en, this message translates to:
  /// **'Add items now. They will be created when you save.'**
  String get addItemsNowTheyWillBeCreatedWhenYouSave;

  /// No description provided for @titleIsRequired.
  ///
  /// In en, this message translates to:
  /// **'Title is required.'**
  String get titleIsRequired;

  /// No description provided for @scoreMustBeAnInteger.
  ///
  /// In en, this message translates to:
  /// **'Score must be an integer.'**
  String get scoreMustBeAnInteger;

  /// No description provided for @serverRejectedAttachmentName.
  ///
  /// In en, this message translates to:
  /// **'Server rejected attachment \"{name}\".'**
  String serverRejectedAttachmentName(Object name);

  /// No description provided for @amountMustBeAValidNumber.
  ///
  /// In en, this message translates to:
  /// **'Amount must be a valid number.'**
  String get amountMustBeAValidNumber;

  /// No description provided for @taskWasNotCreated.
  ///
  /// In en, this message translates to:
  /// **'Task was not created.'**
  String get taskWasNotCreated;

  /// No description provided for @enterATitleBeforeOpeningAdditionalDetails.
  ///
  /// In en, this message translates to:
  /// **'Enter a title before opening additional details.'**
  String get enterATitleBeforeOpeningAdditionalDetails;

  /// No description provided for @taskMustBeSavedFirst.
  ///
  /// In en, this message translates to:
  /// **'Task must be saved first.'**
  String get taskMustBeSavedFirst;

  /// No description provided for @saveTaskFirstToManageAttachmentsCommentsSubtasksTagsAndLinks.
  ///
  /// In en, this message translates to:
  /// **'Save this task first to manage attachments, comments, subtasks, tags, and links.'**
  String get saveTaskFirstToManageAttachmentsCommentsSubtasksTagsAndLinks;

  /// No description provided for @externalLinkTitleAndURLAreRequired.
  ///
  /// In en, this message translates to:
  /// **'External link title and URL are required.'**
  String get externalLinkTitleAndURLAreRequired;

  /// No description provided for @enterAValidLinkedTaskID.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid linked task ID.'**
  String get enterAValidLinkedTaskID;

  /// No description provided for @invalidURL.
  ///
  /// In en, this message translates to:
  /// **'Invalid URL.'**
  String get invalidURL;

  /// No description provided for @couldNotOpenURLCopiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Could not open URL. Copied to clipboard.'**
  String get couldNotOpenURLCopiedToClipboard;

  /// No description provided for @attachmentsCommentsSubtasksTagsAndLinks.
  ///
  /// In en, this message translates to:
  /// **'Attachments, comments, subtasks, tags and links'**
  String get attachmentsCommentsSubtasksTagsAndLinks;

  /// No description provided for @tapToExpandAdvancedTaskDetails.
  ///
  /// In en, this message translates to:
  /// **'Tap to expand advanced task details'**
  String get tapToExpandAdvancedTaskDetails;

  /// No description provided for @advancedSectionsAreHidden.
  ///
  /// In en, this message translates to:
  /// **'Advanced sections are hidden.'**
  String get advancedSectionsAreHidden;

  /// No description provided for @forNewTasksTheAppSavesFirstThenOpensAdvancedSections.
  ///
  /// In en, this message translates to:
  /// **'For new tasks, the app saves first, then opens advanced sections.'**
  String get forNewTasksTheAppSavesFirstThenOpensAdvancedSections;

  /// No description provided for @internalLinkTypesUnavailableForThisUserProject.
  ///
  /// In en, this message translates to:
  /// **'Internal link types unavailable for this user/project.'**
  String get internalLinkTypesUnavailableForThisUserProject;

  /// No description provided for @noPermissionForInternalTaskLinksGetAllLinks.
  ///
  /// In en, this message translates to:
  /// **'No permission for internal task links (`getAllLinks`).'**
  String get noPermissionForInternalTaskLinksGetAllLinks;

  /// No description provided for @linkedTo.
  ///
  /// In en, this message translates to:
  /// **'linked to'**
  String get linkedTo;

  /// No description provided for @userNumber.
  ///
  /// In en, this message translates to:
  /// **'User #{id}'**
  String userNumber(Object id);

  /// No description provided for @estHSpentH.
  ///
  /// In en, this message translates to:
  /// **'Est {est}h · Spent {spent}h'**
  String estHSpentH(Object est, Object spent);

  /// No description provided for @eG1250.
  ///
  /// In en, this message translates to:
  /// **'e.g. 12.50'**
  String get eG1250;

  /// No description provided for @macosFileAccessEntitlementMissingRebuildTheAppAfterEnablingUserSelectedFileReadEntitlement.
  ///
  /// In en, this message translates to:
  /// **'macOS file access entitlement missing. Rebuild the app after enabling user-selected file read entitlement.'**
  String
  get macosFileAccessEntitlementMissingRebuildTheAppAfterEnablingUserSelectedFileReadEntitlement;

  /// No description provided for @tasks2.
  ///
  /// In en, this message translates to:
  /// **'Tasks: {count}'**
  String tasks2(Object count);

  /// No description provided for @columns2.
  ///
  /// In en, this message translates to:
  /// **'Columns: {count}'**
  String columns2(Object count);

  /// No description provided for @noColumnsConfiguredForThisSwimlaneUseStructureToAddColumns.
  ///
  /// In en, this message translates to:
  /// **'No columns configured for this swimlane. Use Structure to add columns.'**
  String get noColumnsConfiguredForThisSwimlaneUseStructureToAddColumns;

  /// No description provided for @taskDragIsUnlockedMoveTasksCarefullyWhileScrollingOrTapLockToPreventAccidentalMoves.
  ///
  /// In en, this message translates to:
  /// **'Task drag is unlocked. Move tasks carefully while scrolling, or tap lock to prevent accidental moves.'**
  String
  get taskDragIsUnlockedMoveTasksCarefullyWhileScrollingOrTapLockToPreventAccidentalMoves;

  /// No description provided for @taskDragIsLockedSoYouCanScrollSafelyTapUnlockInTheTopBarWhenYouWantToMoveTasks.
  ///
  /// In en, this message translates to:
  /// **'Task drag is locked so you can scroll safely. Tap unlock in the top bar when you want to move tasks.'**
  String
  get taskDragIsLockedSoYouCanScrollSafelyTapUnlockInTheTopBarWhenYouWantToMoveTasks;

  /// No description provided for @dragAndDropTasksAcrossSwimlanesAndColumnsUseSearchForAdvancedQuerySyntax.
  ///
  /// In en, this message translates to:
  /// **'Drag and drop tasks across swimlanes and columns. Use Search for advanced query syntax.'**
  String
  get dragAndDropTasksAcrossSwimlanesAndColumnsUseSearchForAdvancedQuerySyntax;

  /// No description provided for @currencyMustBeA3LetterCode.
  ///
  /// In en, this message translates to:
  /// **'Currency must be a 3-letter code.'**
  String get currencyMustBeA3LetterCode;

  /// No description provided for @budgetMustBeAPositiveNumber.
  ///
  /// In en, this message translates to:
  /// **'Budget must be a positive number.'**
  String get budgetMustBeAPositiveNumber;

  /// No description provided for @useKanboardQuerySyntaxExampleStatusOpenAssigneeMeDueTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Use Kanboard query syntax. Example: `status:open assignee:me due:tomorrow`'**
  String get useKanboardQuerySyntaxExampleStatusOpenAssigneeMeDueTomorrow;

  /// No description provided for @enterASearchQuery.
  ///
  /// In en, this message translates to:
  /// **'Enter a search query.'**
  String get enterASearchQuery;

  /// No description provided for @boardStructure2.
  ///
  /// In en, this message translates to:
  /// **'{name} Board Structure'**
  String boardStructure2(Object name);

  /// No description provided for @dragRowsToReorderChangesAreSavedImmediately.
  ///
  /// In en, this message translates to:
  /// **'Drag rows to reorder. Changes are saved immediately.'**
  String get dragRowsToReorderChangesAreSavedImmediately;

  /// No description provided for @noColumnsYetAddOne.
  ///
  /// In en, this message translates to:
  /// **'No columns yet. Add one.'**
  String get noColumnsYetAddOne;

  /// No description provided for @noSwimlanesYetAddOne.
  ///
  /// In en, this message translates to:
  /// **'No swimlanes yet. Add one.'**
  String get noSwimlanesYetAddOne;

  /// No description provided for @positionLimit.
  ///
  /// In en, this message translates to:
  /// **'Position {position} · Limit {limit}'**
  String positionLimit(Object position, Object limit);

  /// No description provided for @position.
  ///
  /// In en, this message translates to:
  /// **'Position {position}'**
  String position(Object position);

  /// No description provided for @horizontalStructureOfTheBoard.
  ///
  /// In en, this message translates to:
  /// **'Horizontal structure of the board'**
  String get horizontalStructureOfTheBoard;

  /// No description provided for @verticalWorkGrouping.
  ///
  /// In en, this message translates to:
  /// **'Vertical work grouping'**
  String get verticalWorkGrouping;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'sl'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'sl':
      return AppLocalizationsSl();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
