// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Slovenian (`sl`).
class AppLocalizationsSl extends AppLocalizations {
  AppLocalizationsSl([String locale = 'sl']) : super(locale);

  @override
  String get kanbanConnect => 'Kanban povezava';

  @override
  String get routeError => 'Napaka poti';

  @override
  String get unknownError => 'Neznana napaka';

  @override
  String get kanboardWorkspace => 'Delovni prostor Kanboard';

  @override
  String get restoringSession => 'Obnavljanje seje...';

  @override
  String get connectToKanboard => 'Poveži se s Kanboardom';

  @override
  String get projects => 'Projekti';

  @override
  String get projectDefaults => 'Privzete nastavitve projekta';

  @override
  String get aiSettings => 'Nastavitve AI';

  @override
  String get aiChat => 'AI klepet';

  @override
  String get connectionSettings => 'Nastavitve povezave';

  @override
  String get refresh => 'Osveži';

  @override
  String get logout => 'Odjava';

  @override
  String get newProject => 'Nov projekt';

  @override
  String get couldNotLoadProjects => 'Projektov ni bilo mogoče naložiti';

  @override
  String get retry => 'Poskusi znova';

  @override
  String get noActiveSession => 'Ni aktivne seje';

  @override
  String get noActiveSessionConnectFirst =>
      'Ni aktivne seje. Najprej se povežite.';

  @override
  String get connectToKanboardToContinue =>
      'Za nadaljevanje se povežite s Kanboardom.';

  @override
  String get connect => 'Poveži';

  @override
  String get projectsWorkspace => 'Delovni prostor projektov';

  @override
  String get trackOrganizeAndOpenYourKanboardProjects =>
      'Spremljajte, organizirajte in odpirajte svoje Kanboard projekte.';

  @override
  String get connectYourKanboardAccountToLoadProjectData =>
      'Povežite svoj Kanboard račun za nalaganje podatkov projektov.';

  @override
  String get total => 'Skupaj';

  @override
  String get active => 'Aktivni';

  @override
  String get inactive => 'Neaktivni';

  @override
  String get noProjectsYet => 'Projektov še ni';

  @override
  String
  get createYourFirstProjectFromTheActionButtonAndStartOrganizingYourBoard =>
      'Ustvarite svoj prvi projekt z akcijskim gumbom in začnite organizirati tablo.';

  @override
  String get openBoard => 'Odpri projekt';

  @override
  String get projectAttachments => 'Priponke projekta';

  @override
  String get deleteProject => 'Izbriši projekt';

  @override
  String get noDescriptionYetOpenTheProjectToAddContext =>
      'Opisa še ni. Odprite projekt in dodajte podrobnosti.';

  @override
  String get deleteProject2 => 'Izbrišem projekt?';

  @override
  String thisWillRemovePermanently(Object name) {
    return 'To bo trajno odstranilo \"$name\".';
  }

  @override
  String get cancel => 'Prekliči';

  @override
  String get delete => 'Izbriši';

  @override
  String get createProject => 'Ustvari projekt';

  @override
  String get editProject => 'Uredi projekt';

  @override
  String get projectName => 'Ime projekta';

  @override
  String get description => 'Opis';

  @override
  String get projectColorSyncedViaMetadata =>
      'Barva projekta (sinhronizirano prek metapodatkov)';

  @override
  String get noColor => 'Brez barve';

  @override
  String get save => 'Shrani';

  @override
  String get stop => 'Ustavi';

  @override
  String get send => 'Pošlji';

  @override
  String attachments(Object name) {
    return 'Priponke · $name';
  }

  @override
  String get noProjectAttachmentsYet => 'Priponk projekta še ni.';

  @override
  String get download => 'Prenesi';

  @override
  String get addFiles => 'Dodaj datoteke';

  @override
  String get close => 'Zapri';

  @override
  String get projectDefaults2 => 'Privzete nastavitve projekta';

  @override
  String get appLanguage => 'Jezik aplikacije';

  @override
  String get followSystemKeepsLocaleAutomatic =>
      'Sledenje sistemu ohranja samodejno izbiro jezika.';

  @override
  String get language => 'Jezik';

  @override
  String get followSystemDefault => 'Sledi sistemu (privzeto)';

  @override
  String get english => 'Angleščina';

  @override
  String get slovene => 'Slovenščina';

  @override
  String get templateAppliedToEveryNewProjectCreatedFromThisApp =>
      'Predloga se uporabi za vsak nov projekt, ustvarjen v tej aplikaciji.';

  @override
  String get leaveFieldsEmptyToKeepServerDefaults =>
      'Polja pustite prazna za ohranitev privzetih nastavitev strežnika.';

  @override
  String get savingADefaultCurrencyAlsoAppliesItToAllExistingProjects =>
      'Shranjevanje privzete valute jo uporabi tudi za vse obstoječe projekte.';

  @override
  String get defaultBoardColumns => 'Privzeti stolpci table';

  @override
  String get defaultBoardColumnsHint =>
      'Ena vrstica na stolpec, npr.\\nBacklog\\nPripravljeno\\nV teku\\nKončano';

  @override
  String get defaultSwimlane => 'Privzeta steza';

  @override
  String get exampleMain => 'Primer: Glavno';

  @override
  String get exampleUSD => 'Primer: USD';

  @override
  String get defaultExpenseCurrency => 'Privzeta valuta stroškov';

  @override
  String get reset => 'Ponastavi';

  @override
  String get enableAI => 'Omogoči AI';

  @override
  String get instantResponse => 'Takojšen odgovor';

  @override
  String get thinkingResponse => 'Razmislek (thinking)';

  @override
  String get thinkingEffort => 'Nivo razmisleka';

  @override
  String get effortLow => 'Nizek';

  @override
  String get effortMedium => 'Srednji';

  @override
  String get effortHigh => 'Visok';

  @override
  String get aiModel => 'AI model';

  @override
  String get openAiApiKey => 'OpenAI API ključ';

  @override
  String get openAiApiKeyIsRequired => 'OpenAI API ključ je obvezen.';

  @override
  String get testAIConnection => 'Preizkusi AI povezavo';

  @override
  String get fetchAvailableModels => 'Pridobi razpoložljive modele';

  @override
  String availableModelsFetched(Object count) {
    return 'Pridobljenih modelov: $count.';
  }

  @override
  String availableModelsFetchFailed(Object error) {
    return 'Pridobivanje modelov ni uspelo: $error';
  }

  @override
  String get aiSettingsSaved => 'AI nastavitve so shranjene.';

  @override
  String aiConnectionTestSucceeded(Object result) {
    return 'AI test je uspel: $result';
  }

  @override
  String aiConnectionTestFailed(Object error) {
    return 'AI test ni uspel: $error';
  }

  @override
  String get aiSettingsSecurityNotice =>
      'Varnostna opomba: lokalni način ključa je manj varen. Vsak z dostopom do naprave/aplikacije lahko pridobi ta ključ.';

  @override
  String get saving => 'Shranjevanje...';

  @override
  String get saveDefaults => 'Shrani privzete';

  @override
  String get configureAiInSettings =>
      'Pred uporabo AI funkcij najprej nastavite AI v nastavitvah.';

  @override
  String get aiNotEnabledForThisProject => 'AI za ta projekt ni omogočen.';

  @override
  String get aiProjectPolicySaved => 'Politika AI za projekt je shranjena.';

  @override
  String get aiActionPlanDetected => 'Zaznan je AI akcijski načrt';

  @override
  String aiActionsApplied(Object swimlanes, Object tasks) {
    return 'Uporabljene akcije: steze $swimlanes, naloge $tasks.';
  }

  @override
  String aiActionsAppliedDetailed(
    Object swimlanes,
    Object columns,
    Object tasks,
    Object moved,
    Object skipped,
  ) {
    return 'Uporabljene akcije: steze $swimlanes, stolpci $columns, nove naloge $tasks, premaknjene naloge $moved, preskočeni premiki $skipped.';
  }

  @override
  String get enableAIForProject => 'Omogoči AI za ta projekt';

  @override
  String get aiKeyMode => 'Način AI ključa';

  @override
  String get ownerKeyMode => 'Lastnikov ključ (deljeni stroški)';

  @override
  String get userKeyRequiredMode => 'Vsak uporabnik potrebuje svoj ključ';

  @override
  String get aiCostNoticeTitle => 'Obvestilo o stroških AI';

  @override
  String aiCostNoticeBody(Object owner) {
    return 'Ta projekt uporablja način lastnikovega ključa. Uporaba AI se tukaj zaračuna uporabniku $owner.';
  }

  @override
  String get iUnderstand => 'Razumem';

  @override
  String aiChatForProject(Object name) {
    return 'AI klepet · $name';
  }

  @override
  String get newChat => 'Nov klepet';

  @override
  String get continueChat => 'Nadaljuj klepet';

  @override
  String get exportChat => 'Izvozi klepet';

  @override
  String currentChatId(Object id) {
    return 'Trenutni klepet: $id';
  }

  @override
  String get noSavedChatsForProject =>
      'Za ta projekt še ni shranjenih klepetov.';

  @override
  String get noMessagesToExport => 'Ni sporočil za izvoz.';

  @override
  String chatExportFailed(Object error) {
    return 'Izvoz klepeta ni uspel: $error';
  }

  @override
  String aiRequestFailed(Object error) {
    return 'AI zahteva ni uspela: $error';
  }

  @override
  String get aiIsTyping => 'AI piše ...';

  @override
  String get aiSuggestedTitle => 'AI predlagan naslov';

  @override
  String get aiSuggestedDescription => 'AI predlagan opis';

  @override
  String get aiImproveTitle => 'Izboljšaj naslov z AI';

  @override
  String get aiImproveDescription => 'Izboljšaj opis z AI';

  @override
  String get message => 'Sporočilo';

  @override
  String get projectDefaultsReset =>
      'Privzete nastavitve projekta so ponastavljene.';

  @override
  String get resetDefaults => 'Ponastavim privzete?';

  @override
  String
  get thisClearsCustomDefaultsAndUsesKanboardServerDefaultsForNewProjects =>
      'To počisti prilagojene privzete nastavitve in uporabi privzete nastavitve strežnika Kanboard za nove projekte.';

  @override
  String get connectYourKanboardInstance => 'Povežite svojo Kanboard instanco';

  @override
  String get loadedSavedCredentials => 'Naložene shranjene poverilnice.';

  @override
  String connectedViaJsonrpcTokenAuthServerVersion(Object version) {
    return 'Povezano prek avtentikacije jsonrpc z žetonom. Različica strežnika: $version';
  }

  @override
  String connectedAsVersion(Object username, Object version) {
    return 'Povezano kot $username. Različica: $version';
  }

  @override
  String connectedSuccessfullyButServerVersionIsTarget1250(Object version) {
    return 'Povezava je uspela, vendar je različica strežnika $version (cilj: 1.2.50).';
  }

  @override
  String
  connectionFailedTipIfYouCopiedAPIUserAccessTryUsernameJsonrpcWithThatToken(
    Object error,
  ) {
    return 'Povezava ni uspela: $error\nNamig: če ste kopirali \"API User Access\", poskusite z uporabniškim imenom \"jsonrpc\" in tem žetonom.';
  }

  @override
  String get usePersonalTokenUsernameOrUseApplicationTokenWithUsernameJsonrpc =>
      'Uporabite osebni žeton + uporabniško ime ali aplikacijski žeton z uporabniškim imenom \"jsonrpc\".';

  @override
  String get nothingToExportYetConnectOnceOrFillAllFieldsFirst =>
      'Še ni nič za izvoz. Najprej se povežite ali izpolnite vsa polja.';

  @override
  String get scanThisCodeWithYourPhoneInTheConnectScreen =>
      'Skenirajte to kodo s telefonom na zaslonu za povezavo.';

  @override
  String get couldNotRenderQRError => 'QR ni bilo mogoče prikazati.\n\$error';

  @override
  String get credentialsTransferQR => 'QR za prenos poverilnic';

  @override
  String get ifQRRenderingFailsCopyPasteTheTransferCode =>
      'Če prikaz QR ne uspe, kopirajte/prilepite kodo za prenos.';

  @override
  String get securityNoteThisQRContainsYourAPITokenInPlainText =>
      'Varnostna opomba: ta QR vsebuje vaš API žeton v navadnem besedilu.';

  @override
  String get transferCodeCopied => 'Koda za prenos je kopirana.';

  @override
  String get importedCredentialsFromTransferCode =>
      'Poverilnice so uvožene iz kode za prenos.';

  @override
  String get credentialsImportedTapConnect =>
      'Poverilnice so uvožene. Tapnite Poveži.';

  @override
  String get clipboardIsEmpty => 'Odložišče je prazno.';

  @override
  String invalidTransferCode(Object error) {
    return 'Neveljavna koda za prenos: $error';
  }

  @override
  String get qrScanningIsAvailableOnIOSAndroidUsePasteTransferCodeHere =>
      'Skeniranje QR je na voljo na iOS/Android. Tukaj uporabite \"Prilepi kodo za prenos\".';

  @override
  String get serverURLIsRequired => 'URL strežnika je obvezen.';

  @override
  String get enterAValidURL => 'Vnesite veljaven URL.';

  @override
  String get usernameIsRequired => 'Uporabniško ime je obvezno.';

  @override
  String get tokenIsRequired => 'Žeton je obvezen.';

  @override
  String get passwordIsRequired => 'Geslo je obvezno.';

  @override
  String get credentials => 'Poverilnice';

  @override
  String get authMode => 'Način prijave';

  @override
  String get apiTokenMode => 'API žeton';

  @override
  String get passwordMode => 'Geslo';

  @override
  String get showTransferQR => 'Prikaži QR za prenos';

  @override
  String get pasteTransferCode => 'Prilepi kodo za prenos';

  @override
  String get serverURL => 'URL strežnika';

  @override
  String get serverURLExample => 'https://kanboard.example.com';

  @override
  String get username => 'Uporabniško ime';

  @override
  String get password => 'Geslo';

  @override
  String get personalAccessToken => 'Osebni dostopni žeton';

  @override
  String get useYourKanboardUsernameAndPassword =>
      'Uporabite svoje Kanboard uporabniško ime in geslo.';

  @override
  String get testConnectionContinue => 'Preizkusi povezavo in nadaljuj';

  @override
  String get openProjects => 'Odpri projekte';

  @override
  String
  get authNotePersonalTokenUsuallyUsesYourUsernameApplicationTokenUsuallyUsesUsernameJsonrpc =>
      'Opomba o prijavi: osebni žeton običajno uporablja vaše uporabniško ime; aplikacijski žeton običajno uporablja \"jsonrpc\".';

  @override
  String get authNotePasswordModeUsesYourKanboardLoginCredentials =>
      'Opomba o prijavi: način z geslom uporablja vaše Kanboard prijavne podatke.';

  @override
  String get scanTransferQR => 'Skeniraj QR za prenos';

  @override
  String get transferCredentials => 'Prenesi poverilnice';

  @override
  String get copyCode => 'Kopiraj kodo';

  @override
  String get done => 'Končano';

  @override
  String get boardStructure => 'Struktura table';

  @override
  String get searchTasks => 'Išči naloge';

  @override
  String get newGroceryList => 'Nov nakupovalni seznam';

  @override
  String get refreshBoard => 'Osveži tablo';

  @override
  String get showDoneTasks => 'Prikaži končane naloge';

  @override
  String get hideDoneTasks => 'Skrij končane naloge';

  @override
  String get lockTaskDrag => 'Zakleni vlečenje nalog';

  @override
  String get unlockTaskDrag => 'Odkleni vlečenje nalog';

  @override
  String get newTask => 'Nova naloga';

  @override
  String get groceryList => 'Nakupovalni seznam';

  @override
  String get expenses => 'Stroški';

  @override
  String get search => 'Iskanje';

  @override
  String get structure => 'Struktura';

  @override
  String get swimlanes => 'Steze';

  @override
  String get columns => 'Stolpci';

  @override
  String get tasks => 'Naloge';

  @override
  String get planned => 'Planirano';

  @override
  String get spent => 'Porabljeno';

  @override
  String get remaining => 'Preostalo';

  @override
  String get noBudget => 'Ni proračuna';

  @override
  String get dropATaskHere => 'Spustite nalogo sem';

  @override
  String get unlockDragToMoveTasks => 'Odklenite vlečenje za premikanje nalog';

  @override
  String get edit => 'Uredi';

  @override
  String get markDone => 'Označi kot končano';

  @override
  String get reopen => 'Ponovno odpri';

  @override
  String get taskSearch => 'Iskanje nalog';

  @override
  String deleteFailed(Object error) {
    return 'Izbris ni uspel: $error';
  }

  @override
  String statusUpdateFailed(Object error) {
    return 'Posodobitev statusa ni uspela: $error';
  }

  @override
  String moveFailed(Object error) {
    return 'Premik ni uspel: $error';
  }

  @override
  String get addColumn => 'Dodaj stolpec';

  @override
  String get editColumn => 'Uredi stolpec';

  @override
  String get deleteColumn => 'Izbrišem stolpec?';

  @override
  String deleteColumn2(Object name) {
    return 'Izbrišem stolpec \"$name\"?';
  }

  @override
  String get taskLimit => 'Omejitev nalog';

  @override
  String get addSwimlane => 'Dodaj stezo';

  @override
  String get editSwimlane => 'Uredi stezo';

  @override
  String get deleteSwimlane => 'Izbrišem stezo?';

  @override
  String deleteSwimlane2(Object name) {
    return 'Izbrišem stezo \"$name\"?';
  }

  @override
  String get name => 'Ime';

  @override
  String structure2(Object name) {
    return 'Struktura $name';
  }

  @override
  String get query => 'Poizvedba';

  @override
  String get queryExampleStatusOpenCategoryBug => 'status:open category:bug';

  @override
  String get noResultsYet => 'Rezultatov še ni.';

  @override
  String get projectExpenses => 'Stroški projekta';

  @override
  String get financeTable => 'Finančna tabela';

  @override
  String get financeProject => 'Finančni projekt';

  @override
  String get financeProjectDescription =>
      'Ta projekt se odpre neposredno v finančni tabeli.';

  @override
  String get sharedFinanceTable => 'Deljena finančna tabela';

  @override
  String get currentBalance => 'Trenutno stanje';

  @override
  String get projectionHorizon => 'Obdobje projekcije';

  @override
  String get showPastMonths => 'Prikaži pretekle mesece';

  @override
  String get includeSpentExternalExpensesInProjection =>
      'Vključi porabljene zunanje stroške v projekcijo';

  @override
  String get unsavedFinanceChangesTitle => 'Neshranjene finančne spremembe';

  @override
  String get unsavedFinanceChangesMessage =>
      'Nekateri finančni podatki še niso shranjeni. Želiš vseeno zapustiti stran?';

  @override
  String get leaveWithoutSaving => 'Zapusti brez shranjevanja';

  @override
  String get summedMonthlyIncome => 'Skupni mesečni prihodki';

  @override
  String get summedMonthlyExpenses => 'Skupni mesečni stroški';

  @override
  String get totalBalance => 'Skupno stanje';

  @override
  String get biggestIncomeExpenseGap =>
      'Najnižji mesečni neto (prihodki - stroški)';

  @override
  String get months3 => '3 mesece';

  @override
  String get months6 => '6 mesecev';

  @override
  String get months12 => '12 mesecev';

  @override
  String get lowestProjectedBalance => 'Najnižje projicirano stanje';

  @override
  String get firstNegativeMonth => 'Prvi negativni mesec';

  @override
  String get endBalance => 'Končno stanje';

  @override
  String get recurringMonthlyEnabled => 'Mesečno ponavljajoče (omogočeno)';

  @override
  String get recurringIncomeMonthlyEnabled =>
      'Mesečni ponavljajoči prihodki (omogočeno)';

  @override
  String get monthlyIncomesAndProjections => 'Mesečni prihodki in projekcije';

  @override
  String get month => 'Mesec';

  @override
  String get incomeTotal => 'Skupaj prihodki';

  @override
  String get expensesTotal => 'Skupaj stroški';

  @override
  String get net => 'Razlika';

  @override
  String get closing => 'Končno';

  @override
  String get contributor => 'Uporabnik';

  @override
  String get contributorOptional => 'Uporabnik (neobvezno)';

  @override
  String get source => 'Vir';

  @override
  String get otherIncome => 'Drugi prihodki';

  @override
  String get otherExpense => 'Drugi stroški';

  @override
  String get recurringIncomes => 'Ponavljajoči prihodki';

  @override
  String get recurringExpenses => 'Ponavljajoči stroški';

  @override
  String get plannedIncomes => 'Načrtovani prihodki';

  @override
  String get plannedExpenses => 'Načrtovani stroški';

  @override
  String get expensesFromOtherProjects => 'Stroški iz drugih projektov';

  @override
  String get ongoing => 'tekoče';

  @override
  String get enabled => 'Omogočeno';

  @override
  String get category => 'Kategorija';

  @override
  String get monthlyAmount => 'Mesečni znesek';

  @override
  String get startMonthYYYYMM => 'Začetni mesec (YYYY-MM)';

  @override
  String get endMonthOptionalYYYYMM => 'Končni mesec (YYYY-MM, neobvezno)';

  @override
  String get addRecurringExpense => 'Dodaj ponavljajoči strošek';

  @override
  String get editRecurringExpense => 'Uredi ponavljajoči strošek';

  @override
  String get recurringExpenseFieldsNotValid =>
      'Polja za ponavljajoči strošek niso veljavna.';

  @override
  String get addRecurringIncome => 'Dodaj ponavljajoči prihodek';

  @override
  String get editRecurringIncome => 'Uredi ponavljajoči prihodek';

  @override
  String get recurringIncomeFieldsNotValid =>
      'Polja za ponavljajoči prihodek niso veljavna.';

  @override
  String get addPlannedExpense => 'Dodaj načrtovani strošek';

  @override
  String get editPlannedExpense => 'Uredi načrtovani strošek';

  @override
  String get plannedExpenseFieldsNotValid =>
      'Polja za načrtovani strošek niso veljavna.';

  @override
  String get addPlannedIncome => 'Dodaj načrtovani prihodek';

  @override
  String get editPlannedIncome => 'Uredi načrtovani prihodek';

  @override
  String get plannedIncomeFieldsNotValid =>
      'Polja za načrtovani prihodek niso veljavna.';

  @override
  String get amount => 'Znesek';

  @override
  String get amountHint => '0,00';

  @override
  String get monthYYYYMM => 'Mesec (YYYY-MM)';

  @override
  String get financeContributorMe => 'Jaz';

  @override
  String incomeForPerson(Object name) {
    return 'Prihodek - $name';
  }

  @override
  String get currentBalanceMustBeValidNumber =>
      'Trenutno stanje mora biti veljavno število.';

  @override
  String get financeTableSaved => 'Finančna tabela je shranjena.';

  @override
  String financeTableSaveFailed(Object error) {
    return 'Shranjevanje finančne tabele ni uspelo: $error';
  }

  @override
  String get serverRejectedFinanceTableSave =>
      'Strežnik je zavrnil shranjevanje finančne tabele.';

  @override
  String get expenseSettingsSaved => 'Nastavitve stroškov so shranjene.';

  @override
  String expenseSettingsFailed(Object error) {
    return 'Nastavitve stroškov niso uspele: $error';
  }

  @override
  String get deleteTask => 'Izbrišem nalogo?';

  @override
  String deletePermanently(Object name) {
    return 'Trajno izbrišem \"$name\"?';
  }

  @override
  String get currencyCode => 'Koda valute';

  @override
  String get budget => 'Proračun';

  @override
  String get leaveEmptyForNoBudget => 'Pustite prazno za brez proračuna';

  @override
  String get task => 'Naloga';

  @override
  String get newLabel => 'Novo';

  @override
  String get openStructure => 'Odpri strukturo';

  @override
  String get noBoardDataYet => 'Podatkov table še ni';

  @override
  String get pullToRefreshOrOpenStructureToConfigureColumnsAndSwimlanes =>
      'Povlecite za osvežitev ali odprite strukturo za nastavitev stolpcev in stez.';

  @override
  String get themeMode => 'Način teme';

  @override
  String get systemTheme => 'Sistemska tema';

  @override
  String get lightTheme => 'Svetla tema';

  @override
  String get darkTheme => 'Temna tema';

  @override
  String get add => 'Dodaj';

  @override
  String get additionalDetails => 'Dodatne podrobnosti';

  @override
  String get attachments2 => 'Priponke';

  @override
  String get comments => 'Komentarji';

  @override
  String get subtasks => 'Podnaloge';

  @override
  String get tags => 'Oznake';

  @override
  String get taskLinks => 'Povezave nalog';

  @override
  String get externalLinks => 'Zunanje povezave';

  @override
  String get link => 'Poveži';

  @override
  String get linkTitle => 'Naslov povezave';

  @override
  String get type => 'Tip';

  @override
  String get dependency => 'Odvisnost';

  @override
  String get url => 'URL';

  @override
  String columnSaveFailed(Object error) {
    return 'Shranjevanje stolpca ni uspelo: $error';
  }

  @override
  String columnDeletionFailed(Object error) {
    return 'Brisanje stolpca ni uspelo: $error';
  }

  @override
  String swimlaneSaveFailed(Object error) {
    return 'Shranjevanje steze ni uspelo: $error';
  }

  @override
  String swimlaneDeletionFailed(Object error) {
    return 'Brisanje steze ni uspelo: $error';
  }

  @override
  String projectSaveFailed(Object error) {
    return 'Shranjevanje projekta ni uspelo: $error';
  }

  @override
  String projectDeletionFailed(Object error) {
    return 'Brisanje projekta ni uspelo: $error';
  }

  @override
  String get apply => 'Uporabi';

  @override
  String get post => 'Objavi';

  @override
  String get noAttachmentsYet => 'Priponk še ni.';

  @override
  String get noCommentsYet => 'Komentarjev še ni.';

  @override
  String get noSubtasksYet => 'Podnalog še ni.';

  @override
  String get noTagsAssigned => 'Oznak ni dodeljenih.';

  @override
  String get noTaskLinks => 'Ni povezav nalog.';

  @override
  String get noExternalLinks => 'Ni zunanjih povezav.';

  @override
  String get newTask2 => 'Nova naloga';

  @override
  String get editTask => 'Uredi nalogo';

  @override
  String get title => 'Naslov';

  @override
  String get column => 'Stolpec';

  @override
  String get swimlane => 'Steza';

  @override
  String get assignee => 'Dodeljeno';

  @override
  String get unassigned => 'Nedodeljeno';

  @override
  String get priority => 'Prioriteta';

  @override
  String get dueDate => 'Rok';

  @override
  String get pickDateTime => 'Izberi datum/čas';

  @override
  String get expense => 'Strošek';

  @override
  String get score => 'Ocena';

  @override
  String get pickDueDate => 'Izberi rok';

  @override
  String get clearDueDate => 'Počisti rok';

  @override
  String get newComment => 'Nov komentar';

  @override
  String get comment => 'Komentar';

  @override
  String get editComment => 'Uredi komentar';

  @override
  String get editSubtask => 'Uredi podnalogo';

  @override
  String get estimateH => 'Ocena (h)';

  @override
  String get spentH => 'Porabljeno (h)';

  @override
  String get newGroceryItem => 'Nova postavka';

  @override
  String get newSubtask => 'Nova podnaloga';

  @override
  String get addTagsCommaSeparated => 'Dodaj oznake (ločene z vejico)';

  @override
  String get relation => 'Relacija';

  @override
  String get linkedTaskID => 'ID povezane naloge';

  @override
  String get export => 'Izvozi';

  @override
  String get remove => 'Odstrani';

  @override
  String get project => 'Projekt';

  @override
  String projectCreatedButDefaultsFailedToApply(Object error) {
    return 'Projekt je ustvarjen, vendar privzetih nastavitev ni bilo mogoče uporabiti: $error';
  }

  @override
  String get projectAttachmentsUploaded => 'Priponke projekta so naložene.';

  @override
  String uploadFailed(Object error) {
    return 'Nalaganje ni uspelo: $error';
  }

  @override
  String get attachmentContentMissing => 'Vsebina priponke manjka.';

  @override
  String downloadFailed(Object error) {
    return 'Prenos ni uspel: $error';
  }

  @override
  String filePickerFailed(Object error) {
    return 'Izbira datotek ni uspela: $error';
  }

  @override
  String attachmentPickerFailed(Object error) {
    return 'Izbira priponke ni uspela: $error';
  }

  @override
  String get attachmentUploadComplete => 'Nalaganje priponk je končano.';

  @override
  String attachmentUploadFailed(Object error) {
    return 'Nalaganje priponk ni uspelo: $error';
  }

  @override
  String get attachmentHasNoDownloadableContent =>
      'Priponka nima vsebine za prenos.';

  @override
  String attachmentExportFailed(Object error) {
    return 'Izvoz priponke ni uspel: $error';
  }

  @override
  String attachmentDeleteFailed(Object error) {
    return 'Brisanje priponke ni uspelo: $error';
  }

  @override
  String commentSaveFailed(Object error) {
    return 'Shranjevanje komentarja ni uspelo: $error';
  }

  @override
  String commentUpdateFailed(Object error) {
    return 'Posodobitev komentarja ni uspela: $error';
  }

  @override
  String commentDeleteFailed(Object error) {
    return 'Brisanje komentarja ni uspelo: $error';
  }

  @override
  String subtaskCreateFailed(Object error) {
    return 'Ustvarjanje podnaloge ni uspelo: $error';
  }

  @override
  String subtaskUpdateFailed(Object error) {
    return 'Posodobitev podnaloge ni uspela: $error';
  }

  @override
  String subtaskDeleteFailed(Object error) {
    return 'Brisanje podnaloge ni uspelo: $error';
  }

  @override
  String tagUpdateFailed(Object error) {
    return 'Posodobitev oznak ni uspela: $error';
  }

  @override
  String get theGroceryListTagIsReservedForGroceryTasks =>
      'Oznaka grocery-list je rezervirana za nakupovalne naloge.';

  @override
  String taskLinkFailed(Object error) {
    return 'Povezovanje naloge ni uspelo: $error';
  }

  @override
  String linkDeleteFailed(Object error) {
    return 'Brisanje povezave ni uspelo: $error';
  }

  @override
  String externalLinkFailed(Object error) {
    return 'Zunanja povezava ni uspela: $error';
  }

  @override
  String externalLinkDeleteFailed(Object error) {
    return 'Brisanje zunanje povezave ni uspelo: $error';
  }

  @override
  String taskStatusUpdateFailed(Object error) {
    return 'Posodobitev statusa ni uspela: $error';
  }

  @override
  String get serverRejectedTaskStatusUpdate =>
      'Strežnik je zavrnil posodobitev statusa naloge.';

  @override
  String taskNumber(Object id) {
    return 'Naloga #$id';
  }

  @override
  String get taskMarkedDone => 'Naloga je označena kot končana.';

  @override
  String get taskReopened => 'Naloga je ponovno odprta.';

  @override
  String get open => 'Odprto';

  @override
  String get reopenTask => 'Ponovno odpri nalogo';

  @override
  String get markAsDone => 'Označi kot končano';

  @override
  String get editTask2 => 'Uredi nalogo';

  @override
  String get createTask => 'Ustvari nalogo';

  @override
  String get editGroceryList => 'Uredi nakupovalni seznam';

  @override
  String get createGroceryList => 'Ustvari nakupovalni seznam';

  @override
  String get groceryListTitle => 'Naslov nakupovalnega seznama';

  @override
  String get noGroceryItemsYet => 'Postavk še ni.';

  @override
  String get addItemsNowTheyWillBeCreatedWhenYouSave =>
      'Dodajte postavke zdaj. Ustvarjene bodo ob shranjevanju.';

  @override
  String get titleIsRequired => 'Naslov je obvezen.';

  @override
  String get scoreMustBeAnInteger => 'Ocena mora biti celo število.';

  @override
  String serverRejectedAttachmentName(Object name) {
    return 'Strežnik je zavrnil priponko \"$name\".';
  }

  @override
  String get amountMustBeAValidNumber => 'Znesek mora biti veljavno število.';

  @override
  String get taskWasNotCreated => 'Naloga ni bila ustvarjena.';

  @override
  String get enterATitleBeforeOpeningAdditionalDetails =>
      'Pred odpiranjem dodatnih podrobnosti vnesite naslov.';

  @override
  String get taskMustBeSavedFirst => 'Nalogo je treba najprej shraniti.';

  @override
  String get saveTaskFirstToManageAttachmentsCommentsSubtasksTagsAndLinks =>
      'Najprej shranite nalogo, da boste lahko upravljali priponke, komentarje, podnaloge, oznake in povezave.';

  @override
  String get externalLinkTitleAndURLAreRequired =>
      'Naslov in URL zunanje povezave sta obvezna.';

  @override
  String get enterAValidLinkedTaskID => 'Vnesite veljaven ID povezane naloge.';

  @override
  String get invalidURL => 'Neveljaven URL.';

  @override
  String get couldNotOpenURLCopiedToClipboard =>
      'URL-ja ni bilo mogoče odpreti. Kopirano v odložišče.';

  @override
  String get attachmentsCommentsSubtasksTagsAndLinks =>
      'Priponke, komentarji, podnaloge, oznake in povezave';

  @override
  String get tapToExpandAdvancedTaskDetails =>
      'Tapnite za prikaz dodatnih podrobnosti naloge';

  @override
  String get advancedSectionsAreHidden => 'Napredni razdelki so skriti.';

  @override
  String get forNewTasksTheAppSavesFirstThenOpensAdvancedSections =>
      'Pri novih nalogah aplikacija najprej shrani, nato odpre napredne razdelke.';

  @override
  String get internalLinkTypesUnavailableForThisUserProject =>
      'Notranji tipi povezav niso na voljo za tega uporabnika/projekt.';

  @override
  String get noPermissionForInternalTaskLinksGetAllLinks =>
      'Ni dovoljenja za notranje povezave nalog (`getAllLinks`).';

  @override
  String get linkedTo => 'povezano z';

  @override
  String userNumber(Object id) {
    return 'Uporabnik #$id';
  }

  @override
  String estHSpentH(Object est, Object spent) {
    return 'Ocena ${est}h · Porabljeno ${spent}h';
  }

  @override
  String get eG1250 => 'npr. 12,50';

  @override
  String
  get macosFileAccessEntitlementMissingRebuildTheAppAfterEnablingUserSelectedFileReadEntitlement =>
      'Manjka macOS dovoljenje za dostop do datotek. Po omogočitvi dovoljenja za branje uporabniško izbranih datotek ponovno zgradite aplikacijo.';

  @override
  String tasks2(Object count) {
    return 'Naloge: $count';
  }

  @override
  String columns2(Object count) {
    return 'Stolpci: $count';
  }

  @override
  String get noColumnsConfiguredForThisSwimlaneUseStructureToAddColumns =>
      'Za to stezo ni nastavljenih stolpcev. Za dodajanje stolpcev uporabite Strukturo.';

  @override
  String
  get taskDragIsUnlockedMoveTasksCarefullyWhileScrollingOrTapLockToPreventAccidentalMoves =>
      'Vlečenje nalog je odklenjeno. Med drsenjem premikajte naloge previdno ali tapnite zaklep, da preprečite nenamerne premike.';

  @override
  String
  get taskDragIsLockedSoYouCanScrollSafelyTapUnlockInTheTopBarWhenYouWantToMoveTasks =>
      'Vlečenje nalog je zaklenjeno, da lahko varno drsite. Ko želite premikati naloge, zgoraj tapnite odklep.';

  @override
  String
  get dragAndDropTasksAcrossSwimlanesAndColumnsUseSearchForAdvancedQuerySyntax =>
      'Povlecite in spustite naloge med stezami in stolpci. Za napredno sintakso uporabite Iskanje.';

  @override
  String get currencyMustBeA3LetterCode => 'Valuta mora biti 3-črkovna koda.';

  @override
  String get budgetMustBeAPositiveNumber =>
      'Proračun mora biti pozitivno število.';

  @override
  String get useKanboardQuerySyntaxExampleStatusOpenAssigneeMeDueTomorrow =>
      'Uporabite sintakso poizvedb Kanboard. Primer: `status:open assignee:me due:tomorrow`';

  @override
  String get enterASearchQuery => 'Vnesite iskalno poizvedbo.';

  @override
  String boardStructure2(Object name) {
    return 'Struktura table · $name';
  }

  @override
  String get dragRowsToReorderChangesAreSavedImmediately =>
      'Vlecite vrstice za spremembo vrstnega reda. Spremembe se shranijo takoj.';

  @override
  String get noColumnsYetAddOne => 'Stolpcev še ni. Dodajte prvega.';

  @override
  String get noSwimlanesYetAddOne => 'Stez še ni. Dodajte prvo.';

  @override
  String positionLimit(Object position, Object limit) {
    return 'Položaj $position · Omejitev $limit';
  }

  @override
  String position(Object position) {
    return 'Položaj $position';
  }

  @override
  String get horizontalStructureOfTheBoard => 'Vodoravna struktura table';

  @override
  String get verticalWorkGrouping => 'Navpično razvrščanje dela';

  @override
  String get organizerAppName => 'Jivie';

  @override
  String get jivieAbout => 'O aplikaciji Jivie';

  @override
  String get jivieDescription =>
      'Brezplačen osebni in družinski organizator za opravila, načrte, nakupe in finance. Osebne podatke lahko ustvarjaš in urejaš na napravi brez računa ali povezave. Sinhronizacijo in deljenje vključiš po izbiri.';

  @override
  String get organizerToday => 'Danes';

  @override
  String get organizerPlans => 'Načrti';

  @override
  String get organizerShopping => 'Nakupi';

  @override
  String get organizerMore => 'Več';

  @override
  String get organizerCalendar => 'Koledar';

  @override
  String get organizerProjects => 'Projekti';

  @override
  String get organizerFinances => 'Finance';

  @override
  String get organizerHome => 'Dom';

  @override
  String get organizerSettings => 'Nastavitve';

  @override
  String get organizerLocalSpace => 'Osebni prostor';

  @override
  String get organizerLocalOnly => 'Shranjeno na tej napravi';

  @override
  String get organizerLocalDescription =>
      'Opravila in načrti so na tej napravi. Račun ni potreben.';

  @override
  String get organizerTodayIntro => 'Prostor za stvari, ki so danes pomembne.';

  @override
  String get organizerNextEvent => 'Naslednje na koledarju';

  @override
  String get organizerNoEvents => 'Koledar je še prazen.';

  @override
  String get organizerNoEventsDescription =>
      'Dodaj dogodek in imej naslednji korak na očeh.';

  @override
  String get organizerNextTasks => 'Naslednji koraki';

  @override
  String get organizerNoTasks => 'Začni z enim opravilom.';

  @override
  String get organizerNoTasksDescription =>
      'Majhna opravila, večji načrti. Vse na svojem mestu.';

  @override
  String get organizerAddTask => 'Dodaj opravilo';

  @override
  String get organizerEditTask => 'Uredi opravilo';

  @override
  String get organizerAddEvent => 'Dodaj dogodek';

  @override
  String get organizerEditEvent => 'Uredi dogodek';

  @override
  String get organizerAddProject => 'Nov projekt';

  @override
  String get organizerEditProject => 'Uredi projekt';

  @override
  String get organizerNoProjects => 'Kaj želiš načrtovati?';

  @override
  String get organizerNoProjectsDescription =>
      'Ustvari projekt za izlet, prenovo ali vsakdanja opravila.';

  @override
  String get organizerShoppingShortcut => 'Na nakupovalni seznam';

  @override
  String get organizerShoppingIntro =>
      'Zapiši, kar potrebuješ. Odkljukaj, ko je v košarici.';

  @override
  String get organizerAddList => 'Nov seznam';

  @override
  String get organizerEditList => 'Uredi seznam';

  @override
  String get organizerNoLists => 'Seznam za naslednji nakup.';

  @override
  String get organizerNoListsDescription =>
      'Ustvari seznam in dodaj prvo stvar, ki jo potrebuješ.';

  @override
  String get organizerAddItem => 'Dodaj izdelek';

  @override
  String get organizerEditItem => 'Uredi izdelek';

  @override
  String get organizerItemHint => 'Kaj potrebuješ?';

  @override
  String get organizerQuantity => 'Količina';

  @override
  String get organizerBought => 'Kupljeno';

  @override
  String get organizerEmptyList => 'Na seznamu še ni izdelkov.';

  @override
  String get organizerTasks => 'Opravila';

  @override
  String get organizerAllTasks => 'Vsa opravila';

  @override
  String get organizerNoProject => 'Brez projekta';

  @override
  String get organizerCompleted => 'Opravljeno';

  @override
  String get organizerTitle => 'Naslov';

  @override
  String get organizerNotes => 'Opombe';

  @override
  String get organizerDescription => 'Opis';

  @override
  String get organizerRequired => 'Vpiši naslov.';

  @override
  String get organizerSaveError =>
      'Spremembe ni bilo mogoče shraniti. Poskusi znova.';

  @override
  String get organizerLoadError => 'Lokalnih podatkov ni bilo mogoče odpreti.';

  @override
  String get organizerRetry => 'Poskusi znova';

  @override
  String get organizerDate => 'Datum';

  @override
  String get organizerTime => 'Ura';

  @override
  String get organizerNoDate => 'Brez roka';

  @override
  String get organizerRemoveDate => 'Odstrani datum';

  @override
  String get organizerUpcoming => 'Prihajajoče';

  @override
  String get organizerCalendarIntro => 'Dogodki in roki opravil na enem mestu.';

  @override
  String get organizerFinanceIntro =>
      'Osebni zapisi prihodkov in odhodkov na tej napravi.';

  @override
  String get organizerAddFinance => 'Dodaj zapis';

  @override
  String get organizerEditFinance => 'Uredi zapis';

  @override
  String get organizerNoFinance => 'Tvoj pregled se začne s prvim zapisom.';

  @override
  String get organizerIncome => 'Prihodek';

  @override
  String get organizerExpense => 'Odhodek';

  @override
  String get organizerCurrency => 'Valuta';

  @override
  String get organizerInvalidMoney =>
      'Vpiši pozitiven znesek z največ dvema decimalkama.';

  @override
  String get organizerBalance => 'Razlika prihodkov in odhodkov';

  @override
  String get organizerConnection => 'Obstoječi Kanboard';

  @override
  String get organizerConnectionDescription =>
      'Tvoji obstoječi projekti so še na strežniku Kanboard. Odpri jih s povezavo računa. Lokalni organizator jih še ne uvaža ali sinhronizira.';

  @override
  String get organizerConnect => 'Poveži račun';

  @override
  String get organizerOpenKanboard => 'Odpri Kanboard';

  @override
  String get organizerBackup => 'Varnostna kopija';

  @override
  String get organizerBackupDescription =>
      'Izvozi lokalne zapise v datoteko JSON ali jih obnovi iz kopije. Datoteka ni šifrirana; shrani jo na varno mesto.';

  @override
  String get organizerExport => 'Izvozi kopijo';

  @override
  String get organizerImport => 'Obnovi iz kopije';

  @override
  String get organizerRestoreWarning =>
      'Obnova doda zapise iz kopije. Če kopija vsebuje že obstoječe zapise, se celoten uvoz zavrne. Najprej izvozi trenutno kopijo.';

  @override
  String get organizerRestoreConfirm => 'Obnovi';

  @override
  String get organizerRestored => 'Lokalni podatki so obnovljeni.';

  @override
  String get organizerReminders => 'Opomniki';

  @override
  String get organizerNoReminders => 'Ni novih opomnikov.';

  @override
  String get organizerRemindersDescription =>
      'Opomniki za roke opravil se pokažejo ob odprtju aplikacije.';

  @override
  String get organizerHomeIntro =>
      'Domače načrte vodi s projekti in opravili v osebnem prostoru.';

  @override
  String get organizerBackToday => 'Nazaj na Danes';

  @override
  String get organizerDeleteConfirm => 'Izbrišem ta zapis?';

  @override
  String get organizerDeleteProjectNote =>
      'Opravila, dogodki in finančni zapisi ostanejo brez projekta.';

  @override
  String organizerProjectProgress(int done, int total) {
    return '$done od $total opravljenih';
  }

  @override
  String organizerShoppingCount(int count) {
    return '$count na seznamih';
  }

  @override
  String organizerTasksCount(int count) {
    return '$count opravil';
  }

  @override
  String get organizerNoMatchingTasks => 'V tem projektu še ni opravil.';

  @override
  String get organizerPersonal => 'Lokalno · osebno';

  @override
  String get organizerSystemLanguage => 'Jezik naprave';

  @override
  String get organizerRead => 'Prebrano';

  @override
  String get organizerWithoutDate => 'Brez roka';

  @override
  String get organizerOverdue => 'Zapadlo';

  @override
  String get organizerHomeProjects => 'Domači projekti';

  @override
  String get organizerProjectArea => 'Področje';

  @override
  String get organizerPersonalArea => 'Osebno';

  @override
  String get organizerHomeArea => 'Dom';

  @override
  String get organizerConflict =>
      'Zapis se je vmes spremenil ali kopija vsebuje obstoječe zapise. Odpri zadnjo različico zapisa; uvoz nasprotujoče kopije je zavrnjen.';

  @override
  String get organizerInvalidData =>
      'Podatki niso veljavni ali oblika kopije ni podprta.';

  @override
  String get secureStorageUnavailable =>
      'Varna shramba ni na voljo. Poverilnice niso bile shranjene; preverite nastavitve varne shrambe naprave.';

  @override
  String get credentialsSharingDisabled =>
      'Gesel in osebnih API ključev ne delimo. Projektna povabila bodo omogočena, ko bo pripravljen varen postopek.';

  @override
  String get personalTokenHint =>
      'Uporabite svoje uporabniško ime in osebni API ključ. Globalni ključ jsonrpc ni podprt.';

  @override
  String get secureConnectionRequired =>
      'Uporabite HTTPS. HTTP je dovoljen samo za izrecno lokalno razvojno povezavo.';

  @override
  String get localDevelopmentConnection =>
      'Lokalna razvojna povezava (HTTP na tem računalniku)';

  @override
  String get aiSessionChanged =>
      'Račun se je spremenil. Ta pogovor pripada prejšnji prijavi; odpri AI pomoč ponovno iz svojega projekta.';

  @override
  String get connectionFailed =>
      'Povezava ni uspela. Preverite naslov strežnika, uporabniško ime in geslo ali osebni API ključ.';

  @override
  String get sharingAccount => 'Račun in deljenje';

  @override
  String get sharingIntro =>
      'Osebni podatki ostanejo na napravi. Poveži račun, ko želiš uporabljati skupne sezname in projekte.';

  @override
  String get sharingPersonal => 'Osebno';

  @override
  String get sharingShared => 'Deljeno';

  @override
  String get sharingConnect => 'Poveži za deljenje';

  @override
  String get sharingLogin => 'Prijava';

  @override
  String get sharingLoginAction => 'Prijavi se';

  @override
  String get sharingHaveInvite => 'Imam povabilo';

  @override
  String get sharingInvitation => 'Povabilo';

  @override
  String get sharingInvitationCode => 'Koda povabila';

  @override
  String get sharingInvitationHint =>
      'Prilepi kodo, ki ti jo je poslala oseba, s katero želiš sodelovati.';

  @override
  String get sharingPreviewInvite => 'Preveri povabilo';

  @override
  String get sharingAcceptInvite => 'Sprejmi povabilo';

  @override
  String get sharingRegister => 'Ustvari račun s povabilom';

  @override
  String get sharingRegisterAction => 'Ustvari račun in sprejmi';

  @override
  String get sharingDisplayName => 'Ime za prikaz';

  @override
  String get sharingEmail => 'E-pošta';

  @override
  String get sharingConfirmPassword => 'Ponovi geslo';

  @override
  String get sharingPasswordMismatch => 'Gesli se ne ujemata.';

  @override
  String get sharingTwoFactorCode => 'Koda dvostopenjske prijave';

  @override
  String get sharingDeviceName => 'Ime te naprave';

  @override
  String get sharingDeviceSession => 'Seja te naprave';

  @override
  String get sharingSpaces => 'Skupni prostori';

  @override
  String get sharingCreateSpace => 'Nov skupni prostor';

  @override
  String get sharingSpaceName => 'Ime prostora';

  @override
  String get sharingScopeType => 'Vrsta prostora';

  @override
  String get sharingHousehold => 'Gospodinjstvo';

  @override
  String get sharingProject => 'Projekt';

  @override
  String get sharingScopeDescription =>
      'V tej različici deliš sezname, projekte in opravila. Skupne finance sledijo v finančni prenovi.';

  @override
  String get sharingNoSpaces => 'Še ni skupnih prostorov.';

  @override
  String get sharingChooseSpace => 'Izberi skupni prostor';

  @override
  String get sharingMembers => 'Člani';

  @override
  String get sharingOwner => 'Lastnik';

  @override
  String get sharingEditor => 'Ureja';

  @override
  String get sharingViewer => 'Bere';

  @override
  String get sharingRole => 'Vloga';

  @override
  String get sharingInvitePerson => 'Povabi osebo';

  @override
  String get sharingCreateInvite => 'Ustvari povabilo';

  @override
  String get sharingInvitations => 'Povabila';

  @override
  String get sharingCopyInvite => 'Kopiraj kodo';

  @override
  String get sharingInviteCopied => 'Koda povabila je kopirana.';

  @override
  String get sharingInviteCodeOnce =>
      'Kodo shrani ali pošlji prejemniku zdaj. Pozneje je ne bo mogoče ponovno prikazati.';

  @override
  String get sharingRevokeInvite => 'Prekliči povabilo';

  @override
  String get sharingRemoveMember => 'Odstrani člana';

  @override
  String get sharingRemoveMemberConfirm =>
      'Član po preklicu ne bo več mogel dostopati do tega prostora. Že prenesenih kopij ni mogoče izbrisati na daljavo.';

  @override
  String get sharingSignOutDescription =>
      'Osebni podatki ostanejo na napravi. Preveri čakajoče skupne spremembe pred odjavo.';

  @override
  String get sharingSyncNow => 'Uskladi zdaj';

  @override
  String get sharingSynced => 'Usklajeno';

  @override
  String get sharingSyncing => 'Usklajujem …';

  @override
  String get sharingPending => 'Čaka na uskladitev';

  @override
  String get sharingOffline => 'Povezava ni na voljo';

  @override
  String get sharingSyncFailed =>
      'Uskladitev ni uspela. Lokalne spremembe so ohranjene.';

  @override
  String get sharingConflicts => 'Spremembe potrebujejo odločitev';

  @override
  String get sharingConflictDescription =>
      'Isti zapis se je spremenil tudi drugje. Primerjaj obe različici in izberi, katero želiš obdržati.';

  @override
  String get sharingLocalVersion => 'Na tej napravi';

  @override
  String get sharingRemoteVersion => 'Na strežniku';

  @override
  String get sharingKeepLocal => 'Obdrži mojo različico';

  @override
  String get sharingKeepRemote => 'Obdrži strežniško različico';

  @override
  String get sharingAccessRevoked =>
      'Dostop je preklican. Čakajoče spremembe niso bile poslane.';

  @override
  String get sharingUnsupported =>
      'Ta strežnik še ne podpira potrebnih funkcij deljenja.';

  @override
  String get sharingOperationFailed =>
      'Dejanje ni uspelo. Preveri povezavo in poskusi znova.';

  @override
  String get sharingInvalidInvite =>
      'Povabilo ni veljavno, je poteklo ali je že porabljeno.';

  @override
  String get sharingSessionExpired =>
      'Seja je potekla. Ponovno se prijavi; osebni podatki ostanejo na napravi.';

  @override
  String get sharingPermissionDenied => 'Za to dejanje nimaš dovoljenja.';

  @override
  String get sharingNoSharedLists => 'V tem prostoru še ni skupnega seznama.';

  @override
  String get sharingNoSharedListsDescription =>
      'Ustvari seznam za sodelovanje. Osebni seznami se ne delijo samodejno.';

  @override
  String get sharingCreateSharedList => 'Nov skupni seznam';

  @override
  String get sharingReadOnly => 'Samo za branje';

  @override
  String get sharingQuietShopping =>
      'Spremembe nakupovalnega seznama so tihe; ne pošiljajo e-pošte.';

  @override
  String get sharingShareList => 'Deli ta seznam';

  @override
  String get sharingShareProject => 'Deli projekt in opravila';

  @override
  String get sharingShareConfirm =>
      'V izbranem prostoru bo nastala skupna kopija. Osebna vsebina in finance se ne delijo samodejno.';

  @override
  String get sharingNoMembers => 'Ni podatkov o članih.';

  @override
  String get sharingNoInvitations => 'Ni aktivnih povabil.';

  @override
  String get sharingGoToAccount => 'Odpri račun in deljenje';

  @override
  String get sharingConnectBeforeShared =>
      'Za skupne sezname poveži račun ali sprejmi povabilo.';

  @override
  String get sharingSaveBeforeSync =>
      'Sprememba se najprej shrani na napravi, nato uskladi s prostorom.';

  @override
  String get sharingMember => 'Član';

  @override
  String get sharingRequired => 'Izpolni to polje.';

  @override
  String get sharingSaveDrafts => 'Shrani moje neusklajene spremembe';

  @override
  String get sharingSaveDraftsDescription =>
      'Izvoz vsebuje tvoje čakajoče skupne spremembe, brez poverilnic. Datoteka JSON ni šifrirana.';

  @override
  String get sharingCopyAction => 'Ustvari skupno kopijo';

  @override
  String get sharingCopyDone =>
      'Skupna kopija je ustvarjena. Osebni izvirnik ostane nespremenjen.';

  @override
  String get sharingCopyDescription =>
      'V tej različici se skopira samo ta seznam oziroma projekt z njegovimi opravili. Finance in dogodki se pri tem ne prenesejo. Poznejše spremembe osebnega izvirnika se ne prenašajo v skupno kopijo.';

  @override
  String get sharingLoginNeedsOtp =>
      'Vpiši kodo iz aplikacije za dvostopenjsko prijavo.';

  @override
  String get sharingInvalidCredentials =>
      'Prijava ni uspela. Preveri uporabniško ime, geslo in morebitno dvostopenjsko kodo.';

  @override
  String get sharingSelectDestination => 'Kam želiš ustvariti skupno kopijo?';

  @override
  String get sharingPendingSignOut =>
      'Skupni pogled bo po odjavi skrit. Osebni podatki ostanejo. Neusklajene skupne spremembe se ne pošljejo pod drugim računom; pred odjavo jih lahko izvoziš.';

  @override
  String get sharingNoPending => 'Ni čakajočih sprememb';

  @override
  String get sharingResumeBlocked => 'Nadaljuj usklajevanje mojih sprememb';

  @override
  String get sharingResumeBlockedDescription =>
      'Dostop je ponovno dovoljen. Prej zadržane spremembe se pošljejo šele, ko izrecno nadaljuješ usklajevanje.';

  @override
  String get sharingOfflineSignOut =>
      'Odjava na napravi je uspela. Preklica seje na strežniku ni bilo mogoče potrditi; seja bo tam veljavna do preklica ali poteka.';

  @override
  String get sharingExpires => 'Velja do';

  @override
  String get sharingAccepted => 'Sprejeto';

  @override
  String get sharingRevoked => 'Preklicano';

  @override
  String get sharingExpired => 'Poteklo';

  @override
  String get sharingSessionEnds => 'Seja velja do';

  @override
  String get sharingSharedTasks => 'Skupna opravila';

  @override
  String get sharingConflictsButton => 'Preglej spremembe';

  @override
  String get sharingDeletedVersion =>
      'Te različice ni oziroma je zapis izbrisan.';

  @override
  String get sharingNetworkError =>
      'Povezava ni na voljo. Neusklajene spremembe ostanejo na napravi; poskusi uskladiti znova.';

  @override
  String get sharingSessionRevoked =>
      'Seja naprave je preklicana. Ponovno se prijavi; neusklajene spremembe se ne pošljejo pod drugim računom.';

  @override
  String get sharingStorageUnavailable =>
      'Trajna shramba za skupne podatke ni na voljo. Dejanje ni bilo potrjeno; preveri shrambo naprave in poskusi znova.';

  @override
  String get sharingInvalidServer =>
      'Preveri veljaven naslov strežnika. Za običajno povezavo uporabi HTTPS.';

  @override
  String get sharingRateLimited =>
      'Preveč poskusov. Počakaj nekaj časa, nato poskusi znova.';

  @override
  String get sharingUnsupportedAuth =>
      'Ta način prijave ni podprt. Za deljenje uporabi podprt lokalni uporabniški račun na strežniku.';

  @override
  String get sharingIncompatibleServer =>
      'Različica strežnika ni združljiva z deljenjem v tej aplikaciji. Preveri strežniški vtičnik; lokalni podatki ostanejo na napravi.';

  @override
  String get sharingValidationError =>
      'Podatki niso veljavni. Preveri vnos in poskusi znova.';

  @override
  String get sharingRegistrationPasswordHint =>
      'Novo geslo potrebuje vsaj 12 znakov (največ 72 bajtov).';

  @override
  String get sharingBlockedDescription =>
      'Te spremembe so zadržane zaradi preklicanega dostopa. Lahko jih izvoziš. Po ponovni pridobitvi dostopa zahtevajo izrecno nadaljevanje.';

  @override
  String get sharingAdvancedLogin => 'Dodatne možnosti prijave';

  @override
  String get sharingMoreDetails => 'Podrobnosti zapisa';

  @override
  String get sharingNoConflicts => 'Ni sprememb, ki bi potrebovale odločitev.';

  @override
  String get sharingRefreshMembers => 'Osveži člane';

  @override
  String get sharingDeletedConflict =>
      'Zapis je bil na strežniku izbrisan. Svojo različico lahko shraniš v izvoz; sprejem strežniškega stanja ga ne obnovi.';

  @override
  String get sharingRelatedConflict =>
      'Povezani zapisi so se spremenili. Najprej shrani svojo različico, sprejmi strežniško stanje in preglej povezane zapise. Nato lahko izrecno ustvariš kopijo ali znova izbereš izbris.';

  @override
  String get sharingStaleEditor =>
      'Ta zapis se je med urejanjem spremenil. Zapri urejevalnik in odpri zadnjo različico; svoje besedilo lahko prej skopiraš.';

  @override
  String get sharingInvalidResponse =>
      'Odgovora strežnika ni mogoče varno uporabiti. Preveri združljivost vtičnika. Lokalne spremembe ostanejo na napravi.';

  @override
  String get sharingRequestMismatch =>
      'Strežnik je zavrnil ponovitev zahteve z drugačno vsebino. Shrani svoje spremembe v izvoz in preveri stanje; zahteve ne pošiljaj znova na slepo.';

  @override
  String get planningAssignees => 'Izvajalci';

  @override
  String get planningUnassigned => 'Še ni dodeljeno';

  @override
  String get planningFormerMember => 'Prejšnji član';

  @override
  String get planningSchedule => 'Načrtovani termin';

  @override
  String get planningStart => 'Začetek';

  @override
  String get planningEnd => 'Konec';

  @override
  String get planningDue => 'Rok';

  @override
  String get planningCreatedBy => 'Ustvaril/a';

  @override
  String get planningUpdatedBy => 'Nazadnje spremenil/a';

  @override
  String get planningInvalidSchedule => 'Konec ne sme biti pred začetkom.';

  @override
  String get planningSharedToday => 'Danes v skupnem prostoru';

  @override
  String get planningTimeline => 'Časovnica';

  @override
  String get planningNoAgenda => 'Za ta dan ni skupnih terminov.';

  @override
  String get planningNoTimeline =>
      'Dodaj termin opravilu ali projektu za pregled časovnice.';

  @override
  String get planningAllPeople => 'Vsi izvajalci';

  @override
  String get planningNoTime => 'Brez termina';

  @override
  String get planningPreviousDay => 'Prejšnji dan';

  @override
  String get planningNextDay => 'Naslednji dan';

  @override
  String get financeMinorUnits => 'najmanjših enot';

  @override
  String get financeUnspecifiedPerson => 'Ni določeno';

  @override
  String get financeUnavailableAccount => 'Račun ni na voljo';

  @override
  String get financePosted => 'Knjiženo';

  @override
  String get financePlanned => 'Načrtovano';

  @override
  String get financeAddTransfer => 'Dodaj prenos';

  @override
  String get financeTransfer => 'Prenos';

  @override
  String get financeInternalTransfer => 'Prenos med računi';

  @override
  String get financeAddAccount => 'Dodaj račun';

  @override
  String get financeNoAccounts => 'Ustvari prvi finančni račun v tem prostoru.';

  @override
  String get financeAccounts => 'Finančni računi';

  @override
  String get financeAccount => 'Finančni račun';

  @override
  String get financeAllAccounts => 'Vsi računi';

  @override
  String get financePayerRecipient => 'Plačnik / prejemnik';

  @override
  String get financeEnteredBy => 'Vnesel/a';

  @override
  String get financeStatus => 'Stanje vnosa';

  @override
  String get financeAllStatuses => 'Vsa stanja';

  @override
  String get financeNoMatchingEntries => 'Za te filtre ni vnosov.';

  @override
  String get financeCategory => 'Kategorija';

  @override
  String get financePayer => 'Plačnik';

  @override
  String get financeRecipient => 'Prejemnik';

  @override
  String get financeJointAccount => 'Skupni račun';

  @override
  String get financeAudit => 'Sled sprememb';

  @override
  String get financeScopeTotals => 'Celoten finančni prostor';

  @override
  String get financeTransfersExcluded =>
      'Seštevki vključujejo knjižene vnose. Prenosi med računi niso nov prihodek ali strošek. Filtri spodaj omejijo tabelo.';

  @override
  String get financeSharedAccountsDescription =>
      'Ti računi so deljeni v tem prostoru. Zasebni lokalni računi se ne povežejo samodejno.';

  @override
  String get financeDate => 'Datum in čas';

  @override
  String get planningAllProjects => 'Vsi projekti';

  @override
  String get inboxDeviceReminder =>
      'Čas je za tvoj opomnik. Odpri aplikacijo za podrobnosti.';

  @override
  String get inboxDeviceEventReminder =>
      'Približuje se tvoj dogodek. Odpri aplikacijo za podrobnosti.';

  @override
  String get inboxTitle => 'Obvestila';

  @override
  String get inboxForMe => 'Zame';

  @override
  String get inboxInSharedSpace => 'V skupnem prostoru';

  @override
  String get inboxAll => 'Vsa';

  @override
  String get inboxRead => 'Prebrano';

  @override
  String get inboxMarkRead => 'Označi kot prebrano';

  @override
  String get inboxMarkUnread => 'Označi kot neprebrano';

  @override
  String get inboxEmpty => 'Za ta pogled še ni obvestil.';

  @override
  String get inboxSettings => 'Nastavitve obvestil';

  @override
  String get inboxDeviceSettings => 'Opomniki na tej napravi';

  @override
  String get inboxDevicePrivacy =>
      'Sistemsko obvestilo pokaže samo splošen opomnik. Podrobnosti odpreš v aplikaciji. Vklop velja za osebne in dostopne skupne opomnike na tej napravi.';

  @override
  String get inboxDeviceEnable => 'Vključi sistemske opomnike';

  @override
  String get inboxSound => 'Zvok';

  @override
  String get inboxDeviceUnsupported =>
      'Časovna sistemska obvestila v tem okolju niso podprta. Center obvestil v aplikaciji ostane na voljo.';

  @override
  String get inboxDeviceDenied =>
      'Sistemska dovoljenja niso omogočena. Spremeni jih v nastavitvah naprave in se vrni v aplikacijo.';

  @override
  String get inboxDeviceGranted => 'Dovoljenje naprave je omogočeno.';

  @override
  String get inboxDeviceUnknown =>
      'Stanje sistemskega dovoljenja še ni potrjeno.';

  @override
  String get inboxDeviceError =>
      'Sistemskih opomnikov ni bilo mogoče pripraviti. Preveri dovoljenja naprave in poskusi znova; podatki ostanejo shranjeni.';

  @override
  String get inboxDeviceInexact =>
      'Android lahko obvestilo dostavi z zamikom, zlasti med varčevanjem z energijo.';

  @override
  String inboxDeviceLimit(int count) {
    return '$count poznejših opomnikov čaka. Razporedi se najbližjih 60; seznam se dopolni ob odprtju in osvežitvi aplikacije.';
  }

  @override
  String inboxDeviceScheduled(int count) {
    return 'Razporejenih opomnikov: $count.';
  }

  @override
  String get inboxDeleted => 'Izvorni zapis je izbrisan.';

  @override
  String get inboxNeedsConnection =>
      'Za preverjanje dostopa in odprtje tega obvestila potrebuješ povezavo.';

  @override
  String get inboxWrongAccount =>
      'To obvestilo pripada drugemu računu. Prijavi se s pravim računom.';

  @override
  String get inboxOfflineView =>
      'Brez povezave · zadnja dostopna kopija. Trenutnih strežniških pravic ni mogoče preveriti.';

  @override
  String inboxPersonalReminders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Opomniki za $count opravil',
      few: 'Opomniki za $count opravila',
      two: 'Opomnika za $count opravili',
      one: 'Opomnik za $count opravilo',
    );
    return '$_temp0';
  }

  @override
  String inboxTasksAssigned(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dodeljenih ti je $count opravil',
      few: 'Dodeljena so ti $count opravila',
      two: 'Dodeljeni sta ti $count opravili',
      one: 'Dodeljeno ti je $count opravilo',
    );
    return '$_temp0';
  }

  @override
  String inboxTaskCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dodanih je $count opravil',
      few: 'Dodana so $count opravila',
      two: 'Dodani sta $count opravili',
      one: 'Dodano je $count opravilo',
    );
    return '$_temp0';
  }

  @override
  String get inboxEventCreated => 'Dodan je dogodek';

  @override
  String get inboxEventAssigned => 'Dodeljen ti je dogodek';

  @override
  String get inboxShoppingListCreated => 'Dodan je nakupovalni seznam';

  @override
  String inboxShoppingItemsCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dodanih je $count izdelkov',
      few: 'Dodani so $count izdelki',
      two: 'Dodana sta $count izdelka',
      one: 'Dodan je $count izdelek',
    );
    return '$_temp0';
  }

  @override
  String get inboxMemberJoined => 'Pridružil se je član';

  @override
  String get inboxRecordUpdated => 'Zapis je spremenjen';

  @override
  String get inboxRecordDeleted => 'Zapis je izbrisan';

  @override
  String get inboxTaskCompleted => 'Opravilo je zaključeno';

  @override
  String get inboxShoppingChecked => 'Izdelek je označen kot kupljen';

  @override
  String get inboxFinanceChanged => 'Sprememba v skupnih financah';

  @override
  String get inboxProjectChanged => 'Sprememba projekta';

  @override
  String get inboxReminderDue => 'Čas je za opomnik';

  @override
  String get inboxOpenToView => 'Odpri za podrobnosti';

  @override
  String get inboxSharedPreferencesUnavailable =>
      'Ta strežnik še ne podpira nastavitev obvestil.';

  @override
  String get planningFullDay => 'Celoten skupni dan';

  @override
  String get sharingView => 'Pogled';

  @override
  String get financeEditAccount => 'Uredi račun';

  @override
  String get financeOpeningBalance => 'Začetno stanje';

  @override
  String get financeDeleteAccountDescription =>
      'Račun lahko izbrišeš, ko nima povezanih vnosov ali prenosov.';

  @override
  String get financeEditEntry => 'Uredi finančni vnos';

  @override
  String get financeAccountCurrencyAmount => 'Znesek v valuti izbranega računa';

  @override
  String get financeEditTransfer => 'Uredi prenos';

  @override
  String get financeTransferDescription =>
      'Prenos poteka med deljenima računoma iste valute v tem prostoru. Ne šteje kot prihodek ali odhodek.';

  @override
  String get financeFromAccount => 'Iz računa';

  @override
  String get financeToAccount => 'Na račun';

  @override
  String get financeInvalidTransfer =>
      'Izberi dva različna računa iste valute.';

  @override
  String get financeNoAudit => 'Še ni finančne sledi.';

  @override
  String get financeRevision => 'Različica';

  @override
  String get financeBefore => 'Pred spremembo';

  @override
  String get financeAfter => 'Po spremembi';

  @override
  String get financeEnable => 'Omogoči skupne finance';

  @override
  String get financeDisabled => 'Finance v tem prostoru še niso omogočene.';

  @override
  String get financeNoAccess =>
      'Za finance v tem prostoru nimaš dostopa. Lastnik lahko dodeli pravico za ogled ali urejanje.';

  @override
  String get financePermissions => 'Dostop do financ';

  @override
  String get financeGrantNone => 'Brez dostopa';

  @override
  String get financeGrantRead => 'Ogled';

  @override
  String get financeGrantWrite => 'Urejanje';

  @override
  String get financeLoadingSnapshot => 'Pripravljamo celoten finančni pregled.';

  @override
  String get financeUnsupported => 'Ta strežnik še ne podpira skupnih financ.';

  @override
  String get financeDisable => 'Onemogoči finance';

  @override
  String get financeDisableDescription =>
      'Finance bodo skrite za člane. Podatki in moje neusklajene spremembe se ohranijo.';

  @override
  String get financePending => 'Finančne spremembe čakajo na uskladitev.';

  @override
  String get financeBlocked =>
      'Finančne spremembe so zadržane. Shrani kopijo, preden razrešiš dostop.';

  @override
  String get financeConflicts => 'Sporne finančne spremembe';

  @override
  String get inboxPreferencesDescription =>
      'Nastavitve veljajo za izbrani skupni prostor in vrsto obvestila. Sistemski opomniki na tej napravi so ločena nastavitev.';

  @override
  String get inboxChannelInApp => 'V centru obvestil';

  @override
  String get inboxChannelSound => 'Zvok opomnikov';

  @override
  String get inboxChannelPush => 'Oddaljena sistemska obvestila';

  @override
  String get inboxChannelEmail => 'E-pošta';

  @override
  String get inboxChannelUnavailable => 'Kanal na tem strežniku ni na voljo.';

  @override
  String get inboxPreferencesUnsupported =>
      'Ta strežnik še ne podpira nastavitev obvestil.';

  @override
  String get inboxCategoryAssignments => 'Dodelitve';

  @override
  String get inboxCategoryTasks => 'Opravila in načrti';

  @override
  String get inboxCategoryShopping => 'Nakupi';

  @override
  String get inboxCategoryMembers => 'Člani';

  @override
  String get inboxCategoryReminders => 'Opomniki';

  @override
  String get inboxCategoryFinance => 'Finance';

  @override
  String get financeHolder => 'Imetnik računa';

  @override
  String get inboxScope => 'Skupni prostor';

  @override
  String get inboxCategoryEvents => 'Dogodki';

  @override
  String get inboxJoinedScope => 'Pridružil/a si se prostoru';

  @override
  String get financeUnsupportedCurrency =>
      'Urejanje te valute še ni podprto. Znesek ostane ohranjen v najmanjših denarnih enotah.';

  @override
  String get financeTotalBalance => 'Skupno stanje';

  @override
  String get remotePushTitle => 'Oddaljena obvestila na tej napravi';

  @override
  String get remotePushPrivacy =>
      'Obvestilo pokaže splošno besedilo. Vsebina se odpre šele po preverjanju računa in pravic.';

  @override
  String get remotePushEnable => 'Omogoči oddaljena obvestila';

  @override
  String get remotePushUnsupported =>
      'Oddaljena obvestila so pripravljena za Android in iPhone. Na tej platformi uporabljaj center obvestil.';

  @override
  String get remotePushUnconfigured =>
      'Ta različica še nima konfiguracije Firebase. Center obvestil in lokalni opomniki ostajajo na voljo.';

  @override
  String get remotePushInvalidConfiguration =>
      'Konfiguracija obvestil ni veljavna za to aplikacijo. Potrebna je popravljena namestitev.';

  @override
  String get remotePushNeedsAccount =>
      'Za oddaljena obvestila se prijavi v svoj račun. Osebna uporaba ostaja brez računa.';

  @override
  String get remotePushDisabled =>
      'Oddaljena obvestila na tej napravi so izključena.';

  @override
  String get remotePushPreparing =>
      'Pripravljam dovoljenje in registracijo naprave …';

  @override
  String get remotePushDenied =>
      'Sistem ne dovoljuje obvestil. Omogoči jih v nastavitvah naprave in poskusi znova.';

  @override
  String get remotePushWaitingApns =>
      'Čakam potrditev Apple za to napravo. Preveri povezavo in omogočeno podpisovanje za obvestila.';

  @override
  String get remotePushRegistered =>
      'Naprava je registrirana. Vrste obvestil izbereš za vsak skupni prostor.';

  @override
  String get remotePushOffline =>
      'Registracija čaka na povezavo. Spremembe v aplikaciji ostajajo shranjene.';

  @override
  String get remotePushServerUnavailable =>
      'Strežnik nima združljive konfiguracije oddaljenih obvestil. Center obvestil ostaja na voljo.';

  @override
  String get remotePushProjectMismatch =>
      'Aplikacija in strežnik uporabljata različna projekta Firebase. Naprava ni registrirana.';

  @override
  String get remotePushCleanupRequired =>
      'Prejšnje registracije naprave še ni bilo mogoče odstraniti. Poskusi znova pred omogočanjem drugega računa.';

  @override
  String get remotePushError =>
      'Oddaljenih obvestil ni bilo mogoče pripraviti. Poskusi znova; center obvestil ostaja na voljo.';

  @override
  String get remotePushRetry => 'Preveri obvestila znova';

  @override
  String get remotePushLoginForOpen =>
      'Prijavi se v račun, ki je prejel to obvestilo.';

  @override
  String get remotePushDeviceUnavailable =>
      'Najprej omogoči in registriraj oddaljena obvestila na tej napravi.';

  @override
  String get setupTitle => 'Kako želiš začeti?';

  @override
  String get setupIntro =>
      'Izberi, kako želiš uporabljati Jivie. Svoj način lahko kasneje spremeniš v nastavitvah.';

  @override
  String get setupHint =>
      'Osebni prostor že deluje brez računa. Po želji poveži svoje naprave ali ustvari skupni dom.';

  @override
  String get setupChoose => 'Izberi svoj začetek';

  @override
  String get setupDeviceOnly => 'Samo na tej napravi';

  @override
  String get setupDeviceOnlyDescription =>
      'Brez računa in strežnika. Podatke varuj z varnostno kopijo.';

  @override
  String get setupPrivateDevices => 'Poveži moje naprave';

  @override
  String get setupPrivateDevicesDescription =>
      'Zasebna sinhronizacija mojih podatkov. Prenos vključiš posebej po prijavi.';

  @override
  String get setupHousehold => 'Skupni dom';

  @override
  String get setupHouseholdDescription =>
      'Ustvari dom in povabi drugo osebo. Osebni prostor ostane ločen.';

  @override
  String get setupOpen => 'Začetek uporabe';

  @override
  String get inviteOpenTitle => 'Odpri povabilo';

  @override
  String get inviteOpenWarning =>
      'Preveri naslov strežnika. Povabilo se ne sprejme samodejno; najprej ga pregledaš.';

  @override
  String get inviteOpenContinue => 'Nadaljuj do povabila';

  @override
  String get inviteLinkInvalid =>
      'Ta povezava ni veljavno povabilo. V aplikacijo lahko ročno vneseš strežnik in kodo.';

  @override
  String get inviteCopyLink => 'Kopiraj povezavo do povabila';

  @override
  String get inviteLinkPrepared =>
      'Povezava odpre povabilo v nameščeni aplikaciji Jivie. Če se aplikacija ne odpre, v njej ročno vnesi strežnik in kodo.';

  @override
  String get accountFirstTitle => 'Prvi račun s kodo';

  @override
  String get accountFirstDescription =>
      'Upravljavec strežnika ti izda enkratno začetno kodo. Ustvariš navaden uporabniški račun. Po prvem računu se drugi pridružijo s povabilom.';

  @override
  String get accountBootstrapCode => 'Začetna koda upravljavca';

  @override
  String get accountCreate => 'Ustvari račun';

  @override
  String accountCreatedSignedIn(String username) {
    return 'Račun je ustvarjen. Prijavljen si kot $username.';
  }

  @override
  String accountCreatedSignInRequired(String username) {
    return 'Račun $username je ustvarjen, vendar prijave na tej napravi ni bilo mogoče shraniti. Prijavi se s tem uporabniškim imenom in izbranim geslom. Začetne kode ali povabila ne uporabi znova.';
  }

  @override
  String get accountEmailConfirmed => 'E-poštni naslov je potrjen.';

  @override
  String get accountSessionAutoRenew =>
      'Prijava na tej napravi se ob uporabi samodejno podaljšuje.';

  @override
  String get accountPasswordRule => 'Geslo mora imeti od 12 do 72 bajtov.';

  @override
  String get accountForgotPassword => 'Pozabljeno geslo';

  @override
  String get accountResetRequestDescription =>
      'Koda se pošlje samo na že potrjen naslov e-pošte. Zaradi zasebnosti ne razkrivamo, ali uporabniško ime obstaja.';

  @override
  String get accountSendReset => 'Zahtevaj kodo za obnovo';

  @override
  String get accountResetGeneric =>
      'Če račun podpira obnovo, je bila koda poslana na potrjen naslov.';

  @override
  String get accountResetConfirm => 'Imam kodo za obnovo';

  @override
  String get accountResetConfirmDescription =>
      'Vnesi prejeto kodo in novo geslo. Pri dvostopenjski prijavi potrebuješ tudi kodo TOTP. Nato se znova prijaviš; stare naprave se odjavijo.';

  @override
  String get accountEmailCode => 'Koda iz e-pošte';

  @override
  String get accountResetPassword => 'Ponastavi geslo';

  @override
  String get accountResetDone =>
      'Geslo je ponastavljeno. Prijavi se z novim geslom.';

  @override
  String get accountEmailTitle => 'E-pošta in obnova dostopa';

  @override
  String get accountEmailNone => 'Naslov še ni nastavljen.';

  @override
  String get accountEmailVerified => 'Potrjen naslov';

  @override
  String get accountEmailUnverified => 'Naslov še ni potrjen';

  @override
  String get accountEmailPending => 'Čaka na potrditev';

  @override
  String get accountEmailChange => 'Nastavi ali spremeni e-pošto';

  @override
  String get accountEmailRequestDescription =>
      'Ponovno potrdi geslo in po potrebi TOTP. Sedanji potrjeni naslov ostane veljaven, dokler ne potrdiš novega.';

  @override
  String get accountEmail => 'Naslov e-pošte';

  @override
  String get accountEmailSend => 'Pošlji potrditveno kodo';

  @override
  String get accountEmailConfirm => 'Potrdi kodo iz e-pošte';

  @override
  String get accountEmailSent =>
      'Potrditvena koda je zahtevana. Vnesi jo po prejemu e-pošte.';

  @override
  String get accountEmailUnavailable =>
      'Strežnik še nima nastavljenega pošiljanja varnostne e-pošte.';

  @override
  String get accountCodeInvalid =>
      'Koda ni veljavna, je potekla ali je že porabljena. Zahtevaj novo.';

  @override
  String get accountEnrollmentUnavailable =>
      'Prvi račun s kodo tu ni več na voljo. Prijavi se ali uporabi povabilo.';

  @override
  String get planningPhases => 'Faze in mejniki';

  @override
  String get planningAddPhase => 'Dodaj fazo';

  @override
  String get planningPhaseTitle => 'Ime faze';

  @override
  String get planningMilestone => 'Mejnik';

  @override
  String get planningRemovePhase => 'Odstrani fazo';

  @override
  String get planningNoPhase => 'Brez faze';

  @override
  String get planningEstimateMinutes => 'Ocena dela v minutah';

  @override
  String get planningAvailabilityMinutes => 'Razpoložljive minute';

  @override
  String get planningAvailabilityPeriod => 'Obdobje razpoložljivosti';

  @override
  String get planningPerDay => 'Na dan';

  @override
  String get planningPerWeek => 'Na teden';

  @override
  String get planningTimerStart => 'Začni časovnik';

  @override
  String get planningTimerPause => 'Začasno ustavi';

  @override
  String get planningElapsed => 'Porabljeni čas';

  @override
  String get planningRemaining => 'Preostali čas';

  @override
  String get planningEstimated => 'Ocenjeni čas';

  @override
  String get planningCalendar => 'Koledarski termin';

  @override
  String get taskCostTitle => 'Strošek opravila';

  @override
  String get taskCostEnabled => 'Dodaj strošek';

  @override
  String get taskCostPaid => 'Plačano';

  @override
  String get taskCostPlanned => 'Načrtovano';

  @override
  String get taskCostAccount => 'Finančni račun';

  @override
  String get taskCostUnassignedAccount => 'Brez izbire računa';

  @override
  String get taskCostPayer => 'Plačnik';

  @override
  String get taskCostRecipient => 'Prejemnik';

  @override
  String get taskCostAuthor => 'Avtor vnosa';

  @override
  String get taskCostNoDue =>
      'Brez roka opravila strošek nima načrtovanega datuma.';

  @override
  String get taskCostDetachHint =>
      'Odstranitev povezave ohrani finančni zapis.';

  @override
  String get spacePickerTitle => 'Prostor';

  @override
  String get organizationTitle => 'Organizacija';

  @override
  String get organizationCreate => 'Ustvari organizacijo';

  @override
  String get organizationProjects => 'Projekti organizacije';

  @override
  String get organizationCreateProject => 'Dodaj projekt v organizacijo';

  @override
  String get organizationAccessDescription =>
      'Članstvo ne odpre vseh projektov ali financ. Dostop uredi za vsak projekt posebej.';

  @override
  String get peopleTitle => 'Osebe';

  @override
  String get peopleAdd => 'Dodaj osebo';

  @override
  String get peopleName => 'Ime';

  @override
  String get peopleNotes => 'Zapiski';

  @override
  String get peopleArchive => 'Arhiviraj';

  @override
  String get peopleRestore => 'Ponovno aktiviraj';

  @override
  String get peopleWithoutAccountDescription =>
      'Profil osebe nima prijave ali dostopnih pravic.';

  @override
  String get peopleEmpty => 'Dodaj osebe, za katere želiš voditi opravila.';

  @override
  String get peopleArchived => 'Arhivirana oseba';

  @override
  String get financePlanTitle => 'Mesečni načrt';

  @override
  String get financePlanWizard => 'Pripravi finančni načrt';

  @override
  String get financePlanDescription =>
      'Okvirni zneski so pričakovani, dokler ne potrdiš dejanskega prejemka ali plačila.';

  @override
  String get financePlanLocal =>
      'Načrt se shrani na tej napravi in v prenosno kopijo.';

  @override
  String get financePlanPrivate =>
      'Načrt se shrani v izbrani zasebni prostor z vključeno sinhronizacijo.';

  @override
  String get financePlanUpgrade =>
      'Za načrtovanje v sinhroniziranem prostoru je potrebna novejša finančna pogodba strežnika.';

  @override
  String get financePlanMonthEnd =>
      'Če dan v mesecu ne obstaja, uporabimo zadnji dan tega meseca.';

  @override
  String get financePlanWeekend =>
      'Pri plači ob koncu tedna sta preverjanji v petek in ponedeljek za isti priliv. Prazniki se ne prilagajajo samodejno.';

  @override
  String get financePlanSalary => 'Kdaj pričakuješ mesečno plačo?';

  @override
  String get financePlanNoSalary => 'Nimam redne plače';

  @override
  String get financePlanLoan => 'Ali imaš kredit?';

  @override
  String get financePlanLoanPrincipal => 'Skupni znesek kredita (neobvezno)';

  @override
  String get financePlanInstallment => 'Okvirni mesečni obrok';

  @override
  String get financePlanCard => 'Ali imaš kartico z odloženim plačilom?';

  @override
  String get financePlanCardEstimate => 'Okvirna mesečna poravnava';

  @override
  String get financePlanOtherIncome => 'Drugi mesečni prilivi';

  @override
  String get financePlanOtherExpenses => 'Mesečni stroški';

  @override
  String get financePlanAddIncome => 'Dodaj priliv';

  @override
  String get financePlanAddExpense => 'Dodaj strošek';

  @override
  String get financePlanEstimatedAmount => 'Okvirni znesek';

  @override
  String get financePlanDay => 'Dan v mesecu';

  @override
  String get financePlanFirstDate => 'Prvi pričakovani datum';

  @override
  String get financePlanSalaryLabel => 'Plača';

  @override
  String get financePlanLoanLabel => 'Obrok kredita';

  @override
  String get financePlanCardLabel => 'Poravnava kartice';

  @override
  String get financePlanReview => 'Preglej načrt';

  @override
  String get financePlanSave => 'Shrani načrt';

  @override
  String get financePlanRules => 'Mesečna ponavljanja';

  @override
  String get financePlanAddRule => 'Dodaj mesečno pravilo';

  @override
  String get financePlanEditRule => 'Uredi mesečno pravilo';

  @override
  String get financePlanRuleActive => 'Pravilo je vključeno';

  @override
  String get financePlanReminders => 'Opomniki za ta načrt';

  @override
  String get financePlanReminderTime => 'Čas opomnika';

  @override
  String get financePlanReminderOptIn =>
      'To ne vključi dovoljenja telefona. Sistemske opomnike vključi v nastavitvah obvestil.';

  @override
  String get financePlanSalaryQuestion => 'Ali si že dobil plačo?';

  @override
  String get financePlanConfirm => 'Potrdi dejanski znesek';

  @override
  String get financePlanActualAmount => 'Dejanski znesek';

  @override
  String get financePlanActualDate => 'Datum prejemka ali plačila';

  @override
  String get financePlanConfirmed => 'Dejanski znesek je potrjen.';

  @override
  String get financePlanForecast => 'Napoved po datumih';

  @override
  String get financePlanNetChange => 'Pričakovana neto sprememba';

  @override
  String get financePlanProjectedBalance => 'Pričakovano stanje';

  @override
  String get financePlanOpeningBalance => 'Začetno stanje (neobvezno)';

  @override
  String get financePlanOpeningDate => 'Začetno stanje na začetku dne';

  @override
  String get financePlanNoOpening =>
      'Začetno stanje ni določeno; prikazana je neto sprememba.';

  @override
  String get financePlanUndated =>
      'Vnosi brez datuma niso vključeni v časovno napoved.';

  @override
  String get financePlanSymbolicAccount =>
      'To je poimenovan račun za evidenco; denarja ne premika in se ne povezuje z banko.';

  @override
  String get financePlanEmpty => 'V izbranem obdobju ni datiranih vnosov.';

  @override
  String get financePlanRuleType => 'Vrsta ponavljanja';

  @override
  String get financePlanSaved => 'Finančni načrt je shranjen.';

  @override
  String get financePlanOverdue => 'Še nepotrjeno';

  @override
  String get financePlanBack => 'Nazaj';

  @override
  String get financePlanNext => 'Naprej';

  @override
  String get financePlanDateNeeded => 'Izberi datum.';

  @override
  String get financePlanNoItems => 'Ni dodatnih vnosov.';

  @override
  String get financePlanAccountName => 'Ime finančnega računa';

  @override
  String get financePlanAccountArchived => 'Arhiviran račun';

  @override
  String get financePlanReminderBody =>
      'Ali si že dobil plačo? Odpri pričakovani priliv in potrdi dejanski znesek.';

  @override
  String get peopleTaskSubjects => 'Na koga se opravilo nanaša';

  @override
  String get financePlanYes => 'Da';

  @override
  String get financePlanNo => 'Ne';

  @override
  String get financePlanRecordedChange => 'Evidentirana neto sprememba';

  @override
  String get financePairedConflict =>
      'Konflikt opravila in stroška preglej v financah.';

  @override
  String get deletionDetachOrganization =>
      'Ohrani ta projekt kot samostojen prostor, ko se izbriše organizacija. Njegovi člani in finance ostanejo nespremenjeni.';

  @override
  String get deletionOrganizationLinks =>
      'Projekti, ki se odvežejo od organizacije';

  @override
  String get financePlanIncomeQuestion => 'Ali si že prejel priliv?';

  @override
  String get financePlanExpenseQuestion => 'Ali je obveznost že plačana?';

  @override
  String get financePlanIncomeReminderBody =>
      'Ali si že prejel priliv? Odpri pričakovani vnos in potrdi dejanski znesek.';

  @override
  String get financePlanExpenseReminderBody =>
      'Ali je obveznost že plačana? Odpri načrtovani vnos in potrdi dejanski znesek.';

  @override
  String get financePlanManageRule =>
      'Ponavljajoči vnos urejaj prek mesečnega pravila. Izključitev pravila ustavi prihodnje vnose; potrjena zgodovina ostane.';

  @override
  String get scopeArchivedProjects => 'Arhivirani projekti';

  @override
  String get scopeArchivedDescription =>
      'Projekt je arhiviran. Podatki in finančna zgodovina ostanejo na voljo glede na tvoje pravice; opravila ne prispevajo k dnevnemu pregledu ali opomnikom.';

  @override
  String get peopleCopyDescription =>
      'Tudi povezani profili oseb (imena in zapiski) bodo kopirani v izbrani prostor.';

  @override
  String get financePlanPrincipalOnlyLoan =>
      'Skupni znesek kredita lahko vneseš samo pri obroku kredita.';

  @override
  String get financePlanOpeningUndated => 'Brez referenčnega datuma';

  @override
  String planningInvalidMinutes(int max) {
    return 'Vpiši pozitivno število minut, največ $max.';
  }

  @override
  String get taskCostSelectAccount => 'Izberi finančni račun.';

  @override
  String get financeDuplicateOccurrence =>
      'Druga naprava je za ta mesec že ustvarila kanonični vnos. Lokalna različica je ohranjena za primerjavo; isti priliv ali strošek se ne šteje dvakrat.';

  @override
  String get financePairedTaskReview =>
      'Povezano opravilo: hkrati bodo obravnavane te spremembe in strošek.';

  @override
  String get privateSyncTitle => 'Moje naprave';

  @override
  String get privateSyncDescription =>
      'Zasebni prostor samo za ta račun. Vanj ni mogoče povabiti drugih oseb.';

  @override
  String get privateSyncOff =>
      'Osebni podatki so za zdaj samo na tej napravi. Prijava jih ne naloži samodejno.';

  @override
  String get privateSyncReview => 'Preglej pred vključitvijo';

  @override
  String get privateSyncEnable => 'Vključi zasebno sinhronizacijo';

  @override
  String get privateSyncUploadWarning =>
      'Ta izbira prenese pregledane osebne zapise, vključno z osebnimi financami, v zasebni prostor računa. Strežniška sinhronizacija ni varnostna kopija.';

  @override
  String get privateSyncRemoteCount => 'Obstoječi zapisi v zasebnem prostoru';

  @override
  String get privateSyncOn => 'Zasebna sinhronizacija je vključena.';

  @override
  String get privateSyncPaused =>
      'Sinhronizacija je začasno ustavljena. Lokalno delo ostaja shranjeno.';

  @override
  String get privateSyncPause => 'Začasno ustavi sinhronizacijo';

  @override
  String get privateSyncResume => 'Nadaljuj sinhronizacijo';

  @override
  String get privateSyncUnavailable =>
      'Za zasebno sinhronizacijo potrebuješ prijavo in podprt strežnik.';

  @override
  String get privateSyncPending => 'Čakajoče spremembe';

  @override
  String get privateSyncIssue =>
      'Pred vključitvijo odpravi nezdružljive ali sporne zapise. Osebni podatki ostanejo na napravi.';

  @override
  String get backupTitle => 'Šifrirana varnostna kopija';

  @override
  String get backupDescription =>
      'Kopija varuje osebne zapise, nastavitve in dovoljeno skupno delo z geslom. Poverilnic ne vključuje. Aktivna baza s tem ne postane dodatno šifrirana.';

  @override
  String get backupCreate => 'Ustvari kopijo';

  @override
  String get backupRestore => 'Obnovi kopijo';

  @override
  String get backupPassword => 'Geslo varnostne kopije';

  @override
  String get backupPasswordHint =>
      'Geslo ni shranjeno. Če ga pozabiš, kopije ne moremo odpreti.';

  @override
  String get backupPasswordRule =>
      'Uporabi vsaj 12 znakov in največ 1024 bajtov UTF-8.';

  @override
  String get backupPrepare => 'Pripravi šifrirano kopijo';

  @override
  String get backupPick => 'Izberi šifrirano kopijo';

  @override
  String get backupOpen => 'Odpri in preglej kopijo';

  @override
  String get backupReview => 'Pregled vsebine';

  @override
  String get backupSave => 'Shrani datoteko kopije';

  @override
  String get backupSaved => 'Datoteka kopije je shranjena.';

  @override
  String get backupCreatedAt => 'Ustvarjena';

  @override
  String get backupScopes => 'Skupni prostori v kopiji';

  @override
  String get backupPending => 'Neusklajene operacije v kopiji';

  @override
  String get backupCredentialsExcluded =>
      'Gesla, seje naprav in žetoni obvestil niso vključeni.';

  @override
  String get backupRemoteQuarantine =>
      'Obnovljeno skupno delo ostane zaščiteno in ločeno. Po prijavi v pravi račun ga pregledaš ter izrecno dovoliš nadaljevanje; nič se ne pošlje samodejno.';

  @override
  String get backupMerge => 'Združi z osebnimi zapisi';

  @override
  String get backupReplace => 'Zamenjaj osebne zapise';

  @override
  String get backupMergeDescription =>
      'Dodaj manjkajoče osebne zapise. Različna vsebina z istim ID zavrne celotno združitev.';

  @override
  String get backupReplaceDescription =>
      'Trenutne osebne zapise zamenja vsebina kopije. Najprej shrani sedanjo varnostno kopijo.';

  @override
  String get backupRestoreConfirm => 'Potrdi obnovo';

  @override
  String get backupRestored =>
      'Kopija je obnovljena. Skupno delo se ne pošilja samodejno.';

  @override
  String get backupWrongPassword =>
      'Geslo ni pravilno ali je kopija poškodovana. Podatki niso bili spremenjeni.';

  @override
  String get backupUnsupported =>
      'Te različice kopije ni mogoče odpreti. Uporabi združljivo aplikacijo.';

  @override
  String get backupChanged =>
      'Predogled ni več aktualen. Znova pripravi kopijo ali preveri vsebino pred obnovo.';

  @override
  String get backupRecoveryTitle => 'Obnovljeno skupno delo';

  @override
  String get backupRecoveryReview => 'Preglej obnovljeno delo';

  @override
  String get backupRecoveryResume => 'Dovoli nadaljevanje obnovljenega dela';

  @override
  String get backupRecoveryBlocked =>
      'Za to delo potrebuješ pravi račun in veljavne pravice. Kopija ostane zaščitena.';

  @override
  String get backupRecoveryNone => 'Ni obnovljenih paketov skupnega dela.';

  @override
  String get backupReadError =>
      'Kopije ni bilo mogoče odpreti ali shraniti. Poskusi znova.';

  @override
  String get backupShoppingItems => 'Artikli na nakupovalnih seznamih';

  @override
  String get backupOtherRecords => 'Drugi zapisi';

  @override
  String get backupSaveCancelled =>
      'Shranjevanje je preklicano. Datoteka ni bila shranjena.';

  @override
  String get backupDownloadStarted =>
      'Prenos kopije je sprožen. Preveri prenesene datoteke v brskalniku.';

  @override
  String get backupSourceAccount => 'Račun kopije';

  @override
  String get backupSourceServer => 'Strežnik kopije';

  @override
  String get backupLocalOnly => 'Samo na napravi';

  @override
  String get backupAccountMatches =>
      'Osebne zapise lahko obnoviš lokalno. Nadaljevanje skupnega dela znova preveri račun in pravice.';

  @override
  String get backupAccountDifferent =>
      'Kopija je iz drugega računa. Skupno delo ostane zaščiteno do prijave v pravi račun.';

  @override
  String get backupCompleteness =>
      'Kopija vključuje osebno vsebino in dovoljene prenesene zapise ter neusklajeno delo. Strežniških podatkov, ki niso bili preneseni na napravo, ne zajame. Odložitve opomnikov veljajo samo na tej napravi in niso vključene.';

  @override
  String get backupTooLarge =>
      'Kopija je večja od dovoljene omejitve 64 MiB. Podatki niso bili spremenjeni.';

  @override
  String get backupMergeConflict =>
      'Kopija vsebuje drugačno vsebino z istim ID. Združitev je zavrnjena; podatki niso spremenjeni.';

  @override
  String get privateSyncLocalPending =>
      'Novi lokalni zapisi čakajo na tvoj pregled.';

  @override
  String get backupRecoveryState => 'Stanje obnovljenega dela';

  @override
  String get backupRecoveryReady => 'Lahko pregledaš in nadaljuješ';

  @override
  String get backupLegacyJson => 'Prejšnji izvoz JSON brez šifriranja';

  @override
  String get backupIncomplete =>
      'Nekateri preneseni prostori v kopiji niso popolni. Po obnovi jih je treba znova uskladiti.';

  @override
  String get backupArchiveReview =>
      'Ločen pregled odklenjene kopije. Ti zapisi ne postanejo del aktivnega računa, dokler izrecno ne nadaljuješ dovoljenega dela.';

  @override
  String get backupCached => 'Preneseni zapis; ni čakajoče spremembe';

  @override
  String get backupSettingsRetry =>
      'Obnovljene nastavitve še niso bile uporabljene. Zapisi so ohranjeni; poskusi znova.';

  @override
  String get privateFinanceIncomplete =>
      'Zasebni finančni pregled še ni v celoti prenesen. Prikazani zapisi in čakajoče spremembe so ohranjeni; skupni seštevek se pokaže po popolni sinhronizaciji.';

  @override
  String get guideTitle => 'Dobrodošli v Jivie';

  @override
  String get guideOpen => 'Kratek vodič po Jivie';

  @override
  String get guideLocalTitle => 'Začnite na svoji napravi';

  @override
  String get guideLocalBody =>
      'Opravila, načrti, nakupi in osebne finance delujejo brez računa in povezave. Začnite z enim opravilom ali nakupovalnim seznamom. Izbirna sinhronizacija potrebuje vašo izrecno vključitev.';

  @override
  String get guideTodayBody =>
      'Danes pokaže vaša naslednja opravila in dogodke. Tu dodate opravilo ali dogodek in pregledate, kaj vas čaka. Skupni dnevni pregled je na voljo za prostor, do katerega imate dostop.';

  @override
  String get guidePlansBody =>
      'V Načrtih uredite opravila, projekte in dogodke. Dodajte termine in po potrebi povežite opravilo s projektom. Na večjem zaslonu jih dosežete tudi prek stranskega menija.';

  @override
  String get guideShoppingBody =>
      'V Nakupih ustvarite seznam, dodajte artikle in označite kupljeno. Osebni seznam ostane na napravi; kopiranje v skupni prostor je vaša izrecna odločitev.';

  @override
  String get guideMoreBody =>
      'Na telefonu odpri levi meni z gumbom ☰. Tam so neposredne povezave do financ, doma, vrta, oseb, obvestil, računa in nastavitev. Na tablici so dodatne možnosti v Več, na računalniku v stranskem meniju. Nastavitve omogočajo temo, jezik, šifrirane kopije in ponoven ogled vodiča. Račun in strežnik sta neobvezna; prijava sama ne deli osebnih financ ali vključi sinhronizacije. Obvestila nastavite posebej.';

  @override
  String get guideSkip => 'Preskoči';

  @override
  String get guideBack => 'Nazaj';

  @override
  String get guideNext => 'Naprej';

  @override
  String get guideDone => 'Začnimo';

  @override
  String guideProgress(int step, int total) {
    return '$step od $total';
  }

  @override
  String get deletionAccountSettings => 'Nastavitve računa';

  @override
  String get deletionTitle => 'Trajno izbriši račun';

  @override
  String get deletionLocalOnly =>
      'Uporabljate lokalni način. Brez strežniškega računa ni računa za izbris. Lokalno delo ostane na napravi.';

  @override
  String get deletionWarning =>
      'Izbris velja za prikazani račun na tem samostojnem strežniku, tudi za isti račun v Kanboardu. Je trajen. Kopij, ki so jih drugi člani že pridobili, ni mogoče odpoklicati.';

  @override
  String get deletionPreview => 'Preglej izbris računa';

  @override
  String get deletionLocalConsequences =>
      'Izbris odstrani tudi zasebno SINHRONIZIRANE podatke tega računa, njegovo lokalno strežniško kopijo, čakajoče spremembe, opomnike, povezavo za sinhronizacijo in obnovitveno delo. Samostojni osebni podatki v lokalnem prostoru ostanejo. Sinhroniziranih podatkov ne prenesemo samodejno nazaj v lokalni prostor.';

  @override
  String get deletionExportLimit =>
      'Šifrirana .vsakdan kopija ni popoln arhiv Kanboarda ali priponk. Po izbrisu računa z njo ni mogoče nadaljevati njegovega strežniškega dela. Za ohranitev zasebno sinhroniziranih osebnih zapisov za samostojno uporabo uporabite spodnji izrecni JSON izvoz. Za popoln Kanboard arhiv se pred izbrisom obrnite na upravljavca.';

  @override
  String get deletionImpact => 'Posledice na strežniku';

  @override
  String get deletionSharedRemains => 'skupni prostor ostane';

  @override
  String get deletionBlocked =>
      'Pred izbrisom razrešite spodnje pogoje. Nato ponovno preglejte posledice.';

  @override
  String get deletionAcknowledge =>
      'Razumem trajni izbris tega računa, njegovih sinhroniziranih podatkov in opisane posledice za skupno delo.';

  @override
  String get deletionTypeDelete => 'Za potrditev vpišite DELETE';

  @override
  String get deletionConfirm => 'Trajno izbriši';

  @override
  String get deletionUnknown =>
      'Izbris še ni potrjen. Povezava je bila prekinjena ali odgovor ni zanesljiv. V nastavitvah računa preverite stanje te iste zahteve; gesla ne hranimo.';

  @override
  String get deletionNotConfirmed =>
      'Strežnik še ni potrdil izbrisa. Račun je lahko še vedno aktiven. Za ponovitev uporabite iste odločitve in sveže geslo/TOTP.';

  @override
  String get deletionSuccess =>
      'Strežnik je potrdil izbris. Nadaljujete lahko v lokalnem načinu.';

  @override
  String get deletionCheckStatus => 'Preveri stanje izbrisa';

  @override
  String get deletionUnavailable =>
      'Ta strežnik ne podpira izbrisa računa v Jivie. Izbris mora omogočiti njegov upravljavec. Brez povezave izbrisa ni mogoče potrditi.';

  @override
  String get deletionStale =>
      'Podatki so se spremenili. Ponovno preglejte posledice in potrdite nove odločitve.';

  @override
  String get deletionPersonalScopes => 'Zasebni prostori za izbris';

  @override
  String get deletionPersonalRecords => 'Zasebni zapisi za izbris';

  @override
  String get deletionPersonalFinance => 'Zasebni finančni zapisi za izbris';

  @override
  String get deletionMemberships => 'Članstva za odstranitev';

  @override
  String get deletionDevices => 'Naprave in seje za preklic';

  @override
  String get deletionPush => 'Potisne registracije za odstranitev';

  @override
  String get deletionEmailTokens => 'E-poštne kode za preklic';

  @override
  String get deletionRelatedData => 'Povezani zapisi za odstranitev';

  @override
  String get deletionOwnedScopes =>
      'Izberite novega lastnika skupnega prostora';

  @override
  String get deletionLastAdmin => 'Najprej določite drugega skrbnika Kanboarda';

  @override
  String get deletionContributions =>
      'Razrešite svoje prispevke in njihove skupne povezave';

  @override
  String get deletionStructure =>
      'Ohrani le generično strukturo za zapise drugih članov. Izvirno ime in lastnik se odstranita; finančni račun ohrani valuto in začetno stanje. Moji vnosi se izbrišejo in skupni seštevki se lahko spremenijo.';

  @override
  String get deletionSharedRecordsDeleted => 'Lastni skupni zapisi za izbris';

  @override
  String get deletionSharedRecordsUpdated =>
      'Skupni zapisi za razvezavo povezav';

  @override
  String get deletionSharedFinanceDeleted =>
      'Lastni skupni finančni zapisi za izbris';

  @override
  String get deletionSharedFinanceUpdated =>
      'Skupni finančni zapisi za razvezavo';

  @override
  String get deletionLegacyTasks => 'Lastna Kanboard opravila za izbris';

  @override
  String get deletionLegacyComments => 'Lastni Kanboard komentarji za izbris';

  @override
  String get deletionLegacyFiles => 'Lastne Kanboard priponke za izbris';

  @override
  String get deletionAssignedTasks =>
      'Kanboard opravila za odstranitev dodelitve';

  @override
  String get deletionAssignedSubtasks =>
      'Kanboard podopravila za odstranitev dodelitve';

  @override
  String get deletionLegacyPrivate =>
      'Najprej razrešite zasebni projekt v Kanboardu';

  @override
  String get deletionServerCleanup =>
      'Račun in podatkovni zapisi so odstranjeni. Strežnik še dokončuje izbris priponk; preverite stanje do potrjenega zaključka.';

  @override
  String get deletionRetry => 'Ponovi isto zahtevo';

  @override
  String get deletionRetryReview =>
      'Ponovitev uporablja iste odločitve in isti predogled spodaj. Geslo in TOTP vnesite ponovno. Če je predogled zastarel, strežnik zavrne izbris in zahteva nov pregled.';

  @override
  String get deletionDeleteOwnedScope =>
      'Trajno izbriši tudi ta prostor in njegovo vsebino';

  @override
  String get deletionUnnamedStructure =>
      'Skupna struktura brez pravice do podrobnosti';

  @override
  String get deletionMinorUnits => 'najmanjših denarnih enot';

  @override
  String get deletionRetainedEdits =>
      'Na strežniku se izbrišejo zapisi, ki jih je ustvaril vaš račun. Zapisi drugih ustvarjalcev ostanejo, tudi če ste urejali njihovo vsebino. Vaše identitetne povezave se odstranijo; urejanj posameznih polj ni mogoče ločiti po avtorju.';

  @override
  String get jiviePrivacyLink => 'Zasebnost';

  @override
  String get jivieHelpLink => 'Pomoč in podpora';

  @override
  String get jivieDeletionLink => 'Spletna pot za izbris računa';

  @override
  String get jivieLinkFailed => 'Povezave ni bilo mogoče odpreti.';

  @override
  String get deletionSpaceDeleted =>
      'Ta skupni prostor in njegova vsebina bosta trajno izbrisana.';

  @override
  String get deletionCancelPending => 'Prekliči čakajočo zahtevo';

  @override
  String get deletionCancelled =>
      'Strežnik je potrdil preklic. Ta zahteva računa ne more več izbrisati. Za izbris ponovno preglejte posledice.';

  @override
  String get deletionLegacyLocal =>
      'Ločeno shranjene stare Kanboard povezave, predpomnilniki in AI pogovori s tem niso odstranjeni. Stara povezava do izbrisanega računa ne bo več delovala.';

  @override
  String get deletionPersonalExport =>
      'Izvozi osebne podatke za lokalno obnovo';

  @override
  String get deletionJsonWarning =>
      'Ta samostojna kopija vsebuje trenutno dostopne osebne zapise, tudi zasebno sinhronizirane. JSON ni šifriran; shranite ga na varno. Ne vsebuje skupnega dela, sej ali sinhronizacijskih povezav. Po izbrisu ga lahko izrecno uvozite v lokalni način prek nastavitev. Obnovljenih podatkov ne prenesite v drug račun brez svoje izrecne odločitve.';

  @override
  String get gardenTitle => 'Vrt';

  @override
  String get gardenIntro =>
      'Zapiši zasaditve in ročno razporedi grede, rastline ali druge površine.';

  @override
  String get gardenLocalOnly =>
      'Na tej napravi · brez sinhronizacije in deljenja';

  @override
  String get gardenNew => 'Nov vrt';

  @override
  String get gardenEdit => 'Uredi vrt';

  @override
  String get gardenName => 'Ime vrta';

  @override
  String get gardenNameRequired => 'Vpiši ime vrta.';

  @override
  String get gardenEmptyTitle => 'Tvoj prvi vrt';

  @override
  String get gardenEmptyBody =>
      'Poimenuj vrt, dodaj opombe in nariši svojo razporeditev. Vse lahko urejaš brez računa ali povezave.';

  @override
  String get gardenLayout => 'Razporeditev';

  @override
  String get gardenSelectTool => 'Izberi / premakni';

  @override
  String get gardenDrawTool => 'Nariši območje';

  @override
  String get gardenUndo => 'Razveljavi spremembo razporeditve';

  @override
  String get gardenDrawHelp =>
      'Povleci od enega vogala do drugega, da narišeš pravokotno območje.';

  @override
  String get gardenSelectHelp =>
      'Izberi območje z dotikom. Povleci ga za premik; velikost in oznako uredi na seznamu.';

  @override
  String get gardenCanvasDescription =>
      'Skica razporeditve vrta. Območja lahko urejaš tudi na spodnjem seznamu.';

  @override
  String get gardenSketchDisclaimer =>
      'Skica prikazuje razporeditev, ne merila ali resničnih razdalj. Spremembe potrdi s Shrani.';

  @override
  String get gardenAreas => 'Območja';

  @override
  String get gardenAreaListHelp =>
      'Območje lahko dodaš in urediš tudi z obrazcem, brez risanja.';

  @override
  String get gardenAddArea => 'Dodaj območje';

  @override
  String get gardenNoAreas =>
      'Še ni območij. Nariši prvo ali ga dodaj z obrazcem.';

  @override
  String get gardenEditArea => 'Uredi območje';

  @override
  String get gardenAreaLabel => 'Kaj je na tem mestu?';

  @override
  String get gardenLabelRequired => 'Vpiši oznako območja.';

  @override
  String get gardenPositionX => 'Od leve';

  @override
  String get gardenPositionY => 'Od zgoraj';

  @override
  String get gardenWidth => 'Širina';

  @override
  String get gardenHeight => 'Višina';

  @override
  String get gardenGeometryHelp =>
      'Položaj in velikost sta v odstotkih celotne skice.';

  @override
  String get gardenNumberError => 'Vpiši 0–100; velikost mora biti vsaj 1.';

  @override
  String get gardenGeometryError =>
      'Območje mora v celoti ostati znotraj skice. Zmanjšaj velikost ali popravi položaj.';

  @override
  String get gardenUnsavedTitle => 'Neshranjene spremembe';

  @override
  String get gardenUnsavedBody =>
      'Spremembe vrta še niso shranjene. Če zapustiš urejanje, jih zavržeš.';

  @override
  String get gardenKeepEditing => 'Nadaljuj urejanje';

  @override
  String get gardenDiscard => 'Zavrzi spremembe';

  @override
  String get gardenSaveError =>
      'Sprememb ni bilo mogoče shraniti. Osnutek je še odprt. Poskusi znova; če se je shranjeni vrt spremenil, ga ponovno odpri.';

  @override
  String get gardenDeleteTitle => 'Izbrišem vrt?';

  @override
  String gardenDeleteBody(String name) {
    return 'Vrt »$name«, opombe in vsa območja bodo izbrisani s te naprave.';
  }

  @override
  String gardenDefaultArea(int number) {
    return 'Območje $number';
  }

  @override
  String gardenAreaCount(int count) {
    return '$count območij';
  }

  @override
  String gardenAreaPosition(int x, int y, int width, int height) {
    return 'Levo $x %, zgoraj $y % · $width × $height %';
  }

  @override
  String get financePlanPendingEntries => 'Nepotrjeni vnosi';

  @override
  String get financePlanPendingDescription =>
      'Vsi pričakovani prilivi in stroški, tudi brez datuma ali zunaj napovedi. Odpri vnos in potrdi dejanski znesek.';

  @override
  String get financePlanUndatedEntry => 'Datum ni določen';

  @override
  String financePlanForecastPeriod(String date) {
    return 'Datirani vnosi do $date; prikazano je stanje ob koncu posameznega dne.';
  }

  @override
  String get organizerMenuOpen => 'Odpri meni';

  @override
  String get organizerMenuClose => 'Zapri meni';

  @override
  String get planningCapacityTitle => 'Okvirno trajanje';

  @override
  String get planningCapacityRule =>
      'Upoštevamo preostalo ocenjeno delo in zaporedno izvedbo opravil. Pri opravilu velja njegova razpoložljivost, sicer projektna; projektni čas si opravila delijo. Tedenski čas preračunamo na povprečje sedmih dni. To je okvirna količina časa, ne obljubljen datum; vikendov in dejanskih delovnih dni ne razporejamo.';

  @override
  String planningCapacityDuration(String days) {
    return 'Okvirno trajanje v dnevih: $days';
  }

  @override
  String planningCapacityMissingEstimates(int count) {
    return 'Odprta opravila brez ocene dela: $count.';
  }

  @override
  String planningCapacityMissingAvailability(int count) {
    return 'Odprta opravila brez dnevne ali tedenske razpoložljivosti: $count.';
  }

  @override
  String get planningCapacityNoTasks => 'Ni opravil za izračun trajanja.';

  @override
  String get planningCapacityComplete => 'Vsa opravila so zaključena.';

  @override
  String organizationProjectPreview(String name) {
    return 'Organizacija: $name';
  }

  @override
  String get organizationProjectInitialVisibility =>
      'Na začetku vidi projekt samo ustvarjalec. Drugi člani organizacije in zunanji sodelavci dobijo dostop šele z izrecnim povabilom v projekt.';

  @override
  String get organizationProjectCreated =>
      'Projekt je ustvarjen. Zdaj lahko povabiš sodelavce ali odpreš projekt.';

  @override
  String get organizationProjectOpen => 'Odpri projekt';

  @override
  String get reminderSnooze => 'Odloži opomnik';

  @override
  String get reminderSnooze15Minutes => 'Čez 15 minut';

  @override
  String get reminderSnooze1Hour => 'Čez eno uro';

  @override
  String get reminderSnoozeTomorrow => 'Jutri ob tej uri';

  @override
  String get reminderSnoozeChooseTime => 'Izberi datum in čas';

  @override
  String get reminderSnoozeSaved => 'Opomnik je odložen.';

  @override
  String get reminderSnoozeFutureRequired => 'Izberi čas v prihodnosti.';

  @override
  String get reminderSnoozeNeedsConnection =>
      'Za odložitev skupnega opomnika se poveži s strežnikom.';

  @override
  String reminderSnoozedUntil(String until) {
    return 'Odloženo do $until';
  }

  @override
  String financeSourceTask(String title) {
    return 'Povezano opravilo: $title';
  }

  @override
  String financeSourceProject(String title) {
    return 'Projekt: $title';
  }

  @override
  String get financeSourceUnlinked => 'Brez povezave z opravilom';

  @override
  String get financeSourceUnavailable => 'Povezano opravilo ni več na voljo.';

  @override
  String get financeAccountUnavailable => 'Finančni račun ni več na voljo.';

  @override
  String get financeNoFilterResults => 'Za izbrani račun ni vnosov.';

  @override
  String get reminderSnoozeDeviceOnly =>
      'Odložitev velja na tej napravi. Rok opravila ali plačila ostane enak.';

  @override
  String get guideMenuTitle => 'Meni in nastavitve';
}
