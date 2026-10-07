# Obvestila in naslednja interna izdaja Jivie

Tekoča evidenca 7. oktobra 2026, ki jo vodi koordinacijski klepet. [Predaja](NOTIFICATION_HANDOFF.md) potrjuje zaključek vzporednih sprememb, gradenj in izdaj. Mobilni ID ostane `si.triparna.jivie`, Firebase projekt `jivie-e928a`, izdajatelj TriparNA. Ta dokument ni potrdilo fizične dostave ali oddaje.

## Vrstni red

1. Pregled že izvedenih obvestil, samo potrebne dopolnitve in preizkusi.
2. Pregled stabilnih virov in Git commit/push aplikacijskega repozitorija s sporočilom natanko `popolna predelava aplikacije`, brez dodatnega telesa.
3. Dvig na `1.0.1+2`, šele po glavnem commitu/pushu; trgovinska gradiva in preverjalnik sledijo isti različici. Zgodovinski dokazi `1.0.0+1` ostanejo.
4. Sveži podpisani AAB/IPA, pregled dejanskih ID-jev, različice, podpisov in Firebase/APNs virov, nato interna oddaja. Upload in aktivna testna distribucija sta ločena rezultata.
5. Šele po oddajah ureditev skupine `Domači`. Naslovov ne ugibamo in seznama ne shranjujemo v javni Git. Dostop do namestitve ni dovoljenje za širše upravljanje App Store Connect.

Ločen javni repozitorij Kanboard/FamilyHub in javna produkcijska izdaja nista predmet naloge. Stari Kanboard/podatki ostanejo ohranjeni.

## Implementacija in dokazi

Center obvestil, lokalni opomniki, konkretni/združeni cilji, preference in izbirni FCM že obstajajo. Drug vzporedni sistem ni potreben. Ciljni SMTP popravek trajno potrdi lease/poskus, nato sveže preveri pravice/prejemnika pod zaklepi `users → scope → job` skozi send/CAS. Dokončan preklic, deaktivacija ali izbris prepreči pošiljanje. Generično inbox sporočilo sledi aktualnemu veljavnemu naslovu; varnostne kode ohranijo ločeno vezavo. SMTP/FCM besedila so Jivie, identifikatorji in format kopij ostanejo združljivi.

- 90/90 Flutter testov v 10 datotekah; analyze izhod 0, istih 35 podedovanih info, brez napak/opozoril. SDK/odvisnosti nespremenjeni. Dokazi: `build/qa/notification-final-check/`.
- Pred-fix šest SMTP scenarijev FAIL na vsaki bazi; po popravku 36 race + 16 SMTP + 77 push + 48 account = 177 na vsaki SQLite/MySQL/MariaDB, skupaj 531. Pravi loopback SMTP, noben resnični prejemnik. Dokazi: `build/qa/smtp-race/`.
- Procesni izpad po SMTP ACK ohrani lease/števec; ponovitev po izteku uporablja isti Message-ID in lahko podvoji e-pošto. Enkratna dostava ni zagotovljena.
- PHP lint osmih datotek in `git diff --check` uspešna. Izolirana testna okolja odstranjena, druge instance/arhiv ohranjeni.

## Ponudniki in fizični preizkus

Firebase HTTP v1 API je dejansko omogočen. Klientovi konfiguraciji/generirana izhoda se ujemajo in so ignorirani v Gitu. Firebase CLI prijava je potrjena; nobena strežniška poverilnica ni v odjemalcu.

Google Cloud zahteva prvo ločeno sprejetje pogojev; potrditev ni prejeta. Strežniška FCM identiteta/ključ in razvojni/produkcijski APNs ključ še niso pripravljeni. FCM na testnem strežniku ostane izključen. Dostave na fizičen telefon ne označujemo kot potrjene.

SMTP TLS/prijava in cron na novi testni namestitvi so preverjeni, prejeto zunanje sporočilo pa še ne. Fizični Android/iPhone, prejemniški test in Apple deklaracija šifriranja so v [korakih lastnika](OWNER_ACTIONS.md).

## Tekoči izidi

Glavni commit/push, dvig različice, sveži paketi in novi oddaji v tej koordinacijski nalogi še niso izvedeni. Namestitev štirih modelov na testni cPanel se preverja ločeno od osnovnega potrjenega 0.6.0 ZIP. Lokalni patch/manifest sta `build/releases/FamilyHub-0.6.0-notification-patch.*`; ne spreminjata baze, konfiguracije ali skrivnosti.
