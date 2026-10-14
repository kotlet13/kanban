# Produkcijska pošta — 14. oktober 2026

**Pošta za Jivie na `https://jivie.triparna.si/` je vključena.** Lastnik je
izbral obstoječi namenski predal `admin@jivie.triparna.si` in sam vnesel njegovo
geslo neposredno v skrit poziv strežniškega terminala. Geslo ni bilo prebrano,
izpisano, poslano v pogovor ali preneseno v Git.

## Dejansko preverjeno

- cPanel račun `tripar13`; namenski predal obstaja in ni omejen za prijavo ali
  odhodno pošto. Prejšnji odprti obrazec ustvarjanja ni bil oddan v imenu lastnika.
- DKIM, SPF in PTR so že veljavni. Dodan je samo manjkajoči TXT
  `_dmarc.jivie.triparna.si = v=DMARC1; p=none;`, kar potrdita cPanel in javni DNS.
  Obstoječa nadrejena domena je imela enako politiko `p=none`.
- SMTP `cp-21.controlpanel.si:465`, SSL/TLS z obveznim preverjanjem certifikata
  in imena strežnika; dejanska prijava uspe brez pošiljanja.
- Naključni ločeni 32-byte ključ za šifrirano vrsto varnostne pošte in povabil.
  Geslo, ključ, SMTP ter feature konfiguracija so 0600 zunaj javnih korenov.
- Javni HTTPS capabilities vrne200, isti `serverId`
  `ad56910f-ca2e-41ee-af0d-3f18081497cf` ter `smtp`, `emailInvitations`,
  `emailVerification`, `passwordReset = true`; `externalPush = false`.
- Kanonični naslov povabil je izrecno `https://jivie.triparna.si/`.
- Celoten prejšnji crontab je ohranjen. Dodana sta samo minutna workerja
  `account-mail.php --limit=20` in `delivery.php --limit=20`, vsak s svojo
  zaklepno datoteko in zasebnim dnevnikom. Oba ročna zagona vrneta exit0 in
  veljaven JSON; ob pregledu oba cron dnevnika vsebujeta uspešen rezultat,
  sta stara48sekund in imata način0600. Vrsti sta takrat prazni.
- Poslano je natanko eno dogovorjeno benigno testno sporočilo lastniku.
  SMTP vrne sprejem enega prejemnika; lastnik potrdi **»Prispelo v Prejeto«**.
  Sporočilo ne vsebuje povabila, kode ali prijavnih podatkov. Drugi prejemniki
  niso bili kontaktirani.

## Nastavitve, kopija in pomočnik

Zasebna mapa `/home/tripar13/private/jivie-production/install/smtp-20261014`
hrani predhodno feature/core konfiguracijo, celoten prejšnji crontab in stanje
aktivacije. Kopije so bile dejansko primerjane pred vključitvijo. Priprava ni
spremenila žive konfiguracije ali opravil; aktivacija je sledila uspešni TLS/
SMTP prijavi. Predhodni feature SHA256 je
`8b95f016af472cf681ceba92978ac959df9d945bfb810926567990ee4977f797`.

[Produkcijska pomočnika](../../server/scripts/production-mail/README.md) sta
nameščena zunaj javnega korena v `install/smtp-tools-20261014`:

| Datoteka | SHA256 |
| --- | --- |
| `setup.py` | `6d3b2a5faa69543d84d890ea6f42fa32e2d71324fecab6bcffbe1c3981c6955e` |
| `probe.php` | `d4a31e64aa3aa8f91d3e7b578d83fc94e41cca6202cbc61716c84e016fd65696` |

Vseh7 lokalnih kontrol varoval PASS; PHP lint uspe v izoliranem obstoječem
PHP8.4 vsebniku brez omrežja in na dejanskem strežniku. Gostovana priprava
potrdi backupVerified/privateModesVerified. To je dopolnitev konfiguracije,
ne nadgradnja vtičnika ali migracija baze.

Dokazi brez gesel v `build/qa/production-mail-20261014/`:
`tools.json`, `prepared-terminal.png`, `dns-valid.png`, `smtp-auth.png`,
`smtp-active.png`, `smtp-test-accepted.png`, `workers-verified.png`,
`public-capabilities.json` in `delivery-evidence.json`.

## Uporaba in meje

Po ponovnem odpiranju aplikacije oziroma osvežitvi strežnika je pošiljanje
e-poštnih povabil na voljo v nastavitvah skupnega prostora. Worker obdeluje
vrsto vsako minuto. Prejemnik odpre povabilo, se prijavi ali ustvari račun,
nato ga izrecno sprejme. SMTP sprejem sam po sebi ne zagotavlja končne dostave
vsakega prihodnjega sporočila; potrjeni prejem velja za zgornji test.

Dejansko povabilo in celotni tok preverjanja naslova/obnove gesla v tej nalogi
nista bila izvedena v imenu uporabnika. Funkcije in pogodbe so obstoječe;
njihova dostavna konfiguracija je zdaj vključena. Ohranjen je isti FamilyHub
0.13/schema17, Android1.7.1(26), strežniška identiteta, računi in vsebina;
test1/test2, spletna stran, Google Play in iOS niso spremenjeni.

FCM/oddaljeni push in redne produkcijske kopije ostajajo ločeno odprto delo.
Zgornje kopije konfiguracije niso kopija prihodnjih uporabniških podatkov.
Redna kopija mora zajeti tudi poštni ključ, zaščiteno SMTP konfiguracijo/geslo,
bazo in celotno zasebno podatkovno drevo.
