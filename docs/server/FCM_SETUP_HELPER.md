# Zasebna priprava FCM na cPanelu

[setup-cpanel-fcm.php](../../server/scripts/setup-cpanel-fcm.php) je ločen CLI pomočnik za obstoječi testni strežnik. Ne vključuje Kanboardovega bootstrapa, ne uporablja omrežja in ne spreminja baze, SMTP, crona, identitete strežnika ali mobilne različice. Ta dokument opisuje orodje, ne dokazuje namestitve ali dostave.

Privzeti poti sta `/home/tripar13/private/jivie-test` in `/home/tripar13/jivie-test.triparna.si`, projekt `jivie-e928a`. Izrecne možnosti `--base`, `--web-root`, `--project` omogočajo izolirane sintetične preizkuse. Za živo uporabo mora glavni agent najprej pregledati izvor pomočnika in aktualno konfiguracijo, vključno z vsemi datotekami, ki jih ta vključuje. Pomočnik teh datotek nikoli ne izvaja; ne more dokazati, da zunanja vključena datoteka dinamično ne definira dodatnih FCM konstant.

## Vhodne datoteke in varovala

Service-account JSON mora **že obstajati**, biti pod zasebno osnovno mapo in zunaj vseh javnih map. Pomočnik ga ne ustvari, kopira ali izpiše. Preveri omejeno velikost, obliko, isti projekt, pripadajoč naslov storitvenega računa, točen HTTPS OAuth naslov in zasebni RSA ključ najmanj 2048 bitov. To ne preveri IAM, veljavnosti pri Googlu ali dostave. PHP CLI potrebuje OpenSSL, cURL, tokenizer in `fsync`; spletni PHP mora kasneje z isto identiteto prebrati zasebne datoteke.

Osnovna mapa, njena nadrejena zasebna mapa ter `install` morajo že obstajati z lastnikovimi dovoljenji brez dostopa skupine/drugih (priporočeno 0700). Vhodne datoteke morajo biti redne, berljive, brez symlinkov ali dodatnih hardlinkov, istega lastnika in brez dovoljenj za skupino/druge (priporočeno 0600). Pomočnik novih datotek ne naredi javnih in obstoječih ne popravlja s širjenjem dovoljenj.

Upravljavec v cPanelu pregleda **vse** document roote vseh domen in pripravi zasebni JSON `public-roots.json`, na primer:

```json
{
  "version": 1,
  "reviewedAllDocumentRoots": true,
  "roots": [
    "/home/tripar13/public_html",
    "/home/tripar13/jivie-test.triparna.si",
    "/home/tripar13/OTHER_REVIEWED_DOCUMENT_ROOT"
  ]
}
```

Primer ni popoln seznam gostovanja. Vsak vnos mora obstajati in biti kanonična absolutna pot brez symlinkov; seznam mora vključiti izbrani spletni koren in `/home/tripar13/public_html` ter vse druge preverjene javne korene. Če katerikoli vsebuje zasebno osnovno mapo ali je v njej, se postopek ustavi. CLI ne more sam odkriti vseh virtualnih gostiteljev. SHA256 te pregledane datoteke se poda izrecno kot `--public-roots-sha`; sprememba seznama razveljavi prejšnjo pripravo.

Izrecno poda tudi SHA256 **trenutne pregledane** `familyhub-config.php` kot `--expected-feature-sha`. V izvoru pomočnika ni ugibanega ali starega strežniškega SHA. Sprejme natanko eno samostojno literalno definicijo `define('FAMILYHUB_ENABLE_FCM', false);`, ignorira komentirane primere in zavrne obstoječe dodatne FCM konstante. To definicijo nadomesti z zasebnim `require`; drugi bajti konfiguracije ostanejo enaki.

## Postopek

Uporabi potrjeni PHP CLI. V vseh štirih načinih podaj iste pregledane argumente. Spodnji SHA in pot do JSON so označbe, ki jih mora izvajalec nadomestiti z dejanskimi pregledanimi vrednostmi; skrivnosti niso argumenti:

```sh
/opt/alt/php84/usr/bin/php /PRIVATE/PATH/setup-cpanel-fcm.php --check \
  --credential=/home/tripar13/private/jivie-test/SERVICE_ACCOUNT.json \
  --public-roots-file=/home/tripar13/private/jivie-test/public-roots.json \
  --public-roots-sha=REVIEWED_INVENTORY_SHA256 \
  --expected-feature-sha=REVIEWED_CURRENT_FEATURE_SHA256
```

1. `--check` samo bere. Pred pripravo ne ustvari imenika, ključa ali zaklepa; po pripravi preveri tudi zasebne artefakte.
2. `--prepare` ustvari zasebni `familyhub-push.key` (naključnih 32 bajtov v base64), `fcm-config.php` ter mapo `install/fcm-setup` s planom, originalom, kandidatom, zaklepom in kontrolnimi vsotami. Vse nove datoteke imajo 0600, mapa 0700. FCM ostane izključen. Ključ je ločen od `account-mail.key`; obstoječega tujega cilja pomočnik ne prepiše.
3. Izvedi `php -l` nad `fcm-config.php` in `install/fcm-setup/familyhub-config.candidate.php`. Pomočnik oba tudi razčleni s tokenizerjem brez izvajanja.
4. `--activate` preveri iste vhode, njihove SHA, vse artefakte in aktualno konfiguracijo ter jo zamenja z atomarnim `rename`. Ohranjen izvirnik omogoča povrnitev. Aktivacija ne pošlje sporočila in ne namesti push crona.
5. Po ločenem pregledu dejanske nastavitve uporabi obstoječi `push-preflight.php` iz vtičnika. Preflight ne uporablja omrežja in `providerVerified=false` ni dokaz IAM ali fizične dostave. Fizični Android preizkus in cron vodita ločena [navodila obvestil](../NOTIFICATION_SETUP.md).

`--rollback` po enakih argumentih povrne točne bajte izvirnika, samo če trenutna konfiguracija še ustreza izvirniku ali pripravljenemu kandidatu. Ključ in konfiguracija ostaneta zasebno ohranjena, da kasnejša ponovitev ne zamenja šifrirnega ključa. Povrnitev ne potrebuje vsebine service-account JSON ali push ključa; deluje tudi, če sta bila po vklopu odstranjena ali poškodovana. Preverjeni inventar poti, prvotni SHA, plan in izvirnik so še vedno obvezni.

## Ponovitev, prekinitev in omejitve

Ponovitev priprave/vklopa/povrnitve je varna; aktivno stanje določa dejanski SHA `familyhub-config.php`, zato izgubljen odgovor po uspešnem `rename` ne povzroči novega ključa. Delno pripravo z veljavnim planom in prvotno konfiguracijo lahko `--prepare` dopolni, ohrani že ustvarjeni veljavni ključ in ne spreminja vklopa. Po dokončani pripravi spremenjen ključ, kandidat, konfiguracija ali poverilnica ustavi preverjanje/vklop.

Če prekinitev pusti mapo brez veljavnega plana ali poškodovano delno datoteko, se pomočnik ustavi za zasebni pregled. Artefaktov ne briše in ne ugiba novega ključa. Spremenjene izvirne/aktivne konfiguracije ne prepiše, tudi med povrnitvijo. Za ponovitev po namerni spremembi konfiguracije je potreben nov pregled; starega SHA se ne rahlja.

Pomočnik uporablja lasten zaklep in `flock` nad konfiguracijo ter ponovno primerjavo tik pred zamenjavo. Drugi urejevalci morajo sodelovati z zaklepanjem; PHP nima atomarne datotečne CAS zaščite pred zunanjim procesom, ki ignorira zaklepe. Med aktivacijo/povrnitvijo zato ne urejaj iste konfiguracije drugje. Zapisi datotek se `fsync`-ajo; to ni dokaz trajnosti celotnega datotečnega sistema ob izpadu napajanja. Lastništvo/dovoljenja CLI ne dokazujejo dejanske spletne PHP berljivosti ali HTTP konfiguracije gostovanja.

## Izolirani sintetični testi

[cpanel-fcm-setup.php](../../server/tests/cpanel-fcm-setup.php) ustvari samo izmišljeno storitveno identiteto in začasne RSA ključe ter uporablja začasne mape. Ne vključuje aplikacije in nima dostopa do živih skrivnosti ali baze. Lokalni testni image dopolni obstoječi Kanboard image samo s tokenizerjem (brez sprememb aplikacijskih odvisnosti); sami preizkusi se izvajajo brez omrežja:

```sh
docker build -t familyhub-fcm-setup-test -f - . <<'DOCKERFILE'
FROM kanboard/kanboard:v1.2.54
RUN apk add --no-cache php84-tokenizer
ENTRYPOINT ["php"]
DOCKERFILE

docker run --rm --network none \
  -v "$PWD/server:/work:ro" familyhub-fcm-setup-test \
  /work/tests/cpanel-fcm-setup.php /work/scripts/setup-cpanel-fcm.php
```

Testi preverjajo nespremenjen `--check`, ločeno pripravo/vklop, točno povrnitev, ponovitve, obnovo delne priprave, zavrnitev spremenjenih vhodov, napačno obliko/projekt/ključ, pravice datotek, symlinke/hardlinke, dodatne javne korene in odsotnost izpisa skrivnosti. Rezultat ni dokaz Google avtentikacije ali dostave na napravo.
