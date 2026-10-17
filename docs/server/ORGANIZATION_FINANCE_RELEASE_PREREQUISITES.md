# Pred javno izdajo organizacijskih financ

17. oktober 2026. To je seznam naslednjih izdajnih korakov za
[novo izvorno pogodbo](ORGANIZATION_FINANCE_API.md). Sedanje naročilo dovoljuje
izvorne spremembe in commit/push, **ne namestitve na gostovanje, javne objave
FamilyHuba ali oddaje v trgovine**. Produkcija in pregledni test1 po zadnjem
[dokazu](UPGRADE_0_15.md) še uporabljata0.15.0/shemo19 brez finance4.

1. Po zaključku odjemalca zamrznemo skupni izvor in pregledamo ciljne teste
   finance4 ter obstoječih financ, task-cost, linked-payment in lifecycle
   poti na SQLite, MariaDB10.11 in MySQL8.4. Preverimo arhiv/odvzem, izolacijo
   projektnega člana in nobeno dvojno knjižbo ali stanje. To je izvorna
   integracija; uspešen commit ne pomeni nameščene funkcije.
2. Za poznejšo konkretno odobreno izdajo določimo novo različico FamilyHuba
   in naredimo nov pregledani manifest/paket. Izrecni manifest že vsebuje
   novi `NativeOrganizationFinancePolicy.php`; stari paket0.15.0 in njegovi
   nadgradni pomagači ostanejo zamrznjeni. Ta razširitev ne potrebuje DDL;
   zahteva pa zamenjavo usklajene strežniške kode. Ne ponavljamo starega
   prehoda18→19 in ne uporabljamo njegovih starih kopij/pinov za nov poseg.
3. Pred dejansko zamenjavo strežniške kode pripravimo nov postopek za trenutno
   stanje vsakega gostovanja: svež bralni zajem identitete/verzije/sheme,
   izvorov, konfiguracij, ključev in delavcev; sveža polna zasebna kopija baze,
   DATA, konfiguracije in izvora; prava preverjena izolirana obnova točne
   kopije. Ohranimo prvotne uporabnike, gesla, članstva, račune, začetna
   stanja, stare knjižbe, ID-je, verzije operacij, ključe, SMTP/FCM in cron.
   Računov ali starih projektnih zapisov ne selimo/združujemo po imenu.
4. Najprej namestimo in preverimo pregledni test1, nato ločeno produkcijo,
   vsako po novi izrecni odobritvi. Pred odprtjem preverimo isti serverId,
   HTTPS200/enabled ter `organizationFinance`,
   `organizationFinanceContractVersions:[1]`, `financeContractVersions:[1,2,3]`
   in obstoječe finance3 zmožnosti. Usklajena aplikacija do tega trenutka novo
   funkcijo varno skrije oziroma pojasni potrebo po strežniški nadgradnji.
5. S testnima računoma potrdimo minimalni projektni accountChoices brez
   salda/začetnega stanja in še vedno zavrnjeni pull starša; račun v prazni
   organizaciji; splošni priliv/strošek; projektni strošek na računu starša;
   isto kanonično knjižbo v obeh pregledih ter pravilno enkratno stanje in
   valuto. Preverimo nesinhroniziran/offline otroški obseg: skupni pregled
   mora jasno ostati nepopoln. Enako velja za
   `organizationFinanceComplete:false`; vsak dovoljeni ID iz
   `organizationFinanceScopeIds` potrebuje svoj popoln posnetek s cursorjem vsaj vrednosti
   `organizationFinanceSequences[id]`, skriti
   prispevajoči projekt pa ne sme razkriti svojega ID-ja. Preizkus ne ustvarja sintetičnih produkcijskih
   povabil ali posega v resnična uporabniška članstva.
6. Po prvem projektnem sklicu preverimo zahtevano finančno pogodbo3 pri
   projektu **in staršu** ter varno zavrnitev zastarelega finance2 pull/audit/
   pisanja. Nato preverimo izgubljeni ACK in prejšnjo operacijo, arhiviranje
   računa/projekta, prepoved izbrisa živega računa in projektnega odklopa,
   ohranitev starega projektnega računa, obnovo odjemalske prenosne kopije ter
   menjavo/odvzem profila brez predpomnjenih tujih izbir.

Povrnitev po prvem v3 zapisu zahteva usklajen načrt: stari strežniški izvor
ne razume novih referenc in zahtevane pogodbe. Ne vrnemo samo starih PHP
preko že uporabljenih v3 podatkov in ne uvažamo stare kopije preko novih
živih knjižb. Izvorna razširitev ne zahteva novega gostovanja, novega crona,
SMTP/FCM pravic ali samodejne finančne migracije.

Šele po dokazani strežniški in odjemalski integraciji ter novi izrecni
odobritvi konkretne izdaje sledita nova gradnja aplikacije in morebitna
javna trgovinska oddaja. Interni Android kanal ostaja odložen; Apple posegi
niso vključeni v ta dokument. Zgornji koraki tukaj niso izvedeni.
