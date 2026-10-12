# Idejnik — popravek premikanja in povečave

12. oktober 2026. Uporabnik je na Androidu fizično preizkusil Idejnik in poročal,
da po začetnem premikanju/povečavi rokica obstane. Risanje in oblike ostanejo
uporabni, ponovno odprtje urejevalnika pa rokice ne popravi. Priloženi posnetek
kaže način premikanja in predhodno izbrano potezo; izbor je samo risarski okvir.

Vzrok je potrjen v dejansko uporabljeni Flutter knjižnici: `GestureDetector`
ustvari `PanGestureRecognizer`, če je nastavljen katerikoli pan callback, tudi
samo `onPanCancel`. Platno je v načinu roke izključilo start/update/end, preklic
pa je ostal. Otroški prepoznavalnik je tako prestrezal dotike pred
`InteractiveViewer`. Dotiki zunaj pomanjšanega platna so lahko delovali; po
povečavi je platno pokrilo pogled in napaka je bila očitnejša.

Popravek odstrani celoten komplet risarskih pan dogodkov skupaj v načinu roke
in pri prikazu brez urejanja. Premikanje in povečavo tedaj vodi samo viewer.
Ob menjavi orodja, pravice urejanja ali identitete table se nedokončana risarska
poteza prekliče. Potrjeni elementi, fotografije, njihov položaj, osnutki,
razveljavitev, podatkovni formati in strežniške pogodbe so ohranjeni.

Preizkus s pravimi pointer dogodki na starem izvoru dejansko odpove pri pan
na platnu na360/800/1280. Po popravku **20 ciljnih testov PASS**, ciljna analiza
**No issues found**, diff čist. Šest novih regresij preveri pan po risanju/izboru,
pinch na samem platnu, dvig enega prsta in nadaljnji pan, ponoven vstop, bralni
pogled ter menjavo orodja/pravice s prstom še na zaslonu. Sprememba pogleda ne
spremeni JSON table in ne pokliče podatkovnega zapisovanja. Preostalih14 so
obstoječi real-provider testi fotografij, urejanja, kopij prikaza, prijav in
konfliktov. Dokazi so v `build/qa/ideas/gesture-{before,final,targeted,analyze}.log`.

Popravek je namenjen interni Android1.6.1(24); dejanska gradnja/objava se
zabeležita v ločenem izdajnem dokazilu. Fizičnega popravljenega obnašanja na
uporabnikovem telefonu še ne trdimo. FamilyHub0.13/schema17, gostovanje,
SDK/odvisnosti/podpisi, iOS/Mac in javna izdaja se pri tem ne spreminjajo.
