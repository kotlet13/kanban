import 'dart:convert';

/// Lossless spreadsheet clipboard data. Empty fields are quoted on encoding,
/// allowing trailing blank rows to survive while accepting Excel's terminal
/// CRLF as a record terminator. Quoted CR/LF/tab characters remain cell text.
class SpreadsheetTsv {
  static const maxBytes = 512 * 1024, maxCells = 10000, maxCellBytes = 4096;
  static const limitError = 'tsv_limit';
  static String encode(Iterable<Iterable<String>> rows) {
    final output = StringBuffer();
    var bytes = 0, count = 0, rowIndex = 0;
    void append(String value) {
      bytes += utf8.encode(value).length;
      if (bytes > maxBytes) throw const FormatException(limitError);
      output.write(value);
    }

    for (final input in rows) {
      if (rowIndex++ > 0) append('\r\n');
      var column = 0;
      for (final value in input) {
        if (++count > maxCells ||
            value.length > maxCellBytes ||
            utf8.encode(value).length > maxCellBytes) {
          throw const FormatException(limitError);
        }
        if (column++ > 0) append('\t');
        append(
          value.isEmpty || value.contains(RegExp('["\\t\\r\\n]'))
              ? '"${value.replaceAll('"', '""')}"'
              : value,
        );
      }
      if (column == 0) {
        if (++count > maxCells) throw const FormatException(limitError);
        append('""');
      }
    }
    return output.toString();
  }

  static List<List<String>> decode(String text) {
    if (text.length > maxBytes || utf8.encode(text).length > maxBytes) {
      throw const FormatException(limitError);
    }
    if (text.isEmpty) return const [];
    final rows = <List<String>>[];
    var row = <String>[], field = StringBuffer();
    var quoted = false, closedQuote = false, atStart = true, endedRow = false;
    var count = 0;
    void endField() {
      final value = field.toString();
      if (++count > maxCells ||
          value.length > maxCellBytes ||
          utf8.encode(value).length > maxCellBytes) {
        throw const FormatException(limitError);
      }
      row.add(value);
      field = StringBuffer();
      atStart = true;
      closedQuote = false;
    }

    void endRow() {
      rows.add(List.unmodifiable(row));
      row = <String>[];
    }

    for (var i = 0; i < text.length; i++) {
      final character = text[i];
      if (quoted) {
        if (character == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
            closedQuote = true;
          }
        } else {
          field.write(character);
        }
        continue;
      }
      if (character == '\t') {
        endField();
        endedRow = false;
      } else if (character == '\r' || character == '\n') {
        endField();
        endRow();
        if (character == '\r' && i + 1 < text.length && text[i + 1] == '\n') {
          i++;
        }
        endedRow = true;
      } else if (character == '"' && atStart) {
        quoted = true;
        atStart = false;
        endedRow = false;
      } else {
        if (closedQuote || character == '"') {
          throw const FormatException('tsv_malformed');
        }
        field.write(character);
        atStart = false;
        endedRow = false;
      }
    }
    if (quoted) throw const FormatException('tsv_malformed');
    if (!endedRow) {
      endField();
      endRow();
    }
    return List.unmodifiable(rows);
  }
}
