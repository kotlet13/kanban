# Lokalni arhiv starega Kanboarda

Namen je ohraniti obstoječe strežniške podatke neodvisno od nove aplikacije. Arhiv ni uvoz v lokalni organizator in ne pomeni upokojitve produkcije. Stara aplikacija lahko med razvojem še deluje; spremembe po času zajema zahtevajo novo kopijo pred končnim preklopom.

## Zajem 4. oktobra 2026

Uporabnik je izrecno določil, da je za nadaljnjo gradnjo bistvena arhivska kopija vseh obstoječih strežniških podatkov. Prek obstoječe prijavljene seje cPanel/Softaculous sta bili izbrani možnosti **Backup Directory** in **Backup Database**, cilj **Local Folder**. Nastala kopija je bila prenesena na uporabnikov računalnik, zunaj repozitorija. Na produkciji niso bili spremenjeni projekti, naloge, konfiguracija ali vtičniki. Izdelana je bila ena varnostna kopija; gostovanje jo po svojem pravilu odstrani po sedmih dneh, lokalni prenos od tega ni odvisen.

| Preverjanje | Rezultat |
| --- | --- |
| Čas kopije | 2026-10-04 19:10:54, Europe/Ljubljana (+02:00) |
| Arhiv | 6.189.615 bajtov, 2.484 zapisov, 17.144.066 nestisnjenih bajtov |
| SHA256 arhiva | `c6757996d5fb533f06a6a28200869869d4015d8ef5fcb29ea0817ae19c15d9e8` |
| Izvor | Kanboard 1.2.54; `DB_DRIVER=mysql`; glava SQL izvoza navaja strežnik 10.11.19 in PHP 8.4.25 |
| Lokalna obnova | SQL uspešno obnovljen v MySQL 8.4.11, izoliran Docker brez omrežja ali objavljenih vrat |
| Celotna baza | 48 tabel, 2.180 vrstic |
| Projekti/opravila | 17 projektov; 196 opravil, od tega 95 odprtih in 101 zaprto |
| Drugi zapisi | 45 podopravil, 954 projektnih aktivnosti, 51 projektnih metapodatkov; nič komentarjev in nič zapisov notranjih/zunanjih povezav nalog v tem zajemu |
| Priponke | 3 projektne in 5 opravilnih; vseh 8 prisotnih, velikosti in SHA256 preverjeni |
| Druge datoteke podatkov | 7 sličic v izvirni kopiji in popisu datotek |
| Stara finančna tabela | Vsi 23 deli prisotni; izvirne vrednosti in sestavljena vsebina ohranjene brez normaliziranja |

Neodvisno preverjanje je primerjalo vseh 48 tabel/2.180 vrstic, sheme, surove izvožene celice, vseh 24 finančnih metapodatkov (marker in 23 delov) ter kontrolne vsote priponk. Primerjava se je ujemala. Celotna izvirna kopija ostaja avtoritativni vir; brskalniški prikaz je redigirana projekcija za branje.

## Ločeni deli arhiva

```text
<zasebna-mapa-zajema>/
  kanboard....tar.gz          Nespremenjena kopija gostovanja
  SHA256SUMS.txt              Kontrolna vsota izvirnika
  original/                  Baza, aplikacijske datoteke, konfiguracija, data/files
  private-export/            Vse tabele, sheme in surove izvožene celice
  browse/                    Samostojen brskalniški prikaz in preverjene priponke
    index.html
    viewer.js, viewer.css
    archive-data.js
    archive-data.json
    manifest.json
    attachments/
  capture-report.json        Podatki o izvoru in obnovi
  attachment-verification.json
```

Celotna kopija vsebuje tudi prijavne in konfiguracijske podatke. Zasebne mape imajo lokalna dovoljenja 0700, datoteke 0600; to ni dodatno šifriranje. Ne dodajaj jih v Git, ne pošiljaj jih AI ponudniku in ne ponujaj izvirnika ali zasebnih tabel prek spletnega strežnika. Mapa `browse` ne vsebuje strežniške konfiguracije, gesel, sej ali trajnih žetonov. Manifest izrecno navede izpuščene tabele in redigirana polja; izvirniki ostanejo v zasebnem delu.

## Izvoz in pregled

Orodje je v [`tools/legacy_archive`](../tools/legacy_archive/). Bere že obnovljeno lokalno kopijo; ne prijavlja se na produkcijo, ne kliče njenega API in ne izvaja PHP iz varnostne kopije. Za MySQL uporablja dejanski lokalni podatkovni pogon, ne lastnega razčlenjevalnika SQL. Izvoz ne prepisuje obstoječega arhiva.

Pregledovalnik vsebuje projekte, odprte/zaprte naloge, podrobnosti, podnaloge, komentarje, povezave, priponke, finančne metapodatke in poslovne tabele. Zapisi so prikazani kot besedilo; zunanja vsebina se ne nalaga avtomatsko. Surova finančna tabela se ohrani tudi, kadar je ni mogoče varno dekodirati. Brskalnik ne izračunava nove finančne projekcije in arhiva ne spreminja.

Statični paket je pripravljen za lokalno odpiranje `browse/index.html`: podatki so v priloženem JavaScriptu, zato ni zahtev `fetch`, CDN ali povezave s Kanboardom. Vgrajeni avtomatizacijski brskalnik ne dovoljuje protokola `file://`; vizualni preizkus zato poteka prek omejenega loopback predogleda. Neposrednega odpiranja datoteke v uporabnikovem privzetem brskalniku s tem ne predstavljamo kot avtomatsko preverjenega.

Končno preverjanje: 26 uspešnih Python testov (vključno z dejanskim izoliranim MySQL) in 12 JavaScript testov pregledovalnika. V brskalniku so preverjeni resnični projekti, iskanje, filtriranje zaključenih nalog, podrobnosti, vseh šest finančnih razdelkov in poročilo zajema. Prenesena priponka se po SHA256 ujema z izvirnikom. Telefonski predogled pri 390 px in namizni prikaz nimata vodoravnega prelivanja; konzola nima opozoril ali napak. Začasni MySQL za obnovo je po preverjanju ustavljen, datoteke arhiva ostanejo neodvisne od njega.

## Meje popolnosti in upokojitev

- Zajeto je trenutno ohranjeno stanje strežnika ob izdelavi kopije. Prej izbrisanih nalog, datotek ali že očiščene zgodovine ni mogoče poustvariti iz tega zajema.
- Kopija datotek in SQL nista dokaz, da med celotnim postopkom ni bilo sočasnih uporabniških zapisov. Pred končno upokojitvijo dogovorimo konec urejanja, ponovimo zajem in preverjanja.
- Uspešna obnova SQL v MySQL 8.4.11 je preverjanje podatkovne kopije, ne preizkus polnega zagona stare PHP aplikacije na izvornem pogonu 10.11.19.
- Arhiv se ne zlije samodejno z novim organizatorjem. Izbrani projekt lahko pozneje postane predloga ali dobi sledljiv uvoz z novimi ID-ji; finančnih načrtov ne pretvarjamo tiho v dejanske transakcije.
- Produkcija in stari projekti s tem korakom niso izbrisani ali izključeni.
