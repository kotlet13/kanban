# Privzeti zvok — Android1.9.1(29) / FamilyHub0.14.1

15. oktober 2026. Uporabnik zahteva privzeto vključen zvok in izrecno ohranitev vseh obstoječih nastavitev. Apple/TestFlight ostane odložen; Android izdaja je izključno javna.

## Vedenje in ohranitev

Nove oziroma manjkajoče lokalne in skupne nastavitve zvoka uporabijo `true`, tudi pri opomnikih in Idejniku. Skupni opomnik brez lokalno prenesene preference uporablja isti privzeti zvok. Strežnik ponovno preveri trenutno nastavitev pred dostavo.

Vsaka shranjena vrednost `sound=false` ali `sound=true` ostane nespremenjena, vključno s starimi celotnimi JSON nastavitvami, ki so materializirale stari privzeti izklop. Njihovega izvora ni mogoče zanesljivo ločiti. Ni migracije, backfilla ali prepisovanja obstoječih nastavitev. Manjkajoče polje deduje novi privzeti zvok. Lokalni opt-in, sistemska dovoljenja in nastavitev Androidovega kanala ostanejo veljavni.

## Ciljno preverjanje

- 51 Flutter testov PASS: nove/manjkajoče nastavitve, lokalne legacy/v2 in skupne shranjene vrednosti, ohranitev izklopa ob spremembi drugega kanala, načrtovalnik in dejanski native parametri ter UI brez zapisovanja ob branju.
- Analiza spremenjenih datotek brez ugotovitev; celotna analiza ima istih10 predhodnih info v nepovezanih izdajnih pripomočkih, brez napak/opozoril.
- Strežniška ciljna integracija180 kontrol PASS na MariaDB10.11.19/schema18: kategorije, shranjeni izklopi, branje brez nastajanja preference vrstic, sveže preverjanje pred dostavo, Android/APNs parametri. Sintetični podatki; brez pošiljanja uporabnikom.

## Izdajni status

Funkcionalni popravek **a51f98e** je poslan na main. Iz istega zamrznjenega izvora je nastala natanko ena podpisana **Android1.9.1(29)**,80.226.180B, SHA256 `42cb54088ead068d9c2e21ad5e267d10a48af8a31483d0c40c7367d2e8fbd475`.421 izdajnih vhodov/308 skupnih runtime; proti28 so spremenjene štiri Dart datoteke in različica. Trije locks, konfiguracije, native vhodi, podpis in Flutter engine v vseh treh ABI ostanejo isti.51 ciljnih testov je uspešnih tudi v tem izoliranem izvoru;23 izdajnih+7Firebase, bundletool/CRC/16KiB,8dovoljenj,min24/target36/non-debuggable PASS. [Lokalni dokazi](../../build/qa/default-sound-release-20261015/local-release-evidence.json).

AAB29 je dejansko naložen in dokončno oddan v javno posodobitev v isti TaknDevs/Jivie produkcijski kanal4698247597354229997.29 vključena/28 izključena,100%,obstoječa Slovenija,SL/en-US opombe,0 izgubljenih/novih naprav. Oddana je natanko1sprememba; galerije in opisi niso spremenjeni. Console potrjuje **»Spremembe v pregledu«**, hitra preverjanja še tečejo. Upravljano objavljanje ostane izklopljeno: samodejna objava po odobritvi. **Odobritev in javna29 še nista potrjeni**; javna28 ostane do takrat. Interni kanal ni bil uporabljen. [Dokaz oddaje](../../build/qa/default-sound-release-20261015/android29-submitted.png).

## FamilyHub in živi namestitvi

Javni [FamilyHubv0.14.1](https://github.com/kotlet13/kanban_family_hub/tree/v0.14.1) je objavljen iz59119dc. ZIP216.711B/SHA256 `8d756b75e1b4ce94cc24aeb97d1c913f872052dd50fcdb15baf2886cfb8d03f6`,102 vnosa;90PHP bajtno enakih pregledanemu izvoru.102. vnos je obstoječi NOTICE iz nespremenjenega dovoljenega manifesta; stari0.14.0 ZIP ga ni vseboval. Stari ZIP-i/tagi,MIT/NOTICE/config.example ostanejo nespremenjeni. Ponovna gradnja bajtno identična, javni HTTPS200/hash/CRC PASS.

Produkcija in pregledni test1 sta **dejansko FamilyHub0.14.1/schema18**, brez migracije. [Ozek pomočnik](../../server/scripts/sound-default-0.14.1/README.md) zamenja samo dva modela in Plugin.php, po preverjeni zasebni kopiji vseh101 prej nameščenih datotek. Gostovani README/pogodbe zato ohranijo prejšnje bajte; javni ZIP vsebuje nove javne opise. Kratke READ ključavnice zagotavljajo nespremenjene preference med preverjanjem in tremi atomarnimi zamenjavami datotek; brez SQL zapisov, DDL, spreminjanja cronov ali zagona aplikacije/delavcev.

| Namestitev | Zaključeno UTC15.okt | Tabele/vrstice | Računi/naprave | Ohranjene preference |
|---|---|---|---|---|
| Produkcija |06:59:17|93/376|3/4|21, vsi izvirni bajti |
| Test1 |07:01:12|93/337|3/9|1, vsi izvirni bajti |

Oba checkpointa potrjujeta `code-patch-complete`, vse table counts/CREATE, identitete/gesla/naprave, config/ključe/cron/data/core/mode ter nespremenjene surove preference. Izvirna vira in prejšnje podatkovne kopije ostanejo zasebni. Ločeni sveži javni Native capabilitiesPOST vrneta HTTPS200/isto serverId/enabled/push2. Test2 ostane nespremenjen. Sintetični pomočnikov preizkus na MariaDB10.11.19/schema18 uspe, tudi4 negativna varovala: spremenjen staged hash, stari vir, cron in ponovitev apply. Prva dva produkcijska check poskusa sta varno zavrnila manjkajoči pins.json med prenosom; nobene spremembe vira/baze pred uspešnim check3/apply.

Fizični zvok novega Android29 ni preverjen; obstoječi shranjeni izklopi tudi po posodobitvi ostanejo izklopljeni. Apple/TestFlight,Windows/Linux in nove slike niso del tega popravka.

Svež read-only Google Play potrdi prejšnjo **1.9.0(28) Na voljo v Googlu Play**, datum15.okt07:58,100%,1država/regija. Prejšnji zapis »v pregledu« je zgodovina. Nova posodobitev uporablja isto galerijo in obstoječo Slovenijo; interni kanal ostane neaktiven.
