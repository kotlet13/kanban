# FamilyHub na spletni strani in v opisu Google Play

13. oktober 2026 — po uporabnikovi ponovni javni objavi repozitorija in potrditvi
modela brezplačne aplikacije/vtičnika je povezava do FamilyHuba dejansko dodana
na jivie.app, slovenski in angleški opis Google Play pa sta shranjena kot osnutek.

## Besedilo in povezave

- SL/EN domači strani imata razdelek `#familyhub`: »Tvoji podatki. Tvoja izbira.«
  oziroma »Your data. Your choice.«, lokalna uporaba, brezplačen odprtokodni
  vtičnik FamilyHub za lastni Kanboard ter gumb do
  <https://github.com/kotlet13/kanban_family_hub>.
- Navedena je MIT licenca vtičnika. Uporabnik skrbi za strežnik in stroške
  gostovanja. Besedilo ne označuje celotne aplikacije kot odprtokodne.
- SL/EN pomoč v razdelku `#server` povezuje namestitveni paket in navodila v
  repozitoriju. Obstoječe omejitve obvestil in kopij ostajajo.
- Play celotna opisa: SL 3391/4000, en-US 3475/4000 znakov. Dodana je razlaga
  brezplačnega odprtokodnega vtičnika za lastni Kanboard in lokalizirana povezava
  do `jivie.app/#familyhub` oziroma `jivie.app/en/#familyhub`.

## Dejanska objava in preverjanje

Anonimni GitHub API potrdi ponovno javni repozitorij. cPanel račun `jivie` in
Domains ponovno potrdita `/home/jivie/public_html`, HTTPS je vključen.
Pred objavo se vsi štirje javni HTML hashi ujemajo z lokalnim izhodiščem.

Pregledani pomočnik ustvari svežo zasebno kopijo celotnega spletnega korena v
`/home/jivie/private/website-familyhub-links-20261013/before-public_html.tar.gz`.
Vsaka od 25 datotek je bajtno primerjana z arhivom in živim izhodiščem.
Objavljene so samo štiri datoteke: SL/EN index in SL/EN help/index.
21 drugih datotek ter pravice/lastništvo datotek in imenikov ostanejo enaki.
Vseh štirih končnih HTTPS200 vsebin ima točen lokalni SHA256. Dejansko prikazani
novi razdelek je vizualno preverjen.

V Play Console sta oba predhodna opisa najprej primerjana z lokalnim izvorom,
nato dopolnjena in posamezno shranjena z »Shrani kot osnutek«. Oba končna opisa
sta po ponovnem nalaganju ponovno prebrana in se povsem ujemata z
`STORE_LISTINGS.json`. Sedem telefonskih slik ostaja; ni oddaje v javni pregled.

Dokazi in pomočnik: `build/qa/familyhub-links-20261013/` — before/payload,
`deploy-website.py`, `deployment-terminal.png`, `website-live-evidence.json`,
`play-evidence.json`, `website-familyhub.png` in `play-familyhub.png`.

Android ostane 1.7.0(25), AAB SHA256
`ef909cddea12b22ac3ec9a7c3805a7ed1a55e6cbe3c00368f767799953a27447` je ponovno
preverjen. Aplikacijski izvor, SDK/locks/dovoljenja, nameščeni strežniki,
FamilyHub licenca/koda, podatki in Mac niso spremenjeni. Naslednji izdajni korak
ostajajo ista AAB25, države in Pregled objavljanja.
