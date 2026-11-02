# Ugotovitvi po ponovni prijavi 2. novembra 2026

Uporabnik potrdi uspešno prijavo z novim geslom. Ne potrjuje celotne
sinhronizacije ali obnove podatkov. Prvotni pregled je bil bralen; lokalni popravek in novi ciljni testi so opisani spodaj. Produkcija in telefoni ostajajo nespremenjeni.

## Povezana plačila

Posredovani dnevnik ima štiri napake `linkedPayments /
crypto_payment_snapshot_incomplete` ob 04:04:13.650338Z, 04:04:17.768070Z,
04:04:21.967630Z in 04:04:25.532414Z. Razmiki so približno 3,6–4,2 sekunde;
ni potrjeno, ali so to samodejni ali uporabnikovi poskusi.

Bralno potrjena pot:
- `collaboration_finance_sync.dart` `_syncFinanceScope`: po finančnem prenosu
  preveri tudi povezana plačila; ta veja neposredno zajame stage `linkedPayments`.
  `collaboration_sync_actions.dart` po osnovnem syncu ločeno izvaja
  `resumePending()`, ki tudi lahko zajame ta stage. Sam stage ne dokazuje
  čakajočega plačilnega ukaza.
- `collaboration_linked_payments.dart` `_fetchLinkedPayments`: po veljavni
  policy/revision/generation preverbi `complete == false` odstrani samo dokaz
  svežine, ohrani zaporedno mejo in vrže točno navedeno napako. Obstoječih
  povezanih dogodkov, denarnih premikov in čakajočih zahtev ta veja ne zamenja
  z nepopolnim posnetkom.
- `e2ee/crypto_business_payments.dart` `_snapshot`: complete je true le ob
  checkpointu za trenutno glavo, complete zastavici finančnega prostora in
  nič čakajočih projekcijah. Projekcija je pending ob različni reviziji izvora,
  blocked ob CryptoAuthorityPending ali CollaborationException pri preverbi
  izvornega prostora. Ujeti razlog se v tej poti izgubi; trenutni diagnostic
  izvoz zato ne loči teh vzrokov.

Dnevnik ne dokazuje napačnega gesla, izgube ključev, trajnega odvzema dostopa,
napake strežnika ali vzročne zveze s ponastavitvijo gesla. Naslednja ciljna
diagnoza mora ločiti checkpoint/complete stanje od razloga za pending/blocked
projekcijo ter preveriti sprožilec ponovitev, brez poslovnih vsebin ali skrivnosti.
Ne resetirati računa, ne ponavljati obnove ključev, ne ustvarjati novih plačil
za obvoz. Prejšnji testi incomplete-reply varovala niso dokaz konkretnega
vzroka na uporabnikovi napravi in niso bili ponovno zagnani.

## SwiftKey po fokusu praznega starega gesla

Uporabnik poroča, da je dovolj dotik praznega polja starega gesla. Priloženi
posnetek kaže drugo aplikacijo, motiv zasebnega načina SwiftKey in opozorilo,
da je bila tema spremenjena zaradi sistemske napake. Vnos gesla ni bil potreben.

`account_password_card.dart` uporablja skupni `showSharingForm` in
`PasswordVisibility`; za staro geslo velja obscure/sensitive, brez predlogov in
personaliziranega učenja. Ob Android hidden/paused/detached ali disable se
obstoječi fokus sprosti. Pregled ne potrdi, da se je ta native lifecycle na
telefonu dejansko izvedel. Prejšnji widget PASS ne dokazuje odpravljene težave
SwiftKey med aplikacijami. Ni najdene kode za spreminjanje globalne tipkovnice.

Microsoft dokumentira samodejni zasebni način ob zasebnem/občutljivem polju
in posebno temo tega načina. Zato preklop že ob fokusu sam zase ni napaka;
obstoj načina v drugi aplikaciji skupaj z opozorilom o temi ostaja odprt.
Vir: https://support.microsoft.com/en-au/swiftkey-keyboard/how-does-incognito-mode-work-on-your-microsoft-swiftkey-keyboard

Za native reprodukcijo zadošča prazno polje, brez dejanskega gesla. Zajeti je
potrebno zaprtje obrazca proti neposrednemu prehodu v drugo aplikacijo ter
stanje vhodne povezave/IME, ne besedila gesla. Zaščite vnosa ne izključujemo
kot obvoz. Začasno je mogoče v običajnem besedilnem polju v meniju SwiftKey
ročno izključiti Incognito; to ni potrjen popravek vzroka ali teme.


## Lokalni popravek 2. novembra — brez naprav ali produkcije

Uporabnik naroči reševanje sinhronizacije brez priključenega telefona; tipkovnico
odloži. Sol 6.1 high pripravi ciljni dokaz in neodvisen bralni pregled, root
pregleda, integrira popravek in izvede zaključne teste. Ni posega v strežnik,
račune, gesla, ključe, podatke ali nameščene aplikacije.

### Dokazana vrzel in meje sklepa

`CryptoBusinessSession.checkpoints` je klical `verifyDomainCheckpoint` brez
`onlineAuthorDirectory`. Veljavno podpisan checkpoint lahko navaja točno glavo
imenika podpisnika, ki je v novi seji še ni v lokalnem predpomnilniku.
`directoryAt` tedaj vrne `directory_proof_pending`. Bralnik checkpointov
ne sprejme tega kandidata in vrne `null`, kar lahko ohrani nepopolno finančno
stanje. To je dokazano na pravem bralniku, podpisih in replayu imenika.

Callback zdaj dovoli pridobitev točno navedenega podpisanega imenika.
Preverjanje podpisov, vloge, aktivne naprave, znanega prednika, prostora,
revizij, inventarja in lokalnih mej ostane. Frozen/deleted evidence še vedno
izrecno preprečuje spletno pridobivanje znotraj verifierja. Ne sprejemamo
strežnikove trditve kot dokaza in ne postavljamo complete=true na slepo.

To NI dokaz, da je prav ta veja povzročila uporabnikovo napako. Uporabniški
izvoz ni vseboval podvzroka. Prav tako to ni celoten preizkus ponastavitve
in finančne sinhronizacije na telefonu ali prek resničnega HTTP strežnika.
Za končno potrditev bo potrebna običajna posodobitev aplikacije in uskladitev
istega računa; brez brisanja aplikacije, ponovne obnove ali novih plačil.

### Diagnostika in razlaga

Nepopoln lokalni payment snapshot zdaj poda eno fiksno kategorijo:
- `crypto_payment_checkpoint_pending`: ni checkpointa za trenutno glavo;
- `crypto_payment_records_pending`: checkpoint je, stanje finančne projekcije
  pa še ni popolno;
- `crypto_payment_projections_pending`: finančno stanje je popolno, povezana
  plačila pa še čakajo preverbo izvornih zapisov.

Kategorije so prednostni prikaz ene ovire, ne dokaz, da drugih ni.
Prejemnik sprejme samo te tri konstante, sicer uporabi dosedanjo generično
`crypto_payment_snapshot_incomplete`. Razlog se posreduje šele po prvotni
transakcijski preverbi in umiku dokaza svežine; dejstva, denarni premiki in
čakajoči ukazi ostanejo. SL/EN razlaga ne usmerja na novo pripravo zaščite.
Izvoz ne dodaja identifikatorjev, imen, vsebine ali surovih izjem.

Štirih posredovanih časovnih oznak ne obravnavamo kot dokaz štirih ponovitev:
`_captureSyncFailure` zamenja prejšnji zapis istega stage/scope/reason. Več
istih razlogov lahko predstavlja različne prostore v eni uskladitvi; scopeId
je namenoma izpuščen iz varnega izvoza. Sprožilnikov/timerjev nismo spreminjali.

### Ciljni rezultati in poskusi

- Novi runtime reader cold test: R1 compile FAIL zaradi manjkajočega getterja
  v kopirani testni glavi; fixture popravljena. R2 pravi RED: veljaven inventar
  vrne null. Po popravku R3 PASS. Ni četrtega poskusa.
- Štiri nove negativne kontrole (fork, napačen podpis, manjkajoča zahtevana
  glava imenika, viewer) PASS v prvem zagonu. Noben checkpoint se ne namesti;
  začasni inventar je odstranjen, ključni store in lokalni imenik nespremenjena.
  Realni podpisi/reducer/SQL; head/scoped-contact boundary sta testna vhoda.
  Zahteva imenika je natanko ena na primer, vezana na pričakovano glavo.
- Dve novi snapshot kategoriji (manjkajoči checkpoint, nepopolno stanje)
  PASS1 na pravi snapshot funkciji s sintetičnim pull/head boundary.
- Pet novih prejemnikovih kontrol (tri kategorije, neznan niz, nepravilni tip)
  PASS1: vsa obstoječa dejstva in pending intent ostanejo, freshness se umakne.
- Tri nove UI kontrole PASS1: slovenska razlaga, ista varna kategorija v izvozu,
  brez gumba za novo pripravo zaščite.
- Skupaj **15 različnih novih PASS**, brez ponavljanja zgodovinskih PASS.
- Analyze: 0 napak; 13 starih info; ena nova opozorilna unused import v novem
  fixture odstranjena, nato samo prizadeta datoteka ponovno analizirana.
  Brez ponavljanja funkcionalnih testov zaradi odstranitve uvoza.
- Neodvisen pregled petih produktnih datotek ni našel blokad ali oslabljenih
  varoval. Git diff check PASS.

Dokazi: `build/qa/post-password-payment-sync-20261102/`:
`runtime-checkpoint-cold-r2.log`, `runtime-checkpoint-r3-and-negatives-r1.log`,
`payment-diagnostics-r1.log`, `analyze.log`, `analyze-new-fixture.log`.
Nova javna Android izdaja v tem koraku ni zgrajena ali oddana.

## Uporabniški rezultat po 1.11.9 — sinhronizacija še ni potrjena

Uporabnik po posodobitvi poroča `linkedPayments /
crypto_payment_records_pending` ob 05:51:13.397080Z, 05:51:18.113928Z in
05:51:22.107566Z. Pred tem je potrdil prikazano preverjanje prostorov;
napaka se je pojavila tudi po potrditvi. Prejšnji lokalni PASS in popravek
imenika zato nista dokaz odprave uporabnikove celotne težave.

Bralni pregled natančno potrdi pomen kategorije: obstaja lokalni checkpoint
za trenutno glavo članstva, vendar finančni `crypto_scope_state` manjka ali
njegov `complete` ni 1. Kategorija ne dokazuje svežine tega checkpointa,
manjkajočega konkretnega zapisa, izgube ključev ali napačnega gesla.
Preverjanje dostopov do prostorov ne potrjuje popolnosti finančne projekcije.

`CryptoDomainCheckpointPublisher.publish` lahko vrne brez complete ob
neujemajočem lokalnem zapisu/inventarju, nepreverjenem prejetem zapisu,
nedokončanem ukazu checkpointa, neuspešni preverbi njegovega podpisa ali
spremenjenih mejah lokalnega prenosa. Sedanja kategorija teh izhodov ne loči.
Zgolj na podlagi izvoza ni mogoče izbrati enega kot dejanski vzrok.

Naslednji dokaz mora zajeti konkretno vejo zaključevanja in varni razlog
zadržanega zapisa ter lokalno povezati pull, preverbo inventarja in končni
payment snapshot. Ne zadostuje še en test samega prevoda kategorije napake.
Ne postaviti complete na silo, ne resetirati računa ali ključev, ne zahtevati
ponovnega potrjevanja prostorov brez novega dokaza. Ta pregled ni spreminjal
produktne kode, telefonov ali strežnika in ni ponavljal uspešnih testov.


## Natančno zaključevanje plačil — implementacija za 1.11.10

Uporabnik naroči implementacijo in novo objavo. Sol 6.1 high implementira
jedro in UI, root poveže prejemnika, pregleda spremembe in preveri paket.
To je diagnostična izdaja: konkretni vzrok na uporabnikovem telefonu in
uspešna finančna uskladitev še nista potrjena.

Vsak dosedanji tihi izhod publisherja vrne končno oznako. Končni guard loči
manjkajoče stanje, floor, revizijo pravic, zaporedje prostora, generacijo
pregleda, zaostali projekcijski kurzor in spremenjeno sejo. Prvotni pogoji,
vrstni red, transakcije in edini zapis complete=1 ostanejo isti. Runtime
hrani največ 20 lokalnih oznak, ločeno po prostoru/domeni, in jih počisti ob
vsakem pullu ter notranjem ponovnem poskusu. Oznake niso dokaz pravic.

Ob nepopolnem posnetku se izvozi completionDiagnostics: checkpointStep in
po potrebi recordVerdict/recordReason za en vzorčni zadržani zapis istega
prostora. SQL bere samo verdict/error (LIMIT 1); vzorec ni nujno zapis, na
katerem se je publisher najprej ustavil. UI to izrecno pojasni. Ne izvozi
identitete, vsebine ali ključev; enum in strogi allowlist veljata ob sprejemu,
prikazu in kopiranju. Neznane oznake se zavržejo oziroma postanejo unknown.
Napaka pomožne poizvedbe ohrani prvotno napako in oznako koraka. Brez novih
HTTP zahtevkov, sprememb sheme, sej, računov, ključev ali strežnika.

Prejemnik še vedno najprej preveri epoch/generation/revision/sequence ter
transakcijsko umakne le dokaz svežine; obstoječa finančna dejstva in čakajoči
ukazi ostanejo. Izvoz in kopiranje sta vezana na isti prikazani poskus.
Ni dodanih navideznih gumbov za reset/obnovo ali samodejnega potrjevanja.

Ciljno lokalno preverjanje: **22 novih različnih PASS**:
- jedro 4 PASS1 na runtime→publisher→snapshot poti ter čiščenje oznak;
- 8 novih follow-up PASS2: prvi ukaz ni izbral testov (0 izvedenih), po
  popravku izbire optional SQL failure, dejanski reader-null in 6 končnih
  guardov; prvotni 4 PASS niso ponovljeni;
- prejemnik 3 PASS1: prenos/sanacija diagnostike, ohranjena dejstva/pending
  in prednost prvotnega access guard; dodatni parser 1 PASS1;
- UI 5 PASS1 in nato 1 nov selektivni SL/EN split-state/cursor PASS1;
  prvotnih 5 ni bilo ponovljenih.

Meje: prava memorySQLite in runtime/publisher/snapshot, transport, dostava
ukaza in ključi so testne meje; končni guardi uporabljajo reader seam,
reader-null posebej pravi reader. Ni celoten produkcijski HTTP ali telefon
PASS in ne dokaz vzroka na uporabniški napravi. Uspešnih starih testov nismo
ponavljali. Root analyze: prvi napačno poimenovan testni path brez analize;
pravilni nabor 0 errors/0 warnings, 21 starih info in 1 nov testni braces
info (odpravljen brez spremembe vedenja; nato analyze samo te datoteke).
Neodvisen bralni pregled ni našel blokad ali oslabljenih varoval.

Dokazi: build/qa/payment-completion-diagnostics-20261102/{core,root,ui}/.


## Uporabniški zasloni 07:42–07:46 — priprava računov/prostorov

Po uporabnikovem naslednjem preizkusu ni potrjen zaključek zaščite ali celotne
uskladitve. Šest posnetkov kaže začetni CryptoMigrationWizard »ni dodatnih
korakov«, nato opozorili za Dom in TriparNA, ScopeRecoveryPage z generično
napako ter oblaček pending ob treh ničelnih poslovnih števcih in prikazanem
času uspešne uskladitve. Na slikah ni novega completionDiagnostics JSON;
iz njih ni mogoče potrditi odprave ali istega vzroka linkedPayments napake.

Bralno potrjena razhajanja:
- account_crypto_startup odpre migration wizard za reviewRequired, ko manjka
  zaključni dokaz ali se ne ujema trenutna naprava. To ni dokaz, da manjka
  obnovitvena datoteka ali da jo je treba ponovno uvoziti.
- CryptoMigrationWizard.canFinish gleda samo seznam migracijskih kandidatov.
  Prazen/committed seznam lahko kaže »ni dodatnih korakov«, medtem ko
  AccountProtectionReady.complete ločeno še preverja obnovljene lastnike.
- _rotateRecoveredOwners v local_meta že shrani konkretni scopeAction.reason.
  account_protection_completion ga v prikazu ne uporabi; prikaže enako
  besedilo za različne ovire glede na canManage. Besedilo o drugem finančnem
  sodelavcu zato ni dokaz, da ga ta račun dejansko potrebuje.
- ScopeRecoveryPage._run ujame vse izjeme v bool _failed in konkretni razlog
  izgubi. Gumb uvoza datoteke je alternativna pot, ne dokaz nujnosti; ob njem
  obstaja reviewLocal/hydrateExistingCandidateKeys. Uporabniško je to nejasno.
- Oblaček pending uporablja tudi hasUnresolvedSyncWork (crypto_outbox,
  commands/payment intents), ki ni razčlenjen v treh poslovnih števcih. Zato
  pending + 0/0/0 ni dokaz izgube sprememb, a uporabniku ne pojasni zadržka.

Uporabnik izrecno zavrne preverjanje z isto obnovitveno datoteko za vsak
prostor. Dogovor za poenostavitev: en izbor datoteke na računski postopek;
uporabiti že preverjene lokalne ključe, kadar so na voljo; aplikacija obdela
upravičene prostore in ohrani napredek. Ena razumljiva skupna predstavitev
rezultata, konkretne izjeme po prostoru (brez ponovnega uvoza zgolj zaradi
nezaključene priprave). Ne enačiti samodejne obdelave z avtomatskim soglasjem
k nepreverjeni zgodovini ali dodelitvijo novih pravic. Pravi potreben pregled
mora biti jasno predstavljen v skupnem postopku; brez ugibanja, da mora
ukrepati drug uporabnik. Nove zahteve zapisane; produktna koda, telefoni in
strežnik v tem bralnem pregledu niso spremenjeni, testov ni bilo.


## Enoten računski pregled in zaključevanje sinhronizacije — lokalna nadgradnja

Uporabnik naroči odpravo ponavljanja po prostorih in nedokončane uskladitve.
Sol 6.1 high: računsko jedro, sync jedro in UI; root integrira, preveri kodo,
poveže vstopne poti in vodi dodatne ciljne teste. Telefoni, produkcija in
Google Play v tem koraku ostanejo nespremenjeni. Različica ostaja 1.11.10+42;
nova binarna izdaja še ni pripravljena ali oddana.

### Uporabniški tok

- Priprava uporablja preverjene obstoječe ključe. Če je potrebna datoteka,
  uporabnik izbere eno datoteko za celoten računski postopek. Omejeni prehodi
  nadaljujejo skozi več kot 20 prostorov; zastoj enega ne skrije ostalih.
- Nedokončana preverjanja lahko nadaljujejo s shranjenimi ključi, brez novega
  recoverEpoch, preklica naprav, novih računov ali novih obnovitvenih ključev.
- Skupni zaslon pokaže lokalna imena in varno oznako posamezne ovire. Izrecen
  pregled nepreverjene zgodovine ostaja; v teh pregledih ni ločenega uvoza
  datoteke. Pravi prispevek drugega sodelavca ostane potreben, kadar manjka.
- Zaprtje/menjava seje ustavi naslednje korake omejene obdelave; uspešni koraki
  in preostale obveznosti ostanejo. Izbrani bajti se počistijo v finally.
- Startup completionMissing in scopeRecovery, ročni pregled in pripravljen
  račun vodijo v novi skupni tok. Prava obnova računa ostane v obstoječem
  čarovniku. Legacy prostori po preverjenem katalogu ohranijo migracijski tok.
- ScopeRecoveryPage ne izgubi več konkretne varne izjeme v bool. Kopija napake
  izključi imena, identifikatorje, vsebino in ključe. Obsolete modalni
  account_protection_completion je odstranjen; nima več klicateljev.

### Dve lokalno ponovljeni sync napaki

1. Čas uspešne uskladitve se je premaknil pred preverjanjem notranje vrste.
   Sedaj se premakne šele brez poslovnih/crypto/payment obveznosti,
   reconciliation oznak, konfliktov in ob ohranjenih sejah/finance guardih.
   Preverjanje uporablja agregatni SQL, ne dodatne serializacije zgodovine.
   Prejšnja uspešna zgodovina ostane, če trenutni poskus ni dokončan.
2. Že preverjen in uporaben checkpoint je povzročil zgodnji return, zato je
   njegov izgubljeni ACK ostal v pending/blocked vrsti. Sedaj se preveri samo
   terminalni receipt točno iste shranjene podpisane zahteve. Ujemati se morajo
   račun, strežnik, prostor, domena, head/epoch/revision/sequence, manifest,
   število zapisov in celotna authorization. Lookup ne pošlje mutacije, ne
   ustvari novega namena in ne nastavi complete. Neznan/zavrnjen lookup ali
   zamenjan dokaz ohrani zahtevo; veljaven zavrnilni receipt ostane rejected.

Oblaček posebej izpiše pending/blocked zahteve protokola. Pending z nič
poslovnimi spremembami se imenuje nedokončana priprava sinhronizacije.
Nobena od teh oznak ne nadomesti dokazov popolnosti ali pooblastil.

### Preverjanje in omejitve

**47 različnih aktualnih lokalnih kontrol PASS:** sync jedro 12, računsko
jedro 14, skupni UI 13, root vstopne poti/status/varen izvoz 8.

- Sync timestamp: prvotni fiksni čas je dal neveljaven pozitivni rezultat;
  popravljen čas RED2, produktni popravek PASS3. Dve lost-ACK kontroli RED1,
  nato PASS2 z novimi negativnimi kontrolami. Poseben nov test potrdi agregate
  in samo obstoječ končni signature read. Stari uspešni testi niso ponovljeni.
- Računsko jedro: 10 začetnih PASS1, 2 nova saved-key PASS1, 1 prilagojen guard
  PASS1 in 1 nov preklic po 20/25 prostorih PASS1. Prejšnji preprost guard PASS
  je nadomeščen in ni v aktualnem seštevku; en začetni selector ni našel testov.
- Skupni UI: 1 builder PASS1, 11 widget PASS2 (FAIL1 inicializacija fixture
  seje pred odprtjem), 1 nova razlaga nepopolne obnove PASS1.
- Root: 6 novih PASS1; direktna sync pot PASS1; prepared-account pot PASS3
  (FAIL1 neizgrajen gumb v lenem ListView; FAIL2 popravljalni skript ni našel
  besedila in fixture ni spremenil; popravek scrollUntilVisible PASS3).
- Končni analyze vseh spremenjenih produktnih datotek in ciljnih testov:
  0 errors, 0 warnings, 50 preostalih starih info. Diff-check PASS.

Pravi SQLite, podpisane zahteve/vrsta, podpisani account genesis in FILE AEAD
so preverjeni lokalno; scope verifier/manager ter transport in UI uporabljajo
izrecne testne meje. To NI dokaz vzroka na telefonu, celotnega HTTP postopka
ali uspešnega zaključka Dom/TriparNA. Nov uporabniški JSON ni bil pridobljen.
Neznani dokazi/permission ali potrebna soglasja še vedno zakonito ustavijo
postopek. Generic commandResult za rejected ukaze ostaja nespremenjen; ločena
ugotovitev o prikazu tega stanja ni potrjena kot vzrok uporabnikove težave.

Dokazi: build/qa/sync-queue-completion-20261102/,
build/qa/account-recovery-batch-20261102/core/,
build/qa/unified-account-protection-20261102/ui/,
build/qa/account-sync-continuation-20261102/root/.

Naslednji dejanski preizkus po novi običajni posodobitvi: isti račun in isti
podatki; brez brisanja, ponovne prijave ali nove obnove. Skupni pregled mora
nadaljevati obstoječe delo. Če ostane ovira, kopirati njeno konkretno varno
napako; zelenega oblačka ali končnega uspeha še ne trdimo.
