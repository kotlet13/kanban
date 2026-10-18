import '../../domain/idea_models.dart';
import 'crypto_business_payload.dart';
import 'crypto_migration_file_object.dart';
import 'crypto_migration_witness.dart';
import 'crypto_record_address.dart';

Map<String, IdeaAsset> cryptoMigrationIdeaAssets(Map<String, dynamic> raw) {
  final board = IdeaBoard.fromJson(
    CryptoBusinessPayload.projection('content', 'idea', raw),
  );
  final out = <String, IdeaAsset>{};
  for (final asset in board.assets) {
    final prior = out[asset.sha256];
    if (prior != null &&
        (prior.mime != asset.mime ||
            prior.size != asset.size ||
            prior.width != asset.width ||
            prior.height != asset.height)) {
      throw const FormatException('crypto_migration_idea_asset_metadata');
    }
    out[asset.sha256] = asset;
  }
  return out;
}

/// Deterministic technical projection alongside the unchanged original raw.
/// The full FILE verifier independently resolves each file's captured binding.
Map<String, dynamic> decorateCryptoMigrationIdea(
  Map<String, dynamic> raw,
  List objects,
  CryptoMigrationWitnessContext boardContext,
) {
  if (raw.containsKey('assets')) {
    throw const FormatException('crypto_migration_idea_reserved_field');
  }
  final expected = cryptoMigrationIdeaAssets(raw),
      hashes = expected.keys.toList()..sort();
  if (objects.length != hashes.length || objects.length > 20) {
    throw const FormatException('crypto_migration_idea_asset_coverage');
  }
  final bindings = <String>{},
      ids = <String>{},
      assets = <Map<String, dynamic>>[];
  for (var i = 0; i < hashes.length; i++) {
    final object = objects[i];
    if (object is! Map ||
        !isCryptoCanonicalUuid(object['sourceBindingId']) ||
        !bindings.add(object['sourceBindingId']) ||
        object['kind'] != 'ideaAsset' ||
        object['plainSize'] != expected[hashes[i]]!.size) {
      throw const FormatException('crypto_migration_idea_asset_binding');
    }
    final context = CryptoMigrationWitnessContext({
      ...boardContext.value,
      'bindingId': object['sourceBindingId'],
    });
    final d = CryptoMigrationFileObject.descriptor(context, object);
    if (!ids.add(d['id'])) {
      throw const FormatException('crypto_migration_idea_asset_binding');
    }
    assets.add({...expected[hashes[i]]!.toJson(), 'cryptoBlob': d});
  }
  return {...raw, 'assets': assets};
}
