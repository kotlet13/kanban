# Pregledni strežnik in Googlova navodila — 13. oktober 2026

**`jivie-test.triparna.si` je dejansko FamilyHub0.13.0/schema17.** Nadgradnja
je bila odprta ob približno19:39; isti pregledni račun `jivie_review` je na Macu
ohranjen in ob19:48 kaže Usklajeno/0 čakajočih/0 spornih/0 zadržanih sprememb.
Navodila v Google Play Console so dokončno shranjena in ponovno odprta za
preverjanje. Android1.7.0(25) in njegov AAB ostajata ista. Ni javne oddaje.

## Kopija, obnova in namestitev

Prijava v cPanel tripar13 je uspela po običajnem samodejnem izpolnjevanju brez
branja gesla. Preflight potrdi pravi serverId
`95c11fe0-916c-48be-a3f6-999732846266`, bazo `tripar13_jivietest`, schema15,
83 starih datotek in GD PNG/JPEG encode/decode na PHP8.4.26.
Obstoječa root konfiguracija je mode0600; DATA je zunaj javne mape.
Test1 uporablja svoj obstoječi SMTP/FCM, zato varovala ne kopirajo konfiguracije
test2, kjer sta oba izključena.

[Ločeni pomočniki](../../server/scripts/reviewer-test1/README.md) ciljajo samo ta
strežnik. Pozitivni sintetični preizkus pokriva poln neprazen Kanboard/MariaDB,
dejansko izolirano obnovo, migraciji15→17, ohranitev in odprtje; pet negativnih
varoval PASS. Pred vzdrževanjem je varovalo dvakrat zavrnilo napačno ročno
prepisan hash `.htaccess`. Pravilni hash je nato prebran skozi običajni File
Manager View, popravljen samo v treh zasebnih pomočnikih in njihovi končni hashi
primerjani z lokalnim izvorom. Stran/baza/cron v teh zavrnitvah niso spremenjeni.

Mac je pred vzdrževanjem običajno zaprt brez odjave. Točno pet test1 delavcev
je začasno komentiranih; ostale cron vrstice ostanejo. HTTPS503 je dejansko
potrjen in pred zajemom mine najmanj65 resničnih sekund. Svež pregled procesov
ter READ zaklepi vseh InnoDB tabel preprečijo sočasne zapise med kopiranjem.

Nova kopija ima **53.216 bajtov**, SHA256
`0a129e65760e4151dd46096d228c94342e7f36c05c0256f266eda4eaa0b51325`.
SQL SHA256 `500e9396d60f988d26d6a6022538c5162557bb038dffb0d54b431ed7a8a31b39`.
Dejansko obnovljena v sveži **MariaDB10.11.19, network=none, brez vrat ali host
bindov, samo anonimni MySQL volume**: **86 tabel,295 vrstic,2 zasebni datoteki,
2 imenika**. Vsi row/CREATE/file/config/HTTPS/cron hashi in števci računov/sej
PASS. Nobena aplikacija ali dostavni delavec ni zagnan. Ta obnovitveni vsebnik
je ustavljen; arhiv, obnova, volume in predhodne kopije ostajajo zasebno.

Staging zahteva prav to novo kopijo/proof in ujemanje vsake trenutne vrstice ter
datoteke. Nameščen je isti preverjeni FamilyHub0.13 ZIP `00df4cec…`,96 datotek.
Končni checkpoint potrdi:

- **92 tabel**, šest natanko določenih novih praznih tabel za pravila/prijave/assets;
- vseh295 starih vrstic in CREATE definicij ohranjenih, edina dovoljena sprememba
  je FamilyHub metadata15→17;
- isti serverId,3 Native računi,7 naprav ter isti geselni/sejni podatki;
- ista konfiguracija, DATA, Kanboard jedro in po odprtju prvotna HTTPS pravila;
- isti bajtni cron ter nespremenjeni SMTP/FCM; dve originalni kopiji vtičnika
  in vsi vhodni paketi/proof so ohranjeni zasebno.

Končni nadgradni pomočnik SHA256:
`03919d47f9d3d6d17a78cfdae0b520f9d8075db761e8188c785a7d5403a312e0`.
HTTPS API po odprtju vrne200/istiID, record1–5 in
**ideas/ideaAssets/contentReporting/sharedContentPolicy=true**.
Javna politika vrne200/policy1. Anonimna `ideas.asset.get` in `sync5.pull`
vrneta401/auth_required. Končni checkpoint ima phase released/apiPaused false.
To ni nov dokaz fizične dostave push/SMTP; nastavitve so ohranjene.

## Pregledni račun in navodila

Mac po ponovnem odprtju ohrani račun, izbrani Review project in vzorčno opravilo.
Deljeni Idejnik se odpre. »Prijavi vsebino« na obstoječem opravilu pridobi dejanski
strežniški predogled z vrsto/revizijo/naslovom/opombo in prejemnikom
FamilyHub server administrator na test1. Predogled in urejevalnik sta preklicana
brez shranitve ali oddaje prijave. Pravila niso sprejeta v imenu uporabnika;
nov deljeni upload še vedno zahteva izrecni sprejem. Nova vzorčna tabla/fotografija
ni objavljena in dejanski admin ukrep ni izveden. To so meje preverjanja, ne
sprememba pravic ali obhod pravil.

Console → Podrobnosti o prijavi → Jivie review account ima isto uporabniško ime,
geslo in strežniški URL. Spremenjena so samo navodila (476/500 znakov):

> Offline: Personal, no login. Shared: More > Account and sharing > Sign in. Server https://jivie-test.triparna.si/; credentials above. Select Review household for shopping/finances or Review project for project/tasks. Planner > Ideas: notes, drawings, photos. Before sharing, read/accept the server rules in the app. Report an item via details > Report content; report a member via People > member menu. No registration, invite code, 2FA, email verification or purchase needed.

Končni Shrani pokaže »Sprememba je shranjena«; ponovno odprti obrazec vsebuje
točno ista nova navodila. Nobena poverilnica ni spremenjena ali izvožena. Poziv
za pregled objavljanja je zaprt z Ne zdaj; nič ni oddano Googlu v celotni pregled.

## Dokazi in nadaljevanje

Dokazi: `build/qa/reviewer-server-20261013/` — fixture/input evidence, dejanski
hosted-export/restore-proof/release-checkpoint, HTTPS endpoint evidence, Mac AX
Idejnik/report/account/sync ter `google-access-evidence.json` in dva posnetka.
Zasebna dejanska kopija je zunaj Gita in javnih map v
`~/.local/share/jivie/backups/reviewer-upgrade-20261013/hosted-173546/`.
Stare enkratne schema15/16 pomočnike ne uporabljaj za bodočo schema17 kopijo.

Android AAB25 SHA256 po koncu je še vedno
`ef909cddea12b22ac3ec9a7c3805a7ed1a55e6cbe3c00368f767799953a27447`.
Android/desktop izvor, SDK, locks, dovoljenja, test2, produkcija in jivie.app niso
spremenjeni. Naslednje je priprava javne izdaje **istega AAB25**, države in končni
Pregled objavljanja; uspešna namestitev sama ni javna objava ali odobritev Googla.
