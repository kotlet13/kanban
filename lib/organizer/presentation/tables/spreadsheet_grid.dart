import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../../domain/spreadsheet_formula.dart';
import '../../domain/spreadsheet_models.dart';
import '../../domain/spreadsheet_tsv.dart';
import 'tables_strings.dart';
import 'table_text_prompt.dart';
import 'table_help.dart';

/// A two-axis viewport: only visible cell widgets exist. Its scrollable extent
/// grows as the user approaches an edge, with A1..ZZZ100000 safety bounds.
class SpreadsheetGrid extends StatefulWidget {
  const SpreadsheetGrid({
    super.key,
    required this.cells,
    required this.editable,
    required this.onChanged,
    this.canAccess,
  });
  final Map<String, String> cells;
  final bool editable;
  final ValueChanged<Map<String, String>> onChanged;
  final bool Function()? canAccess;
  @override
  State<SpreadsheetGrid> createState() => _SpreadsheetGridState();
}

class _SpreadsheetGridState extends State<SpreadsheetGrid> {
  final _horizontal = ScrollController(), _vertical = ScrollController();
  final _input = TextEditingController(),
      _focus = FocusNode(),
      _inputFocus = FocusNode();
  var _row = 0,
      _column = 0,
      _anchorRow = 0,
      _anchorColumn = 0,
      _rows = 100,
      _columns = 26;
  double _columnWidth = 120, _zoom = 1;
  static const _minZoom = .5, _maxZoom = 2.0;
  double get _cellWidth => _columnWidth * _zoom;
  double get _height => 48 * _zoom;
  double get _headerWidth => 56 * _zoom;
  final _pointers = <int, Offset>{};
  final _viewportKey = GlobalKey();
  bool _pinching = false, _suppressSelection = false;
  double _pinchDistance = 1, _pinchZoom = 1;
  Offset _pinchAnchor = Offset.zero;

  Offset get _scrollOffset => Offset(
    _horizontal.hasClients ? _horizontal.offset : 0,
    _vertical.hasClients ? _vertical.offset : 0,
  );

  Offset get _focalPoint {
    final points = _pointers.values.take(2).toList();
    return (points[0] + points[1]) / 2;
  }

  double get _distance {
    final points = _pointers.values.take(2).toList();
    return (points[0] - points[1]).distance;
  }

  void _pointerDown(PointerDownEvent event) {
    if (_pointers.isEmpty) _suppressSelection = false;
    if (event.kind != PointerDeviceKind.touch &&
        event.kind != PointerDeviceKind.stylus &&
        event.kind != PointerDeviceKind.invertedStylus) {
      return;
    }
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 2) _beginPinch();
  }

  void _beginPinch() {
    _pinchDistance = math.max(1, _distance);
    _pinchZoom = _zoom;
    _pinchAnchor =
        (_scrollOffset + _focalPoint - Offset(_headerWidth, _height)) / _zoom;
    // Cancel an in-progress single-finger scroll before the second finger moves.
    for (final controller in [_horizontal, _vertical]) {
      if (controller.hasClients) controller.jumpTo(controller.offset);
    }
    setState(() {
      _pinching = true;
      _suppressSelection = true;
    });
  }

  void _pointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    if (_pinching && _pointers.length >= 2) {
      _setZoom(
        _pinchZoom * _distance / _pinchDistance,
        focal: _focalPoint,
        anchor: _pinchAnchor,
      );
    }
  }

  void _pointerEnd(PointerEvent event) {
    if (_pointers.remove(event.pointer) == null) return;
    if (_pointers.length >= 2) {
      _beginPinch();
    } else if (_pinching) {
      setState(() => _pinching = false);
    }
  }

  void _setZoom(double value, {Offset? focal, Offset? anchor}) {
    value = value.clamp(_minZoom, _maxZoom);
    final size = _viewportKey.currentContext?.size;
    focal ??= size == null
        ? Offset.zero
        : Offset(size.width / 2, size.height / 2);
    anchor ??= (_scrollOffset + focal - Offset(_headerWidth, _height)) / _zoom;
    final target = anchor * value - focal + Offset(56 * value, 48 * value);
    setState(() => _zoom = value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_horizontal.hasClients) {
        _horizontal.jumpTo(
          target.dx.clamp(0, _horizontal.position.maxScrollExtent),
        );
      }
      if (_vertical.hasClients) {
        _vertical.jumpTo(
          target.dy.clamp(0, _vertical.position.maxScrollExtent),
        );
      }
    });
  }

  late SpreadsheetCalculator _calculator;
  String get _address => SpreadsheetAddress(_row, _column).label;
  @override
  void initState() {
    super.initState();
    _calculator = SpreadsheetCalculator(widget.cells);
    _input.text = widget.cells[_address] ?? '';
    _expandForData();
    _horizontal.addListener(_scrolled);
    _vertical.addListener(_scrolled);
  }

  @override
  void didUpdateWidget(SpreadsheetGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.cells, oldWidget.cells)) {
      _calculator = SpreadsheetCalculator(widget.cells);
      _expandForData();
      final raw = widget.cells[_address] ?? '';
      if (raw != _input.text) _input.text = raw;
    }
  }

  void _expandForData() {
    for (final key in widget.cells.keys) {
      final a = SpreadsheetAddress.parse(key);
      if (a != null) {
        _rows = math.min(
          SpreadsheetAddress.maxRows,
          math.max(_rows, a.row + 21),
        );
        _columns = math.min(
          SpreadsheetAddress.maxColumns,
          math.max(_columns, a.column + 7),
        );
      }
    }
  }

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    _input.dispose();
    _focus.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _scrolled() {
    if (!mounted) return;
    setState(() {
      if (_horizontal.hasClients && _horizontal.position.extentAfter < 600) {
        _columns = math.min(SpreadsheetAddress.maxColumns, _columns + 26);
      }
      if (_vertical.hasClients && _vertical.position.extentAfter < 600) {
        _rows = math.min(SpreadsheetAddress.maxRows, _rows + 100);
      }
    });
  }

  void _select(
    int row,
    int column, {
    bool extend = false,
    bool keyboard = false,
  }) {
    row = row.clamp(0, SpreadsheetAddress.maxRows - 1);
    column = column.clamp(0, SpreadsheetAddress.maxColumns - 1);
    setState(() {
      _row = row;
      _column = column;
      if (!extend) {
        _anchorRow = row;
        _anchorColumn = column;
      }
      _rows = math.min(SpreadsheetAddress.maxRows, math.max(_rows, row + 21));
      _columns = math.min(
        SpreadsheetAddress.maxColumns,
        math.max(_columns, column + 7),
      );
      _input.text = widget.cells[_address] ?? '';
    });
    if (keyboard) {
      _focus.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureVisible();
      });
    }
  }

  void _ensureVisible() {
    if (_horizontal.hasClients) {
      final left = _column * _cellWidth,
          right = left + _cellWidth,
          offset = _horizontal.offset,
          width = _horizontal.position.viewportDimension;
      _horizontal.jumpTo(
        (left < offset
                ? left
                : right > offset + width
                ? right - width
                : offset)
            .clamp(0, _horizontal.position.maxScrollExtent),
      );
    }
    if (_vertical.hasClients) {
      final top = _row * _height,
          bottom = top + _height,
          offset = _vertical.offset,
          height = _vertical.position.viewportDimension;
      _vertical.jumpTo(
        (top < offset
                ? top
                : bottom > offset + height
                ? bottom - height
                : offset)
            .clamp(0, _vertical.position.maxScrollExtent),
      );
    }
  }

  void _limit() {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(TablesStrings.of(context).limit)));
    }
  }

  void _write(String value) {
    if (!widget.editable) return;
    if (utf8.encode(value).length > 4096) {
      _limit();
      return;
    }
    final cells = Map<String, String>.of(widget.cells);
    if (value.isEmpty) {
      cells.remove(_address);
    } else {
      cells[_address] = value;
    }
    if (cells.length <= 10000 &&
        utf8.encode(jsonEncode(cells)).length <= 524288) {
      widget.onChanged(cells);
    } else {
      final previous = widget.cells[_address] ?? '';
      _input.value = TextEditingValue(
        text: previous,
        selection: TextSelection.collapsed(offset: previous.length),
      );
      _limit();
    }
  }

  Future<void> _copy() async {
    if (widget.canAccess?.call() == false) return;
    final rows = <List<String>>[];
    final top = math.min(_row, _anchorRow),
        bottom = math.max(_row, _anchorRow),
        left = math.min(_column, _anchorColumn),
        right = math.max(_column, _anchorColumn);
    if ((bottom - top + 1) * (right - left + 1) > 10000) {
      _limit();
      return;
    }
    for (var r = top; r <= bottom; r++) {
      rows.add([
        for (var c = left; c <= right; c++)
          widget.cells[SpreadsheetAddress(r, c).label] ?? '',
      ]);
    }
    try {
      await Clipboard.setData(ClipboardData(text: SpreadsheetTsv.encode(rows)));
    } on FormatException {
      _limit();
    }
  }

  Future<void> _paste() async {
    if (!widget.editable) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || !widget.editable || data?.text == null) return;
    final List<List<String>> rows;
    try {
      rows = SpreadsheetTsv.decode(data!.text!);
    } on FormatException catch (error) {
      if (error.message == SpreadsheetTsv.limitError) {
        _limit();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(TablesStrings.of(context).invalidPaste)),
        );
      }
      return;
    }
    if (rows.isEmpty) return;
    final cells = Map<String, String>.of(widget.cells);
    var count = 0;
    for (var r = 0; r < rows.length; r++) {
      final columns = rows[r];
      for (var c = 0; c < columns.length; c++) {
        if (++count > 10000 || utf8.encode(columns[c]).length > 4096) {
          _limit();
          return;
        }
        final address = SpreadsheetAddress(_row + r, _column + c);
        if (!address.valid) {
          _limit();
          return;
        }
        if (columns[c].isEmpty) {
          cells.remove(address.label);
        } else {
          cells[address.label] = columns[c];
        }
      }
    }
    if (cells.length <= 10000 &&
        utf8.encode(jsonEncode(cells)).length <= 524288) {
      widget.onChanged(cells);
    } else {
      _limit();
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey,
        ctrl =
            HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed,
        shift = HardwareKeyboard.instance.isShiftPressed;
    if (ctrl && key == LogicalKeyboardKey.keyC) {
      _copy();
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyV) {
      _paste();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.enter) {
      _select(_row + 1, _column, extend: shift, keyboard: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _select(_row - 1, _column, extend: shift, keyboard: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.tab) {
      _select(
        _row,
        _column + (shift && key == LogicalKeyboardKey.tab ? -1 : 1),
        extend: shift && key != LogicalKeyboardKey.tab,
        keyboard: true,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _select(_row, _column - 1, extend: shift, keyboard: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      if (widget.editable) {
        _write('');
        _input.clear();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f2 && widget.editable) {
      _inputFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (widget.editable &&
        !ctrl &&
        event.character != null &&
        event.character!.codeUnits.every((c) => c >= 32)) {
      _input.text = event.character!;
      _write(_input.text);
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
      _inputFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _go() async {
    final s = TablesStrings.of(context);
    final target = await tableTextPrompt(
      context,
      title: s.go,
      label: s.go,
      initial: _address,
      maxBytes: 12,
    );
    final address = SpreadsheetAddress.parse(target?.trim() ?? '');
    if (address != null && mounted) {
      _select(address.row, address.column, keyboard: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = TablesStrings.of(context), colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, outerConstraints) => Column(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: outerConstraints.maxHeight * .5,
            ),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 72,
                        height: 48,
                        child: TextButton(
                          onPressed: _go,
                          child: Text(_address),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('spreadsheet-formula-input'),
                          controller: _input,
                          focusNode: _inputFocus,
                          readOnly: !widget.editable,
                          inputFormatters: [const _CellByteLimit()],
                          maxLength: 4096,
                          maxLengthEnforcement: MaxLengthEnforcement.enforced,
                          decoration: InputDecoration(
                            labelText: s.input,
                            counterText: '',
                            prefixText: 'ƒx  ',
                            isDense: true,
                          ),
                          onChanged: _write,
                          onSubmitted: (_) =>
                              _select(_row + 1, _column, keyboard: true),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: s.zoomOut,
                                onPressed: _zoom > _minZoom
                                    ? () => _setZoom(_zoom - .1)
                                    : null,
                                icon: const Icon(Icons.remove),
                              ),
                              SizedBox(
                                width:
                                    88 *
                                    MediaQuery.textScalerOf(context).scale(14) /
                                    14,
                                child: TextButton(
                                  key: const ValueKey('spreadsheet-zoom-reset'),
                                  onPressed: () => _setZoom(1),
                                  child: Text(
                                    '${(_zoom * 100).round()}%',
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: s.zoomIn,
                                onPressed: _zoom < _maxZoom
                                    ? () => _setZoom(_zoom + .1)
                                    : null,
                                icon: const Icon(Icons.add),
                              ),
                              IconButton(
                                tooltip: s.copy,
                                onPressed: _copy,
                                icon: const Icon(Icons.copy),
                              ),
                              IconButton(
                                tooltip: s.paste,
                                onPressed: widget.editable ? _paste : null,
                                icon: const Icon(Icons.paste),
                              ),
                              IconButton(
                                tooltip: s.narrower,
                                onPressed: _columnWidth > 80
                                    ? () => setState(() => _columnWidth -= 20)
                                    : null,
                                icon: const Icon(Icons.compress),
                              ),
                              IconButton(
                                tooltip: s.wider,
                                onPressed: _columnWidth < 300
                                    ? () => setState(() => _columnWidth += 20)
                                    : null,
                                icon: const Icon(Icons.expand),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: s.help,
                        onPressed: () => showTableHelp(context),
                        icon: const Icon(Icons.help_outline),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Focus(
              focusNode: _focus,
              onKeyEvent: _key,
              child: Listener(
                key: const ValueKey('spreadsheet-viewport'),
                behavior: HitTestBehavior.opaque,
                onPointerDown: _pointerDown,
                onPointerMove: _pointerMove,
                onPointerUp: _pointerEnd,
                onPointerCancel: _pointerEnd,
                child: LayoutBuilder(
                  key: _viewportKey,
                  builder: (context, constraints) {
                    final width = math.max(
                          1.0,
                          constraints.maxWidth - _headerWidth,
                        ),
                        height = math.max(1.0, constraints.maxHeight - _height);
                    final x = _horizontal.hasClients ? _horizontal.offset : 0.0,
                        y = _vertical.hasClients ? _vertical.offset : 0.0;
                    final firstColumn = (x / _cellWidth).floor(),
                        firstRow = (y / _height).floor();
                    final lastColumn = math.min(
                          _columns - 1,
                          ((x + width) / _cellWidth).ceil(),
                        ),
                        lastRow = math.min(
                          _rows - 1,
                          ((y + height) / _height).ceil(),
                        );
                    final top = math.min(_row, _anchorRow),
                        bottom = math.max(_row, _anchorRow),
                        left = math.min(_column, _anchorColumn),
                        right = math.max(_column, _anchorColumn);
                    Widget box(
                      String text, {
                      bool header = false,
                      bool selected = false,
                      VoidCallback? onTap,
                      String? label,
                    }) => Semantics(
                      label: label,
                      selected: selected,
                      button: onTap != null,
                      child: Material(
                        color: selected
                            ? colors.primaryContainer
                            : header
                            ? colors.surfaceContainerHigh
                            : colors.surface,
                        child: InkWell(
                          onTap: onTap,
                          child: Container(
                            alignment: header
                                ? Alignment.center
                                : Alignment.centerLeft,
                            padding: EdgeInsets.symmetric(
                              horizontal: 8 * _zoom,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: selected
                                    ? colors.primary
                                    : colors.outlineVariant,
                                width: selected ? 2 : .5,
                              ),
                            ),
                            child: Text(
                              text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize:
                                    (Theme.of(
                                          context,
                                        ).textTheme.bodyMedium?.fontSize ??
                                        14) *
                                    _zoom,
                                color: selected
                                    ? colors.onPrimaryContainer
                                    : header
                                    ? colors.onSurfaceVariant
                                    : colors.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                    return Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Positioned(
                          left: _headerWidth,
                          top: _height,
                          width: width,
                          height: height,
                          child: SingleChildScrollView(
                            controller: _horizontal,
                            physics: _pinching
                                ? const NeverScrollableScrollPhysics()
                                : null,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: _columns * _cellWidth,
                              height: height,
                              child: SingleChildScrollView(
                                controller: _vertical,
                                physics: _pinching
                                    ? const NeverScrollableScrollPhysics()
                                    : null,
                                child: SizedBox(
                                  width: _columns * _cellWidth,
                                  height: _rows * _height,
                                  child: Stack(
                                    children: [
                                      for (var r = firstRow; r <= lastRow; r++)
                                        for (
                                          var c = firstColumn;
                                          c <= lastColumn;
                                          c++
                                        )
                                          Positioned(
                                            left: c * _cellWidth,
                                            top: r * _height,
                                            width: _cellWidth,
                                            height: _height,
                                            child: Builder(
                                              builder: (context) {
                                                final address =
                                                        SpreadsheetAddress(
                                                          r,
                                                          c,
                                                        ).label,
                                                    value = _calculator
                                                        .evaluate(address)
                                                        .display;
                                                return box(
                                                  value,
                                                  selected:
                                                      r >= top &&
                                                      r <= bottom &&
                                                      c >= left &&
                                                      c <= right,
                                                  label: '$address: $value',
                                                  onTap: () {
                                                    if (_suppressSelection) {
                                                      return;
                                                    }
                                                    _select(
                                                      r,
                                                      c,
                                                      extend: HardwareKeyboard
                                                          .instance
                                                          .isShiftPressed,
                                                    );
                                                    _focus.requestFocus();
                                                  },
                                                );
                                              },
                                            ),
                                          ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        for (var c = firstColumn; c <= lastColumn; c++)
                          Positioned(
                            left: _headerWidth + c * _cellWidth - x,
                            top: 0,
                            width: _cellWidth,
                            height: _height,
                            child: box(
                              SpreadsheetAddress.columnLabel(c),
                              header: true,
                            ),
                          ),
                        for (var r = firstRow; r <= lastRow; r++)
                          Positioned(
                            left: 0,
                            top: _height + r * _height - y,
                            width: _headerWidth,
                            height: _height,
                            child: box('${r + 1}', header: true),
                          ),
                        Positioned(
                          left: 0,
                          top: 0,
                          width: _headerWidth,
                          height: _height,
                          child: box('', header: true),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CellByteLimit extends TextInputFormatter {
  const _CellByteLimit();
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => utf8.encode(newValue.text).length <= 4096 ? newValue : oldValue;
}
