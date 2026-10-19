# E2EE: pogodbe in meje trenutnega izvora

17. oktober 2026. Ta zapis opisuje **delovni izvor `crypto2`/Capture3**,
ne nameščene različice ali končne potrditve celotne nadgradnje. Izhodna merila
ostajajo v [prvotnem načrtu](E2EE_UPGRADE_PLAN.md); priklopi so v
[zemljevidu kode](E2EE_CODE_MAP.md), stanje zaključevanja pa v
[izvedbi](E2EE_IMPLEMENTATION.md). Stari preview `crypto.*` in njegovi
nespremenljivi zahtevki ostajajo ločena združljivostna pogodba.

## Vklop in status

V2 handlerji zahtevajo dodajalno crypto shemo, PHP `ext-sodium` in izrecni
`FAMILYHUB_ENABLE_CRYPTO_PREVIEW=true`. Lokalni sintetični runtime ni dokaz
izpolnjenih gostovalnih predpogojev. Preview ne odpravi trajnih zapor že
pripetih kripto izvorov ali migracijskih fenceov, tudi če ga pozneje izklopimo.

V delovnem izvoru obstajajo dejanski V2 poslovni adapterji, Capture3 hladno
preverjanje in atomski `crypto2.migration.commit3`. Stara trditev, da je vsak
commit namenoma onemogočen, zato ne velja več. **To še ni produkcijska izdaja.**
Ob pisanju tega zapisa ima javni capability odgovor v `NativeService` še
stari V1-only oglas; končni V2 oglas mora glavni integrator povezati za istim
izrecnim preview stikalom. Oglas ne nadomesti preverjanja finaliziranega izvora.
Končni predstavniki na zamrznjenem izvoru in zaključna matrika še čakajo.

**P0 neodvisni pregled sestave protokola ostaja odprt.** Enotski testi,
Dart–PHP preizkusi in notranji pregledi niso ta pregled. P8 vključuje fizične
naprave, preverjeno izdajno/native sestavo, pravo strežniško kopijo in obnovo
ter novo izrecno odobritev namestitve. Ta izvor ne dovoljuje namestitve,
novih gradenj ali trgovinske oddaje.

## Primitive, serializacija in skrivnosti

`CryptoCodec` uporablja libsodium Ed25519, sealed boxes in XChaCha20-Poly1305.
Sealed box šifrira ključ za prejemnika, sam pa ne potrjuje pošiljatelja; namen,
identiteto in prejemnika veže ločen podpis. Dokumentni objekti in arhivi
uporabljajo libsodium secretstream ter preverjene velikosti, hashe, vrstni red
in zaključek. Zasebni koren, DEK in obnovitvena skrivnost niso strežniški ključi.

Podpisni domenski predponi ukazov in računskega dnevnika sta
`JivieE2EE/v2\n` in `JivieAccountLog/v2\n`; zapisi in batch commitments imajo
ločeni `JivieE2EE/record/v2\n` in `JivieE2EE/batch/v2\n`. Drugi namenski kodeki
imajo svoje predpone. Sprejem podpisanega JSON nikoli ne pomeni sprejema
poljubnega namena z istim podpisnim ključem.

`CryptoJson` je strogi transportni format: urejeni ASCII ključi, nespremenjen
vrstni red polj, preverjeno base64 kodiranje, cela števila v varnem JSON območju,
brez podvojenih ključev ali alternativnih bajtnih predstavitev. To ni splošna
implementacija RFC8785. **Poslovna vsebina ni omejena na ta format:**
`CryptoBusinessJson` in izvirne typed SQL celice ohranijo neznana polja,
float vrednosti in zgodovinske JSON nize znotraj šifriranih ovojnic.

Stabilne finančne uniqueness oznake izpelje `CryptoFinanceUniqueTags` z
**keyed BLAKE2b** (`libsodium genericHash`) iz preverjene najzgodnejše ustrezne
finance DEK osnove in namenskega konteksta. To ni HMAC. Capture3 uporablja
svojo ločeno HMAC-SHA256 izpeljavo soli/vezav; surovi hash zasebne izvorne
vrstice ni javni dokaz. Različnih izpeljav ne zamenjujemo.

To je lastna sestava standardnih primitiv, ne MLS ali HPKE. Ne obljublja
popolne tajnosti vse pretekle vsebine ob kraji dolgo ohranjenega obnovitvenega
ključa ali zaščite odklenjene naprave pred zlonamerno aplikacijo.

## Prijava, namestitev in račun

PHP še vedno preveri prijavno geslo in izda napravno sejo. Geslo ali e-poštni
reset **ne odklene E2EE na novi napravi**. Nova naprava potrebuje uporabnikovo
računsko obnovitveno datoteko oziroma obstoječi tok potrjene naprave.
Potrjena e-poštna identiteta pogojuje nove povezane zapise; lokalna uporaba
ostaja brez računa.

Ločeni so trije izdelki:

- Lokalni vault ščiti **celotno namestitev**, tudi lokalne podatke in predpomnjene
  particije. Njegov ključ ni sejni žeton.
- Računska obnovitvena datoteka veže `serverId/accountId` in računske korene.
  Ne vsebuje installation ključa, seje, navadnega device private ključa ali
  celotne podatkovne kopije.
- Prenosna šifrirana podatkovna kopija vsebuje izbrano vsebino in izrecne
  odvisnosti, ne novega pooblastila za strežniški zapis.

Datoteka nastane, se preveri in shrani lokalno po uporabnikovi izbiri.
Sistemsko deljenje je uporabnikovo dejanje; **Jivie SMTP je nikoli ne pošilja**.
Ponovni uvoz izbrane datoteke preveri obnovljivost; vrnitev iz OS dialoga sama
ni dokaz uporabne kopije. Varnostna pošta vsebuje samo dovoljen generičen
računski dogodek, brez vsebine, DEK ali datoteke.

## Podpisani računski dnevnik in svežina

`AccountDirectoryV2` preveri celoten append-only dnevnik, identiteto,
generacijo, prejšnjo glavo, command hash, snapshot in device snapshot.
`CryptoIdentityStore` loči SQL predpomnilnik od neodvisnega varnega sidra.
Po [uporabnikovi odločitvi 19. oktobra](E2EE_SHARING_SIMPLIFICATION.md) prvi
tuji stik zaupa povezavi račun–javni ključ, ki jo sporoči izbrano gostovanje.
Odjemalec še vedno preveri podpisano verigo in varno shrani koren; ta
samodejni način je ločen od neobvezne neodvisne primerjave varnostne kode.
Že pripetega korena ne zamenja tiho. Zaupanje imeniku ne nadomesti podpisanega
pooblastila za članstvo ali predajo ključev. Ta model ne zagotavlja zaščite
pred aktivnim upravljavcem, ki ponaredi identiteto ob prvem stiku.

Obnova preveri lastno verigo iz FILE pripetega korena, odobri novo napravo in
ohrani zgodovinske dokaze. Stara podpisana naprava ni zato ponovno trenutna.
Spremembe se podpisujejo in trajno shranijo pred prvim HTTP; receipt veže točno
zahtevo in bajte. Izgubljen ACK ne ustvari novega requestId. Zapis varnega floor
in promocija SQL predpone uporabljata obnovljiv staging; konkurenčni fork ne
sme zamenjati prej preverjene žive predpone.

Zgodovinska predpona znanega tujega računa mora vsebovati znano varno sidro
ali biti njegov dokazani prednik v ohranjeni preverjeni verigi.
`requireKnownDirectoryPrefix` ne odpira poljubnega najnovejšega tujega repa in
ne pripenja globalnega zaupanja samo zaradi članstva v prostoru.

Kratko, največ petsekundno preverjeno bralno okno omeji ponavljanje istih
preveritev. Po poteku začne novo logično okno; ne podaljšuje veljavnosti starega.
Pisanje ponovno preveri svežo identiteto, pravice, glavo in lifecycle.
Strežnik lahko zadrži podatke ali še neznano spremembo; dokaz proti že znanemu
rollbacku ni dokaz globalne najnovejše resnice.

## Prostori, epohe in pravice

`ScopeCryptoManager`, `ScopeCryptoCodec` in `SessionCryptoAccess` preverjajo
podpisano glavo/aktivacijo, effective roster, device snapshots, manageKeys,
ločeni CONTENT/FINANCE pravici in ključne commitments. Sprememba članstva,
lastništva, finance politike ali dostopa uporablja točen namenski intent,
zaprtja prejšnjih domen in svež CAS. Navadna poslovna pot ne sprejme zgolj
SQL `active`, strežniškega trenutnega epoch ali nepopolnega kandidata.

Legacy politika se pri normalnem branju vzpostavi iz finaliziranega
šifriranega baseline; nove prazne prostore veže podpisan izvor. Finance baseline
vsebuje točen `enabled/revision/requiredContractVersion/policyHash/grantCount`;
policy hash zajame celoten zajeti raw grant stream, tudi dormant vrstice.
Poznejši podpisani finance/access intenti sestavljajo nasledstvo. Marked
relocation izvor ima svoj finalizirani baseline; njegov avtor ni avtomatično
prvotni lastnik.

Lifecycle baseline, lastni/podedovani archive in exact previous lifecycle
hash so ločeni od vsebinskih epohe. Child-only dokaz uporablja opaque parent
token; ne daje starševskega rosterja ali DEK. Brisanje in premik ohranjata
iste obstoječe pravice, vključno s potrebnimi odobritvami drugih upravljavcev.

Pred migracijskim commitom je dovoljena samo tipizirana, omejena
`CryptoMigrationCandidate`: exact server/account/scope/capture/genesis,
epoch1, ničelni prednik in brez porabljenih access/finance intentov. Omogoča
namensko staging preverjanje in dovoljene ključe, **ne** običajnega currentHead,
varnega scope floora, zapisovanja poslovne projekcije ali navadnega WRITE.
Podoben zasebni relocation kandidat ni splošno dovoljenje novega izvora.

## Zapisi, zgodovina, checkpointi in datoteke

Posamezen zapis ima svoj podpisani record proof; batch commitment veže urejen
popoln niz digestov brez zasebnih sibling descriptorjev. Običajni batch ostaja
omejen na32 zapisov. Cilj, tip, revizija, prednik, epoch, lifecycle in metadata
morajo prestati klientovo preverjanje in strežniški ACL/CAS. Zneski ter besedila
ostajajo v šifriranem poslovnem ovoju. Podpis sam ne dokazuje veljavnosti vsote
povračil ali pravilnosti poslovnega modela.

Opaque zaporedje exact proof hashov, zaprtja domen, podpisani checkpointi in
lastni `scopeObserve` dokazujejo zgodovinsko vključitev. History-only sibling
lahko dopolni dokaz atomskega batcha po preverjeni current→ancestor verigi;
ne sme postati trenutna projekcija, saldo, ACK, obvestilo ali memo trenutne
avtorske authority. Bralnik ne zamenja starega observed inventoryja z
najnovejšim strežniškim inventoryjem pod istim imenom.

Signed metadata nameni `migrationOrigin`, `inlineDeletion` in
`projectRelocation` so medsebojno izključni. Označen zapis obvezno potrebuje
svoj finalizirani izvor/publication/inclusion dokaz; ne pade nazaj na navadno
WRITE preverjanje. Parser tagov sam ni authority. Staged tombstone ni navaden
izbris. Namenski večstranski koordinator preveri ves končni graf pred učinki
in ga objavi atomsko; ne zviša običajne omejitve batcha.

Velika poslovna vsebina, preglednice, Ideas slike in priponke uporabljajo
šifrirane dokumentne objekte in manifest. Reader preveri AEAD/secretstream,
celoten plaintext hash/velikost in semantične descriptorje pred projekcijo.
Cache ali uspešen blob GET ne nadomesti source/purpose/ACL dokaza.

## Finance, izbor računov in audit

En projektni strošek ostaja en kanoničen denarni zapis. Opaque finance topology
in podpisani contributor checkpointi varujejo popolnost organizacijskega
pregleda, tudi zadnjo odstranjeno povezavo. Manjkajoč ali zaseben potreben
prispevek je izrecno nepopoln, nikoli izmišljen ničelni saldo.

`financeAccountChoice` je saniran lokalni manifest izbire brez parent salda.
Source FINANCE READ izdajatelj podpiše celotno, tudi prazno izbiro; target
manager odobri isti salted/encrypted selection hash, target FINANCE WRITE pa
materializira običajni zapis. To je preverjena izpeljava pooblaščenega
izdajatelja, ne matematičen dokaz filtriranja poljubno zamolčanega ledgerja.
Target-only član ne potrebuje parent FINANCE ključa ali rosterja. Capture3
varianta loči issuerjev lastni FILE selector od targetovega lastnega FILE
preverjanja in finalnega companion izvora; med vlogami ne deli zasebnih arhivov.
Obstoječi `.structure.context/.contexts` closed variant
`financeAccountChoicesRequest` prenaša samo minimalni target context in blind
child binding. To je trajno usmerjanje zahteve, ne authority. Issuerjev lastni
FILE vodi v obstoječi signed offer/certificate, target manager odobri točno
izbiro, recipientov raw7 pa je tehnični Capture3 companion z obveznim finalnim
`materializationRole:financeAccountChoice` in `derivedPayloadHash`.

Linked-payment dogodki, cash in projekcije potrebujejo točne podpisane skupine,
unikatne keyed oznake ter preverjene disclosure/manifeste. Poznejši zasebni
catch-up uporablja iste izvirne zahtevke in ne podvoji denarja. Samostojen
izbris opravila ne izbriše že knjiženega stroška; izrecni izbris celotnega
projekta upošteva njegov pregledani denarni graf in zahteva FINANCE WRITE.

`CryptoFinanceAuditEvidence` združi navadno dokazano verigo z finaliziranim
migracijskim audit indeksom oziroma označenimi relocation snapshots. Ohrani
prvotni actor, časovni niz, logical revision, raw before/after JSON in unknown
celice. Fizični imported baseline1 ne ustvari lažnega novega legacy popravka.
Scoped audit rooti vseh prispevkov, tudi praznih, se preverijo pred lokalnim
filtriranjem recordId; seznam SQL vrstic sam ni dokaz odsotnosti zgodovine.
Relocation snapshot je označena manager-attested preslikava, ne ponarejen
prvotni avtorjev podpis.

## Capture3 in končni prehod

Javni `CryptoMigrationCoordinator` vodi trajne prepare/review/fence/archive/
cold verification/certification/activation/commit korake. Fence in maintenance
lease uskladita pisce, workerje in fizični cleanup. Izvor zajame celotne
zahtevane typed SQL vrstice, datotečne bajte, zgodovino, stare receipts in
ločene lastne zasebne namere; caller-selected podseznam ne dokazuje popolnosti.

FILE-only preverjanje uporablja novo šifrirano lokalno bazo brez starega
journala ali živih ključev za pisanje. Preveri source inventory, blind bindings,
AEAD/witness/canonical records, poslovno parity in pet control razdelkov
(structure, notifications, invitations, audit, receipts). Scoped finance-audit
indeks ostane vezan lastnemu scope, globalni audit razdelek pa verify3.
Domain contributioni, manager certifikati in njihovi lastni vključeni dogodki
vežejo exact iste roots. Final scoped activation poveže te dokaze; commit3
ponovno preveri popolno zamrznjeno komponento in jo namesti v enem SQL commitu.

Pripravljeni, staged, FILE-verificirani, objavljeni in committed niso sinonimi.
Objavljenega finalnega podpisa ni dovoljeno prezreti pri poznejšem resetu
generacije. Prekinitev ali izgubljen ACK nadaljujeta izvirni podpisani cilj;
automatičen povratek že pripetega E2EE v plaintext ni dovoljen.

Nove oziroma obnovljene stare offline namere imajo lasten account-partition
artefakt in karanteno. Izvirni bajti/ID/receipts ostanejo; uvoz ne aktivira
neposlanih operacij ali pripiše novemu računu tujih draftov.

## Povabila, dostava, moderacija in izbris

Nova povabila uporabljajo v4 intent in kasnejši pravi članski prehod. Stara
native povabila/mail se zajamejo nespremenjeno, brez novega tokena, roka ali
samodejnega resenda. Token-holder metadata capsule je **ne** E2EE skrivnost
pred hostingom, ki pozna stari tokenHash; authority dajejo podpisani bridge,
celoten cert/root, scoped final activation in vključeni dogodki. Prejemnik
vidi samo svoj leaf/capsule ter opaque digeststream, ne zasebnega batcha.
Stara povezava ne daje DEK: potreben je svež podpisani sprejem in manager
admission. Prehod null email recipient accountId v dejanski račun se preveri
z istim prvotnim tokenom/bridge podpisom in originalnim podpisanim sprejemom.
Numerična Kanboard project povabila ostajajo zunaj native migracije.

Generic push/mail ne vsebuje vsebine ali ključev. Scheduling podpisi dovolijo
minimalno strežniško usmerjanje/rok/closed stanje; worker po zaklepu preveri
trenutno authority, fence in provenance. Originalne dostavne identitete,
accepted stanje in lease se ne ponastavijo med migracijo. SMTP accepted pred
DB crashom še vedno pomeni obstoječo at-least-once negotovost, ne obljube
exactly-once. Moderacija razkrije samo uporabnikovo izbrano in pregledano
kopijo dokazila; nikoli ključa prostora.

Account deletion policy4 je dosegljiva z overjeno prijavo/geslom/OTP tudi brez
FILE. Pseudonimni carrier/tombstone ohrani nujne tuje podpisane dokaze, trajne
auth/recovery/device zapore pa preprečijo oživitev računa. Shared scope ostane
read-only do pravega prehoda preostalih članov; izbris ne ponaredi owner/DEK
rotacije in ne obljubi odstranitve drugih kopij ključev. **Prizadeti nedokončani
migracijski fence trenutno blokira izbris (`canDelete=false`)**; ne trdimo,
da obstaja nov zgodovinski plaintext reader/snapshot subsystem.

Signed scope/inline deletion vežeta točen pregledani graf, head/lifecycle CAS,
podpisan public header, scoped list inclusion in atomski own-log companion.
Parent finance-topology successor je del iste končne transakcije, kadar je
potreben. Tujemu child-only bralcu dokaz ne razkrije sibling grafov/finančnih ID.
Retained signed evidence, encrypted backups in zaznani legacy migration sources
so izrecno razkriti; aktivni izbris ni obljuba popolnega fizičnega cryptoerase.

## Vidnost strežniku in hramba

Strežnik vidi auth e-pošto/uporabniško ime, opaque račun/scope/record ID-je,
javne ključe in verige, effective članstvo/pravice, revizije, velikosti/število
šifratov, promet ter namenske minimalne scheduling/notification metapodatke
(npr. rok, closed, recipient IDs). Ne dobi vsebinskih zasebnih ključev. Pred
prehodom in do dejanskega čiščenja lahko skrbnik še bere stare SQL vire,
datoteke in stare strežniške kopije. Novi ciphertext tega ne izbriše za nazaj.

Uporabnik je določil **30 dni od dokumentirane dejanske uspešne obnove nove
šifrirane kopije** za stare berljive strežniške kopije. Rok ne začne teči ob
šifriranju, uploadu ali migracijskem commitu. Nepotrjena obnova zadrži cleanup;
vsako gostovanje/kopija potrebuje svoj dokaz in checkpoint. Fizično čiščenje
spada v poznejšo skupno namestitev; v tem izvornem delu se nič ne briše.
Potrebni podpisani/šifrirani dokazi preostalih uporabnikov se ohranijo.
