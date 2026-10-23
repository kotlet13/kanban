# Popravki po pregledu aktualne Mac različice

23. oktober 2026. Nadaljevanje [pregleda r14](UX_LATEST_MAC_REVIEW_2026_10_23.md) po izrecnem naročilu uporabnika: vzrok sync napake, iskanje odprtih opravil, slabo vidno besedilo in razlage. Implementacija in neodvisni pregledi: GPT 6.1 Sol/high; glavni agent pregleda spremembe in upravlja samo isto Mac Share A. Telefoni in produkcija niso del te naloge.

## Potrjen vzrok in popravek sinhronizacije

Na isti ohranjeni Share A je diagnostična r15 pri samodejni celotni sinhronizaciji ob **09:53:59.161811 UTC** zajela:

```text
stage=content_canonical
recordType=table
errorType=ArgumentError
finalCode=invalid_response
```

Native AOT ni vrnil izvornih stack frameov (`frames=[]`). Točnega native mesta vrženja zato ne predstavljamo kot neposredno prebranega. Ločena lokalna kontrola s pravo SQL potjo `CryptoBusinessSession.pull` in običajnim `CollaborationRepository.syncNow` ponovi pretvorbo `SharedRecordType.values.byName`: enum ne vsebuje `table` in `attachment`. Splošni catch to lokalno izjemo spremeni v `invalid_response`, staro besedilo pa napačno namiguje na strežnik oziroma vtičnik.

Popravek v [crypto_business_router.dart](../lib/organizer/data/e2ee/crypto_business_router.dart):

- Kriptografsko preverjanje ostane pred branjem projekcij. Strani se določijo po vseh pregledanih preverjenih zapisih, po največ 100.
- Običajnemu modelu se ne posredujeta znana dokumentna tipa `table` in `attachment` v domeni `content`; njuna vsebina ostane v isti shrambi in dostopna obstoječemu `CryptoBusinessDocuments` adapterju.
- Cursor napreduje po zadnjem pregledanem zapisu, tudi pri strani samo z dokumenti ali internimi zapisi. `hasMore` izhaja iz pregledane strani.
- Projekcija mora biti objekt in njen tip se mora ujemati s tipom shranjene vrstice. Neznani tipi se ne ignorirajo; običajni validator jih še vedno zavrne pred potrditvijo cursorja.
- Ni migracije baze, brisanja podatkov, ponastavitve vrst, spreminjanja ključev, dovoljenj ali kriptografskih varoval.

`invalid_response` ima zdaj nevtralno SL/EN razlago neuspešne obdelave podatkov. `redirect_rejected` posebej razloži zavrnjeno preusmeritev. Sprememba besedila ne spreminja kontrolnega toka.

## Iskanje, čitljivost in razlage

- Globalno iskanje prej zahteva `showCompleted: true`, kar pomeni samo zaključena opravila. Zdaj vključi tudi odprta opravila prek iste dovoljene projekcije; deduplikacija po izvoru/tipu/ID in varovala dostopa ostanejo ista. Običajni zaslon Opravila ohrani svoje filtre.
- Navadno besedilo na platnu idej dobi kontrasten obris, če ima glede na podlago kontrast pod 4,5 : 1. Izvirna barva in shranjeni dokument se ne spreminjata. Upoštevani sta temna privzeta pisava in prej shranjena bela pisava; pripisi na fotografijah so izvzeti.
- Priprava ključev računa ne trdi več, da so vsi prostori nešifrirani. Pregled zaščite loči pripravo od zaključnega preverjanja; gumb je »Preveri in končaj«, obstoječa zaključna preverjanja pa ostanejo obvezna.
- Kartica pravil loči potrjeno, nepotrjeno in še nepreverjeno stanje. Neznano ni več samodejno prikazano kot nepotrjeno.
- Nedostopen seznam finančnih računov ne ponuja več razlage, da je zagotovo prazen. Skupni finančni pogled razloži neto spremembo brez začetnih stanj; vrstica računa jasno označi začetno stanje.
- Opravilo brez projekta/roka kaže »Brez projekta«. Nakupi v lokalnem gospodinjstvu uporabijo dejansko ime prostora. Nastavitve ne opisujejo več vse uporabe kot samo lokalne.

## Nove ciljne kontrole

| Sklop | Rezultat | Meje dokaza |
| --- | --- | --- |
| Prvotni sync vzrok | Baseline PASS v poskusu 2; prvi poskus je fixture napaka pred ciljno potjo | Sintetične že preverjene projekcije, prava SQL in običajna repository pot; ne ponovitev native baze |
| Sync popravek | 8 novih kontrol PASS, prvi poskus | Mešani dokumenti, strani 100/101, interni rep, ohranjeni adapterji, neznani/napačni tipi, vrstni red preverjanja in finančna domena. Verifier ter finančna authority metadata so nadzorovani; ni nov dokaz kriptografije ali celotnega HTTP synca |
| Iskanje | 4 nove kontrole PASS, prvi poskus | Odprta/zaključena opravila, opombe, deduplikacija, enaki ID v različnih izvorih, odvzet/blocked/arhiviran prostor, menjava računa in ohranjeni običajni filtri |
| Razlage in kontrast | 15 aktualnih novih kontrol PASS | SL/EN stanja in pravi raster editorja/kartice v obeh temah ter bela izvozna podlaga. Štiri protection kontrole so uspele v poskusu 2 po popravku fixture UUID. Prva dva testa stalno belega platna sta superseded, ne dokaz končnega popravka |

Skupaj **27 aktualnih novih kontrol popravkov PASS**, poleg diagnostičnega baseline. Stari uspešni testi niso bili ponovljeni. Končne ciljne analize so brez ugotovitev, prevodi so generirani in diff-check uspešen. Celotna zgodnejša analiza je imela stare informativne ugotovitve; ne trdimo, da je celoten repozitorij brez njih.

## Paket in neposredni Mac preizkus

Diagnostična r15 je bila zgrajena in nameščena po enkrat, v isti bundle `si.tripar.jivie.e2eetest.sharea20261019`. AOT SHA256 `96270b190a93cda8fc6e00ad944f5aa42a9d2e06547a4774fd8db15943d452f4`. Samodejna sinhronizacija je zajela zgornji prvi izvirni problem; ročnega Sync ni bilo. Zapis je prebran prek QA prikaza v aplikaciji. Branja sandbox podatkov prek TCC nismo obšli.

Končna skupna **r16 je zgrajena in nameščena po enkrat**. AOT SHA256 `97c91a9affeb9ab9ab8019550a7b30aba3cde466f9e584aed6f9fbcf98dbde3f`, artifact SHA256 `fe13916ef003824bf1a173ca9d87cdf2a69502e89f61c344696c5cd9cbec3375`. Vsebuje 588 pripetih izvornih vhodov, vse pregledane popravke in prvotnih osem QA prilagoditev. R15 diagnostična koda je odstranjena. Podpis, SDK in locki so preverjeni; ciljna analiza pri gradnji ima 0 errors/warnings/infos.

Glavni agent je prek GUI na isti shrambi potrdil:

- **Sync PASS:** zelen oblaček in »Synced«, zadnji uspeh in poskus oba **12:01 lokalno**, vrste **0/0/0**, brez prikazane napake. Panel izrecno pokriva račun in vse prostore. Samodejni sync, brez ročnega Sync now.
- **Iskanje PASS:** `UX26` vrne osem rezultatov, vključno s prej manjkajočim `UX26 – opravilo`. Odprto obstoječe opravilo kaže Completed=0 in No project. Preklic brez shranjevanja.
- **Kontrast PASS:** obstoječa `UX26 – ideja` pokaže vidno besedilo tako na kartici kot v odprtem temnem urejevalniku. Izvirno besedilo »UX26: zamisel za preprosto deljenje.« je ohranjeno. Preklic brez shranjevanja.
- **Razlaga zaščite PASS:** nov opis pregleda in »Check and finish« sta vidna. Uporabljeno je samo Continue locally; brez novih ključev ali potrjevanja pravil.

Aplikacija je nato normalno zaprta prek menija Quit; svež pregled procesov potrdi, da Share A/B ne tečeta. To je en ciljni native preizkus popravkov, ne ponovni celotni raziskovalni pregled ali ponovitev prejšnjih poslovnih PASS scenarijev. Widget kontrole pokrivajo pregled zaščite, stanja pravil, finančne razlage/prazni prikaz in oznako opravila. Ime prostora pri nakupih, besedila nastavitev in ključev računa ter ločeni razlagi napak so preverjeni izvorno, z generiranjem prevodov in analizo; nimajo vsaka svojega novega widget testa. Vseh različic nismo znova odpirali v native GUI.

Namestitveni postopki zamenjajo samo isti aplikacijski paket ter ohranijo podpis, Keychain nastavitve, lokalni CA in identiteto vsebnika. Podatkov ne brišejo ali ponastavljajo. **Bajtna enakost vault datotek ni preverjena**, ker macOS TCC preprečuje neposredno branje; tega ne enačimo z dokazom izgube. Stari paketi in podatki ostanejo ohranjeni. Strežniška programska oprema v tej nalogi ni spremenjena.

Po uspešni predaji so odstranjeni samo štirje obnovljivi predpomnilniki istega `source-a` (Xcode intermediates, Flutter build, hooks runner in module cache), skupaj **1.698.377.933 B** logičnih datotek. Izvor, končni paketi, nameščeni AOT, obnovljiva r14/r15 paketa in dokazi ostanejo ohranjeni. Nova polna izvorna kopija ni bila ustvarjena.

## Dokazi in preostala meja

- `build/qa/local-diagnostics/document-content-sync-20261023/`: baseline, prvotna native napaka, ciljni popravki in njihove omejitve.
- `build/qa/local-diagnostics/desktop-search-task-fix-20261023/`: en uspešen ciljni tek in analiza.
- `build/qa/local-diagnostics/ux-clarity-20261023/result.json`: aktualni in superseded izidi, raster kontrole, prevodi, analize.
- Zasebni `JivieLocalTest/share-20261019/candidate-a-r15-diagnostic/` in `candidate-a-r16/`: pripeti izvori, paketi in namestitveni dokazi. Gesla, ključi in poslovna vsebina niso vključeni v javno poročilo.

To ni zaključna mobilna ali produkcijska odobritev. Ta naloga ne ponavlja uspešnih preizkusov povabil, odvzema, obnove ali finance CRUD, ne uvaja dodatnega osveževanja/Firebase in ne spreminja privzetih pravic deljenja.
