# Izbris računa v Jivie — Flutter odjemalec

Izvedba 7. oktobra 2026 za **samostojno gostovanje**; upravljano gostovanje nima dokončanih pravil. Odjemalec uporablja [strežniško pogodbo](server/account-api-contract.md). Lokalni testni dokazi niso namestitev v produkcijo ali potrdilo skladnosti trgovin.

## Uporabniški tok

Nastavitve računa so v nastavitvah in na strani računa/deljenja. Predogled pokaže dejanski strežnik/uporabnika, izbris istega Kanboard računa, konkretna števila posledic, skupne prostore, lastniške odločitve ter potrebne posamezne strukturne izjeme. Celotna policy-v1 struktura se preveri v podatkovni plasti pred gradnjo destruktivnega obrazca. Nepodprt ali nepovezan strežnik ne dobi izmišljene potrditve.

Lastnik izbere obstoječega upravičenega naslednika. Izbris celotnega lastnega prostora je mogoč le, ko ga predogled izrecno dovoli, in je posebej označen. Za strukturo seznama/finančnega računa je potreben posamezen checkbox: generično ime, odstranitev lastnika, pri finančnem računu ohranitev valute in začetnega stanja za vnose drugih. Finančni znesek uporablja obstoječi formatter, ne surovih najmanjših denarnih enot. Lastni vnosi se izbrišejo, seštevki se lahko spremenijo. Zapisi drugih ustvarjalcev ostanejo, vključno z vašimi urejanji njihovih polj, ker ni provenance po posameznih poljih. Ta meja je vidna pred potrditvijo.

Potrditev zahteva razumevanje posledic, `DELETE`, geslo in po potrebi TOTP. Geslo/TOTP se počistita po vsakem poskusu in se ne shranita za retry. Stale/blocked prvi poskus naloži nov predogled in počisti stare izbire/potrditev. Po neposrednem uspehu je vidna potrditev; `cleanupPending` pomeni odstranjen račun/podatkovne zapise in še nedokončano brisanje strežniških datotek, ne popolnega uspeha.

## Izvoz in lokalna vsebina

Samostojni `local` workspace ostane. Zasebno sinhronizirana vsebina tega računa spada k izbrisu: particija, zasebni binding/preslikave/opomniki, vrste, konflikti, obvestila, lokalni strežniški zapisi in staged recovery iste particije se odstranijo. Ni samodejnega kopiranja v local ali drugo identiteto. Lokalni opomniki se ob spremembi projekcije ponovno uskladijo.

Pred izbrisom je na voljo šifrirana `.vsakdan` kopija z jasno omejitvijo: po izbrisu računa ne more nadaljevati njegovega strežniškega dela in ni popoln Kanboard/priponkovni arhiv. Poseben **Izvozi osebne podatke za lokalno obnovo** izrecno shrani nešifriran osebni JSON, vključno s trenutno dostopno zasebno projekcijo. Opozorilo razloži varno hrambo ter poznejši izrecni lokalni uvoz. JSON ne vsebuje sej, deljenega dela ali sync binding/vrst; sveži izvoz prebere storage in ACL, namesto da kodira star UI snapshot. Uvoz po izbrisu ne ustvari strežniških operacij. Popoln arhiv starega sistema zahteva ločen upravljavski zajem.

Stare povezave Kanboard, njihovi predpomnilniki in AI pogovori živijo v ločenem legacy sistemu. Ta tok jih ne odstrani; brez zanesljive preslikave ne briše drugih profilov. UI izrecno navede to omejitev. Kopij drugih članov, zunanjih arhivov in starih že izvoženih datotek ni mogoče odpoklicati.

## Neznan izid, ponavljanje in preklic

Naključna 32-byte receipt skrivnost, `operationId`, izvorna identiteta in zamrznjeni predogled/odločitve so pred pošiljanjem trajno v varni shrambi. Nikoli niso del običajnega izvoza. SQLite `deletion_pending:<partition>` prepreči nadaljnji sync in odklopi zasebno projekcijo, dokler izid ni razrešen. Timeout, revocation ali neveljaven odgovor niso dokaz izbrisa; status ne uporablja bearerja in preveri isti serverId. Retry ohrani prvotno operationId/hash/odločitve ter zahteva novo geslo/TOTP.

Znana precommit zavrnitev lahko odstrani pending samo pri prvem poskusu. Zavrnitev ponovitve ne dokaže izida prvotne zahteve. `account.deletion.cancelPending` uporablja isti strežniški lock kot confirm. Za nov preklicni marker potrebuje aktiven bearer točno izvorne particije; po odjavi je potrebna ponovna prijava v isti račun. Klient nikoli ne uporabi bearerja drugega računa. Preverjanje že obstoječega receipt/status ostane javno: šele `cancelled:true` odstrani lokalno barrier/receipt in omogoči svež predogled. Če je prvotni izbris že uspel, preklic vrne dejanski izid; računa ne obudi. Status lahko obnovi tudi potrditev preklica po izgubljenem odgovoru.

Potrjen izbris in lokalno čiščenje imata trajni `deleted_account:<partition>` tombstone. Stare seje se ob odpiranju/refreshu izključijo; stari recovery podatki iste particije se ne morejo nadaljevati. Pozni odgovor po menjavi naprave/računa ne izbriše novega profila. Poznejši status počisti samo izvorno particijo. Pravice ostanejo strežniška odgovornost; lokalni tombstone ni nadomestek ACL.

## Preverjanje in odprte meje

Namenski testi: `account_deletion_repository_test.dart`, `account_deletion_preview_test.dart`, `account_deletion_ui_test.dart`. Pokrivajo zavrnjene zmožnosti, malformed nested predogled, uspeh, izgubljen ACK/restart, step-up, cleanupPending, menjavo identitete, prvi precommit error, ohranitev unknown receipt ob retry napaki, preklic pred/po commit ter zasebni osebni JSON izvoz–izbris–lokalni uvoz brez upload vrste. UI predogled–izbire–potrditev in uspeh sta preverjena na 320/390/1280, SL/EN, svetlo/temno; stale izbire in menjava računa imata dodatna testa.

Nastavitve vsebujejo povezave `https://jivie.app/privacy/`, `/help/`, `/delete-account/` ter angleške `/en/...` različice. To so pripravljene destinacije; domena/strani še niso objavljene ali preverjene kot dosegljive. Namestitev strežnika, podpisane fizične naprave, native file picker, realni bralnik zaslona ter končne trgovinske zahteve ostajajo ločena dokazila.

## Izrecno vključen preizkus pravega HTTP toka

`test/organizer/data/account_deletion_http_test.dart` privzeto preskoči oba testa. Vključitev zahteva `KANBAN_ACCOUNT_DELETION_HTTP_FIXTURE`; datoteka mora izrecno vsebovati `synthetic:true`, HTTP loopback `127.0.0.1:18384` in kontejner z začetkom `kanban-familyhub-account-deletion-final`. PHP pred delom ponovno preveri razvojni način in `self_hosted`. Test ne uporabi lastnikovih/bootstrap poverilnic iz fixture; vsak test prek izoliranega Dockerja ustvari nov naključen `app-user`. Geslo gre samo skozi stdin in HTTP, telesa/poverilnice se ne izpisujejo.

Prvi tok uporabi pravi HttpCollaborationTransport prek ControlledHttp, prijavo, podatkovni decoder predogleda, novo lastno skupno območje in njegov izrecni izbris skupaj z računom; status ter neposredna poizvedba izolirane baze preverita dejanski izbris Kanboard users zapisa. Drugi tok prekine prvo confirm zahtevo pred pošiljanjem, preveri ohranjen račun/receipt/barrier, pošlje avtoriziran cancelPending ter preveri cancelled status; svež predogled in nova confirm zahteva nato odstranita izključno novi testni račun.

Primer za namenski lokalni fixture (ne za produkcijo):

```sh
KANBAN_ACCOUNT_DELETION_HTTP_FIXTURE=build/qa/deletion-http-final/fixture.json \
  flutter test test/organizer/data/account_deletion_http_test.dart
```

Glavni agent je 7. oktobra 2026 oba toka dejansko izvedel: **2 HTTP PASS**. Ločeno je uspešnih **50 izbranih enotnih/widget testov** izbrisa, predogleda in prvega vodiča. Končna analiza ima 35 obstoječih informacijskih lintov, brez napak ali opozoril. Uspešne so spletna release, Android debug in iOS simulator debug gradnje. Dnevniki so lokalno v `build/qa/account-deletion/`; končni HTTP dokaz je `http-client-final.log`. Prvi skupni zagon je vseboval dva neuspeha testnega okolja (prestrezanje HTTP v widget bindingu); po odstranitvi bindinga in obnovi razvojne nastavitve izoliranega fixture sta dejanska HTTP testa ponovljena uspešno. To ni preizkus produkcije ali fizičnih podpisanih naprav.
