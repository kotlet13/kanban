# Načrt računov organizacije in projektnih pregledov

Dogovor z uporabnikom, 17. oktober 2026. **Po naknadnem izrecnem naročilu
»dej kr nared nadgradnjo še financ« je izveden v izvoru.** Končno obliko,
preverjanje in meje vodi [zapis izvedbe](ORGANIZATION_FINANCE_IMPLEMENTATION.md),
preostale gostovane korake pa [strežniški predpogoji](server/ORGANIZATION_FINANCE_RELEASE_PREREQUISITES.md).
Spodaj ostaja prvotni dogovor in analiza takratnega izhodišča.
Računi pripadajo organizaciji oziroma nadrejenemu prostoru,
projekti pa omogočajo ločen pregled pripadajočih stroškov in prilivov.
Prva faza ne dodeljuje ali rezervira denarja projektom.

## Potrjena uporabniška smer

- Finančni račun je mogoče ustvariti neposredno v organizaciji oziroma
  prostoru, tudi če nima nobenega projekta.
- Priliv ali strošek se naveže na konkreten račun in po potrebi na projekt
  tega prostora. Splošne transakcije prostora lahko ostanejo brez projekta.
- Pregled računa pokaže njegove prilive in stroške; projektni pregled pokaže
  samo transakcije izbranega projekta. Organizacijski pregled zajame dovoljeno
  celoto, vsako transakcijo in njen denarni učinek samo enkrat.
- Projektni »podračun« v prvi fazi pomeni ločen pregled istega računa,
  ne samostojnega računa z dodatnim začetnim stanjem ali denarjem.
- Projekt lahko ima svoj proračun, vendar proračun ni finančni račun.
  Izdelava ali prenova proračunov ni del tega začetnega obsega.
- Član samo posameznega projekta vidi njegove dovoljene finančne podatke;
  povezava z računom prostora mu ne odpre drugih projektov, vseh transakcij
  ali celotnega stanja računa nadrejenega prostora.

Primer: račun TriparNA ima splošen strošek 50 EUR ter strošek projekta
»Dogodek« 300 EUR. Pregled računa pokaže oba, projekt »Dogodek« samo 300 EUR,
skupni stroški pa znašajo 350 EUR. Projektni prikaz ne ustvari kopije stroška.

## Prijavljena napaka pri dodajanju

Uporabnik je na Androidu v Financah organizacije TriparNA izbral
»Dodaj v prostor« in nato TriparNA. Dialog se je zaprl, obrazec pa se ni odprl.
Priložena posnetka `1000012088.jpg` in `1000012090.jpg` prikazujeta izbiro
in vrnitev na prazen pregled.

Vzrok v pregledanem izvoru: [SharingWorkspace](../lib/organizer/presentation/shared/sharing_workspace.dart)
za Finance organizacije uporabi zbirni `AllSpacesPage` brez namenskega
`onCreateSource`. [Izbira cilja](../lib/organizer/presentation/all_spaces/all_spaces_page.dart)
zato kliče navigacijo, [organizer shell](../lib/organizer/presentation/organizer_shell.dart)
pa ponovno izbere isto organizacijo in isto področje. Obrazec za ustvarjanje
se ne sproži. Načrtovani popravek mora omogočiti neposredno dodajanje računa
in transakcije v izbranem prostoru brez te zanke.

## Zmožnosti FamilyHuba in potrebna razširitev

Izhodišče je FamilyHub 0.15.0 / schema19 iz
[zapisa nameščene izdaje](server/UPGRADE_0_15.md). Ta pogovor je preveril
izvorno kodo; ni izvedel novega preverjanja živega strežnika.

Obstoječa finančna pogodba dopušča račune in transakcije na organizaciji.
Za ta osnovni primer je treba urediti aplikacijski tok. Splošna povezava
projektnih transakcij z računom nadrejenega prostora pa zahteva razširitev
aplikacije in vtičnika FamilyHub:

- [Finance2 validator](../server/plugins/FamilyHub/Model/NativeFinancePlanningPolicy.php)
  račun transakcije išče znotraj istega `scope_id`. Skupni `financeEntry`
  nima splošnega polja za navezavo na projekt nadrejenega prostora.
- [Model skupnega računa](../lib/organizer/domain/shared_finance_models.dart)
  nima povezave na nadrejeni finančni račun; trenutni projektni računi so
  ločeni zapisi v svojih obsegih.
- [Povezana plačila](server/linked-payments-api-contract.md) že omogočajo
  povračilo osebnega plačila iz računa nadrejene organizacije. To je poseben
  tok, ne splošna podpora običajnim projektnim prilivom in stroškom.

Obstoječe gostovanje zadostuje; nov strežnik ni potreben. Natančna oblika
povezave, različica pogodbe in morebitna migracija sheme se določijo ob
izvedbenem načrtovanju. Prikaz naj temelji na enem kanoničnem finančnem dejstvu
z omejenimi projektnimi pogledi, ne na podvojenih knjižbah.

## Merila prihodnje izvedbe

1. V prazni organizaciji je mogoče ustvariti račun in nanj vnesti priliv ali
   strošek brez projekta; izbira istega prostora odpre ustrezni obrazec.
2. Transakcija, pripisana projektu, se pravilno pojavi v projektnem pregledu
   in pregledu izbranega računa; skupni seštevki je ne podvojijo.
3. Projektni član lahko dela v dovoljenem projektnem obsegu brez pridobitve
   dostopa do vseh financ nadrejenega prostora. Omejitve veljajo na strežniku
   ter pri sinhronizaciji, izvozu in lokalnem prikazu.
4. Obstoječi računi, transakcije, povezana plačila in zgodovina se ohranijo.
   Pred spremembo modela se določi preslikava obstoječih projektnih računov;
   računov se ne združuje samodejno samo zaradi enakega imena.
5. Lokalna uporaba, osnutki, ponovitve sinhronizacije, konflikti ter prenosna
   kopija in obnova ohranijo povezave brez podvajanja. Različne valute ostanejo
   ločene. Starejši odjemalci imajo opredeljeno združljivost.

## Prvotne odprte podrobnosti in meja naročila

Pred izvedbo določimo končna imena gumbov in filtrov, izbiro računa ob vnosu
v projekt, ravnanje pri arhiviranju ali izbrisu projekta ter preslikavo
obstoječih podatkov. Možnost, da projekt uporablja več računov prostora,
je predlog za izvedbeno razjasnitev, ne dodatna obvezna funkcija tega dogovora.

Uporabnik je prvotno naročil zapis načrta in nato pogovor o naslednji nadgradnji;
poznejše naročilo za izvedbo je navedeno na vrhu. Naročilo za izvor in commit/push
ne vključuje namestitve vtičnika ali nove trgovinske oddaje. Poznejši strežniški poseg sledi
obstoječemu postopku sveže kopije in preverjene izolirane obnove.
