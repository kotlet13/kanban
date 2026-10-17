# Strežniški pogoji pred javno izdajo hierarhičnega izbirnika

17. oktober 2026. Obseg je prenova izbirnika iz
[dogovora o hierarhiji](../SPACE_PICKER_HIERARCHY_PLAN.md). Ta zapis temelji
na branju izvora in obstoječih dokazov namestitve; v tem pregledu ni bilo
prijave na gostovanje, živega API preizkusa, spremembe podatkov ali namestitve.
Commit/push aplikacijskega popravka ni javna izdaja aplikacije.

## Sklep za to prenovo

**Za hierarhijo, iskanje in razvrstitev po trenutnem lastništvu ni potrebna
nova strežniška koda, API metoda, namestitev FamilyHuba ali migracija sheme.**
Obstoječa pogodba vrača potrebne podatke in že upošteva neposredni ter
podedovani dostop. Lokalni projekti uporabljajo svoje lokalne povezave;
prikaz drevesa ne zahteva njihove objave v oblak.

Zadnji [dokazani nameščeni stanji](UPGRADE_0_15.md) produkcije
`jivie.triparna.si` in preglednega test1 sta FamilyHub **0.15.0 / shema19**
z dne 16. oktobra. Ta zgodovinski dokaz ni nov pregled današnjega živega
stanja. Postopka prehoda18→19 zaradi izbirnika ne ponavljamo.

## Kaj je preverjeno v izvoru

| Podatek oziroma pravilo | Preverjena izvedba |
| --- | --- |
| Dovoljeni prostori in projekti | [NativeScopeService::execute](../../server/plugins/FamilyHub/Model/NativeScopeService.php): `scopes.list` zajame neposredno članstvo ter dovoljeni podedovani dostop, nato uporabi osrednje preverjanje dostopa. Organizacije, arhiv in spremembe dostopa se vključujejo z obstoječimi zastavicami. |
| Povezava s staršem | [NativeDatabase::scopeWire](../../server/plugins/FamilyHub/Model/NativeDatabase.php) vrne `parentScopeId`, `parentScopeKind` ter združljivi `organizationId`. Odjemalski [SharedScope](../../lib/organizer/domain/collaboration_models.dart) uporablja `parentScopeId ?? organizationId`. |
| Lastništvo projekta | [NativeOrganizationAccess::decorate](../../server/plugins/FamilyHub/Model/NativeOrganizationAccess.php) ohrani neposredni `owner` projekta; lastnik nadrejenega prostora je na tujem projektu prek dedovanja `member`. Lastništvo starša zato ne ustvari lažnega lastništva otroka. `SharedScope.isOwner` bere vrnjeno vlogo. |
| Nastanek in prenos lastništva | `scopes.create` shrani `owner_id` in neposredno članstvo `owner`. [NativeAccountDeletionService](../../server/plugins/FamilyHub/Model/NativeAccountDeletionService.php) pri obstoječem potrjenem prenosu spremeni oba podatka. Avtor zapisa `createdByAccountId` ni merilo trenutnega lastništva. |
| Starejši projekti v vsebini prostora | Inline projekt nima samostojnega projektnega članstva ali ločenega strežniškega lastnika. Veljajo pravice njegovega obsega. [Izločitev projekta](../../server/plugins/FamilyHub/Model/NativeProjectSharingService.php) že obstaja kot ločen izrecni postopek; izbirnik je ne sme sprožiti zaradi prikaza. |
| Odvzem in izbris | `scopes.list(includeAccessChanges:true)` vrača `revokedScopeIds` in `deletedScopeIds`; [sinhronizacija](../../lib/organizer/data/collaboration_sync_actions.dart) ju uporabi za lokalno stanje. Pri normalnem odvzemu članstva prostora veljajo aktualna [lifecycle pravila](scope-lifecycle-api-contract.md), vključno z njegovimi projekti. |

Vseh šest zgoraj pregledanih strežniških datotek je bilo tudi **bajtno
primerjanih z obstoječim izdajnim paketom** `build/releases/FamilyHub-0.15.0.zip`:
`NativeScopeService.php`, `NativeOrganizationAccess.php`, `NativeDatabase.php`,
`NativeAccountDeletionService.php`, `NativeProjectSharingService.php` in
`Schema/SharingSchema.php`. Vseh šest se ujema. SHA256 celotnega paketa je
`5c14ca9a79d92cf1c5f71b681d8417f44f4bfb9b474443cdad4dbb3f589f51e7`,
isti kot v dokazu nameščene izdaje. Pregled ni odkril neskladja med vlogo
lastnika in opisano logiko dedovanja; dejanskih živih vrstic ni pregledoval.

## Najmanjši koraki pred poznejšo javno izdajo

1. Zabeležimo svež bralni pregled produkcijskih zmožnosti: pričakovani HTTPS200,
   ista identiteta strežnika, omogočen Native API ter obstoječe zmožnosti
   organizacij, projektnega članstva, arhiva in sprememb dostopa. Preverimo
   ohranitev že nameščenega izhodišča0.15.0/shema19 iz dokaza nadgradnje;
   javni capabilities odgovor sam ni dokaz sheme ali enakosti vseh datotek.
   Morebitno odstopanje najprej raziščemo, brez samodejne ponovne namestitve.
2. Na namenskem testnem računu z obstoječimi preizkusnimi podatki osvežimo
   seznam in preverimo: lasten projekt nima bližnjice »Deljeno z mano«;
   tuj projekt pod dostopnim prostorom je v drevesu in kot bližnjica z istim
   ID; lastnik prostora na projektu drugega člana dobi `member`, lastnik
   projekta pa `owner`. Preverimo neposredni in podedovani dostop.
3. Račun z dostopom samo do projekta mora dobiti projekt brez nedovoljenega
   prostora in sorodnih projektov v seznamu; izbirnik ne sme prikazati imena
   nedovoljenega starša. Lasten samostojni projekt ostane dosegljiv.
4. Na testnih podatkih preverimo arhiv, osvežitev po odvzemu dostopa ter
   menjavo računa med odprtim izbirnikom. Stara izbira ne sme odpreti
   nedovoljene vsebine. Primerjamo tudi isti projekt, odprt iz drevesa in
   bližnjice. Za ta preizkus ni treba pošiljati novih produkcijskih povabil
   ali posegati v resnična uporabniška članstva.

To so ciljne bralne in uporabniške kontrole obstoječe pogodbe; nova splošna
strežniška migracijska ali gradilna matrika samo zaradi izbirnika ni potrebna.
Pred javno trgovinsko oddajo ostaja potrebna nova izrecna uporabnikova
odobritev konkretne izdaje. Ta dokument ne potrjuje izvedbe zgornjih živih
kontrol, nove gradnje, namestitve na telefon ali trgovinske oddaje.

## Ločena prihodnja finančna nadgradnja

[Organizacijski računi in projektni finančni pregledi](../ORGANIZATION_FINANCE_PLAN.md)
ostajajo načrtovani. Finance2 trenutno išče račun transakcije v istem
`scope_id`; splošna povezava projektne transakcije z računom nadrejenega
prostora še potrebuje dogovorjeno razširitev aplikacije in FamilyHuba.
Hierarhični izbirnik tega ne implementira in ne odpravlja prijavljene zanke
»Dodaj v prostor« v Financah.

Ko bo ta ločena nadgradnja naročena, je treba najprej določiti podatkovni
model, strežniški ACL projektnih pogledov, združljivost starejših odjemalcev
ter ohranitev obstoječih računov in knjižb. Šele takrat se določi različica
pogodbe, morebitna shema in namestitveni postopek na obstoječe gostovanje.
Pred vsako dejansko spremembo podatkov ali sheme ostajata obvezni sveža polna
zasebna kopija in preverjena prava izolirana obnova. To ni predpogoj za
sedanjo prenovo izbirnika, ki strežniškega stanja ne spreminja.
