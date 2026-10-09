# Jivie 1.1.6 (9) — izbor prostorov

Stanje 9. oktobra 2026: **Google Play potrdi Aktivno / 1.1.6 (9) — preglednejši izbor prostorov, na voljo notranjim preizkuševalcem od 11:05.** Izvorne spremembe in izdajna priprava so commitane in poslane na `origin/codex/navigation-task-opening`.

## Vsebina

Izbor prostorov ima zaobljen meni, ikone, oznake vrste prostora, jasno označeno izbiro s kljukico ter ločeno akcijo »Nov prostor«. Uporablja obstoječo svetlo in temno temo. Obstoječe izbire Vsi, osebno in skupno ter vedenje ustvarjanja, arhiva in zavrnjenega dostopa ostanejo ohranjeni.

- `58291d5`: priprava predstavitve v Googlu Play, izvornih slik in statične spletne strani.
- `d268074`: priprava ločene produkcijske namestitve; strežnik še ni aktiviran. [Stanje produkcije](../server/PRODUCTION_SETUP.md).
- `bfc85d5`: funkcionalna sprememba izbire prostorov.
- `106bbef`: izrecni dvig na `1.1.6+9` po funkcionalnem commitu/pushu.

Identiteta ostaja `si.triparna.jivie`. SDK, odvisnosti, lokalna shema in strežniške pogodbe se v tej izdaji ne spreminjajo. Pripravljena javna predstavitev še ni oddana v pregled; ta objava je namenjena obstoječim internim preizkuševalcem.

## Preverjanje

- **59 ciljnih Flutter UI testov PASS**: kompaktna glava in Vsi (46), organizacije/osebe (13).
- `flutter analyze`: brez napak/opozoril, 37 obstoječih info.
- Generiranje lokalizacije, formatiranje in `git diff --check`: uspešno.
- Telefonski širini 320/390, tablična in namizna umestitev, SL/EN in 2× povečava besedila: preverjeno.
- Dejanski render svetlega/temnega menija pri 390×844 je vizualno pregledan v `build/qa/jivie-space-picker/`; uporabljeni so izolirani testni podatki.
- Izdajna orodja **18 PASS**, Firebase orodja **7 PASS**, izvorni release checker PASS. Po dvigu različice sta izdajni nabor in checker ponovno uspešna.
- Pregled spremenjenih/novih datotek ni našel skrivnosti ali zasebnih izvozov. Vseh 15 trgovinskih PNG ustreza inventarju in hashom; slike uporabljajo sintetične podatke.

## Podpisana Android gradnja

`flutter build appbundle --release --dart-define-from-file=.firebase/client.json` je uspešen. Končni AAB je `build/releases/Jivie-1.1.6+9-android-firebase.aab`, 77.583.118 bajtov, SHA256 `561a91c14deb7b5f13a8d250df537a1e665da8673f5be1e31c3758e1e6b4d91a`.

Preverjeni so pravi ID in različica, min SDK 24/target SDK 36, omogočen Android Back callback, isti namenski upload certifikat kot pri objavljeni gradnji 8, `jarsigner`, `bundletool validate`, ZIP CRC, `PAGE_ALIGNMENT_16K` in vseh osem 64-bitnih ELF knjižnic. Native Firebase identiteta se ujema s prejšnjo izdajo; projekt `jivie-e928a` je prisoten tudi v Dart AOT vseh treh ABI. AAB ne vsebuje service-account datoteke, podpisnih skrivnosti, zasebnega ključa ali datoteke client.json kot sredstva aplikacije.

Dokaz: `build/qa/jivie-space-picker-release/android-release-artifact-evidence.json`, spremljajoči manifest, dnevniki in podpisni izhodi. Dokazni JSON opisuje stanje lokalnega paketa pred nalaganjem; stanje objave se vodi ločeno. Nov fizični preizkus prikaza na Samsungu ostaja uporabnikov korak po posodobitvi.


## Objava v Googlu Play

Naložen je preverjeni AAB zgoraj. Predogled potrdi različico 9 (1.1.6), target SDK 36 ter nespremenjeno podporo napravam. Opombe ob izdaji so shranjene v slovenščini in angleščini. »Shrani in objavi« je izveden samo za obstoječi interni kanal `4701286726300038561`; izbran ostaja seznam **domači (15)**.

Končni prikaz: **Aktivno**, najnovejša izdaja **1.1.6 (9) — preglednejši izbor prostorov**, **Na voljo notranjim preizkuševalcem**, 9. oktober 2026 ob **11:05**. Dokaz: `build/qa/jivie-space-picker-release/play-internal-1.1.6-9-active.png`. [Povezava za posodobitev](https://play.google.com/apps/internaltest/4701286726300038561).

Nova fizična namestitev/prikaz še nista potrjena. Preveri izbiro Vsi/osebno/skupno, oznako izbranega prostora in možnost Nov prostor. Javna objava, iOS in dokončanje novega produkcijskega strežnika so ločeni koraki.
