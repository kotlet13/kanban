# Jivie produkcija na TriparNA

Stanje: **9. oktober 2026 — priprava, še ni pripravljeno za uporabniške račune**.

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

## Nadaljevanje namestitve

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
