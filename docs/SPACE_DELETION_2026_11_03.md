# Izbris prostora in dostopnost dejanj — 3. november 2026

## Uporabnikovo poročilo

Po različici 1.11.16 uporabnik potrdi, da je predhodna sinhronizacija uspešna. Ob poskusu izbrisa testnega gospodinjstva se prikaže kratko obvestilo, da podatki niso na voljo. Prostor ostane na seznamu; naslednje osveževanje ob 04:04:54 UTC vrne `metadata / crypto_reconciliation_required`, brez prenesenih strani. Poročilo samo še ne potrjuje, ali je strežnik izbris sprejel.

Uporabnik naroči diagnozo in popravek, premik dejanj Arhiviraj/Izbriši na dno nastavitev prostora ter novo javno Android izdajo. Produkcijski podatki in telefoni niso tarča testiranja.

## Izhodiščni pregled kode

`CryptoBusinessDeletion.retainedStatus` že vsebuje preverjanje podpisanega potrdila o izbrisu in povezave z imenikom/zgodovino, vendar pred popravkom nima klicatelja. Seznam šifriranih prostorov za manjkajoče vnose uporablja stare `scopeAccessChanges` podatke. Odsotnost sama se pravilno ne obravnava kot dokaz izbrisa. Ta pot je kandidat za napako pri uskladitvi seznama; dejanski lokalni izid in natančen popravek sledita spodaj.

## Dejanski lokalni izbris — prvi poskus

Na isti ohranjeni HTTP namestitvi iz preizkusa gesla je nov predogled izbrisa uspel (4 zahteve). Po dejanski potrditvi je bila strežniška `crypto2.scope.delete` uspešno izvedena, odjemalec pa je že shranil njeno potrjeno nespremenljivo potrdilo. Nato `_verifyOwnResult` vrne `crypto_scope_deletion_event_inclusion`, ker preverjanje dogodka uporabi stanje avtoritete pred izbrisom. Lokalni gospodinjski zapis zato še vedno vsebuje `deleted=false` in `revoked=false`. Poskus je ustvaril natanko eno strežniško zahtevo za izbris; ne gre za neuspešno klikanje ali zavrnitev izbrisa na strežniku.

Dodatna vrzel pri odkrivanju izbrisa: strežniško čiščenje nastavi `familyhub_scopes.deleted_at`, vendar ne doda stare vrstice v `familyhub_scope_revocations`, ki jo zahteva stara bralna poizvedba. Podpisano potrdilo E2EE ostane ohranjeno in ga mora odjemalec preveriti.

## Opravljena preverjanja popravka

Po popravku je običajna ročna sinhronizacija istega že zataknjenega računa uspela v prvem poskusu: 28 HTTP zahtev, en bralni `deletionStatus`, nič novih zahtev za izbris in brez ponovne potrditve. Izbrisani prostor je odsoten iz aktivnega seznama, preostala dva prostora sta vidna. Njune vrstice, vsebina in oddaljene projekcije so ostale nespremenjene; enako seja, ključi in obnovitvena datoteka. Izvirna potrjena zahteva za izbris in šest starih checkpoint dokazov so ohranjeni. Aktivne vrste in trenutne napake so prazne. To je preverjanje metapodatkov v običajnem koordinatorju; nespremenjenih vsebin ni ponovno prenašalo.

Premik gumbov ima 15 novih uspešnih UI preverjanj; podrobnosti in zgodovina poskusov v `SPACE_SETTINGS_LIFECYCLE_2026_11_03.md`. Jedro ima 13 novih uspešnih preverjanj; podpisna in zgodovinska varovala niso oslabljena. Končni neposredni izbris novega testnega gospodinjstva je ločen naslednji preizkus.

Dodaten preizkus trenutno izbranega prostora je uspel: po potrjenem izbrisu njegovi podatki/dejanja niso več prikazani, izbor drugega prostora deluje. Aplikacija sama ne preusmeri novih zapisov v drug prostor.

## Nov neposreden izbris po popravku

Celoten nov postopek na istem računu je uspešen: novo testno gospodinjstvo, novo sinhronizirano opravilo, izbor gospodinjstva, predogled in natanko ena zahteva za izbris, nato samodejno uspešno osveževanje. Skupaj 285 HTTP zahtev v približno 7 s, obe izbrisani gospodinjstvi nista več v aktivnem seznamu, preostala prostora in njuni podatki/ključi/seja/FILE so nespremenjeni.

Uspeh je zabeležen v tretjem dovoljenem poskusu: prvi zagon ni naložil testa zaradi spora pri datoteki native_assets med dvema testnima zaganjalnikoma; drugi je pred ustvarjanjem ustavil napačno tipiziran testni zemljevid. Popravljena je bila testna priprava, brez spremembe produktnih varoval. Tretji je prvi prišel do ustvarjanja in izbrisa. Vsi dnevniki so ohranjeni; uspešnih testov ni bilo ponavljanih.
