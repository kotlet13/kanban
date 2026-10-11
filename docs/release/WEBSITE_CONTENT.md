# Javne vsebine za jivie.app

Aktualna vsebinska odločitev, 11. oktober 2026: prvo javno izdajo pripravljamo **brez AI**. Slovenski in angleški paket ustvarja `website/build_site.py`; vključuje predstavitev, `/privacy/`, `/help/` in `/delete-account/` ter njihove angleške različice. Obstoječa spletna objava in njeni dokazi so v [website/README.md](../../website/README.md). Ta nova lokalna uskladitev sama ni dokaz ponovne spletne objave ali javne objave mobilne aplikacije. Besedila ne pomenijo pravnega pregleda ali zaključenih obrazcev trgovin.

## Izdajatelj in kontakt

Uporabnik je kot izdajatelja navedel TriparNA. [Uradna stran](https://triparna.si/) navaja naziv **TriparNA – kooperativa za sonaravno življenje in razvoj tehnologij samooskrbe, z.o.o.**, sedež **Jablanica 18, 8294 Boštanj**. HTML je bil prebran neposredno prek HTTPS 7. oktobra 2026. Aktualni kontakt za Jivie je **support@jivie.app**; uporabnik je potrdil, da novi poštni predal deluje. Kontakt ne potrjuje upravljavskih vlog vseh samostojnih strežnikov ali imetništva vseh avtorskih pravic.

Javno besedilo: »Jivie izdaja TriparNA. Za vprašanja o aplikaciji in zasebnosti piši na [support@jivie.app](mailto:support@jivie.app). V sporočilo ne dodajaj gesel, kod za prijavo, API ključev ali varnostnih kopij osebnih podatkov.«

## /privacy/ — Podatki in zasebnost

Jivie je brezplačna aplikacija za osebno in skupno organizacijo. V osebnem načinu uporabljate opravila, načrte, nakupe in finance brez računa. Ti zapisi se hranijo na napravi. Aktivna lokalna baza nima dodatnega šifriranja v aplikaciji; zaščita je odvisna tudi od naprave in operacijskega sistema.

Za izbirno sinhronizacijo in sodelovanje povežete svoj združljivi strežnik Kanboard z vtičnikom FamilyHub. Prijava sama ne prenese osebnih vsebin. Zasebni prenos omogočite izrecno; skupne vsebine so vidne glede na pravice prostora. Strežnik obdeluje podatke računa, seje, članstva, poslane vsebine ter tehnične podatke za delovanje in varnost. Upravljavec vašega strežnika določa svojo konfiguracijo, dnevnike, ponudnike in varnostne kopije. TriparNA trenutno ne ponuja upravljanega gostovanja Jivie.

Lokalni opomniki uporabljajo sistem obvestil in dovoljenja naprave. Oddaljena obvestila uporabljajo Firebase Cloud Messaging ter zahtevajo združljivo nastavitev strežnika, izrecno registracijo naprave in dovoljenje operacijskega sistema. Kategorije brez shranjenih nastavitev imajo v trenutni izvedbi vključena push in obvestila v aplikaciji, e-pošto in zvok pa izključena; shranjene izbire, tudi izrecni izklopi, imajo prednost. Starejši strežniki imajo lahko drugačne privzete nastavitve. Obdelujejo se žetoni naprave, tehnični podatki SDK in generična sporočila z referencami; naša push sporočila ne vsebujejo naslovov opravil ali finančnih zneskov. Pri samostojnem gostovanju kanal ni samodejno na voljo. Android dostava je preverjena na testnem strežniku; povezava iOS APNs je še v pripravi. macOS uporablja center v aplikaciji, brez oddaljenega sistemskega push. Strežniška e-pošta potrebuje ločeno nastavitev in lahko uporablja preverjeni naslov za varnostne kode ali omogočena obvestila.

Prenosno kopijo `.vsakdan` ustvarite z geslom in shranite na izbrano lokacijo. Je šifrirana, vsebuje podprte zapise, ne vsebuje prijavnih sej ali priponk in ni popolna kopija strežnika. Pri pretvorbi obnovljenega strežniškega prostora v samostojno lokalno uporabo se prenosi med finančnimi računi in povezave plačil ne aktivirajo kot novi lokalni zapisi; izvirniki ostanejo v šifriranem obnovitvenem arhivu, finančni pregled pa je označen kot nepopoln. Napredni JSON izvoz je nešifriran. Sami izberete mesto shranjevanja in upravljate kopije, ki ste jih izvozili.

Odjava ne izbriše računa ali vseh lokalnih zapisov. Navodila za strežniški račun so na strani [Izbris računa](/delete-account/). Izbris pri strežniku ne more odpoklicati kopij, ki so jih člani že prej prenesli, ali vaših ločeno shranjenih izvozov. Za dnevnike in varnostne kopije svojega strežnika vprašajte njegovega upravljavca.

Statična spletna stran v svoji kodi ne uporablja analitike, oglaševalskih sledilnikov ali piškotkov. Pisave, slike in skripte se nalagajo s te strani. Infrastruktura gostovanja lahko za dostavo in zaščito strani obdeluje običajne tehnične podatke zahtev, na primer naslov IP. Vnos naslova strežnika na strani za izbris samo pripravi povezavo v brskalniku; stran ne preverja računa in ne pošilja prijavnih podatkov. Z odprtjem povezave se uporabnik poveže z izbranim strežnikom.

Za vprašanja o Jivie se obrnite na TriparNA prek zgornjega kontakta. Za dostop, popravek ali izbris podatkov na samostojnem strežniku je pristojen njegov upravljavec. Končna politika pred oddajo potrebuje potrjeno pravno podlago in upravljavske vloge, dejanske ponudnike, hrambo ter postopek uveljavljanja pravic; ti niso dokazani samo z izvorno kodo. Ne določamo izmišljenih rokov ali univerzalnih pravil za tuje strežnike.

## /help/ — Pomoč

**Začnite brez računa.** Jivie lahko uporabljate lokalno. Dodajte svoje prvo opravilo, načrt ali nakup. Za lokalno osebno uporabo strežnik ni potreben.

**Poiščite področja in prostor.** Na telefonu področja odpre levi zložljivi meni, na tablici spodnji zavihki, na namizju stranski meni. Načrti se imenujejo Opravila. Prostor izbere zgornji izbor; Vsi združi dovoljeno vsebino, pred dodajanjem pa je treba izbrati določen prostor. Člani, povabila in deljenje so v Nastavitvah prostora.

**Ohranite svoje podatke.** V aplikaciji odprite možnost za kopije in ustvarite šifrirano prenosno kopijo podprtih zapisov brez priponk in prijavnih sej. Geslo kopije shranite varno; brez njega kopije ne morete obnoviti. Kopija ni popolna kopija strežnika; pri samostojni obnovi veljajo zgornje omejitve financ. Pred menjavo naprave preverite obnovo. Sinhronizacija ni varnostna kopija.

**Povežite samostojni strežnik.** Potrebujete HTTPS naslov združljivega Kanboarda z omogočenim FamilyHub Native API in svoj uporabniški račun. Prvi račun oziroma povabilo pripravi upravljavec. Poštno povezavo odprite, ustvarite račun ali se prijavite in povabilo posebej sprejmite. Članstvo celotnega gospodinjstva ali organizacije odpre skupno vsebino, finance ter vse obstoječe in prihodnje projekte. Povabilo samo v projekt odpre le ta projekt, njegova opravila, dogodke, obvestila in finance, brez članstva nadrejenega prostora. V deljenem obsegu lahko člani ustvarjajo, urejajo, brišejo, upravljajo finance ter vabijo in upravljajo člane. Zaščita lastništva ostane; stare politike deljenja zahtevajo izrecen predogled prehoda. Kanboard brez vtičnika ne zagotavlja novih tokov sodelovanja. Povezovanje strežnika ne pomeni samodejne delitve osebnih podatkov.

**Obvestila.** Lokalni opomniki potrebujejo dovoljenje sistema in lokalno dostopen zapis. Center obvestil pri strežniškem delu se osveži ob povezavi oziroma sinhronizaciji. Privzeto vključen push sam ne registrira naprave. Označi vse kot prebrano velja za trenutni filter in ne zaključi opravil ali plačil. Oddaljeno telefonsko opozorilo ob zaprti aplikaciji pri poljubnem samostojnem strežniku ni zagotovljeno.

**Račun in dostop.** Pri težavi s prijavo preverite naslov strežnika in se obrnite na njegovega upravljavca. Obnova po e-pošti deluje samo, če strežnik to omogoča in je naslov preverjen. Za izbris glejte [Izbris računa](/delete-account/).

**Pišite nam.** Opišite težavo, različico aplikacije in operacijski sistem. Posnetek naj ne vsebuje zasebnih podatkov. Kontakt: [support@jivie.app](mailto:support@jivie.app).

## /delete-account/ — Izbris računa Jivie

Jivie v osebnem lokalnem načinu nima strežniškega računa. Spodnji postopek velja za račun na vašem samostojnem strežniku Kanboard z vtičnikom FamilyHub. Izdajatelj aplikacije nima dostopa do teh računov samo zato, ker uporabljate Jivie.

Pred izbrisom izvozite podatke, ki jih želite ohraniti, ter preverite posledice za skupne prostore. Na javni strani jivie.app ne vpisujte gesla, TOTP kode ali prijavne seje. Pot do dejanske potrditve mora odpreti stran **vašega strežnika** prek HTTPS. Preverite naslov pred prijavo.

FamilyHub uporablja relativno pot `index.php?controller=AccountDeletionController&action=index&plugin=FamilyHub` na istem osnovnem HTTPS naslovu Kanboarda. Tam se prijavite, pregledate vpliv, uredite lastništvo oziroma zahtevane odločitve in izbris posebej potrdite. Dosegljiva javna statična stran ne dokazuje, da ima poljuben uporabnikov strežnik nameščeno združljivo pot za izbris. Statika ne oddaja gesel ali sej na drug izvor, ne preverja računa ter ne prikazuje lažnega uspeha. Če upravljavec še nima združljive izvedbe, ga prosite za nadgradnjo in postopek izbrisa. Jivie uporablja isti račun kot Kanboard: izbris odstrani tudi njegovo prijavo v Kanboard. Odjava, deaktivacija ali odstranitev aplikacije niso izbris strežniškega računa.

Predogled pokaže prizadete osebne podatke, dostop, prispevke in lastništva. Urejanja v zapisih drugih ustvarjalcev lahko ostanejo kot del njihove skupne vsebine; polja nimajo popolne zgodovine posameznega avtorstva. Po izrecni ohranitvi ali prenosu skupnega prostora oziroma projekta lahko ostanejo že deljena finančna dejstva, tudi stroški, plačila in povračila. Osebne finančne projekcije in povezave do zasebnih računov se odstranijo po predogledu. Nekateri zgodovinski identifikatorji lahko ostanejo; to ni popolna anonimizacija. Skupni seznam ali finančni račun, ki ga potrebujejo drugi, lahko po izrecni izbiri ostane brez osebnih oznak; predogled pojasni ohranjeno stanje. Lastništvo in stare Kanboard vsebine z več prispevki lahko zahtevajo dodatne odločitve. Ne obljubljamo odpoklica lokalnih kopij/izvozov. Roki dnevnikov in varnostnih kopij niso lastnost statične strani in jih ne izmišljamo. Pravila morebitnega prihodnjega upravljanega gostovanja se določijo posebej.

## Meje pred prvo javno mobilno izdajo

- Pripravljeni lokalni paket in ZIP sama nista dokaz objave novih vsebin; dejansko objavo in dosegljivost vodi `website/README.md`.
- Javna zasebnost opisuje dejanske podatkovne poti prve izdaje. Ne vključuje razvojne zgodovine ali odstavka o odstranjenem AI (izrecna korekcija uporabnika 11. oktobra).
- Končno besedilo, kandidatka in obrazci trgovin morajo opisovati isto izvedbo, vključno s preostalimi prenosi za sodelovanje in FCM.
- Izbris v aplikaciji in spletni tok zahtevata funkcionalen test proti isti podprti pogodbi; avtorjev/inbox/audit/outbox podatkov ne imenujemo anonimnih brez preverjanja.
- Podpis, fizične naprave, trgovinske evidence in končni obrazci ostanejo odprti po [READINESS](READINESS.md).
