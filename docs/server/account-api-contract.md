# Račun in izbirni zasebni prostor — FamilyHub 0.5

Izvedena pogodba, preverjena 5. oktobra 2026 na SQLite, MySQL 8.4.11 in MariaDB 10.11.19. Native v1 envelope, HTTPS, bearer, CORS in obstoječi sync2 ostanejo. Additivna schema9; stare seje/zapisi/outbox se ne brišejo. Namestitev v produkcijo ni izvedena.

## Zasebni prostor

`personal.ensure {}` → `{scope}`. `scope.kind='personal'`, ime `Personal`, role owner. En trajen prostor na durable accountId; ponavljanje in sočasne naprave vrnejo isti UUID. Noben samodejni prenos osebne vsebine. Klient izrecno izbere vključitev in podatke. Članstvo/povabila/finance grants drugim so prepovedani tudi na strežniku. UUID/podtaknjen user/account/member ne omogoči dostopa. Izklop klienta ne izbriše strežniške kopije.

Project/task/event/shoppingList/shoppingItem uporabljajo sync2. Osebne finance uporabljajo **ločene finance.push/pull/audit** in tip `personalFinanceEntry`, dovoljen samo v personal prostoru. Payload vsebuje natanko `title,amountMinor,currency,kind,occurredAt,projectId,notes,createdAt,updatedAt`; kind income/expense, amountMinor pozitiven integer do9e12, EUR/USD/GBP/CHF, projectId UUID|null, title500 in notes50000 UTF16 units (UTF8 bound2000/200000 bytes), datumi UTC po obstoječi pogodbi. Ne ustvarjamo umetnega account/payer/transfer modela. Private finance ima owner-write policy, svoj sequence/accessRevision/audit/idempotent operations in ni del generic sync2. Projekt se ne izbriše pred odklopom task/event in personalFinanceEntry povezav (live_children z avtoriziranim serverRecord). Klient počaka na finance unlink ACK pred generic project delete; nova finance povezava mora pripadati živemu projektu istega personal prostora.

Besedilo mora biti veljaven UTF-8 brez NUL; klient pred vključitvijo preveri vse zapise in ničesar tiho ne krajša. Zasebni generic zapisi imajo enake lokalne meje title500/description-notes50000/quantity100 UTF16 units; payload do524288 bajtov, request do1MiB. Shared meje ostajajo nespremenjene. Pull strani ostajajo512KiB.

`scopes.list {includePersonal?:bool}` brez parametra ohrani samo household/project za stare klientove enum parserje. Novi klient izrecno pošlje includePersonal=true. `personal.ensure` je ločen novi klic.

Capabilities: `features.privateSync`, `features.personalFinanceEntry`, `scopeKinds` doda personal. Finance types v household/project ostanejo nespremenjeni.

## Prvi račun

`auth.enroll {code,username,password,displayName,deviceName}` → obstoječi session `{serverId,user,device,token}`. Email ni del enrollment; nastavi/preveri se po prijavi. Username3..64 ASCII po obstoječi pogodbi, password12..72 bytes, ostala polja obstoječe omejitve. Samo pred prvim FamilyHub accountom. Upravljavec Kanboarda izrecno izda bootstrap code na admin strani z POST+CSRF; refresh/GET ne izdaja ali ponavlja skrivnosti. Izdaja prekliče stare kode, rok15min, ena uspešna poraba. Koda se hrani samo kot hash; poraba/user/account/device so atomski. Novi račun app-user, nikoli admin. Obstoječi uporabniki se še naprej prijavijo z auth.login; ko katerikoli FamilyHub account obstaja, je enrollment zaprt. Ni javne registracije brez kode ali običajnega povabila.

Capabilities `features.accountEnrollment` pomeni trenutno mogoč prvi enrollment, ob Native API enable; po prvem računu false. Ne objavlja kode ali admin identitete. CLI je fallback za cPanel z zasebnim izhodom, ne zahteva SSH.

## E-pošta in obnova gesla

- `account.status {}` → `{email:string|null,emailVerified:bool,pendingEmail:string|null,resetAvailable:bool}`; trenutni bearer uporabnik.
- `account.email.request {email,language:'sl'|'en',password,otp?:string}` → `{accepted:true}`. Zahteva ponovno preverjanje gesla in ob aktivni2FA svež TOTP v isti zahtevi. Naslov do254 ASCII bytes; trenutno verificiran naslov ostane veljaven do potrditve novega. Nova izdaja prekliče prejšnjo pending verification kodo. Koda rok30min, namen in account ter pending email revision vezani.
- `account.email.confirm {token}` → `{verified:true}`. Trenutni bearer istega accounta, enkratna veljavna koda; zamenja naslov, shrani verified timestamp in prekliče stare reset kode. Prejšnji nepreverjen core users.email sam po sebi ni dokaz lastništva.
- `auth.reset.request {username,language:'sl'|'en'}` → `{accepted:true}` za obstoječ/neobstoječ/nepodprt/nepreverjen račun. Brez podatkov o obstoju ali naslovu. Pošilja samo na predhodno verificiran naslov. Rate limits username3/15min +IP20/15min; nima javnega email lookup.
- `auth.reset.confirm {token,password,otp?:string}` → `{reset:true}`. Enkratna koda rok15min, vezana accountu, verificiranemu naslovu in trenutnemu fingerprintu gesla/2FA. Password12..72 bytes. Aktivna TOTP je obvezna, replay zavrnjen; reset ne odstrani2FA in ne ustvari seje. Po uspehu prekliče vse bearer naprave/push generacije, stare reset kode in ponastavi failed-login counters. Za nadaljevanje je potrebna običajna prijava.

EmailVerification/passwordReset capabilities so false brez lastne SMTP konfiguracije in ločenega32-byte `FAMILYHUB_ACCOUNT_MAIL_KEY_BASE64`. Pozivi takrat503 `email_unavailable`; nikoli fakeaccepted za neobstoječ transport. Enotni napačni/porabljeni/expired token `account_token_invalid`, step-up `invalid_credentials`/`two_factor_required`, rate_limited kot obstoječa pogodba.

Trajna account-mail queue vsebuje samo šifrirano enkratno kodo in vezano identiteto, ne plaintext skrivnosti. Hash tokena je avtoritativen; transport pred pošiljanjem ponovno preveri veljavnost/rok/account/namen. SMTP pošilja navadno besedilo s kodo za vnos v aplikacijo, brez URL tokena ali avtomatskega deep-link write. Enkratna poraba in FIFO generation preprečita stare sprejete zahteve; ambiguous SMTP ACK lahko podvoji isto kodo. Inbox email preference ne blokira varnostne email kode. Ključi samo server config, zunaj repo/javnih map; capture testi samo .invalid.

Popolne šifrirane lokalne kopije/obnova so klientov tok; server ta obseg podpira z ločenimi private cursors in ACL. Strežniški sync ni backup. Ta pogodba ne vključuje oddaljenega cloud backup blob storage.
