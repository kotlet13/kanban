# Poenostavitev deljenja E2EE

19. oktober 2026. Uporabnik je izrecno odobril spremembo modela zaupanja:
enostavno deljenje ima prednost pred obveznim neodvisnim preverjanjem prvega
stika. Ta odločitev nadomesti zahtevo po ročnem primerjanju kartic iz
prvotnega [načrta](E2EE_UPGRADE_PLAN.md#9-deljenje-preverjanje-identitet-in-naprave).
Ne spreminja zahteve po šifriranju vsebine, lokalne baze in obnovitvene datoteke.

## Dogovorjena meja zaščite

- Gostovanje ob prvem stiku poveže račun z javnim korenom identitete.
  Aplikacija preveri podpisano verigo in si sprejeti koren varno zapomni.
  To je zaupanje gostovanju ob prvem stiku, ne neodvisen dokaz osebe.
- Že zapomnjenega korena ni dovoljeno tiho zamenjati. Dokazana kontinuiteta
  naprav iste identitete ostane samodejna; nepojasnjena menjava identitete
  mora ustaviti predajo ključev in pokazati razumljivo opozorilo.
- Zasebni ključi, obnovitvena skrivnost in ključi vsebine ostanejo na
  napravah. Strežnik hrani šifrirano vsebino ter potrebne javne in
  administrativne podatke. Sam pregled nove šifrirane baze ne razkrije vsebine.
- Podpisana pooblastila, izrecni sprejem povabila, vloge, omejitve obsegov,
  svežina, zaščita pred ponovitvijo in preklic ostanejo obvezni. Strežniška
  vrstica članstva sama ne pooblasti izdaje ključa.
- Ta model ne obljublja zaščite pred upravljavcem, ki ob prvem stiku
  namerno ponaredi povezavo med računom in ključem. Prikaz upravljavca in
  uporabnikovo soglasje opredelita zaupanje; nista kriptografski dokaz.
- Neobvezna napredna primerjava identitete ostane mogoča. Za močnejše
  samodejno preverjanje proti aktivnemu upravljavcu bi potrebovali ločeno
  zasnovo neodvisno preverljivega imenika; to ni del te spremembe.

## Uporabniški tok

Ob prvi povezavi in povabilu je viden naslov gostovanja ter podatek o
upravljavcu, če ga gostovanje objavi. Manjkajoč podatek se ne nadomesti z
ugibanjem imena skrbnika ali lastnika prostora. Obstoječi gumb za nadaljevanje
oziroma pristop nosi soglasje; običajnemu toku ne dodajamo še ene potrditvene
kartice. Podatek o gostovanju ostane dosegljiv v nastavitvah.

Prejemnik sprejme isto povabilo brez kopiranja javnega JSON. Pooblaščena
naprava potrdi dostop prejemniku in opravi podpisovanje ter predajo dovoljenih
ključev. Če taka naprava ni na voljo, je dostop vidno čakajoč. Strežnik ne
dobi nadomestnega glavnega ključa. Obstoječa sprejeta povabila, ki čakajo na
ključe, morajo nadaljevati brez novega povabila, registracije ali FILE.

Geslo in e-poštni reset še vedno omogočita prijavo, ne samostojnega odklepa
vsebine na novi napravi. Za odklep ostane potrebna računska obnovitvena
datoteka ali potrjena naprava. Lokalna uporaba ostane brez računa.

## Izvedba in preverjanje

Izvedbo so opravili trije podagenti GPT-6.1 Sol/high; glavni agent je pregledal
meje pooblastil, integracijo in dokaze. Končna skupna analiza je zaključena.

| Del | Izvor | Namen |
| --- | --- | --- |
| Zaupanje prvemu stiku | `crypto_identity_store.dart`, `crypto_identity_verification.dart` | Varen trajni koren, izvor zaupanja, zavrnitev zamenjave/forka/rollbacka; ročna primerjava ostane razločena. |
| Podpisan imenik in povabila | `session_crypto_access.dart`, `invite_crypto_repository.dart` | Preverjena veriga, nadaljevanje starega povabila ob novejšem zapomnjenem imeniku, sprejem in lastnikova odobritev. |
| Podedovani projekti | `crypto_inherited_invitation_evidence.dart`, `crypto_inherited_invitation_grants.dart`, `scope_crypto_manager.dart` | Podpisan sprejem v nadrejeni prostor, točna povezava projekta, ohranjene neposredne pravice in nadaljevanje po prekinitvi. |
| Običajni UI | `crypto_invitation_page.dart`, `invitation_wizard.dart`, `crypto_approvals_page.dart` | Brez obveznega prenosa kartic, prikaz dostopa, ena lastnikova potrditev, vidno čakajoče delo. |
| Gostovanje | `hosting_information.dart`, `hosting_disclosure.dart`, `NativeService.php` | Javni, izrecno nastavljeni podatki upravljavca; nastavitve/prijava/povabilo, brez izpeljevanja zasebnih podatkov skrbnika. |

Dart poti v tabeli so pod `lib/organizer/data/e2ee`, `lib/organizer/domain`
oziroma `lib/organizer/presentation`; strežniška datoteka je pod
`server/plugins/FamilyHub/Model`. Nova strežniška informacija je dodajalna
razširitev javnih zmožnosti, brez DDL. Samo izrecno javni nastavitvi
`FAMILYHUB_HOSTING_OPERATOR_NAME` in `FAMILYHUB_HOSTING_OPERATOR_CONTACT`
se smeta prikazati. Gostovanje brez teh podatkov ali brez dosegljivega
odgovora ostane uporabno in je prikazano brez izmišljenega upravljavca.

### Prekinitev deljenja prostora

Sprejem povabila v nadrejeni prostor sam po sebi ne preda ključev že
obstoječih projektov. Nova pot pripravi trajen dnevnik pred aktivacijo
nadrejenega dostopa in nato nadaljuje projekte. Vrstica dnevnika je samo
navodilo za nadaljevanje, nikoli pooblastilo za izdajo ključa. Vsaka izdaja
znova preveri podpisano članstvo, prvotni sprejem, identiteto prejemnika,
povezavo projekta, politiko financ, življenjski cikel in sveže pravice.
Prekinitev ohrani isto povabilo in delo pokaže med čakajočimi odobritvami.
Začetek novega povabila ali nova obnovitvena datoteka nista potrebna.
Ob napaki na lastnikovi potrditvi je neposredna pot do čakajočih odobritev.
Dokončana opravila se ne potrjujejo znova. Osebna lokalna vsebina prejemnika
se s tem ne objavi.

Običajno branje zdaj prevzame manjkajoče dovoljene ključe iz aktivne predaje.
Uporabi obstoječe preverjanje podpisov, manifesta, prejemnikov, ovojnic in
zaveze ključa ter svežo preverbo istega aktivnega obsega. Obnova kandidatov
in dovoljenje za pisanje ostaneta ločeni poti.

### Meje dokazov

Preverjanje uporablja samo nov ločen Docker vsebnik s sintetičnima računoma,
loopback naslovom in začasno podatkovno shrambo. Testi nadaljujejo isto
stanje po posameznih popravkih; uspešnih priprav/prijav ne ponavljajo.
Neuspešen sestavljen tek ni označen kot v celoti uspešen zgolj zato, ker je
njegova prva faza uspela.

Potrjeno s ciljnimi preizkusi:

- 15 novih testov zaupanja imeniku in ena prizadeta sočasna CAS regresija:
  prvi stik, kontinuiteta, zamenjava korena, drugačen strežnik, SQL rollback,
  ohranjena ročna primerjava, staro povabilo ob novejšem zapomnjenem imeniku
  in točen podpisni predhodnik sprejema.
- 21 različnih novih testov podedovanega dostopa: podpisan sprejem,
  vloge/finance/arhiv, nespremenjene neposredne pravice, sprememba naprave,
  sveža revizija, trajno nadaljevanje, izpuščen projekt, napačen namig starša,
  napačna podpisana povezava in manjkajoč podpisan seznam projektov.
- Novi testi čarovnika in strani potrditve preverijo SL/EN, pot brez kartic,
  eno potrditev, čakajoč dostop, spremembo identitete, pozni odgovor in
  blokiranje podvojenega klika: 3 novi ciljni testi čarovnika, 8 novih testov
  strani in zadnji dodatni test neposredne poti v čakajoče odobritve PASS.
  Prvotni prizadeti čarovnik je imel 21 PASS v enem teku; po poznejših ozkih
  spremembah so bili izvedeni samo prizadeti novi testi, ne znova celoten tek.
- 7 novih testov običajnega prevzema ključev PASS: manjkajoča predaja,
  spremenjen prejemnik, napačna zaveza ključa, preklicano članstvo,
  prepovedan finančni dostop, ohranjeni ključi samo za branje brez novega
  prenosa in veljavna ponovljiva predaja. Ena prizadeta obstoječa regresija
  nadaljevanja čakajočega šifriranega zapisa PASS.
- Gostovanje: 8 začetnih novih Flutter testov ter ozko prizadete kontrole
  ločenega nedosegljivega/starega odgovora; javna zahteva brez poverilnic,
  zamenjava naslova, preklic/debounce, SL/EN pri 320 px in večjem besedilu,
  neveljavni podatki. PHP 4 scenariji × 3 kontrole in lint PASS.
- Dejanski HTTP: prvi običajni sprejem brez kartic, zavrnitev pred odobritvijo,
  lastnikova odobritev in odklep predhodne vsebine so uspeli. Poznejši del
  prvotnega sestavljenega testa je zastal ob dodani napravi, ker bi obstoječi
  obseg potreboval uskladitev naprav; celoten prvotni tek zato ni PASS.
- Ločen par v istem začasnem vsebniku: isto prvotno povabilo v organizacijo
  je sprejeto dvakrat z enim dejanskim sprejemnim zahtevkom in ohrani novejši
  podpisan imenik. Lastnikova odobritev in nadaljevanje predaje projektnih
  ključev sta dokončana. Nato isti prejemnik skozi običajno branje odklene
  točno vsebino projekta, ustvarjeno pred povabilom (**read-child PASS**).
- Dejanska podpisana zamenjava korena drugega računa: strežnik zavrne
  predajo že pri ponovnem branju sprejema (`crypto_invitation_acceptance_required`).
  Ciljno nadaljevanje istega zamenjanega stanja potrdi ohranjen prejšnji
  lokalni koren in natanko en bralni zahtevek, brez predaje ključev ali
  zapisovanja glave (**root-denial PASS**). To ni dokaz, da je tokrat zavrnil
  prav odjemalčev validator korena; ta ima ločene ciljne teste.

Med testi so bile odpravljene dejanske vrzeli: predaja ključa samo staršu,
branje finančne politike iz napačnega vira za izvorni projekt, stara
transportna revizija po podedovani spremembi dostopa in manjkajoč prevzem
projektnih ključev pri prejemnikovem običajnem branju. Pregled je dodatno
zaprl možnost lažne dokončanosti pri izpuščenem projektu. Zadnja podpisana
kontrola popolnosti je potrjena s ciljnimi testi in pregledom; predhodno
zaključenega dejanskega dnevnika nismo umetno odpirali za ponovno izdajo.

Diagnostične zaplete ločimo od teh napak: prvotno napačen testni klic
prejemnikovega API kot lastnik; preozko pričakovanje tipa zavrnitve v testu;
en konflikt Flutterjeve namestitve native assets pred začetkom Dart testa.
Flutter ukazi so bili nato zaporedni. Dosežena omejitev 601 zahtevkov je bila
skupna čez več poskusov, ne izmerjeno število enega deljenja; omejitve nismo
ponastavili. Izmerjeno poznejše nadaljevanje je imelo 152 zahtevkov, prvi
prejemnikov prevzem projektnih ključev pa 70. To ostaja opozorilo za
zmogljivost hladnih poti in večjih prostorov, ne meritev telefonske hitrosti.

Sanitizirani lokalni dnevniki so v
`build/qa/e2ee-sharing-simplification-20261019/FINAL.md` in vezanih logih.
Zasebne testne poverilnice, FILE in klientove baze niso v repozitoriju.
Po zaključku je odstranjen samo nov vsebnik
`jivie-simple-sharing-20261019-9d22b6c3` z njegovimi začasnimi volumni in
zasebnimi sintetičnimi datotekami. Ohranjeni mobilni/Mac QA viri niso odstranjeni.

Prva celotna analiza je razkrila eno že obstoječo neusklajeno deklaracijo
testnega `_Runtime.organizationFinanceCoverage`; tako izvorni API kot stari
neusklajeni test sta potrjena v začetnem `HEAD`. Popravek uskladi samo
opcijska imenovana parametra testnega pomočnika, brez spremembe finančne logike.
Ena ciljna obstoječa kontrola tega pomočnika PASS. Končni
`flutter analyze --no-fatal-infos` uspe: **0 error, 0 warning, 510 info**.
Spremenjeni Dart viri so formatirani, lokalizacije generirane z
`flutter gen-l10n`, `git diff --check` PASS. Ni ponovljenega celotnega Flutter
nabora, finančne matrike, native gradnje ali fizičnega preizkusa.

Fizični mobilni checkpoint ostane v
[mobilnem zapisniku](E2EE_MOBILE_TWO_USER_TEST_2026_10_18.md); ta sprememba
ne ponovi že uspešnih Mac testov in ne pomeni zaključka P0/P8 ali izdaje.

Produkcija, trgovinski različici, uporabnikovi podatki ter ohranjene mobilne
QA seje ostanejo nedotaknjeni. Stare berljive kopije ohranijo dogovorjeni
ločeni rok 30 dni po dokazani uspešni obnovi nove šifrirane kopije.
