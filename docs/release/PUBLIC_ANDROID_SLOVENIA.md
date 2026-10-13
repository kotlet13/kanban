# Prva javna Android izdaja — Slovenija

13. oktober 2026 — uporabnik je po zaključku predstavitvenih sprememb naročil
pregled in nadaljevanje javne izdaje, z začetno državo Slovenijo.

## Izvedeno v Google Play Console

- Produkcijski kanal `4698247597354229997`, izdaja `1`.
- Iz knjižnice je dodan samo obstoječi sveženj **25 (1.7.0)**, naložen
  12. oktobra. Ni nove gradnje ali ponovnega prenosa AAB.
- Ime: **1.7.0 (25) – prva javna izdaja**. Slovenske in angleške opombe
  opisujejo začetno ponudbo organizatorja, Idejnika in izbirnega deljenja.
- Edina ciljna država je **Slovenija**; začetno uvajanje za vse v tem trgu.
- Predogled izdaje kaže **Pripravljeno za izdajo**, brez prikazanih napak;
  API24+, ciljni SDK36, ReTrace in izvorni simboli že pripeti.
- SL3391/en-US3475 znakov sta prebrana iz sveže odprtega obrazca in bajtno
  enaka zadnjemu `STORE_LISTINGS.json`, vključno s povezavo do FamilyHuba.
  Sedem telefonskih slik, vključno z odprto tablo, je ohranjenih.
- Končni Pregled objave vsebuje **11 sprememb**: izdajo, Slovenijo, oba
  trgovinska jezika, IARC, ciljno skupino18+, zasebnost, oglase, Data safety,
  zdravstveno izjavo in kategorijo Storilnost. Obstoječi pregledni dostop in
  druge deklaracije so navedeni kot informacije za pregled.
- Dejansko sta pritisnjena **Pošlji 11 sprememb v pregled** in potrditveni
  **Pošljite spremembe v pregled**. Rezultat: **Spremembe v pregledu**.

## Natančna meja statusa

Ob koncu še tečejo hitra samodejna Googlova preverjanja. Console izrecno pravi,
da bodo spremembe poslane v pregled, čim bodo ta uspešno dokončana.
Oddaja je potrjena, **odobritev in javna razpoložljivost še nista potrjeni**.
Upravljano objavljanje ostaja izklopljeno; izdaja je nastavljena za objavo po
odobritvi. Potrditveno okno navaja običajno do7dni, lahko tudi dlje.
Ni bilo novega sprejema pogodbe, spremembe podpisnega ključa ali dovoljenj.

Dokazi: `build/qa/public-release-slovenia-20261013/`:
`before-submission.txt`, `listing-check.json`, `submitted.txt`, `submitted.png`.

Android AAB SHA256 je ponovno preverjen:
`ef909cddea12b22ac3ec9a7c3805a7ed1a55e6cbe3c00368f767799953a27447`.
Izvor aplikacije, SDK/locks, dovoljenja, nameščeni strežniki, podatki in Mac
ostanejo nespremenjeni. Že opravljenega funkcionalnega testnega kroga nismo
ponavljali. Naslednji korak je izid Google preverjanj/pregleda; ob zahtevi
popraviti konkretno ugotovitev, ne samodejno izdelati nove Android gradnje.
