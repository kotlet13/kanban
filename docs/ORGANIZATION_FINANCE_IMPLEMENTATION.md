# Računi prostora in projektni finančni pregledi

17. oktober 2026. Izvedeno po naknadnem izrecnem uporabnikovem naročilu,
s tremi podagenti GPT-6.1 Sol/high in pregledom glavnega agenta.
[Prvotni dogovor](ORGANIZATION_FINANCE_PLAN.md) ostaja osnova obsega.

## Obnašanje aplikacije

Finance organizacije ali gospodinjstva odprejo namenski pregled, v katerem
je mogoče neposredno dodati račun in transakcijo tudi v praznem prostoru.
Odpravljena je zanka »Dodaj v prostor« → izbira iste organizacije.
Račun pripada prostoru. Projektni pregled pokaže svoje prilive in stroške,
ne dodatnega začetnega stanja ali rezerviranega denarja. Projektni proračuni
se s tem ne spreminjajo.

Pregled prostora združi njegove zapise in dovoljene neposredne projekte.
Filtra za račun in projekt delujeta skupaj. Projektni in drugi filtri pokažejo
gibanje; celotno stanje je prikazano samo za popoln ustrezen pregled.
Primer s 1.000 EUR začetnega stanja, splošnim stroškom 50 EUR in projektnim
stroškom 300 EUR pokaže 350 EUR stroškov ter 650 EUR na računu. Projekt
pokaže samo svojih 300 EUR. Vsak strošek obstaja le enkrat.

Projektni član brez članstva v prostoru dobi samo varno izbiro imen računov,
valut in arhivskega stanja. Ne pridobi stanja računa, začetnega stanja,
drugih transakcij, članov ali sorodnih projektov. Ob manjkajočem ali skritem
prispevajočem projektu se celotno stanje ne prikaže. Enako velja za manjkajoče
obvezne podatke povezanih osebnih plačil in povračil.

Dodajanje računa iz projekta s staršem odpre starševski obrazec samo ob
ustreznih pravicah; sicer pojasni potrebo po računu prostora. Stari projektni
računi ostanejo ločeni in označeni. Ni združevanja po imenu, prepisovanja
začetnih stanj ali samodejne migracije zgodovine. Urejanje, revizijska sled,
opomniki in povezave na opravila ciljajo izvirni obseg in izvirni ID.

Lokalni prostori uporabljajo obstoječi račun istega lokalnega prostora in
projektni filter. Ob izrecni poznejši vključitvi sinhronizacije nova pogodba
objavi račun le v staršu, projektne stroške pa kot kanonične projektne zapise
s sklicem na ta račun. Obstoječe že objavljene strukture se ne prepisujejo.

Obstoječa mesečna pravila ostanejo dostopna v zložljivem razdelku načrta.
Nova čezobsežna mesečna pravila niso del te faze; projektni zapisi podpirajo
običajne prilive/stroške in vezane stroške opravil. Objava lokalne vsebine
z nepodprto čezobsežno ponovitvijo se vidno zavrne, brez izgube izvirnika.

## Podatki in združljivost

[Finance4 pogodba](server/ORGANIZATION_FINANCE_API.md) uporablja finančne
zapise različice3 z `accountScopeId` in `projectId`. Projektni zapis ostane
v projektu; starš prejme signal osvežitve. Predpomnilnik varnih izbir je
vezan na identiteto, projekt in revizijo dostopa. Pozni odgovori po odvzemu
ali menjavi računa ne obnovijo skritih podatkov.
Popolnost zahteva strežniški seznam prispevajočih projektov in njihove
zahtevane finančne sequence vrednosti. Stari popolni otroški posnetek ni
dovolj po novejši spremembi. Če je strežnik odstranil zadnjo povezavo,
zastarela lokalna knjižba prav tako prepreči prikaz popolnega stanja.

Stare operacije ohranijo svoje telo, ID in pogodbo. Izgubljeni odgovor in
ponovitev ne ustvarita druge knjižbe. Prva v3 povezava zaščiti starša in
projekt pred nezdružljivim starejšim odjemalcem. Starejši strežnik v novi
aplikaciji še omogoča obstoječe finance, nove povezave pa zahtevajo nadgradnjo.
Finance3 osebni predujmi/povračila ostajajo ločena pogodba; v3 strošek z
neposrednim računom starša se ne pretvori še v osebni predujem.

Prenosna šifrirana kopija je različice8; lokalna baza ostaja različice10.
V3 povezave in nespremenjene čakajoče operacije ostanejo obnovljive, kopije1–7
ostanejo berljive. Izbire računov in dovoljenja se ne prenašajo kot nova
pravica. Skupno delo ostane v šifrirani karanteni do izrecne obnove z istim
računom in svežimi pravicami. Pri ločeni obnovi v lokalne prostore se sklic
preslika na en obnovljen račun starša. Če projektna kopija starševega računa
ne vsebuje, se denar ali račun ne izmisli: gibanje ostane brez računa,
lokalna kopija je označena kot finančno nepopolna, izvirno delo pa ostane
v šifriranem arhivu.

## Preverjanje in meje

Ciljni testi pokrivajo seštevanje, valute, enake ID-je različnih obsegov,
arhive, nedostopne prispevajoče projekte, omejene projektne izbire, izgubljeni
odgovor, objavo lokalnega prostora ter šifrirano kopijo in obnovo.
Dejanska ozka prikaza prostora in projektnega člana sta vizualno pregledana
v `build/qa/organization-finance/parent-390.png` in `project-only-390.png`.
To sta sintetična widget prikaza, ne preizkus nameščene aplikacije.

Končni rezultati (sklopi se deloma prekrivajo, zato številk ne seštevamo):

| Preverjanje | Rezultat |
| --- | --- |
| Devet UI sklopov in projekcija prostora | 104 PASS, od tega 12 projekcijskih |
| Osem podatkovnih/regresijskih sklopov | 72 PASS |
| Zaključni odjemalec in stroški opravil po popravku enakega UUID računa | 24 PASS; vključuje 13 novih odjemalskih primerov |
| Kopije, validacija in predogled | 26 PASS ter dodatna obnova enega starševskega računa PASS |
| Združljivost kopij1–7 po zadnji dopolnitvi | PASS |
| Obstoječi repository varnostnih kopij | 4 PASS |
| FamilyHub: osem sklopov na SQLite/MariaDB/MySQL | 1506 kontrol PASS |
| PHP lint | 20 datotek PASS |
| Celotni Flutter analyze | 10 predhodnih info v tools/release, brez novih opozoril ali napak |

Zaključna dnevnika sta `build/qa/organization-finance/final-ui-projection.log`
in `final-analysis.log`; podatkovna sta `data-regressions-final.log` in
`task-scope-collision-final.log`. Strežniška matrika z razčlenitvijo je v
[API zapisu](server/ORGANIZATION_FINANCE_API.md#preverjanje).
Pregledani so tudi dejanski ohranjeni payload/ID izgubljenega odgovora,
novi račun starša pred projektnim push ter izrecna menjava med lastnim in
starševskim računom z enakim UUID. `git diff --check` je čist.

Ni spremembe SDK, odvisnosti, dovoljenj, različice aplikacije ali nove native
gradnje. FamilyHub razširitev ne potrebuje DDL, potrebuje pa usklajeno novo
strežniško kodo. Gostovanja, javni paket FamilyHub in trgovini v tem naročilu
niso spremenjeni. Pred javno izdajo je treba opraviti
[korake v novem strežniškem dokumentu](server/ORGANIZATION_FINANCE_RELEASE_PREREQUISITES.md).
Obstoječa objavljena/naložena aplikacija31 te nadgradnje ne vsebuje.
