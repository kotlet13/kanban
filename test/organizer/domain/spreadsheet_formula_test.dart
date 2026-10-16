import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/domain/spreadsheet_formula.dart';
import 'package:kanban/organizer/domain/spreadsheet_models.dart';

void main() {
  String value(String raw, [Map<String, String> cells = const {}]) =>
      SpreadsheetCalculator({...cells, 'ZZ1': raw}).evaluate('ZZ1').display;
  test('text, numbers, escape and empty remain distinct', () {
    expect(value('Hello'), 'Hello');
    expect(value('1,25'), '1.25');
    expect(value("'=SUM(A1:A2)"), '=SUM(A1:A2)');
    expect(value(''), '');
  });
  test('basic arithmetic precedence, unary signs and exponents', () {
    expect(value('=2+3*4'), '14');
    expect(value('=(2+3)*4'), '20');
    expect(value('=-2*-3+1'), '7');
    expect(value('=1e2/4'), '25');
    expect(value('=1,5+2'), '3.5');
  });
  test('SL decimals and semicolon arguments; comma arguments', () {
    expect(value('=SUM(1,5;2,5)'), '4');
    expect(value('=SUM(1,2,3)'), '6');
  });
  test('references, referenced formulas and absolute refs', () {
    expect(value(r'=A1+$B$1', {'A1': '2', 'B1': '=A1*3'}), '8');
  });
  test('aggregates ignore range text and blanks but count numeric zero', () {
    const cells = {'A1': '2', 'A2': 'words', 'A3': '0', 'B1': '=A1*3'};
    expect(value('=SUM(A1:B3)', cells), '8');
    expect(value('=COUNT(A1:B3)', cells), '3');
    expect(value('=AVERAGE(A1:B3)', cells), '2.66666666667');
    expect(value('=MIN(A1:B3)', cells), '0');
    expect(value('=MAX(A1:B3)', cells), '6');
    expect(value('=SUM(B3:A1)', cells), '8');
  });
  test('errors propagate through refs and ranges', () {
    expect(value('=1/0'), '#DIV/0!');
    expect(value('=A1+1', {'A1': 'words'}), '#VALUE!');
    expect(value('=SUM(A1:A2)', {'A1': '=1/0'}), '#DIV/0!');
    expect(value('=AVERAGE(A1:A2)'), '#DIV/0!');
    expect(value('=NOPE(1)'), '#NAME?');
    expect(value('=SUM(1,)'), '#FORMULA!');
    expect(value('=1+'), '#FORMULA!');
    expect(value('=2(3)'), '#FORMULA!');
    expect(value('=1e309'), '#NUM!');
  });
  test('self and indirect cycles are stable', () {
    expect(value('=ZZ1'), '#CYCLE!');
    expect(value('=A1', {'A1': '=B1', 'B1': '=ZZ1'}), '#CYCLE!');
    expect(value('=SUM(ZZ1:ZZ2)'), '#CYCLE!');
  });
  test('backend coordinates and work bounds', () {
    expect(SpreadsheetAddress.parse('ZZZ100000')!.label, 'ZZZ100000');
    expect(SpreadsheetAddress.parse('AAAA1'), isNull);
    expect(SpreadsheetAddress.parse('A100001'), isNull);
    expect(value('=A0'), '#REF!');
    expect(value('=ZZZ100001'), '#REF!');
    expect(value('=SUM(A1:ZZZ100000)'), '#LIMIT!');
    expect(value('=${'(' * 110}1${')' * 110}'), '#LIMIT!');
  });
  test('depth budget does not poison independent evaluation cache', () {
    final cells = {
      for (var i = 1; i <= 110; i++) 'A$i': i == 110 ? '1' : '=A${i + 1}',
    };
    final calculator = SpreadsheetCalculator(cells);
    expect(calculator.evaluate('A1').error, '#LIMIT!');
    expect(calculator.evaluate('A109').display, '1');
  });
  test('scientific display preserves exponent zeros', () {
    expect(value('1e20'), '1e+20');
    expect(value('0.00000000000000000001'), '1e-20');
  });
  test('wire and draft roundtrip preserve raw formulas', () {
    final document = SpreadsheetDocument(
      id: 't',
      scopeId: 's',
      title: 'Plan',
      cells: {'A1': '=SUM(B1:B3)'},
      revision: 7,
      updatedAt: 10,
    );
    expect(
      SpreadsheetDocument.fromJson(document.toJson()).cells,
      document.cells,
    );
    final draft = SpreadsheetDraft(
      tableId: 't',
      baseRevision: 7,
      title: 'Draft',
      cells: {'A1': '1'},
      updatedAt: 11,
    );
    expect(SpreadsheetDraft.fromJson(draft.toJson()).baseRevision, 7);
  });
}
