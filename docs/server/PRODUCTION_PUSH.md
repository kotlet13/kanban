# Produkcijski push na jivie.triparna.si

14. oktober 2026: **produkcijski FCM je vključen, Google OAuth in validacija
HTTP v1 sta uspešna, minutni cron je dejansko tekel**. Telefonski prikaz pri
zaprti aplikaciji še ni potrjen. Lastnik je po odstranitvi aplikacije obnovil
geslo istega uporabnika, se uspešno prijavil in potrdil »Naprava je
registrirana«; read-only baza potrdi eno aktivno Android registracijo za isti
Firebase projekt. Sledi eno pravo oddaljeno časovno opozorilo iz aplikacije.
Android ostaja javni **1.7.1(26)**, brez nove gradnje ali internega kanala.

## Identiteta in varovanje

Po lastnikovi izrecni potrditvi je v obstoječem projektu `jivie-e928a`
ustvarjen samo produkcijski račun
`jivie-production-fcm-sender@jivie-e928a.iam.gserviceaccount.com`, z izbrano
vlogo **Firebase Cloud Messaging API Admin**
(`roles/firebasecloudmessaging.admin`). Ta vloga velja za FCM vire projekta;
ni splošna vloga Owner/Editor in ni omejena na posamezno napravo.
Obstoječi testni pošiljatelj in njegov ključ nista spremenjena ali kopirana.

En nov ključ je v Google Cloud prikazan kot **Active**, ID
`4099e9d7bd43375af409e6c26fcc64ff146c3e9a`. JSON/private key, napravljeni
žetoni, OAuth/JWT in gesla niso izpisani, vključeni v dokumentacijo ali Git.
Lokalni ključ je zunaj repozitorija v zaščiteni zasebni mapi (0700/0600);
izvirna datoteka iz Downloads je prestavljena tja. Nalaganje je po omejitvi
Braveovega dodatka potekalo z običajnim sistemskim izbirnikom, brez novih
dovoljenj dodatka.

Na gostovanju je ključ pod
`/home/tripar13/private/jivie-production/jivie-production-fcm-sender.json`.
Svež cPanel `DomainInfo domains_data` inventar potrdi **15 kanoničnih spletnih
korenov**, zasebna mapa je zunaj vseh. Konfiguracija, JSON in ločeni naključni
32-bajtni `familyhub-push.key` imajo 0600; zasebne mape 0700. Poštni šifrirni
ključ ni ponovno uporabljen.

## Preklop in dokazi

Uporabljen je obstoječi pregledani
[FCM pomočnik](FCM_SETUP_HELPER.md), SHA256
`eda0eba325be4c379332c75d7228942be1cbcb21b409a59c5d7cb17f7ba314f3`, z izrecnimi
produkcijskimi potmi in istim Firebase projektom; njegovih testnih privzetih
poti nismo uporabili. `--check`, `--prepare`, oba PHP lint pregleda,
`--activate` ter `push-preflight.php` so uspešni. Izklopljena literalna FCM
definicija je zamenjana samo z vključitvijo zasebnega `fcm-config.php`;
obstoječa vključitev SMTP in ostale nastavitve so ohranjene.

| Dokaz | Rezultat |
| --- | --- |
| Feature SHA pred preklopom | `913784fa9a2f52f83bcfeb9c380095103359a2dad5c59a7fce9675d902c10822` |
| Feature SHA po preklopu | `a3a109f8d1bf05c1ecf02c929e5659ef385946b7390dbad65c8e81af545ea21c` |
| Inventar 15 korenov SHA | `35f24acd63f43bb11942510a2ac0ff26750ee0e61e2d054a3dd962e76890b5b3` |
| Cron SHA po dodatku | `d0fe5413284dd8457be32d77ad5303159b30c587eb784393c889d3e7a74a2197` |
| Offline preflight | configured/nativeEnabled=true; networkRequests=0, providerVerified=false po zasnovi |
| Google | Pravi NativeFcmTransport OAuth scope firebase.messaging PASS; `validate_only=true` HTTP200; 2 omrežna klica, brez dostave in DB dostopa |
| HTTPS capabilities | HTTP200, externalPush=true, pushProjectId=jivie-e928a, smtp/emailInvitations/emailVerification/passwordReset=true |
| Server ID | Isti `ad56910f-ca2e-41ee-af0d-3f18081497cf` |
| Android registracija | Lastnik »Naprava je registrirana«; read-only baza eno aktivno Android registracijo v jivie-e928a, brez izpisa žetona |
| Minutni cron | Dejanski dnevnik star 46 sekund; examined/accepted/retry/cancelled/coalesced vsi 0; zasebna dovoljenja preverjena |

Validacija uporabi sintetično temo in standardni generični push payload, brez
pravega napravnega žetona ali uporabniške vsebine.
[Googlova referenca](https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages/send)
določa, da `validate_only` preizkusi zahtevo brez dejanske dostave. To ne dokazuje
prikaza na telefonu ali APNs.

Konfiguracijska kopija/inventar/cron pred in po preklopu ter neskrivni dokaz
so zasebno pod `install/fcm-production-20261014`; zapečaten izvirnik in
kandidat pomočnika pod `install/fcm-setup`. Ni migracije, spremembe kode
vtičnika, računa, gesla, uporabniške vsebine ali samodejno ustvarjenega
preizkusnega obvestila. Obstoječi reminders/account cleanup/SMTP vnosi so
bajtno ohranjeni; dodan je natanko en vnos:

```cron
* * * * * umask 077; /usr/bin/flock -n /home/tripar13/private/jivie-production/logs/push.lock /opt/alt/php84/usr/bin/php /home/tripar13/jivie.triparna.si/plugins/FamilyHub/cli/push.php --limit=20 >> /home/tripar13/private/jivie-production/logs/push.log 2>&1
```

Neskrivni lokalni dokazi so v `build/qa/production-push-20261014/`:
`public-capabilities.json`, `provider-verified.png`, `production-push-ready.png`
in `production-service-account-key.png`. Operativni provider probe je v isti
ignorirani QA mapi in zasebno na strežniku; ni del javnega vtičnika.

## Vzdrževanje in naslednji fizični korak

Geslo Jivie preverja `NativeAuthService` proti isti `users.password` kot
Kanboard. Skrbnik lahko spremeni geslo obstoječega **anze.novsak**, brez
brisanja računa/podatkov ali spremembe `jivie_admin`. Novo geslo vnese lastnik
neposredno; sprememba fingerprinta razveljavi stare Native prijave. Obnova
po e-pošti zahteva prej potrjen e-poštni naslov, ne samo delujoč SMTP.
Lastnik potrdi obnovljen dostop in uspešno prijavo; agent gesla ni spreminjal
ali bral.

Po ponovni prijavi na Androidu: Več → Nastavitve → Oddaljena obvestila na tej
napravi → Omogoči oddaljena obvestila, dovoljenje OS ter »Naprava je
registrirana«. Vrste obvestil se izberejo za posamezni skupni prostor.
Naprava je zdaj registrirana in potrjena; lastnik pripravlja eno opravilo
»Preizkus push« v sinhroniziranem Dom ter pravi »Dodaj oddaljeni opomnik«.
Za urejevalca je to ločeni zvonček s plusom desno ob opravilu na seznamu;
prejšnje navodilo za meni ⋯ je bilo popravljeno po pregledu istega mobilnega
izvora. Lokalni prostor ali sam rok opravila tega oddaljenega opomnika ne
ustvarita.
Nato sledi obvestilo pri zaprti/zaklenjeni aplikaciji in preverjanje
odpiranja pravega zapisa. Tega preizkusa še ni bilo; ne ponavljaj splošne
funkcionalne matrike ali gradnje. APNs/iPhone ostajata ločeno preverjanje.

Povrnitev FCM uporablja zapečateni izvirnik pomočnika z istimi argumenti;
obnavlja SMTP-vključen feature config. Cron povrni z odstranitvijo samo
novih produkcijskih push vrstic ob upoštevanju morebitnih poznejših sprememb,
ne s slepo namestitvijo celotne stare kopije. Ključev ne briši.
Prejšnji SMTP setup/check pomočnik zaradi novega feature/cron odtisa namerno
zavrne spremenjeno stanje; ne zaženi njegove aktivacije/obnove in ne rahljaj
varoval, da bi odstranil ta dovoljeni FCM dodatek.

Redne produkcijske kopije ostajajo odprto ločeno delo. Ta kopija nastavitev
ne vključuje DB ali fotografij. Pri bodočem celotnem zajemu ohrani tudi
zasebne FCM/SMTP konfiguracije in šifrirne ključe.

## Povezava v povabilu

Obstoječe povabilo po e-pošti vsebuje HTTPS povezavo do strani povabila;
ta ima »Odpri v aplikaciji« (`jivie://invite?...`) ter kopiranje kode.
Neposredne Google Play namestitvene povezave trenutno ni niti v sporočilu
niti na tej strani. To je preverjeno v NativeAccountMailTransport in
InvitationController; ta korak besedila ali funkcije povabila ne spreminja.
