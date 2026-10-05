import '../../models/kanboard_models.dart';

/// Legacy credential sharing is intentionally disabled; project invitations use
/// a separate expiring token protocol instead of durable account credentials.
String buildCredentialsTransferPayload(KanboardCredentials credentials) =>
    throw UnsupportedError('Sharing account credentials is disabled.');

KanboardCredentials parseCredentialsTransferPayload(String rawValue) =>
    throw UnsupportedError('Importing shared account credentials is disabled.');
