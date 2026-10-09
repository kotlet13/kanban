# Jivie — priprava javne Google Play izdaje

Stanje 9. oktobra 2026. Uporabnik je naročil pripravo dokumentacije, opisov in grafik v Console; spletno stran in preizkus z dvema napravama bo uredil pozneje. **Spremembe niso oddane v pregled in produkcijska izdaja ni objavljena.** Trenutna interna izdaja ostaja **1.1.5 (8)**. V tej nalogi ni nove gradnje, spremembe verzije, strežnika ali objave v Git.

## Dejanske spremembe v Console

Pregledana je evidenca `si.triparna.jivie`, app ID `4972659047480717992`, organizacijski račun `4991604398202512900`. Stara Kanban Connect ostaja ločena.

| Področje | Shranjeno stanje |
| --- | --- |
| Predstavitev | Jivie, slovenski privzeti jezik in dodatni `en-US`; kratki/dolgi opisi iz [STORE_LISTINGS.json](STORE_LISTINGS.json). |
| Slike | Potrjena ikona 512 × 512, lokalizirani predstavitveni grafiki 1024 × 500, šest telefonskih zaslonov 1080 × 1920 na jezik. Vrstni red: Danes, Načrti, Nakupi, Finance, Vrt, finančni zapisi. |
| AI oznaka slik | Ikona in obe predstavitveni grafiki so označene, ker vsebujejo potrjeni znak z AI izvorom. Izriši dejanskih widgetov niso označeni kot generirane ilustracije. |
| Kategorija | Aplikacija, Storilnost. |
| Kontakt | `zadruga@triparna.si`, `https://jivie.app/`; javni poslovni kontakt shranjen. |
| Oglasi / oglaševalski ID | Brez oglasov; ne uporablja advertising ID. |
| Državna / zdravstvena aplikacija | Ni državna aplikacija; brez namenskih zdravstvenih funkcij. |
| Finančne funkcije | Other: ročna osebna/skupna evidenca prihodkov, izdatkov, računov in proračuna. Izrecno brez povezave z bankami, premikanja denarja, plačil, posojil, naložb ali finančnega svetovanja. |
| Varnost podatkov | Samo osnutek: izbirni prenos podatkov, šifriranje med oddaljenim prenosom, geselni račun in možnost TOTP. Nadaljevanje zaustavi nedosegljiv `https://jivie.app/delete-account/`. Podrobne vrste/purposes še niso oddane. |

Končni pregled objave kaže oba jezika in shranjene izjave. Glava izrecno pravi **»Spremembe še niso bile poslane v pregled«**, gumb za oddajo je onemogočen zaradi manjkajočih korakov. AD_ID, državna in finančna izjava so ločeno navedene kot informacije za pregled. To je dokaz priprave, ne odobritve Google.

Slike so izriši trenutnih proizvodnih Flutter widgetov s sintetičnimi lokalnimi podatki, ne fotografije uporabnikovih podatkov ali zajemi fizične Android namestitve. [Postopek, pisave, omejitve in ponovitev](store-assets/README.md), [manifest slik](../../assets/store/google-play/manifest.json). Pred oddajo jih primerjamo s podpisano kandidatko.

## Preostali koraki pred oddajo

1. **Spletna stran:** objaviti `jivie.app` ter preveriti HTTPS, `/privacy/`, `/help/`, `/delete-account/` in angleške poti. Google je trenutno URL za izbris zavrnil kot nedosegljiv. Spletno besedilo o AI je popravljeno, ker prejšnji opis ločenega soglasja ni ustrezal pregledani kodi. Novi lokalni paket je `build/releases/jivie-website-2026-10-09.zip`; starega paketa ne prepisujemo. Politiko pred končno oddajo uskladimo s končno kandidatko in resnično prakso gostovanja.
2. **Ciljno občinstvo:** lastnik še ni odgovoril na vprašanje odrasli / tudi najstniki / tudi otroci. Predlog 18+ ni shranjena odločitev. Družinski namen sam ne določa starostne skupine.
3. **IARC:** začetni obrazec ima poslovni e-poštni naslov in kategorijo »Vse druge vrste aplikacij«. Sprejem [IARC pogojev](https://web.iarcservices.com/terms) ostaja nepotrjen; vprašanje lastniku je odprto. Pravila upravljanja brskalnika zahtevajo potrditev ob sprejemu novega pravno zavezujočega sporazuma. Vprašalnik/ocena še nista zaključena.
4. **Dostop za Google pregled:** lokalni način je prost, sodelovanje pa zahteva namenski pregledni HTTPS strežnik in delujoč račun. Obrazec App access ni shranjen z lažnim »poln dostop« ali lastnikovim geslom. Pripraviti trajen testni dostop in angleška navodila za dejanski obseg kandidatke; samo kratkotrajna enkratna registracijska koda ne zadostuje za ponovljiv pregled. V javnih datotekah ni poverilnic.
5. **Medijska dovoljenja:** obstoječi AAB8 zaradi `open_filex` vsebuje široka READ_MEDIA_IMAGES/VIDEO/AUDIO in starejše READ_EXTERNAL_STORAGE. Pregled ni pokazal potrebe po širokem dostopu. V novi kandidatki odstraniti nepotrebna dovoljenja ter preveriti izbirnik/odpiranje priponk in kopij. Console izjave o bistveni galerijski funkciji ne izpolnimo z neresničnim razlogom.
6. **Stari AI in deljena vsebina:** pregled ni našel ločene privolitve za samodejno dodan projektni AI kontekst, prijave spornega AI odgovora ali zahtevanih UGC pogojev/prijave vsebine oziroma uporabnika. Preveriti dosegljive tokove z računom, dopolniti ali izrecno omejiti obseg javne kandidatke; ne predpostaviti, da lastni ključ ali zaprta skupina odpravita zahteve. [Dokazi in uradni viri](GOOGLE_PLAY_DECLARATIONS.md).
7. **Varnost podatkov:** po zgornjih odločitvah dokončati konkretne collected/shared vrste in namene, preveriti hrambo strežnika/SMTP/AI ter uskladiti javno politiko. Delni osnutek še ni dokončna izjava.
8. **Fizični preizkusi:** uporabnik je potrdil izboljšano navigacijo/odzivnost. Posebej ostanejo preizkus dveh naprav/računov, pravice do financ, offline spremembe in ponovno povezovanje, obvestila drugega člana, kopija/obnova ter izbris testnega računa. To niso že potrjeni izidi tega koraka.
9. **Končna kandidatka:** po nujnih popravkih nov podpisani AAB, pregled končnega manifesta in dovoljenj, notranje testiranje, primerjava slik in deklaracij. Pred javno oddajo pregled preostalih nastavitev distribucije ter izrecna odločitev o oddaji/objavi.

## Preverjanje in dokazila

- 2 zajemna Flutter testa PASS, 12 dejanskih UI izrisov; brez pisanja v uporabnikovo bazo.
- Analiza: brez napak/opozoril, 37 obstoječih informacijskih ugotovitev. Proizvodna Dart koda, SDK in zaklenjene odvisnosti niso spremenjeni.
- Vseh 15 PNG preverjenih vizualno, po dimenzijah in hashih. Ikona je bajtno enaka obstoječi potrjeni Play ikoni.
- `python3 -m unittest discover -s tools/release -v`: 18 PASS.
- `python3 tools/release/check_readiness.py --code-only`: PASS; to ni store approval ali fizični preizkus.
- `git diff --check`, lokalne povezave dokumentacije in statičnih strani: PASS. `node tools/release/test_deletion_link.mjs`: PASS.
- Dokazi Console so v ignorirani `build/qa/google-play-public/`: `publishing-prepared.png`, `listing-ready.png`, `sl-screenshots-saved.jpg`, `category-contact-saved.jpg`, pet posnetkov posameznih shranjenih izjav, `data-safety-draft-url-pending.jpg`, `app-access-review-account-needed.jpg`, `iarc-terms-pending.jpg`.
- Javno besedilo o AI/FCM je usklajeno z najdenim vedenjem; paket je pripravljen lokalno, na gostovanje ni prenesen. Vseh 15 datotek ZIP se bajtno ujema s trenutnim `website/public/`; SHA-256 `0fb842c6f58ac83964bd8103f7393a11f2072f27ef060ee97caccb41a577b166`.

Obstoječi interni kanal s 15 člani ostaja nespremenjen. Ta priprava ne spreminja iOS stanja ali uvaja plačljivega gostovanja.
