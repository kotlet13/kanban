# Dokaz podpisnika pravil zapisov — 1. november 2026

## Ugotovitev

Uporabnik po posodobitvi posreduje `recordPolicy / directory_proof_pending`
z uro 2026-11-01T08:29:08.194930Z. Slika kaže splošnejši zapis. V kodi je
potrjena pot `ensureRecordPolicy → recordPolicies.ensure → active →
_verifyHeaders → _authorization → directoryAt`, ki je privzeto zahtevala
lokalni dokaz. Manjkajoč lokalni podpisnikov imenik je pred omrežnim branjem
sprožil točno to izjemo; to je reproducirano s podpisanim lokalnim primerom.
To ni dokaz, da uporabnik nima pravic ali potrebuje nove ključe.

## Sprememba

Samo v `_authorization` pravil zapisov `headAt` in `directoryAt` zdaj dovolita
obstoječo spletno preverbo (`online: true`). Poizvedba ostaja vezana na točen
prostor, zgodovinsko glavo članstva in podpisnikov imenik. Podpisi, lastništvo,
revizija dostopa, veriga identitete, znani varni sidrni podatki in varovala seje
ostanejo. Globalne privzete nastavitve niso spremenjene; ni nepreverjenega
zaupanja ali obhoda pravic. Strežniška sprememba ni potrebna za to pot.

Preverjeno dokazilo se lahko shrani pred kasnejšo zavrnitvijo ponarejenega
podpisa pravil. To samo po sebi ne aktivira pravil, članstva ali vrne ključa
zapisa. Lokalni testi ne dokazujejo vseh vej predpomnilnika/promocije.

Prikaz diagnostike in kopiranje zdaj uporabljata isti zamrznjeni očiščeni
posnetek ob odprtju okna. Za novejši poskus se okno ponovno odpre. Ob menjavi
računa/naprave ostane izvoz blokiran in okno se zapre. Dodana kratka SL/EN
razlaga manjkajočega dokazila; korak je »Preverjanje pravil za zapise«.

## Preverjanje

11 različnih novih lokalnih kontrol PASS, uspešnih testov nismo ponavljali:

- Podpisani primer prejemnika: pridobitev dveh strani zgodovinskega imenika
  do znanega novejšega varnega sidra, preverjanje podpisov priprave/aktivacije/
  vsebine in AEAD odklep ključa istega zapisa. Ponovno branje istega zapisa
  ne doda omrežnih poizvedb za imenik (ostaneta dve).
- Ponarejen podpis imenika, imenik drugega računa, napačen podpis priprave,
  aktivacije ali posameznega zapisa: vsak zavrnjen, varna identiteta ohranjena.
- Menjava seje med branjem: zavrnjena brez spremembe varne identitete.
- UI: sprememba/brisanje napake v ozadju, posodobitev tik pred klikom, kopiranje
  istega prikazanega zapisa, ponovno odprtje z novimi podatki; varovalo menjave
  računa pred naslednjim izrisom; slovenska in angleška razlaga.

Poskusi:
1. Primer prejemnika: napačen testni v4 ID namesto izpeljanega ID zapisa (FAIL1).
2. Popravljen testni model: pričakovani RED2 z dejansko izjemo
   `SessionCryptoAccess.directoryAt: directory_proof_pending`.
3. Po spremembi dveh klicev: prejemnik PASS3 in pet negativnih kontrol PASS1.
   Kontrola menjave seje je varno odpovedala z drugo, zgodnejšo izjemo od
   pričakovane; popravljen samo matcher, ta kontrola izolirano PASS2.
4. Vse štiri nove UI kontrole PASS1. Nobenega ponavljanja šestih že uspešnih
   podatkovnih kontrol, nobenega ponavljanja starih poslovnih testov.

Analiza štirih spremenjenih/novih datotek: 0 napak, 0 opozoril, ena obstoječa
slogovna informacija (curly braces) v baseline. Diff check uspešen. Neodvisen
Sol6.1/high pregled obeh sprememb brez blokirajočih ugotovitev.

Dokazi: `build/qa/record-policy-online-proof-20261101/` in
`build/qa/record-policy-proof-20261101/`.

## Omejitve in namestitev

Testi uporabljajo pravi reducer imenika, podpise, identitetno shrambo,
preverjanje lastništva in AEAD. Priznana zgodovina prostora in dostop do
njegovega ključa sta testni meji; transport je sintetičen, baza v pomnilniku.
Ni novega celotnega podpisanega HTTP, telefonskega ali produkcijskega testa.
Omrežna nedosegljivost, zavrnjen dostop, ponarejena veriga ali manjkajoča
zgodovina še vedno ustavijo postopek. Uspeha na dejanskem A33 še ne trdimo.

Telefoni, strežnik, računi, povabila in uporabniški podatki niso bili spremenjeni.
Nadaljevanje je običajna posodobitev iste aplikacije; brez ponovne prijave,
brisa, novega povabila ali novih ključev. Android paket se pripravi posebej;
priprava paketa ni javna objava.
