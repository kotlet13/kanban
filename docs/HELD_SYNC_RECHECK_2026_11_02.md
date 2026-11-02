# Zadržane zahteve in ročni ponovni poskus — 2. november 2026

## Prijava in potrjena ugotovitev

Uporabnik po posodobitvi 1.11.11 poroča: poslovne čakajoče/sporne/zadržane
spremembe so 0, zadržane zahteve sinhronizacije 19; preverjanje sprememb je
uspešno, poskus uskladitve ni zabeležen. Klik »Uskladi zdaj« nima vidnega učinka.

V kodi je potrjena izpuščena pot: CollaborationPendingSyncSelection bere
crypto_outbox pending, medtem ko prikaz šteje tudi blocked ter karanteno povezanih
plačil. Ob nespremenjenem account.changes koordinator vrne unchanged, preden
preveri zadržane zahteve. To je reproducibilen vzrok tihega preskoka; brez
uporabnikove baze ni dokaz, zakaj je nastalo konkretnih 19 zadržanih zahtev.

## Obseg popravka

Izrecni ročni poskus začne z omejenim pregledom obstoječih zahtev prek njihovih
točnih potrdil. Ta korak samo bere izide; ne pošilja mutacij, ne preoblikuje
podpisanih teles, ne obnavlja računa in ne prestavlja vseh blokiranih zahtev nazaj
v pending. Naslednji običajni prenos lahko po vseh obstoječih preverjanjih
dostavi že predhodno odobrene namere. Redno preverjanje
brez sprememb ne ponavlja tega pregleda in ne odpira vseh prostorov.

Prikaz vključuje napredek med preverjanjem, čas poskusa ter varne razloge
preostalih ovir. Plačilna karantena ostane ločena. Po resničnem napredku z
veljavnim applied potrdilom mora običajni preverjeni prenos podatkov potrditi
popolnost, preden se lahko zapiše nov uspeh.

Dokončne zavrnitve v tem splošnem pregledu ne odstranjujejo blokiranega dela:
poseben obstoječi potek za izvorno operacijo še vedno obravnava njeno zavrnitev.
Tako ponovni zagon ne more prikazati zelene kljukice samo zato, ker je zavrnitev
izginila iz števca, obenem pa ne uvajamo nove trajne blokade brez poti razrešitve.

## Dokazi

Dokazi: build/qa/held-sync-20261102/. Produkcija in telefoni niso spremenjeni.

27 različnih novih lokalnih testov PASS: 20 jedro in 7 UI. Podagenti
GPT 6.1 Sol/high: jedro, UI in neodvisni pregled; root dodatno pregleda
izbiro domen, zaključevanje in izdajni paket. Uspešnih testov ne ponavljamo.

Jedro uporablja dejanski SQLite, produkcijski CryptoBusinessRouter in podpisano
vrsto, sintetični transport ter izrecni testni route guard za projekcijske poti.
Preverjeni so 19 neznanih izidov, nespremenjena vrsta, omejitev 64 zahtev/1 MiB,
nič mutacij v pregledu potrdil, poceni naslednji samodejni pregled, dejanski
prenos vsebine in financ po applied, izguba lease, napačna potrdila in vezave,
plačilna karantena, manjkajoči adapter, napredek v UI in neuspešna/verificirana
nadaljevanja. Zgodovinski uspeh ne more zaključiti novega neuspešnega poskusa.

UI testi pokrijejo slovenščino pri 360 px in angleščino pri 1100 px, en ročni
klik, stanje busy, onemogočen gumb med delom, varne podrobnosti, zavrnitev pri
ničelnem števcu in menjavo računa. To ni preizkus telefona, native kode ali
resničnega HTTP strežnika in ne potrjuje izvora uporabnikovih 19 zahtev.

Vmesne neuspešne fixture poskuse ohranijo dnevniki. Jedro R1 ni prevedeno
(manjkajoči import/ime števca), R2 10 PASS in en nepravi null-adapter fixture;
samo ta R3 PASS. Novi projekcijski fixture R1 neusklajena vrsta Map, R2 PASS;
5 negativnih vezav v svojem scenariju PASS1. Zadnji štirje novi scenariji R1
3 PASS in eno napačno fixture pričakovanje, samo ta R2 in nov zgodovinski
uspeh/konfliktni guard PASS1. UI prvih 6 PASS1, dodatni prehodni test R1
pričakovan presledek v obstoječem prevodu, R2 PASS. Ni četrtih poskusov.

## Nadaljevanje po potrjenem potrdilu

Applied rezultat in oznaka `held_receipt_refresh_v1` nastaneta v isti transakciji.
Oznaka sama ne podeli pravic in ne odpre obnovitvenega čarovnika. Po neuspešnem
preverjanju ostane in naslednji ročni poskus nadaljuje običajni preverjeni prenos.
Po nespremenjenem samodejnem preverjanju ne sproža ponavljajočih celotnih prenosov.
Zaključek zahteva točno zaporedje uspešnega celotnega prenosa, končne lokalne
kontrole ter CAS nad isto generacijo napredka. Napaka ohrani oznako in prejšnji
čas uspeha; novejše generacije se ne izbrišejo. Zgodovina se zapiše šele po
uspešnem prikazu končnega stanja.

Po običajnem prenosu se preostale ovire ponovno preberejo lokalno; razlog stare
že zaključene zahteve se ne pripiše drugi zahtevi. Neznanega izida ali pravega
manjkajočega dokazila ta popravek ne obide. Za konkreten preostali razlog
uporabnik lahko kopira varne podrobnosti po enem ročnem poskusu.


Končna skupna analiza spremenjenih Dart datotek: 0 napak, 0 opozoril,
31 predhodnih slogovnih info. Dve novi pripombi sta popravljeni.

Dodatni dve root zahtevani kontroli zaključka sta PASS1 brez ponavljanja starih:
prava SQLite transakcija z novejšo generacijo tik pred CAS ohrani novo oznako,
prejšnji čas in zgodovino; napaka agregatnega branja po potrjenem CAS obnovi
izvorno oznako ter prejšnji čas/zgodovino. Naslednji ročni poskus opravi celotno
preverjanje in zaključi oznako brez novega branja že potrjenega receipta.
