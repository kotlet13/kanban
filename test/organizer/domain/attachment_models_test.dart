import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/attachment_models.dart';

AttachmentMetadata fixtureAttachment({
  String id = 'attachment-1',
  String scopeId = 'scope-1',
}) => AttachmentMetadata(
  id: id,
  scopeId: scopeId,
  targetType: 'scope',
  targetId: 'scope-1',
  name: 'Načrt.pdf',
  mime: 'application/pdf',
  size: 4,
  sha256: List.filled(64, 'a').join(),
  createdAt: 1780000000,
  complete: true,
  offset: 4,
);

void main() {
  test('attachment metadata round trip preserves explicit target', () {
    final attachment = fixtureAttachment();
    final restored = AttachmentMetadata.fromJson(attachment.toJson());
    expect(restored.toJson(), attachment.toJson());
    expect(
      restored.target,
      const AttachmentTarget(
        scopeId: 'scope-1',
        targetType: 'scope',
        targetId: 'scope-1',
      ),
    );
  });

  test('allows every supported extension and matching MIME', () {
    for (final pair in attachmentMimeByExtension.entries) {
      expect(
        validateAttachmentFile(
          'Račun.${pair.key.toUpperCase()}',
          4,
          mime: pair.value,
        ),
        pair.value,
      );
    }
  });

  test('rejects dangerous names, unsupported types and MIME mismatch', () {
    for (final name in [
      '../a.pdf',
      r'a\b.pdf',
      'a/b.pdf',
      '.a.pdf',
      'a.pdf ',
      ' a.pdf',
      'a.pdf\u0000',
      'a\u202epdf.exe',
      'a.exe',
      'a.pdf.exe',
      'a:pdf.pdf',
      'a',
      'a.',
    ]) {
      expect(
        () => validateAttachmentFile(name, 4),
        throwsFormatException,
        reason: name,
      );
    }
    expect(
      () => validateAttachmentFile('a.pdf', 4, mime: 'text/plain'),
      throwsFormatException,
    );
    expect(
      () => validateAttachmentFile('${List.filled(240, 'č').join()}.pdf', 4),
      throwsFormatException,
    );
  });

  test('size must be positive and bounded before any upload', () {
    expect(() => validateAttachmentFile('a.pdf', 0), throwsFormatException);
    expect(
      () => validateAttachmentFile('a.pdf', attachmentMaxBytes + 1),
      throwsFormatException,
    );
    expect(
      validateAttachmentFile('a.pdf', attachmentMaxBytes),
      'application/pdf',
    );
  });

  test('rejects invalid integrity and progress metadata', () {
    final original = fixtureAttachment().toJson();
    for (final change in [
      {'sha256': 'bad'},
      {'offset': 5},
      {'offset': -1},
      {'offset': 0},
      {'createdAt': -1},
      {'targetType': 'other'},
      {'scopeId': ''},
      {'id': '../file'},
      {'mime': 'application/javascript'},
    ]) {
      expect(
        () => AttachmentMetadata.fromJson({...original, ...change}),
        throwsFormatException,
      );
    }
    expect(
      AttachmentMetadata.fromJson({
        ...original,
        'complete': false,
        'offset': 0,
      }).complete,
      false,
    );
  });

  test('byte limits keep chunk bound below full attachment bound', () {
    expect(attachmentChunkBytes, 256 * 1024);
    expect(attachmentScopeMaxBytes, 256 * 1024 * 1024);
    expect(Uint8List(4).length, fixtureAttachment().size);
  });
}
