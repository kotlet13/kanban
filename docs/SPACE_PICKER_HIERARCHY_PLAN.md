# Načrt hierarhičnega izbirnika prostorov

Dogovor z uporabnikom, 17. oktober 2026. **Status: izvedeno v izvoru po
naknadnem izrecnem naročilu uporabnika istega dne.** [Izvedba in preverjanje](SPACE_PICKER_HIERARCHY_IMPLEMENTATION.md)
ter [strežniški predpogoji izdaje](server/SPACE_PICKER_RELEASE_PREREQUISITES.md)
vodijo dejansko stanje. Spodaj je ohranjen dogovorjeni obseg. Izbirnik naj pokaže projekte pod njihovimi krovnimi prostori,
omogoči zlaganje in razširjanje ter najde projekte tudi v zloženih vejah.
»Deljeno z mano« naj pomeni dostopne projekte, katerih trenutni lastnik
ni prijavljeni uporabnik.

## Dogovorjeno vedenje

- Zavihek »Prostori« ohrani krovne prostore. Prostor s projekti dobi puščico
  za razširitev oziroma zlaganje; pod njim so zamaknjeni njegovi projekti.
- Dotik imena izbere prostor, dotik puščice razširi ali zloži njegove projekte.
  Prostor brez projektov nima neuporabne puščice. Dotik projekta odpre projekt.
- Iskanje zajame dovoljene prostore in projekte, tudi kadar je nadrejeni
  prostor zložen. Zadetek projekta pokaže njegovo dovoljeno nadrejeno vejo
  in jo med iskanjem razširi. Iskanje ne sme zahtevati predhodnega ročnega
  preklopa na drugi zavihek, da bi uporabnik sploh našel projekt.
- »Deljeno z mano« vsebuje dostopne projekte drugih lastnikov. Lastni
  projekti ne sodijo v ta razdelek; merilo je trenutno lastništvo, ne avtorstvo.
- Projekt drugega člana znotraj dostopne organizacije ostane viden pod
  organizacijo in ima dodatno bližnjico v »Deljeno z mano«. Gre za isti projekt
  z istim ID, ne kopijo ali dodatno članstvo.
- Projekt, do katerega ima uporabnik dostop brez dostopa do nadrejenega
  prostora, je v »Deljeno z mano«. Izbirnik ne razkrije nedovoljenega
  nadrejenega prostora, njegovega imena ali sorodnih projektov.

## Trenutna težava

Uporabnikov posnetek `1000012092.jpg` kaže krovne prostore in iskalno polje
»Poišči prostor ali projekt«. Trenutni
[izbirnik](../lib/organizer/presentation/shared/space_picker.dart) razvršča
po vrsti zapisa: v »Prostori« vse neprojektne prostore, v »Deljeno z mano«
pa vse skupne projekte, tudi lastne. Iskalni filter se uporabi samo na
trenutno izbranem zavihku. Hierarhija in lastništvo pri razvrščanju nista
upoštevana, čeprav imamo osnovne podatke zanju.

## Lastništvo in ustvarjalec

[FamilyHub](../server/plugins/FamilyHub/Model/NativeScopeService.php) ob
ustvarjanju skupnega prostora ali projekta shrani `owner_id` in ustvarjalcu
dodeli članstvo `owner`. [Odjemalski model](../lib/organizer/domain/collaboration_models.dart)
že pozna `role` oziroma `isOwner` ter `parentSpaceId`. To zadošča za osnovno
razvrščanje dovoljenih skupnih projektov po hierarhiji in lastništvu.

Lastništvo organizacije ne pomeni nujno lastništva vsakega njenega projekta:
projekt lahko ustvari in ima v lasti drug član. Dostop do njega je lahko
neposreden ali podedovan iz članstva prostora; dostop ni isto kot lastništvo.

Ustvarjalec je ločen zgodovinski podatek. Novejši skupni projektni zapisi
hranijo `created_by` oziroma `createdByAccountId`. Krovni prostor nima
ločenega trajnega polja za prvotnega ustvarjalca; trenutni lastnik se lahko
ob prenosu lastništva spremeni. Lokalni prostori brez prijave nimajo
strežniške uporabniške identitete lastnika. Prenova izbirnika ne uvaja nove
zgodovine avtorstva in ne sklepa o ustvarjalcu iz trenutnega lastnika.

## Obseg prihodnje izvedbe in preverjanja

Osnovna prenova skupnega izbirnika lahko uporabi obstoječe podatke FamilyHuba.
Za lokalne projekte je treba uporabiti njihove lokalne povezave s prostorom;
ne ustvarjati strežniških obsegov ali vključevati sinhronizacije zaradi prikaza.

Ob izvedbi preverimo razširitev, izbiro krovnega prostora in projekta,
iskanje po zloženih vejah, lastne in tuje projekte, podedovan dostop ter
dostop samo do projekta. Ohranimo »Vsi«, osebni prostor, ustvarjanje novega
prostora, prikaz arhiva in preverjanje dostopa ob izbiri. Lastni samostojni
projekt brez dostopnega nadrejenega prostora mora ostati dosegljiv v
»Prostori«, ne izginiti zaradi izključitve iz »Deljeno z mano«.

Odvzem dostopa ali menjava računa med odprtim izbirnikom ne smeta odpreti
stare izbire. Prikaz na ozkem telefonu, pri povečani pisavi ter na iOS in
namizju mora jasno ločiti dotik za izbiro od dotika za razširitev.

Pri izvedbi so izbrani skupni iskalni zadetki obeh zavihkov, pomnjenje vej
znotraj odprtega izbirnika in samostojni lastni projekti v »Prostori«.
Prvotno naročilo je zajemalo samo načrtovanje; poznejše izrecno naročilo
istega dne dovoljuje izvedbo, commit in push, ne strežniške ali trgovinske oddaje.

Sorodni ločeni načrt: [računi organizacije in projektni finančni pregledi](ORGANIZATION_FINANCE_PLAN.md).
