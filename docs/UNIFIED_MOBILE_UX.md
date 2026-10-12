# Enoten Jivie: Android in iOS

**Nadaljnja izdaja12.oktobra:** Android **1.7.0(25) Aktivno od21:04** na istem
internem kanalu domači(15). [Izdajni dokazi](release/UNIFIED_UX_RELEASE.md).
Spletna predstavitev in galerija sta objavljeni na jivie.app; nove slike in opisi
v Play so shranjen osnutek. Spodnje stanje1.6.1 in odsotnost nove izdaje opisujeta
zaključek same izvedbe pred tem izrecno naročenim izdajnim korakom.

Dogovor 12. oktobra 2026: skupna informacijska arhitektura in grafitno-modra
podoba. Izvedbo vodi glavni agent, ločene dele pripravljajo GPT-6.1 Sol / high.
Ta smer nadomesti prejšnji telefonski predal kot glavno navigacijo.

## Razporeditev

| Stalni zavihek | Namen | Vsebina |
| --- | --- | --- |
| Utrip | Kaj se dogaja in kaj prihaja | Današnji dogodki, naslednjih sedem dni, odprti projekti, kratek pregled opravil |
| Planer | Od zamisli do izvedbe | Opravila, Koledar, Idejnik |
| Prostor | Za kaj skrbim | Projekti, Finance, glede na prostor tudi Nakupi, Vrt in Osebe |
| Več | Moja uporaba aplikacije | Račun, nastavitve prostora, nastavitve, kopije, pomoč |

Zgornji izbor določa osebni/gospodinjski/organizacijski prostor oziroma Vsi.
Vsi ostane pregled: novo vsebino je treba usmeriti v konkreten prostor.
Vrt ostane trajno področje z lastnimi gredami in sezonami. Za navigacijsko
spremembo ga ne pretvarjamo v navaden projekt. Finance prostora ostanejo
dostopne tudi brez projekta. Projektni pogledi uporabljajo iste zapise.

## Oblikovanje

- Nevtralno svetlo/temno ozadje, grafitno besedilo, moder poudarek za dejanja
  in izbor. Hierarhija izhaja iz tipografije in razmikov.
- Štirje stalni cilji imajo ikono in besedilo; njihovi položaji se ob menjavi
  prostora ne spreminjajo. Namizni prikaz uporablja iste skupine.
- Povzetki pokažejo resnične podatke in kratka uporabna prazna stanja. Ni
  vzorčnih dogodkov, izmišljenih zneskov ali avtomatičnih zapisov v uporabniško bazo.
- Obrazci ohranijo prijavo ob naslovu in eno spodnjo vrstico
  brisanje / Prekliči / ikona Shrani. Kompaktni oblak ostane ob naslovu.

## Platformne smernice in preverjanje

Upoštevamo [Apple UI Design](https://developer.apple.com/design/tips/),
[Android dostopnost](https://developer.android.com/guide/topics/ui/accessibility/views/apps-views),
[Android navigacijo](https://developer.android.com/develop/ui/compose/components/navigation-bar)
in [Flutter prilagoditve platformi](https://docs.flutter.dev/ui/adaptive-responsive/platform-adaptations).

Skupni minimum dotika je 48 logičnih točk (pokriva tudi Applov minimum 44).
Besedilo sledi sistemski povečavi, vsebina se prilagaja širini, ikone dejanj
imajo imena, izbor ni sporočen samo z barvo. Ohranjeni so varni odmiki,
sistemsko urejanje besedila, platformno drsenje ter sistemski izbirniki datotek.
Flutterjevi privzeti prehodi nadomestijo vsiljen iOS prehod na vseh platformah.

To je izvedbena kontrola konkretnih uporabniških poti, ne potrdilo trgovin o
skladnosti celotne aplikacije. Fizični VoiceOver/TalkBack, iPhone uporaba ter
trgovinski postopki imajo ločene dokaze. Nova podoba sama ne reši še odprtih
APNs, App Privacy, podpisovanja ali javne oddaje.

## Dokazi izvedbe

Izvedba je zaključena v izvoru. Utrip uporablja skupno bralno projekcijo lokalnih
in dovoljenih deljenih podatkov; izbira vrstice odpre izvirni zapis oziroma projekt.
Dogodki, ki se končajo ob polnoči, sodijo prejšnjemu dnevu; večdnevnih dogodkov
iz današnjega pregleda ne podvajamo še med prihajajočimi. Preklicane pravice,
menjava računa, izrecni zapisovalni cilj v Vsi in bralni način ostanejo uveljavljeni.

Končno skupno preverjanje 12. oktobra:

- **651 uspešnih testov / 1 opt-in preskok**: celoten `test/organizer/ui`, nova
  projekcija Utripa in oblikovna tema. Med njimi so vračanje nazaj, prehodi med
  prostori in računi, finančne pravice, kopije, urejevalniki in poteze Idejnika.
- `flutter analyze --no-pub`: **No issues found**.
- Android debug APK in iOS simulator debug: uspešni gradnji iz končnega izvora.
- **28 widget posnetkov**: sedem pogledov pri Android 360/svetlo,
  iOS 390/svetlo, iOS 390/temno in Android 320 z 2× besedilom. Posnetki so
  v `build/qa/unified-mobile-ux/`; njihovi vzorčni zapisi so izolirana testna
  vsebina, ne podatki uporabnika in ne vsebina, ki jo dodaja aplikacija.
- Koledar pri običajni širini ohrani mrežo z najmanj 48-točkovnimi dnevi;
  ob ozkem zaslonu ali velikem besedilu uporabi izbor celotnega datuma z istimi
  dogodki in menjavo meseca. Besedilo se ne zmanjšuje na silo.
- Preverjeni kontrasti teme, poimenovanja dejanj, tipkovnični dostop in vodoravni
  urejevalni gumbi pri 2× besedilu. Veliko besedilo preuredi tudi kartice Več.

Prva razvojna iOS gradnja je bila z `simctl` nameščena in zagnana v simulatorju.
Mac se je nato pri računalniškem upravljanju izkazal za zaklenjenega, zato
neposreden pregled simulatorja in fizični VoiceOver/TalkBack nista potrjena.
Widget posnetki niso posnetki fizičnega telefona.

Ni spremembe različice, SDK, zaklenjenih odvisnosti, dovoljenj, podatkovnih shem,
FamilyHub ali gostovanja. Aktivni interni Android ostane **1.6.1 (24)**;
nova podoba še ni izdana testerjem ali trgovinam. Naslednji korak je uporabnikov
pregled podobe ter nova interna Android izdaja; iOS distribucija ostaja ločen korak.

Ponovitev potrebnih preverjanj:

```sh
flutter test --no-pub test/organizer/ui test/organizer/data/utrip_projection_test.dart test/jivie_design_theme_test.dart
flutter analyze --no-pub
flutter build apk --debug --no-pub
flutter build ios --simulator --debug --no-pub
JIVIE_UI_CAPTURE=1 flutter test --no-pub test/organizer/ui/unified_visual_review_test.dart
```
