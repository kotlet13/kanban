# Jivie — priprava javne Google Play izdaje

Stanje 9. oktobra 2026. Uporabnik je naročil pripravo dokumentacije, opisov in grafik v Console. Po vrnitvi domov je izrecno naročil nadaljevanje obrazcev ter ustavitev pred izdelavo nove izdaje. **Spremembe niso oddane v pregled in produkcijska izdaja ni objavljena.** Ob pripravi obrazcev je bila interna izdaja **1.1.10 (13)**; poznejši ločeni izdajni korak je objavil **1.2.0 (14)** za interne uporabnike; [izdajni dnevnik](NOTIFICATION_RELEASE_RUN.md) vodi njen ločeni dokaz. Nadaljevanje obrazcev ne izdeluje nove gradnje, ne spreminja verzije ali strežnika.

## Nadaljevanje z lastnikom — vsebinska ocena

Lastnik je izbral **samo odrasle (18+)** in **prvo javno izdajo brez starega AI klepeta**. Na predlog prepovedi seksualno eksplicitne vsebine je odgovoril »verjetn bi blo dobr«; to je podpora smeri, ne dokaz že sprejetih uporabniških pogojev ali delujoče moderacije. Končno pravilo mora pred oddajo natančno opredeliti tudi goloto, saj vprašalnik ne sprašuje samo o pornografiji.

IARC kategorijo in sprejem pogojev je do začetka tega nadaljevanja opravil uporabnik; agent pogojev ni ponovno sprejemal. Osnutek vprašalnika je shranjen in odprt na **Povzetku**, končni gumb **Shrani** za prenos ocene v Pregled objavljanja pa ni bil pritisnjen. Osnutek opisuje načrtovano javno kandidatko, ne nespremenjene interne 1.1.10 (13), v kateri je AI še dosegljiv.

| Vprašanje | Odgovor v osnutku / pogoj |
| --- | --- |
| Vsebina za ocenjevanje v začetnem paketu | Ne; ta odgovor je ob začetku že izbral uporabnik. |
| Izmenjava uporabniške vsebine | Da; skupni zapiski, komentarji in poljubne priponke. |
| Deljena UGC kot glavni vir vsebine | Ne; osebni organizator z izbirnim sodelovanjem, brez javnega vsebinskega feeda. |
| Deljenje golote | Začasno Ne za predlagano javno politiko; pred končno oddajo uskladiti obseg pravila in dejansko kandidatko. |
| Javno deljenje nazornega resničnega nasilja | Ne; ni javne objave vsebine. |
| Blokiranje / prijava uporabnikov ali vsebine / moderiranje klepeta | Ne / Ne / Ne po trenutnem izvornem pregledu. Odstranitev članstva ni osebna funkcija blokiranja. |
| Interakcije samo s povabljenimi prijatelji | Da; zaprt dostop do skupne vsebine po članstvih. |
| Promovirana spletna vsebina, vključno z AI | Začasno Ne **samo pod pogojem dejanske odstranitve dosegljivega generativnega AI iz javne kandidatke**. Če ostane pomoč pri naslovu/opisu ali druga AI pot, odgovor ponovno pregledati in označiti Da. |
| Promoviranje starostno omejenih izdelkov/dejavnosti | Ne. |
| Natančna lokacija drugim / digitalni nakupi / denarne ali kripto nagrade / brskalnik ali iskalnik / novice ali izobraževanje | Vsi Ne po izvornem pregledu. Nakupi so seznam, ne trgovinski checkout. |

Izračunani **osnutek** kaže PEGI 3, ESRB Everyone, ClassInd/USK za vse starosti ter splošno 3+, z oznako Interakcija uporabnikov. To ni potrjena končna ocena, odobritev Google ali sprememba ciljne skupine: lastnikova ciljna skupina ostaja 18+. Pred oddajo ponovno preveriti končno kandidatko in odgovore. [Google navodila za ocenjevanje](https://support.google.com/googleplay/android-developer/answer/9859655?hl=en), [UGC](https://support.google.com/googleplay/android-developer/answer/11070862?hl=en), [glavni vir UGC](https://support.google.com/googleplay/android-developer/answer/12994051?hl=en) in [spletna vsebina](https://support.google.com/googleplay/android-developer/answer/11070055?hl=en).

Izvorni podagent GPT-6.1 Sol / high je samo bralno preveril dosegljive stare Kanboard in AI poti ter odsotnost osebnega blokiranja, prijave, starostnega preverjanja in lastne vsebinske moderacije. Ni izvedel nove gradnje ali fizičnega testa. Novo pravilo o deljeni vsebini potrebuje dejanske uporabniške pogoje in možnost prijave pred javno oddajo; to ni izvedeno s tem obrazcem.

### Preostali obrazci in dejanske prepreke

- **Ciljna skupina 18+** je shranjena v Console po potrditvi preglednega dostopa. Izbrana je samo skupina »18 in več«; izbirna dodatna blokada prenosa za mladoletne ni vključena. Povzetek potrdi starost in »Sprememba je shranjena«. Sprememba ni poslana v pregled. Dokaz: `target-audience-18-saved.png` v spodnji QA mapi.
- **Podrobnosti o prijavi** so dejansko shranjene: lastnik je neposredno vnesel geslo namenskega računa in shranil obrazec. Console prikazuje shranjen komplet preglednih podatkov ter potrdilo shranitve. Izbrano ostaja Da za omejeni dostop; strežnik in angleška navodila so navedeni. Dokaz brez gesla: `app-access-saved.png` v spodnji QA mapi. Normalno prijavo še preverimo pred oddajo.
- **Javne povezave**: dejanski HTTP pregled 9. oktobra je vrnil `https://jivie.app/` 403, `/privacy/` 404 in `/delete-account/` 404. Spletnega dostopa nismo obšli z izklopom TLS; strani je treba objaviti ter ponovno preveriti pred izjavami o zasebnosti/izbrisu.
- **Medijska dovoljenja**: pregled Console še kaže zahtevano izjavo zaradi dovoljenj v obstoječem svežnju. Potrebna je že zabeležena odstranitev nepotrebnih širokih dovoljenj v novi kandidatki, ne izmišljen razlog za galerijsko funkcijo.
- **Varnost podatkov** ostaja osnutek do delujočih strani, dostopa za pregled in preverjanja dejanske nove kandidatke brez starega AI.

Lastnik je nato dovolil uporabo obstoječega **jivie-test.triparna.si** z novim namenskim preglednim računom. Pripravljeni Kanboard obrazec je določal lokalnega uporabnika z vlogo User, brez obstoječega projekta ali skupine, brez e-poštnih obvestil in z angleškim jezikom. Lastnik je neposredno vnesel novo geslo ter shranil račun. Spletni profil potrjuje aktivno lokalno uporabniško vlogo, prazna skupinska članstva in izključeno 2FA. Geslo ni v klepetu, dokumentaciji ali izvorih. To še ni dokaz normalne Native prijave ali končnega Googlovega dostopa.

Angleška navodila in uporabniško ime so pripravljeni v obrazcu Google Play; lastnik je geslo vnesel neposredno in potrdil shranitev. Agent je shranjeno stanje preveril v vidnem povzetku, brez branja gesla ali ponovnega odpiranja njegovega vnosa. To je shranjena izjava, ne potrjen Googlov pregled ali normalna prijava v kandidatki. Javni HTTPS Native `capabilities` na istem testnem strežniku je ponovno vrnil HTTP200, pričakovani `serverId`, record pogodbe [1,2,3] ter finance [1,2]. Različice živega vtičnika ne sklepamo iz spremenjenih lokalnih virov.

**Namenski testni podatki so dejansko pripravljeni.** Ločeni CLI pomočnik zunaj spletnega korena je zahteval nespremenljive PHP izvore commita `de453f0`, FamilyHub0.7.0/schema11, točno testno bazo/strežnik ter samo nov navaden uporabniški račun. Pred izvedbo je bil preizkušen na ločeni MySQL8.4/Kanboard1.2.54 fixture: začetni zapis, ponovitev brez podvajanja, nespremenjen uporabnik2, preklic začasnih sej, odsotnost e-poštnih/push opravil in zavrnitev neznanega obstoječega zapisa brez sprememb baze. Testna infrastruktura je odstranjena. Izvirni pomočnik ima SHA256 `fb8f25e557938ef0afdd31401d9311b0e63118a740dcc085fecb9a8a84509043`; ujemanje prenosa in PHP8.4 lint sta na gostovanju potrjena.

Živa izvedba je prek obstoječih Native storitev ustvarila samo dva lastna namenska prostora, projekt/opravilo, nakupovalni seznam/artikel ter račun in sintetični izdatek 5 EUR. Končni Native pregledi potrdijo seznam samo teh dveh prostorov in lastno članstvo. Ločen bralni pregled potrdi **2 prostora / 4 splošne zapise / 2 finančna zapisa / 0 aktivnih pripravljalnih sej**. Geslo ni bilo uporabljeno ali kopirano za seeding; žeton začasne pripravljalne seje je obstajal samo v pomnilniku in je preklican. Zato ta dokaz **ni** normalna prijava z geslom ali fizični prikaz v končni kandidatki. Ob neprestrezljivem SIGKILL bi bila možna standardna nepreklicana seja do izteka; pri tej dejanski izvedbi je njen preklic potrjen. Pomočnik ostane zaseben, CLI-only in zavrne neznane/spremenjene podatke; ni HTTP poti ali novega javnega API.

Dokazi: `build/qa/google-play-public-continuation/review-user-created.png`, `seed-helper-local-test-evidence.json` in `review-data-live-verified.png`. Namenski prostori imajo izrecno sintetične oznake; to niso vzorčni začetni podatki običajnega uporabnika aplikacije. Googlov komplet podatkov je shranjen; normalno prijavo še preverimo pred končno oddajo.

Osnovni pregledni tok: zagon lokalnega načina brez računa, dodajanje osebnih podatkov, nato povezava v Nastavitvah z namenskim računom in pregled namenskega prostora. Samostojni izbris bi trajno odstranil pregledni račun; za dejanski preizkus izbrisa uporabimo drug namenski testni račun, da stalni dostop za Google ostane ponovljiv. Običajna Native prijava, izolacija prostorov in testni podatki se preverijo ločeno pred končno oddajo. Poverilnic ne izmišljamo in jih ne shranjujemo v javni Git.

Dokazi v ignorirani `build/qa/google-play-public-continuation/`: `iarc-sharing-draft.png`, `iarc-summary-draft.png`, `iarc-pegi-draft.png`. Nova izdaja, izvorne spremembe, oddaja v pregled in javna objava niso izvedene. Spodnja evidenca o prvi pripravi ostane zgodovina.

## Dejanske spremembe v Console

Pregledana je evidenca `si.triparna.jivie`, app ID `4972659047480717992`, organizacijski račun `4991604398202512900`. Stara Kanban Connect ostaja ločena.

| Področje | Shranjeno stanje |
| --- | --- |
| Predstavitev | Jivie, slovenski privzeti jezik in dodatni `en-US`; kratki/dolgi opisi iz [STORE_LISTINGS.json](STORE_LISTINGS.json). |
| Slike | Potrjena ikona 512 × 512, lokalizirani predstavitveni grafiki 1024 × 500, šest telefonskih zaslonov 1080 × 1920 na jezik. Vrstni red: Danes, Načrti, Nakupi, Finance, Vrt, finančni zapisi. |
| AI oznaka slik | Ikona in obe predstavitveni grafiki so označene, ker vsebujejo potrjeni znak z AI izvorom. Izriši dejanskih widgetov niso označeni kot generirane ilustracije. |
| Kategorija | Aplikacija, Storilnost. |
| Kontakt | `zadruga@triparna.si`, `https://jivie.app/`; javni poslovni kontakt shranjen. |
| Oglasi / oglaševalski ID | Brez oglasov; ne uporablja advertising ID. |
| Državna / zdravstvena aplikacija | Ni državna aplikacija; brez namenskih zdravstvenih funkcij. |
| Finančne funkcije | Other: ročna osebna/skupna evidenca prihodkov, izdatkov, računov in proračuna. Izrecno brez povezave z bankami, premikanja denarja, plačil, posojil, naložb ali finančnega svetovanja. |
| Varnost podatkov | Samo osnutek: izbirni prenos podatkov, šifriranje med oddaljenim prenosom, geselni račun in možnost TOTP. Nadaljevanje zaustavi nedosegljiv `https://jivie.app/delete-account/`. Podrobne vrste/purposes še niso oddane. |

Končni pregled objave kaže oba jezika in shranjene izjave. Glava izrecno pravi **»Spremembe še niso bile poslane v pregled«**, gumb za oddajo je onemogočen zaradi manjkajočih korakov. AD_ID, državna in finančna izjava so ločeno navedene kot informacije za pregled. To je dokaz priprave, ne odobritve Google.

Slike so izriši trenutnih proizvodnih Flutter widgetov s sintetičnimi lokalnimi podatki, ne fotografije uporabnikovih podatkov ali zajemi fizične Android namestitve. [Postopek, pisave, omejitve in ponovitev](store-assets/README.md), [manifest slik](../../assets/store/google-play/manifest.json). Pred oddajo jih primerjamo s podpisano kandidatko.

## Preostali koraki pred oddajo

1. **Spletna stran:** objaviti `jivie.app` ter preveriti HTTPS, `/privacy/`, `/help/`, `/delete-account/` in angleške poti. Google je trenutno URL za izbris zavrnil kot nedosegljiv. Spletno besedilo o AI je popravljeno, ker prejšnji opis ločenega soglasja ni ustrezal pregledani kodi. Novi lokalni paket je `build/releases/jivie-website-2026-10-09.zip`; starega paketa ne prepisujemo. Politiko pred končno oddajo uskladimo s končno kandidatko in resnično prakso gostovanja.
2. **Ciljno občinstvo:** lastnik še ni odgovoril na vprašanje odrasli / tudi najstniki / tudi otroci. Predlog 18+ ni shranjena odločitev. Družinski namen sam ne določa starostne skupine.
3. **IARC:** začetni obrazec ima poslovni e-poštni naslov in kategorijo »Vse druge vrste aplikacij«. Sprejem [IARC pogojev](https://web.iarcservices.com/terms) ostaja nepotrjen; vprašanje lastniku je odprto. Pravila upravljanja brskalnika zahtevajo potrditev ob sprejemu novega pravno zavezujočega sporazuma. Vprašalnik/ocena še nista zaključena.
4. **Dostop za Google pregled:** lokalni način je prost, sodelovanje pa zahteva namenski pregledni HTTPS strežnik in delujoč račun. Obrazec App access ni shranjen z lažnim »poln dostop« ali lastnikovim geslom. Pripraviti trajen testni dostop in angleška navodila za dejanski obseg kandidatke; samo kratkotrajna enkratna registracijska koda ne zadostuje za ponovljiv pregled. V javnih datotekah ni poverilnic.
5. **Medijska dovoljenja:** obstoječi AAB8 zaradi `open_filex` vsebuje široka READ_MEDIA_IMAGES/VIDEO/AUDIO in starejše READ_EXTERNAL_STORAGE. Pregled ni pokazal potrebe po širokem dostopu. V novi kandidatki odstraniti nepotrebna dovoljenja ter preveriti izbirnik/odpiranje priponk in kopij. Console izjave o bistveni galerijski funkciji ne izpolnimo z neresničnim razlogom.
6. **Stari AI in deljena vsebina:** pregled ni našel ločene privolitve za samodejno dodan projektni AI kontekst, prijave spornega AI odgovora ali zahtevanih UGC pogojev/prijave vsebine oziroma uporabnika. Preveriti dosegljive tokove z računom, dopolniti ali izrecno omejiti obseg javne kandidatke; ne predpostaviti, da lastni ključ ali zaprta skupina odpravita zahteve. [Dokazi in uradni viri](GOOGLE_PLAY_DECLARATIONS.md).
7. **Varnost podatkov:** po zgornjih odločitvah dokončati konkretne collected/shared vrste in namene, preveriti hrambo strežnika/SMTP/AI ter uskladiti javno politiko. Delni osnutek še ni dokončna izjava.
8. **Fizični preizkusi:** uporabnik je potrdil izboljšano navigacijo/odzivnost. Posebej ostanejo preizkus dveh naprav/računov, pravice do financ, offline spremembe in ponovno povezovanje, obvestila drugega člana, kopija/obnova ter izbris testnega računa. To niso že potrjeni izidi tega koraka.
9. **Končna kandidatka:** po nujnih popravkih nov podpisani AAB, pregled končnega manifesta in dovoljenj, notranje testiranje, primerjava slik in deklaracij. Pred javno oddajo pregled preostalih nastavitev distribucije ter izrecna odločitev o oddaji/objavi.

## Preverjanje in dokazila

- 2 zajemna Flutter testa PASS, 12 dejanskih UI izrisov; brez pisanja v uporabnikovo bazo.
- Analiza: brez napak/opozoril, 37 obstoječih informacijskih ugotovitev. Proizvodna Dart koda, SDK in zaklenjene odvisnosti niso spremenjeni.
- Vseh 15 PNG preverjenih vizualno, po dimenzijah in hashih. Ikona je bajtno enaka obstoječi potrjeni Play ikoni.
- `python3 -m unittest discover -s tools/release -v`: 18 PASS.
- `python3 tools/release/check_readiness.py --code-only`: PASS; to ni store approval ali fizični preizkus.
- `git diff --check`, lokalne povezave dokumentacije in statičnih strani: PASS. `node tools/release/test_deletion_link.mjs`: PASS.
- Dokazi Console so v ignorirani `build/qa/google-play-public/`: `publishing-prepared.png`, `listing-ready.png`, `sl-screenshots-saved.jpg`, `category-contact-saved.jpg`, pet posnetkov posameznih shranjenih izjav, `data-safety-draft-url-pending.jpg`, `app-access-review-account-needed.jpg`, `iarc-terms-pending.jpg`.
- Javno besedilo o AI/FCM je usklajeno z najdenim vedenjem; paket je pripravljen lokalno, na gostovanje ni prenesen. Vseh 15 datotek ZIP se bajtno ujema s trenutnim `website/public/`; SHA-256 `0fb842c6f58ac83964bd8103f7393a11f2072f27ef060ee97caccb41a577b166`.

Obstoječi interni kanal s 15 člani ostaja nespremenjen. Ta priprava ne spreminja iOS stanja ali uvaja plačljivega gostovanja.
