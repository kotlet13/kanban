import 'dart:math' as math;
import 'spreadsheet_models.dart';

class SpreadsheetValue {
  const SpreadsheetValue._(this.number, this.text, this.error);
  const SpreadsheetValue.number(double number) : this._(number, null, null);
  const SpreadsheetValue.text(String text) : this._(null, text, null);
  const SpreadsheetValue.error(String error) : this._(null, null, error);
  final double? number;
  final String? text, error;
  String get display {
    if (error != null) return error!;
    if (number == null) return text ?? '';
    if (number == 0) return '0';
    if (number == number!.truncateToDouble() && number!.abs() < 1e15) {
      return number!.toInt().toString();
    }
    final parts = number!.toStringAsPrecision(12).split('e');
    parts[0] = parts[0].replaceFirst(RegExp(r'\.?0+$'), '');
    return parts.join('e');
  }
}

/// Deterministic, bounded parser: no code evaluation or network functions.
/// Decimal commas are accepted when semicolon argument separators are used.
class SpreadsheetCalculator {
  SpreadsheetCalculator(Map<String, String> cells)
    : cells = Map.unmodifiable(cells);
  final Map<String, String> cells;
  final _cache = <String, SpreadsheetValue>{};
  final _active = <String>{};
  int _budget = 0;
  SpreadsheetValue evaluate(String address) {
    _budget = 20000;
    return _cell(address.toUpperCase(), 0);
  }

  SpreadsheetValue _cell(String address, int depth) {
    if (--_budget < 0 || depth > 100) {
      return const SpreadsheetValue.error('#LIMIT!');
    }
    if (SpreadsheetAddress.parse(address) == null) {
      return const SpreadsheetValue.error('#REF!');
    }
    if (_active.contains(address)) {
      return const SpreadsheetValue.error('#CYCLE!');
    }
    if (_cache.containsKey(address)) return _cache[address]!;
    final raw = cells[address] ?? '';
    if (!raw.startsWith('=')) {
      final number = double.tryParse(raw.trim().replaceAll(',', '.'));
      return _cache[address] = number != null && number.isFinite
          ? SpreadsheetValue.number(number)
          : SpreadsheetValue.text(raw.startsWith("'") ? raw.substring(1) : raw);
    }
    if (raw.length > 8192) return const SpreadsheetValue.error('#LIMIT!');
    _active.add(address);
    SpreadsheetValue result;
    try {
      final parser = _FormulaParser(
        raw.substring(1),
        (ref) => _cell(ref, depth + 1),
        () {
          if (--_budget < 0) throw const _FormulaError('#LIMIT!');
        },
      );
      result = SpreadsheetValue.number(parser.parse());
    } on _FormulaError catch (error) {
      result = SpreadsheetValue.error(error.code);
    } finally {
      _active.remove(address);
    }
    if (result.error != '#LIMIT!') _cache[address] = result;
    return result;
  }
}

class _FormulaError implements Exception {
  const _FormulaError(this.code);
  final String code;
}

class _FormulaParser {
  _FormulaParser(String source, this.resolve, this.tick)
    : source =
          (source.contains(';') || !RegExp(r'[A-Za-z]+\s*\(').hasMatch(source))
          ? source.replaceAll(RegExp(r'(?<=\d),(?=\d)'), '.')
          : source;
  final String source;
  final SpreadsheetValue Function(String) resolve;
  final void Function() tick;
  int position = 0, nesting = 0;
  double parse() {
    final result = expression();
    space();
    if (position != source.length) throw const _FormulaError('#FORMULA!');
    return checked(result);
  }

  void space() {
    while (position < source.length && source[position].trim().isEmpty) {
      position++;
    }
  }

  bool take(String token) {
    space();
    if (source.startsWith(token, position)) {
      position += token.length;
      return true;
    }
    return false;
  }

  double checked(double n) {
    if (!n.isFinite) throw const _FormulaError('#NUM!');
    return n;
  }

  double expression() {
    tick();
    var value = product();
    while (true) {
      if (take('+')) {
        value = checked(value + product());
      } else if (take('-')) {
        value = checked(value - product());
      } else {
        return value;
      }
    }
  }

  double product() {
    var value = atom();
    while (true) {
      if (take('*')) {
        value = checked(value * atom());
      } else if (take('/')) {
        final divisor = atom();
        if (divisor == 0) throw const _FormulaError('#DIV/0!');
        value = checked(value / divisor);
      } else {
        return value;
      }
    }
  }

  double atom() {
    tick();
    if (++nesting > 100) throw const _FormulaError('#LIMIT!');
    try {
      if (take('+')) return atom();
      if (take('-')) return -atom();
      if (take('(')) {
        final result = expression();
        if (!take(')')) throw const _FormulaError('#FORMULA!');
        return result;
      }
      space();
      final tail = source.substring(position);
      final numeric = RegExp(
        r'^(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?',
      ).firstMatch(tail);
      if (numeric != null) {
        position += numeric[0]!.length;
        return checked(double.parse(numeric[0]!));
      }
      final reference = RegExp(r'^\$?[A-Za-z]{1,3}\$?[0-9]+').firstMatch(tail);
      if (reference != null) {
        position += reference[0]!.length;
        return cell(reference[0]!, false) ?? 0;
      }
      final function = RegExp(r'^[A-Za-z]+').firstMatch(tail);
      if (function != null) {
        position += function[0]!.length;
        return aggregate(function[0]!.toUpperCase());
      }
      throw const _FormulaError('#FORMULA!');
    } finally {
      nesting--;
    }
  }

  double? cell(String reference, bool ignoreText) {
    final address = SpreadsheetAddress.parse(reference);
    if (address == null) throw const _FormulaError('#REF!');
    final value = resolve(address.label);
    if (value.error != null) throw _FormulaError(value.error!);
    if (value.number != null) return value.number;
    if (value.text == '') return ignoreText ? null : 0;
    if (ignoreText) return null;
    throw const _FormulaError('#VALUE!');
  }

  double aggregate(String name) {
    if (!{'SUM', 'AVERAGE', 'COUNT', 'MIN', 'MAX'}.contains(name)) {
      throw const _FormulaError('#NAME?');
    }
    if (!take('(')) throw const _FormulaError('#FORMULA!');
    final values = <double>[];
    if (!take(')')) {
      do {
        tick();
        space();
        final start = position;
        final first = RegExp(
          r'^\$?[A-Za-z]{1,3}\$?[0-9]+',
        ).firstMatch(source.substring(position));
        if (first != null) {
          position += first[0]!.length;
          if (take(':')) {
            space();
            final second = RegExp(
              r'^\$?[A-Za-z]{1,3}\$?[0-9]+',
            ).firstMatch(source.substring(position));
            if (second == null) throw const _FormulaError('#REF!');
            position += second[0]!.length;
            final a = SpreadsheetAddress.parse(first[0]!),
                b = SpreadsheetAddress.parse(second[0]!);
            if (a == null || b == null) throw const _FormulaError('#REF!');
            final top = math.min(a.row, b.row), bottom = math.max(a.row, b.row);
            final left = math.min(a.column, b.column),
                right = math.max(a.column, b.column);
            if ((bottom - top + 1) * (right - left + 1) > 10000) {
              throw const _FormulaError('#LIMIT!');
            }
            for (var r = top; r <= bottom; r++) {
              for (var c = left; c <= right; c++) {
                tick();
                final n = cell(SpreadsheetAddress(r, c).label, true);
                if (n != null) values.add(n);
              }
            }
          } else {
            space();
            if (position == source.length || ',;)'.contains(source[position])) {
              final n = cell(first[0]!, true);
              if (n != null) values.add(n);
            } else {
              position = start;
              values.add(expression());
            }
          }
        } else {
          values.add(expression());
        }
      } while (take(',') || take(';'));
      if (!take(')')) throw const _FormulaError('#FORMULA!');
    }
    return switch (name) {
      'COUNT' => values.length.toDouble(),
      'SUM' => checked(values.fold<double>(0, (a, b) => a + b)),
      'AVERAGE' =>
        values.isEmpty
            ? throw const _FormulaError('#DIV/0!')
            : checked(values.reduce((a, b) => a + b) / values.length),
      'MIN' => values.isEmpty ? 0 : values.reduce(math.min),
      'MAX' => values.isEmpty ? 0 : values.reduce(math.max),
      _ => throw const _FormulaError('#NAME?'),
    };
  }
}
