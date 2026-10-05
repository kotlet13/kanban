# Izbirna FCM dostava — pogodba 0.4.0

Izvedeno 5. oktobra 2026 in preverjeno s sintetičnimi napravami ter nadomestnim transportom. Resnična konfiguracija Firebase in zunanja dostava še nista preverjeni. Native envelope v1/actor ACL ostaneta nespremenjena. FamilyHub inbox je kanoničen; FCM je samo izbirni dostavni kanal. Firebase auth/baza/Analytics niso del tega adapterja.

- `push.state {}` → `{registration:{registered:bool,platform:"android"|"ios"|null,language:"sl"|"en"|null,revision:int,updatedAt:UTC|null}}`; samo trenutna bearer naprava, brez FCM žetona/hash/šifropisa.
- `push.register {token,platform,language,expectedRevision?:int,projectId?:string}` → isti odgovor. Token1..4096 printable ASCII bytes brez whitespace, platform Android/iOS, language sl/en. Veljavna konfiguracija obvezna; sicer503 `push_unavailable`. Enaka aktivna registracija (hash/platform/language/project) je idempotentna pred CAS: izgubljeni ACK se lahko ponovi z istim expectedRevision. projectId odjemalec vedno pošlje; neujemanje409 `push_project_mismatch`. Podan stale expectedRevision409 `push_conflict` s trenutno lastno registration metadata. Nove/rotirane registracije povečajo revision.
- `push.unregister {expectedRevision?:int}` → isti odgovor registered=false. Vedno dovoljen veljavni bearer tudi če provider izključen. Brez expectedRevision izrecno odstrani trenutno registracijo; client serializira registration/unregistration in zavrne stale ACKs. Če je registracija že izključena, je ponovitev idempotentna pred CAS; nove aktivne registracije star unregister ne odstrani (409 `push_conflict`).

Aktivni FCM token je globalno unikaten po SHA256 in pripada natanko eni durable accountId/deviceId. Poskus prevzema409 `push_token_bound` brez informacij o drugem računu. Explicit unregister sprosti token in poveča generation; rotacija in device revoke prekličeta stare jobs. Offline logout ne zagotovi takojšnjega preklica na strežniku: client shrani ciljano pending cleanup samo za staro identiteto, SDKdeleteToken/fresh token prepreči ponovno uporabo podB. Ni password/APIkey fallbacka. Po poteku/geslo/2FA/deactivation jobs ne dostavljajo.

Token je AES-256-GCM šifriran s posebnim base64 ključem32 bytes; AAD binds serverId/accountId/deviceId/revision. Konfiguracija/ključi zunaj javne mape, token nikoli log/export/response. Queue hrani samo inboxId/deviceId/generation/tokenHash; snapshot nikoli ne dostavi starega dogodka na kasneje vezan token/račun.

Payload data vsebuje natanko string `type=familyhub.inbox.v1`, `serverId`, `accountId`, `notificationId`. Notification naslov/body sta generična SL/EN, brez source naslova, zneskov, kategorije, scopeID, URL ali finance payload. Android uporablja channels `familyhub_push_silent_v1` / `familyhub_push_sound_v1`; APNs sounddefault le ob category sound=true. OS/user channel setting lahko utiša dostavo. Klik preveri identiteto in `inbox.open{id}`; snapshot ali pushdata ni ACL.

Push preference je neodvisna od inApp/email. Ob configoff ni queue/backfill starih dogodkov. Sender ponovno preveri active device/account/fingerprint/expiry, scope/finance ACL in currentcategory push/sound pred send. Device/scope lock skozi omejeno pošiljanje serializira revoke/rotation/policy change; že ponudniku sprejetega sporočila ni mogoče preklicati. Jobs imajo lease120s, expiry24h, največ5 poskusov, bounded backoff/Retry-After, cron največ 50 jobs/40 s dispatch budget, HTTP vsak10s. OAuth in send skupaj zahtevata največ 20 s rezerviranega HTTP časa. DB lock waits so omejeni na5s, vendar lahko podaljšajo celotni walltime procesa. Pri SQLite ostane write transaction zaklenjena med transportom; pri cronu upoštevaj začasen vpliv na urejanje. FCMaccepted ni dokaz OS prikaza in ambiguousACK lahko podvoji dostavo. Inbox event ostane idempotenten.

FCM HTTPv1 uporablja RS256 service-account JWT, scope `https://www.googleapis.com/auth/firebase.messaging`, fixed audience/token endpoint `https://oauth2.googleapis.com/token`; send je samo `https://fcm.googleapis.com/v1/projects/{projectId}/messages:send`. TLSverify obvezen, redirects izključeni, JSON/file/response size bounded. `UNREGISTERED` deaktivira samo isto generation; `INVALID_ARGUMENT` ne šteje samodejno za invalidtoken (lahko pomeni napačen payload). Malformed/auth/config errors ne razkrivajo provider body. OAuth token samo v pomnilniku enega cron procesa.

Primarni viri: [HTTPv1](https://firebase.google.com/docs/cloud-messaging/send/v1-api), [token lifecycle](https://firebase.google.com/docs/cloud-messaging/manage-tokens), [REST payload](https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages), [service-account OAuth](https://developers.google.com/identity/protocols/oauth2/service-account).


## Skupina ob kliku

`inbox.group {id:int,beforeId?:int,limit?:int}` → `{items,hasMore,nextBeforeId}`. Privzeta in največja stran je100. Rezultati so po ID padajoče, `nextBeforeId` je zadnji ID strani ob hasMore. Anchor mora pripadati trenutnemu uporabniku in imeti trenutno dovoljene scope/finance pravice. Vrne samo isto scope/groupKey/kind/category/audience skupino, največ anchor ID; kasnejši dogodki ne spremenijo zajetega klika. Vključi tudi push-only reference ob inApp=false. Za vsako odprtje klient uporabi `inbox.open`; ne konstruira tarč iz pushdata. Branje označi natanko zajete IDje. SQL poizvedba in strani so omejene; dolgih skupin ne nalaga neomejeno. Worker lahko združi stare pending jobs, a ne odstrani kanoničnih inbox dogodkov. Android tag in APNs collapse/thread ID sta stabilna neobčutljiva hash reference.

## Konfiguracija in namestitev

Javna capabilities `pushProjectId` je string samo ob native API in lokalno veljavni FCM konfiguraciji, sicer null. `features.externalPush` je takrat true; to ne dokazuje uspeha Googlove avtentikacije ali APNs. Klient primerja lastni Firebase projectId pred register; server ga preveri še enkrat. Neujemanje ponudnikovega SENDER_ID_MISMATCH konča job brez trditve o dostavi ali tihega prevzema žetona. FCM401 zavrže pomnilniški OAuth cache, naslednji poskus pripravi nov JWT.

Predloga konstant brez skrivnosti je [fcm-config.php.example](../../server/examples/fcm-config.php.example):

- `FAMILYHUB_ENABLE_NATIVE_API` in `FAMILYHUB_ENABLE_FCM`: boolean true samo po preverjeni namestitvi.
- `FAMILYHUB_FCM_PROJECT_ID`: isti Firebase project ID kot v service account in odjemalcu.
- `FAMILYHUB_FCM_SERVICE_ACCOUNT_FILE`: absolutna zasebna pot do JSON, največ64KiB, RSA najmanj2048bit.
- `FAMILYHUB_PUSH_KEY_BASE64`: ločen naključni32-byte ključ, strogo base64, samo na strežniku.
- `FAMILYHUB_PUBLIC_ROOT`: obstoječa dejanska javna mapa, npr. `/home/USER/public_html`.

Preverjanje realpath zavrne service JSON pod configured public root, Kanboard ROOT_DIR ali HTTP DOCUMENT_ROOT, tudi prek symlinka. CLI brez DOCUMENT_ROOT uporabi izrecni PUBLIC_ROOT in Kanboard root. To ni dokaz lokacije zunaj vseh virtualnih gostiteljev: skrbnik mora preveriti dodatne javne mape. Zasebna mapa naj ima700, datoteke600 in lastništvo, ki PHP HTTP/CLI dovoljuje branje. Ključ/JSON ne sodita v repo, ZIP ali javno mapo. Šifrirni ključ zavaruj skupaj z varnostno kopijo; ob njegovi menjavi naprave izrecno unregister/register. Restore brez pravega ključa ne zagotavlja dostave starih šifropisov.

Primer ustvarjanja šifrirnega ključa iz PHP (pot predhodno varno pripravi):

```sh
umask 077
php -r 'echo base64_encode(random_bytes(32)), PHP_EOL;' > /home/USER/private/familyhub-push.key
php /home/USER/public_html/kanboard/plugins/FamilyHub/cli/push-preflight.php
php /home/USER/public_html/kanboard/plugins/FamilyHub/cli/push.php --limit=20
```

Preflight ne pošilja omrežnih zahtev, izpiše samo configured/nativeEnabled/providerVerified/networkRequests in vrne neničelno izhodno kodo ob neveljavni konfiguraciji. Preveri PHP cURL/OpenSSL, pot in JSON/ključ/project skladnost. Ne preveri IAM, omogočenega FCM API, odhodnega HTTPS ali Apple dovoljenj. Cron naj teče vsako minuto z dejanskim PHP CLI gostovanja; zgornja namestitev ni izvedena na produkciji. HTTPS/OAuth/send endpointi so fiksni; JSON token_uri drugega izvora ni dovoljen. Ni subprocess/Composer/permanentnega workerja.

`server/scripts/test-push-http.py` pripravi samo sintetičen lokalni ključ in official Kanboard vsebnik z `--network none`, preveri konfiguriran HTTP register/CAS in ga odstrani. Integracija `push-integration.php` uporablja lokalni funkcijski zajemnik, preverja RS256 podpis in payload brez zunanjega providerja. Realno Android/iOS background/terminated dostavo, Firebase IAM/APNs in cPanel omrežje/cron preverimo šele po uporabnikovi nastavitvi.
