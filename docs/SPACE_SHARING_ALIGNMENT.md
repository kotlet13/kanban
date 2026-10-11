# Deljenje celotnega prostora ali posameznega projekta

**Poznejši izdajni korak:** commit/push 70f6113, testni FamilyHub 0.11.0/schema15,
aktivna interna Android 1.3.0 (15) in podpisana Mac 1.3.0 (15) so preverjeni.
[Dokazi izdaje](release/SPACE_SHARING_RELEASE.md) nadomestijo spodnje zgodovinsko
stanje »lokalno«. Doma še uporablja staro politiko do lastnikovega predogleda in
potrditve; fizično urejanje med napravama še sledi.

## Potrjena odločitev — 10. oktober 2026

Uporabnik je po dejanskem sprejemu povabila v Doma popravil preozko razumevanje
članstva. Ta odločitev nadomesti starejšo matriko, kjer običajni član organizacije
ni dobil dostopa do njenih projektov. Nato je izrecno dodal: **člani lahko delajo
vse** znotraj vsebine, ki jim je deljena.

| Povabilo | Dovoljena vsebina | Pravice člana |
| --- | --- | --- |
| Celoten prostor: gospodinjstvo ali organizacija | Skupna vsebina in finance prostora, vsi njegovi obstoječi in prihodnji projekti ter njihove vsebine. | Ustvarjanje, branje, urejanje, brisanje, finančni vnosi, povabila in upravljanje članov/nastavitev znotraj tega prostora. |
| Samo projekt | Ta projekt ter njegova opravila, dogodki, obvestila in finance. | Enake polne pravice znotraj tega projekta; brez pravic nad nadrejenim prostorom ali drugimi projekti. |

Obseg deljenja in identiteta lastnika sta ločena. Članstvo ne daje pravic do
drugih računov, zasebnih osebnih podatkov, osebnih plačilnih računov ali
strežniške administracije. Lastnik ostaja sledljiva identiteta; zaščita pred
odstranitvijo zadnjega lastnika ter izrecni postopki prenosa lastništva in izbrisa
uporabniškega računa ostanejo. Ne uvajamo nove vloge upravitelja ali dodatnega
finančnega dovoljenja za običajnega člana novega modela. Stara članstva samo za
branje se ne pretvorijo tiho v polne pravice.

Projektni prejemnik vidi deljeni projekt v izboru. Zaradi tega ne postane član
organizacije/gospodinjstva. Če ima hkrati več veljavnih članstev, velja njihov
skupni dovoljeni obseg. Odvzem članstva prostora odstrani izpeljane pravice,
samostojno projektno članstvo pa lahko ostane. Dostop in preference obvestil sta
ločena: članstvo ne vključi samodejno vsake e-poštne ali potisne dostave.

## Izvedbeni pristop

- Nova različica politike deljenja 3 in strežniško oglaševanje podpore; stare
  politike 1/2 in že shranjene odhodne operacije ohranijo prejšnjo razlago.
- Nova e-poštna pogodba povabil 3 izrecno opiše prostor oziroma projekt in
  polne pravice. Povezave v1/v2 ostanejo berljive za še veljavne stare tokove.
- Nova skupna prostora nastaneta s politiko 3. Obstoječa potrebujeta svež
  lastnikov predogled prejemnikov ter razširjenih pravic branja/urejanja.
  Starih povabil se pri prehodu ne razlaga kot novih širših povabil.
- Projekti gospodinjstva dobijo enako ločeno mejo dostopa kot organizacijski
  projekti. Dodana vez na nadrejeni prostor ohrani stari `organizationId`.
- Stare gospodinjske projekte, zapisane neposredno v gospodinjstvu, je mogoče
  ločiti le s predogledom in atomarnim prenosom zaprtega sklopa odvisnosti.
  Prenos ne sme izpostaviti skupnega finančnega računa drugih projektov,
  njihovih stanj, osebnih podatkov ali medsebojnih finančnih povezav. Neločljive
  odvisnosti so izrecna ovira prenosa, ne razlog za širše povabilo. Čakajoče
  operacije in konflikti se pred prenosom razrešijo; starih teles/ID-jev operacij
  ne prepisujemo.
- Pravila veljajo v strežniških bralnih in zapisovalnih metodah, seznamih
  prostorov in članov, dodelitvah, financah, zgodovini, izvozu, obvestilih in
  lokalnih projekcijah. Samo skrit gumb ni omejitev dostopa.
- Local-first, trajni podatki brez strežnika, identitete, šifrirane kopije in
  obravnava potrjenega preklica ostanejo ohranjeni.

## Preverjanje

Preverimo vsaj tri račune: lastnika, polnega člana prostora in sodelavca samo
enega projekta. Polni član vidi in ureja stare ter nove projekte in finance;
projektni sodelavec lahko upravlja svoj projekt, strežnik pa zavrne branje in
spreminjanje sorojenca/nadrejenega prostora. Preverimo tudi dvojno članstvo,
preklic, izgubljene odgovore, novega člana med spremembo pravic, zastarel
predogled, stare aplikacije/povabila, obvestila in dodeljevanje opravil.

Pri gospodinjstvu preverimo ločitev obstoječega projekta z opravili, dogodki in
ločljivimi financami ter zavrnitev odvisnosti, ki presegajo projekt. Nepovezano
čakajoče delo in zasebni podatki se ne izgubijo. Mobilni in namizni prikaz morata
jasno pokazati obseg; upravljanje članov ostane v Nastavitvah prostora.

## Stanje

Pred začetkom je bil izveden commit **0cdf468** in push na
`origin/codex/email-invitations`, s prejšnjimi povabili po e-pošti in kompaktnim
prikazom sinhronizacije. Nova uskladitev je izdelana v odjemalcu in izvoru
FamilyHub **0.11.0/schema15**; natančen API določa
[pogodba deljenja](server/space-sharing-api-contract.md).

Nov skupni prostor uporablja novo politiko. Pri obstoječem prostoru lastnik v
Nastavitvah prostora pregleda dodatne prejemnike pravic ter preklic še čakajočih
starih povabil. Nova registracija še vedno ne pomeni sprejema povabila.
Uporabnik z obema članstvoma vidi oba izvora pravic. Samostojno projektno
članstvo oziroma lastništvo ostane tudi po izgubi članstva nadrejenega prostora.

Za stare samostojne prostore vrste projekt mora predogled potrditi en projektni
koren in skladen graf zapisov. Stari gospodinjski projekt se loči po predogledu
zapisov, finančnih računov z začetnim stanjem, oseb z zapiski ter opomnikov.
Skupne odvisnosti, ki presegajo projekt, prenos ustavijo. Izgubljen ali poškodovan
odgovor ohrani trajno oznako postopka in možnost nadaljevanja; medtem so novi
zapisi v prizadeta obsega blokirani. Izvirne odhodne operacije se ne prepisujejo.

Gostovana testna namestitev ostaja **0.10.0/schema14**, produkcija in trenutno
odprta podpisana Mac aplikacija ostanejo nespremenjene. Nova uskladitev še ni
objavljena v trgovini ali nameščena na gostovanju; dejanski preizkus nove politike
na uporabnikovih dveh napravah še sledi. Odjemalec ostane **1.2.0+14**, brez
spremembe SDK-ja, odvisnosti, podpisovanja ali platformnih identitet. Predhodni
commit je poslan; nove spremembe te uskladitve so trenutno lokalne.

## Dokazi končnega preverjanja

- **947 Flutter PASS / 13 opt-in preskočenih** v celotni zbirki. Po zadnjih
  slogovnih popravkih še **15 ciljnih UI/provider testov PASS**.
- Analiza: **0 napak, 0 opozoril, 35 podedovanih info**. Novi slogovni očitki so
  odpravljeni; izhodni status analizatorja ostane 1 zaradi podedovanih info.
- **Dejanski Dart/HTTP test PASS** z lastnikom, članom prostora in projektnim
  članom na izoliranem `127.0.0.1:18384`: gospodinjstvo in organizacija, finance,
  prihodnji projekti, zavrnitev nadrejenega/sorodnega prostora, preklic, zastarel
  predogled, izgubljen odgovor, nespremenjena čakajoča operacija ter ponovno
  odprta datoteka SQLite brez strežnika in novo lokalno opravilo.
- Strežnik: **2505 preverjanj PASS** na SQLite, MySQL in MariaDB; 17 zbirk na
  bazo, vključno z zadnjo delitveno zbirko **105 PASS na bazo**. Preverjena so tudi
  obvestila, opomniki, podedovana dovoljenja, finance, izbris/prenos lastništva,
  stara povabila in prepoved znižanja nove politike s starim odjemalcem.
  **111 PHP lint PASS**. Zadnji usmerjeni popravki ohranijo notranji finančni
  prenos in ločijo vrsto tarče ob enakem UUID-ju opravila ter finančnega zapisa.
- Android debug APK in web release sta uspešno zgrajena. To ni podpisana
  distribucijska izdaja ali dokaz fizičnega preizkusa novega vedenja.
- Deset testov izdelave paketa PASS; seznam dovoljenih datotek vtičnika se ujema
  z izvorom. Svež omrežno izoliran vsebnik potrjuje izključene privzete API-je.

Pripravljen je `build/releases/FamilyHub-0.11.0-sharing-source.zip` s 80 vhodi;
ponovljena izdelava je bajtno enaka, CRC in vsak vhod se ujemata z izvorom.
SHA256: `d6f0b91c7fe539442ee6b0b84c017e14ee5fd23801aecc0a26f9b451f456288f`.
Paket ne vsebuje konfiguracij, gesel, zgodovine Gita ali baze. Izdelava paketa
ni namestitev; pred gostovano nadgradnjo ostajata zahtevana varnostna kopija in
preverjena obnova po obstoječem cPanel postopku.

Dnevniki odjemalca in izolirani HTTP dokaz so v
`build/qa/space-sharing-20261010/`; strežniška matrika, povzetek števcev in PHP
lint so v `build/qa/space-sharing/`. Zasebne testne poverilnice imajo pravice 0600
in ostanejo zunaj Gita. Obe mapi vsebujeta lokalne dokaze, ne produkcijskih
uporabniških podatkov.

## Ponovitev dejanskega HTTP preizkusa

Uporabi sveže namensko ime Docker projekta in neuporabljen izhod. Primer za
prosta vrata 18384:

```sh
python3 server/scripts/start-account-http-fixture.py \
  --project kanban-familyhub-account-sharing-check \
  --port 18384 \
  --output build/qa/sharing-check/account.json
docker exec kanban-familyhub-account-sharing-check-kanboard-1 \
  php /familyhub-tests/space-sharing-http-seed.php 18384
docker cp kanban-familyhub-account-sharing-check-kanboard-1:/tmp/space-sharing-http-fixture.json \
  build/qa/sharing-check/space.json
chmod 600 build/qa/sharing-check/space.json
KANBAN_SPACE_HTTP_FIXTURE="$PWD/build/qa/sharing-check/space.json" \
  flutter test --no-pub test/organizer/data/space_access_http_test.dart
docker compose -p kanban-familyhub-account-sharing-check \
  -f server/compose.account-tests.yaml down
```

Ustvari se samo lokalna sintetična SMTP/računska namestitev. JSON z gesli se ne
izpisuje ali vključuje v izvor. Za PHP matriko uporabi
`python3 server/scripts/test-space-sharing-matrix.py` nad tremi obstoječimi
razvojnimi vsebniki.
