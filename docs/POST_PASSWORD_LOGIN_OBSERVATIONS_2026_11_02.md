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
