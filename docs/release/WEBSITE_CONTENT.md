# Javne vsebine za jivie.app

Osnutek za statični paket, 7. oktober 2026. Paket se pripravi lokalno; objava na cPanel in preverjanje javnih naslovov sta ločena koraka. Predlagane poti: `/privacy/`, `/help/`, `/delete-account/`. Nakup domene je uporabnikov podatek, ne dokaz delujočega DNS/TLS ali objave. Besedila ne pomenijo pravnega pregleda ali zaključenih obrazcev trgovin.

## Izdajatelj in kontakt

Uporabnik je kot izdajatelja navedel TriparNA. [Uradna stran](https://triparna.si/) javno navaja naziv **TriparNA – kooperativa za sonaravno življenje in razvoj tehnologij samooskrbe, z.o.o.**, sedež **Jablanica 18, 8294 Boštanj** in kontakt **zadruga@triparna.si**. HTML je bil prebran neposredno prek HTTPS 7. oktobra 2026; spletno iskalno orodje strani ni moglo odpreti. Javna objava kontakta ne potrjuje upravljavskih vlog vseh strežnikov ali imetništva vseh avtorskih pravic.

Uporabno javno besedilo: »Jivie izdaja TriparNA. Za vprašanja o aplikaciji in zasebnosti pišite na [zadruga@triparna.si](mailto:zadruga@triparna.si). V sporočilo ne dodajajte gesel, kod za prijavo, API ključev ali varnostnih kopij osebnih podatkov.«

## /privacy/ — Podatki in zasebnost

Jivie je brezplačna aplikacija za osebno in skupno organizacijo. V osebnem načinu uporabljate opravila, načrte, nakupe in finance brez računa. Ti zapisi se hranijo na napravi. Aktivna lokalna baza nima dodatnega šifriranja v aplikaciji; zaščita je odvisna tudi od naprave in operacijskega sistema.

Za izbirno sinhronizacijo in sodelovanje povežete svoj združljivi strežnik Kanboard z vtičnikom FamilyHub. Prijava sama ne prenese osebnih vsebin. Zasebni prenos omogočite izrecno; skupne vsebine so vidne glede na pravice prostora. Strežnik obdeluje podatke računa, seje, članstva, poslane vsebine ter tehnične podatke za delovanje in varnost. Upravljavec vašega strežnika določa svojo konfiguracijo, dnevnike, ponudnike in varnostne kopije. Jivie trenutno ne ponuja upravljanega gostovanja.

Lokalni opomniki uporabljajo sistem naprave. Oddaljeni kanal Firebase Cloud Messaging oziroma APNs še ni nastavljen za javno izdajo; pri samostojnem gostovanju ni samodejno na voljo. Osnovna uporaba ne zahteva tega kanala. Morebitna strežniška e-pošta zahteva ločeno nastavitev upravljavca in lahko uporablja preverjeni e-poštni naslov za varnostne kode ali omogočena obvestila.

AI je izbirna napredna možnost v starejših Kanboard poteh. Če jo posebej nastavite in pošljete vsebino, se sporočilo ter izrecno dovoljeni projektni kontekst pošljeta k OpenAI z vašim API ključem. Lokalna zgodovina ostane v profilu. Osebni organizator deluje brez AI.

Prenosno kopijo `.vsakdan` ustvarite z geslom in shranite na izbrano lokacijo. Je šifrirana, ne vsebuje prijavnih sej ali priponk in ni popolna kopija strežnika. Stari JSON izvoz je nešifriran. Sami izberete mesto shranjevanja in upravljate kopije, ki ste jih izvozili.

Odjava ne izbriše računa ali vseh lokalnih zapisov. Navodila za strežniški račun so na strani [Izbris računa](/delete-account/). Izbris pri strežniku ne more odpoklicati kopij, ki so jih člani že prej prenesli, ali vaših ločeno shranjenih izvozov. Za dnevnike in varnostne kopije svojega strežnika vprašajte njegovega upravljavca.

Za vprašanja o Jivie se obrnite na TriparNA prek zgornjega kontakta. Za dostop, popravek ali izbris podatkov na samostojnem strežniku je pristojen njegov upravljavec. Končna politika pred oddajo potrebuje potrjeno pravno podlago in upravljavske vloge, dejanske ponudnike, hrambo ter postopek uveljavljanja pravic; ti niso dokazani samo z izvorno kodo. Ne določamo izmišljenih rokov ali univerzalnih pravil za tuje strežnike.

## /help/ — Pomoč

**Začnite brez računa.** Jivie lahko uporabljate lokalno. Dodajte svoje prvo opravilo, načrt ali nakup. Za lokalno osebno uporabo strežnik ni potreben.

**Ohranite svoje podatke.** V aplikaciji odprite možnost za kopije in ustvarite šifrirano prenosno kopijo. Geslo kopije shranite varno; brez njega kopije ne morete obnoviti. Pred menjavo naprave preverite obnovo. Sinhronizacija ni varnostna kopija.

**Povežite samostojni strežnik.** Potrebujete HTTPS naslov združljivega Kanboarda z omogočenim FamilyHub Native API in svoj uporabniški račun. Prvi račun oziroma povabilo pripravi upravljavec. Kanboard brez vtičnika ne zagotavlja novih tokov sodelovanja. Povezovanje strežnika ne pomeni samodejne delitve osebnih podatkov.

**Obvestila.** Lokalni opomniki potrebujejo dovoljenje sistema in lokalno dostopen zapis. Center obvestil pri strežniškem delu se osveži ob povezavi oziroma sinhronizaciji. Oddaljeno telefonsko opozorilo ob zaprti aplikaciji pri poljubnem samostojnem strežniku ni zagotovljeno.

**Račun in dostop.** Pri težavi s prijavo preverite naslov strežnika in se obrnite na njegovega upravljavca. Obnova po e-pošti deluje samo, če strežnik to omogoča in je naslov preverjen. Za izbris glejte [Izbris računa](/delete-account/).

**Pišite nam.** Opišite težavo, različico aplikacije in operacijski sistem. Posnetek naj ne vsebuje zasebnih podatkov. Kontakt: [zadruga@triparna.si](mailto:zadruga@triparna.si).

## /delete-account/ — Izbris računa Jivie

Jivie v osebnem lokalnem načinu nima strežniškega računa. Spodnji postopek velja za račun na vašem samostojnem strežniku Kanboard z vtičnikom FamilyHub. Izdajatelj aplikacije nima dostopa do teh računov samo zato, ker uporabljate Jivie.

Pred izbrisom izvozite podatke, ki jih želite ohraniti, ter preverite posledice za skupne prostore. Na javni strani jivie.app ne vpisujte gesla, TOTP kode ali prijavne seje. Pot do dejanske potrditve mora odpreti stran **vašega strežnika** prek HTTPS. Preverite naslov pred prijavo.

FamilyHub uporablja relativno pot `index.php?controller=AccountDeletionController&action=index&plugin=FamilyHub` na istem osnovnem HTTPS naslovu Kanboarda. Tam se prijavite, pregledate vpliv, uredite lastništvo oziroma zahtevane odločitve in izbris posebej potrdite. Trenutni osnutek in lokalni paket sama nista dokaz nameščene javne poti. Statika ne oddaja gesel ali sej na drug izvor, ne preverja računa ter ne prikazuje lažnega uspeha. Če upravljavec še nima združljive izvedbe, ga prosite za nadgradnjo in postopek izbrisa. Odjava, deaktivacija ali odstranitev aplikacije niso izbris strežniškega računa.

Predogled pokaže odstranjeni osebni prostor/dostop in prispevke glede na prvotnega ustvarjalca. Urejanja v zapisih drugih ustvarjalcev lahko ostanejo kot del njihove skupne vsebine; polja nimajo popolne zgodovine posameznega avtorstva. Skupno lastništvo zahteva prenos ali dovoljen izbris lastnega prostora. Strukture za podatke drugih članov zahtevajo izrecno odločitev; stare Kanboard vsebine z več prispevki imajo posebne omejitve za razrešitev. Ne obljubljamo odpoklica lokalnih kopij/izvozov. Roki dnevnikov in varnostnih kopij niso lastnost statične strani in jih ne izmišljamo. Pravila morebitnega prihodnjega upravljanega gostovanja se določijo posebej.

## Meje pred objavo

- Statični ZIP ni objavljena politika, delujoča spletna zahteva ali dokaz dosegljivosti URL-ja.
- Povezave na strani je treba dodati odjemalcu; končno besedilo mora ustrezati kandidatki za trgovino.
- Izbris v aplikaciji in spletni tok zahtevata funkcionalen test proti isti podprti pogodbi; avtorjev/inbox/audit/outbox podatkov ne imenujemo anonimnih brez preverjanja.
- Podpis, fizične naprave, trgovinske evidence in končni obrazci ostanejo odprti po [READINESS](READINESS.md).
