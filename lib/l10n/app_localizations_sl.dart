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
}
