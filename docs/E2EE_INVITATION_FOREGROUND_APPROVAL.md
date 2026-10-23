# Potrditev dostopa po sprejemu povabila

Izvedba 23. oktobra 2026. Sprememba je implementirana in izvorno pregledana;
59 različnih novih ozkih kontrol je uspelo. Celotni HTTP scenarij ostaja
DELNO / STOP3. To še ni potrdilo za mobilno ali produkcijsko izdajo.

## Uporabniški potek

Za že pripravljen E2EE račun ostane [obstoječi v5 potek](E2EE_PREAUTHORIZED_INVITATIONS_V5.md).
Za nov račun pošiljatelj pošlje običajno e-poštno povabilo. Prejemnik ustvari
račun, potrdi e-pošto, pripravi svojo zaščito računa in izrecno sprejme povabilo.
Pošiljatelju nastane obvestilo, ki odpre prav to čakajočo potrditev dostopa.

Če pošiljatelj uporablja aplikacijo v ospredju, ta lahko dokonča dostop na
podlagi njegovega prvotnega Send. Pošiljatelj in prejemnik ne potrebujeta
sočasne povezave. Prejemnik lahko po sprejemu odide; pošiljatelj pozneje
dokonča predajo, prejemnik pa naslednjič prevzame šifrirane ključe.

Samodejno dokončanje velja za nova povabila, za katera je ta naprava ob Send
zabeležila točen namen in prejela potrjeno pošiljanje. Stara povabila ostanejo
na izrecni poti. Spremenjene pravice, politika ali identiteta ter nezanesljiva
zgodovina ustavijo avtomatiko in ohranijo ročno potrditev.

## Meje in povezave v izvoru

- `invite_crypto_repository.dart` shrani nov namen skupaj z osnutkom v isti
  lokalni transakciji. `crypto_invitation_autoapproval.dart` preverja prvotno
  podpisano pošiljanje, točen podpisan sprejem, pravice in trenutni račun.
- `scope_crypto_manager.dart` in `crypto_inherited_invitation_grants.dart`
  uporabljata obstoječe preverjanje zgodovine ter predajo ključev. Samodejne
  odobritve uporabljajo lastne shranjene ID pregledov in ohranijo izvirne
  zahteve ob prekinitvi; ne izbirajo nepovezanega ročnega pregleda.
- `foreground_invitation_approval_coordinator.dart` sproži omejen pregled ob
  pripravljenem zagonu, vrnitvi v ospredje ali novem preverjenem obvestilu.
  Ni novega časovnika, delavca za ključe v ozadju ali samodejnega sprejema na
  prejemnikovi strani.
- `NativeCryptoInvitationNotificationV2.php` veže obvestilo na prvotnega
  pošiljatelja, povabilo in odtis sprejema. Obvestilo je namig za navigacijo;
  ne daje pooblastila za razkritje ključev. Odprtje v aplikaciji ponovno
  preveri strežniško obvestilo in podpisano povabilo.

Sprejem ustvari interni dogodek `crypto2.invitation.accepted`; obstoječi inbox
API odstrani predpono in odjemalcu vrne `invitation.accepted`. Dodani objekt
`invitationAcceptance` vsebuje samo `scopeId`, `invitationId`,
`acceptanceProofHash`, `creatorProofHash` in `tokenHash`. Push prenaša obstoječo
referenco na obvestilo, brez ključev ali vsebine prostora.

Uporabniške nastavitve obvestil ostanejo veljavne. V ospredju ni dodatnega
pojavnega opozorila. Ob dokončanju ali preklicu se še neposlana obvestila
prekličejo in zastarelo obvestilo ni več uporabno. Že dostavljenega sistemskega
obvestila ni mogoče zanesljivo preklicati; tekmovanje med dostavo in
dokončanjem zato ostane možno.

## Lokalna preverjanja

Nove kontrole so omejene na to spremembo. Izolirani HTTP scenarij uporablja
`127.0.0.1:59780`, lastne podatke ter nov račun, ki pred Send še ne obstaja.
Obstoječi QA, telefoni in produkcija niso del preverjanja.

| Sklop | Trenutni rezultat | Meja dokaza |
| --- | --- | --- |
| Strežniška vezava in življenjski cikel obvestila | 13 novih PASS1 | PHP pomnilniška baza; ne dostava FCM/APNs |
| Prebrano zastarelo obvestilo | 6 novih PASS1 | Lastno nedostopno obvestilo ob veljavnem dostopu do prostora je `notification_missing`; napačen račun/dejanski odvzem ostaneta zavrnjena |
| Samodejna odobritev in potrdila zahtev | 20 različnih novih PASS | Dart/SQL, kontrolirani vmesniki in podpisi; ena popravljena testna predpostavka v drugem poskusu |
| Trenutna žična oblika, usmerjanje in koordinator | 11 različnih novih PASS | Model/repository/widget kontrole, ne fizični telefon |
| Trije ročni pregledi sprejema na strani povabila | UNVERIFIED / STOP3 | Napake testnega okolja in prevajanja; brez četrtega poskusa |
| Nadaljevanje čakajočega označevanja obvestila kot prebranega | UNVERIFIED / STOP3 | Ohranitev izvirne zahteve skozi osvežitev je potrjena; celotni sintetični sync ni dokazal odstranitve obvestila. Točen razlog ni zajet, zato ne trdimo niti uspeha niti nove napake aplikacije |
| Novi HTTP potek z novim računom | DELNO / STOP3 | Potrjeni Send, registracija, e-pošta, ključi novega računa, izrecni sprejem brez lastnika, točno obvestilo, zavrnitev napačnega računa ter prepoved odobritve v ozadju. Resnični parent activation 200 z izgubljenim odgovorom je potrjen; nadaljevanje podprostora je obstalo pri `crypto_key` |

Prva dva HTTP zagona sta se ustavila zaradi nastavitev testa: stari v4
odgovor ne nastavi `deliveryQueued`, čeprav je pošta pravilno v vrsti; novo
testno okolje pa ni imelo URL za sestavo zajete e-pošte. Isti Send in ista
poštna vrsta sta bila ohranjena; ni bilo novega povabila, ponastavitve ali
ponovitve uspešnih korakov. Tretji zagon je prišel do prave napake nove
izvedbe: `automaticReviewIds` je uporabljal UUID kot ključ objekta, kar
`CryptoJson` zavrne. To je določeno z izvorom in zaporedjem klicev; točen
sklad ujete izjeme ni shranjen. Ozki popravek uporablja seznam objektov
`{scopeId, reviewId}`. Devet novih kontrol tega popravka je uspelo v drugem
poskusu po napaki prevajanja testnega primera: prava pomnilniška SQL baza,
kanonični zapis, ponovno branje prek produkcijske storitve ter zavrnitev
neveljavnih/podvojenih povezav. Strogo preverjanje podpisov in zgodovine je
ohranjeno. Celotni HTTP scenarij ni bil zagnan četrtič; nadaljevanje podprostora
in prejemnikovo branje prostora/podprostora po popravku ostajata NEPREVERJENA.

Končni pregled ohranjenega stanja potrdi točno eno aktivacijo prostora in en
sprejem. Izgubljeni odgovor se je po ponovnem odprtju uskladil s točnim
strežniškim potrdilom: lokalna izvirna podpisana zahteva je potrjena in ni
bila ponovno poslana. Prostor ima dva člana; podprostor ostaja pri izvirni
prvi reviziji in enem članu, njegov čakajoči zapis je ohranjen. Sintetična
neposlana push referenca je preklicana z nič poskusi dostave. Lastni testni
strežnik je ustavljen; podatki, ključi in volumni so ohranjeni. Končni pregled
drugih vsebnikov ni pokazal sprememb stanja ali slike.

Ohranjeni so tudi neuspešni poskusi. Prve tri sintetične kontrole s staro
napačno predpono dogodka so nadomeščene s kontrolo dejanske žične oblike in
ne štejejo kot trenutni dokaz. En stari uspešen primer iz tega novega sklopa
se je zaradi preširokega filtra pomotoma ponovil; zapis je ohranjen, ne šteje
še enkrat med 20 kontrol. Ostali uspešni primeri niso bili namenoma ponavljani.

Dokazi so v `build/qa/local-diagnostics/invitation-approval-20261023/` ter
`build/qa/local-diagnostics/invitation-foreground-approval-20261023/`.
Dejanska dostava APNs/FCM in prikaz na fizičnih telefonih ostajata za poznejši
mobilni pregled. Že začete omrežne zahteve ni mogoče preklicati za nazaj;
varovalo prepreči naslednjo novo predajo po izgubi aktivnega ospredja.
