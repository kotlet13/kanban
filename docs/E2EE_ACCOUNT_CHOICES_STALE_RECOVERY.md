# Samodejno nadaljevanje zastarele izbire računov

20. oktober 2026. Uporabnik je po pojasnilu izrecno naročil popravek ločene
napake, odkrite med [združevanjem finančnih branj](E2EE_FINANCE_READ_REUSE.md).
Izvedba in neodvisni pregled: podagenta GPT-6.1 Sol/high; glavni agent
pregleda spremembo, dokaze in integracijo ter opravi commit/push.

## Napaka in meja popravka

Projekt že vsebuje potrjeno izbiro računov svojega prostora. Ko se nabor
računov prostora spremeni, stara izbira ne ustreza več trenutnemu stanju.
`CryptoFinanceAccountChoices.ensure` pri prvem branju prepozna zastarelost,
nato poskusi prevzeti že izdano izbiro. Če prevzame star že uporabljen
certifikat, naslednji `read` pravilno zazna zastarelost, vendar je bil ta
klic zunaj obstoječe obravnave napake. Postopek se ustavi z
`crypto_account_choices_source_set_changed` namesto nove izpeljane izbire.

Dejanski HTTP tek je potrdil tudi zgodnejšo mejo iste težave: strežniški
`crypto2.exports.delegation.forOffer` pri prvotnem izdajatelju preveri
trenutni nabor računov in lahko vrne isto zastarelost. Odjemalec je ta
klic opravil pred obstoječim `try` za preskok zastarelega certifikata.
Popravek zato obravnava obe meji: pridobivanje podatkov certifikata v
ozkem discovery `catch` za običajne certifikate in drugo preverjeno branje
v `ensure`. Migracijski kandidati in Capture3 ohranijo strogo zavrnitev.
Obstoječe dovoljene vrste napak nadaljujejo pripravo nove izbire; stari
podpisani zahtevki se ne spreminjajo. Discovery ohrani svoje štiri dovoljene vrste zastarelosti, mejo strani in
preverjanje kazalca. Preverjanje podpisov, pravic, pinov, celovitosti in
potrebna odobritev upravljavca ostanejo.
Obstoječa največ dva poskusa priprave/odobritve/zaključka se ne povečata.
Napake, ki niso priznana zastarelost ali manjkajoča objava, se vrnejo klicatelju.

Sprememba ne posega v strežnik, shemo, urnik, Firebase, SDK, odvisnosti ali
nameščene aplikacije. Produkcija, stari Mac/mobilni QA in nepovezana lokalna
dokumenta ostanejo nedotaknjeni. Novi preizkus uporablja samo ohranjeni
izolirani HTTP fixture59776 in isto stanje, brez ponovitve starih uspešnih
native scenarijev ali benchmarka. Največ trije neuspešni poskusi na težavo.

## Preverjanje

Dejanski stari HTTP tok je napako ponovil: po enem novem računu z ničelnim
začetnim zneskom v istem prostoru je običajni sync vrnil
`crypto_account_choices_source_set_changed`. Dva stara finančna zapisa in
42 starih podpisanih zahtevkov so ostali nespremenjeni, saldo33,33EUR in
strošek12,34EUR sta ista, nič429. Prvi poskus se ni prevedel zaradi dveh
napak novega testnega ogrodja in ni spreminjal fixture; drugi je uspešno
potrdil pričakovano aplikacijsko napako. Isto stanje je ohranjeno za
nadaljevanje s popravkom, brez ročne priprave/odobritve izbire.

Devet novih ciljnih testov v `crypto_account_choice_ensure_stale_test.dart`
je PASS. Prvi poskus je ustavila priprava tabele, ki jo baza že ustvari;
drugi je s starim izvorom ponovil točno `source_set_changed`, tretji pa je
s popravkom uspešno zaključil vseh devet kontrol. Pokrivajo novo izpeljano
generacijo po zastarelosti, ohranjene izvirne dnevnike zahtevkov, največ dva
poskusa, že svežo izbiro brez nove generacije, nadaljevanje nedokončanega
dejanja in ohranitev ročne odobritve pri ločenih vlogah. Negativne kontrole
preverjajo, da podtaknjene napake identitete/pinov/podpisov/pravic ostanejo
iste napake; to niso novi napadi na dejansko kriptografsko implementacijo.

Prvi popravljeni HTTP tek je še vedno vrnil `source_set_changed`, zato
ni bil PASS. Bralna diagnoza strežniške poti `forOffer → source` in
nespremenjen dnevnik brez novih propose/delegate/certify sta pokazala
zgodnejšo manjkajočo obravnavo. Dodaten ozki popravek obravnava samo štiri že priznane vrste zastarelosti
pri pridobivanju ponudbe/delegacije običajnega certifikata. Pri migracijskem
kandidatu ali certifikatu Capture3 napaka še vedno prekine postopek;
obstoječi catch pri dejanski materializaciji ostane nespremenjen. Nadaljuje se isto stanje, ne nova priprava.

Glavni in neodvisni pregled prve veje sta PASS; `replaceStale`
ohrani tudi predhodno ugotovljeno zastarelost. `prepare`, `approve`, `finish`
in končno preverjanje podpisov/glav/pravic se ne spreminjajo.

Tri dodatne nove discovery kontrole so PASS v prvem poskusu: preskok
zastarelega `forOffer` in napredovanje kazalca/do izteka strani; natančno
vračanje drugih napak; stroga zavrnitev pri Capture3 in migracijskem
kandidatu. Prejšnjih devet že uspešnih testov nismo ponavljali. Končni
izvor sta pregledala glavni agent in neodvisni pregledovalec.

**Drugi popravljeni HTTP tek je PASS.** Isti račun, starš/projekt, ista
baza in zahteva dodanega računa: en običajni `syncNow()` samodejno izpelje
novo izbiro brez ročnega `prepare/approve/finish`, novega povabila ali
resetiranja. Končni rezultat nima napake ali nerešenega dela; projekt ima
dve dovoljeni izbiri računov, vključno z novim računom. Saldo33,33EUR in
strošek12,34EUR ostaneta ista. Dva izvirna in vsi trije finančni zapisi ob
začetku nadaljevanja so ohranjeni z istimi ID-ji, revizijami in vsebino.
Vseh48 podpisanih zahtevkov ob začetku nadaljevanja (tudi zahteva novega
računa) ostane bajtno nespremenjenih po ID/operaciji/podpisanem telesu/hashu;
preverjeno je tudi prvotnih42. Ni429.

Omejeni zajem operacije/kode/sklada potrdi staro `certificates.get` branje
ter dva zastarela `delegation.forOffer` certifikata; zadnja se zdaj pravilno
preskočita, običajna priprava nove izbire pa se zaključi. Zajem ne vsebuje
payloadov ali ključev. Novi Docker59776 je ponovno ustavljen; zasebne seje,
ključi, ID-ji in baza ostanejo ohranjeni. Noben star uspešen native scenarij
ali benchmark ni ponovljen. Odprta napaka iz prejšnjega dokumenta je za ta
dokazani samodejni tok **odpravljena**.

Celotni `flutter analyze` je vrnil0error,515obstoječihinfo in eno novo
opozorilo za neuporabljen import v HTTP testu. Import je odstranjen;
ciljni `dart analyze` te datoteke je nato čist (exit0). Drugih izvornih
sprememb po uspešnih tekih ni, testov zaradi odstranitve importa ne ponavljamo.
`git diff --check` je čist.
Popravek sam ne zaključuje P0/mobile/P8 ali N7.

## Vezani dokazi

- Popravljeni ciljni testi: `/tmp/kanban-choice-stale-fix-20261020/unit-fixed-attempt3.log`,
  SHA-256 `54cfd60ed120de311a3f1b6991c2b3d9d9ccaa7707d65f457293bb98b3e35bab`.
- Stari izvor, točna regresija: `unit-baseline-attempt2.log` v isti mapi,
  SHA-256 `f26065b30f6bba7104d72812851d8389db3bbd50927645c306b2a3e53eef3baf`.
- `crypto_finance_account_choices.dart` SHA-256
  `77939e4ec5493136d5b24517971343c0a7502babfcd9b2cfdbcc9236c631a694` (končni izvor obeh vej).
- Dodatne tri kontrole: `discovery-fixed-attempt1.log` v isti mapi,
  SHA-256 `2966a866c0ad5851fc874816bfb0e9f470407ee8a999cb74f8aa64828202af79`.
- Končni dejanski HTTP tek: `/tmp/jivie-finance-read-reuse-20261020/stale-choice-fixed-attempt2.log`,
  SHA-256 `27331f635ce8b0e8b6eff60d3f7138d2d05be55699a7b0a5bd2d953de5f21586`;
  `stale-choice-fixed-result.json` v isti mapi, SHA-256
  `921b1363c3c8df1ea02cee499241953fbc76a56ff11997c4c8199a9b68d18191`.

- Celotna analiza: `/tmp/jivie-choices-stale-root-20261020/flutter-analyze-final.log`,
  SHA-256 `4ced8ebc4fa5e02e657db688dee9bc64f117b7f66f97949eb7bcfefb98fd06c6`;
  po odstranitvi importa `http-test-analyze-fixed.log` v isti mapi, SHA-256
  `ecf6f0b5bb1b71012032fa809775cfba01ab69da474bb8edd282bff3fd74521a`.
