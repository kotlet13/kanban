# Skupno preverjeno branje financ — 20. oktober 2026

## Naročilo

Po združenem pridobivanju pravic je uporabnik naročil samo prvi naslednji
korak: finančni pregled, izbira računov in povezana plačila naj znotraj iste
sinhronizacije uporabijo iste preverjene finančne podatke. Podagenti
GPT-6.1 Sol/high izvajajo jedro, povezavo z običajno sinhronizacijo in
neodvisni pregled; glavni agent pregleduje integracijo in rezultate.

Ta naloga ne spreminja urnika osveževanja, Firebase, petminutnih omejitev,
strežniških kvot ali uporabniških tokov. Predlogi ostanejo v
[dokumentu združevanja pravic](E2EE_AUTHORITY_BATCHING.md#možno-nadaljevanje--v-tej-nadgradnji-ni-izvedeno).
Produkcija, trgovini, nameščene aplikacije ter obstoječi Mac/mobilni QA
podatki ostanejo nedotaknjeni. Dva nepovezana lokalna dokumenta nista del
spremembe. Native uspešnih scenarijev in izvedenega odvzema N7 ne ponavljamo.
Za posamezno novo težavo velja največ tri neuspešne poskuse, nato zapis
in preskok; novega računa ne uporabljamo za ponastavitev tega števca.

## Izhodišče in sprejeta meja

[Prejšnja izvorna analiza](E2EE_MAC_SHARING_TEST_2026_10_19.md#strošek-poskus2-omejena-analiza-blocked-brez-novega-teka)
je našla podvajanje med ločenimi poslovnimi dispatchi, ne podvojenega pulla
znotraj enega uspešnega account-choices dispatcha. Običajni `_syncFinance`
preveri politiko, odda čakajoče finance, prebere finance, nato izbiro računov
in povezana plačila. Slednja dela lahko znova zahtevata že prebrani obseg.

Meja novega konteksta je obdelava enega prostora v enem finančnem prehodu.
Ni globalnega ali trajnega predpomnilnika in ni daljše veljavnosti pravic.
Podatkovni ključ ni samo ID prostora: ponovna uporaba mora ostati vezana na
račun/sejo, bazo, podpisano glavo in dostop, preverjen checkpoint, stanje
projekcije ter nespremenjene varne pine. Velja obstoječa največ petsekundna
meja. Manjkajoča ali nepopolna dokazila pomenijo običajno novo branje.

Objava izbire računov, checkpointa ali opažanja ter razreševanje izpeljanih
finančnih vnosov lahko zapišejo podatke. Zato navaden `alreadyPulled` ni
zadosten. Ponovna uporaba sme nastati šele po dokončanem preverjanju in
potrebnih zapisih; znana sprememba jo razveljavi. Lokalna vrsta, identitete
zahtevkov, konflikti, saldo in ločenost finančnih pravic ostanejo ohranjeni.

## Izvedba

- [`collaboration_finance_sync.dart`](../lib/organizer/data/collaboration_finance_sync.dart)
  obdela vsak prostor v svojem izbirnem `CryptoFinanceReadContext`. Politika,
  oddaja čakajočih sprememb, glavni pull, izbire računov in povezana plačila
  ohranijo vrstni red, preverjanje seje/zakupa ter obstoječe obravnave napak.
  Samostojni UI klic in naslednji sync ne podedujeta tega konteksta.
- [`crypto_business_router.dart`](../lib/organizer/data/e2ee/crypto_business_router.dart)
  ustvari račun in skupni preverjevalnik šele ob prvem dejanskem E2EE
  dispatchu. Legacy pot zato ne sproži kriptografske inicializacije. Vsak
  dispatch še vedno dobi nov poslovni runtime; skupna je samo izrecna
  podlaga za preverjeno branje. Drugi dispatchi in oddaja zapisov jo
  razveljavijo.
- [`crypto_verified_finance_reads.dart`](../lib/organizer/data/e2ee/crypto_verified_finance_reads.dart)
  shrani rezultat šele po uspešnem attested pullu, checkpointu in izpeljavah.
  Ponovna uporaba zahteva enako podpisano glavo, epoch, access revision in
  odtis lokalnega stanja. Napaka počisti rezultate, zaključek konteksta pa
  jih dokončno zavrže. Potrošniki še vedno preverijo svoje povezave,
  manifeste in popolnost.
- [`session_crypto_access.dart`](../lib/organizer/data/e2ee/session_crypto_access.dart)
  omeji veljavnost na izvirno petsekundno okno, točno identiteto, življenjski
  cikel aplikacije, generacijo avtoritete in varne pine. Ponovna uporaba
  časovnega okna ne podaljša. Pisanje ohrani svežo preverjevalno mejo.

Odtis vključuje stanje domen, materializirane zapise, prejete revizije,
checkpointe in generacijo finančnega dostopa. Ob začetnem zajemu mora biti enak pred in po preverjanju. Pri ponovni
uporabi se v transakciji preverijo prvotna veljavnost, isti odtis in znova
prvotna veljavnost; nova časovna meja se ne ustvari. Ponovna uporaba ima omejitev 128 materializiranih zapisov,
128 prejetih revizij, 8 checkpointov in 256 KiB kodiranega stanja; večji
obsegi opravijo običajno preverjeno branje. To ne omejuje dovoljene
vsebine ali sinhronizacije uporabnika, temveč strošek te optimizacije.

## Preverjanje

Štirje novi integracijski testi `finance_combined_read_sync_test.dart`
so PASS v drugem poskusu: skupen kontekst potrošnikov istega prostora,
ločitev naslednje sinhronizacije in samostojnega UI, zaključek ob ujeti
napaki avtoritete ter ob napaki oblike odgovora. Prvi poskus je odpovedal
pred tem zaradi napačnega generičnega tipa sintetičnega `features` mapa;
popravljena je bila samo testna priprava. Ciljna analiza povezave nima
napak/opozoril, en obstoječ slogovni info ostaja v nespremenjenem preflightu.

Šestnajst novih jedrnih kontrol `crypto_verified_finance_reads_test.dart`
je PASS v prvem poskusu: 11 kontrol pogodbe ponovne uporabe (vključno s
pretekom prvotnega časa, napako, razveljavitvijo med asinhronim preverjanjem
in zaprtjem konteksta) ter 5 SQLite kontrol dejanskih revizij, payloadov,
cursorjev, checkpointov, generacije dostopa, nepopolnosti in omejitve velikosti.
Generični test razveljavljenega varovala ni ločen dejanski test menjave
identitete, življenjskega cikla ali Keychain pina; te produkcijske povezave
so pregledali glavni agent in neodvisna pregledovalca. Takih dodatnih
fizičnih/mutacijskih preizkusov ne zatrjujemo.

### Ločena odkrita težava: zastarela izbira računov

Prva dva poskusa nove HTTP priprave sta zadela
`crypto_account_choices_source_set_changed`: projekt je imel potrjeno prazno
izbiro, nadrejeni prostor pa je pozneje dobil finančni račun.
V [`CryptoFinanceAccountChoices.ensure`](../lib/organizer/data/e2ee/crypto_finance_account_choices.dart)
lahko `materializeAvailable` vrne star že uporabljen certifikat; neposredni
`read` za to vejo je zunaj obstoječe zanke za obnovitev zastarele izbire.
To ni izguba finančnih zapisov in ni nova regresija ponovne uporabe branj.
Izvor te ločene poslovne poti v tej nalogi ostane nespremenjen, samodejno
nadaljevanje take zastarele izbire je **OPEN**.

Tretji poskus nadaljuje istega uporabnika, isti prostor/projekt in podatke:
izrecni `prepare → approve → finish` ustvari novo izpeljano izbiro z vnaprej
shranjenimi ID-ji dejanj. Stari podpisani zahtevki ostanejo ohranjeni.
Ta nadaljevalni korak je uspel; ne dokazuje popravljenega samodejnega `ensure`.

Tretji celotni HTTP tek s ponovno uporabo izključeno je PASS: 131 zahtevkov,
21.326 B teles zahtevkov, 1.790.955 B teles odgovorov, 2.066 ms in 9 klicev
`crypto2.records.pull`; nič 429 ali končnih napak. Vključeval je še eno
začetno objavo opažanja, zato to **ni čista primerjalna osnova prihranka**.
Končna meritev uporabi že ustaljeno isto stanje in en par vključeno/izključeno.

### Končni dejanski HTTP par — PASS

Na istem ohranjenem sintetičnem računu, nadrejenem prostoru in projektu sta
tekla dva običajna `CollaborationRepository.syncNow()` cikla: najprej
optimizacija vključena, nato izključena v testnem routerju. Ista končna
izvorna koda in isti strežnik; nobeno merjeno branje ni ponarejeno, kvota
ni zvišana, merjena cikla nimata dodatnega pacinga ali ponovitev.

| Meritev | Vključena ponovna uporaba | Izključena kontrola |
|---|---:|---:|
| HTTP v finančnih dispatchih | 39 | 58 |
| Finančni `crypto2.records.pull` | 4 | 7 |
| HTTP v celotnem ciklu | 85 | 88 |
| Vsi `crypto2.records.pull` | 6 | 9 |
| Bajti teles zahtevkov | 11.063 | 9.541 |
| Bajti teles odgovorov | 1.577.252 | 1.246.114 |
| Čas celotnega cikla | 1.552 ms | 1.327 ms |

Finančni subtotal ima 19 manj zahtevkov (32,8 %). Glavni parent pull ima
16 namesto 17, child pull 6 namesto 7, izbira računov 3 namesto 8, obe
payment branji vsako 2 namesto 7, dodatni politiki pa vsaka 2 namesto 3.
To pokaže odpravo treh ponovljenih finančnih pullov v običajnem toku.

**Prihranek bajtov in časa ni dokazan.** Prvi, optimizirani cikel je opravil
še dve checkpoint in štiri receipt preverjanja ter več membership/content
osveževanja; naslednja kontrola tega dela ni imela. Tabela pošteno ohrani
vse meritve, ne pripisuje celotne razlike samo optimizaciji in ne predstavlja
splošnega benchmarka. Uspešnega para ne ponavljamo zaradi lepše številke.
Štejejo se telesa dejanskih HTTP zahtevkov/odgovorov brez glav ali TLS.

V obeh ciklih so PASS: isti finančni ID-ji, revizije in payloadi; en račun,
en strošek 12,34 EUR, saldo 33,33 EUR (otvoritev 45,67 EUR); ena veljavna
izbira računa pri projektu, dva popolna payment snapshot markerja,
ohranjen projekt, nič nerešenega dela, nič končnih napak in nič 429.
To ni preizkus nepraznega povezanega plačila ali menjave identitete.

Neodvisni pregled in glavni pregled končne kode sta PASS. Novi zasebni
Docker na 59776 je ustavljen, sintetična baza, ključi, seje in prvotni
ID-ji zahtevkov so ohranjeni zunaj repozitorija. Stari Docker18811 in
nameščene aplikacije niso bili uporabljeni ali spremenjeni.

### Vezani dokazi

- Jedro, 16 PASS / poskus 1:
  `/tmp/jivie-finance-core-tests-attempt1.log`, SHA-256
  `573c274105cfb98f3d2fcc487f08e85706c0731af23f7156454b75deb1b22984`.
- Povezava, 4 PASS / poskus 2:
  `/tmp/kanban-finance-combined-read-sync-attempt2.log`, SHA-256
  `667c522b94c8eb5c05b399300dadcb64f5fcfde4ad721e7e4f92df10ccbc0e29`.
- Dejanski par, PASS / poskus 1:
  `/tmp/jivie-finance-read-reuse-20261020/paired-final-attempt1.log`, SHA-256
  `850590c16f31e79397927c8524bd5f5460a219e8aa6bfe48ef833323c0507e4c`;
  `paired-final.json`, SHA-256
  `5c9b463350b0c35f3f8cf36e91adbbe4cdc5d14d3c8d3842ddbe0d83db1d0ba0`.
- `crypto_business_router.dart` SHA-256
  `1a5166c777f82dd2d1067d3b3cbb053eb5a20a4462c18eb3d1092a38872321be`;
  `crypto_verified_finance_reads.dart`
  `66fcc7c51cc3e2157ffd800d9c806dc53437e3939b69e114cf83850b2ec34866`;
  `session_crypto_access.dart`
  `1b0ae4738eb44826e63fd6a056a3acf926ec5607410d759c108ed4db24c40685`.

Končni `flutter analyze`: **0 error, 0 warning, 515 obstoječih info**
(enako skupno število kot ob prejšnji nadgradnji pravic); izhodna koda1 je
posledica info pravil. Novi helper/test datoteki sta brez analiznih pripomb.
Zapis `/tmp/jivie-finance-read-root-20261020/flutter-analyze-final.log`,
SHA-256 `f167bd22a429a8e1f96684acf039ab2663301ad41673637eedcbb47fdd2122db`.
`git diff --check` je čist. Izvedba gre v commit/push brez namestitve.
Zmanjšanja celotnega prejšnjega native cikla s 412 zahtevki ne bomo sklepali
iz ožjega testa. P0/mobile/P8 in prejšnje odprte meje N7 niso zaključene s
to spremembo.
