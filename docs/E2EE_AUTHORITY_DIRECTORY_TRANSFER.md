# Manj ponovnega prenosa imenika računa — 20. oktober 2026

Naslednji korak po [meritvi hitrosti](E2EE_SYNC_SPEED_2026_10_20.md)
zmanjša ponovni prenos že preverjene podpisane zgodovine lastnega računa.
Na istem majhnem testnem naboru so telesa odgovorov običajnega cikla manjša
za47,58 %; občuten časovni pospešek ni dokazan. Število zahtevkov ostane69.
Izvedba in preverjanje uporabljata GPT-6.1 Sol/high podagente, neodvisni
pregled in pregled glavnega agenta.

## Sprememba in varnostna meja

`AccountDirectoryRepository` doda kazalec `directoryAfterGenerations`
za lastni račun samo, če že ima kriptografsko rekonstruirano zgodovino
`_verified`. Trenutno varno sidro mora ustrezati strežniku, računu,
generaciji, glavi, odtisu posnetka, korenu identitete in stanju `verified`.
Identiteto preveri pred branjem varne shrambe in po njem; sprememba
rekonstruirane zgodovine med čakanjem prepreči uporabo kazalca.

`CryptoAuthoritySnapshot` pred prenosom pridobi ta izbirni namig in ponovno
preveri obstoječo veljavnost operacije. Strežnik že podpira ta parameter:
za točno izbrano zgodovinsko glavo omeji kazalec na njeno generacijo.
Tako se skrajša vnaprejšnji prenos strani, katerih vsebino odjemalec že ima.

Namig ni dokaz pravic ali popolnosti. Obstoječi porabniki še vedno
rekonstruirajo in preverjajo podpisano verigo. Če lokalna zgodovina manjka,
porabnik zahteva `afterGeneration: 0`; prazna stran z drugačnim kazalcem
ne ustreza temu točnemu ključu in sledi prvotno posamezno branje.
Zgodovinski dokaz mora še vedno doseči znano varno sidro.

Spremenjeni sta le dve produkcijski datoteki, skupaj33 dodanih vrstic:
`account_directory_repository.dart` in `crypto_authority_snapshot.dart`.
Ni nove skupne shrambe pravic med operacijami, podaljšanja petsekundne meje
ali spremembe svežih mej pri pisanju. Strežniška koda, shema, podpisi,
kontrole dostopa, urnik, kvote, Firebase in odvisnosti ostanejo enaki.
Kazalcev za druge račune ali zgodovino življenjskega cikla ne dodajamo.
Hladna pot brez rekonstruiranega lastnega imenika namig izpusti.

## Novi ciljni preizkusi

- Dvanajst kontrol namiga PASS v prvem poskusu: preverjena topla pot,
  hladna pot, sedem neujemanj varnega sidra, sprememba med čakanjem,
  nov postopek po odstranitvi sidra in potek veljavnosti med čakanjem.
- Dve kontroli z dejanskimi podpisanimi dokazili PASS v drugem poskusu.
  Manjkajoči lokalni imenik sproži stran nič, nato podpisano nadaljevanje
  do varnega sidra. Ponarejen podpis je zavrnjen, sidro in lokalni dnevnik
  ostaneta nespremenjena. Prvi poskus je odpovedal pri inicializaciji
  testnega ogrodja zaradi manjkajočega `pinComparedIdentity`; popravek je
  samo v testu. Prejšnjih12 uspešnih kontrol nismo ponovili.
- Ozka analiza štirih prizadetih produkcijskih/testnih datotek:
  0 napak, 0 opozoril in1 obstoječi slogovni info. Primerjalno HTTP ogrodje
  ima ločeno čisto analizo. `git diff --check` je čist.

Podpisana fallback testa uporabljata sintetični transport in ne preverjata
celotnega dostopa do prostora. Dejanski HTTP preizkus spodaj preveri
običajno sinhronizacijo; to ni nov neodvisni varnostni pregled P0.

## Primerjalna meritev

Stara koda je zamrznjeni izvor `609cc52`, nova koda ima spodaj vezana odtisa.
Obe veji uporabljata isto nespremenjeno testno ogrodje in ločeni kopiji istega
zamrznjenega odjemalčevega stanja po prejšnjem urejanju:3 finančni zapisi,
62 podpisanih zahtevkov, isti račun, prostor, projekt in seja.
Izvirna testna namestitev in prejšnji rezultati ostanejo nespremenjeni.

Za vsako vejo izvedemo en ločen začetni cikel in dva merjena običajna
`syncNow()` cikla brez novih poslovnih sprememb. Ni novega urejanja,
ponovitve starega preizkusa odvzema ali preklapljanja optimizacije sredi
iste veje. Vsak cikel zahteva nov dejanski zaključek in HTTP aktivnost.
Čas zajema `syncNow()`, brez inicializacije in preverjanja rezultatov.
Bajti so telesa HTTP, brez glav/TLS. V merjenih ciklih ni pacinga ali
višje kvote. Obe HTTP veji uspeta v prvem poskusu.

| Meritev običajnega cikla | Pred spremembo | Po spremembi |
|---|---:|---:|
| Čas, vzorec1 | 1.113,758 ms | 1.071,072 ms |
| Čas, vzorec2 | 1.071,465 ms | 1.096,641 ms |
| Povprečje dveh vzorcev | 1.092,612 ms | 1.083,857 ms |
| HTTP zahtevki | 69 | 69 |
| Telesa zahtevkov | 7.229 B | 8.165 B |
| Telesa odgovorov | 1.363.662 B | 714.801 B |
| Authority snapshot klici | 13 | 13 |
| Authority snapshot odgovori | 1.214.755 B | 563.520 B |
| Capability klici | 17 | 17 |

Pri obeh merjenih vzorcih vsake veje so število zahtevkov in bajti enaki.
Authority odgovori so manjši za651.235 B; celotni odgovori za648.861 B
(47,58 %), zahteve pa zaradi kazalcev večje za936 B.
Razlika povprečnega časa je približno0,8 %, kar pri dveh lokalnih vzorcih
ne dokazuje pomembnega pospeška.

Začetna cikla sta ločena: stari1.616,024 ms/80HTTP/1.653.099 B odgovorov,
novi1.695,764 ms/80HTTP/904.048 B odgovorov. Vsak opravi en checkpoint in
lokalno doda en podpisani zahtevek (62→63), ne novega poslovnega vnosa.

**Strežniško stanje med vejama ni ponastavljeno.** Checkpoint stare veje
je viden novi; inventory odgovori imajo zato2.374 B več.
Vsi drugi razčlenjeni števci metod in velikosti odgovorov, razen ciljanih
authority odgovorov, so enaki. Ta razlika je navedena, ne skrita v
pripisovanju prihranka. Uspešnih meritev nismo ponavljali za lepši čas.

Vseh šest ciklov ima HTTP200, nič napak/429, končne vrste0/0/0,
saldo33,33EUR, strošek12,34EUR, dva računa in dve projektni izbiri.
Vse tri finančne vrstice in vseh62 začetnih podpisanih zahtevkov ostanejo
točno enaki. Meritev uporablja majhen lokalni loopback nabor v Flutter
testnem izvajalniku; ni meritev native aplikacije, interneta, velikih
deljenih prostorov ali celotne zgodovine drugih uporabnikov.

## Zaključek in nadaljevanje

Dokazan je manjši prenos pri enakih preverjanjih. Ponavljajoči capability
klici in število authority snapshotov ostajajo konkretni nadaljnji cilji;
širjenje življenjske dobe dokazil zaradi prihranka ni del tega popravka.

Samo izolirani Docker59776 je bil začasno zagnan in je spet ustavljen.
Izvirna zasebna baza ostane pri3 finančnih zapisih/62 podpisanih zahtevkih;
primerjalni kopiji sta ohranjeni posebej. Produkcija, Docker18811, stare
Mac/mobilne QA namestitve, trgovini, SDK/locks in nepovezana dokumenta so
nedotaknjeni. Ni nove native gradnje ali namestitve. P0/mobile/P8/N7
ostajajo odprti.

## Vezani dokazi

- `account_directory_repository.dart` SHA-256
  `cc0104f687a733bf9380719f2770b974fcc8156a4655edee68b1de7867a2075f`.
- `crypto_authority_snapshot.dart`
  `615edea11e06b6f8f63dd64088b19defa3e86f33bb6afa1a8bd9367f69cc79c7`.
- `/tmp/jivie-authority-directory-hints-attempt1.log`
  `855b115a9d7148f319778edcffa9e8dde1454870dc82a4070efc9231a3fdde20`.
- `/tmp/jivie-authority-directory-fallback-attempt2.log`
  `6b2073543ddbcc57311cd619320bcaa984ca84a9bab458182f5ae645e6624fbc`.
- `/tmp/jivie-authority-directory-final-analyze.log`
  `1c217467bac6e7437bd09fd266264d20a6b5bd0e7e5b7f3ee34e538e9176d232`.
- Primerjalno ogrodje `crypto_sync_metadata_compare_http_test.dart`
  `ad62aa4ca77f519e43a71c2e7988ad614915004f88580a01360b718eee8d6912`.

Zasebni rezultati so v
`/tmp/jivie-finance-read-reuse-20261020/metadata-comparison/`:

- `baseline/result.json`
  `82b9593f9d9b018efa00cf1816a9fa8fc9b75f3a3f60fd5adde1ff395ae60e98`.
- `optimized/result.json`
  `da3a4561de5c858fedf5e040ac156f28f53d1bf453c11f2d0fe04c4394df9948`.
- `comparison-summary.json`
  `00c14ce8da0053287a62d8371c823ce698b7ea554d5c0bae67989d8b8b703a98`.

Skrivnosti in izvirni zasebni posnetki ostanejo zunaj repozitorija.
