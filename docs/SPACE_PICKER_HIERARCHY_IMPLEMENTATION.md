# Izvedba hierarhičnega izbirnika prostorov

17. oktober 2026. Po izrecnem naročilu uporabnika je
[načrt izbirnika](SPACE_PICKER_HIERARCHY_PLAN.md) izveden v aplikacijskem izvoru.
Delo so opravili trije podagenti GPT-6.1 Sol z razmišljanjem high in glavni
agent, ki je povezal navigacijo, pregledal spremembe ter izvedel zaključne
kontrole. Naročeni zaključek je commit in push, brez trgovinske oddaje.

## Uporabniško vedenje

Krovni prostor s projekti ima ločeno puščico za razširjanje in zlaganje.
Dotik imena še vedno odpre prostor, dotik projekta pa neposredno njegov
pregled, tudi če je bil prej odprt koledar ali drugo področje. Prikaz zajame
lokalne projekte, skupne projektne obsege in starejše projekte v vsebini
skupnega prostora. Istoimenski oziroma enako identificirani lokalni projekti
v različnih prostorih se odprejo iz točno izbranega vira.

»Deljeno z mano« vsebuje dostopne projektne obsege drugih trenutnih lastnikov.
Lastni projekti so v hierarhiji ali kot samostojna izbira v »Prostori«.
Tuj projekt pod dostopnim prostorom je tudi bližnjica v deljenem zavihku.
Avtor projekta ni merilo lastništva. Starejši projekt brez samostojnega
članstva ostane pod svojim prostorom; izbirnik mu ne izmisli lastnika ali
neodvisne delitve.

Vnos v iskanje pokaže skupne rezultate obeh zavihkov. Zadetek otroka razširi
dovoljeno nadrejeno vejo, arhivirani zadetki pa so razkriti v arhivu.
Neposredno deljeni projekt brez dostopa do starša ne razkrije njegovega
imena ali drugih projektov. Med iskanjem ne podvajamo bližnjice projekta,
ki je že prikazan v drevesu. Brisanje iskanja vrne izbrani zavihek in
razširjene veje istega odprtega izbirnika. Stanje vej se ne shranjuje trajno;
ob novem odpiranju se razširi veja trenutno izbranega skupnega projekta.

Ohranjeni so »Vsi«, osebni prostor, nov prostor, arhiv in obstoječa delitev
med lokalno vsebino ter izbirno sinhronizacijo. Namizni odprti urejevalnik
prepreči preklop na projekt, dokler uporabnik ne konča urejanja.

## Preverjanje vira in dostopa

Izbira vsebuje konkreten prostor in po potrebi projekt ter identiteto
lokalnega delovnega prostora. Po zaprtju izbirnika se znova preverijo račun,
dostop, obstoj projekta in njegov vir. Navigacija po asinhronih korakih
preveri še generacijo navigacije in ponovno naložen lokalni posnetek.
Sprememba računa, izbris ali odvzem dostopa zato ne nadaljuje stare izbire.

Izbirnik in navigacija uporabljata isti resolver osebnega posnetka. Novejši
posnetek trenutno odprtega osebnega prostora ima prednost pred zastarelim
katalogom, zasebni posnetek pa mora pripadati trenutnemu računu in osebni
vrstici. S tem je odpravljeno tudi neskladje, ugotovljeno pri neodvisnem
pregledu, ki bi med osveževanjem lahko tiho zavrnilo veljaven klik.

## Preverjanja

- Ciljni widget preizkusi: **56 PASS** (29 izbirnik, 27 lokalna/skupna
  navigacija; skupaj55 in dodani zasebni primer posebej1). Pokrivajo hierarhijo, lastništvo, globalno iskanje,
  neposredno deljene in arhivirane projekte, zavrnitev zastarele izbire ter
  lokalno in skupno odpiranje konkretnega projekta na telefonu in namizju.
- Navigacijska regresijska zbirka: **123 PASS**, vključno z zgodovino Nazaj,
  namiznim urejevalnikom in osnutki, nastavitvami prostora ter skupnim ovojem.
- `flutter gen-l10n` in formatiranje sta izvedena. Celotni `flutter analyze
  --no-pub` vrne samo **10 predhodnih info** v `tools/release`, brez novih
  ugotovitev ter brez warning/error. Analiza zaradi teh info vrne exit1.
- Vizualno pregledana dejanska widget izrisa s pisavami pri širini390 in
  pri320/dvojni pisavi: `build/qa/upgrade-navigation/hierarchy-expanded-390.png`
  ter `hierarchy-global-search-320-2x.png`. Dolga besedila se omejijo znotraj
  vrstic; to ni dokaz fizične namestitve na telefonu.
- `git diff --check` in preverjanje relativnih povezav dokumentacije PASS.

## Strežnik in izdaja

Nov [dokument strežniških predpogojev](server/SPACE_PICKER_RELEASE_PREREQUISITES.md)
pojasni že obstoječo pogodbo, primerjavo z nameščenim izdajnim paketom in
ozke kontrole pred poznejšo javno objavo. Za to prenovo ni potrebna nova
shema, API ali namestitev FamilyHuba. V tem koraku ni bilo živih posegov
na strežniku, nove native gradnje ali spremembe različice aplikacije,
SDK, odvisnosti, ključavnic odvisnosti ali dovoljenj.

[Finančna nadgradnja](ORGANIZATION_FINANCE_PLAN.md) ostaja ločen načrt;
njena prijavljena zanka dodajanja in povezava projektnih transakcij z računom
organizacije nista del te izvedbe. Javna izdaja potrebuje novo izrecno
naročilo uporabnika.
