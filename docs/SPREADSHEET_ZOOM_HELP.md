# Povečava preglednic in pomoč pri formulah — 16. oktober 2026

Po uporabnikovem preizkusu na Samsungu S25 sta v izvoru dodana:

- Povečava oziroma pomanjšava območja celic z dvema prstoma med 50 % in
  200 %. Mere, besedilo in pripete oznake vrstic/stolpcev se spreminjajo
  skupaj, vnosno polje in dejanja ostanejo običajne velikosti. Povečava
  ohrani mesto pod prstoma, kolikor dopušča rob tabele.
- Vidni gumbi −, odstotek in +. Dotik odstotka povrne 100 %. Povečava je
  stanje trenutnega prikaza in ne spreminja skupnih podatkov ali zaklepa.
- Stalno dosegljiv gumb »Formule in pomoč« ob orodni vrstici. Pomoč vsebuje
  vseh pet podprtih funkcij SUM, AVERAGE, COUNT, MIN in MAX s primeri,
  sklice/obsege celic, osnovne računske operacije in decimalno vejico s
  podpičjem. Imena funkcij ostajajo angleška; razlage so slovenske/angleške.

Zoom opazuje samo dotike na mreži; enoprstno drsenje, izbira celice in
tipkovni vnos ostanejo dosegljivi. Poteza z dvema prstoma ne izbere druge
celice in ne zapisuje podatkov. Preklic dotika ali tretji prst ne pustita
drsenja onemogočenega. Pomoč je drsna tudi pri 320 px in 2× besedilu.

## Preverjanje

63 ciljnih preizkusov PASS: 9 novih za dejanske večprstne poteze, meje
povečave, ohranjeno mesto pod prstoma, poravnavo oznak, drsenje/izbiro/vnos
po povečavi, preklic/tretji prst, pomoč SL/EN pri 320 px/2× in izračun
prikazanih formul. Vključeni tudi vsi obstoječi UI, formula in TSV preizkusi
preglednic, s postavitvami 320/390/1280, svetlo/temno in 2× besedilu.
Ciljna analiza brez ugotovitev. Dnevniki: build/qa/spreadsheet-zoom-final-tests.log
in build/qa/spreadsheet-zoom-analyze.log.
Vizualno pregledani tudi trije izrisi pri 360×780: 100 %, 50 % in odprta
pomoč s pravimi pisavami (build/qa/spreadsheet-zoom-*.png); ločen capture
preizkus PASS. To so widget izrisi s sintetičnimi podatki, ne fizični telefon.

Samo aplikacijski izvor: brez strežniških, shematskih, SDK, zaklenjenih
odvisnosti ali dovoljenjskih sprememb. Obstoječa 1.10.0+30 in njen izdajni
paket ostaneta nespremenjena; ta popravek potrebuje naslednjo aplikacijsko
izdajo. Ni nove gradnje, namestitve ali Google Play oddaje. Fizična povečava
na S25/iPhonu še ni potrjena.
