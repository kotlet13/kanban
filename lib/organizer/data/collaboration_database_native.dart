import 'dart:io';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'collaboration_database.dart';

Future<CollaborationDatabase> openCollaborationDatabase() async {
  final directory = await getApplicationDocumentsDirectory();
  return CollaborationDatabase(
    NativeDatabase.createInBackground(
      File('${directory.path}/organizer_shared_v1.sqlite'),
    ),
  );
}
