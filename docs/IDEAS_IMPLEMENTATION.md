# Idejnik — uredljive table

**Poznejši naročeni izdajni korak:** test2 je nadgrajen na FamilyHub0.13/schema17,
Android1.6.0(23) je Aktivno za domači(15) od12. oktobra11:52.
[Dejanski izdajni dokazi](release/IDEAS_RELEASE.md) imajo prednost pred spodnjim
izhodiščem priprave. Fizična posodobitev telefona še ni potrjena.

12. oktober 2026. Uporabnik je po pregledu načrta naročil izvedbo. Izhodišče je
main1e79460, Android1.5.2(22), izvor in test2 FamilyHub0.12.0/schema16. Ta dokument
ločuje dogovor, lokalno izvedbo in dejanske dokaze. Nova gostovana namestitev ali
trgovinska izdaja še nista izvedeni.

## Potrjen obseg

Ena ideja je tabla z naslovom, besedilom/lističi, fotografijami, svinčnikom,
markerjem, radirko, puščicami/črtami/okvirji. Elementi se izbirajo, premikajo,
povečujejo in vrtijo. Oznake in opombe lahko pripadajo fotografiji; ob premiku ali
spremembi fotografije ohranijo lego. Tabla omogoča pan/zoom in undo/redo.
Izbira/premikanje ter risanje sta ločena načina za dotik in miško.

Lokalno delo zajame osebni prostor, gospodinjstvo, organizacijo in njihove
projekte. Deljenje sledi trenutnemu gospodinjstvu/organizaciji/projektu in
obstoječim članstvom; Vsi ni zapisovalni cilj. Lokalni osnutek se sproti ohranja,
Shrani potrdi vsebino in šele nato pripravi skupno operacijo/obvestilo.
Različni spremenjeni elementi se združujejo; konflikti istega elementa ohranijo
obe različici. Privzeti izklopi obvestil ter upravičenost ostanejo spoštovani.

Fotografije so dejanski preverjeni bajti v zasebni hrambi, ne oddaljeni URL-ji.
Kopija in samostojna obnova morata vsebovati fotografije in uredljive elemente.
Manjkajoči prenos mora biti viden; nedosegljiv strežnik ne izbriše lokalne table.
Prijava skupne table zajame tudi skico/slike, z omejenim predogledom in varnim
skrbniškim prikazom. AI, video, kamera in javne povezave niso naročeni.

## Skupna pogodba in lastništvo

- Podatki/stanje/Dart: agent ideas_data, domain/data/state in podatkovni testi.
- Prikaz: agent moderation_ui (prevzem začetnega ideas_ui), presentation/l10n in UI testi/posnetki.
- Strežnik: agent ideas_server, server/plugins/FamilyHub in PHP/HTTP testi.
- Glavni agent: pogodbe, dokumentacija, pregled, integracija, končno preverjanje.

Začetna pogodba: IdeaBoard(id,title,projectId?,width,height,elements,revision,
createdAt,updatedAt), JSONversion1. Element ima trajni id, kind, geometrijo,
rotation/barvo/debelino, ustrezno besedilo/točke/asset in parentImageId?.
Poteze/oznake vezane na sliko uporabljajo slikovne lokalne koordinate; ostali
elementi so v koordinatah table. Rotacija in merilo slike se upoštevata tudi pri
hit-testu. Enota debele poteze in meje so enake v Dart/PHP.

IdeaAsset(sha256,mime,size,width,height) je nespremenljiv; dostop je vezan na
račun/strežnik/prostor/tablo, ne dovoljen samo s poznavanjem hasha. Izvedeno:
JPEG/PNG do2MiB, največ4096×4096 in20slik/tablo, chunk do256KiB. JSON table ima dve preverjeni meji:768KiB surovega UTF-8 in1MiB privzeto
ubežanega PHP JSON. Dejansko ubežana stran pull ima približno1.5MiB in največ20
vrstic, pod odjemalčevim2MiB transportom. Velika Unicode vsebina je dejansko preverjena. Izbor/uporaba slike ne uvaja širokih Android dovoljenj.

SharedRecordType.idea uporablja novo pogodbo5/sync5 in obstoječe zapise,
revizije/receipts. Stare čakajoče zahteve ostanejo enake; za razrešeno združitev
se ustvari nova operacija. FamilyHub oglašuje ideas/ideaAssets, nova kategorija
obvestil je ideas. Stari odjemalci ne smejo tiho preskočiti table in potrditi
nepopolnega prenosa. Zasebni asset API je ločen od zapisovanja boardJSON.

Nove lokalne tabele in format kopije morajo imeti ohranjajočo migracijo in branje
prejšnjih verzij. FamilyHub0.13.0/schema17 je izveden v izvoru z dvema dodatnima tabelama. SDK, zaklenjene odvisnosti, identitete in platformni podpisi ostanejo.

## Lokalna izvedba

Urejevalnik je v meniju Idejnik, tudi v lokalnem načinu. Table omogočajo naslov,
izbiro projekta, tekst/lističe, svinčnik/marker/radirko, črto/puščico/pravokotnik/elipso,
izbor/premik/merilo/rotacijo, pan/zoom ter undo/redo. Oznake slike uporabljajo njeno
transformacijo. Dejanja ohranijo dogovorjeno kompaktno vrstico in prijavo ob naslovu.
Osnutki se shranjujejo ločeno od potrjene table, preklic omogoča nadaljevanje.
Vsi združi vidno vsebino, pokaže izvor in za novo tablo zahteva izbrani cilj.
Branje nima skritih pravic urejanja ali samodejne oddaje prijave. Aktivni viewer
lahko bere in izrecno prijavi vsebino, tudi ko so njegove zapisovalne operacije
blocked; preklicana ali neznana politika se ne obide.

`image4.7.2` je že zaklenjena odvisnost, premaknjena iz dev v runtime; različica
se ni spremenila. JPEG/PNG vhod do20MiB in32 milijonov pik se dekodira v ločenem
izolatu, ponovno kodira brez vgrajenih metapodatkov in po potrebi pomanjša na
4096 pik/2MiB. Izvirna izbrana datoteka se ne spreminja. PNG prosojnost ostane.
Za prenos velja natančna identiteta račun/strežnik/prostor/tabla; SHA256 ni dovoljenje.
Bajti so preverjeni pri uvozu, strežniškem zaključku, prenosu in obnovi.

Lokalna schema9 in kopija vsebine5 ohranita table, fotografije, osnutke, izhodišča
in prvotne čakajoče operacije. Stare kopije1–4 ostanejo berljive. Samostojna obnova
ustvari nove ID-je table/elementov, preveže projekt in oznake slike, kopira dejanske
bajte ter ohrani izvirni šifrirani arhiv. Manjkajoči bajti pomenijo vidno nepopolnost.
Omejitev kopije je96MiB dekodirane vsebine/128MiB ovojnice; obstoječi AES-GCM/PBKDF
postopek in600k ponovitev ostaneta. Druge strežniške priponke niso s tem izvedene.

Vključitev zasebne sinhronizacije prenese potrjene osebne table ter lokalne osnutke
v točno zasebno particijo. Osnutki niso objavljeni. Izvirne anonimne vrstice se po
preverjenem prenosu odstranijo; izvorni dnevnik in fotografije ostanejo v zasebnem
arhivu, ne obudijo se ob odjavi. Podatki drugih računov/prostorov ostanejo ločeni.
Objava lokalnega gospodinjstva/organizacije preveže tudi njihove projektne table in
osnutke ter kopira fotografije v točen ciljni prostor; predogled ima ločene števce.
Odprti urejevalnik starega vira ne sme po vezavi prostora pisati v napačni račun.
Izbris projekta razveže njegove table/osnutke, izbris računa počisti samo njegovo
zasebno vsebino; nedosegljivost strežnika ohrani lokalni predpomnilnik.

FamilyHub0.13/schema17 doda le metadata slik in reference slik prijav. Podpira
sync5/record5, avtenticirane chunk prenose in kategorijo `ideas`; stare operacije,
receipts, pravice in politike se ne prepišejo. Potrjen Save ustvari eno spremembo
in obvestilo; poteze/osnutki/chunki ne pošiljajo obvestil. Različni elementi se
združijo, konflikt istega elementa ohrani oba predogleda in prvotno operacijo.
Nova razrešitev dobi nov opId. Izrecna prijava vsebuje celotno tablo in fotografije.
Admin vidi zaščiten raster, berljivo ubežano besedilo, zloženi JSON ter izvirne slike,
ki jih oznake ne morejo prekriti. Omejitev/odstranitev sledi prvotni moderaciji1.
GD JPEG/PNG je pogoj novih zapisov; manjkajoča podpora je oglaševana in zavrnjena,
obstoječi izvorni zapisi pa ostanejo uporabni.
[Pogodba API](server/ideas-api-contract.md).

## Dejanski dokazi

- Realni Dart/HTTP/PHP z dvema odjemalcema in ponovno odprto datoteko SQLite:
  fotografije/oznake, eno obvestilo in odpiranje table, predogled prijave, zavrnitev
  drugega računa, rebase različnih elementov, konflikt istega elementa, offline
  ponovni zagon ter šifrirana kopija/samostojna obnova brez starega strežnika PASS.
  Tudi izrecni zasebni prenos in objava lokalne organizacije/projekta s fotografijami PASS.
  Sintetična CLI dodelitev člana ni dokaz fizičnega e-poštnega povabila.
- PHP dejanski HTTP/DB:156 kontrol na vsaki SQLite/MySQL8.4/MariaDB10.11.19
  (468 skupaj). Tri migracije16→17 ohranijo definicije/hashe vseh prejšnjih tabel
  in identiteto, dodajo le2 tabeli. Missing-GD negativni tok PASS.
- Osem dodatnih admin kontrol: UTF-8/emoji/ubežan HTML pred zloženim JSON,
  zasebne foto/raster poti ter dejanski piksel prosojnega markerja PASS.
  Rotirana fotografija z vezano potezo je preverjena na dejanskem rastru.
- 87 PHP lint ter18 paketnih Python testov PASS.
- Celoten Flutter pregled:1060 uspešnih,14 opt-in preskokov;18 starih testov
  je imelo predpostavke prejšnjega menija, kategorij in formatov kopij. Te se
  popravijo z zgodovinsko točnimi fixtures in ciljno preverijo, brez spremembe
  produkcijske migracije ali oslabitve preverjanja kopije. Vseh12 prizadetih
  podatkovnih in28 prizadetih UI testov je nato PASS; vseh18 prvotnih neuspehov
  je razrešenih. Dodaten real-provider preizkus lokalne table ob zasebnem prostoru
  je PASS. Skupaj42 ciljnih UI ter13 novih podatkovnih testov PASS. Celotnega
  uspešnega dela suite brez novih funkcionalnih sprememb nismo ponavljali.
- Ločen zadnji Dart/HTTP z zasebnim osnutkom/fotografijo in lokalnim projektnim
  osnutkom PASS: oba po prenosu ostaneta neobjavljena; anonimni izvirnik se ne
  obudi. Prikazana predogledna števca idej/osnutkov se ujemata z dejansko objavo.
- Android debug in web release PASS. Zgrajeni APK ima istih8 dovoljenj, brez
  širokih media/storage ali kamere. SDK/AGP/Kotlin/zaklenjene verzije ostanejo;
  orodje opozori na bodočo opustitev podpore starih AGP/Kotlin, build uspe.
  Po zadnji korekciji prikaza sta gradnji ponovljeni z278 nespremenjenimi
  preverjenimi izvornimi vhodi; to ni podpisana trgovinska gradnja.
- Končna celotna analiza: **No issues found**.

Sintezni dnevniki so v `build/qa/ideas-20261012/`, strežniški v
`build/qa/jivie-ideas/server/`, UI posnetki v `build/qa/ideas/`.
Fixture z naključnimi poverilnicami je ločeno0700/0600 in ni v Gitu ali paketih.

## Paketi in stanje izdaje

- `build/releases/FamilyHub-0.13.0-source.zip`,96 dovoljenih datotek, SHA256
  `00df4cec3baebb66d4e67adad20c235149529b2ee9853b614b0a74ef85cfbe52`.
- `build/releases/jivie-website-2026-10-12-ideas.zip`,15 statičnih datotek, SHA256
  `e33f55353c451f3eea91a49e505c5bd6cb7d3534e3c88395b4b464adfbaf72c0`.
- Bajtno ujemanje izvorov, dovoljenih datotek in CRC obeh ZIP je PASS. Spletni
  generator ohrani moderacijo in ima SL/EN opis fotografij/kopij, brez AI zgodovine.

Po nadaljnjem naročilu je ta nadgradnja nameščena na test2 in objavljena kot
interna Android1.6.0(23); [izdajni dokazi](release/IDEAS_RELEASE.md) opisujejo
dejanski GD, svežo kopijo/obnovo16 in ohranitev vseh podatkov pri prehodu17.
Test1/produkcija, splet jivie.app ter iOS/Mac ostanejo nespremenjeni. Telefon
še ni fizično potrjeno posodobljen. Pre-upgrade helper16 ne potrjuje kopije17. Fizični
preizkus telefona/FCM in nastavljena dostava SMTP sledita namestitvi, lokalni
HTTP/widget dokazi tega ne nadomestijo. Obvestilna opravila in upravičenost so
preverjeni, fizična dostava ni nova trditev.

[Inventar zasebnosti](release/PRIVACY_AND_DATA_SAFETY.md) je dopolnjen s fotografijami;
Console/Data safety/IARC in javna oddaja niso s tem zaključeni.
