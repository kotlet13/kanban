import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/spreadsheet_tsv.dart';

void main() {
  test('empty clipboard, empty fields and trailing blank rows roundtrip', () {
    for (final rows in <List<List<String>>>[
      [],
      [
        [''],
      ],
      [
        ['', ''],
      ],
      [
        ['a'],
        [''],
        [''],
      ],
      [
        ['a', ''],
        ['', ''],
      ],
    ]) {
      expect(SpreadsheetTsv.decode(SpreadsheetTsv.encode(rows)), rows);
    }
  });
  test(
    'quotes, tabs, newlines and CRLF inside fields roundtrip byte for byte',
    () {
      final rows = [
        ['a\tb', 'say "hi"', 'line1\nline2', 'cr\rlf', 'both\r\nlines'],
        ['', '"', 'šč😀'],
      ];
      expect(SpreadsheetTsv.decode(SpreadsheetTsv.encode(rows)), rows);
    },
  );
  test('Excel quoted TSV accepts doubled quotes and terminal CRLF', () {
    expect(
      SpreadsheetTsv.decode('"a\tb"\t"say ""hi"""\r\n"line1\r\nline2"\t\r\n'),
      [
        ['a\tb', 'say "hi"'],
        ['line1\r\nline2', ''],
      ],
    );
  });
  test('unquoted empty columns and interior blank rows are retained', () {
    expect(SpreadsheetTsv.decode('a\t\n\nb\t'), [
      ['a', ''],
      [''],
      ['b', ''],
    ]);
    expect(SpreadsheetTsv.decode('\r\n\r\n'), [
      [''],
      [''],
    ]);
  });
  test(
    'unclosed quotes and characters after closing quotes reject entire payload',
    () {
      for (final text in [
        '"open',
        'good\t"open',
        '"closed"junk',
        'un"quoted',
        '"a" "b"',
      ]) {
        expect(() => SpreadsheetTsv.decode(text), throwsFormatException);
      }
    },
  );
  test('UTF8 cell limit enforced in encode and decode', () {
    final good = 'š' * 2048, bad = 'š' * 2049;
    expect(
      SpreadsheetTsv.decode(
        SpreadsheetTsv.encode([
          [good],
        ]),
      ),
      [
        [good],
      ],
    );
    expect(
      () => SpreadsheetTsv.encode([
        [bad],
      ]),
      throwsFormatException,
    );
    expect(() => SpreadsheetTsv.decode(bad), throwsFormatException);
  });
  test('cell count limit and total payload limit enforce bounded work', () {
    expect(
      () => SpreadsheetTsv.decode(List.filled(10001, '').join('\t')),
      throwsFormatException,
    );
    expect(
      () => SpreadsheetTsv.encode([List.filled(10001, '')]),
      throwsFormatException,
    );
    final rows = [List.filled(130, 'x' * 4096)];
    expect(() => SpreadsheetTsv.encode(rows), throwsFormatException);
    expect(
      () => SpreadsheetTsv.decode('x' * (512 * 1024 + 1)),
      throwsFormatException,
    );
  });
}
