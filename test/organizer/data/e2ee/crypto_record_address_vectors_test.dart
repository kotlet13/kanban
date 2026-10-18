import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';

void main() {
  final vectors =
      jsonDecode(
            File(
              'server/tests/fixtures/e2ee-record-address-v2.json',
            ).readAsStringSync(),
          )
          as List;
  for (final raw in vectors) {
    final vector = raw as Map, context = vector['context'] as Map;
    test('PHP/Dart exact record address ${vector['type']}', () {
      final address = CryptoRecordAddress.forType(
        serverId: context['serverId'],
        scopeId: context['scopeId'],
        type: vector['type'],
        canonicalId: context['canonicalId'],
      );
      expect(address.sourceKind, context['sourceKind']);
      expect(address.domain, context['domain']);
      expect(address.wireId, vector['wireId']);
      expect(isCryptoWireRecordId(address.wireId), isTrue);
      expect(
        () => CryptoRecordAddress.forType(
          serverId: context['serverId'],
          scopeId: context['scopeId'],
          type: vector['type'],
          canonicalId: context['canonicalId'],
          domain: context['domain'] == 'finance' ? 'content' : 'finance',
        ),
        throwsFormatException,
      );
    });
  }
  for (final invalid in [
    '33333333-3333-8333-8333-333333333333',
    '33333333-3333-0333-8333-333333333333',
    '33333333-3333-4333-7333-333333333333',
  ]) {
    test('canonical source rejects invalid version or variant $invalid', () {
      expect(
        () => CryptoRecordAddress.forType(
          serverId: '11111111-1111-4111-8111-111111111111',
          scopeId: '22222222-2222-4222-8222-222222222222',
          type: 'task',
          canonicalId: invalid,
        ),
        throwsFormatException,
      );
    });
  }
}
