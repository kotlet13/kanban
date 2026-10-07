# Jivie — preostali koraki za lastnika

Stanje te naloge: 7. oktober 2026. Uporabnik je dovolil samostojne izvedbene odločitve in zahteval, da odprte odločitve zapišemo, ker ne bo več pri računalniku. To je seznam za nadaljevanje; ni nova zahteva, da sproti potrjuje že dogovorjeno delo.

## Kaj je že odločeno in urejeno

- Ime **Jivie**, izgovorjava dživi; Android/iOS **si.triparna.jivie**; brezplačna aplikacija. Plačljivo upravljano gostovanje ostaja poznejša faza.
- Nov ločen testni strežnik **https://jivie-test.triparna.si/** s FamilyHub 0.6.0. Stari Kanboard/podatki so ohranjeni. Native API in self-hosted izbris sta vključena; stara projektna povabila in FCM dostava ostajajo izključeni.
- Podatki, SMTP geslo in šifrirni ključ poštne vrste so zunaj javnih spletnih map, z omejenimi dovoljenji. Poštni predal `jivie-test@triparna.si` je ustvaril lastnik; SMTP TLS in prijava sta uspešno preverjena brez pošiljanja sporočila.
- Periodična opravila so nastavljena. Nakupovalnih dodatkov nismo spremenili v obvezna posamezna e-poštna sporočila.
- Vrt je izveden kot lokalni modul s kopijo/obnovo. Samodejnega deljenja vrtov ali preselitve arhiva ni.
- Android 1.0.0 (1) je na internem kanalu; iOS IPA 1.0.0 (1) je podpisana. Javne izdaje še ni. Končno stanje in uskladitev naslednje izdaje vodi [predaja](NOTIFICATION_HANDOFF.md).

## Odprto

| Korak | Kaj še potrebujemo | Kaj lahko agent naredi sam |
| --- | --- | --- |
| Test na telefonih | Dostopen Android in iPhone, namestitev testne izdaje ter preverjanje dovoljenj/obvestil na zaklenjenem telefonu. | Pripravi izdajo, navodila in preizkuse; center, lokalni opomniki ter FCM že obstajajo. |
| Testni dostop Play/TestFlight | Končni preizkuševalci in dovoljen dostop; trenutna Play izdaja nima izbranega seznama. | Uredi dogovorjeni seznam po zaključeni implementaciji in novi izdaji; ne dodaja ljudi iz nepovezanih seznamov. |
| FCM in APNs | Dokončanje strežniške FCM identitete in Apple APNs povezave; morebitno potrjevanje ponudnikovih pogojev ali varnostnega dostopa ostane lastnikovo. | Pripravi najmanjše potrebne pravice, zasebno konfiguracijo ter merljiv preizkus dostave. Ključev ni treba pošiljati v klepet. |
| Google Cloud pogoji | Odprt je prvi obrazec za ločeno sprejetje Google Cloud Platform Terms of Service in pogojev uporabljenih storitev/API-jev. Potrditev še ni prejeta. | Obrazec za projekt `jivie-e928a` je pripravljen, promocijska pošta izključena. Potrjena Firebase CLI prijava ne nadomesti tega pravnega koraka. |
| Apple encryption compliance | Izdajateljeva klasifikacija šifriranja/izjeme ter države distribucije, zlasti Francija. | Predloži tehničen popis in pripravi obrazec; ne označi izjeme brez ustrezne podlage. AES-256-GCM/PBKDF2 in Dart fallback pomenijo, da šifriranje ni omejeno samo na Apple OS. |
| Dejanski prejem pošte | E-poštni naslov in dovoljenje za eno testno sporočilo oziroma test preverjanja/obnove računa. | TLS/prijava sta že preverjena brez sporočila. Po potrditvi preveri še sprejem in obnašanje vrste. |
| Javna stran jivie.app | Lastnik namerava sam objaviti pripravljen statični ZIP; nato potrdi, da je objavljena. | Preveri javne HTTPS strani, povezave pomoči/zasebnosti/izbrisa in povezave v trgovinah. |
| Končna trgovinska oddaja | Pregled dejanskih podatkovnih izjav in morebitnih novih pravno zavezujočih izjav v konzolah. | Pripravi izpolnjen predlog iz kode in preverjenih tokov; ne trdi, da je build ali naložitev že javna objava. |
| Zasebna kopija podpisnih ključev | Lastnik naj varno ohrani Android upload ključ in obnovitvene podatke zunaj repozitorija. | Lokalno so v `/Users/anzenovsak/.local/share/jivie/signing/`, mapa 0700/datoteke 0600; ključev in gesel ne izpisuje. |

Za Apple: [uradna tabela šifriranja](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption), [izdajateljeva presoja](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/). Prisotnost standardnega algoritma sama ne določa, ali velja pravna izjema.

Podrobna dokazila: [testni izdaji](TEST_RELEASE_STATUS.md), [cPanel](../server/CPANEL_SETUP.md), [preostali pogoji javne izdaje](READINESS.md). Ta dokument ne vsebuje gesel, sejnih povezav ali ključev.

## Usklajeno nadaljevanje obvestil in izdaje

Drugi klepet je predal stabilno stanje. Končni odjemalčev sklop je 90/90 PASS; analiza ohrani 35 prejšnjih info, brez napak/opozoril. SMTP popravek in Jivie besedila so preverjeni s 531 kontrolami na treh bazah. To ne potrjuje fizičnega push ali prejetega zunanjega sporočila. [Tekoča izvedba](NOTIFICATION_RELEASE_RUN.md) loči ta stanja.

Uporabnikov vrstni red je implementacija/testi → Git commit/push s sporočilom natanko `popolna predelava aplikacije` → dvig različice → novi interni izdaji → skupina `Domači`. Naslovov ne ugibamo ali shranjujemo v javni Git. iOS notranji TestFlight dostop preverimo glede na obstoječe člane App Store Connect; za namestitev ne dodeljujemo širših upravljavskih pravic brez ustrezne podlage. Ločen javni repozitorij vtičnika ostaja za pozneje.
