# Preizkus Google Play preglednega računa na Macu

**Nadaljevanje13. oktobra:** pregledni test1 je zdaj dejansko nadgrajen na
0.13/schema17 in Googlova navodila shranjena. [Nadgradnja in dokazi](REVIEW_SERVER_UPGRADE.md)
odpravijo spodnjo zgodovinsko omejitev starega strežnika; Android25 ostane isti.

13. oktober 2026 — **dejanska prijava `jivie_review` na
`https://jivie-test.triparna.si/` PASS**, tudi po zaprtju in ponovnem zagonu
podpisane Jivie. Uporabnik je geslo vnesel neposredno; ni bilo prebrano ali
izvoženo v pogovor oziroma dokaze.

## Vzrok napake in popravek paketa

Odprta namizna QA gradnja iz `build/qa/desktop-ux/macos-derived/` je bila
izdelana brez podpisovanja. Ni imela podpisane identitete, ekipe ali dovoljenj
za Keychain, zato prijava ni mogla varno shraniti seje. Uspešna gradnja za
preverjanje postavitve sama po sebi ni dokaz delujoče prijave.

Isti že prevedeni paket je kopiran in podpisan z obstoječo identiteto
Apple Development ter istim veljavnim profilom in dovoljenji kot prej delujoča
podpisana Mac gradnja. Izvor in projektne nastavitve niso spremenjeni.
Paket za uporabo:

`build/qa/review-access-mac-20261013/SignedProducts/Debug/Jivie.app`

- Različica 1.7.0 (25), bundle `com.example.kanban`, ekipa `CXNM99632B`.
- Ista skupina Keychain `CXNM99632B.com.example.kanban`; profil velja do
  10. oktobra 2027. Profil in podpisana dovoljenja so enaki prejšnjemu paketu.
- `codesign --verify --deep --strict` PASS; podpisanih 26 Mach-O,
  78 drugih datotek in 69 povezav primerjanih brez sprememb vsebine/ciljev.
- 315 zamrznjenih izvornih vhodov in originalni nepodpisani paket ostajajo isti.
  Ni nove kompilacije, spremembe SDK/locks ali nove Android gradnje.

Prvi poskus izolirane Xcode gradnje z globalnim profilom ni uspel, ker Pods
cilji ne podpirajo take nastavitve. Končni paket je podpisana kopija uspešne
namizne gradnje; zgornji rezultat velja za ta paket.

## Dejanska uporaba

Podpisana aplikacija je najprej uspešno obnovila prejšnjo sejo `slt_test` na
test2. Nato je običajna odjava uspela brez izbrisa uporabniških podatkov.
Po uporabnikovem vnosu preglednih poverilnic je prikazala Google Play Review,
`jivie_review` in pravilen test1 URL brez napake varne hrambe.

Prebrana sta oba pregledna prostora, gospodinjstvo in deljeni projekt. Vidni so:

- projekt »Review: prepare a home workspace« in opravilo
  »Review: compare two desk layouts«;
- »Review shopping list (synthetic)« z izdelkom »Review: notebook«;
- »Review cash account (synthetic)« in knjiženi vzorčni odhodek 5 EUR.

Gospodinjstvo nima opravila; vzorčno opravilo je v projektu. Po ponovnem zagonu
ostanejo račun, izbrani projekt in njegova vsebina. Zasebna sinhronizacija ni
vključena. Noben vzorčni zapis, prijava vsebine ali sprejem pravil ni oddan.

## Preostali dostop pred javno oddajo

Shranjena Console navodila še uporabljajo test1. Njegov javni capabilities
odgovor HTTP 200 podpira record 1–4, ne oglašuje Idejnika ali prijav vsebine.
Test2 odgovori HTTP 200 z record 1–5, ideas/ideaAssets in moderacijo/prijavami.
**Uspešna prijava zato še ne potrjuje preglednega dostopa do vseh novih
deljenih funkcij.** Naslednji korak je uskladitev preglednega gostovanja in
Console navodil z aktualnimi funkcijami. Gostovana nadgradnja potrebuje svežo
preverjeno kopijo po obstoječem postopku; v tem koraku ni izvedena.

Dokazi so v ignorirani mapi `build/qa/review-access-mac-20261013/`:
`signing-evidence.json`, `signature-verification.log`, `mac-source-inputs.json`,
`runtime-evidence.json`, AX zapisi in `reviewer-after-restart.png`.
`prepared.json` je zgodovinski dokaz pred vnosom gesla; končni rezultat je v
`runtime-evidence.json`. Noben dokaz ne vsebuje gesla ali sejnega žetona.

To je preizkus Mac odjemalca, ne fizični Android preizkus. Aktivna Android
1.7.0 (25), njen AAB, strežnika, Console deklaracije in spletna stran ostajajo
isti. Ni oddaje Googlu ali javne objave.
