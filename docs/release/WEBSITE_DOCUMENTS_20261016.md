# Spletna zasebnost in pomoč — objava 16. oktobra 2026

**Štiri strani so dejansko objavljene.** Pregledani postopek na gostovanju je
potrdil `published=true` in `backupVerified=true`: zasebna kopija vsebuje vseh
25 datotek, nameščeni so štirje HTML, drugih 21 datotek ter vse pravice in
lastništvo so ohranjeni. Ločen sveži HTTPS zajem vseh štirih javnih strani je
vrnil 200 in bajtno ujemanje s pregledanim payloadom. DNS, aplikacijski paket
in uporabniški podatki niso del te spletne objave.

Pregledane so štiri spremembe generatorja [build_site.py](../../website/build_site.py):
SL/EN zasebnost in pomoč. Ujemajo se s trenutnim izvorom:

- Prenosna kopija ohrani samo podprte lokalne osnutke preglednic za vključene
  obsege; ne obljublja kopije celotnih strežniških preglednic, zaklepov ali
  dokumentnih datotek. Strežniška kopija mora vključevati bazo in zasebne datoteke.
- Dokumentne priloge ohranijo izvirne bajte in vgrajene metapodatke; fotografije
  Idejnika se ločeno normalizirajo. HTTPS in zasebna hramba nista šifriranje
  od pošiljatelja do prejemnika.
- Prijava preglednice vsebuje omejen izbor celic in hash; prijava priloge
  vsebuje metapodatke in kontekst, brez bajtov dokumenta. Skrbnik prejme
  izrecno pregledano prijavo na izbranem strežniku.
- Manjkajoče nastavitve vključijo zvok, push in prikaz v aplikaciji; e-pošta
  ostane izključena. Že shranjeni izrecni izklopi imajo prednost.
- Pomoč opisuje deljenje iz prostora, username/e-poštni tok, ločen sprejem,
  sinhronizacijo ob ustvarjanju ter urejanje preglednic s povezavo in zaklepom.

Dokazi teh podatkovnih poti so v `portable_backup_tables.dart`,
`NativeAttachmentService.php`, `NativeTableService.php` in
`NativeNotificationPreferences.php`; PHP/odjemalčevi funkcionalni dokazi so
ločeni od te spletne objave.

## Omejen postopek objave

Lokalni artefakti: `build/qa/website-documents-20261016/`.
Javni stari štirje HTML so dejansko preneseni v `before/`; `before.json`
vsebuje HTTPS200, točne URL-je, čas zajema, velikosti in SHA256.
`payload.json` vsebuje natanko:

- `privacy/index.html`
- `en/privacy/index.html`
- `help/index.html`
- `en/help/index.html`

Pregledani helper SHA256:
`cadd717b18c7776a2ffee7514fba03b31b41b916f0486502c4e94204af06368c`.
Payload SHA256:
`f68a864248edb4706ce276d7c3604c8f29c0c92a4622d8c26e3a1c75b0620649`.
`prepared-files.json` in `before.json` sta strojno berljiva manifesta;
`deploy-command.txt` je bil izveden v gostovanem terminalu; dokaz je
`deployment-terminal.png` v istem lokalnem imeniku.

Gostovani cilj ostaja račun `jivie`, koren `/home/jivie/public_html`;
nov zasebni delovni imenik je
`/home/jivie/private/website-documents-20261016` (0700).
Skript in payload sta 0600. Postopek zavrne drug račun, simbolne povezave,
spremenjen payload, že obstoječo izvedbo ali katerikoli od štirih živih HTML,
ki se ne ujema s svežim HTTPS zajemom.

Pred menjavo ustvari celotno zasebno `before-public_html.tar.gz` ter dejansko
prebere vse arhivirane datoteke: primerja bajtne hashe, mode, uid in gid z
izvornim popisom, vključno s korenskim imenikom. Pred namestitvijo ponovno
preveri nespremenjenost spletnega drevesa. Vsi štirje novi HTML se najprej
pripravijo na istem datotečnem sistemu s prvotnimi pravicami in lastništvom;
nato se posamično atomarno zamenjajo. Končna primerjava zahteva iste bajte,
pravice in lastnike vseh drugih datotek ter vsebino natanko štirih sprememb.
Ob delnem neuspehu obnovi že zamenjane datoteke iz preverjenega arhiva.

Lokalna sintetična vaja ima **5 uspešnih kontrol**: dejansko preverjen tar,
ohranitev drugih datotek/pravic/lastništva, zavrnitev spremenjenega živega
HTML, zavrnitev spremenjenega payloada ter obnova po napaki druge zamenjave.
`rehearsal.json` jasno označi, da ne gre za gostovano kopijo ali objavo.
Python prevajanje helperja je uspešno.

## Dokaz dejanske objave

Pristni gostovani zapis `build/qa/website-documents-20261016/deployment-live.json`
potrjuje preverjeno zasebno kopijo
`/home/jivie/private/website-documents-20261016/before-public_html.tar.gz`, SHA256
`37f89d016beaa1a99ecd8f38641a1c8e163db589721e197f3d5042eb77f0005b`,
25 datotek ter uspešno namestitev samo štirih datotek in ohranitev drugih 21.
Kontrola arhiva je primerjala dejanske bajte, pravice in lastništvo; končna
kontrola je potrdila ohranitev vseh pravic in lastnikov.

Neodvisno preverjanje 16. oktobra ob 10:53 UTC je shranjeno v
`build/qa/website-documents-20261016/live-verification.json`; preneseni dejanski
HTML so v `live/`. Vseh štirih HTTPS200 odgovorov se ujema s payloadom:

| Javna stran | SHA256 |
| --- | --- |
| [SL zasebnost](https://jivie.app/privacy/) | `cf9d48bb3f26b078b5dc5e7a96ba5ad06bb7f83b16d9dcdd9884ee9e2c0229f8` |
| [EN privacy](https://jivie.app/en/privacy/) | `48968596ebfdc0d0460a68ebd371b10fd6e5e51f407a72dfe3dfa309b445c7d4` |
| [SL pomoč](https://jivie.app/help/) | `b342d56f83d45367127f737374942101df8d8974fb1a403abd2cb6e8197feed3` |
| [EN help](https://jivie.app/en/help/) | `8ea25fb285d8706f301c10070677dffb54abfb8f88e6cca9a160256fb6ee9cef` |

Gostovani dokaz izvira iz shranjenega pristnega `deployment-live.json` in
dejanskega terminalskega izpisa glavnega agenta;
javni bajti so bili preverjeni ločeno po objavi. Ta korak ne potrjuje
trgovinske oddaje ali nadgradnje strežnika FamilyHub.
