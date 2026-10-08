# Jivie — preostali koraki za lastnika

Kratek aktualni seznam: [kaj še urediš ti](OWNER_NEXT_STEPS.md). Android 1.1.0+3 je aktivno objavljen za obstoječi seznam `domači` (15); njegove dokaze in testno namestitev vodi [izvedbeni dnevnik](../UPGRADE_IMPLEMENTATION.md). Spodnji dokazi izdaje2 ostanejo zgodovinski.

Stanje te naloge: 8. oktober 2026. Uporabnik je dovolil samostojne izvedbene odločitve in zahteval, da odprte odločitve zapišemo, ker ne bo več pri računalniku. To je seznam za nadaljevanje; ni nova zahteva, da sproti potrjuje že dogovorjeno delo.

## Kaj je že odločeno in urejeno

- Ime **Jivie**, izgovorjava dživi; Android/iOS **si.triparna.jivie**; brezplačna aplikacija. Plačljivo upravljano gostovanje ostaja poznejša faza.
- Nov ločen testni strežnik **https://jivie-test.triparna.si/** s FamilyHub 0.7.0/schema11 po preverjeni kopiji in obnovi. Stari Kanboard/podatki so ohranjeni. Native API in self-hosted izbris sta vključena; stara projektna povabila in FCM dostava ostajajo izključeni.
- Podatki, SMTP geslo in šifrirni ključ poštne vrste so zunaj javnih spletnih map, z omejenimi dovoljenji. Poštni predal `jivie-test@triparna.si` je ustvaril lastnik; SMTP TLS in prijava sta uspešno preverjena brez pošiljanja sporočila.
- Periodična opravila so nastavljena. Nakupovalnih dodatkov nismo spremenili v obvezna posamezna e-poštna sporočila.
- Vrt je izveden kot lokalni modul s kopijo/obnovo. Samodejnega deljenja vrtov ali preselitve arhiva ni.
- Android **1.1.1 (4)** je objavljen na aktivnem internem kanalu z vključenim seznamom `domači` (zdaj 15 članov); prvotna iOS oddaja 1.0.1 (2) je bila zavrnjena pri Apple obdelavi. Popravljena iOS razvojna kandidatka je preverjena, njen distribucijski izvoz pa še ni uspel. Stari paketi ostanejo ohranjeni. [Aktualni potek](NOTIFICATION_RELEASE_RUN.md) loči upload, obdelavo in dejanski dostop.

## Odprto

| Korak | Kaj še potrebujemo | Kaj lahko agent naredi sam |
| --- | --- | --- |
| Odklep in Xcode podpisovanje | Mac je zaklenjen; distribucijski izvoz popravljene iOS kandidatke z obstoječo ekipo vrne `No Accounts`. Odkleni Mac in preveri/obnovi obstoječo prijavo v Xcode → Settings → Accounts za TriparNA. | Pripravi svežo iOS kandidatko iz aktualne kode (zdaj 1.1.1+4) iz nadgrajene kode z obstoječim managed certifikatom/profilom, nato preveri App Store obdelavo. Ne ustvarja novega certifikata ali druge ekipe. Zaklep native UI in CLI `No Accounts` sta ločeni opažanji, ne dokazana ista napaka. |
| Test na telefonih | Uporabnik je 8. oktobra potrdil namestitev/zagon Android 1.0.1 (2) na Galaxy S25 po prisilni ustavitvi Trgovine Play. Še potrebujemo preizkuse funkcij/dovoljenj/obvestil in iPhone namestitev. | Pripravi izdajo, navodila in preizkuse; center, lokalni opomniki ter FCM že obstajajo. |
| Testni dostop Play/TestFlight | 8. oktobra je po novi uporabnikovi odločitvi obstoječi `domači` s 14 člani izbran in shranjen za Jivie; Play kanal 1.0.1 (2) kaže `Aktivno`. Po naslednji uporabnikovi zahtevi je dodan še njegov razvijalski račun, skupaj 15 članov. [Pridružitev Android preizkusu](https://play.google.com/apps/internaltest/4701286726300038561). Namestitev na uporabnikov telefon še ni potrjena; popravljena iOS oddaja še ni na voljo. | Android dostop je urejen, iOS nadaljuje po uspešni oddaji. Naslovov ne ugiba; za namestitev ne ustvarja širših App Store Connect privilegijev. |
| FCM in APNs | Dokončanje strežniške FCM identitete in Apple APNs povezave; morebitno potrjevanje ponudnikovih pogojev ali varnostnega dostopa ostane lastnikovo. | Pripravi najmanjše potrebne pravice, zasebno konfiguracijo ter merljiv preizkus dostave. Ključev ni treba pošiljati v klepet. |
| Google Cloud pogoji | Odprt je prvi obrazec za ločeno sprejetje Google Cloud Platform Terms of Service in pogojev uporabljenih storitev/API-jev. Potrditev še ni prejeta. | Obrazec za projekt `jivie-e928a` je pripravljen, promocijska pošta izključena. Potrjena Firebase CLI prijava ne nadomesti tega pravnega koraka. |
| Katalog naprav Google Play | Pri pregledu uporabnikove neuspešne namestitve na Galaxy S25 je prvi vstop v katalog zahteval dodatne pogoje storitve za katalog naprav. Niso sprejeti. | Če bo potreben pregled konkretnega modela, pripravi [Googlove pogoje](https://play.google.com/about/device-catalog-terms.html) za izrecno potrditev. Paket je neodvisno preverjen: API 24+, arm64-v8a/armeabi-v7a/x86_64 ter podpora 16 KB; to ne potrjuje konkretne naprave ali uspešne namestitve. |
| Apple encryption compliance | Izdajateljeva klasifikacija šifriranja/izjeme ter države distribucije, zlasti Francija. | Predloži tehničen popis in pripravi obrazec; ne označi izjeme brez ustrezne podlage. AES-256-GCM/PBKDF2 in Dart fallback pomenijo, da šifriranje ni omejeno samo na Apple OS. |
| Nadaljnji e-poštni preizkusi | Preizkus obnove gesla in običajnih obvestil na izrecno izbranem testnem računu. | Uporabnik je 8. oktobra že potrdil prejem kode in preverjanje e-pošte v Android aplikaciji. Sporočilo o uspehu je popravljeno in lokalno preverjeno; obnova gesla in druge vrste pošte ostajajo ločeni preizkusi. |
| Javna stran jivie.app | Lastnik namerava sam objaviti pripravljen statični ZIP; nato potrdi, da je objavljena. | Preveri javne HTTPS strani, povezave pomoči/zasebnosti/izbrisa in povezave v trgovinah. |
| Končna trgovinska oddaja | Pregled dejanskih podatkovnih izjav in morebitnih novih pravno zavezujočih izjav v konzolah. | Pripravi izpolnjen predlog iz kode in preverjenih tokov; ne trdi, da je build ali naložitev že javna objava. |
| Zasebna kopija podpisnih ključev | Lastnik naj varno ohrani Android upload ključ in obnovitvene podatke zunaj repozitorija. | Lokalno so v `/Users/anzenovsak/.local/share/jivie/signing/`, mapa 0700/datoteke 0600; ključev in gesel ne izpisuje. |

Za Apple: [uradna tabela šifriranja](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption), [izdajateljeva presoja](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/). Prisotnost standardnega algoritma sama ne določa, ali velja pravna izjema.

Podrobna dokazila: [testni izdaji](TEST_RELEASE_STATUS.md), [cPanel](../server/CPANEL_SETUP.md), [preostali pogoji javne izdaje](READINESS.md). Ta dokument ne vsebuje gesel, sejnih povezav ali ključev.

## Usklajeno nadaljevanje obvestil in izdaje

Drugi klepet je predal stabilno stanje. Končni odjemalčev sklop je 90/90 PASS; analiza ohrani 35 prejšnjih info, brez napak/opozoril. SMTP popravek in Jivie besedila so preverjeni s 531 kontrolami na treh bazah. To ne potrjuje fizičnega push ali prejetega zunanjega sporočila. [Tekoča izvedba](NOTIFICATION_RELEASE_RUN.md) loči ta stanja.

Prvotni vrstni red je implementacija/testi → Git commit/push s sporočilom natanko `popolna predelava aplikacije` → dvig različice → novi interni izdaji → skupina `Domači`. Uporabnik je 8. oktobra spremenil zadnji pogoj: Android testiranje se začne takoj, neodvisno od iOS. Seznam `domači` je že vključen; dokaz je `build/qa/jivie-next-release/play-domaci-active.png`. Naslovov ne ugibamo ali shranjujemo v javni Git. iOS notranji TestFlight dostop preverimo glede na obstoječe člane App Store Connect; za namestitev ne dodeljujemo širših upravljavskih pravic brez ustrezne podlage. Ločen javni repozitorij vtičnika ostaja za pozneje.
