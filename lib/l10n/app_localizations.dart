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

  /// No description provided for @showDoneTasks.
  ///
  /// In en, this message translates to:
  /// **'Show done tasks'**
  String get showDoneTasks;

  /// No description provided for @hideDoneTasks.
  ///
  /// In en, this message translates to:
  /// **'Hide done tasks'**
  String get hideDoneTasks;

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

  /// No description provided for @organizerAppName.
  ///
  /// In en, this message translates to:
  /// **'Jivie'**
  String get organizerAppName;

  /// No description provided for @jivieAbout.
  ///
  /// In en, this message translates to:
  /// **'About Jivie'**
  String get jivieAbout;

  /// No description provided for @jivieDescription.
  ///
  /// In en, this message translates to:
  /// **'A free personal and family organizer for tasks, plans, shopping and finances. Create and edit personal data on your device without an account or connection. Enable synchronization and sharing when you choose.'**
  String get jivieDescription;

  /// No description provided for @organizerToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get organizerToday;

  /// No description provided for @organizerPlans.
  ///
  /// In en, this message translates to:
  /// **'Plans'**
  String get organizerPlans;

  /// No description provided for @organizerShopping.
  ///
  /// In en, this message translates to:
  /// **'Shopping'**
  String get organizerShopping;

  /// No description provided for @organizerMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get organizerMore;

  /// No description provided for @organizerCalendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get organizerCalendar;

  /// No description provided for @organizerProjects.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get organizerProjects;

  /// No description provided for @organizerFinances.
  ///
  /// In en, this message translates to:
  /// **'Finances'**
  String get organizerFinances;

  /// No description provided for @organizerHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get organizerHome;

  /// No description provided for @organizerSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get organizerSettings;

  /// No description provided for @organizerLocalSpace.
  ///
  /// In en, this message translates to:
  /// **'Personal space'**
  String get organizerLocalSpace;

  /// No description provided for @organizerLocalOnly.
  ///
  /// In en, this message translates to:
  /// **'Saved on this device'**
  String get organizerLocalOnly;

  /// No description provided for @organizerLocalDescription.
  ///
  /// In en, this message translates to:
  /// **'Tasks and plans live on this device. No account needed.'**
  String get organizerLocalDescription;

  /// No description provided for @organizerTodayIntro.
  ///
  /// In en, this message translates to:
  /// **'Room for what matters today.'**
  String get organizerTodayIntro;

  /// No description provided for @organizerNextEvent.
  ///
  /// In en, this message translates to:
  /// **'Next on your calendar'**
  String get organizerNextEvent;

  /// No description provided for @organizerNoEvents.
  ///
  /// In en, this message translates to:
  /// **'Your calendar is empty.'**
  String get organizerNoEvents;

  /// No description provided for @organizerNoEventsDescription.
  ///
  /// In en, this message translates to:
  /// **'Add an event to keep your next step in sight.'**
  String get organizerNoEventsDescription;

  /// No description provided for @organizerNextTasks.
  ///
  /// In en, this message translates to:
  /// **'Next steps'**
  String get organizerNextTasks;

  /// No description provided for @organizerNoTasks.
  ///
  /// In en, this message translates to:
  /// **'Start with one task.'**
  String get organizerNoTasks;

  /// No description provided for @organizerNoTasksDescription.
  ///
  /// In en, this message translates to:
  /// **'Small tasks, bigger plans. Everything in its place.'**
  String get organizerNoTasksDescription;

  /// No description provided for @organizerAddTask.
  ///
  /// In en, this message translates to:
  /// **'Add task'**
  String get organizerAddTask;

  /// No description provided for @organizerEditTask.
  ///
  /// In en, this message translates to:
  /// **'Edit task'**
  String get organizerEditTask;

  /// No description provided for @organizerAddEvent.
  ///
  /// In en, this message translates to:
  /// **'Add event'**
  String get organizerAddEvent;

  /// No description provided for @organizerEditEvent.
  ///
  /// In en, this message translates to:
  /// **'Edit event'**
  String get organizerEditEvent;

  /// No description provided for @organizerAddProject.
  ///
  /// In en, this message translates to:
  /// **'New project'**
  String get organizerAddProject;

  /// No description provided for @organizerEditProject.
  ///
  /// In en, this message translates to:
  /// **'Edit project'**
  String get organizerEditProject;

  /// No description provided for @organizerNoProjects.
  ///
  /// In en, this message translates to:
  /// **'What would you like to plan?'**
  String get organizerNoProjects;

  /// No description provided for @organizerNoProjectsDescription.
  ///
  /// In en, this message translates to:
  /// **'Create a project for a trip, renovation or everyday tasks.'**
  String get organizerNoProjectsDescription;

  /// No description provided for @organizerShoppingShortcut.
  ///
  /// In en, this message translates to:
  /// **'Open shopping lists'**
  String get organizerShoppingShortcut;

  /// No description provided for @organizerShoppingIntro.
  ///
  /// In en, this message translates to:
  /// **'Write down what you need. Check it off when it is in your basket.'**
  String get organizerShoppingIntro;

  /// No description provided for @organizerAddList.
  ///
  /// In en, this message translates to:
  /// **'New list'**
  String get organizerAddList;

  /// No description provided for @organizerEditList.
  ///
  /// In en, this message translates to:
  /// **'Edit list'**
  String get organizerEditList;

  /// No description provided for @organizerNoLists.
  ///
  /// In en, this message translates to:
  /// **'A list for your next shop.'**
  String get organizerNoLists;

  /// No description provided for @organizerNoListsDescription.
  ///
  /// In en, this message translates to:
  /// **'Create a list and add the first thing you need.'**
  String get organizerNoListsDescription;

  /// No description provided for @organizerAddItem.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get organizerAddItem;

  /// No description provided for @organizerEditItem.
  ///
  /// In en, this message translates to:
  /// **'Edit item'**
  String get organizerEditItem;

  /// No description provided for @organizerItemHint.
  ///
  /// In en, this message translates to:
  /// **'What do you need?'**
  String get organizerItemHint;

  /// No description provided for @organizerQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get organizerQuantity;

  /// No description provided for @organizerBought.
  ///
  /// In en, this message translates to:
  /// **'Purchased'**
  String get organizerBought;

  /// No description provided for @organizerEmptyList.
  ///
  /// In en, this message translates to:
  /// **'There are no items on this list yet.'**
  String get organizerEmptyList;

  /// No description provided for @organizerTasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get organizerTasks;

  /// No description provided for @organizerAllTasks.
  ///
  /// In en, this message translates to:
  /// **'All tasks'**
  String get organizerAllTasks;

  /// No description provided for @organizerNoProject.
  ///
  /// In en, this message translates to:
  /// **'No project'**
  String get organizerNoProject;

  /// No description provided for @organizerCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get organizerCompleted;

  /// No description provided for @organizerTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get organizerTitle;

  /// No description provided for @organizerNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get organizerNotes;

  /// No description provided for @organizerDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get organizerDescription;

  /// No description provided for @organizerRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a title.'**
  String get organizerRequired;

  /// No description provided for @organizerSaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not save the change. Please try again.'**
  String get organizerSaveError;

  /// No description provided for @organizerLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not open local data.'**
  String get organizerLoadError;

  /// No description provided for @organizerRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get organizerRetry;

  /// No description provided for @organizerDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get organizerDate;

  /// No description provided for @organizerTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get organizerTime;

  /// No description provided for @organizerNoDate.
  ///
  /// In en, this message translates to:
  /// **'No due date'**
  String get organizerNoDate;

  /// No description provided for @organizerRemoveDate.
  ///
  /// In en, this message translates to:
  /// **'Remove date'**
  String get organizerRemoveDate;

  /// No description provided for @organizerUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get organizerUpcoming;

  /// No description provided for @organizerCalendarIntro.
  ///
  /// In en, this message translates to:
  /// **'Events and task deadlines in one place.'**
  String get organizerCalendarIntro;

  /// No description provided for @organizerFinanceIntro.
  ///
  /// In en, this message translates to:
  /// **'Personal income and expense entries on this device.'**
  String get organizerFinanceIntro;

  /// No description provided for @organizerAddFinance.
  ///
  /// In en, this message translates to:
  /// **'Add entry'**
  String get organizerAddFinance;

  /// No description provided for @organizerEditFinance.
  ///
  /// In en, this message translates to:
  /// **'Edit entry'**
  String get organizerEditFinance;

  /// No description provided for @organizerNoFinance.
  ///
  /// In en, this message translates to:
  /// **'Your overview starts with the first entry.'**
  String get organizerNoFinance;

  /// No description provided for @organizerIncome.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get organizerIncome;

  /// No description provided for @organizerExpense.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get organizerExpense;

  /// No description provided for @organizerCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get organizerCurrency;

  /// No description provided for @organizerInvalidMoney.
  ///
  /// In en, this message translates to:
  /// **'Enter a positive amount with at most two decimal places.'**
  String get organizerInvalidMoney;

  /// No description provided for @organizerBalance.
  ///
  /// In en, this message translates to:
  /// **'Income minus expenses'**
  String get organizerBalance;

  /// No description provided for @organizerConnection.
  ///
  /// In en, this message translates to:
  /// **'Existing Kanboard'**
  String get organizerConnection;

  /// No description provided for @organizerConnectionDescription.
  ///
  /// In en, this message translates to:
  /// **'Your existing projects are still on your Kanboard server. Connect your account to open them. The local organizer does not import or sync them yet.'**
  String get organizerConnectionDescription;

  /// No description provided for @organizerConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect account'**
  String get organizerConnect;

  /// No description provided for @organizerOpenKanboard.
  ///
  /// In en, this message translates to:
  /// **'Open Kanboard'**
  String get organizerOpenKanboard;

  /// No description provided for @organizerBackup.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get organizerBackup;

  /// No description provided for @organizerBackupDescription.
  ///
  /// In en, this message translates to:
  /// **'Export local records to a JSON file or restore them from a backup. The file is not encrypted; store it in a safe place.'**
  String get organizerBackupDescription;

  /// No description provided for @organizerExport.
  ///
  /// In en, this message translates to:
  /// **'Export backup'**
  String get organizerExport;

  /// No description provided for @organizerImport.
  ///
  /// In en, this message translates to:
  /// **'Restore backup'**
  String get organizerImport;

  /// No description provided for @organizerRestoreWarning.
  ///
  /// In en, this message translates to:
  /// **'Restoring adds records from the backup. If the backup contains records that already exist, the entire import is rejected. Export your current backup first.'**
  String get organizerRestoreWarning;

  /// No description provided for @organizerRestoreConfirm.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get organizerRestoreConfirm;

  /// No description provided for @organizerRestored.
  ///
  /// In en, this message translates to:
  /// **'Local data restored.'**
  String get organizerRestored;

  /// No description provided for @organizerReminders.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get organizerReminders;

  /// No description provided for @organizerNoReminders.
  ///
  /// In en, this message translates to:
  /// **'No new reminders.'**
  String get organizerNoReminders;

  /// No description provided for @organizerRemindersDescription.
  ///
  /// In en, this message translates to:
  /// **'Task deadline reminders appear when you open the app.'**
  String get organizerRemindersDescription;

  /// No description provided for @organizerHomeIntro.
  ///
  /// In en, this message translates to:
  /// **'Organize home plans with projects and tasks in your personal space.'**
  String get organizerHomeIntro;

  /// No description provided for @organizerBackToday.
  ///
  /// In en, this message translates to:
  /// **'Back to Today'**
  String get organizerBackToday;

  /// No description provided for @organizerDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this entry?'**
  String get organizerDeleteConfirm;

  /// No description provided for @organizerDeleteProjectNote.
  ///
  /// In en, this message translates to:
  /// **'Tasks, events and finance entries are kept without a project.'**
  String get organizerDeleteProjectNote;

  /// No description provided for @organizerProjectProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} completed'**
  String organizerProjectProgress(int done, int total);

  /// No description provided for @organizerShoppingCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items on your lists'**
  String organizerShoppingCount(int count);

  /// No description provided for @organizerTasksCount.
  ///
  /// In en, this message translates to:
  /// **'{count} tasks'**
  String organizerTasksCount(int count);

  /// No description provided for @organizerNoMatchingTasks.
  ///
  /// In en, this message translates to:
  /// **'There are no tasks in this project yet.'**
  String get organizerNoMatchingTasks;

  /// No description provided for @organizerPersonal.
  ///
  /// In en, this message translates to:
  /// **'Local · personal'**
  String get organizerPersonal;

  /// No description provided for @organizerSystemLanguage.
  ///
  /// In en, this message translates to:
  /// **'Device language'**
  String get organizerSystemLanguage;

  /// No description provided for @organizerRead.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get organizerRead;

  /// No description provided for @organizerWithoutDate.
  ///
  /// In en, this message translates to:
  /// **'Without a deadline'**
  String get organizerWithoutDate;

  /// No description provided for @organizerOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get organizerOverdue;

  /// No description provided for @organizerHomeProjects.
  ///
  /// In en, this message translates to:
  /// **'Home projects'**
  String get organizerHomeProjects;

  /// No description provided for @organizerProjectArea.
  ///
  /// In en, this message translates to:
  /// **'Area'**
  String get organizerProjectArea;

  /// No description provided for @organizerPersonalArea.
  ///
  /// In en, this message translates to:
  /// **'Personal'**
  String get organizerPersonalArea;

  /// No description provided for @organizerHomeArea.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get organizerHomeArea;

  /// No description provided for @organizerConflict.
  ///
  /// In en, this message translates to:
  /// **'The record changed or the backup contains existing records. Open the latest version of the record; a conflicting import is rejected.'**
  String get organizerConflict;

  /// No description provided for @organizerInvalidData.
  ///
  /// In en, this message translates to:
  /// **'The data is invalid or the backup format is unsupported.'**
  String get organizerInvalidData;

  /// No description provided for @secureStorageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Secure storage is unavailable. Credentials were not saved; check this device’s secure storage settings.'**
  String get secureStorageUnavailable;

  /// No description provided for @credentialsSharingDisabled.
  ///
  /// In en, this message translates to:
  /// **'Passwords and personal API keys are not shared. Project invitations will be available when the secure flow is ready.'**
  String get credentialsSharingDisabled;

  /// No description provided for @personalTokenHint.
  ///
  /// In en, this message translates to:
  /// **'Use your username and personal API token. The global jsonrpc key is not supported.'**
  String get personalTokenHint;

  /// No description provided for @secureConnectionRequired.
  ///
  /// In en, this message translates to:
  /// **'Use HTTPS. HTTP is allowed only for an explicit local development connection.'**
  String get secureConnectionRequired;

  /// No description provided for @localDevelopmentConnection.
  ///
  /// In en, this message translates to:
  /// **'Local development connection (HTTP on this computer)'**
  String get localDevelopmentConnection;

  /// No description provided for @aiSessionChanged.
  ///
  /// In en, this message translates to:
  /// **'The account changed. This chat belongs to the previous session; reopen AI help from your project.'**
  String get aiSessionChanged;

  /// No description provided for @connectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed. Check the server address, username and password or personal API token.'**
  String get connectionFailed;

  /// No description provided for @sharingAccount.
  ///
  /// In en, this message translates to:
  /// **'Account and sharing'**
  String get sharingAccount;

  /// No description provided for @sharingIntro.
  ///
  /// In en, this message translates to:
  /// **'Personal data stays on this device. Connect an account when you want to use shared lists and projects.'**
  String get sharingIntro;

  /// No description provided for @sharingPersonal.
  ///
  /// In en, this message translates to:
  /// **'Personal'**
  String get sharingPersonal;

  /// No description provided for @sharingShared.
  ///
  /// In en, this message translates to:
  /// **'Shared'**
  String get sharingShared;

  /// No description provided for @sharingConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect for sharing'**
  String get sharingConnect;

  /// No description provided for @sharingLogin.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get sharingLogin;

  /// No description provided for @sharingLoginAction.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get sharingLoginAction;

  /// No description provided for @sharingHaveInvite.
  ///
  /// In en, this message translates to:
  /// **'I have an invitation'**
  String get sharingHaveInvite;

  /// No description provided for @sharingInvitation.
  ///
  /// In en, this message translates to:
  /// **'Invitation'**
  String get sharingInvitation;

  /// No description provided for @sharingInvitationCode.
  ///
  /// In en, this message translates to:
  /// **'Invitation code'**
  String get sharingInvitationCode;

  /// No description provided for @sharingInvitationHint.
  ///
  /// In en, this message translates to:
  /// **'Paste the code sent by the person you want to collaborate with.'**
  String get sharingInvitationHint;

  /// No description provided for @sharingPreviewInvite.
  ///
  /// In en, this message translates to:
  /// **'Check invitation'**
  String get sharingPreviewInvite;

  /// No description provided for @sharingAcceptInvite.
  ///
  /// In en, this message translates to:
  /// **'Accept invitation'**
  String get sharingAcceptInvite;

  /// No description provided for @sharingRegister.
  ///
  /// In en, this message translates to:
  /// **'Create an account with an invitation'**
  String get sharingRegister;

  /// No description provided for @sharingRegisterAction.
  ///
  /// In en, this message translates to:
  /// **'Create account and accept'**
  String get sharingRegisterAction;

  /// No description provided for @sharingDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get sharingDisplayName;

  /// No description provided for @sharingEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get sharingEmail;

  /// No description provided for @sharingConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get sharingConfirmPassword;

  /// No description provided for @sharingPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get sharingPasswordMismatch;

  /// No description provided for @sharingTwoFactorCode.
  ///
  /// In en, this message translates to:
  /// **'Two-factor authentication code'**
  String get sharingTwoFactorCode;

  /// No description provided for @sharingDeviceName.
  ///
  /// In en, this message translates to:
  /// **'This device’s name'**
  String get sharingDeviceName;

  /// No description provided for @sharingDeviceSession.
  ///
  /// In en, this message translates to:
  /// **'This device’s session'**
  String get sharingDeviceSession;

  /// No description provided for @sharingSpaces.
  ///
  /// In en, this message translates to:
  /// **'Shared spaces'**
  String get sharingSpaces;

  /// No description provided for @sharingCreateSpace.
  ///
  /// In en, this message translates to:
  /// **'New shared space'**
  String get sharingCreateSpace;

  /// No description provided for @sharingSpaceName.
  ///
  /// In en, this message translates to:
  /// **'Space name'**
  String get sharingSpaceName;

  /// No description provided for @sharingScopeType.
  ///
  /// In en, this message translates to:
  /// **'Space type'**
  String get sharingScopeType;

  /// No description provided for @sharingHousehold.
  ///
  /// In en, this message translates to:
  /// **'Household'**
  String get sharingHousehold;

  /// No description provided for @sharingProject.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get sharingProject;

  /// No description provided for @sharingScopeDescription.
  ///
  /// In en, this message translates to:
  /// **'In this version you share lists, projects, and tasks. Shared finances will follow in the finance redesign.'**
  String get sharingScopeDescription;

  /// No description provided for @sharingNoSpaces.
  ///
  /// In en, this message translates to:
  /// **'No shared spaces yet.'**
  String get sharingNoSpaces;

  /// No description provided for @sharingChooseSpace.
  ///
  /// In en, this message translates to:
  /// **'Choose a shared space'**
  String get sharingChooseSpace;

  /// No description provided for @sharingMembers.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get sharingMembers;

  /// No description provided for @sharingOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get sharingOwner;

  /// No description provided for @sharingEditor.
  ///
  /// In en, this message translates to:
  /// **'Can edit'**
  String get sharingEditor;

  /// No description provided for @sharingViewer.
  ///
  /// In en, this message translates to:
  /// **'Can view'**
  String get sharingViewer;

  /// No description provided for @sharingRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get sharingRole;

  /// No description provided for @sharingInvitePerson.
  ///
  /// In en, this message translates to:
  /// **'Invite someone'**
  String get sharingInvitePerson;

  /// No description provided for @sharingCreateInvite.
  ///
  /// In en, this message translates to:
  /// **'Create invitation'**
  String get sharingCreateInvite;

  /// No description provided for @sharingInvitations.
  ///
  /// In en, this message translates to:
  /// **'Invitations'**
  String get sharingInvitations;

  /// No description provided for @sharingCopyInvite.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get sharingCopyInvite;

  /// No description provided for @sharingInviteCopied.
  ///
  /// In en, this message translates to:
  /// **'Invitation code copied.'**
  String get sharingInviteCopied;

  /// No description provided for @sharingInviteCodeOnce.
  ///
  /// In en, this message translates to:
  /// **'Save or send the code now. It cannot be displayed again later.'**
  String get sharingInviteCodeOnce;

  /// No description provided for @sharingRevokeInvite.
  ///
  /// In en, this message translates to:
  /// **'Revoke invitation'**
  String get sharingRevokeInvite;

  /// No description provided for @sharingRemoveMember.
  ///
  /// In en, this message translates to:
  /// **'Remove member'**
  String get sharingRemoveMember;

  /// No description provided for @sharingRemoveMemberConfirm.
  ///
  /// In en, this message translates to:
  /// **'Once removed, this member can no longer access this space. Previously downloaded copies cannot be erased remotely.'**
  String get sharingRemoveMemberConfirm;

  /// No description provided for @sharingSignOutDescription.
  ///
  /// In en, this message translates to:
  /// **'Personal data stays on this device. Check pending shared changes before signing out.'**
  String get sharingSignOutDescription;

  /// No description provided for @sharingSyncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get sharingSyncNow;

  /// No description provided for @sharingSynced.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get sharingSynced;

  /// No description provided for @sharingSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing …'**
  String get sharingSyncing;

  /// No description provided for @sharingPending.
  ///
  /// In en, this message translates to:
  /// **'Waiting to sync'**
  String get sharingPending;

  /// No description provided for @sharingOffline.
  ///
  /// In en, this message translates to:
  /// **'Connection unavailable'**
  String get sharingOffline;

  /// No description provided for @sharingSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Sync failed. Local changes have been kept.'**
  String get sharingSyncFailed;

  /// No description provided for @sharingConflicts.
  ///
  /// In en, this message translates to:
  /// **'Changes need a decision'**
  String get sharingConflicts;

  /// No description provided for @sharingConflictDescription.
  ///
  /// In en, this message translates to:
  /// **'The same record also changed elsewhere. Compare both versions and choose which to keep.'**
  String get sharingConflictDescription;

  /// No description provided for @sharingLocalVersion.
  ///
  /// In en, this message translates to:
  /// **'On this device'**
  String get sharingLocalVersion;

  /// No description provided for @sharingRemoteVersion.
  ///
  /// In en, this message translates to:
  /// **'On the server'**
  String get sharingRemoteVersion;

  /// No description provided for @sharingKeepLocal.
  ///
  /// In en, this message translates to:
  /// **'Keep my version'**
  String get sharingKeepLocal;

  /// No description provided for @sharingKeepRemote.
  ///
  /// In en, this message translates to:
  /// **'Keep server version'**
  String get sharingKeepRemote;

  /// No description provided for @sharingAccessRevoked.
  ///
  /// In en, this message translates to:
  /// **'Access was revoked. Pending changes have not been sent.'**
  String get sharingAccessRevoked;

  /// No description provided for @sharingUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This server does not support the required sharing features yet.'**
  String get sharingUnsupported;

  /// No description provided for @sharingOperationFailed.
  ///
  /// In en, this message translates to:
  /// **'The action failed. Check the connection and try again.'**
  String get sharingOperationFailed;

  /// No description provided for @sharingInvalidInvite.
  ///
  /// In en, this message translates to:
  /// **'The invitation is invalid, expired, or already used.'**
  String get sharingInvalidInvite;

  /// No description provided for @sharingSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session expired. Sign in again; personal data stays on this device.'**
  String get sharingSessionExpired;

  /// No description provided for @sharingPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission for this action.'**
  String get sharingPermissionDenied;

  /// No description provided for @sharingNoSharedLists.
  ///
  /// In en, this message translates to:
  /// **'This space has no shared list yet.'**
  String get sharingNoSharedLists;

  /// No description provided for @sharingNoSharedListsDescription.
  ///
  /// In en, this message translates to:
  /// **'Create a list to collaborate. Personal lists are not shared automatically.'**
  String get sharingNoSharedListsDescription;

  /// No description provided for @sharingCreateSharedList.
  ///
  /// In en, this message translates to:
  /// **'New shared list'**
  String get sharingCreateSharedList;

  /// No description provided for @sharingReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Read only'**
  String get sharingReadOnly;

  /// No description provided for @sharingQuietShopping.
  ///
  /// In en, this message translates to:
  /// **'Shopping list changes are quiet; they do not send email.'**
  String get sharingQuietShopping;

  /// No description provided for @sharingShareList.
  ///
  /// In en, this message translates to:
  /// **'Share this list'**
  String get sharingShareList;

  /// No description provided for @sharingShareProject.
  ///
  /// In en, this message translates to:
  /// **'Share project and tasks'**
  String get sharingShareProject;

  /// No description provided for @sharingShareConfirm.
  ///
  /// In en, this message translates to:
  /// **'A shared copy will be created in the selected space. Personal content and finances are not shared automatically.'**
  String get sharingShareConfirm;

  /// No description provided for @sharingNoMembers.
  ///
  /// In en, this message translates to:
  /// **'No member information available.'**
  String get sharingNoMembers;

  /// No description provided for @sharingNoInvitations.
  ///
  /// In en, this message translates to:
  /// **'No active invitations.'**
  String get sharingNoInvitations;

  /// No description provided for @sharingGoToAccount.
  ///
  /// In en, this message translates to:
  /// **'Open account and sharing'**
  String get sharingGoToAccount;

  /// No description provided for @sharingConnectBeforeShared.
  ///
  /// In en, this message translates to:
  /// **'Connect an account or accept an invitation to use shared lists.'**
  String get sharingConnectBeforeShared;

  /// No description provided for @sharingSaveBeforeSync.
  ///
  /// In en, this message translates to:
  /// **'Changes are saved on this device first, then synced with the space.'**
  String get sharingSaveBeforeSync;

  /// No description provided for @sharingMember.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get sharingMember;

  /// No description provided for @sharingRequired.
  ///
  /// In en, this message translates to:
  /// **'Complete this field.'**
  String get sharingRequired;

  /// No description provided for @sharingSaveDrafts.
  ///
  /// In en, this message translates to:
  /// **'Save my unsynced changes'**
  String get sharingSaveDrafts;

  /// No description provided for @sharingSaveDraftsDescription.
  ///
  /// In en, this message translates to:
  /// **'The export contains your pending shared changes, without credentials. The JSON file is not encrypted.'**
  String get sharingSaveDraftsDescription;

  /// No description provided for @sharingCopyAction.
  ///
  /// In en, this message translates to:
  /// **'Create a shared copy'**
  String get sharingCopyAction;

  /// No description provided for @sharingCopyDone.
  ///
  /// In en, this message translates to:
  /// **'Shared copy created. Your personal original is unchanged.'**
  String get sharingCopyDone;

  /// No description provided for @sharingCopyDescription.
  ///
  /// In en, this message translates to:
  /// **'This version copies only this list or the project with its tasks. Finances and events are not transferred in this action. Later edits to the personal original are not sent to the shared copy.'**
  String get sharingCopyDescription;

  /// No description provided for @sharingLoginNeedsOtp.
  ///
  /// In en, this message translates to:
  /// **'Enter the code from your two-factor authentication app.'**
  String get sharingLoginNeedsOtp;

  /// No description provided for @sharingInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed. Check your username, password, and any two-factor code.'**
  String get sharingInvalidCredentials;

  /// No description provided for @sharingSelectDestination.
  ///
  /// In en, this message translates to:
  /// **'Where should the shared copy be created?'**
  String get sharingSelectDestination;

  /// No description provided for @sharingPendingSignOut.
  ///
  /// In en, this message translates to:
  /// **'The shared view will be hidden after signing out. Personal data remains. Unsynced shared changes are not sent under another account; you can export them before signing out.'**
  String get sharingPendingSignOut;

  /// No description provided for @sharingNoPending.
  ///
  /// In en, this message translates to:
  /// **'No pending changes'**
  String get sharingNoPending;

  /// No description provided for @sharingResumeBlocked.
  ///
  /// In en, this message translates to:
  /// **'Resume syncing my changes'**
  String get sharingResumeBlocked;

  /// No description provided for @sharingResumeBlockedDescription.
  ///
  /// In en, this message translates to:
  /// **'Access has been restored. Previously blocked changes are sent only when you explicitly resume syncing.'**
  String get sharingResumeBlockedDescription;

  /// No description provided for @sharingOfflineSignOut.
  ///
  /// In en, this message translates to:
  /// **'Signed out on this device. Server session revocation could not be confirmed; that session remains valid until revoked or expired.'**
  String get sharingOfflineSignOut;

  /// No description provided for @sharingExpires.
  ///
  /// In en, this message translates to:
  /// **'Expires'**
  String get sharingExpires;

  /// No description provided for @sharingAccepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get sharingAccepted;

  /// No description provided for @sharingRevoked.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get sharingRevoked;

  /// No description provided for @sharingExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get sharingExpired;

  /// No description provided for @sharingSessionEnds.
  ///
  /// In en, this message translates to:
  /// **'Session expires'**
  String get sharingSessionEnds;

  /// No description provided for @sharingSharedTasks.
  ///
  /// In en, this message translates to:
  /// **'Shared tasks'**
  String get sharingSharedTasks;

  /// No description provided for @sharingConflictsButton.
  ///
  /// In en, this message translates to:
  /// **'Review changes'**
  String get sharingConflictsButton;

  /// No description provided for @sharingDeletedVersion.
  ///
  /// In en, this message translates to:
  /// **'This version is absent or the record has been deleted.'**
  String get sharingDeletedVersion;

  /// No description provided for @sharingNetworkError.
  ///
  /// In en, this message translates to:
  /// **'Connection unavailable. Unsynced changes stay on this device; try syncing again.'**
  String get sharingNetworkError;

  /// No description provided for @sharingSessionRevoked.
  ///
  /// In en, this message translates to:
  /// **'This device’s session was revoked. Sign in again; unsynced changes are not sent under another account.'**
  String get sharingSessionRevoked;

  /// No description provided for @sharingStorageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Durable storage for shared data is unavailable. The action was not confirmed; check this device’s storage and try again.'**
  String get sharingStorageUnavailable;

  /// No description provided for @sharingInvalidServer.
  ///
  /// In en, this message translates to:
  /// **'Check the server address. Use HTTPS for a normal connection.'**
  String get sharingInvalidServer;

  /// No description provided for @sharingRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait a while, then try again.'**
  String get sharingRateLimited;

  /// No description provided for @sharingUnsupportedAuth.
  ///
  /// In en, this message translates to:
  /// **'This sign-in method is not supported. Use a supported local user account on the server for sharing.'**
  String get sharingUnsupportedAuth;

  /// No description provided for @sharingIncompatibleServer.
  ///
  /// In en, this message translates to:
  /// **'The server version is not compatible with sharing in this app. Check the server plugin; local data stays on this device.'**
  String get sharingIncompatibleServer;

  /// No description provided for @sharingValidationError.
  ///
  /// In en, this message translates to:
  /// **'The data is invalid. Check your input and try again.'**
  String get sharingValidationError;

  /// No description provided for @sharingRegistrationPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'A new password needs at least 12 characters (at most 72 bytes).'**
  String get sharingRegistrationPasswordHint;

  /// No description provided for @sharingBlockedDescription.
  ///
  /// In en, this message translates to:
  /// **'These changes are blocked because access was revoked. You can export them. Restored access requires an explicit choice to resume them.'**
  String get sharingBlockedDescription;

  /// No description provided for @sharingAdvancedLogin.
  ///
  /// In en, this message translates to:
  /// **'Additional sign-in options'**
  String get sharingAdvancedLogin;

  /// No description provided for @sharingMoreDetails.
  ///
  /// In en, this message translates to:
  /// **'Record details'**
  String get sharingMoreDetails;

  /// No description provided for @sharingNoConflicts.
  ///
  /// In en, this message translates to:
  /// **'No changes need a decision.'**
  String get sharingNoConflicts;

  /// No description provided for @sharingRefreshMembers.
  ///
  /// In en, this message translates to:
  /// **'Refresh members'**
  String get sharingRefreshMembers;

  /// No description provided for @sharingDeletedConflict.
  ///
  /// In en, this message translates to:
  /// **'This record was deleted on the server. You can save your version in an export; accepting the server state does not restore it.'**
  String get sharingDeletedConflict;

  /// No description provided for @sharingRelatedConflict.
  ///
  /// In en, this message translates to:
  /// **'Related records have changed. First save your version, accept the server state, and review related records. You can then explicitly create a copy or choose deletion again.'**
  String get sharingRelatedConflict;

  /// No description provided for @sharingStaleEditor.
  ///
  /// In en, this message translates to:
  /// **'This record changed while you were editing it. Close the editor and open the latest version; you can copy your text first.'**
  String get sharingStaleEditor;

  /// No description provided for @sharingInvalidResponse.
  ///
  /// In en, this message translates to:
  /// **'The server response cannot be used safely. Check plugin compatibility. Local changes remain on this device.'**
  String get sharingInvalidResponse;

  /// No description provided for @sharingRequestMismatch.
  ///
  /// In en, this message translates to:
  /// **'The server rejected a repeated request with different content. Save your changes in an export and review the state; do not blindly resend the request.'**
  String get sharingRequestMismatch;

  /// No description provided for @planningAssignees.
  ///
  /// In en, this message translates to:
  /// **'Assigned to'**
  String get planningAssignees;

  /// No description provided for @planningUnassigned.
  ///
  /// In en, this message translates to:
  /// **'Not assigned yet'**
  String get planningUnassigned;

  /// No description provided for @planningFormerMember.
  ///
  /// In en, this message translates to:
  /// **'Former member'**
  String get planningFormerMember;

  /// No description provided for @planningSchedule.
  ///
  /// In en, this message translates to:
  /// **'Planned schedule'**
  String get planningSchedule;

  /// No description provided for @planningStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get planningStart;

  /// No description provided for @planningEnd.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get planningEnd;

  /// No description provided for @planningDue.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get planningDue;

  /// No description provided for @planningCreatedBy.
  ///
  /// In en, this message translates to:
  /// **'Created by'**
  String get planningCreatedBy;

  /// No description provided for @planningUpdatedBy.
  ///
  /// In en, this message translates to:
  /// **'Last updated by'**
  String get planningUpdatedBy;

  /// No description provided for @planningInvalidSchedule.
  ///
  /// In en, this message translates to:
  /// **'The end cannot be before the start.'**
  String get planningInvalidSchedule;

  /// No description provided for @planningSharedToday.
  ///
  /// In en, this message translates to:
  /// **'Today in this shared space'**
  String get planningSharedToday;

  /// No description provided for @planningTimeline.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get planningTimeline;

  /// No description provided for @planningNoAgenda.
  ///
  /// In en, this message translates to:
  /// **'There are no shared scheduled items for this day.'**
  String get planningNoAgenda;

  /// No description provided for @planningNoTimeline.
  ///
  /// In en, this message translates to:
  /// **'Add a schedule to a task or project to see the timeline.'**
  String get planningNoTimeline;

  /// No description provided for @planningAllPeople.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get planningAllPeople;

  /// No description provided for @planningNoTime.
  ///
  /// In en, this message translates to:
  /// **'No schedule'**
  String get planningNoTime;

  /// No description provided for @planningPreviousDay.
  ///
  /// In en, this message translates to:
  /// **'Previous day'**
  String get planningPreviousDay;

  /// No description provided for @planningNextDay.
  ///
  /// In en, this message translates to:
  /// **'Next day'**
  String get planningNextDay;

  /// No description provided for @financeMinorUnits.
  ///
  /// In en, this message translates to:
  /// **'minor units'**
  String get financeMinorUnits;

  /// No description provided for @financeUnspecifiedPerson.
  ///
  /// In en, this message translates to:
  /// **'Not specified'**
  String get financeUnspecifiedPerson;

  /// No description provided for @financeUnavailableAccount.
  ///
  /// In en, this message translates to:
  /// **'Account unavailable'**
  String get financeUnavailableAccount;

  /// No description provided for @financePosted.
  ///
  /// In en, this message translates to:
  /// **'Posted'**
  String get financePosted;

  /// No description provided for @financePlanned.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get financePlanned;

  /// No description provided for @financeAddTransfer.
  ///
  /// In en, this message translates to:
  /// **'Add transfer'**
  String get financeAddTransfer;

  /// No description provided for @financeTransfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get financeTransfer;

  /// No description provided for @financeInternalTransfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer between accounts'**
  String get financeInternalTransfer;

  /// No description provided for @financeAddAccount.
  ///
  /// In en, this message translates to:
  /// **'Add account'**
  String get financeAddAccount;

  /// No description provided for @financeNoAccounts.
  ///
  /// In en, this message translates to:
  /// **'Create the first financial account in this space.'**
  String get financeNoAccounts;

  /// No description provided for @financeAccounts.
  ///
  /// In en, this message translates to:
  /// **'Financial accounts'**
  String get financeAccounts;

  /// No description provided for @financeAccount.
  ///
  /// In en, this message translates to:
  /// **'Financial account'**
  String get financeAccount;

  /// No description provided for @financeAllAccounts.
  ///
  /// In en, this message translates to:
  /// **'All accounts'**
  String get financeAllAccounts;

  /// No description provided for @financePayerRecipient.
  ///
  /// In en, this message translates to:
  /// **'Payer / recipient'**
  String get financePayerRecipient;

  /// No description provided for @financeEnteredBy.
  ///
  /// In en, this message translates to:
  /// **'Entered by'**
  String get financeEnteredBy;

  /// No description provided for @financeStatus.
  ///
  /// In en, this message translates to:
  /// **'Entry status'**
  String get financeStatus;

  /// No description provided for @financeAllStatuses.
  ///
  /// In en, this message translates to:
  /// **'All statuses'**
  String get financeAllStatuses;

  /// No description provided for @financeNoMatchingEntries.
  ///
  /// In en, this message translates to:
  /// **'No entries match these filters.'**
  String get financeNoMatchingEntries;

  /// No description provided for @financeCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get financeCategory;

  /// No description provided for @financePayer.
  ///
  /// In en, this message translates to:
  /// **'Payer'**
  String get financePayer;

  /// No description provided for @financeRecipient.
  ///
  /// In en, this message translates to:
  /// **'Recipient'**
  String get financeRecipient;

  /// No description provided for @financeJointAccount.
  ///
  /// In en, this message translates to:
  /// **'Joint account'**
  String get financeJointAccount;

  /// No description provided for @financeAudit.
  ///
  /// In en, this message translates to:
  /// **'Change history'**
  String get financeAudit;

  /// No description provided for @financeScopeTotals.
  ///
  /// In en, this message translates to:
  /// **'Entire financial space'**
  String get financeScopeTotals;

  /// No description provided for @financeTransfersExcluded.
  ///
  /// In en, this message translates to:
  /// **'Totals include posted entries. Transfers between accounts are not new income or expenses. The filters below apply to the table.'**
  String get financeTransfersExcluded;

  /// No description provided for @financeSharedAccountsDescription.
  ///
  /// In en, this message translates to:
  /// **'These accounts are shared in this space. Private local accounts are not connected automatically.'**
  String get financeSharedAccountsDescription;

  /// No description provided for @financeDate.
  ///
  /// In en, this message translates to:
  /// **'Date and time'**
  String get financeDate;

  /// No description provided for @planningAllProjects.
  ///
  /// In en, this message translates to:
  /// **'All projects'**
  String get planningAllProjects;

  /// No description provided for @inboxDeviceReminder.
  ///
  /// In en, this message translates to:
  /// **'It is time for your reminder. Open the app for details.'**
  String get inboxDeviceReminder;

  /// No description provided for @inboxDeviceEventReminder.
  ///
  /// In en, this message translates to:
  /// **'Your event is approaching. Open the app for details.'**
  String get inboxDeviceEventReminder;

  /// No description provided for @inboxTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get inboxTitle;

  /// No description provided for @inboxForMe.
  ///
  /// In en, this message translates to:
  /// **'For me'**
  String get inboxForMe;

  /// No description provided for @inboxInSharedSpace.
  ///
  /// In en, this message translates to:
  /// **'In a shared space'**
  String get inboxInSharedSpace;

  /// No description provided for @inboxAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get inboxAll;

  /// No description provided for @inboxRead.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get inboxRead;

  /// No description provided for @inboxMarkRead.
  ///
  /// In en, this message translates to:
  /// **'Mark as read'**
  String get inboxMarkRead;

  /// No description provided for @inboxMarkUnread.
  ///
  /// In en, this message translates to:
  /// **'Mark as unread'**
  String get inboxMarkUnread;

  /// No description provided for @inboxEmpty.
  ///
  /// In en, this message translates to:
  /// **'There are no notifications in this view yet.'**
  String get inboxEmpty;

  /// No description provided for @inboxSettings.
  ///
  /// In en, this message translates to:
  /// **'Notification settings'**
  String get inboxSettings;

  /// No description provided for @inboxDeviceSettings.
  ///
  /// In en, this message translates to:
  /// **'Reminders on this device'**
  String get inboxDeviceSettings;

  /// No description provided for @inboxDevicePrivacy.
  ///
  /// In en, this message translates to:
  /// **'System notifications show a generic reminder only. Open the app for details. Enabling applies to personal and accessible shared reminders on this device.'**
  String get inboxDevicePrivacy;

  /// No description provided for @inboxDeviceEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable system reminders'**
  String get inboxDeviceEnable;

  /// No description provided for @inboxSound.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get inboxSound;

  /// No description provided for @inboxDeviceUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Timed system notifications are not supported here. The in-app notification center remains available.'**
  String get inboxDeviceUnsupported;

  /// No description provided for @inboxDeviceDenied.
  ///
  /// In en, this message translates to:
  /// **'System permission is not enabled. Change it in device settings and return to the app.'**
  String get inboxDeviceDenied;

  /// No description provided for @inboxDeviceGranted.
  ///
  /// In en, this message translates to:
  /// **'Device permission is enabled.'**
  String get inboxDeviceGranted;

  /// No description provided for @inboxDeviceUnknown.
  ///
  /// In en, this message translates to:
  /// **'System permission status has not been confirmed yet.'**
  String get inboxDeviceUnknown;

  /// No description provided for @inboxDeviceError.
  ///
  /// In en, this message translates to:
  /// **'System reminders could not be prepared. Check device permissions and try again; your data remains saved.'**
  String get inboxDeviceError;

  /// No description provided for @inboxDeviceInexact.
  ///
  /// In en, this message translates to:
  /// **'Android may deliver the notification later, especially in battery-saving mode.'**
  String get inboxDeviceInexact;

  /// No description provided for @inboxDeviceLimit.
  ///
  /// In en, this message translates to:
  /// **'{count} later reminders are waiting. The nearest 60 are scheduled; the list is replenished when the app opens or refreshes.'**
  String inboxDeviceLimit(int count);

  /// No description provided for @inboxDeviceScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled reminders: {count}.'**
  String inboxDeviceScheduled(int count);

  /// No description provided for @inboxDeleted.
  ///
  /// In en, this message translates to:
  /// **'The source record was deleted.'**
  String get inboxDeleted;

  /// No description provided for @inboxNeedsConnection.
  ///
  /// In en, this message translates to:
  /// **'A connection is needed to verify access and open this notification.'**
  String get inboxNeedsConnection;

  /// No description provided for @inboxWrongAccount.
  ///
  /// In en, this message translates to:
  /// **'This notification belongs to another account. Sign in with the correct account.'**
  String get inboxWrongAccount;

  /// No description provided for @inboxOfflineView.
  ///
  /// In en, this message translates to:
  /// **'Offline · last accessible copy. Current server permissions cannot be checked.'**
  String get inboxOfflineView;

  /// No description provided for @inboxPersonalReminders.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Reminder for {count} task} other{Reminders for {count} tasks}}'**
  String inboxPersonalReminders(int count);

  /// No description provided for @inboxTasksAssigned.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} task was assigned to you} other{{count} tasks were assigned to you}}'**
  String inboxTasksAssigned(int count);

  /// No description provided for @inboxTaskCreated.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} task was added} other{{count} tasks were added}}'**
  String inboxTaskCreated(int count);

  /// No description provided for @inboxEventCreated.
  ///
  /// In en, this message translates to:
  /// **'An event was added'**
  String get inboxEventCreated;

  /// No description provided for @inboxEventAssigned.
  ///
  /// In en, this message translates to:
  /// **'An event was assigned to you'**
  String get inboxEventAssigned;

  /// No description provided for @inboxShoppingListCreated.
  ///
  /// In en, this message translates to:
  /// **'A shopping list was added'**
  String get inboxShoppingListCreated;

  /// No description provided for @inboxShoppingItemsCreated.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} item was added} other{{count} items were added}}'**
  String inboxShoppingItemsCreated(int count);

  /// No description provided for @inboxMemberJoined.
  ///
  /// In en, this message translates to:
  /// **'A member joined'**
  String get inboxMemberJoined;

  /// No description provided for @inboxRecordUpdated.
  ///
  /// In en, this message translates to:
  /// **'A record was updated'**
  String get inboxRecordUpdated;

  /// No description provided for @inboxRecordDeleted.
  ///
  /// In en, this message translates to:
  /// **'A record was deleted'**
  String get inboxRecordDeleted;

  /// No description provided for @inboxTaskCompleted.
  ///
  /// In en, this message translates to:
  /// **'A task was completed'**
  String get inboxTaskCompleted;

  /// No description provided for @inboxShoppingChecked.
  ///
  /// In en, this message translates to:
  /// **'An item was marked as bought'**
  String get inboxShoppingChecked;

  /// No description provided for @inboxFinanceChanged.
  ///
  /// In en, this message translates to:
  /// **'A shared finance change'**
  String get inboxFinanceChanged;

  /// No description provided for @inboxProjectChanged.
  ///
  /// In en, this message translates to:
  /// **'A project change'**
  String get inboxProjectChanged;

  /// No description provided for @inboxReminderDue.
  ///
  /// In en, this message translates to:
  /// **'It is time for a reminder'**
  String get inboxReminderDue;

  /// No description provided for @inboxOpenToView.
  ///
  /// In en, this message translates to:
  /// **'Open for details'**
  String get inboxOpenToView;

  /// No description provided for @inboxSharedPreferencesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This server does not support notification preferences yet.'**
  String get inboxSharedPreferencesUnavailable;

  /// No description provided for @planningFullDay.
  ///
  /// In en, this message translates to:
  /// **'Full shared day'**
  String get planningFullDay;

  /// No description provided for @sharingView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get sharingView;

  /// No description provided for @financeEditAccount.
  ///
  /// In en, this message translates to:
  /// **'Edit account'**
  String get financeEditAccount;

  /// No description provided for @financeOpeningBalance.
  ///
  /// In en, this message translates to:
  /// **'Opening balance'**
  String get financeOpeningBalance;

  /// No description provided for @financeDeleteAccountDescription.
  ///
  /// In en, this message translates to:
  /// **'You can delete an account when it has no linked entries or transfers.'**
  String get financeDeleteAccountDescription;

  /// No description provided for @financeEditEntry.
  ///
  /// In en, this message translates to:
  /// **'Edit financial entry'**
  String get financeEditEntry;

  /// No description provided for @financeAccountCurrencyAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount in selected account currency'**
  String get financeAccountCurrencyAmount;

  /// No description provided for @financeEditTransfer.
  ///
  /// In en, this message translates to:
  /// **'Edit transfer'**
  String get financeEditTransfer;

  /// No description provided for @financeTransferDescription.
  ///
  /// In en, this message translates to:
  /// **'A transfer moves funds between shared accounts in the same currency within this space. It does not count as income or expense.'**
  String get financeTransferDescription;

  /// No description provided for @financeFromAccount.
  ///
  /// In en, this message translates to:
  /// **'From account'**
  String get financeFromAccount;

  /// No description provided for @financeToAccount.
  ///
  /// In en, this message translates to:
  /// **'To account'**
  String get financeToAccount;

  /// No description provided for @financeInvalidTransfer.
  ///
  /// In en, this message translates to:
  /// **'Choose two different accounts in the same currency.'**
  String get financeInvalidTransfer;

  /// No description provided for @financeNoAudit.
  ///
  /// In en, this message translates to:
  /// **'No financial audit yet.'**
  String get financeNoAudit;

  /// No description provided for @financeRevision.
  ///
  /// In en, this message translates to:
  /// **'Revision'**
  String get financeRevision;

  /// No description provided for @financeBefore.
  ///
  /// In en, this message translates to:
  /// **'Before change'**
  String get financeBefore;

  /// No description provided for @financeAfter.
  ///
  /// In en, this message translates to:
  /// **'After change'**
  String get financeAfter;

  /// No description provided for @financeEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable shared finances'**
  String get financeEnable;

  /// No description provided for @financeDisabled.
  ///
  /// In en, this message translates to:
  /// **'Finances are not enabled in this space yet.'**
  String get financeDisabled;

  /// No description provided for @financeNoAccess.
  ///
  /// In en, this message translates to:
  /// **'You do not have finance access in this space. The owner can grant viewing or editing rights.'**
  String get financeNoAccess;

  /// No description provided for @financePermissions.
  ///
  /// In en, this message translates to:
  /// **'Finance access'**
  String get financePermissions;

  /// No description provided for @financeGrantNone.
  ///
  /// In en, this message translates to:
  /// **'No access'**
  String get financeGrantNone;

  /// No description provided for @financeGrantRead.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get financeGrantRead;

  /// No description provided for @financeGrantWrite.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get financeGrantWrite;

  /// No description provided for @financeLoadingSnapshot.
  ///
  /// In en, this message translates to:
  /// **'Preparing the complete financial overview.'**
  String get financeLoadingSnapshot;

  /// No description provided for @financeUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This server does not support shared finances yet.'**
  String get financeUnsupported;

  /// No description provided for @financeDisable.
  ///
  /// In en, this message translates to:
  /// **'Disable finances'**
  String get financeDisable;

  /// No description provided for @financeDisableDescription.
  ///
  /// In en, this message translates to:
  /// **'Finances will be hidden from members. Records and my unsynced changes are retained.'**
  String get financeDisableDescription;

  /// No description provided for @financePending.
  ///
  /// In en, this message translates to:
  /// **'Financial changes are waiting to sync.'**
  String get financePending;

  /// No description provided for @financeBlocked.
  ///
  /// In en, this message translates to:
  /// **'Financial changes are blocked. Save a copy before resolving access.'**
  String get financeBlocked;

  /// No description provided for @financeConflicts.
  ///
  /// In en, this message translates to:
  /// **'Conflicting financial changes'**
  String get financeConflicts;

  /// No description provided for @inboxPreferencesDescription.
  ///
  /// In en, this message translates to:
  /// **'Preferences apply to the selected shared space and notification type. System reminders on this device are a separate setting.'**
  String get inboxPreferencesDescription;

  /// No description provided for @inboxChannelInApp.
  ///
  /// In en, this message translates to:
  /// **'In notification center'**
  String get inboxChannelInApp;

  /// No description provided for @inboxChannelSound.
  ///
  /// In en, this message translates to:
  /// **'Reminder sound'**
  String get inboxChannelSound;

  /// No description provided for @inboxChannelPush.
  ///
  /// In en, this message translates to:
  /// **'Remote system notifications'**
  String get inboxChannelPush;

  /// No description provided for @inboxChannelEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get inboxChannelEmail;

  /// No description provided for @inboxChannelUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This channel is unavailable on this server.'**
  String get inboxChannelUnavailable;

  /// No description provided for @inboxPreferencesUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This server does not support notification preferences yet.'**
  String get inboxPreferencesUnsupported;

  /// No description provided for @inboxCategoryAssignments.
  ///
  /// In en, this message translates to:
  /// **'Assignments'**
  String get inboxCategoryAssignments;

  /// No description provided for @inboxCategoryTasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks and plans'**
  String get inboxCategoryTasks;

  /// No description provided for @inboxCategoryShopping.
  ///
  /// In en, this message translates to:
  /// **'Shopping'**
  String get inboxCategoryShopping;

  /// No description provided for @inboxCategoryMembers.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get inboxCategoryMembers;

  /// No description provided for @inboxCategoryReminders.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get inboxCategoryReminders;

  /// No description provided for @inboxCategoryFinance.
  ///
  /// In en, this message translates to:
  /// **'Finances'**
  String get inboxCategoryFinance;

  /// No description provided for @financeHolder.
  ///
  /// In en, this message translates to:
  /// **'Account holder'**
  String get financeHolder;

  /// No description provided for @inboxScope.
  ///
  /// In en, this message translates to:
  /// **'Shared space'**
  String get inboxScope;

  /// No description provided for @inboxCategoryEvents.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get inboxCategoryEvents;

  /// No description provided for @inboxJoinedScope.
  ///
  /// In en, this message translates to:
  /// **'You joined the space'**
  String get inboxJoinedScope;

  /// No description provided for @financeUnsupportedCurrency.
  ///
  /// In en, this message translates to:
  /// **'Editing this currency is not supported yet. The amount remains preserved in minor units.'**
  String get financeUnsupportedCurrency;

  /// No description provided for @financeTotalBalance.
  ///
  /// In en, this message translates to:
  /// **'Total balance'**
  String get financeTotalBalance;

  /// No description provided for @remotePushTitle.
  ///
  /// In en, this message translates to:
  /// **'Remote notifications on this device'**
  String get remotePushTitle;

  /// No description provided for @remotePushPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Notifications show generic text. Content opens only after checking the account and access.'**
  String get remotePushPrivacy;

  /// No description provided for @remotePushEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable remote notifications'**
  String get remotePushEnable;

  /// No description provided for @remotePushUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Remote notifications are prepared for Android and iPhone. Use the inbox on this platform.'**
  String get remotePushUnsupported;

  /// No description provided for @remotePushUnconfigured.
  ///
  /// In en, this message translates to:
  /// **'This build has no Firebase configuration yet. The inbox and local reminders remain available.'**
  String get remotePushUnconfigured;

  /// No description provided for @remotePushInvalidConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Notification configuration does not match this app. An updated installation is required.'**
  String get remotePushInvalidConfiguration;

  /// No description provided for @remotePushNeedsAccount.
  ///
  /// In en, this message translates to:
  /// **'Sign in to receive remote notifications. Personal use remains available without an account.'**
  String get remotePushNeedsAccount;

  /// No description provided for @remotePushDisabled.
  ///
  /// In en, this message translates to:
  /// **'Remote notifications on this device are disabled.'**
  String get remotePushDisabled;

  /// No description provided for @remotePushPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing permission and device registration…'**
  String get remotePushPreparing;

  /// No description provided for @remotePushDenied.
  ///
  /// In en, this message translates to:
  /// **'Notifications are blocked by the system. Enable them in device settings and try again.'**
  String get remotePushDenied;

  /// No description provided for @remotePushWaitingApns.
  ///
  /// In en, this message translates to:
  /// **'Waiting for Apple to register this device. Check the connection and push-enabled signing.'**
  String get remotePushWaitingApns;

  /// No description provided for @remotePushRegistered.
  ///
  /// In en, this message translates to:
  /// **'This device is registered. Choose notification types for each shared space.'**
  String get remotePushRegistered;

  /// No description provided for @remotePushOffline.
  ///
  /// In en, this message translates to:
  /// **'Registration is waiting for a connection. App changes remain saved.'**
  String get remotePushOffline;

  /// No description provided for @remotePushServerUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The server has no compatible remote notification configuration. The inbox remains available.'**
  String get remotePushServerUnavailable;

  /// No description provided for @remotePushProjectMismatch.
  ///
  /// In en, this message translates to:
  /// **'The app and server use different Firebase projects. This device is not registered.'**
  String get remotePushProjectMismatch;

  /// No description provided for @remotePushCleanupRequired.
  ///
  /// In en, this message translates to:
  /// **'The previous device registration could not be removed. Retry before enabling another account.'**
  String get remotePushCleanupRequired;

  /// No description provided for @remotePushError.
  ///
  /// In en, this message translates to:
  /// **'Remote notifications could not be prepared. Retry; the inbox remains available.'**
  String get remotePushError;

  /// No description provided for @remotePushRetry.
  ///
  /// In en, this message translates to:
  /// **'Check notifications again'**
  String get remotePushRetry;

  /// No description provided for @remotePushLoginForOpen.
  ///
  /// In en, this message translates to:
  /// **'Sign in to the account that received this notification.'**
  String get remotePushLoginForOpen;

  /// No description provided for @remotePushDeviceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'First enable and register remote notifications on this device.'**
  String get remotePushDeviceUnavailable;

  /// No description provided for @setupTitle.
  ///
  /// In en, this message translates to:
  /// **'How would you like to start?'**
  String get setupTitle;

  /// No description provided for @setupIntro.
  ///
  /// In en, this message translates to:
  /// **'Choose how you want to use Jivie. You can change how you use the app in settings later.'**
  String get setupIntro;

  /// No description provided for @setupHint.
  ///
  /// In en, this message translates to:
  /// **'Your personal space already works without an account. Optionally connect your devices or create a shared home.'**
  String get setupHint;

  /// No description provided for @setupChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose your starting point'**
  String get setupChoose;

  /// No description provided for @setupDeviceOnly.
  ///
  /// In en, this message translates to:
  /// **'Only on this device'**
  String get setupDeviceOnly;

  /// No description provided for @setupDeviceOnlyDescription.
  ///
  /// In en, this message translates to:
  /// **'No account or server. Protect your data with a backup.'**
  String get setupDeviceOnlyDescription;

  /// No description provided for @setupPrivateDevices.
  ///
  /// In en, this message translates to:
  /// **'Connect my devices'**
  String get setupPrivateDevices;

  /// No description provided for @setupPrivateDevicesDescription.
  ///
  /// In en, this message translates to:
  /// **'Private synchronization of my data. Enable upload separately after signing in.'**
  String get setupPrivateDevicesDescription;

  /// No description provided for @setupHousehold.
  ///
  /// In en, this message translates to:
  /// **'Shared home'**
  String get setupHousehold;

  /// No description provided for @setupHouseholdDescription.
  ///
  /// In en, this message translates to:
  /// **'Create a home and invite another person. Your personal space stays separate.'**
  String get setupHouseholdDescription;

  /// No description provided for @setupOpen.
  ///
  /// In en, this message translates to:
  /// **'Getting started'**
  String get setupOpen;

  /// No description provided for @inviteOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'Open invitation'**
  String get inviteOpenTitle;

  /// No description provided for @inviteOpenWarning.
  ///
  /// In en, this message translates to:
  /// **'Check the server address. Invitations are not accepted automatically; preview it first.'**
  String get inviteOpenWarning;

  /// No description provided for @inviteOpenContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue to invitation'**
  String get inviteOpenContinue;

  /// No description provided for @inviteLinkInvalid.
  ///
  /// In en, this message translates to:
  /// **'This link is not a valid invitation. You can enter the server and code manually in the app.'**
  String get inviteLinkInvalid;

  /// No description provided for @inviteCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy invitation link'**
  String get inviteCopyLink;

  /// No description provided for @inviteLinkPrepared.
  ///
  /// In en, this message translates to:
  /// **'The link opens the invitation in the installed Jivie app. If the app does not open, enter the server and code manually in the app.'**
  String get inviteLinkPrepared;

  /// No description provided for @accountFirstTitle.
  ///
  /// In en, this message translates to:
  /// **'First account with a code'**
  String get accountFirstTitle;

  /// No description provided for @accountFirstDescription.
  ///
  /// In en, this message translates to:
  /// **'The server operator provides a one-use setup code. This creates a regular user account. Once the first account exists, others join by invitation.'**
  String get accountFirstDescription;

  /// No description provided for @accountBootstrapCode.
  ///
  /// In en, this message translates to:
  /// **'Operator setup code'**
  String get accountBootstrapCode;

  /// No description provided for @accountCreate.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get accountCreate;

  /// No description provided for @accountCreatedSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Your account is created. You are signed in as {username}.'**
  String accountCreatedSignedIn(String username);

  /// No description provided for @accountCreatedSignInRequired.
  ///
  /// In en, this message translates to:
  /// **'Account {username} is created, but sign-in could not be saved on this device. Sign in with this username and the password you chose. Do not use the setup code or invitation again.'**
  String accountCreatedSignInRequired(String username);

  /// No description provided for @accountEmailConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Your email address is verified.'**
  String get accountEmailConfirmed;

  /// No description provided for @accountSessionAutoRenew.
  ///
  /// In en, this message translates to:
  /// **'Sign-in on this device renews automatically while you use the app.'**
  String get accountSessionAutoRenew;

  /// No description provided for @accountPasswordRule.
  ///
  /// In en, this message translates to:
  /// **'Password must contain 12 to 72 bytes.'**
  String get accountPasswordRule;

  /// No description provided for @accountForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password'**
  String get accountForgotPassword;

  /// No description provided for @accountResetRequestDescription.
  ///
  /// In en, this message translates to:
  /// **'A code is sent only to an already verified email address. For privacy, we do not reveal whether a username exists.'**
  String get accountResetRequestDescription;

  /// No description provided for @accountSendReset.
  ///
  /// In en, this message translates to:
  /// **'Request recovery code'**
  String get accountSendReset;

  /// No description provided for @accountResetGeneric.
  ///
  /// In en, this message translates to:
  /// **'If this account supports recovery, a code was sent to its verified address.'**
  String get accountResetGeneric;

  /// No description provided for @accountResetConfirm.
  ///
  /// In en, this message translates to:
  /// **'I have a recovery code'**
  String get accountResetConfirm;

  /// No description provided for @accountResetConfirmDescription.
  ///
  /// In en, this message translates to:
  /// **'Enter the received code and a new password. Two-factor accounts also require a TOTP code. Sign in again afterward; old device sessions are revoked.'**
  String get accountResetConfirmDescription;

  /// No description provided for @accountEmailCode.
  ///
  /// In en, this message translates to:
  /// **'Email code'**
  String get accountEmailCode;

  /// No description provided for @accountResetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get accountResetPassword;

  /// No description provided for @accountResetDone.
  ///
  /// In en, this message translates to:
  /// **'Password reset. Sign in with the new password.'**
  String get accountResetDone;

  /// No description provided for @accountEmailTitle.
  ///
  /// In en, this message translates to:
  /// **'Email and account recovery'**
  String get accountEmailTitle;

  /// No description provided for @accountEmailNone.
  ///
  /// In en, this message translates to:
  /// **'No email address is set yet.'**
  String get accountEmailNone;

  /// No description provided for @accountEmailVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified address'**
  String get accountEmailVerified;

  /// No description provided for @accountEmailUnverified.
  ///
  /// In en, this message translates to:
  /// **'Address is not verified yet'**
  String get accountEmailUnverified;

  /// No description provided for @accountEmailPending.
  ///
  /// In en, this message translates to:
  /// **'Awaiting verification'**
  String get accountEmailPending;

  /// No description provided for @accountEmailChange.
  ///
  /// In en, this message translates to:
  /// **'Set or change email'**
  String get accountEmailChange;

  /// No description provided for @accountEmailRequestDescription.
  ///
  /// In en, this message translates to:
  /// **'Confirm your password again and TOTP if required. Your current verified address stays active until you verify the new one.'**
  String get accountEmailRequestDescription;

  /// No description provided for @accountEmail.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get accountEmail;

  /// No description provided for @accountEmailSend.
  ///
  /// In en, this message translates to:
  /// **'Send verification code'**
  String get accountEmailSend;

  /// No description provided for @accountEmailConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm email code'**
  String get accountEmailConfirm;

  /// No description provided for @accountEmailSent.
  ///
  /// In en, this message translates to:
  /// **'A verification code was requested. Enter it after receiving the email.'**
  String get accountEmailSent;

  /// No description provided for @accountEmailUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The server has not configured account security email yet.'**
  String get accountEmailUnavailable;

  /// No description provided for @accountCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'The code is invalid, expired or already used. Request a new one.'**
  String get accountCodeInvalid;

  /// No description provided for @accountEnrollmentUnavailable.
  ///
  /// In en, this message translates to:
  /// **'First-account setup is no longer available here. Sign in or use an invitation.'**
  String get accountEnrollmentUnavailable;

  /// No description provided for @planningPhases.
  ///
  /// In en, this message translates to:
  /// **'Phases and milestones'**
  String get planningPhases;

  /// No description provided for @planningAddPhase.
  ///
  /// In en, this message translates to:
  /// **'Add phase'**
  String get planningAddPhase;

  /// No description provided for @planningPhaseTitle.
  ///
  /// In en, this message translates to:
  /// **'Phase name'**
  String get planningPhaseTitle;

  /// No description provided for @planningMilestone.
  ///
  /// In en, this message translates to:
  /// **'Milestone'**
  String get planningMilestone;

  /// No description provided for @planningRemovePhase.
  ///
  /// In en, this message translates to:
  /// **'Remove phase'**
  String get planningRemovePhase;

  /// No description provided for @planningNoPhase.
  ///
  /// In en, this message translates to:
  /// **'No phase'**
  String get planningNoPhase;

  /// No description provided for @planningEstimateMinutes.
  ///
  /// In en, this message translates to:
  /// **'Estimated work in minutes'**
  String get planningEstimateMinutes;

  /// No description provided for @planningAvailabilityMinutes.
  ///
  /// In en, this message translates to:
  /// **'Available minutes'**
  String get planningAvailabilityMinutes;

  /// No description provided for @planningAvailabilityPeriod.
  ///
  /// In en, this message translates to:
  /// **'Availability period'**
  String get planningAvailabilityPeriod;

  /// No description provided for @planningPerDay.
  ///
  /// In en, this message translates to:
  /// **'Per day'**
  String get planningPerDay;

  /// No description provided for @planningPerWeek.
  ///
  /// In en, this message translates to:
  /// **'Per week'**
  String get planningPerWeek;

  /// No description provided for @planningTimerStart.
  ///
  /// In en, this message translates to:
  /// **'Start timer'**
  String get planningTimerStart;

  /// No description provided for @planningTimerPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get planningTimerPause;

  /// No description provided for @planningElapsed.
  ///
  /// In en, this message translates to:
  /// **'Elapsed time'**
  String get planningElapsed;

  /// No description provided for @planningRemaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining time'**
  String get planningRemaining;

  /// No description provided for @planningEstimated.
  ///
  /// In en, this message translates to:
  /// **'Estimated time'**
  String get planningEstimated;

  /// No description provided for @planningCalendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar dates'**
  String get planningCalendar;

  /// No description provided for @taskCostTitle.
  ///
  /// In en, this message translates to:
  /// **'Task cost'**
  String get taskCostTitle;

  /// No description provided for @taskCostEnabled.
  ///
  /// In en, this message translates to:
  /// **'Add cost'**
  String get taskCostEnabled;

  /// No description provided for @taskCostPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get taskCostPaid;

  /// No description provided for @taskCostPlanned.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get taskCostPlanned;

  /// No description provided for @taskCostAccount.
  ///
  /// In en, this message translates to:
  /// **'Financial account'**
  String get taskCostAccount;

  /// No description provided for @taskCostUnassignedAccount.
  ///
  /// In en, this message translates to:
  /// **'No account selected'**
  String get taskCostUnassignedAccount;

  /// No description provided for @taskCostPayer.
  ///
  /// In en, this message translates to:
  /// **'Payer'**
  String get taskCostPayer;

  /// No description provided for @taskCostRecipient.
  ///
  /// In en, this message translates to:
  /// **'Recipient'**
  String get taskCostRecipient;

  /// No description provided for @taskCostAuthor.
  ///
  /// In en, this message translates to:
  /// **'Entry author'**
  String get taskCostAuthor;

  /// No description provided for @taskCostNoDue.
  ///
  /// In en, this message translates to:
  /// **'Without a task due date, the cost has no planned date.'**
  String get taskCostNoDue;

  /// No description provided for @taskCostDetachHint.
  ///
  /// In en, this message translates to:
  /// **'Removing the link preserves the financial entry.'**
  String get taskCostDetachHint;

  /// No description provided for @spacePickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Space'**
  String get spacePickerTitle;

  /// No description provided for @organizationTitle.
  ///
  /// In en, this message translates to:
  /// **'Organization'**
  String get organizationTitle;

  /// No description provided for @organizationCreate.
  ///
  /// In en, this message translates to:
  /// **'Create organization'**
  String get organizationCreate;

  /// No description provided for @organizationProjects.
  ///
  /// In en, this message translates to:
  /// **'Organization projects'**
  String get organizationProjects;

  /// No description provided for @organizationCreateProject.
  ///
  /// In en, this message translates to:
  /// **'Add organization project'**
  String get organizationCreateProject;

  /// No description provided for @organizationAccessDescription.
  ///
  /// In en, this message translates to:
  /// **'Membership does not grant access to every project or finances. Set access for each project separately.'**
  String get organizationAccessDescription;

  /// No description provided for @peopleTitle.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get peopleTitle;

  /// No description provided for @peopleAdd.
  ///
  /// In en, this message translates to:
  /// **'Add person'**
  String get peopleAdd;

  /// No description provided for @peopleName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get peopleName;

  /// No description provided for @peopleNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get peopleNotes;

  /// No description provided for @peopleArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get peopleArchive;

  /// No description provided for @peopleRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get peopleRestore;

  /// No description provided for @peopleWithoutAccountDescription.
  ///
  /// In en, this message translates to:
  /// **'A person profile has no login or access rights.'**
  String get peopleWithoutAccountDescription;

  /// No description provided for @peopleEmpty.
  ///
  /// In en, this message translates to:
  /// **'Add people whose tasks you want to manage.'**
  String get peopleEmpty;

  /// No description provided for @peopleArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived person'**
  String get peopleArchived;

  /// No description provided for @financePlanTitle.
  ///
  /// In en, this message translates to:
  /// **'Monthly plan'**
  String get financePlanTitle;

  /// No description provided for @financePlanWizard.
  ///
  /// In en, this message translates to:
  /// **'Set up a financial plan'**
  String get financePlanWizard;

  /// No description provided for @financePlanDescription.
  ///
  /// In en, this message translates to:
  /// **'Estimates stay expected until you confirm actual receipt or payment.'**
  String get financePlanDescription;

  /// No description provided for @financePlanLocal.
  ///
  /// In en, this message translates to:
  /// **'The plan is saved on this device and in portable backups.'**
  String get financePlanLocal;

  /// No description provided for @financePlanPrivate.
  ///
  /// In en, this message translates to:
  /// **'The plan is saved in your selected private space with sync enabled.'**
  String get financePlanPrivate;

  /// No description provided for @financePlanUpgrade.
  ///
  /// In en, this message translates to:
  /// **'Planning in a synced space requires the newer server finance contract.'**
  String get financePlanUpgrade;

  /// No description provided for @financePlanMonthEnd.
  ///
  /// In en, this message translates to:
  /// **'If the day does not exist in a month, its last day is used.'**
  String get financePlanMonthEnd;

  /// No description provided for @financePlanWeekend.
  ///
  /// In en, this message translates to:
  /// **'Weekend salary checks occur on Friday and Monday for the same income. Holidays are not adjusted automatically.'**
  String get financePlanWeekend;

  /// No description provided for @financePlanSalary.
  ///
  /// In en, this message translates to:
  /// **'When do you expect your monthly salary?'**
  String get financePlanSalary;

  /// No description provided for @financePlanNoSalary.
  ///
  /// In en, this message translates to:
  /// **'No regular salary'**
  String get financePlanNoSalary;

  /// No description provided for @financePlanLoan.
  ///
  /// In en, this message translates to:
  /// **'Do you have a loan?'**
  String get financePlanLoan;

  /// No description provided for @financePlanLoanPrincipal.
  ///
  /// In en, this message translates to:
  /// **'Total loan amount (optional)'**
  String get financePlanLoanPrincipal;

  /// No description provided for @financePlanInstallment.
  ///
  /// In en, this message translates to:
  /// **'Estimated monthly installment'**
  String get financePlanInstallment;

  /// No description provided for @financePlanCard.
  ///
  /// In en, this message translates to:
  /// **'Do you have a deferred payment card?'**
  String get financePlanCard;

  /// No description provided for @financePlanCardEstimate.
  ///
  /// In en, this message translates to:
  /// **'Estimated monthly settlement'**
  String get financePlanCardEstimate;

  /// No description provided for @financePlanOtherIncome.
  ///
  /// In en, this message translates to:
  /// **'Other monthly income'**
  String get financePlanOtherIncome;

  /// No description provided for @financePlanOtherExpenses.
  ///
  /// In en, this message translates to:
  /// **'Monthly expenses'**
  String get financePlanOtherExpenses;

  /// No description provided for @financePlanAddIncome.
  ///
  /// In en, this message translates to:
  /// **'Add income'**
  String get financePlanAddIncome;

  /// No description provided for @financePlanAddExpense.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get financePlanAddExpense;

  /// No description provided for @financePlanEstimatedAmount.
  ///
  /// In en, this message translates to:
  /// **'Estimated amount'**
  String get financePlanEstimatedAmount;

  /// No description provided for @financePlanDay.
  ///
  /// In en, this message translates to:
  /// **'Day of month'**
  String get financePlanDay;

  /// No description provided for @financePlanFirstDate.
  ///
  /// In en, this message translates to:
  /// **'First expected date'**
  String get financePlanFirstDate;

  /// No description provided for @financePlanSalaryLabel.
  ///
  /// In en, this message translates to:
  /// **'Salary'**
  String get financePlanSalaryLabel;

  /// No description provided for @financePlanLoanLabel.
  ///
  /// In en, this message translates to:
  /// **'Loan installment'**
  String get financePlanLoanLabel;

  /// No description provided for @financePlanCardLabel.
  ///
  /// In en, this message translates to:
  /// **'Card settlement'**
  String get financePlanCardLabel;

  /// No description provided for @financePlanReview.
  ///
  /// In en, this message translates to:
  /// **'Review plan'**
  String get financePlanReview;

  /// No description provided for @financePlanSave.
  ///
  /// In en, this message translates to:
  /// **'Save plan'**
  String get financePlanSave;

  /// No description provided for @financePlanRules.
  ///
  /// In en, this message translates to:
  /// **'Monthly recurrences'**
  String get financePlanRules;

  /// No description provided for @financePlanAddRule.
  ///
  /// In en, this message translates to:
  /// **'Add monthly rule'**
  String get financePlanAddRule;

  /// No description provided for @financePlanEditRule.
  ///
  /// In en, this message translates to:
  /// **'Edit monthly rule'**
  String get financePlanEditRule;

  /// No description provided for @financePlanRuleActive.
  ///
  /// In en, this message translates to:
  /// **'Rule is active'**
  String get financePlanRuleActive;

  /// No description provided for @financePlanReminders.
  ///
  /// In en, this message translates to:
  /// **'Reminders for this plan'**
  String get financePlanReminders;

  /// No description provided for @financePlanReminderTime.
  ///
  /// In en, this message translates to:
  /// **'Reminder time'**
  String get financePlanReminderTime;

  /// No description provided for @financePlanReminderOptIn.
  ///
  /// In en, this message translates to:
  /// **'This does not enable phone permission. Enable device reminders in notification settings.'**
  String get financePlanReminderOptIn;

  /// No description provided for @financePlanSalaryQuestion.
  ///
  /// In en, this message translates to:
  /// **'Have you received your salary?'**
  String get financePlanSalaryQuestion;

  /// No description provided for @financePlanConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm actual amount'**
  String get financePlanConfirm;

  /// No description provided for @financePlanActualAmount.
  ///
  /// In en, this message translates to:
  /// **'Actual amount'**
  String get financePlanActualAmount;

  /// No description provided for @financePlanActualDate.
  ///
  /// In en, this message translates to:
  /// **'Receipt or payment date'**
  String get financePlanActualDate;

  /// No description provided for @financePlanConfirmed.
  ///
  /// In en, this message translates to:
  /// **'The actual amount is confirmed.'**
  String get financePlanConfirmed;

  /// No description provided for @financePlanForecast.
  ///
  /// In en, this message translates to:
  /// **'Forecast by date'**
  String get financePlanForecast;

  /// No description provided for @financePlanNetChange.
  ///
  /// In en, this message translates to:
  /// **'Expected net change'**
  String get financePlanNetChange;

  /// No description provided for @financePlanProjectedBalance.
  ///
  /// In en, this message translates to:
  /// **'Projected balance'**
  String get financePlanProjectedBalance;

  /// No description provided for @financePlanOpeningBalance.
  ///
  /// In en, this message translates to:
  /// **'Opening balance (optional)'**
  String get financePlanOpeningBalance;

  /// No description provided for @financePlanOpeningDate.
  ///
  /// In en, this message translates to:
  /// **'Opening balance at the start of day'**
  String get financePlanOpeningDate;

  /// No description provided for @financePlanNoOpening.
  ///
  /// In en, this message translates to:
  /// **'No opening balance is set; net change is shown.'**
  String get financePlanNoOpening;

  /// No description provided for @financePlanUndated.
  ///
  /// In en, this message translates to:
  /// **'Undated entries are excluded from the dated forecast.'**
  String get financePlanUndated;

  /// No description provided for @financePlanSymbolicAccount.
  ///
  /// In en, this message translates to:
  /// **'This is a named ledger account; it does not move money or connect to a bank.'**
  String get financePlanSymbolicAccount;

  /// No description provided for @financePlanEmpty.
  ///
  /// In en, this message translates to:
  /// **'No dated entries in the selected period.'**
  String get financePlanEmpty;

  /// No description provided for @financePlanRuleType.
  ///
  /// In en, this message translates to:
  /// **'Recurrence type'**
  String get financePlanRuleType;

  /// No description provided for @financePlanSaved.
  ///
  /// In en, this message translates to:
  /// **'The financial plan is saved.'**
  String get financePlanSaved;

  /// No description provided for @financePlanOverdue.
  ///
  /// In en, this message translates to:
  /// **'Still unconfirmed'**
  String get financePlanOverdue;

  /// No description provided for @financePlanBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get financePlanBack;

  /// No description provided for @financePlanNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get financePlanNext;

  /// No description provided for @financePlanDateNeeded.
  ///
  /// In en, this message translates to:
  /// **'Choose a date.'**
  String get financePlanDateNeeded;

  /// No description provided for @financePlanNoItems.
  ///
  /// In en, this message translates to:
  /// **'No additional entries.'**
  String get financePlanNoItems;

  /// No description provided for @financePlanAccountName.
  ///
  /// In en, this message translates to:
  /// **'Financial account name'**
  String get financePlanAccountName;

  /// No description provided for @financePlanAccountArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived account'**
  String get financePlanAccountArchived;

  /// No description provided for @financePlanReminderBody.
  ///
  /// In en, this message translates to:
  /// **'Have you received your salary? Open the expected income and confirm the actual amount.'**
  String get financePlanReminderBody;

  /// No description provided for @peopleTaskSubjects.
  ///
  /// In en, this message translates to:
  /// **'Who this task concerns'**
  String get peopleTaskSubjects;

  /// No description provided for @financePlanYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get financePlanYes;

  /// No description provided for @financePlanNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get financePlanNo;

  /// No description provided for @financePlanRecordedChange.
  ///
  /// In en, this message translates to:
  /// **'Recorded net change'**
  String get financePlanRecordedChange;

  /// No description provided for @financePairedConflict.
  ///
  /// In en, this message translates to:
  /// **'Review the task and cost conflict in finances.'**
  String get financePairedConflict;

  /// No description provided for @deletionDetachOrganization.
  ///
  /// In en, this message translates to:
  /// **'Keep this project as an independent space when the organization is deleted. Its members and finances remain unchanged.'**
  String get deletionDetachOrganization;

  /// No description provided for @deletionOrganizationLinks.
  ///
  /// In en, this message translates to:
  /// **'Projects detached from an organization'**
  String get deletionOrganizationLinks;

  /// No description provided for @financePlanIncomeQuestion.
  ///
  /// In en, this message translates to:
  /// **'Have you received this income?'**
  String get financePlanIncomeQuestion;

  /// No description provided for @financePlanExpenseQuestion.
  ///
  /// In en, this message translates to:
  /// **'Has this obligation been paid?'**
  String get financePlanExpenseQuestion;

  /// No description provided for @financePlanIncomeReminderBody.
  ///
  /// In en, this message translates to:
  /// **'Have you received this income? Open the expected entry and confirm the actual amount.'**
  String get financePlanIncomeReminderBody;

  /// No description provided for @financePlanExpenseReminderBody.
  ///
  /// In en, this message translates to:
  /// **'Has this obligation been paid? Open the planned entry and confirm the actual amount.'**
  String get financePlanExpenseReminderBody;

  /// No description provided for @financePlanManageRule.
  ///
  /// In en, this message translates to:
  /// **'Manage a recurring entry through its monthly rule. Disabling the rule stops future entries and preserves confirmed history.'**
  String get financePlanManageRule;

  /// No description provided for @scopeArchivedProjects.
  ///
  /// In en, this message translates to:
  /// **'Archived projects'**
  String get scopeArchivedProjects;

  /// No description provided for @scopeArchivedDescription.
  ///
  /// In en, this message translates to:
  /// **'This project is archived. Data and financial history remain available according to your permissions; tasks do not contribute to the daily overview or reminders.'**
  String get scopeArchivedDescription;

  /// No description provided for @peopleCopyDescription.
  ///
  /// In en, this message translates to:
  /// **'Related person profiles (names and notes) will also be copied into the selected space.'**
  String get peopleCopyDescription;

  /// No description provided for @financePlanPrincipalOnlyLoan.
  ///
  /// In en, this message translates to:
  /// **'The total loan amount can only be entered for a loan installment.'**
  String get financePlanPrincipalOnlyLoan;

  /// No description provided for @financePlanOpeningUndated.
  ///
  /// In en, this message translates to:
  /// **'No reference date'**
  String get financePlanOpeningUndated;

  /// No description provided for @planningInvalidMinutes.
  ///
  /// In en, this message translates to:
  /// **'Enter a positive number of minutes, up to {max}.'**
  String planningInvalidMinutes(int max);

  /// No description provided for @taskCostSelectAccount.
  ///
  /// In en, this message translates to:
  /// **'Choose a financial account.'**
  String get taskCostSelectAccount;

  /// No description provided for @financeDuplicateOccurrence.
  ///
  /// In en, this message translates to:
  /// **'Another device already created the canonical entry for this month. Your local version is kept for comparison; the same income or expense is not counted twice.'**
  String get financeDuplicateOccurrence;

  /// No description provided for @financePairedTaskReview.
  ///
  /// In en, this message translates to:
  /// **'Linked task: these changes and the cost will be reviewed together.'**
  String get financePairedTaskReview;

  /// No description provided for @privateSyncTitle.
  ///
  /// In en, this message translates to:
  /// **'My devices'**
  String get privateSyncTitle;

  /// No description provided for @privateSyncDescription.
  ///
  /// In en, this message translates to:
  /// **'A private space for this account only. Other people cannot be invited.'**
  String get privateSyncDescription;

  /// No description provided for @privateSyncOff.
  ///
  /// In en, this message translates to:
  /// **'Personal data currently stays on this device. Signing in does not upload it automatically.'**
  String get privateSyncOff;

  /// No description provided for @privateSyncReview.
  ///
  /// In en, this message translates to:
  /// **'Review before enabling'**
  String get privateSyncReview;

  /// No description provided for @privateSyncEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable private synchronization'**
  String get privateSyncEnable;

  /// No description provided for @privateSyncUploadWarning.
  ///
  /// In en, this message translates to:
  /// **'This uploads the reviewed personal records, including personal finances, to your account’s private space. Server synchronization is not a backup.'**
  String get privateSyncUploadWarning;

  /// No description provided for @privateSyncRemoteCount.
  ///
  /// In en, this message translates to:
  /// **'Existing records in private space'**
  String get privateSyncRemoteCount;

  /// No description provided for @privateSyncOn.
  ///
  /// In en, this message translates to:
  /// **'Private synchronization is enabled.'**
  String get privateSyncOn;

  /// No description provided for @privateSyncPaused.
  ///
  /// In en, this message translates to:
  /// **'Synchronization is paused. Local work remains saved.'**
  String get privateSyncPaused;

  /// No description provided for @privateSyncPause.
  ///
  /// In en, this message translates to:
  /// **'Pause synchronization'**
  String get privateSyncPause;

  /// No description provided for @privateSyncResume.
  ///
  /// In en, this message translates to:
  /// **'Resume synchronization'**
  String get privateSyncResume;

  /// No description provided for @privateSyncUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Private synchronization requires sign-in and a supported server.'**
  String get privateSyncUnavailable;

  /// No description provided for @privateSyncPending.
  ///
  /// In en, this message translates to:
  /// **'Pending changes'**
  String get privateSyncPending;

  /// No description provided for @privateSyncIssue.
  ///
  /// In en, this message translates to:
  /// **'Resolve incompatible or conflicting records before enabling. Personal data stays on this device.'**
  String get privateSyncIssue;

  /// No description provided for @backupTitle.
  ///
  /// In en, this message translates to:
  /// **'Encrypted backup'**
  String get backupTitle;

  /// No description provided for @backupDescription.
  ///
  /// In en, this message translates to:
  /// **'A password protects this copy of personal records, settings and authorized shared work. Credentials are excluded. This does not add encryption to the active database.'**
  String get backupDescription;

  /// No description provided for @backupCreate.
  ///
  /// In en, this message translates to:
  /// **'Create backup'**
  String get backupCreate;

  /// No description provided for @backupRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore backup'**
  String get backupRestore;

  /// No description provided for @backupPassword.
  ///
  /// In en, this message translates to:
  /// **'Backup password'**
  String get backupPassword;

  /// No description provided for @backupPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'The password is not saved. If you forget it, we cannot open the backup.'**
  String get backupPasswordHint;

  /// No description provided for @backupPasswordRule.
  ///
  /// In en, this message translates to:
  /// **'Use at least 12 characters and no more than 1024 UTF-8 bytes.'**
  String get backupPasswordRule;

  /// No description provided for @backupPrepare.
  ///
  /// In en, this message translates to:
  /// **'Prepare encrypted backup'**
  String get backupPrepare;

  /// No description provided for @backupPick.
  ///
  /// In en, this message translates to:
  /// **'Choose encrypted backup'**
  String get backupPick;

  /// No description provided for @backupOpen.
  ///
  /// In en, this message translates to:
  /// **'Open and review backup'**
  String get backupOpen;

  /// No description provided for @backupReview.
  ///
  /// In en, this message translates to:
  /// **'Content review'**
  String get backupReview;

  /// No description provided for @backupSave.
  ///
  /// In en, this message translates to:
  /// **'Save backup file'**
  String get backupSave;

  /// No description provided for @backupSaved.
  ///
  /// In en, this message translates to:
  /// **'Backup file saved.'**
  String get backupSaved;

  /// No description provided for @backupCreatedAt.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get backupCreatedAt;

  /// No description provided for @backupScopes.
  ///
  /// In en, this message translates to:
  /// **'Shared spaces in backup'**
  String get backupScopes;

  /// No description provided for @backupPending.
  ///
  /// In en, this message translates to:
  /// **'Unsent operations in backup'**
  String get backupPending;

  /// No description provided for @backupCredentialsExcluded.
  ///
  /// In en, this message translates to:
  /// **'Passwords, device sessions and notification tokens are excluded.'**
  String get backupCredentialsExcluded;

  /// No description provided for @backupRemoteQuarantine.
  ///
  /// In en, this message translates to:
  /// **'Restored shared work stays protected and separate. After signing in to the matching account, review it and explicitly allow recovery; nothing is sent automatically.'**
  String get backupRemoteQuarantine;

  /// No description provided for @backupMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge with personal records'**
  String get backupMerge;

  /// No description provided for @backupReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace personal records'**
  String get backupReplace;

  /// No description provided for @backupMergeDescription.
  ///
  /// In en, this message translates to:
  /// **'Add missing personal records. Different content with the same ID rejects the entire merge.'**
  String get backupMergeDescription;

  /// No description provided for @backupReplaceDescription.
  ///
  /// In en, this message translates to:
  /// **'The backup replaces current personal records. Save a current backup first.'**
  String get backupReplaceDescription;

  /// No description provided for @backupRestoreConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm restore'**
  String get backupRestoreConfirm;

  /// No description provided for @backupRestored.
  ///
  /// In en, this message translates to:
  /// **'Backup restored. Shared work is not sent automatically.'**
  String get backupRestored;

  /// No description provided for @backupWrongPassword.
  ///
  /// In en, this message translates to:
  /// **'The password is incorrect or the backup is damaged. Data was not changed.'**
  String get backupWrongPassword;

  /// No description provided for @backupUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This backup version cannot be opened. Use a compatible app.'**
  String get backupUnsupported;

  /// No description provided for @backupChanged.
  ///
  /// In en, this message translates to:
  /// **'This preview is no longer current. Prepare the backup again or review the contents before restoring.'**
  String get backupChanged;

  /// No description provided for @backupRecoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Restored shared work'**
  String get backupRecoveryTitle;

  /// No description provided for @backupRecoveryReview.
  ///
  /// In en, this message translates to:
  /// **'Review restored work'**
  String get backupRecoveryReview;

  /// No description provided for @backupRecoveryResume.
  ///
  /// In en, this message translates to:
  /// **'Allow restored work to resume'**
  String get backupRecoveryResume;

  /// No description provided for @backupRecoveryBlocked.
  ///
  /// In en, this message translates to:
  /// **'This work requires the matching account and current access. The copy remains protected.'**
  String get backupRecoveryBlocked;

  /// No description provided for @backupRecoveryNone.
  ///
  /// In en, this message translates to:
  /// **'No restored shared-work packages.'**
  String get backupRecoveryNone;

  /// No description provided for @backupReadError.
  ///
  /// In en, this message translates to:
  /// **'The backup could not be opened or saved. Try again.'**
  String get backupReadError;

  /// No description provided for @backupShoppingItems.
  ///
  /// In en, this message translates to:
  /// **'Shopping items'**
  String get backupShoppingItems;

  /// No description provided for @backupOtherRecords.
  ///
  /// In en, this message translates to:
  /// **'Other records'**
  String get backupOtherRecords;

  /// No description provided for @backupSaveCancelled.
  ///
  /// In en, this message translates to:
  /// **'Saving cancelled. The file was not saved.'**
  String get backupSaveCancelled;

  /// No description provided for @backupDownloadStarted.
  ///
  /// In en, this message translates to:
  /// **'Backup download started. Check your browser downloads.'**
  String get backupDownloadStarted;

  /// No description provided for @backupSourceAccount.
  ///
  /// In en, this message translates to:
  /// **'Backup account'**
  String get backupSourceAccount;

  /// No description provided for @backupSourceServer.
  ///
  /// In en, this message translates to:
  /// **'Backup server'**
  String get backupSourceServer;

  /// No description provided for @backupLocalOnly.
  ///
  /// In en, this message translates to:
  /// **'Device only'**
  String get backupLocalOnly;

  /// No description provided for @backupAccountMatches.
  ///
  /// In en, this message translates to:
  /// **'Personal records can be restored locally. Resuming shared work checks the account and permissions again.'**
  String get backupAccountMatches;

  /// No description provided for @backupAccountDifferent.
  ///
  /// In en, this message translates to:
  /// **'The backup belongs to another account. Shared work stays protected until you sign in to the matching account.'**
  String get backupAccountDifferent;

  /// No description provided for @backupCompleteness.
  ///
  /// In en, this message translates to:
  /// **'The backup includes personal content, permitted cached records and unsynced work. Server data that has not been downloaded to this device is excluded.'**
  String get backupCompleteness;

  /// No description provided for @backupTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The backup exceeds the 64 MiB limit. Your data was not changed.'**
  String get backupTooLarge;

  /// No description provided for @backupMergeConflict.
  ///
  /// In en, this message translates to:
  /// **'The backup contains different content with an existing ID. Merge was rejected; your data was not changed.'**
  String get backupMergeConflict;

  /// No description provided for @privateSyncLocalPending.
  ///
  /// In en, this message translates to:
  /// **'New local records are awaiting your review.'**
  String get privateSyncLocalPending;

  /// No description provided for @backupRecoveryState.
  ///
  /// In en, this message translates to:
  /// **'Recovered work status'**
  String get backupRecoveryState;

  /// No description provided for @backupRecoveryReady.
  ///
  /// In en, this message translates to:
  /// **'Ready to review and resume'**
  String get backupRecoveryReady;

  /// No description provided for @backupLegacyJson.
  ///
  /// In en, this message translates to:
  /// **'Legacy unencrypted JSON export'**
  String get backupLegacyJson;

  /// No description provided for @backupIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Some cached spaces in this backup are incomplete. They need to sync again after restoration.'**
  String get backupIncomplete;

  /// No description provided for @backupArchiveReview.
  ///
  /// In en, this message translates to:
  /// **'Separate unlocked backup preview. These records do not enter the active account until you explicitly resume permitted work.'**
  String get backupArchiveReview;

  /// No description provided for @backupCached.
  ///
  /// In en, this message translates to:
  /// **'Cached record; no pending change'**
  String get backupCached;

  /// No description provided for @backupSettingsRetry.
  ///
  /// In en, this message translates to:
  /// **'Restored settings have not been applied yet. Your records are preserved; try again.'**
  String get backupSettingsRetry;

  /// No description provided for @privateFinanceIncomplete.
  ///
  /// In en, this message translates to:
  /// **'The private financial view has not fully downloaded. Visible records and pending changes are preserved; totals appear after a complete sync.'**
  String get privateFinanceIncomplete;

  /// No description provided for @guideTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Jivie'**
  String get guideTitle;

  /// No description provided for @guideOpen.
  ///
  /// In en, this message translates to:
  /// **'A quick guide to Jivie'**
  String get guideOpen;

  /// No description provided for @guideLocalTitle.
  ///
  /// In en, this message translates to:
  /// **'Start on your device'**
  String get guideLocalTitle;

  /// No description provided for @guideLocalBody.
  ///
  /// In en, this message translates to:
  /// **'Tasks, plans, shopping and personal finances work without an account or connection. Start with one task or shopping list. Optional sync requires your explicit choice.'**
  String get guideLocalBody;

  /// No description provided for @guideTodayBody.
  ///
  /// In en, this message translates to:
  /// **'Today shows your next tasks and events. Add a task or event here and see what is coming up. A shared daily overview is available for spaces you can access.'**
  String get guideTodayBody;

  /// No description provided for @guidePlansBody.
  ///
  /// In en, this message translates to:
  /// **'In Plans, organize tasks, projects and events. Add dates and link a task to a project when useful. On a larger screen, you can also reach them from the sidebar.'**
  String get guidePlansBody;

  /// No description provided for @guideShoppingBody.
  ///
  /// In en, this message translates to:
  /// **'In Shopping, create a list, add items and mark purchases. A personal list stays on your device; copying it to a shared space is your explicit choice.'**
  String get guideShoppingBody;

  /// No description provided for @guideMoreBody.
  ///
  /// In en, this message translates to:
  /// **'More contains finances, home, garden, account and settings. Settings offer theme, language, encrypted backups and this guide. An account and server are optional; signing in alone does not share personal finances or turn on sync. Set up notifications separately.'**
  String get guideMoreBody;

  /// No description provided for @guideSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get guideSkip;

  /// No description provided for @guideBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get guideBack;

  /// No description provided for @guideNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get guideNext;

  /// No description provided for @guideDone.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get guideDone;

  /// No description provided for @guideProgress.
  ///
  /// In en, this message translates to:
  /// **'{step} of {total}'**
  String guideProgress(int step, int total);

  /// No description provided for @deletionAccountSettings.
  ///
  /// In en, this message translates to:
  /// **'Account settings'**
  String get deletionAccountSettings;

  /// No description provided for @deletionTitle.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete account'**
  String get deletionTitle;

  /// No description provided for @deletionLocalOnly.
  ///
  /// In en, this message translates to:
  /// **'You are using local mode. There is no server account to delete. Local work stays on your device.'**
  String get deletionLocalOnly;

  /// No description provided for @deletionWarning.
  ///
  /// In en, this message translates to:
  /// **'Deletion affects the displayed account on this self-hosted server, including the same Kanboard account. It is permanent. Copies already obtained by other members cannot be recalled.'**
  String get deletionWarning;

  /// No description provided for @deletionPreview.
  ///
  /// In en, this message translates to:
  /// **'Review account deletion'**
  String get deletionPreview;

  /// No description provided for @deletionLocalConsequences.
  ///
  /// In en, this message translates to:
  /// **'Deletion also removes this account’s private SYNCED data, its local server copy, pending changes, reminders, sync binding and staged recovery work. Independent personal data in the local workspace remains. Synced data is not automatically copied back to local mode.'**
  String get deletionLocalConsequences;

  /// No description provided for @deletionExportLimit.
  ///
  /// In en, this message translates to:
  /// **'An encrypted .vsakdan backup is not a complete Kanboard or attachment archive. It cannot resume this account’s server work after deletion. To retain private synced personal records for standalone use, use the explicit JSON export below. Contact the administrator for a full Kanboard archive before deleting.'**
  String get deletionExportLimit;

  /// No description provided for @deletionImpact.
  ///
  /// In en, this message translates to:
  /// **'Server impact'**
  String get deletionImpact;

  /// No description provided for @deletionSharedRemains.
  ///
  /// In en, this message translates to:
  /// **'shared space remains'**
  String get deletionSharedRemains;

  /// No description provided for @deletionBlocked.
  ///
  /// In en, this message translates to:
  /// **'Resolve the requirements below before deletion, then review the impact again.'**
  String get deletionBlocked;

  /// No description provided for @deletionAcknowledge.
  ///
  /// In en, this message translates to:
  /// **'I understand the permanent deletion of this account, its synced data and the described effects on shared work.'**
  String get deletionAcknowledge;

  /// No description provided for @deletionTypeDelete.
  ///
  /// In en, this message translates to:
  /// **'Type DELETE to confirm'**
  String get deletionTypeDelete;

  /// No description provided for @deletionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get deletionConfirm;

  /// No description provided for @deletionUnknown.
  ///
  /// In en, this message translates to:
  /// **'Deletion is not confirmed. The connection was interrupted or the response was inconclusive. Check the status of this same request in Account settings; your password is not stored.'**
  String get deletionUnknown;

  /// No description provided for @deletionNotConfirmed.
  ///
  /// In en, this message translates to:
  /// **'The server has not confirmed deletion. The account may still be active. Retry with the same decisions and a fresh password/TOTP.'**
  String get deletionNotConfirmed;

  /// No description provided for @deletionSuccess.
  ///
  /// In en, this message translates to:
  /// **'The server confirmed deletion. You can continue in local mode.'**
  String get deletionSuccess;

  /// No description provided for @deletionCheckStatus.
  ///
  /// In en, this message translates to:
  /// **'Check deletion status'**
  String get deletionCheckStatus;

  /// No description provided for @deletionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This server does not support account deletion in Jivie. Its administrator must enable deletion. Deletion cannot be confirmed offline.'**
  String get deletionUnavailable;

  /// No description provided for @deletionStale.
  ///
  /// In en, this message translates to:
  /// **'Data has changed. Review the impact again and confirm your decisions.'**
  String get deletionStale;

  /// No description provided for @deletionPersonalScopes.
  ///
  /// In en, this message translates to:
  /// **'Private spaces to delete'**
  String get deletionPersonalScopes;

  /// No description provided for @deletionPersonalRecords.
  ///
  /// In en, this message translates to:
  /// **'Private records to delete'**
  String get deletionPersonalRecords;

  /// No description provided for @deletionPersonalFinance.
  ///
  /// In en, this message translates to:
  /// **'Private finance records to delete'**
  String get deletionPersonalFinance;

  /// No description provided for @deletionMemberships.
  ///
  /// In en, this message translates to:
  /// **'Memberships to remove'**
  String get deletionMemberships;

  /// No description provided for @deletionDevices.
  ///
  /// In en, this message translates to:
  /// **'Devices and sessions to revoke'**
  String get deletionDevices;

  /// No description provided for @deletionPush.
  ///
  /// In en, this message translates to:
  /// **'Push registrations to remove'**
  String get deletionPush;

  /// No description provided for @deletionEmailTokens.
  ///
  /// In en, this message translates to:
  /// **'Email codes to revoke'**
  String get deletionEmailTokens;

  /// No description provided for @deletionRelatedData.
  ///
  /// In en, this message translates to:
  /// **'Related records to remove'**
  String get deletionRelatedData;

  /// No description provided for @deletionOwnedScopes.
  ///
  /// In en, this message translates to:
  /// **'Choose a new owner for the shared space'**
  String get deletionOwnedScopes;

  /// No description provided for @deletionLastAdmin.
  ///
  /// In en, this message translates to:
  /// **'Assign another Kanboard administrator first'**
  String get deletionLastAdmin;

  /// No description provided for @deletionContributions.
  ///
  /// In en, this message translates to:
  /// **'Resolve your contributions and their shared references'**
  String get deletionContributions;

  /// No description provided for @deletionStructure.
  ///
  /// In en, this message translates to:
  /// **'Keep only a generic structure for other members’ records. The original name and owner are removed; a finance account retains its currency and opening balance. My entries are deleted and shared totals may change.'**
  String get deletionStructure;

  /// No description provided for @deletionSharedRecordsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Own shared records to delete'**
  String get deletionSharedRecordsDeleted;

  /// No description provided for @deletionSharedRecordsUpdated.
  ///
  /// In en, this message translates to:
  /// **'Shared records to detach'**
  String get deletionSharedRecordsUpdated;

  /// No description provided for @deletionSharedFinanceDeleted.
  ///
  /// In en, this message translates to:
  /// **'Own shared finance records to delete'**
  String get deletionSharedFinanceDeleted;

  /// No description provided for @deletionSharedFinanceUpdated.
  ///
  /// In en, this message translates to:
  /// **'Shared finance records to detach'**
  String get deletionSharedFinanceUpdated;

  /// No description provided for @deletionLegacyTasks.
  ///
  /// In en, this message translates to:
  /// **'Own Kanboard tasks to delete'**
  String get deletionLegacyTasks;

  /// No description provided for @deletionLegacyComments.
  ///
  /// In en, this message translates to:
  /// **'Own Kanboard comments to delete'**
  String get deletionLegacyComments;

  /// No description provided for @deletionLegacyFiles.
  ///
  /// In en, this message translates to:
  /// **'Own Kanboard attachments to delete'**
  String get deletionLegacyFiles;

  /// No description provided for @deletionAssignedTasks.
  ///
  /// In en, this message translates to:
  /// **'Kanboard tasks to unassign'**
  String get deletionAssignedTasks;

  /// No description provided for @deletionAssignedSubtasks.
  ///
  /// In en, this message translates to:
  /// **'Kanboard subtasks to unassign'**
  String get deletionAssignedSubtasks;

  /// No description provided for @deletionLegacyPrivate.
  ///
  /// In en, this message translates to:
  /// **'Resolve the private Kanboard project first'**
  String get deletionLegacyPrivate;

  /// No description provided for @deletionServerCleanup.
  ///
  /// In en, this message translates to:
  /// **'The account and database records have been removed. The server is still deleting attachments; check status until completion is confirmed.'**
  String get deletionServerCleanup;

  /// No description provided for @deletionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry the same request'**
  String get deletionRetry;

  /// No description provided for @deletionRetryReview.
  ///
  /// In en, this message translates to:
  /// **'This retry uses the same decisions and the same preview below. Enter your password and TOTP again. If the preview is stale, the server rejects deletion and requires a new review.'**
  String get deletionRetryReview;

  /// No description provided for @deletionDeleteOwnedScope.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete this space and its content too'**
  String get deletionDeleteOwnedScope;

  /// No description provided for @deletionUnnamedStructure.
  ///
  /// In en, this message translates to:
  /// **'Shared structure without permission to view details'**
  String get deletionUnnamedStructure;

  /// No description provided for @deletionMinorUnits.
  ///
  /// In en, this message translates to:
  /// **'minor currency units'**
  String get deletionMinorUnits;

  /// No description provided for @deletionRetainedEdits.
  ///
  /// In en, this message translates to:
  /// **'Server records created by your account are deleted. Records created by others remain, including your edits to their content. Your identity references are removed; individual field edits cannot be separated by author.'**
  String get deletionRetainedEdits;

  /// No description provided for @jiviePrivacyLink.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get jiviePrivacyLink;

  /// No description provided for @jivieHelpLink.
  ///
  /// In en, this message translates to:
  /// **'Help and support'**
  String get jivieHelpLink;

  /// No description provided for @jivieDeletionLink.
  ///
  /// In en, this message translates to:
  /// **'Account deletion website'**
  String get jivieDeletionLink;

  /// No description provided for @jivieLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the link.'**
  String get jivieLinkFailed;

  /// No description provided for @deletionSpaceDeleted.
  ///
  /// In en, this message translates to:
  /// **'This shared space and its content will be permanently deleted.'**
  String get deletionSpaceDeleted;

  /// No description provided for @deletionCancelPending.
  ///
  /// In en, this message translates to:
  /// **'Cancel pending request'**
  String get deletionCancelPending;

  /// No description provided for @deletionCancelled.
  ///
  /// In en, this message translates to:
  /// **'The server confirmed cancellation. This request can no longer delete the account. Review the impact again to delete it.'**
  String get deletionCancelled;

  /// No description provided for @deletionLegacyLocal.
  ///
  /// In en, this message translates to:
  /// **'Separately stored legacy Kanboard connections, caches and AI conversations are not removed by this action. A legacy connection to the deleted account will no longer work.'**
  String get deletionLegacyLocal;

  /// No description provided for @deletionPersonalExport.
  ///
  /// In en, this message translates to:
  /// **'Export personal data for local recovery'**
  String get deletionPersonalExport;

  /// No description provided for @deletionJsonWarning.
  ///
  /// In en, this message translates to:
  /// **'This standalone copy contains currently accessible personal records, including private synced records. JSON is not encrypted; save it securely. It contains no shared work, sessions or sync bindings. After deletion, explicitly import it in local mode through Settings. Do not upload recovered data to another account without your explicit choice.'**
  String get deletionJsonWarning;

  /// No description provided for @gardenTitle.
  ///
  /// In en, this message translates to:
  /// **'Garden'**
  String get gardenTitle;

  /// No description provided for @gardenIntro.
  ///
  /// In en, this message translates to:
  /// **'Keep planting notes and arrange beds, plants or other areas by hand.'**
  String get gardenIntro;

  /// No description provided for @gardenLocalOnly.
  ///
  /// In en, this message translates to:
  /// **'On this device · no sync or sharing'**
  String get gardenLocalOnly;

  /// No description provided for @gardenNew.
  ///
  /// In en, this message translates to:
  /// **'New garden'**
  String get gardenNew;

  /// No description provided for @gardenEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit garden'**
  String get gardenEdit;

  /// No description provided for @gardenName.
  ///
  /// In en, this message translates to:
  /// **'Garden name'**
  String get gardenName;

  /// No description provided for @gardenNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a garden name.'**
  String get gardenNameRequired;

  /// No description provided for @gardenEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your first garden'**
  String get gardenEmptyTitle;

  /// No description provided for @gardenEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Name your garden, add notes and draw its layout. You can edit everything without an account or connection.'**
  String get gardenEmptyBody;

  /// No description provided for @gardenLayout.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get gardenLayout;

  /// No description provided for @gardenSelectTool.
  ///
  /// In en, this message translates to:
  /// **'Select / move'**
  String get gardenSelectTool;

  /// No description provided for @gardenDrawTool.
  ///
  /// In en, this message translates to:
  /// **'Draw area'**
  String get gardenDrawTool;

  /// No description provided for @gardenUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo layout change'**
  String get gardenUndo;

  /// No description provided for @gardenDrawHelp.
  ///
  /// In en, this message translates to:
  /// **'Drag from one corner to another to draw a rectangular area.'**
  String get gardenDrawHelp;

  /// No description provided for @gardenSelectHelp.
  ///
  /// In en, this message translates to:
  /// **'Tap an area to select it. Drag to move it; edit its size and label in the list.'**
  String get gardenSelectHelp;

  /// No description provided for @gardenCanvasDescription.
  ///
  /// In en, this message translates to:
  /// **'Garden layout sketch. Areas can also be edited in the list.'**
  String get gardenCanvasDescription;

  /// No description provided for @gardenSketchDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'This is a layout sketch, without a physical scale or real distances. Confirm your changes with Save.'**
  String get gardenSketchDisclaimer;

  /// No description provided for @gardenAreas.
  ///
  /// In en, this message translates to:
  /// **'Areas'**
  String get gardenAreas;

  /// No description provided for @gardenAreaListHelp.
  ///
  /// In en, this message translates to:
  /// **'You can also add and edit areas using a form, without drawing.'**
  String get gardenAreaListHelp;

  /// No description provided for @gardenAddArea.
  ///
  /// In en, this message translates to:
  /// **'Add area'**
  String get gardenAddArea;

  /// No description provided for @gardenNoAreas.
  ///
  /// In en, this message translates to:
  /// **'No areas yet. Draw the first one or add it using the form.'**
  String get gardenNoAreas;

  /// No description provided for @gardenEditArea.
  ///
  /// In en, this message translates to:
  /// **'Edit area'**
  String get gardenEditArea;

  /// No description provided for @gardenAreaLabel.
  ///
  /// In en, this message translates to:
  /// **'What goes here?'**
  String get gardenAreaLabel;

  /// No description provided for @gardenLabelRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter an area label.'**
  String get gardenLabelRequired;

  /// No description provided for @gardenPositionX.
  ///
  /// In en, this message translates to:
  /// **'From left'**
  String get gardenPositionX;

  /// No description provided for @gardenPositionY.
  ///
  /// In en, this message translates to:
  /// **'From top'**
  String get gardenPositionY;

  /// No description provided for @gardenWidth.
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get gardenWidth;

  /// No description provided for @gardenHeight.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get gardenHeight;

  /// No description provided for @gardenGeometryHelp.
  ///
  /// In en, this message translates to:
  /// **'Position and size are percentages of the whole sketch.'**
  String get gardenGeometryHelp;

  /// No description provided for @gardenNumberError.
  ///
  /// In en, this message translates to:
  /// **'Enter 0–100; size must be at least 1.'**
  String get gardenNumberError;

  /// No description provided for @gardenGeometryError.
  ///
  /// In en, this message translates to:
  /// **'The whole area must stay inside the sketch. Reduce its size or adjust its position.'**
  String get gardenGeometryError;

  /// No description provided for @gardenUnsavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get gardenUnsavedTitle;

  /// No description provided for @gardenUnsavedBody.
  ///
  /// In en, this message translates to:
  /// **'Your garden changes have not been saved. Leaving the editor discards them.'**
  String get gardenUnsavedBody;

  /// No description provided for @gardenKeepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get gardenKeepEditing;

  /// No description provided for @gardenDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard changes'**
  String get gardenDiscard;

  /// No description provided for @gardenSaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not save changes. Your draft is still open. Try again; if the saved garden changed, reopen it.'**
  String get gardenSaveError;

  /// No description provided for @gardenDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete garden?'**
  String get gardenDeleteTitle;

  /// No description provided for @gardenDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'The garden “{name}”, its notes and all areas will be deleted from this device.'**
  String gardenDeleteBody(String name);

  /// No description provided for @gardenDefaultArea.
  ///
  /// In en, this message translates to:
  /// **'Area {number}'**
  String gardenDefaultArea(int number);

  /// No description provided for @gardenAreaCount.
  ///
  /// In en, this message translates to:
  /// **'{count} areas'**
  String gardenAreaCount(int count);

  /// No description provided for @gardenAreaPosition.
  ///
  /// In en, this message translates to:
  /// **'Left {x}%, top {y}% · {width} × {height}%'**
  String gardenAreaPosition(int x, int y, int width, int height);

  /// No description provided for @financePlanPendingEntries.
  ///
  /// In en, this message translates to:
  /// **'Unconfirmed entries'**
  String get financePlanPendingEntries;

  /// No description provided for @financePlanPendingDescription.
  ///
  /// In en, this message translates to:
  /// **'All expected income and expenses, including undated entries and entries beyond the forecast. Open an entry to confirm the actual amount.'**
  String get financePlanPendingDescription;

  /// No description provided for @financePlanUndatedEntry.
  ///
  /// In en, this message translates to:
  /// **'No date set'**
  String get financePlanUndatedEntry;

  /// No description provided for @financePlanForecastPeriod.
  ///
  /// In en, this message translates to:
  /// **'Dated entries through {date}, showing the closing total for each day.'**
  String financePlanForecastPeriod(String date);
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
