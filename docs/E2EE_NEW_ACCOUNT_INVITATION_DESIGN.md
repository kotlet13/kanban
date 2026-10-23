# Predlog: povabilo novemu računu brez ponovne povezave lastnika

**Poznejša odločitev uporabnika: ta smer je zavrnjena.** Ohrani se običajno
e-poštno povabilo in časovno ločen sprejem/predaja: pošiljatelj prejme obvestilo
za potrditev dostopa. Novo naročilo dodaja samodejno dokončanje tega istega
dostopa, kadar pošiljatelj aktivno uporablja aplikacijo. Ne uvaja skrivne
povezave, novega invitation principala ali izvajanja ključne predaje v ozadju.
Spodaj je ohranjen zgodovinski predlog, ne aktivni izvedbeni načrt.

Stanje 23. oktobra 2026: **predlog po pregledu izvora, brez nove izvedbe ali
testov**. Obstoječi v5 za že pripravljen E2EE račun je zaključen v commitu
`b4648a7`; njegovo pogodbo in meje določa
[E2EE_PREAUTHORIZED_INVITATIONS_V5.md](E2EE_PREAUTHORIZED_INVITATIONS_V5.md).
Novi, še neobstoječi račun danes ostaja na v4 in potrebuje lastnikovo poznejšo
odobritev ključev.

Takrat odprto vprašanje osebne dostave skrivnosti je zdaj zaključeno: uporabnik
je predlog zavrnil. Aktivna izvedba je opisana v
[E2EE_INVITATION_FOREGROUND_APPROVAL.md](E2EE_INVITATION_FOREGROUND_APPROVAL.md).
Spodnje možnosti so ohranjene samo kot zgodovina odločitve.

## Predlagana kriptografska smer

Lastnik ob Send še nima prejemnikovega računskega javnega ključa. Lastnik zato
**ne ustvari prejemnikovega računskega korena, obnovitvene datoteke ali naprave**.
Prejemnik svoje računske ključe ustvari sam v obstoječem postopku zaščite računa.
Neodvisna naključna skrivnost povabila bi omogočila odpiranje vnaprej pripravljenih
šifriranih ovojev; običajni `fhi4` token za to ne zadošča, ker ga pozna gostitelj.

Kandidat za nadaljnjo analizo je izrecno podpisano mesto povabila v članstvu,
omejeno na povabilo in obseg, ter nova različica admission prehoda. To mesto ni
izmišljen uporabniški račun. Lastnik vnaprej podpiše točne pravice, prejemnikov
naslov, strežnik, povabilo, pripravo in dovoljeno vezavo bodočega računa.
Prejemnik nato z dvojnim podpisom ključa povabila in svoje dejanske naprave
zahteva atomarno zamenjavo točno tega mesta s svojim računom v trenutnem
nadrejenem/podrejenem grafu. Ostali člani, politika in key commitments se ne
spreminjajo. Ključ mesta po uspešnem prevzemu izgubi vsa pooblastila.

Predlagana je ozka kanonična zamenjava ob prevzemu, ne trajna dodatna plast
članstva ali obvod običajnega `headPut`. Omejeni principal ne sme postati splošni
upravljavec ali dobiti pooblastila za poljubno spreminjanje članstva. Potrebna je
izrecna pogodba dedovanja key epoch/grants, tudi za viewer in pravice brez financ;
samo en šifriran paket ne dokazuje pravilnega dostopa vseh takih vlog.

To **še ni določena žična pogodba**. Oblika glav, točna dovoljena sprememba,
vezava prejemnikovega imenika, veljavnost skozi rotacije ter preverjanje pri vseh
bralnikih ostajajo predmet analize. Obstoječa glava v5 ne dopušča poljubnega
nadomeščanja pripravljenega računa z novim računom. Tega ni dovoljeno prikriti
kot navaden v5 sprejem ali razrahljati verifierja, da bi sprejel nepodpisano
strežniško preslikavo. Pred izvedbo mora neodvisni pregled potrditi popoln,
omejen prehod in združljivost celotnega grafa prostorov.

## Dostava in meje zaupanja

Gostitelj sme dobiti javne dokaze, šifrirane ovoje in običajni lifecycle token;
ne sme dobiti nove skrivnosti ali celotne povezave, ki jo vsebuje. Zato iste
celotne povezave ne more sam sestaviti in poslati prek svojega SMTP. Lahko pošlje
obvestilo brez skrivnosti; neodvisni del bi poslal uporabnik prek izbranega kanala.

Tudi HTTPS fragment na trenutni strani povabila ni dovolj. Gostiteljev
`InvitationController` izvaja JavaScript, ki bere `location.hash`; skrbnik lahko
spremeni ta JavaScript. Celotna skrivna povezava zato ne sme skozi to stran.
Predlog preučuje neposredno povezavo `jivie://`, ki jo razčleni nameščena
aplikacija, in izrecni prilepi/kopiraj kot nadomestno pot. Lastna native shema sama
ne dokazuje, da povezavo prevzame prava aplikacija: drugo aplikacijo je mogoče
registrirati za isto shemo. Pred izdajo je zato treba določiti preverjeno
platformno dostavo oziroma uvoz datoteke in njune meje. Morebitna prihodnja HTTPS
vstopna točka bi potrebovala ločeno opredeljeno zaupanje in preverjanje.

Poznejša alternativa je pošiljanje iz naprave prek uporabnikovega ponudnika pošte.
To zahteva novo integracijo, OAuth/dovoljenja in opredelitev zaupanja; obstoječi
backend SMTP s tem ne postane varen kanal nove skrivnosti. Ta alternativa ni
izbrana ali izvedena.

Zaupanje v prvo uporabo računskega imenika ter gostiteljevo registracijo,
preverjanje e-pošte in SQL lifecycle ostaja izrecno. Prikazna imena in e-pošta
gostitelja niso kriptografski dokaz človekove identitete. Novi kanal doda zaupanje
v izbranega ponudnika pošte/sporočil in imetnika povezave: kdor pridobi celotno
skrivno povabilo, pridobi njegovo capability. Načrt ne dokazuje zaščite pred
ponudnikom, ki vidi vsebino sporočila, ali pred posredovanjem povezave.

Enkratna poraba, rok in preklic so pogoji poštenega gostitelja ter odjemalčevega
preverjanja. Ne trdimo, da zlonamerni gostitelj lahko kriptografsko izbriše že
razkrito skrivnost ali onemogoči že odprte stare ključe. Potrebni podpisani
odstranitveni prehodi in rotacije morajo biti določeni posebej.

## Predlagani uporabniški tok

1. Lastnik v obstoječem kontekstu prostora vnese e-pošto in izbere Send. Že
   pripravljeni računi nadaljujejo po v5. Samo točen rezultat »neobstoječ
   prejemnik« je kandidat za novo pot; manjkajoči ključi ali druga napaka niso
   tiha preusmeritev.
2. Po potrjeni pogodbi in odobrenem kanalu aplikacija pripravi in objavi celoten
   potreben šifrirani graf. Do potrjene objave ne pokaže povabila kot pripravljenega.
3. Lastnik vidi »Deli varno povabilo«, izbere svojo pošto/sporočila ali izrecno
   kopira povezavo. Prekinitev ohrani isto pripravo za nadaljevanje. Vrnitev iz
   sistemskega deljenja ne dokazuje dostave: primeren status je »Pripravljeno«
   oziroma »Predano izbrani aplikaciji«, ne »E-pošta dostavljena«.
4. Prejemnik odpre native povezavo ali jo prilepi v aplikacijo. Aplikacija jo
   najprej strogo razčleni in varno shrani. Omrežju posreduje samo dovoljeni
   običajni token in dokaze; skrivnost ostane lokalna.
5. Prejemnik se registrira in sam pripravi zaščito računa. Obstoječa shranitev
   obnovitvene datoteke ter njen svež zunanji uvoz ostaneta obvezna. Prekinitev
   ohrani povabilo. Priprava računa še ni sprejem povabila.
6. Ista pot pokaže svež preverjen pregled prejemnika, pošiljatelja, obsega, vloge,
   roka in vidnosti. En »Strinjam se in sprejmi« podpiše točen novi račun in
   odobreni prehod. Pregled je vezan tudi na capability, ne le server/token.
7. Točno potrdilo in podpisani dokazi odprejo prostor. Izgubljeni odgovor in
   restart najprej uporabita isto shranjeno zahtevo/potrdilo. Lastnik lahko ostane
   brez povezave; uspeh te lastnosti bo moral dokazati nov lokalni HTTP scenarij.

Predlagani konec lastnikovega dela je objavljena priprava in predaja celotnega
povabila izbranemu kanalu. Dejanski prejem sporočila ni lokalno preverljiv.
Ni časovnega workerja, samodejnega sprejema ali samodejnega ustvarjanja računov.

## Konkretna mesta v izvoru

| Področje | Obstoječe mesto in potrebna dopolnitev po odobritvi pogodbe |
| --- | --- |
| Lastnikov obrazec | `lib/organizer/presentation/shared/scope_invitation_form.dart`, `showScopeInvitation`: danes ustvari povabilo in pokaže snackbar; nov rezultat potrebuje varen, nadaljevalen prikaz deljenja. |
| Priprava | `lib/organizer/data/e2ee/invite_crypto_repository.dart`, ustvarjanje drafta in `_resolvePreauthorized`: današnji `localToken` ni nova neodvisna skrivnost; potrebna bo tipizirana lokalna dostava in ločena veja za nov račun. |
| Povezave | `lib/organizer/platform/invitation_links/invitation_link.dart`, `tryParseInput`, `_parse`, `_parseEmailLink`, `toUri`: danes dovoljujejo le fhi1–4, native povezava zavrne fragment/dodatna polja. |
| Hramba | `lib/organizer/data/pending_invitation_store.dart`, `PendingInvitation`, `deferred`, JSON in `receiveLink`: ohraniti capability skozi vse kopije in določiti njeno točno identiteto. |
| Native dogodki | `lib/organizer/platform/invitation_links/invitation_link_coordinator.dart`, `_sameLink`, `_receive`, restore: danes primerjajo samo server/token. Zamenjana skrivnost ne sme obdržati starega pregleda. |
| Drugi restore | `lib/organizer/presentation/shared/sharing_account_page.dart` ponovno sestavi `InvitationLink` iz pending zapisa; ohraniti nova lokalna polja. |
| Registracija | `lib/organizer/data/collaboration_email_invitations.dart`, `registerWithEmailInvitation`: `auth.registerInvitation4` danes prejme token in podatke računa. Nova skrivnost ne sme v parametre. |
| Zaščita računa | `lib/organizer/data/e2ee/account_crypto_v2_workflow.dart`, `prepareRecoveryFile`, `verifyAndInitialize`; `presentation/recovery/account_crypto_wizard.dart`, `_save`, `_import`: obstoječa lastna priprava ključev in svež uvoz. |
| Pregled in sprejem | `lib/organizer/presentation/shared/invitation_wizard.dart`, `_restore`, `_reviewMatchesCurrent`, `_authenticate`, `_joinEncrypted`: vezava na exact capability in isti račun/napravo/pregled. |
| Potrdilo | `lib/organizer/data/e2ee/invite_crypto_repository.dart`, `accept`, `resumeAccepted`: nova različica sprejemnega protokola, lokalni podpis in exact receipt pred odpiranjem. |
| Glave in ključi | `lib/organizer/data/e2ee/scope_crypto_codec.dart`, preverjanje prejšnjega managerja, imenikov, key reuse in activation; `scope_crypto_manager.dart`, `_grantAndActivate`; `session_crypto_access.dart`, meje ključev/closures in dedovanje grantov: omejena zamenjava mora biti samostojen preverjen prehod, brez popuščanja običajnim glavam. |
| Strežniško članstvo | `server/plugins/FamilyHub/Model/NativeCryptoScopeV2.php`, roster/parity ter popolnost grantov; `NativeCryptoInvitationV2.php`, registracija in podpisani sprejem; nova pogodba poleg `NativeCryptoInvitationPreauthorizationV5.php`: atomarna poraba celotnega grafa, CAS in točno potrdilo brez spremembe v4/v5 dokazov. |
| Dostava gostitelja | `server/plugins/FamilyHub/Model/NativeCryptoInvitationMailV2.php` pozna običajni token; `Controller/InvitationController.php` bere HTTPS fragment. Nobeden ne sme dobiti nove skrivnosti. |

`share_plus` 11.1.0 in `url_launcher` sta že odvisnosti. Povabila ju danes ne
uporabljajo za pošiljanje. Predlog je ločen, testljiv adapter za deljenje besedila;
obstoječi `PrivateFileChannel.shareRecovery` je strogo namenjen obnovitvenim
datotekam. Native podpora ali dostava novega adapterja še nista preizkušeni.

## Združljivost in ohranitev

Novi protokol potrebuje izrecno capability/version oglaševanje šele po pripravi
strežnika in odjemalca. V4 in v5 ostaneta veljavna; njihova podpisana telesa,
requestId, tokeni, ključi, claimi, journals, potrdila in podatki se ne prepisujejo.
Nova hramba naj bo additive; migracija ne sme ponovno podpisati starih zahtev ali
interpretirati starega tokena kot nove skrivnosti. Stari pending zapisi brez novega
polja ohranijo prvotni pomen. Stari klient mora neznano podpisano semantiko
zavrniti in zahtevati nadgradnjo; ne sme je preskočiti.

Za sprejem brez lastnikove povezave je treba določiti tudi obstoječe in pozneje nastale podrejene prostore,
politike, sočasne rotacije in odstranitve. Neznan ali nepopoln graf zavrne objavo
oziroma sprejem. Brez resetov, brisanja rezervacij, avtomatskega regranta ali
spreminjanja prejšnjih dokazov.

## Omejen nadaljnji načrt

1. Zaključiti odločitev o neodvisnem kanalu in pregled omejenega principala,
   podpisanega prehoda, različic ter celotnega grafa. Zapisati točno pogodbo pred
   runtime spremembami; nobena spodnja faza ne pomeni že odobrene dostave.
2. Po potrditvi pogodbe ločeno implementirati parser/varno hrambo in kriptografski
   protokol. Novi lokalni testi preverijo strogo obliko, roundtrip/restart,
   zamenjano skrivnost, stare povezave ter ohranitev pri Nazaj, preview in
   acceptance checkpointu. Pregledati vsako kopijo `PendingInvitation`.
3. Dodati ciljne UI kontrole: odpoved deljenja ohrani isto pripravo; retry ne
   ustvarja novega povabila; odpoved zaščite ohrani povezavo; po svežem uvozu
   sledi en končni pregled. Preveriti, da skrivnost ni v registracijskih,
   preview, accept ali SMTP parametrih in javnih diagnostičnih izpisih.
4. V novem izoliranem lokalnem HTTP okolju dokazati nov račun, sprejem in branje
   pripravljenega grafa brez lastnikovih HTTP zahtev. Ločeno preveriti izgubljeni
   ACK/restart z exact receipt ter napačno skrivnost/račun, preklic, rok,
   superseded pripravo in lažni consumed odgovor. Ohranjeni stari račun,
   zasebni prostor, zahteve in ključi morajo ostati isti.
5. Glavni in neodvisni pregled pogodbe, izvora in dokazov. Native/telefoni,
   dostava prave pošte ter produkcijska izdaja potrebujejo ločeno naročilo in
   dokaze; ta načrt jih ne izvaja.

Vsaka nova testna faza ima največ tri zunanje poskuse; FAIL in isto stanje se
ohranita. Uspešne nove kontrole in zgodovinski PASS se ne ponavljajo brez nove
relevantne spremembe. To je načrt preverjanja, **ne seznam že opravljenih testov**.

## Referenčna pojasnila

[Bitwarden Send](https://bitwarden.com/en-gb/help/send-encryption/) prikazuje
lokalno dešifriranje s ključem iz fragmenta povezave. To je primer ločitve ključa
od HTTP zahteve, ne dokaz zaščite pred JavaScriptom gostitelja. V tej aplikaciji
je konkretno branje fragmenta potrjeno v navedenem `InvitationController`.
[RFC 9180](https://www.rfc-editor.org/rfc/rfc9180.html) opisuje šifriranje za
prejemnikov javni ključ; sam po sebi ne rešuje dostave skrivnosti osebi, ki še
nima ključa. Predlog ne uvaja nove kriptografske primitive na podlagi teh virov.
