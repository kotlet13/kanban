# FamilyHub: pogodba API različice 1

> Pogodba opisuje izvedeno razvojno osnovo. Registracija, prijava z napravo, ločene pravice financ in sinhronizacija niso vključene. Besedilo pogodbe je v slovenščini; imena metod ostajajo angleška.

## Prenos in identiteta

Metode uporabljajo Kanboardov `jsonrpc.php` in JSON-RPC 2.0. Parameter `id` je identifikator odgovora JSON-RPC, `request_id` pa ločen trajen identifikator ustvarjanja povabila. Odjemalec uporabi svoje uporabniško ime z uporabniškim geslom ali obstoječim osebnim API žetonom. Na produkcijski povezavi je potreben HTTPS. Lokalni HTTP je vezan na loopback.

Kanboardova avtentikacija še vedno preverja geslo, aktivnost uporabnika in zaklepanje neuspelih prijav. Uporabnik z vključeno 2FA se prek obstoječega API prijavi z osebnim API žetonom; samo geslo je zavrnjeno. Vtičnik ne izdaja novih napravnih žetonov in ne obide drugega faktorja. Dolgoživost obstoječih Kanboard API žetonov ni rešitev bodoče pogodbe za naprave.

Vse metode zavrnejo anonimnega uporabnika, deaktiviran račun ter globalno identiteto `jsonrpc`. Lastni middleware za predpono `familyHub` po Kanboardovi avtentikaciji preveri tudi, da HTTP uporabniško ime ustreza dejansko prijavljeni uporabniški identiteti. Skrbniški položaj aplikacije sam po sebi ne zadošča za upravljanje povabila. Uporabnik potrebuje trenutno standardno vlogo `project-manager` v konkretnem projektu, neposredno ali prek skupine. Poljubne ali javne vloge niso samodejno priznane kot upravljavske.

## Pogajanje o zmožnostih

`familyHubGetCapabilities` nima parametrov. Vrne:

```json
{
  "plugin": "FamilyHub",
  "plugin_version": "0.5.0",
  "contract_version": 1,
  "kanboard_version": "1.2.54",
  "actor": {"user_id": 12, "username": "synthetic-user"},
  "features": {
    "project_invitations": false,
    "account_registration": false,
    "device_login": false,
    "local_first_sync": false,
    "finance_acl": false
  },
  "invitation_policy": {
    "enabled": false,
    "configuration": "FAMILYHUB_ENABLE_PROJECT_INVITATIONS",
    "reason": "requires_separate_finance_storage_and_acl",
    "recipient": "existing_named_user",
    "role": "project-member",
    "max_lifetime_seconds": 604800
  }
}
```

Odjemalec ne sme sklepati o zmožnostih iz same različice Kanboarda. Manjkajoča metoda (`Method not found`) pomeni odsoten ali nezdružljiv vtičnik; osnovni lokalni način mora delovati dalje. Napaka avtentikacije ali dostopa ni dokaz, da vtičnika ni, in ne sme sprožiti poskusa z globalnim ključem. Za neznano različico pogodbe odjemalec izključi razširitvene funkcije, dokler nima podprte pogodbe. Stari odjemalci uporabljajo obstoječe metode Kanboarda; vtičnik jih ne nadomesti.

Privzeto so povabila izključena. Dovoljenje boolean `FAMILYHUB_ENABLE_PROJECT_INVITATIONS=true` v Kanboardovi nastavitvi omogoči razvojno preverjanje na SQLite ali MySQL. Takrat `project_invitations` in `invitation_policy.enabled` postaneta `true`, razlog pa `explicit_opt_in`. `finance_acl` ostane `false`. S tem ni dovoljeno deliti obstoječih finančnih projektov v produkciji.

## Povabila obstoječih uporabnikov

| Metoda | Parametri | Pogoji in rezultat |
| --- | --- | --- |
| `familyHubCreateProjectInvitation` | `project_id`: pozitivni celoštevilski ID; `recipient_username`: obstoječe aktivno ime; `request_id`: 16–64 znakov `[A-Za-z0-9_-]`; `expires_in`: celo število 60–604800, privzeto 86400 | Trenutni upravljavec aktivnega, skupnega projekta ustvari povabilo za drugega obstoječega uporabnika. Vrne `invitation_id`, `project_id`, `expires_at`, `token`, `token_available`. |
| `familyHubPreviewProjectInvitation` | `token`: 64 malih šestnajstiških znakov | Samo imenovani prejemnik. Povabilo mora biti neuporabljeno, nepreklicano in veljavno; izdajatelj mora še vedno upravljati aktivni skupni projekt. Vrne samo ID, ime projekta, vlogo in potek. |
| `familyHubAcceptProjectInvitation` | `token` | Samo imenovani aktivni prejemnik. Preveri stanje povabila in trenutne pravice izdajatelja; v isti transakciji porabi povabilo ter doda projektnega člana. Vrne `accepted=true`, ID in `replayed`. |
| `familyHubRevokeProjectInvitation` | `invitation_id`: 32 malih šestnajstiških znakov | Trenutni upravljavec istega projekta prekliče neuporabljeno povabilo. Vrne ID in `revoked=true`. Sprejetega povabila ne spreminja; odstranjevanje članstva je ločen Kanboardov postopek. |

Zasebni in neaktivni projekti niso deljeni s to pogodbo. Projektni ID je **oddaljeni Kanboard ID**, ne lokalna identiteta osebnega zapisa. Vtičnik ne zagotavlja dostopa do ločenih financ ali gospodinjstva. Obstoječa neposredna ali skupinska vloga prejemnika se ob sprejemu ohrani, tudi če je samo `project-viewer`; sprejem je ne zviša.

## Žetoni, ponavljanje in transakcije

Žeton ustvari `random_bytes(32)`. V bazi je samo SHA256 žetona; surovi žeton se vrne enkrat ob ustvarjanju. Povabilo je vezano na ID konkretnega prejemnika. Povezava ali QR zato ne vsebuje gesla ali osebnega API ključa. Pošiljanje QR, povezave in e-pošte še ni implementirano.

`request_id` je enoličen znotraj izdajatelja. Ponovitev z istim projektom, prejemnikom in trajanjem vrne isto povabilo, `token=null` ter `token_available=false`. Drugačni parametri z istim ključem so napaka. Odjemalec mora enkrat prejeti žeton varno ohraniti do izdelave povabila; po izgubljenem odgovoru lahko dobi ID, prekliče povabilo in ustvari novo z novim `request_id`. Strežnik žetona ne more obnoviti iz zgoščene vrednosti in ob ponovitvi ne ustvari tiho drugega.

Sprejem uporablja pogojni `UPDATE`, ki uspe samo za trenutno veljavno neuporabljeno in nepreklicano vrstico. Poraba povabila in dodajanje neposrednega člana sta v isti transakciji na isti PDO povezavi. Napaka dodajanja člana povrne tudi porabo povabila. Sočasna sprejema ne podvojita članstva. Hkratna sprejem in preklic lahko povzročita prehodno napako ene zahteve; drugi klic varno ponovi z istim žetonom ali ID. `revoked=true` se ne vrne, če je sprejem že porabil povabilo.

Ponovljen sprejem lahko vrne `replayed=true`, če isti prejemnik še vedno ima neposreden ali skupinski dostop do aktivnega skupnega projekta. Po odstranitvi obeh vrst dostopa je zavrnjen in ne ustvari članstva ponovno. Odstranitev samo neposrednega članstva ne odstrani preostale skupinske pravice. Ponovljen preklic že preklicanega neuporabljenega povabila je varen uspeh.

Povabilo zavrne potek časa, preklic, izguba trenutne upravljavske vloge izdajatelja, deaktivacija izdajatelja/prejemnika ali neaktiven/zaseben projekt. Čas velja kot UTC Unix sekunde in se preveri ob uporabi; za potek ni potreben cron. Pravice se preverjajo ob vsaki zahtevi. Ni dodatne serializacije sočasnih upravljavskih sprememb članstev prek jedra Kanboarda; to ostaja del preizkusa bodoče širše pogodbe za sodelovanje.

Napake so dejanske napake JSON-RPC, ne rezultati `success=true`. Odjemalec mora ločiti rezultat od objekta `error`, ohraniti čakajočo lokalno spremembo ter omogočiti varen ponovni poskus ali uporabnikov popravek. Sporočila dostopa so namenoma splošna; nepravilnemu prejemniku ne razkrivajo podatkov projekta.

## Odprte pogodbe

Prijava, registracija, sprejem povabila novega uporabnika in obnova računa so različni postopki. V tej različici ni javne registracijske metode ali vzporednega preverjanja gesel. Pred naslednjim korakom določimo OTP/2FA tok, omejevanje poskusov, potek in preklic napravnih žetonov, SMTP ter pravice gospodinjstva/financ.

Sinhronizacija bo potrebovala lokalno ustvarjene identifikatorje in ločeno preslikavo v Kanboard ID, revizije, trajen dnevnik sprememb, idempotenco, označene izbrise, konflikte in spremembe iz spletnega vmesnika. Ta vtičnik trenutno ne zajema teh sprememb, ne sinhronizira lokalne baze ter ne zagotavlja izvoza ali varnostnih kopij.
