# Android 1.6.1 (24) — premikanje in povečava Idejnika

12. oktober 2026. Popravek fizično prijavljene napake rokice v Idejniku.
Funkcionalni commit **f6520a0**, izdajni metadata **196b711**.
[Vzrok in regresije](../IDEAS_PAN_ZOOM_FIX.md): risarski prepoznavalnik je zaradi
samega onPanCancel ostal aktiven tudi v načinu premikanja. Zdaj celoten komplet
risarskih dogodkov preneha skupaj; nedokončana poteza ob menjavi orodja/dostopa
ne more ostati aktivna. **20 ciljnih testov PASS**, ciljna analiza brez ugotovitev.
Uspešnih funkcionalnih preizkusov med izdajo nismo ponavljali.

Ena podpisana gradnja: `build/releases/Jivie-1.6.1+24-android-firebase.aab`,
**78.412.840 bajtov**, SHA256
`138311c770ccb67e5f7ee83229c565bcca01d89b854ca784a8140994d8c03db3`.
AAB/checksum read-only; AAB23 ohranjen. **317 zamrznjenih vhodov PASS**, agregat
`7f16ac9d1046e70d274ee3162a6d17673fcc5cb4ce56d844b5c11d9901af3245`.

Isti upload certifikat/Firebase native in vsi Dart ABI/8 dovoljenj kot23.
`si.triparna.jivie`, min24/target36, Back callback, share FileProvider, brez kamere
ali širokih media/storage dovoljenj. Bundletool/CRC/PAGE_ALIGNMENT_16K vseh8
64-bitnih knjižnic/odsotnost podpisnih in service-account skrivnosti PASS.
**23 izdajnih +7 Firebase kontrol/source checker PASS**. SDK in zaklenjene
odvisnosti niso spremenjeni. Metadata commit veže iste vhode brez nove gradnje.

**Play Console potrjuje Aktivno /1.6.1(24) od12. oktobra12:36**, za isti
interni seznam **domači(15)**. Naložen je preverjeni24,23 je izključen iz nove
izdaje,0 izgubljenih/novih naprav; opombe SL/en-US so objavljene. Isti kanal
4701286726300038561, račun TriparNA/TaknDevs4991604398202512900,
aplikacija4972659047480717992. [Posodobitev](https://play.google.com/apps/internaltest/4701286726300038561).
Dokazi: `build/qa/ideas-panzoom-release-20261012/android/`.
Fizični preizkus popravljenih potez na uporabnikovem telefonu še ni potrjen.
FamilyHub0.13/schema17, gostovanje, podatki/sheme, iOS/Mac, splet in javna izdaja
so pri tem nespremenjeni.
