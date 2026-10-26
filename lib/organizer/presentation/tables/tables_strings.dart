import 'package:flutter/widgets.dart';

class TablesStrings {
  TablesStrings(this.sl);
  final bool sl;
  static TablesStrings of(BuildContext context) =>
      TablesStrings(Localizations.localeOf(context).languageCode == 'sl');
  String pick(String en, String si) => sl ? si : en;
  String get tables => pick('Tables', 'Preglednice');
  String get newTable => pick('New table', 'Nova preglednica');
  String get title => pick('Title', 'Naslov');
  String get cancel => pick('Cancel', 'Prekliči');
  String get create => pick('Create', 'Ustvari');
  String get apply => pick('Apply', 'Uporabi');
  String get save => pick('Save', 'Shrani');
  String get finish =>
      pick('Save and finish editing', 'Shrani in končaj urejanje');
  String get report => pick('Report content', 'Prijavi vsebino');
  String get more => pick('More', 'Več');
  String get rename => pick('Rename table', 'Preimenuj preglednico');
  String get delete => pick('Delete table', 'Izbriši preglednico');
  String get deleteConfirm => pick(
    'Delete this table and its cells?',
    'Izbrišem to preglednico in njene celice?',
  );
  String get refresh => pick('Refresh', 'Osveži');
  String get edit => pick('Edit table', 'Uredi preglednico');
  String get revision => pick('Revision', 'Revizija');
  String get empty => pick(
    'Create a table for text, numbers and formulas.',
    'Ustvarite preglednico za besedilo, številke in formule.',
  );
  String get offline => pick(
    'Offline: saved tables are available to view. Editing needs a connection.',
    'Brez povezave: shranjene preglednice si lahko ogledate. Urejanje potrebuje povezavo.',
  );
  String get missingTable => pick(
    'This table is no longer available. Your draft stays on this device.',
    'Ta preglednica ni več na voljo. Osnutek ostane na tej napravi.',
  );
  String get accessLost => pick(
    'This view is no longer current. Return to the space and reopen it. Your draft stays on this device.',
    'Ta pogled ni več aktualen. Vrni se v prostor in ga znova odpri. Osnutek ostane na tej napravi.',
  );
  String get failed => pick(
    'Could not load or save. Try again.',
    'Nalaganje ali shranjevanje ni uspelo. Poskusite znova.',
  );
  String get lockedOrFailed => pick(
    'Editing is unavailable. Another person may be editing this table.',
    'Urejanje ni na voljo. Preglednico morda ureja nekdo drug.',
  );
  String locked(String name) => pick(
    '${name.isEmpty ? 'Another person' : name} is editing. You can view this table.',
    '${name.isEmpty ? 'Drug član' : name} ureja preglednico. Lahko si jo ogledate.',
  );
  String get editing => pick(
    'You are editing. Others can view until you finish.',
    'Urejate vi. Drugi si lahko ogledajo preglednico, dokler ne končate.',
  );
  String get lost => pick(
    'Editing stopped. Your draft stays on this device. Reconnect and acquire editing to continue.',
    'Urejanje je ustavljeno. Osnutek ostane na tej napravi. Za nadaljevanje znova pridobite urejanje.',
  );
  String get localDraftOnly => pick(
    'Sharing is unavailable. You can finish this draft on this device. Shared changes cannot be saved now.',
    'Deljenje ni na voljo. Osnutek lahko dokončate na tej napravi. Sprememb trenutno ni mogoče shraniti v skupno preglednico.',
  );
  String get keepDraftAndClose =>
      pick('Keep draft and close', 'Ohrani osnutek in zapri');
  String get recovery => pick(
    'A draft from this device is available.',
    'Na tej napravi je na voljo osnutek.',
  );
  String get restore => pick('Restore draft', 'Obnovi osnutek');
  String get copyDraft => pick('Copy draft', 'Kopiraj osnutek');
  String get useSaved =>
      pick('Use saved version', 'Uporabi shranjeno različico');
  String get discardDraft => pick(
    'Discard the draft on this device and continue with the saved table?',
    'Zavržem osnutek na tej napravi in nadaljujem s shranjeno preglednico?',
  );
  String get draftCopied => pick(
    'The table changed. Your earlier draft was copied with cell addresses for recovery.',
    'Preglednica se je spremenila. Prejšnji osnutek je kopiran z naslovi celic za obnovo.',
  );
  String get draftFailed => pick(
    'The draft could not be stored. Keep this table open and try saving again.',
    'Osnutka ni bilo mogoče shraniti. Preglednico pustite odprto in znova poskusite shraniti.',
  );
  String get saved => pick('Saved', 'Shranjeno');
  String get limit => pick(
    'This input is too large. Use up to 10,000 filled cells, 4 KiB per cell and 512 KiB per table.',
    'Vnos je prevelik. Uporabite do 10.000 izpolnjenih celic, 4 KiB na celico in 512 KiB na preglednico.',
  );
  String get input =>
      pick('Cell value or formula', 'Vrednost celice ali formula');
  String get copy => pick('Copy selected cells', 'Kopiraj izbrane celice');
  String get invalidPaste => pick(
    'Clipboard text is not valid tab-separated data. Nothing was pasted.',
    'Besedilo v odložišču ni veljavno ločeno s tabulatorji. Nič ni prilepljeno.',
  );
  String get paste => pick('Paste cells', 'Prilepi celice');
  String get wider => pick('Wider columns', 'Širši stolpci');
  String get narrower => pick('Narrower columns', 'Ožji stolpci');
  String get go => pick('Go to cell', 'Pojdi v celico');
  String get zoomOut => pick('Zoom out', 'Pomanjšaj tabelo');
  String get zoomIn => pick('Zoom in', 'Povečaj tabelo');
  String get help => pick('Formulas and help', 'Formule in pomoč');
  String get close => pick('Close', 'Zapri');
  String get helpInput => pick(
    'Select a cell, then enter text, a number or a formula in the field above the table. Start formulas with =. Cell references use addresses such as A1 or B2.',
    'Izberite celico in v polje nad tabelo vnesite besedilo, številko ali formulo. Formule začnite z =. Na druge celice se sklicujete z naslovi, kot sta A1 ali B2.',
  );
  String get helpFunctions => pick('Supported functions', 'Podprte funkcije');
  String get sum => pick('Sum of numbers', 'Seštevek števil');
  String get average => pick('Average of numbers', 'Povprečje števil');
  String get count =>
      pick('Count of numeric cells', 'Število celic s številkami');
  String get minimum => pick('Smallest number', 'Najmanjše število');
  String get maximum => pick('Largest number', 'Največje število');
  String get helpArithmetic => pick(
    'Use +, -, *, / and parentheses, for example =(A1+B1)*2. A1:A10 means cells A1 through A10. With decimal commas, separate arguments with a semicolon: =SUM(1,5;2,5). Function names stay in English.',
    'Uporabite +, -, *, / in oklepaje, na primer =(A1+B1)*2. A1:A10 pomeni celice od A1 do A10. Pri decimalni vejici argumente ločite s podpičjem: =SUM(1,5;2,5). Imena funkcij ostanejo angleška.',
  );
  String get helpZoom => pick(
    'Pinch with two fingers over the cells to zoom between 50% and 200%. You can also use the − and + buttons in the toolbar (swipe it sideways to see more). Tap the percentage to reset to 100%. Only the table changes size.',
    'Z dvema prstoma na celicah povečajte ali pomanjšajte tabelo med 50 % in 200 %. Uporabite lahko tudi gumba − in + v orodni vrstici (za več možnosti jo podrsajte vstran). Dotik odstotka povrne 100 %. Velikost se spremeni samo tabeli.',
  );
}
