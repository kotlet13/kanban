# Osnutek zasebnosti in deklaracij Jivie

**12. oktober — Android fotografije: shranjen Console osnutek.** Aktualna interna
1.6.1 (24) ima izpolnjenih vseh 11 vrst, tudi Photos; vseh enajst je izbirnih,
Collected Yes / Shared No / Ephemeral No z nameni iz
[aktualnega inventarja in izvedbe](ANDROID_PHOTOS_DATA_SAFETY.md).
»Shrani kot osnutek« je dejansko potrjen, brez oddaje v pregled ali javne objave.
SL/EN zasebnost s fotografijami je pripravljena, vendar je spletna objava ustavljena
zaradi potekle prijave računa jivie in odsotnega lastnika. Spodnji lokalni/zunanji
zgodovinski statusi imajo ta novejši dodatek. Dovoljenja, gradnja in Apple so nespremenjeni.

**Idejnik, 12. oktober — lokalni izvor:** novi modul dodaja besedilo/risbe in
normalizirane fotografije PNG/JPEG. Izključno lokalno delo ne pošilja vsebine.
Shrani v deljenem prostoru ali izrecni vklop zasebne sinhronizacije pošlje
podprte table in fotografije na izbrani strežnik; dostop sledi pravicam prostora.
Fotografije se pred hrambo ponovno kodirajo brez vgrajenih metapodatkov;
ne beremo galerije v ozadju in ne dodajamo kamere ali širokih medijskih dovoljenj.
Aktivna SQLite/hramba strežnika nista dodatno šifrirani od pošiljatelja do prejemnika;
prenos je HTTPS, prenosna kopija pa ostaja posebej šifrirana z uporabnikovim geslom.

Prijava table po uporabnikovem predogledu pošlje skrbniku istega strežnika
natančne elemente in njihove fotografije. Osnutki sami ne sprožijo obvestila;
izrecno shranjevanje uporablja obstoječe kanale in kategorijo `ideas`.
Preneseni preverjeni bajti so v lokalnem predpomnilniku, kopiji vsebine5 in
samostojni obnovi; manjkajoča fotografija označi nepopolnost.

Pri deklaraciji nove distribuirane kandidatke je treba dopolniti vsaj
**Photos and videos → Photos**, ob obstoječi uporabniški vsebini in identifikatorjih.
Prenos na uporabnikov strežnik je še vedno prenos z naprave; lokalnost osnovnega
načina sama ne pomeni »No data collected«. Namen je delovanje aplikacije,
fotografije so izbirne. Opredelitev »shared« preverimo po dejanskem toku in
pogojih izrecnega uporabniškega deljenja, ne avtomatično po imenu self-hosted.
[Google, uradna navodila Data safety](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en).
SL/EN spletni izvor je usklajen lokalno, **ni objavljen**. Console, gostovanje,
Android različica in javna oddaja s tem niso spremenjeni.
[Izvedba in preverjanje](../IDEAS_IMPLEMENTATION.md).

**Zaključna odstranitev starega odjemalca, 11. oktober:** stari Kanboard UI, njegov
JSON-RPC prenos, komentarji/priponke v tem UI in AI niso več dosegljive poti nove
kandidatke. [Dokazi in ohranjene odvisnosti](LEGACY_INTERFACE_REMOVAL.md).
Aktualni izvorni inventar zajema lokalni organizer, FamilyHub račune/seje/sinhronizacijo,
prostore/finance/povabila, obvestila/FCM/SMTP ter kopije/obnovo in sistemsko deljenje
izvozov. Širokih medijskih dovoljenj in open_filex ni več. Spodnji inventar ostaja
zgodovinski; končne Console deklaracije uskladimo z dejansko distribuirano kandidatko.

**11. oktober 2026 — prva javna kandidatka brez AI:** uporabnik je naročil dejansko
odstranitev vseh starih AI poti, transporta in pomočnikov. Aktualni dokazi ter meje
so v [NO_AI_FIRST_RELEASE.md](NO_AI_FIRST_RELEASE.md). Objavljena SL/EN zasebnost
in kontakt `support@jivie.app` imata prednost pred spodnjim zgodovinskim inventarjem
7.–9. oktobra. Stare interne izdaje AI še vsebujejo; sprememba izvora ne spreminja
že nameščenih aplikacij ali shranjenih Console odgovorov. Preostale poti sodelovanja,
priponk, FCM in SMTP ostajajo predmet deklaracij; odsotnost AI ne pomeni odsotnosti
prenosov podatkov. [Objavljeno spletno besedilo](../../website/README.md).

**Dopolnitev 9. oktobra 2026:** aktualni inventar kandidatke 1.1.5 (8), vključno z native SDK, medijskimi dovoljenji in vrzelmi starega AI toka, je v [Google Play deklaracijah](GOOGLE_PLAY_DECLARATIONS.md). Stanje dejansko izpolnjenih obrazcev je v [pripravi javne izdaje](GOOGLE_PLAY_PUBLIC_PREPARATION.md). Spodnje zgodovinske predloge uskladimo s končno kandidatko; niso potrditev Console ali javne politike.

Pregled izvorne kode 7. oktobra 2026. To je delovni inventar in osnutek besedil, **ni objavljena politika ali dokončno izpolnjen obrazec trgovine**. Uporabnik je kot izdajatelja določil TriparNA; javni naziv in kontakt `zadruga@triparna.si` sta preverjena na uradni strani. [Osnutek javnih vsebin](WEBSITE_CONTENT.md) navaja vir in meje do samostojnih strežnikov. Veljavna pravna podlaga, dejanska hramba, ponudniki/obdelovalci, države gostovanja ter objavljeni URL-ji še niso dokončno potrjeni. Ne trdimo skladnosti z GDPR ali drugimi predpisi. Končni upravljavec mora potrditi resnično konfiguracijo in prakso; podpisana izdaja mora ustrezati deklaraciji.

## Inventar dejanskih poti

| Način / pot | Podatki in cilj | Zakaj / izbirnost | Dokaz iz kode in odprta meja |
| --- | --- | --- | --- |
| Osebni način brez računa | Opravila, projekti, dogodki, nakupi, finance ter nastavitve na napravi | Lokalna organizacija; račun in internet nista pogoj | `lib/organizer/data/organizer_repository.dart`, SQLite in lokalni opomniki. Aktivna baza nima dodatnega šifriranja; zaščita OS ni dokaz lastnega šifriranja baze. |
| FamilyHub prijava / ustvarjanje / obnova | Uporabniško in prikazno ime, geslo/TOTP za overjanje, ime naprave, identiteta računa/seje; e-pošta po ločeni nastavitvi in potrditvi | Izbirni strežniški način; e-pošta za preverjanje/obnovo, ne avtomatski del prvega vpisa | `collaboration_account_actions.dart`, [pogodba računa](../server/account-api-contract.md). Strežnik hrani tudi varnostne/rate-limit podatke; lokacijo in roke mora opredeliti upravljavec. |
| Self-hosted izbris računa | Preverjeni podatki računa/predogled in geslo/TOTP pri lastnem strežniku; lokalno potrdilo postopka v varni shrambi, server hash receipt tokena in pending poti datotek | Izrecno zahtevani izbris istega Kanboard/FamilyHub računa; status/cancel za neznani odgovor | [Pogodba izbrisa](../server/account-deletion-contract.md). Datotečno pending ni dokončan uspeh; skupni zapisi drugih avtorjev lahko ohranijo urejanja. Statika jivie.app pošilja samo uporabnika na njegov HTTPS strežnik, ne poverilnic. |
| Izbirna zasebna sinhronizacija | Izbrane osebne vsebine in finance, identitete/revizije/operacije na izbranem strežniku | Samo po izrecnem prenosu; branje med napravami istega računa | [Osebni mejnik](../PERSONAL_SYNC_AND_RECOVERY.md); finance imajo ločeno API pogodbo. Prenos HTTPS ni end-to-end šifriranje proti strežniškemu upravljavcu. |
| Dom / deljeni projekt | Skupna vsebina, članstvo, dodelitve, termini, aktivnosti, obvestila in izrecno dovoljene finance na strežniku ter napravah članov | Sodelovanje, po trenutnih pravicah | `collaboration_repository.dart`, finance access generation/ACL. Projektno članstvo ne odpre vseh financ; preklic ne more odstraniti že shranjenih kopij na nepovezani napravi. |
| Lokalni opomniki | Referenca zapisa, čas, generično besedilo ter dovoljenje/časovni pas pri OS | Izrecna nastavitev, deluje za prenesene podatke brez povezave | `local_notification_adapter.dart`. OS obvestilo ni nov strežniški prenos, iOS ima omejen razpored in Android lahko zamika. |
| FCM / APNs (če konfigurirano in vključeno) | Firebase installation/FCM/APNs žetoni in SDK metapodatki pri Google/Apple; identiteta naprave/računa in žeton pri FamilyHub; generično besedilo/referenčni ID-ji za dostavo | Izbirna oddaljena dostava po nastavitvi in opt-in; ni Firebase Auth ali vsebinski backend | `remote_push/`, `remote_push_store.dart`, [push pogodba](../server/push-api-contract.md). Ni naslovov opravil/zneskov v namenskem push payloadu. To ni dokaz, da SDK ne obdeluje drugih tehničnih podatkov. |
| SMTP | Preverjeni e-poštni naslov, generično obvestilo ali enkratna varnostna koda pri strežniku/SMTP ponudniku | Obnova/verifikacija in izbirna e-poštna obvestila | [Account](../server/account-api-contract.md), [collaboration](../server/collaboration-api-contract.md). Produkcijski ponudnik, hramba in dostava še niso potrjeni. |
| Šifrirana prenosna kopija / izbirnik datotek | Dovoljeni lokalni/preneseni podatki v uporabnikovi izbrani datoteki; geslo kopije se ne shrani | Ročni izvoz/obnova; zunanja lokacija je uporabnikova izbira | `portable_backup_crypto.dart`, `backup_wizard.dart`. `.vsakdan` uporablja AES-GCM; ne vsebuje napravnih sej/ključev ali priponk. Stari JSON izvoz je ločena **nešifrirana** možnost; ne imenujemo vseh izvozov šifriranih. |
| Izbirna stara povezava Kanboard | URL, uporabniška identiteta/API poverilnica, projektni zapisi, finance in priponke na uporabnikovem strežniku; datoteke pri izbranem cilju deljenja | Uporabnik jo posebej poveže | `lib/features/auth`, `lib/kanboard`, `credentials_store.dart`. Pregled končne izdaje mora vključiti tudi ta dosegljivi tok; ne sklepamo, da novi organizer pokrije ves arhiv. |
| Izbirni AI v Kanboard tokovih | Prompts, pogovorna zgodovina in poslani podatki projektov/opravil k OpenAI Responses API; lokalna zgodovina v profilu | AI privzeto izključen; posebej nastavljen ključ. Projektni pogovor avtomatsko doda kontekst in zgodovino; ločeno soglasje za ta kontekst ni dokazano. | `lib/ai/openai_local_ai_provider.dart`, `project_ai_chat_page.dart`, `ai_consent_store.dart`, `ai_chat_store.dart`. Pregled 9. oktobra je popravil prejšnjo trditev o soglasju: obstoječi dialog govori o strošku in ga lasten ključ obide. Dosegljivo pot moramo urediti pred javno oddajo. |

Namenske nove seje, push skrivnosti in API ključi so v varni shrambi. Nastavitve so v SharedPreferences; lokalni osebni/skupni zapisi v SQLite, stare shrambe so ohranjene kot vir selitve. Varnostna kopija podatkov ne vključuje skrivnosti prijave. Pri odjavi se strežniški podatki drugega računa skrijejo, osebni lokalni in čakajoči podatki pa se ne izbrišejo tiho. To ni tok izbrisa računa.

Končna deklaracija mora zajeti tudi sistemske kopije naprave, loge na gostovanju in dejansko rabo zunanjih storitev. Iz nastavitev odjemalca ne moremo ugotoviti, kako upravljavec tujega strežnika hrani HTTP/IP podatke ali kopije. V pregledani neposredni odvisnostni konfiguraciji ni Firebase Analytics, Auth, Firestore, Cloud Functions ali Crashlytics; iz tega ne izpeljemo splošne trditve »brez tehničnih podatkov pri SDK-jih«.

## Predlagana preslikava v trgovinah

Za privzeti način velja, da izključno lokalno obdelani podatki niso »collected« po pravilih deklaracij. Omogočene izbirne poti, SDK-ji in ponudniki morajo biti vključeni; samo možnost uporabe brez računa ne zadostuje za univerzalni odgovor »No data collected«. Apple in Google različno opredeljujeta nekatere izjeme/začasno obdelavo. Vira: [Apple App Privacy](https://developer.apple.com/app-store/app-privacy-details/), [Google Data safety](https://support.google.com/googleplay/android-developer/answer/10787469).

| Vsebina omogočene izdaje | Predlog Apple | Predlog Google | Kaj še potrditi |
| --- | --- | --- | --- |
| Prikazno ime, preverjeni e-poštni naslov | Contact Info: Name, Email Address | Personal info: Name, Email address | Dejansko zbiranje vseh omogočenih tokov, povezanost z identiteto in obveznost v posameznem načinu. |
| Račun/članstvo in naprava/seja, FCM/Firebase installation | Identifiers: User ID / Device ID | Personal info: User IDs; Device or other IDs | Namen app functionality/security, SDK metapodatki, povezava žetona z računom, možnost opt-out. |
| Opravila, opisi, načrti, nakupi, dogodki | User Content: Other User Content | App activity: Other user-generated content | Vsebina pride na strežnik samo v omogočenem toku; ne označevati vseh polj kot health/contact data zgolj ker vanje lahko uporabnik vnese poljuben tekst. |
| Osebna in skupna finančna evidenca | Financial Info: Other Financial Info | Financial info: Other financial info | Lahko zajema zneske, valuto, račune, plačnika/prejemnika; ni kartičnega plačevanja ali bank-linking storitve. |
| AI pogovor in poslana projektna vsebina | User Content: Other User Content (dodatne vrste glede na namenske funkcije) | Messages / Other user-generated content, glede na dejanski obrazec | Pošiljanje k OpenAI je izbirno, vendar obrazec vključuje dosegljivo funkcijo in pogodbo ponudnika; ne trdimo avtomatsko izjeme »service provider«. |
| Priponke / deljenje iz starega Kanboard odjemalca | Vrsta User Content glede na dejansko medijsko/datotečno pot | Files and docs / Photos and videos glede na dejansko pot | Nova kopija organizerja priponk ne vsebuje; stare dosegljive poti preizkusiti pred dokončno kategorijo. |
| Varnostni IP/rate-limit in Firebase tehnični podatki | Odvisno od dejanske vrste, rabe in hrambe | Odvisno od dejanske vrste in začasne obdelave | Strežniški dnevniki, native SDK manifest/report in deployment nastavitve; ničesar ne potrditi samo iz tega osnutka. |

Predlagan glavni namen je delovanje aplikacije (sinhronizacija, račun, dostava, uporabniško zahtevani AI). Za account/security dejavnosti določimo točne kategorije v aktualnem obrazcu. Deljeni podatki in naprava so lahko povezani z uporabnikom; anonimizacije ne trdimo. »Collected« in »shared« nista ista odgovora: izjem za ponudnika storitve ali izrecno uporabniško deljenje ne uveljavljamo brez potrjene pogodbe in pogojev. Ne prijavljamo oglasnega namena ali ATT izjeme samo po odsotnosti Analytics; potrditi je treba dejanske prakse vseh omogočenih ponudnikov.

Firebase dokumentira odvisnost Messaging od Installations in tehnične metapodatke; za iOS povezavo APNs žetona z installation ID. Pregledati moramo dejansko pripete native različice, default/init vedenje, konfiguracijo in končni artefakt. Google dokumentacija opisuje najnovejši SDK, zato ni samodejno potrdilo za naš build. Vira: [Android Firebase disclosure](https://firebase.google.com/docs/android/play-data-disclosure), [Apple Firebase disclosure](https://firebase.google.com/docs/ios/app-store-data-collection).

Apple archive mora vsebovati ustrezne privacy manifests in razloge za required-reason API iz aplikacije ter SDK-jev. Prisotnost datotek v pub-cache še ne potrdi vključitve v archive. Določitev odgovorov o izvoznih pravilih šifriranja zahteva pregled AES-GCM/PBKDF2 in distribucijskih držav; AES izvozov ne označimo samodejno kot izvzetih.

## Jedro bodoče politike (SL / EN)

Spodnji odstavki opisujejo vedenje kode, ne nadomestijo politike. Pred objavo dodamo potrjeno identiteto/kontakt upravljavca, datum veljavnosti, pravne podlage, roke hrambe, države/prejemnike, pravice in postopek zahtev ter dejanski izbris računa. Politike ne objavimo z lažnimi URL-ji ali opisom neizdelanega izbrisa.

**Slovenščina:** Jivie omogoča osebno organizacijo na napravi brez računa. Osebna opravila, načrti, nakupi in izdatki se v tem načinu obdelujejo lokalno. Ob prijavi ne prenesemo osebnih podatkov samodejno. Če vključite izbirno zasebno sinhronizacijo ali deljenje, se ustrezni zapisi pošljejo na izbrani združljivi strežnik; vidnost določajo pravice prostora. Njegov upravljavec lahko obdeluje podatke za delovanje, varnost in varnostne kopije strežnika. Samostojni strežnik ima lastnega upravljavca, katerega prakso je treba preveriti.

Lokalni opomniki uporabljajo sistem naprave. Oddaljena obvestila ob ustrezni nastavitvi in vašem vklopu uporabljajo Firebase Cloud Messaging ter na iOS APNs. Za dostavo se obdelujejo žetoni naprave, tehnični metapodatki ter generično sporočilo z referencami, brez naslovov opravil ali finančnih zneskov v našem push sporočilu. Če posebej omogočite AI in posredujete vsebino, je izbrana vsebina poslana k OpenAI. Funkcija zahteva ločeno nastavitev; osnovno osebno delo deluje brez AI.

Šifrirano prenosno kopijo ustvarite z geslom in jo shranite na izbrano lokacijo. Stari JSON izvoz je nešifriran. Prenosna kopija ne vsebuje prijavnih sej ali priponk in ni popolna kopija strežnika. Aktivna lokalna baza nima dodatnega lastnega šifriranja. Odjava sama ne izbriše računa, osebnih lokalnih zapisov ali vseh čakajočih sprememb. Samostojni strežniški izbris računa je v lokalnem pregledu. Ima ločeno preverjanje identitete, vpliva, skupnega lastništva in datotek; pred javno objavo je treba potrditi delovanje nameščene pogodbe in njene meje.

**English:** Jivie supports personal organization on your device without an account. Personal tasks, plans, shopping and expenses are processed locally in this mode. Signing in does not upload personal data automatically. When you enable optional private synchronization or sharing, the relevant records are sent to your selected compatible server; workspace permissions control their visibility. The server operator may process data for operation, security and server backups. A self-hosted server has its own operator whose practices must be checked.

Local reminders use your device's operating system. With compatible configuration and your opt-in, remote notifications use Firebase Cloud Messaging and APNs on iOS. Delivery processes device tokens, technical metadata and a generic message with references; our push message does not include task titles or financial amounts. If you separately enable AI and submit content, the selected content is sent to OpenAI. Basic personal use works without AI.

You create an encrypted portable backup with a password and save it to your chosen location. The legacy JSON export is unencrypted. Portable backups do not contain login sessions or attachments and are not complete server backups. The active local database has no additional application-level encryption. Signing out does not delete the account, personal local records or all pending changes. Self-hosted account deletion is under local review, with separate checks for identity, impact, shared ownership and file cleanup. Its deployed contract and limits must be verified before public release.

## Zahtevani zaključki upravljavca

- Potrditi identiteto in kontakt izdajatelja/upravljavca ter mejo do samostojnih upravljavcev; objaviti politiko/podporo na resničnih javnih HTTPS naslovih in jih dodati aplikaciji.
- Potrditi vsa omrežja/ponudnike in pogodbe, namen ter roke hrambe aktivnih podatkov, dnevnikov, SMTP in kopij. Ne dodajati izmišljenih rokov (npr. 30 dni) ali trditev o neprodaji/neučenju brez potrditve.
- Zaključiti lokalni pregled ter preizkusiti nameščeni self-hosted izbris računa v aplikaciji/storitvi in javno spletno pot; natančno prikazati skupno lastništvo/finance, preostala urejanja v tujih zapisih in morebitne zakonske izjeme. [Odprti pogoji](READINESS.md).
- Pregledati vse omogočene poti podpisane kandidatke, zlasti staro Kanboard/AI/datotečno deljenje, transport HTTPS, SDK init in privacy manifest. Uskladiti obe trgovinski deklaraciji s to kandidatko.
