# Jivie produkcija na TriparNA

Stanje: **13. oktober 2026 — FamilyHub 0.13.0/schema17 dejansko nameščen; pripravljen za prvi račun.**

## Zaključena namestitev 13. oktobra

Po uporabnikovi novi Softaculous namestitvi in spletni skrbniški prijavi je bil
nameščen aktualni FamilyHub. Spodnja starejša pregleda sta zgodovina, ne navodilo
za ponovno namestitev. **Pomočnika za svežo bazo ne zaganjaj na tej živi namestitvi.**

| Področje | Dejanski končni dokaz |
| --- | --- |
| Namestitev | `https://jivie.triparna.si/`, Kanboard 1.2.54, PHP 8.4.26, MariaDB 10.11.19, baza `tripar13_jivieprod`. |
| FamilyHub | 0.13.0/schema17; 96 nameščenih datotek bajtno ustreza preverjenemu paketu. |
| Identiteta | Novi `serverId` je `ad56910f-ca2e-41ee-af0d-3f18081497cf`. |
| Praznost | Pred migracijo 48 tabel/40 začetnih vrstic, samo `jivie_admin`, nič projektov/opravil/FH tabel. Po migraciji 92 tabel, 44 FamilyHub tabel, **0 aplikacijskih računov in 0 naprav**. Edini začetni FH vrstici sta identiteta in sistemska ključavnica; uporabniška vsebina je prazna. |
| Ohranitev | 47 starih tabel ima iste vrstice in CREATE hashe; izjema je pričakovana nova vrstica v `plugin_schema_versions`. Skrbnik/geslo sta ohranjena. Vseh 2.100 datotek jedra ima iste hashe. |
| Zasebnost datotek | `config.php` in `familyhub-config.php` sta pod `/home/tripar13/private/jivie-production`, način 0600; podatkovno drevo in `files`/`cache` so 0700. Zasebna pot je zunaj vseh 15 pregledanih document rootov. |
| Javni API | HTTPS capabilities 200, Native API vključen, `self_hosted`, record1–5, Idejnik/fotografije/prijave vsebine/prvi račun/izbris računa/inbox podprti. Anonimna `sync5.pull` in `ideas.asset.download` vrneta 401 `auth_required`. |
| Skrbniški vmesnik | Obstoječa prijava ostane; stran prijav kaže »Ni prijav«, stran FamilyHub enrollment ponuja »Izdaj novo kodo«. Koda ni izdana in prvi račun ni ustvarjen. |
| Opravila v ozadju | Izvirni crontab je ohranjen v celoti, dodana sta samo produkcijska minutely `reminders.php` in `account-deletion-cleanup.php` z ločenima `flock` ključavnicama/zasebnima dnevnikoma. Začetna izvedba uspe; končni crontab je točno pričakovan, oba dnevnika obstajata in sta bila ob pregledu stara 1 sekundo. |
| Dostava | **SMTP in FCM sta izključena.** Capabilities pošteno kaže emailInvitations/emailVerification/passwordReset/externalPush=false. Nobene testne poverilnice niso kopirane in nobena pošta/push ni poslana. |

### Kopija in dejanska obnova pred namestitvijo

Samo produkcijska domena je bila začasno zaprta s preverjenim HTTPS 503, njen
novi Softaculous cron začasno umaknjen, nato je preteklo dejanskih 65 sekund.
Kopija je nastala pod zaklepom tabel in z dvema primerjavama inventarja.
Zasebni ZIP ima **19.524 bajtov, 8 vnosov**; SHA256
`2db06c4074dda04ace7b87892032c3a255b75b32d21cc5f1bd7f7d8903542d0a`.
SQL SHA256 je `50ca1d33fb4aa5d4cef20c5fdb36da72a9405241aa749a978838660ea6072128`.

- Gostovana kopija: `/home/tripar13/private/jivie-production/backups/fresh-before-familyhub-20261013/ProductionFresh-private-backup.zip`.
- Lokalna zasebna kopija zunaj Git: `/Users/anzenovsak/.local/share/jivie/backups/production-fresh-20261013/ProductionFresh-private-backup.zip` (0600).
- Dejanska obnova v izolirani MariaDB 10.11.19 brez omrežja, portov in bind mountov potrdi vseh **48 tabel/40 vrstic/2 datoteki/0 podimenikov** ter vse row/CREATE/config/cron hashe. Vsebnik in njegov začasni volumen sta po preverjanju odstranjena.

To je prednamestitvena kopija sveže baze; **ni tekoča kopija prihodnjih računov,
fotografij ali sprememb**. Redni produkcijski interval/hramba in kopija po začetni
konfiguraciji še sledijo. Izvirna `.htaccess` je po namestitvi povrnjena bajtno.

### Pomočnik in meje preverjanja

[Produkcijski pomočnik](PRODUCTION_INSTALL_HELPER.md) zdaj podpira tudi točno
pregledano celotno Softaculous predlogo Kanboarda 1.2.54 s štirimi DB literali.
Pri selitvi konfiguracije je bilo treba ohraniti absolutni javni `PLUGINS_DIR`:
prva različica je zaradi relativnega `__DIR__` iskala vtičnik v zasebni mapi.
To je bilo popravljeno še med vzdrževanjem, ko je baza še imela 48 tabel in ni
bila izvedena nobena migracija FamilyHub. Izvirna konfiguracija/stanje sta
zasebno ohranjena; končni pomočnik `deploy-production-0.13.0-r2.php` potrdi
aktivirano stanje. Šele nato je dejanski bootstrap izvedel migracije do17.
**208 izoliranih kontrol pomočnika PASS**, vključno s točno potjo vtičnikov,
ohranitvijo poverilnic in zavrnitvijo spremenjene predloge. Funkcionalni izvor
vtičnika ni spremenjen.

Dokazi brez gesel so v `build/qa/production-install-20261013/`:
`fresh-database.png`, `backup-export.png`, `restore-proof.json`,
`schema17-empty.png`, `public-capabilities.json`, `anonymous-guards.json`,
`reports-ready.png`, `first-account-ready.png`, `cron-and-private-paths.png`.
Pomožni skripti in manifest so v `server/scripts/production-0.13.0/`;
ne vsebujejo dejanske konfiguracije ali SQL kopije.

### Naslednji korak

1. Lastnik v odprtem **FamilyHub enrollment** izda enkratno kodo. V Jivie odpre
   **Prvi račun s kodo**, vnese `https://jivie.triparna.si/`, kodo, svoje novo
   uporabniško ime in geslo z vsaj 12 znaki. Kode/gesla ne pošilja v klepet.
   Pred tem **ne izvajaj Native prijave s spletnim skrbnikom**, ker bi zaprl bootstrap.
2. Dokončaj produkcijski SMTP in ločeno FCM identiteto/ključ za projekt aplikacije;
   nato potrdi dejansko dostavo na dogovorjeno napravo/prejemnika. Do takrat
   e-poštna povabila, e-poštna obnova gesla in oddaljeni push ne delujejo.
3. Nastavi redne zasebne kopije z določeno hrambo in zajemom celotnega podatkovnega
   drevesa ter konfiguracije. Prva zgornja kopija ostane izhodišče.

Android ostaja **1.7.0(25)**. Test1/test2, aplikacijska koda, splet in javni
FamilyHub repo v tem koraku niso spremenjeni. Prva Native prijava/dvosmerna
produkcijska uporaba še ni potrjena; ni potrebna nova Android gradnja.

## Zgodovinski pregled pred namestitvijo 13. oktobra

Na pravilnem cPanel računu `tripar13` je bilo samo za branje preverjeno:

- Domena ima lasten koren `/home/tripar13/jivie.triparna.si` in vključen Force HTTPS. Običajno preverjen TLS uspe; HTTP preusmeri na HTTPS, ta vrne 403.
- V korenu sta samo `php.ini` in `.user.ini` (vsaka 374 bajtov). `common.php` in `plugins/FamilyHub/Plugin.php` ne obstajata. Softaculous prikazuje samo stare `kan`, `test1` in `test2` namestitve Kanboarda.
- Celoten cPanel seznam desetih baz **ne vsebuje `tripar13_jivieprod`**. To ni prazna nameščena baza: produkcijska baza še ni ustvarjena.
- Poštni API uspešno potrdi odsotnost `jivie@triparna.si`; v crontabu ni produkcijskih poti.
- Zasebna priprava še vsebuje stari paket **0.7.0** in pripadajoči pomočnik/manifest. **Ne izvedi te stare dostave.** Nadaljevanje potrebuje pregledano pripravo za aktualni **FamilyHub 0.13.0 / schema17**; spodnja navodila za 0.7.0 so zgodovinska.

Softaculous obrazec je znova pripravljen za Kanboard **1.2.54**, HTTPS koren
`jivie.triparna.si`, skrbnika `jivie_admin`, novo bazo `tripar13_jivieprod` in
izključene samodejne nadgradnje. Geslo je prazno in skrito; uporabnik mora sam
vnesti novo geslo ter oddati Install. Obrazec **ni oddan**. Po tem sledijo
pregled sveže baze, aktualni FamilyHub, zasebne datoteke, SMTP/FCM, opravila v
ozadju in kopija pred prvo registracijo. Native admin prijave pred prvim računom
ne izvajaj, ker bi ustvarila račun in zaprla bootstrap.

Lokalni dokazi: `build/qa/production-readiness-20261013/database-list.png`,
`production-files.png`, `installation-prepared.png`. Nobena gostovana datoteka,
baza ali cron ni bila spremenjena; obrazec je le pripravljen. Android, spletna
stran in testni strežniki ostajajo isti.

## Zgodovinska priprava 9. oktobra

Uporabnik je naročil produkcijski strežnik in izbral **nov naslov s prazno bazo**. Cilj je `https://jivie.triparna.si/`; računov, prostorov, podatkov ali dostavnih vrst iz `jivie-test.triparna.si` ne prenašamo. Testni strežnik in stari `kan.triparna.si` ostaneta ločena. Začetni dostop ostane prek prve kode in poznejših povabil, brez odprte registracije. To je namestitev v sedanjem načinu `self_hosted`, ne uvedba plačljive storitve.

## Dejansko izvedeno

| Področje | Preverjeno stanje |
| --- | --- |
| Nova poddomena | cPanel potrdi `jivie.triparna.si`, lasten document root `/home/tripar13/jivie.triparna.si`; ne deli `public_html`. |
| HTTPS | AutoSSL Domain Validated za osnovni in `www` naslov, prikazani potek 7. januarja 2027. Vključen Force HTTPS Redirect samo za novo domeno. Javni HTTPS HEAD z običajnim preverjanjem certifikata uspe; prazen document root vrne HTTP 403. To še ni delujoča aplikacija. |
| Zasebni mapi | `/home/tripar13/private/jivie-production` in podmapa `install`, obe dejansko ustvarjeni in preverjeni z načinom 0700 ter kanonično potjo. |
| PHP CLI | `/opt/alt/php84/usr/bin/php`, PHP 8.4.26; `curl`, `openssl`, `tokenizer`, `pdo_mysql`, `zip`, `mbstring`, `dom`, `gd`, `SimpleXML` so prisotni. Spletni PHP in dostop do nove zasebne konfiguracije še čakata namestitev. |
| Vtičnik | Lokalni `build/releases/FamilyHub-0.7.0-source.zip` ima 63 dovoljenih datotek in bajtno ustreza trenutnemu izvoru ter javni dokumentaciji. Ne vsebuje konfiguracije ali podatkov strežnikov. Namestitev in migracija še nista izvedeni. |
| Zasebna dostava | ZIP, `manifest.json` in `deploy-cpanel-production.php` so prek cPanel File Manager dejansko naloženi v zasebni `install`. Oddaljeni PHP je preveril vse tri SHA256 in dovoljenja 0600. Pomočnik še ni zagnan; paket ni razširjen v spletni koren. |
| Kanboard obrazec | Pripravljen Softaculous 1.2.54, HTTPS, koren nove domene, skrbnik `jivie_admin`, predlagana baza `tripar13_jivieprod`, brez samodejnih nadgradenj. Geslo je prazno; obrazec še ni oddan. Baza zato še ni potrjena kot ustvarjena. |
| Poštni obrazec | Pripravljen nov predal `jivie@triparna.si`, 100 MB. Obstoječi testni predal ostane pri miru. Geslo je prazno; ustvarjanje še ni potrjeno. |

Posnetki preverjenega stanja so v lokalni mapi `build/qa/jivie-production/`: `domain-created.png`, `tls-ready.png`, `install-password-pending.png`, `mail-password-pending.png`, `package-uploaded.png` in `private-package-verified.png`. Posnetki in statusne ugotovitve niso dokaz dokončane namestitve.

Kontrolni vsoti pripravljene dostave:

```text
FamilyHub-0.7.0-source.zip
1f201bb6c44c269af081bf629236db815fae3bf5518e8a1913f4a2c6f0bd67ba

manifest.json
0e05619fbcbd33921c3c2a7a29d7b79ddc1f15785791f2ae77c5e076acf23bb1

deploy-cpanel-production.php
4dee0bbcf09aeb86dac24e1798efea7656ec5f6438e77e0132ed918eb4bfc883
```

Vir manifesta je `build/qa/jivie-upgrade/cpanel-upload/manifest.json`; vsebuje inventar javnega vtičnika, ne prejšnje baze ali skrivnosti. Pred vsakim izvajanjem preveri dejanske oddaljene vsote. Lokalni testi paketorja: **10 PASS** (`python3 -m unittest discover -s tools/plugin_release -v`).

Produkcijski pomočnik je neodvisno pregledan in preverjen z **194 kontrolami PASS** v izoliranem vsebniku brez omrežja; ponovitev glavnega agenta potrdi isti rezultat. PHP lint je uspešen. Testi vključujejo zavrnitev napačnega cilja, spremembe konfiguracije/paketa ter delne priprave in aktivacije, brez prepisovanja. To so preizkusi sintetičnih datotek, ne dokaz delovanja nove žive baze. Priprava ne spreminja Flutter kode, različice aplikacije ali testnega strežnika.

## Zgodovinski načrt namestitve z 9. oktobra

1. Lastnik v odprtih obrazcih zasebno določi in shrani ločeni močni gesli za `jivie_admin` in `jivie@triparna.si` ter sam odda **Install** oziroma **Create**. Pravila upravljanja brskalnika zahtevajo uporabnikov vnos in potrditev novih gesel. Gesel ne pošilja v klepet.
2. Preveri uspešno novo namestitev, dejanske DB ime/gonilnik, različico Kanboarda ter odsotnost projektov, opravil in FamilyHub tabel. Dovoljen je samo začetni skrbnik z zasebno nastavljenim geslom. Preveri inventar vseh document rootov računa; zasebna mapa ne sme ležati pod nobenim. Uvedi vzdrževanje samo na novi domeni in dejansko preveri HTTPS 503.
3. Uporabi ločeni [produkcijski pomočnik](../../server/scripts/deploy-cpanel-production.php) po [njegovih navodilih](PRODUCTION_INSTALL_HELPER.md). Stara `deploy-cpanel-fresh.php` in `setup-cpanel-smtp.php` imata fiksne testne poti in **nista produkcijska namestitvena ukaza**. Produkcijski pomočnik ohrani DB poverilnice in izvorne datoteke, pripravi zasebna konfiguracijo ter `DATA_DIR`, preveri paket in ohrani vzdrževanje. Potrdilo sveže baze je izjava na podlagi dejanskega pregleda, ne avtomatičen pregled žive baze; ne izpolni ga vnaprej.
4. Preveri PHP sintakso in spletno/CLI berljivost zasebne konfiguracije, nato ločeno izvedi ter potrdi migracijo na FamilyHub **0.7.0 / schema11**. Preveri nov `serverId`, konfiguracijski `FAMILYHUB_ACCOUNT_MODE=self_hosted`, zmožnost izbrisa računa, zasebno sinhronizacijo in izključena stara projektna povabila. Ni razvojnih HTTP izjem, zaupanja v poljubne proxyje ali splošnega CORS. Če sveži Kanboard še nima podatkovnih podmap `files` in `cache`, ju po aktivaciji ustvari v zasebnem `DATA_DIR` z dovoljenji 0700 in preveri zapisovanje; pomočnik kopira samo dejansko izvorno drevo.
5. Dokončaj produkcijski SMTP z novim predalom ter lastnim ključem za šifriranje vrste. Nastavitve in geslo ostanejo zunaj vseh javnih map; datoteke 0600, mape 0700. Šele po preverjenem TLS/prijavi in dogovorjenem prejemniku preizkusi dejansko pošto. Potrditev konfiguracije sama ne dokazuje prejema ali obnove gesla.
6. Za Android FCM uporabi isti Firebase projekt **`jivie-e928a`**, ki ga uporablja trenutna aplikacija, vendar ločeno produkcijsko identiteto/ključ. Predlagani račun je `jivie-production-fcm-sender` z vlogo Firebase Cloud Messaging API Admin. Ustvarjanje novega dostopa in ključa zahteva ločeno potrditev pri dejanju; prejšnje dovoljenje se je nanašalo na testno identiteto. Do takrat FCM ostane izključen. Testne poverilnice se ne kopirajo; APNs je ločen nedokončan korak.
7. Dodaj in preveri samo nove produkcijske crone za opomnike, čiščenje po izbrisu ter vključene dostavne kanale. Testnih cronov ne spreminjaj. Pred realno uporabo pripravi skladno zasebno kopijo baze, datotek in ključev ter preveri obnovo brez omrežja in brez delavcev za dostavo. Prisotnost gumba R1Soft Backups še ne potrjuje intervala, hrambe ali uspešne obnove.
8. Odstrani vzdrževanje šele po ločenem pregledu pripravljenosti. Preveri javni HTTPS Native API, zavrnjen dostop do zasebnih/podatkovnih datotek in čist zagon brez razvojnih ali vzorčnih računov. Prvi račun pripravi po spodnjem vrstnem redu.

## Prvi uporabnik in telefon

**Pred ustvarjanjem prvega uporabniškega računa ne kliči Native `auth.login` s skrbnikom ali testnim uporabnikom.** Takšna prijava ustvari prvi `familyhub_accounts` zapis in s tem zapre začetno registracijo s kodo. Skrbniška prijava v Kanboardov spletni vmesnik je ločena in je dovoljena za nastavitve.

Pravilni vrstni red je skrbniški splet → **Settings → FamilyHub Bootstrap** → enkratna 15-minutna koda → **Prvi račun s kodo** v Jivie na novem URL. Poznejše člane povabi obstoječi uporabnik po podprtem postopku; kod ne zapisuj v repozitorij ali običajne dnevnike.

Nova baza ustvari nov trajni `serverId`. Trenutni odjemalec loči strežnik in račun; sam novi naslov ne zahteva nove Android izdaje. Testna prijava, skupni prostori in dovoljenja ne postanejo produkcijski. Osebni lokalni podatki ostanejo na napravi, njihova sinhronizacija potrebuje izrecno izbiro. Na produkcijskem računu je treba posebej omogočiti oddaljena obvestila in nastavitve prostorov. Prvi dejanski preizkus naj zajame dve napravi, novo dodelitev/opomnik, zaklenjen telefon in klik do pravega zapisa.

## Meje in povrnitev

Ločene baze in poti so na istem cPanel računu; s tem nismo vzpostavili ločenega strežnika ali ločene skrbniške varnostne meje. Trenutni pregled kapacitete je pokazal približno 4,3 GB od 8 GB diskovnega prostora; to ni obremenitveni preizkus ali določitev števila uporabnikov.

Do potrjene namestitve ni novega strežniškega računa Jivie, aktivnega produkcijskega Native API ali dokazane dostave obvestil. Stanje testnega strežnika ne dokazuje produkcijskega delovanja.

Če nova namestitev odpove, ohrani vzdrževanje in ustavi samo njene delavce. Pred začetkom uporabniške uporabe je mogoče pregledano povrniti njeno konfiguracijo iz zasebne kopije; po migracijah je potrebna skladna kopija baze in datotek. Odstranitev vtičnika ne povrne migracije. Delnih stanj pomočnika ne briši in ne prepisuj na slepo; uporabi njegova navodila za ročno obnovo. Nobena povrnitev ne sme izbrisati novih uporabniških zapisov ali poseči v testni/stari strežnik.
