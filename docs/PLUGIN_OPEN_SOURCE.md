# FamilyHub: priprava javnega izvornega repozitorija

Dogovor 7. oktobra 2026: pripraviti samostojen javni izvorni paket vtičnika, brez objave GitHub v tem koraku. Objava celotne zgodovine aplikacije ni del dovoljenja. Paket vsebuje samo pregledani `server/plugins/FamilyHub`; produkcijske konfiguracije, skrivnosti, izvozi, baze, priponke, varnostne kopije in testni računi niso javno gradivo.

## Licenca in odvisnosti

Kanboard uporablja [MIT](https://github.com/kanboard/kanboard/blob/main/LICENSE), preverjeno pri glavnem agentu 7. oktobra 2026. Uporabnik želi enako licenco za vtičnik. Po uporabnikovem navodilu je izdajatelj TriparNA; za novo kodo vtičnika uporabimo copyright **TriparNA – kooperativa za sonaravno življenje in razvoj tehnologij samooskrbe, z.o.o.** v `FamilyHub/LICENSE`. Obstoječa avtorska in dependency obvestila ostanejo ohranjena. Orodje izrecno zavrne oznake DRAFT/TODO in začasni `TriparNA contributors`; ne spreminja licence tuje kode.

Pregled trenutnega drevesa: vtičnik nima `vendor`, Composer manifesta ali kopiranih knjižnic tretjih oseb. Koda uporablja PHP/razširitve ter Kanboardove API-je. `NativeSmtpTransport` in `NativeVerifiedSmtp` uporabljata obstoječo Kanboardovo knjižnico Swift Mailer; v novi ZIP je ne kopiramo. Dejansko obvestilo v preizkusnem pripetem Kanboard 1.2.54 containerju je prebrano iz `/var/www/app/libs/swiftmailer/LICENSE`: MIT, copyright 2013–2016 Fabien Potencier. Ta dependency vir ni del vtičnikovega ZIP-a; njegovega copyrighta ne prenesemo na TriparNA. Zato njena licenca ni samostojno vključena kot bundled odvisnost. Izvedba je vezana na preizkušeni Kanboard 1.2.54; javni paket ni samostojna strežniška aplikacija. Če kasneje dodamo vendored kodo, pred vključitvijo preverimo njeno konkretno licenco in ohranimo zahtevana obvestila. Swift je starejša nevzdrževana upstream odvisnost; izbira licence tega ne odpravi.

Objavljeni naziv TriparNA na [triparna.si](https://triparna.si/) je »TriparNA – kooperativa za sonaravno življenje in razvoj tehnologij samooskrbe, z.o.o.«; javni kontakt je `zadruga@triparna.si`. Vir je neposredno prebran HTTPS HTML dne 7. oktobra 2026. Copyright sledi uporabnikovemu navodilu o izdajatelju; spletni vir potrjuje javni naziv in kontakt. To ni pravno zagotovilo glede pravic tuje kode.

## Ločitev in preverjanje

[Orodje za paket](../tools/plugin_release/README.md) vsebuje izrecni seznam datotek, zavrne neznane dodatke/simbolne povezave in nikoli ne prekopira Git zgodovine. Ne gre za isti stari široki deployment paketor, ki je rekurzivno zajel vse datoteke imenika. Pregledni izvorni ZIP in SHA256 nastaneta v ignorirani `build/release/`, ko je potrjena licenca na mestu.

Pred poznejšo javno objavo pregledamo vsak vključeni vir ter ZIP manifest, odstranimo sklice na zasebna okolja in vključimo dostopne pogodbe/navodila. Paketor zamenja razvojni README z [samostojnimi javnimi navodili](../tools/plugin_release/PUBLIC_README.md): zahteve, namestitev, konfiguracijske zastavice, capabilities, prijava/prvi račun, self-hosted spletna pot izbrisa, SMTP/FCM cron ter rollback in meje. Ta javni README ne potrebuje manjkajočih dokumentov aplikacijskega repozitorija. PHP izvor se kopira nespremenjen; zamenjava je izrecna samo za public README. To ne pomeni objave aplikacijskega repozitorija. Namestitveni/testni dokazi v zasebnem razvojnem repozitoriju ostanejo ločeni.

Novi javni repo pozneje ustvarimo z novo zgodovino in pregledanim prvim commitom. Orodje ne izvaja `git init`, `git push`, namestitve, migracije ali dostopa do produkcije. Ime/lastnik repozitorija in resnični javni URL še nista določena. Website naj do tedaj ne kaže lažnega gumba »Source« na neobstoječ repo.

## Končni lokalni paket 7. oktobra 2026

`build/releases/FamilyHub-0.6.0-source.zip`:61 datotek,101096B; SHA256 `433d45fbb8c7aa350e92beab812a7b9e7ffc1ed07bdae5d003fa1fce4e9624c0`. Vključenih je60 dovoljenih plugin datotek in ena izrecno pregledana javna kopija [pogodbe izbrisa](server/account-deletion-contract.md), v ZIP na `FamilyHub/docs/account-deletion-contract.md`. Razvojni README se zamenja s samostojnim public README; PHP in MIT LICENSE sta nespremenjeni kopiji. CRC in lokalne povezave v paketnih dokumentih so uspešno preverjeni.

Orodje ima10 pozitivnih/negativnih testov PASS. Javna pogodba je izrecno dovoljena datoteka, ne rekurzivna kopija dokumentacije; tudi zanjo veljajo prepoved symlinkov/traversal/sumljivih skrivnosti in omejitev velikosti. Novi repo še ni ustvarjen ali objavljen. Stari `server/scripts/package-plugin.py` ima hardcoded ime ZIP-a (zdaj0.6.0) in širok rekurzivni zajem, zato za to javno predajo ni uporabljen. Novi source ZIP že ima pravilno `FamilyHub/` strukturo za ločen repo ali pregledano ročno namestitev.
