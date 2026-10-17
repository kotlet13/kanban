# Finance organizacije in projektov — nova izvorna pogodba

17. oktober 2026. Implementacija je v izvornem drevesu; **ni nameščena na
produkciji/test1 in ni objavljen nov paket FamilyHub**. Dokazano gostovano
izhodišče ostaja [0.15.0 / shema19](UPGRADE_0_15.md). Ta razširitev uporablja
obstoječe JSON zapise in stolpce; ne dodaja DDL ali migracije podatkov.

## Pogajanje in združljivost

Capabilities dodaja `features.organizationFinance:true`,
`organizationFinanceContractVersions:[1]` ter `financeContractVersions:[1,2,3]`.
Novi transport je **finance4**, ker finance3 že vsebuje povezane osebne
izdatke/povračila in ostaja ločena pogodba. Finance4 uporablja finančne zapise
`contractVersion:3`. Metode `finance4.policy`, `finance4.pull`, `finance4.push`
in `finance4.audit` ohranijo obstoječe oblike finance2 zahtev/odgovorov,
vključno z `linkedPaymentsAware`, revizijami, cursorjem, avtorjem in revizijsko
sledjo. Nastavitve članstva/omogočanja financ ohranijo obstoječe metode.

Finance4 policy in pull dodajata `organizationFinanceComplete` ter
`organizationFinanceScopeIds` ter `organizationFinanceSequences` (objekt
berljiviID→zahtevani finančni sequence). Strežnik iz vseh živih knjižb, ki ciljajo
račune tega starša, določi prispevajoče projektne obsege. Vrne samo njihove
trenutno finančno berljive ID-je. Če je kateri skrit, nedostopen ali ni več
pravilen neposredni otrok, vrne `organizationFinanceComplete:false` brez
razkritja njegovega ID-ja. Odjemalec zahteva ta true in popoln posnetek vseh
navedenih ID-jev s cursorjem vsaj zahtevane vrednosti; odsotno polje pomeni
nepopoln pregled. Nov parent signal zato ne potrdi starega otroškega posnetka. Tako tudi otrok,
ki nastane med scopes.list in parent policy, ne ustvari lažno popolnega salda.
Izvorni projekt ostane avtoriteta svojih finančnih revizij. Če lokalna
stara knjižba še cilja starša, njen izvor pa je izginil iz njegovega novega
inventarja prispevkov, odjemalec ohrani nepopoln prikaz do pridobitve
projektnega tombstona oziroma nove dodelitve računa. Tako izbris zadnje
knjižbe ne pusti starega zneska v navidezno popolnem stanju.

`finance4.push.operationContractVersion` lahko izrecno določi1/2/3; brez njega
velja3. Izvirna sprejeta v1/v2 operacija se na novem transportu ponovi z istim
nespremenjenim telesom, ID in izrecno prvotno verzijo. Hash uporablja izvirno
pogodbo, zato izgubljeni ACK ne ustvari druge knjižbe. Stara operacija ne more
prepisati novejšega zapisa3. Prva nova v3 operacija dvigne zahtevano finančno
pogodbo obsega; prva povezava s starševskim računom jo dvigne tudi pri staršu.
Finance1/2 pull/audit in nove nesprejete push operacije nato vrnejo
`unsupported_version`. Policy še vedno pove `requiredContractVersion:3`,
da lahko starejši odjemalec varno prepozna potrebno nadgradnjo.

## Kanonična knjižba in račun

`financeEntry` v3 ohrani vsa zahtevana polja finance2 in dodaja dve neobvezni
nullable polji:

- `accountScopeId:null` pomeni račun v kanoničnem obsegu zapisa. Za račun
  neposrednega starša je vrednost njegov točni UUID. Lastnega scope ID ni
  dovoljeno podati kot alternativni zapis za `null`.
- `projectId:null` velja za samostojni projektni obseg, kjer projekt določa
  že njegov scope. V gospodinjskem/organizacijskem obsegu je mogoče navesti
  točni ID obstoječega inline projekta v istem obsegu. Nativni projektni
  obseg zavrne ne-null tag, tudi če bi bil enak njegovemu korenu.

`accountId` in ne-null `ledgerAccountId` označujeta isti račun v izbranem
obsegu; oba ostajata predmet valutnih in arhivskih preverjanj. Opravilo,
osobe, udeleženci ter dovoljenja knjižbe ostanejo v izvornem projektnem
obsegu. Inline tag z vezanim opravilom mora ustrezati projektu tega opravila.
Pri v1/v2 ti novi polji nista dovoljeni. Druge vrste finančnih zapisov
(account, transfer, osebni zapisi, recurrence) ohranijo svojo obstoječo obliko.

Projektni izdatek se shrani **enkrat v projektu**, tudi kadar uporablja račun
starša. Starš dobi signal spremembe finančnega sequence/revision, ne kopije
knjižbe. Projektni pregled uporablja te iste zapise; skupni pregled združi
samo dovoljene kanonične projektne podatke po točnem `accountScopeId`/ID računa.
Dokler niso dosegljivi in osveženi vsi potrebni dovoljeni projektni finančni
posnetki, odjemalec ne sme prikazati popolnega stanja računa. Različne valute
ostanejo ločene. Začetnega stanja računa se ne kopira v projekt.

Strežnik pri vsaki novi povezavi zahteva projektni finančni write dostop,
policy3 projekt in neposrednega policy3 starša vrste organization/household,
živega ne-arhiviranega starša z omogočenimi financami ter pravi račun in
valuto. Tuji, sorodni, osebni ali poljubni drugi račun ni dovoljen. Novih
samostojnih računov v projektu s staršem na v3 ni mogoče ustvariti
(`finance_account_parent_required`); obstoječi projektni računi se ne
združujejo in ostanejo urejani/arhivirani po svojih prvotnih pravicah.
Samostojni projekt brez starša ohrani svoj račun.

## Omejena izbira računa

`finance4.accountChoices:{scopeId}` zahteva finančni bralni dostop do projekta.
Vrne:

```json
{
  "accounts": [
    {"scopeId":"parent-uuid","id":"account-uuid","name":"Račun","currency":"EUR","archived":false}
  ],
  "accessRevision": 3,
  "accountScopeId": "parent-uuid",
  "accountSequence": 5
}
```

`accessRevision` je natanko revizija projektnega finance policy odgovora;
`accountSequence` je trenutni finančni cursor starša. Za neprojektni obseg,
projekt brez ustreznega starša ali arhiviranega starša je seznam prazen,
`accountScopeId:null` in `accountSequence:0`. To so samo računi starša;
odjemalec lahko ločeno doda svoje že dovoljene projektne račune.

Tudi član samo projekta sme izbrati ta račun, vendar odgovor **ne vsebuje
začetnega stanja, stanja računa, lastnika računa, starševega imena, članov,
transakcij ali sorodnih projektov**. Klic ne podeli članstva ali finančnega
dostopa do starša; njegov pull ostane zavrnjen. Predpomnilnik mora biti
razdeljen po strežniku/računu/projektu in reviziji dostopa ter odstranjen
ob odvzemu/menjavi profila. Posnetek imen ne nadomesti strežniške validacije
pri pisanju. Odgovor je omejen na512KiB.

## Zgodovina, arhiv in povezane knjižbe

Nov sklic na arhiviran račun je zavrnjen. Nespremenjeni zgodovinski sklic
lahko popravi obstoječo knjižbo; brisanje računa z živim projektnim sklicem
vrne `live_children`. Arhiviranje prostora onemogoči nova pisanja, stari
podatki ostanejo berljivi. Brisanje nativnega projekta z živimi knjižbami na
računu zunaj grafa je blokirano z `cross_scope_finance_dependency`; parent
računa ni mogoče odrezati s skritim izbrisom projekta.

Izbris uporabniškega računa ohrani strukturo starševskega računa in
kanonične povezane izdatke ter anonimizira avtorje po obstoječem postopku.
Starša z živimi projektnimi sklici ni mogoče izbrisati z implicitno ločitvijo
teh projektov. Obstoječi nadzorovan prenos lastništva ostane možnost.
Inline izbrisni predogled že zajame njegov `projectId` in trajne finančne
tombstone. Izločitev inline projekta z novo neposredno finančno oznako je
zaščiteno blokirana (`project_finance_scope_reference`), dokler uporabnik
izrecno ne uredi njegovega finančnega grafa; ne premakne računa samodejno.

Obstoječe finance3 povezano osebno plačilo ne sme pridobiti novega
`accountScopeId` zaradi varovala nespremenljivega vira. Obratno v3 knjižba
z računom starša že pomeni neposredni denarni učinek in je ni mogoče še
pretvoriti v osebni predujem/povračilo (`linked_payment_source_locked`).
Tako isti izdatek ne ustvari dvojnega učinka prek povračila.

Obstoječi `sync3/4/5/6.pushTaskWithCost` sprejme
`financeOperationContractVersion:3` za novo obliko;2 ostane privzeto.
Opravilo in izdatek se potrdita ali razveljavita skupaj. Navadna sprememba
roka opravila ohrani finančno pogodbo3 in povezavo do računa, osveži
projektni izdatek ter signalizira tudi starša.

Čezobsežne povezave mesečnih recurrence pravil v tej pogodbi niso dovoljene;
obstoječa pravila ostanejo v svojih računskih obsegih. Nova funkcija podpira
splošne prilive/stroške in vezane stroške opravil, ne prerazporejanja
proračunov ali samodejnega združevanja starih računov.

## Preverjanje

Namenski [integracijski preizkus](../../server/tests/organization-finance-integration.php)
preverja organizacije in gospodinjstva, neposredni in projektni bralni dostop,
minimalne izbire, izvor enega zapisa, stare ACK ponovitve, stare klientove
zavrnitve, nepravilnega starša/valuto, arhiv in izbris, inline oznake,
finance3 varovalo, skrite prispevke brez razkritja ID-jev, finančna obvestila3,
atomski strošek opravila, njegove datume ter ohranitev pri
izbrisu avtorja. Dokazi matrike so v
`build/qa/organization-finance-20261017/summary.json`. Ponovitev vodi
`python3 server/scripts/test-organization-finance-matrix.py` na treh že
obstoječih lokalnih razvojnih vsebnikih; ne resetira njihovih nosilcev. Ti preizkusi ne uporabljajo žive
produkcije in ne dokazujejo nove gostovane ali trgovinske izdaje.


Končni lokalni rezultat: **1506 kontrol PASS** (502 na vsaki od SQLite,
MariaDB10.11.19 in MySQL8.4), osem sklopov na vsakem mehanizmu:

| Sklop | Kontrole na mehanizem |
| --- | ---: |
| organization-finance-integration | 104 |
| finance-planning-integration | 20 |
| finance-integration | 40 |
| linked-payments-integration | 51 |
| scope-lifecycle-integration | 64 |
| space-sharing-integration | 109 |
| spaces-integration (vključuje task-cost) | 78 |
| deletion-integration | 36 |

PHP lint vseh20 neposredno pregledanih PHP datotek ter Python compile novega
matričnega pomagača sta PASS; `git diff --check` je čist. Starejši finančni
preizkusi so potrebovali samo dopolnitev sintetične prijave z že obstoječim
izrecnim sprejemom pravil vsebine. Strežniško varovalo se ni rahljalo; novi
sklop posebej potrdi zavrnitev finance4 uporabniku brez sprejema.
