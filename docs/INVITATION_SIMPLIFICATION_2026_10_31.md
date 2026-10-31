# Poenostavitev povabil in priprave računa

Uporabnik je 31. oktobra po pregledu in dopolnitvi Word poročila naročil
izvedbo ugotovitev, povezanih roadmap zapiskov in novo javno Android izdajo.
Obstoječi računi, ključi, podatki in povabila ostanejo veljavni; prejemnik
včerajšnjega povabila mora nadaljevati isti postopek po običajni posodobitvi.
Telefona sta odklopljena; lokalni preizkusi niso dokaz fizične mobilne potrditve.

## Dogovorjeni sklopi

- Povabilo: glavna povezava, dodatni vnos kode zložen; kratki povzetki brez
  ponavljanja celotne razlage gostovanja. Opisi vlog sledijo dejanskim pravicam.
  Odstranimo odvečno menjavo računa v pravilno vezanem toku, ohranimo izhod ob
  napačni identiteti. Vnos naslovov brez samopopravkov in samodejnih presledkov.
- E-pošta: jasno glavno dejanje Potrdi e-pošto, potrditvena povezava ter rezervna
  koda; predogled povezave ne porabi potrditve. Pravi račun/strežnik, rok,
  enkratnost in ohranitev povabila ostanejo obvezni. Po potrditvi ni ponovnega
  poziva, naslednji korak je shranjevanje datoteke.
- Obnovitvena datoteka: razumljiv naslov in kratek namen, podrobnosti za
  povezavo. Razlaga loči ključ od kopije vsebine in različne obsege datotek.
- Prvi Utrip: začetni namig izgine po prvi uporabi; pomoč ostane dosegljiva
  prek obstoječih nastavitev. Nobenega posega v podatke prostora.
- Odobritev dostopa: ob odprtju obvestila isti koordinator uporabi ohranjeno
  izrecno namero pošiljatelja za samodejno dokončanje nespremenjenega povabila.
  Ročno preverjanje ostane ob spremenjeni identiteti/pravicah ali manjkajočem
  soglasju. Že dokazano dokončan dostop pokaže uspeh namesto lažne napake.
- Prejemnik: po dokončanju dostopa samodejno nadaljevanje, kjer ga omogoča
  obstoječi koordinator; brez ponovnega sprejema ali novega neomejenega preverjanja.

Prenova vrta in splošno združevanje vseh vrst zapisov ostajata ločeni poznejši
fazi po prejšnjem dogovoru. Že izvedenih roadmap točk ne izvajamo ponovno.
Uporabnik je potrdil javno ime upravljavca: **Anže Novšak, TriparNA z.o.o.**

## Preverjanje in izdaja

Vsak sklop ima ciljne nove regresije, največ tri neuspešne poskuse istega
primera. Varovala, nespremenljive zahteve, podpisi in stari formati se ohranijo.
Root pregleda diffe in rezultate. Izdaja sledi šele preverjeni integraciji;
oddaja na Google Play ni isto kot javna razpoložljivost. Strežniške odvisnosti
se navedejo posebej in se ne prikazujejo kot že nameščene.

## Izidi

Implementacija je pripravljena in neodvisno izvorno pregledana. Obstoječa
včerajšnja povabila, računi in ročne e-poštne kode ostanejo uporabni.

- Povabilo/vnosna polja: 8 novih widget kontrol PASS, oba sklopa v drugem
  poskusu po popravku testnega modela oziroma manjkajočega vzporednega importa.
- Prvi obisk in razlaga datotek: 5 novih kontrol PASS1. Posebna integracija
  e-poštnega statusa z gumbom za datoteko PASS2: začetno skrit gumb, potrditev
  v istem čarovniku, skrit ob nedosegljivem statusu; po eno branje na spremembo.
  Prvi poskus je ujel neprijetno asinhrono napako pred priklopom FutureBuilder;
  popravljena je takojšnja obravnava napake brez skrivanja prikazanega stanja.
- E-pošta: 17 novih backend assertions PASS2, 6 loopback HTTP kontrol PASS1,
  10 kontrol dejansko izrisanega SL/EN JS PASS2, 3 parser PASS1, 2 izrecna
  native-review widget PASS2, 1 cold-start ordering widget PASS1. To niso
  dokazi fizičnega telefona, dejanske dostave SMTP ali celotne Kanboard HTTP poti.
- Samodejni dostop: 14 različnih novih Dart kontrol PASS, 2 PHP besedili PASS.
  Preverjeni prvotni Send, podpisani sprejem, sveže članstvo/pravice/imenik;
  že porabljen sprejem in izgubljen odgovor ne povzročita ponovne dodelitve.
  Izbrisano obvestilo je le namig za točno preverjanje, nikoli dokaz dovoljenja.
  Napaka naknadne osvežitve obvestil ne spremeni potrjenega uspeha v neuspeh.
- Skupna analiza spremenjenih Dart datotek: 0 napak, 0 opozoril, 13 obstoječih
  stilskih informacij. PHP lint in diff whitespace pregled PASS. Root pregled
  dejanskega Kanboard1.2.54 Runner/Middleware potrdi, da CSRF ni globalni
  middleware; javna email pot sama zahteva Origin+JSON+izrecni veljavni token.

### Jasno odprte omejitve

Štiri prvotne widget kontrole so dosegle STOP3 in niso bile ponovljene:
dve e-poštne kartice (ročna osvežitev, background/resume) ter dve stare ročne
odobritve (zastarel consumed odgovor, splošna neveljavnost). Prve so razkrile
popravljeni eager-read/void-setState težavi; druge so imele nekanoničen testni
JSON, popravljen izvorno. Ločena zgornja integracija in core scenariji so PASS,
vendar to ne spremeni STOP3 v PASS. Točni dnevniki ostajajo shranjeni.

Prejemnik, ki ves čas ostane na čakalnem zaslonu, še lahko potrebuje obstoječi
Preveri dostop; pri vrnitvi v aplikacijo se uporabi obstoječe nadaljevanje.
Ni dodan nov neomejen polling. Telefona nista bila uporabljena; dejanski OS
mail/deep-link ter navadna mobilna posodobitev ostajajo uporabnikova potrditev.

Dokazi: `build/qa/invite-ux-20261031/RESULT.md`,
`build/qa/email-links-20261031/RESULT.md`,
`build/qa/invite-auto-20261031/RESULT.md` in
`build/qa/invitation-release-20261031/`.

Strežniška namestitev in javna oddaja sta naslednja koraka; še nista PASS.
