import 'package:flutter/widgets.dart';

/// Module-local strings until the next generated localization pass.
class AttachmentStrings {
  AttachmentStrings(BuildContext context)
    : _sl = Localizations.localeOf(context).languageCode == 'sl';
  final bool _sl;
  String get title => _sl ? 'Priloge' : 'Attachments';
  String get add => _sl ? 'Dodaj prilogo' : 'Add attachment';
  String get refresh => _sl ? 'Osveži' : 'Refresh';
  String get empty => _sl ? 'Tu še ni prilog.' : 'No attachments yet.';
  String get supported => _sl
      ? 'PDF, dokumenti, preglednice, besedilo ter JPG/PNG. Največ 20 MiB na datoteko; 256 MiB na prostor.'
      : 'PDF, documents, spreadsheets, text and JPG/PNG. Up to 20 MiB per file; 256 MiB per space.';
  String get readOnly => _sl
      ? 'Priloge lahko prenesete. Za dodajanje in brisanje potrebujete pravico urejanja.'
      : 'You can download attachments. Adding and deleting requires edit access.';
  String get offline => _sl
      ? 'Brez povezave: na voljo so le že prenesene priloge. Za dodajanje ali brisanje se povežite.'
      : 'Offline: only previously downloaded attachments are available. Connect to add or delete files.';
  String get stale => _sl
      ? 'Dostop ali račun se je spremenil. Znova odprite priloge.'
      : 'Access or account changed. Reopen attachments.';
  String get actions => _sl ? 'Dejanja priloge' : 'Attachment actions';
  String get report => _sl ? 'Prijavi prilogo' : 'Report attachment';
  String get reportError => _sl
      ? 'Prijave ni bilo mogoče odpreti.'
      : 'Could not open the report form.';
  String get save => _sl ? 'Shrani kopijo' : 'Save a copy';
  String get delete => _sl ? 'Izbriši' : 'Delete';
  String get cancel => _sl ? 'Prekliči' : 'Cancel';
  String get retry => _sl ? 'Poskusi znova' : 'Retry';
  String get deleteTitle => _sl ? 'Izbrišem prilogo?' : 'Delete attachment?';
  String deleteBody(String name) => _sl
      ? '»$name« bo odstranjena za vse člane. Že shranjene kopije ostanejo.'
      : '“$name” will be removed for all members. Copies already saved will remain.';
  String get pending => _sl ? 'Nalaganje ni dokončano' : 'Upload incomplete';
  String get cached => _sl ? 'Na voljo brez povezave' : 'Available offline';
  String get notCached =>
      _sl ? 'Za prenos je potrebna povezava' : 'Connect to download';
  String get loadError =>
      _sl ? 'Prilog ni bilo mogoče naložiti.' : 'Could not load attachments.';
  String get pickError => _sl
      ? 'Datoteke ni mogoče prebrati. Izberite podprto datoteko z veljavnim imenom, veliko največ 20 MiB.'
      : 'Could not read this file. Choose a supported file with a valid name, up to 20 MiB.';
  String get uploadError => _sl
      ? 'Priloge ni bilo mogoče dodati. Preverite povezavo, pravice in prostor za datoteke.'
      : 'Could not add attachment. Check your connection, access and file storage.';
  String get downloadError => _sl
      ? 'Kopije ni bilo mogoče shraniti. Preverite povezavo in dostop.'
      : 'Could not save a copy. Check your connection and access.';
  String get deleteError => _sl
      ? 'Priloge ni bilo mogoče izbrisati. Preverite povezavo in pravice.'
      : 'Could not delete attachment. Check your connection and access.';
  String get saved => _sl ? 'Kopija je shranjena.' : 'Copy saved.';
  String get downloadStarted =>
      _sl ? 'Prenos se je začel.' : 'Download started.';
  String get uploading => _sl ? 'Dodajanje priloge' : 'Uploading attachment';
  String get downloading =>
      _sl ? 'Prenašanje priloge' : 'Downloading attachment';
  String get deleting => _sl ? 'Brisanje priloge' : 'Deleting attachment';
  String get picking => _sl ? 'Izbira datoteke' : 'Choosing a file';
}
