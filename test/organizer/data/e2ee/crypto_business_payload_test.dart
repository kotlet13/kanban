import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_payload.dart';
import 'package:kanban/organizer/domain/idea_models.dart';

void main() {
  test(
    'Idea semantic projection keeps encrypted extensions out of strict model',
    () {
      final board = IdeaBoard(
        id: '11111111-1111-4111-8111-111111111111',
        title: 'Fractional board',
        createdAt: DateTime.utc(2026, 10, 17),
        updatedAt: DateTime.utc(2026, 10, 17),
        elements: [
          IdeaElement(
            id: '22222222-2222-4222-8222-222222222222',
            kind: IdeaElementKind.stroke,
            x: 10.25,
            y: 11.75,
            width: 90.5,
            height: 50.25,
            points: const [IdeaPoint(0.1, 0.2), IdeaPoint(1.2, 2.3)],
          ),
        ],
      );
      final raw = Map<String, dynamic>.from(board.toJson());
      raw['assets'] = <Object?>[];
      raw['cryptoPayloadBlob'] = {'transport': 'already validated separately'};
      raw['future'] = {'scale': 0.125};
      final element = (raw['elements'] as List).single as Map;
      element['futureElement'] = {'rotation': 0.25};
      ((element['points'] as List).first as Map)['futurePoint'] = true;
      final before = jsonEncode(raw);
      final semantic = CryptoBusinessPayload.projection('content', 'idea', raw);
      expect(IdeaBoard.fromJson(semantic).elements.single.x, 10.25);
      expect(semantic.containsKey('assets'), isFalse);
      expect(semantic.containsKey('cryptoPayloadBlob'), isFalse);
      expect(
        ((semantic['elements'] as List).single as Map).containsKey(
          'futureElement',
        ),
        isFalse,
      );
      expect(jsonEncode(raw), before);
      element['width'] = -1;
      expect(
        () => CryptoBusinessPayload.projection('content', 'idea', raw),
        throwsA(anything),
      );
    },
  );
  test(
    'unrelated Idea title edit preserves future fields in non-ID points',
    () {
      final old = <String, dynamic>{
        'title': 'before',
        'elements': [
          {
            'id': 'stroke',
            'points': [
              {
                'x': 0.25,
                'y': 1.5,
                'future': {'pressure': 0.75},
              },
              {
                'x': 2.0,
                'y': 3.0,
                'future': {'pressure': 0.5},
              },
            ],
          },
        ],
      };
      final edited = {
        'title': 'after',
        'elements': [
          {
            'id': 'stroke',
            'points': [
              {'x': 0.25, 'y': 1.5},
              {'x': 2.0, 'y': 3.0},
            ],
          },
        ],
      };
      final before = jsonEncode(old);
      final merged = CryptoBusinessPayload.merge(old, edited) as Map;
      expect(merged['title'], 'after');
      expect(
        ((merged['elements'] as List).single as Map)['points'],
        ((old['elements'] as List).single as Map)['points'],
      );
      expect(jsonEncode(old), before);
    },
  );
  test('changed or reordered points never acquire invented old identity', () {
    final raw = [
      {'x': 1, 'y': 2, 'future': 'first'},
      {'x': 3, 'y': 4, 'future': 'second'},
    ];
    for (final edited in [
      [
        {'x': 3, 'y': 4},
        {'x': 1, 'y': 2},
      ],
      [
        {'x': 1, 'y': 9},
        {'x': 3, 'y': 4},
      ],
      [
        {'x': 1, 'y': 2},
      ],
      <Map<String, dynamic>>[],
    ]) {
      expect(CryptoBusinessPayload.merge(raw, edited), edited);
    }
    expect(CryptoBusinessPayload.merge([1, 2], [2, 1]), [2, 1]);
  });
}
