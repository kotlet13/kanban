# Meritev hitrosti običajne sinhronizacije — 20. oktober 2026

Po uporabnikovem naročilu je izmerjena trenutna koda `73fd3d6` na istem
izoliranem HTTP strežniku Docker59776 in ohranjenem sintetičnem odjemalcu.
GPT-6.1 Sol/high pripravi in izvede meritev, drugi opravi neodvisni pregled,
glavni agent pregleda kodo in rezultate. Sprememb produkcijske kode ni.

## Obseg in metoda

Obstoječi račun ima nadrejeni prostor, projekt, dva finančna računa in en
strošek. Uporabljeni so isti baza, seja in ključi; ni nove registracije,
obnove, povabila ali odvzema. Prejšnji uspešni scenariji in primerjava
vključene/izključene optimizacije se ne ponavljajo.

Novi opt-in `crypto_sync_speed_http_test.dart` kliče običajni
`CollaborationRepository.syncNow()` s trenutnim privzetim routerjem.
Ločen začetni cikel ogreje pot, nato sledijo trije vzorci brez novih
poslovnih sprememb in en cikel po spremembi naslova istega stroška.
Vsak vzorec preveri novo zaporedno številko zaključka in dejanske HTTP klice,
da preskočen cikel ne bi pomenil lažno hitrega rezultata.

Čas vključuje celotni pričakani klic `syncNow()`. Inicializacija, preverjanje
rezultatov, priprava urejanja in premor zaradi kvote so zunaj meritve.
HTTP instrumentacija šteje dejanske zahteve, statuse in telesa odgovorov;
glave, TLS in omrežni režijski stroški niso vključeni. RPC in poslovni časi
se prekrivajo s HTTP časi in se ne seštevajo v razdelitev CPU/omrežje.
Ni dodatnega pacinga ali samodejnih ponovitev znotraj merjenih ciklov.

## Rezultati — PASS

| Cikel | Čas | HTTP zahtevki | Telesa zahtevkov | Telesa odgovorov |
|---|---:|---:|---:|---:|
| Začetni cikel, ločen od vzorcev | 1.975,696 ms | 99 | 14.875 B | 1.891.858 B |
| Brez novih vnosov, 1 | 1.099,708 ms | 69 | 7.229 B | 1.316.134 B |
| Brez novih vnosov, 2 | 1.052,344 ms | 69 | 7.229 B | 1.316.134 B |
| Brez novih vnosov, 3 | 1.053,242 ms | 69 | 7.229 B | 1.316.134 B |
| En spremenjen naslov stroška | 1.935,046 ms | 137 | 33.302 B | 2.428.964 B |

Mediana treh običajnih osvežitev je **1.053,242 ms**. Vseh pet ciklov ima
nov zaključek, vsi odgovori so HTTP200, brez RPC/transportnih napak ali429.
Pred urejanjem je bil en 61,005-sekundni premor za običajno kvoto, izključen
iz časov. Priprava urejanja traja 14,791 ms, brez HTTP, in ustvari eno
čakajočo spremembo. Merjeni cikel jo zaključi: pending1→0, conflict0,
blocked0 in brez nerešenega dela.

Saldo ostane33,33EUR, strošek12,34EUR, dva računa, dve projektni izbiri,
en strošek. Vseh53 predhodnih podpisanih zahtevkov je ohranjenih točno.
Druga dva finančna zapisa sta nespremenjena; pri strošku se spremenijo le
naslov, čas posodobitve in revizija. Izvirnik in namen urejanja sta trajno
zapisana v zasebnem dnevniku. Sintetični naslov ostane spremenjen, brez
dodatnega povratnega urejanja ali ponovitve sinhronizacije.

## Kaj meritev pokaže

V vsakem od treh običajnih ciklov je13 klicev
`crypto2.authority.snapshot`, skupaj1.176.743 B odgovorov oziroma89,4 %
vseh prejetih teles. Poleg tega je17 klicev `capabilities`,
13 `crypto2.account.scopeObservations` in12 `crypto2.domain.inventory`.
Pri enem urejanju je23 authority snapshotov in28 capability klicev.

To je konkretna podlaga za naslednjo optimizacijo ponavljajočih se
pridobivanj pravic in zmogljivosti. V tej nalogi je ne izvajamo; preverjanje
podpisov, svežina, kvote, urnik in Firebase ostanejo nespremenjeni.

**To ni dokaz hitrosti na telefonu ali prek interneta.** Gre za majhen
obstoječi nabor, lokalni loopback in Flutter testno izvajanje brez native UI.
Začetni cikel ni prvi prenos prazne namestitve. Trije vzorci niso p95 ali
obremenitveni test. Prejšnja para meritev sta imela drugačno metapodatkovno
delo; iz teh številk ne računamo odstotka pospešitve ali primerjave s starim
native ciklom412 zahtevkov. P0/mobile/P8/N7 ostajajo odprti.

## Poskusi, stanje in dokazi

Začetna statična analiza novega ogrodja je odkrila napačen getter stanja in
tip napake; popravljena pred prvim HTTP tekom. Končna ozka analiza je čista,
dejanski HTTP tek uspe v prvem poskusu. Brez ponovitve uspešnih vzorcev.
Ogrodje ohrani začetni zasebni posnetek, rezultate in števec največ treh
poskusov; že uspešne faze preskoči, dvoumnega urejanja ne odda ponovno.

Samo Docker59776 je bil zagnan in nato znova ustavljen. Zasebno stanje
ostane ohranjeno. Produkcija, Docker18811, nameščeni Mac/mobilni aplikaciji,
trgovini, SDK/locks in nepovezana dokumenta so nedotaknjeni.

Dokazi so v zasebnem imeniku `/tmp/jivie-finance-read-reuse-20261020`:

- `sync-speed-result.json`, SHA-256
  `6d02d5fd5a3348f1b3356203e77c1b4c34c1f6ed44ab94ba714463c2088d609e`.
- `sync-speed-attempt1.log`, SHA-256
  `b221136232ad41fbb80de3ba9d6bb0530e9f9e8c256d43f91d809d780d554580`.
- Testno ogrodje SHA-256
  `16802186b1a4763ffc7631e9b3f7edeeb55623b591bff6b9b5d2abe66cb67995`.

Skrivnosti, izvirni payloadi in podpisani zahtevki ostanejo zunaj repozitorija.
