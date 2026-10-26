# Postopna optimizacija koordinatorja — 26. oktober 2026

Izhodišče: `66ee218`; ugotovitve P1–P8 iz
[modulnega pregleda](MODULE_SYNC_AUDIT_2026_10_26.md).
Uporabnik naroča ločene lokalne/headless kontrole ter commit in push vsakega
smiselnega sklopa. Brez posegov v telefone, obstoječe QA podatke ali produkcijo.
Meritve spodaj so števci konkretnih testnih poti, ne mobilni časovni benchmark
ali obljuba števila fizičnih E2EE HTTP zahtevkov. Starih uspešnih scenarijev
ne ponavljamo. Največ trije poskusi neuspešnega scenarija.

## P1 — ciljni signali dokumentov in lastno branje

Izvedeno: lokalni signal preverjene projekcije nosi vrsto in canonical ID;
priloga še stari/novi cilj. En SQL commit objavi en paket. Seznam preglednic
posluša preglednice, podrobnost svoj ID, priloge svoj cilj in njegov izbris.
Neznana stara tombstone/legacy invalidacija ostane konservativno široka.
Signal nikoli ne prečka računa/prostora ali neuspešnega SQL commita.

Vsako dokumentno branje ima kontekstni query-origin, prenesen po async coni.
Samo lastna projekcija istega branja ne sproži ponovnega branja tega pogleda;
drugi pogledi in neodvisni koordinatorjevi commiti ostanejo obveščeni. To ni
cache dovoljenj in ne preskoči svežih dokazov, pravic ali samega branja.
Lease, osnutki, šifriranje, signed requesti in protokol so nespremenjeni.
Lastne mutacije še vedno objavijo signal; ne trdimo odprave vsakega možnega
ponovnega branja po uploadu ali navigaciji nazaj.

Nove kontrole, vseh **5 PASS v prvem poskusu**:
- 3 repository/gateway kontrole: query-origin razlikovanje; res oddaljen commit
  med branjem; target filter in device_revoked ob ohranjenem lokalnem osnutku.
- 1 pravi memory SQLite preizkus: nested commit, paketno dedupliciranje,
  rollback, partition/scope izolacija in neznan tombstone.
- 1 headless widget preizkus dejanske list→detail poti: list=1, detail=1;
  dve nepovezani spremembi ne dodata branj; matching remote revision doda
  natanko eno branje in je vidna. Lastni read-signal ne doda trailing branja.

Repository transport v teh kontrolah je sintetičen; to ni nov kriptografski
HTTP ali native dokaz. Izvorni pregled emitterja ohranja hash-change pogoj in
objavo šele po potrjenem SQL commitu. Ozka analiza: 0 napak/0 opozoril;
12 obstoječih slogovnih info (nov curly-braces info odpravljen). Diff check PASS.
Dokazi: `build/qa/coordinator-optimization-20261026/p1-*.log` (ignorirano).
Prvi skupni testni filter je izbral samo tri `coordinator` teste; SQL test
je zato zagnan posebej, ne ponovljen. Vseh pet kontrol ima samo en tek.

## Nadaljevanje

P2–P7 še odprto; P8 najprej zahteva meritev lokalnega SQL/CPU, ne slepega
spreminjanja. Status naslednjih sklopov dodajamo spodaj pred njihovim commitom.
