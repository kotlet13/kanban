import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:kanban/organizer/platform/remote_push/system_push_display.dart';

void main() {
  const server = '11111111-1111-4111-a111-111111111111';
  const account = '22222222-2222-4222-a222-222222222222';
  Map<String, Object?> data({String id = '12'}) => {
    'type': 'familyhub.inbox.v1',
    'serverId': server,
    'accountId': account,
    'notificationId': id,
    'displayVersion': '2',
    'title': 'Dodano v Nakupi',
    'body': 'Korenje · Dom',
    'language': 'sl',
    'sound': '1',
  };
  test('topic display requires negotiated format and strict identity', () {
    final message = SystemPushMessage.tryParse(data())!;
    expect(message.sound, true);
    expect(message.title, 'Jivie');
    expect(message.body, 'V aplikaciji Jivie imate opomnik.');
    expect(
      SystemPushMessage.tryParse({...data(), 'displayVersion': '1'}),
      isNull,
    );
    expect(
      SystemPushMessage.tryParse({...data(), 'notificationId': 'bad'}),
      isNull,
    );
    expect(SystemPushMessage.tryParse({...data(), 'sound': 'true'}), isNull);
    expect(SystemPushMessage.tryParse({...data(), 'body': 'a' * 513}), isNull);
  });
  test('native grouping counts current topics once and isolates accounts', () {
    final message = SystemPushMessage.tryParse(data())!;
    final group = SystemPushGroup(message, [
      ActiveNotification(
        id: message.summaryId,
        groupKey: message.groupKey,
        title: 'Summary',
      ),
      ActiveNotification(
        id: message.id,
        groupKey: message.groupKey,
        title: 'Previous delivery',
      ),
      ActiveNotification(
        id: 99,
        groupKey: message.groupKey,
        title: 'Projekt Mansarda',
      ),
      const ActiveNotification(
        id: 98,
        groupKey: 'another-account',
        title: 'Private',
      ),
    ]);
    expect(group.lines, List.filled(2, 'V aplikaciji Jivie imate opomnik.'));
    expect(group.lines.join(), isNot(contains('Mansarda')));
    expect(group.label('sl'), 'Nova obvestila (2)');
    expect(group.label('en'), 'New notifications (2)');
    expect(message.id, isNot(message.summaryId));
    expect(message.id, greaterThanOrEqualTo(0x40000000));
    expect(SystemPushMessage.tryParse(data(id: '13'))!.id, isNot(message.id));
    expect(message.payload(summary: true), contains('"summary":true'));
  });
}
