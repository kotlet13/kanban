import 'crypto_record_address.dart';

/// Authenticated server display metadata, never a membership or identity proof.
Map<String, Map<String, dynamic>> parseCryptoMemberLabels(
  Map<String, dynamic> response, {
  required String serverId,
  required String accountId,
  required String deviceId,
  required String scopeId,
  required String headHash,
  required List<String> requested,
}) {
  if (response['version'] != 1 ||
      response['serverId'] != serverId ||
      response['accountId'] != accountId ||
      response['deviceId'] != deviceId ||
      response['scopeId'] != scopeId ||
      response['headHash'] != headHash ||
      response['accountIds'] is! List ||
      (response['accountIds'] as List).length != requested.length ||
      response['labels'] is! List ||
      (response['labels'] as List).length > requested.length) {
    throw const FormatException('crypto_member_labels_binding');
  }
  for (var index = 0; index < requested.length; index++) {
    if (response['accountIds'][index] != requested[index]) {
      throw const FormatException('crypto_member_labels_binding');
    }
  }
  final labels = <String, Map<String, dynamic>>{};
  String? previous;
  for (final row in response['labels'] as List) {
    if (row is! Map ||
        !isCryptoCanonicalUuid(row['accountId']) ||
        !requested.contains(row['accountId']) ||
        previous != null &&
            (row['accountId'] as String).compareTo(previous) <= 0 ||
        row['userId'] is! int ||
        row['userId'] <= 0 ||
        row['username'] is! String ||
        (row['username'] as String).isEmpty ||
        (row['username'] as String).length > 100 ||
        row['displayName'] is! String ||
        (row['displayName'] as String).length > 200 ||
        (row['username'] as String).contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        (row['displayName'] as String).contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const FormatException('crypto_member_labels_row');
    }
    previous = row['accountId'] as String;
    // Copy only display fields. Extra fields cannot override signed roles.
    labels[previous] = {
      'userId': row['userId'],
      'username': row['username'],
      'displayName': row['displayName'],
    };
  }
  return labels;
}
