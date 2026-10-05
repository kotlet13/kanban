export 'collaboration_database_stub.dart'
    if (dart.library.io) 'collaboration_database_native.dart'
    if (dart.library.js_interop) 'collaboration_database_web.dart';
