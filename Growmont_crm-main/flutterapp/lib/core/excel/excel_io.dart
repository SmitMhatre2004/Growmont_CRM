import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;

import '../io/file_saver.dart';

/// How a column's numbers should read in Excel.
///
/// The cell keeps its real numeric value — only the display changes — so a
/// reader can still sum or chart the column.
enum ExcelNumberFormat {
  /// Left as Excel's General.
  plain,

  /// Indian-grouped rupees, e.g. 570700 -> ₹5,70,700.
  rupees,

  /// Whole number with thousands separators.
  count,

  /// A fraction rendered as a percentage, e.g. 0.2953 -> +29.5%.
  /// Values must therefore be written as fractions, not as 29.53.
  signedPercent,
}

/// One tab of a multi-sheet workbook. See [ExcelIO.buildMultiSheetBytes].
///
/// The styling fields are all optional: a sheet that sets none of them
/// renders exactly as a plain grid, which is what every pre-existing
/// export wants.
class ExcelSheet {
  const ExcelSheet({
    required this.name,
    this.headers = const [],
    required this.rows,
    this.columnFormats = const {},
    this.cellFormats = const {},
    this.columnWidths = const {},
    this.titleRows = const {},
    this.sectionRows = const {},
    this.headerRows = const {},
    this.boldRows = const {},
    this.boldFirstColumn = false,
  });

  /// Tab name. Excel rejects `[]:*?/\` and anything over 31 characters, so
  /// callers should keep these short and plain.
  final String name;

  /// Header row, written first when non-empty and styled as a header.
  final List<String> headers;

  final List<List<Object?>> rows;

  /// Number format per column index.
  final Map<int, ExcelNumberFormat> columnFormats;

  /// Per-cell overrides, keyed by `(row, column)` into [rows]. Needed
  /// wherever a column is not uniform — a summary table whose rows are
  /// alternately money and counts cannot be described column-wise.
  final Map<(int, int), ExcelNumberFormat> cellFormats;

  /// Explicit width per column index. Columns left out are auto-fitted.
  final Map<int, double> columnWidths;

  /// Indices into [rows] to render as a document title.
  final Set<int> titleRows;

  /// Indices into [rows] to render as a section heading.
  final Set<int> sectionRows;

  /// Indices into [rows] to render with the filled header style, for a
  /// sheet whose header line sits inside [rows] rather than in [headers].
  final Set<int> headerRows;

  /// Indices into [rows] to render bold — totals lines, typically.
  final Set<int> boldRows;

  /// Bold the first cell of every row, for `label | value` blocks.
  final bool boldFirstColumn;
}

/// Generic .xlsx read/write helpers used by every screen's Export/Import
/// buttons. All parsing/building runs on-device — there is no server
/// component involved.
class ExcelIO {
  ExcelIO._();

  /// Builds a single-sheet .xlsx workbook in memory. Cell values may be
  /// [String], [num], [bool], [DateTime], or null.
  static Uint8List buildBytes({
    required String sheetName,
    required List<String> headers,
    required List<List<Object?>> rows,
  }) {
    final workbook = xls.Excel.createExcel();
    final defaultSheet = workbook.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != sheetName) {
      workbook.rename(defaultSheet, sheetName);
    }
    final sheet = workbook[sheetName];

    sheet.appendRow(headers.map((h) => xls.TextCellValue(h)).toList());
    for (final row in rows) {
      sheet.appendRow(row.map(_toCellValue).toList());
    }

    // Size every column to its longest cell (header included), the same
    // way Excel's own "AutoFit Column Width" does — no column here was
    // getting a deliberate width before, so every sheet used Excel's
    // generic default regardless of content.
    for (var i = 0; i < headers.length; i++) {
      sheet.setColumnAutoFit(i);
    }

    final bytes = workbook.encode();
    if (bytes == null) {
      throw StateError('Failed to encode workbook');
    }
    return Uint8List.fromList(bytes);
  }

  /// Builds a workbook and hands it to the user via [FileSaver], which opens
  /// a native Save As dialog on desktop and the share sheet on mobile, and
  /// side-steps an existing file rather than overwriting or failing on it.
  ///
  /// Returns the path actually written on desktop; null on mobile, or if the
  /// user cancelled the save dialog.
  static Future<String?> exportWorkbook({
    required String filename,
    required String sheetName,
    required List<String> headers,
    required List<List<Object?>> rows,
    String? shareText,
  }) {
    return FileSaver.save(
      filename: filename,
      bytes: buildBytes(sheetName: sheetName, headers: headers, rows: rows),
      extensions: const ['xlsx'],
      shareText: shareText,
    );
  }

  /// One tab of a multi-sheet workbook. [headers] may be empty for a
  /// free-form sheet (a cover page, say) that is just labelled rows.
  ///
  /// A blank entry in [rows] renders as a spacer line, which is how a
  /// report sheet separates its sections without needing cell merging.
  static ExcelSheet sheet({
    required String name,
    List<String> headers = const [],
    required List<List<Object?>> rows,
  }) {
    return ExcelSheet(name: name, headers: headers, rows: rows);
  }

  /// Builds a workbook with one tab per entry of [sheets], in order.
  ///
  /// Separate from [buildBytes] rather than a parameter on it: every
  /// existing caller exports exactly one sheet and must keep behaving
  /// identically, including the auto-fit pass and the default-sheet
  /// rename. Throws if [sheets] is empty — an empty workbook is a bug at
  /// the call site, not something to paper over with a blank file.
  static Uint8List buildMultiSheetBytes(List<ExcelSheet> sheets) {
    if (sheets.isEmpty) {
      throw ArgumentError.value(sheets, 'sheets', 'must not be empty');
    }

    final workbook = xls.Excel.createExcel();

    // createExcel() seeds a 'Sheet1'. Renaming it to the first requested
    // tab — rather than adding tabs beside it — is what keeps the finished
    // file free of a stray empty sheet.
    final defaultSheet = workbook.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != sheets.first.name) {
      workbook.rename(defaultSheet, sheets.first.name);
    }

    for (final spec in sheets) {
      final sheet = workbook[spec.name];
      var rowIndex = 0;

      if (spec.headers.isNotEmpty) {
        sheet.appendRow(
          spec.headers.map((h) => xls.TextCellValue(h)).toList(),
        );
        for (var col = 0; col < spec.headers.length; col++) {
          _styleCell(sheet, col, rowIndex, _headerStyle);
        }
        rowIndex++;
      }

      for (var r = 0; r < spec.rows.length; r++) {
        final row = spec.rows[r];
        sheet.appendRow(row.map(_toCellValue).toList());

        for (var col = 0; col < row.length; col++) {
          final style = _bodyStyle(spec, rowIndex: r, column: col);
          if (style != null) _styleCell(sheet, col, rowIndex, style);
        }
        rowIndex++;
      }

      // Auto-fit across the widest row, since a report sheet's columns are
      // not all declared in `headers` the way an export sheet's are. An
      // explicit width wins: auto-fit measures the raw value, so a column
      // whose display is widened by a number format (a rupee sign and its
      // separators) would otherwise come out too narrow.
      final columnCount = [
        spec.headers.length,
        ...spec.rows.map((r) => r.length),
      ].fold<int>(0, (widest, n) => n > widest ? n : widest);
      for (var i = 0; i < columnCount; i++) {
        final width = spec.columnWidths[i];
        if (width != null) {
          sheet.setColumnWidth(i, width);
        } else {
          sheet.setColumnAutoFit(i);
        }
      }
    }

    final bytes = workbook.encode();
    if (bytes == null) {
      throw StateError('Failed to encode workbook');
    }
    return Uint8List.fromList(bytes);
  }

  /// Builds a multi-sheet workbook and hands it to the user via
  /// [FileSaver]. Returns the written path on desktop, null on mobile or
  /// if the save dialog was cancelled.
  static Future<String?> exportMultiSheetWorkbook({
    required String filename,
    required List<ExcelSheet> sheets,
    String? shareText,
  }) {
    return FileSaver.save(
      filename: filename,
      bytes: buildMultiSheetBytes(sheets),
      extensions: const ['xlsx'],
      shareText: shareText,
    );
  }

  // ── Styling ───────────────────────────────────────────────────────────
  //
  // Colours mirror AppColors (navy 700 / slate) so a saved workbook looks
  // like the screen it came from. They are repeated as hex here rather
  // than imported because this file must stay free of Flutter widgets.

  static final _headerStyle = xls.CellStyle(
    bold: true,
    fontSize: 10,
    fontColorHex: xls.ExcelColor.white,
    backgroundColorHex: xls.ExcelColor.fromHexString('FF00337C'),
    verticalAlign: xls.VerticalAlign.Center,
  );

  static final _titleStyle = xls.CellStyle(
    bold: true,
    fontSize: 15,
    fontColorHex: xls.ExcelColor.fromHexString('FF001C4A'),
  );

  static final _sectionStyle = xls.CellStyle(
    bold: true,
    fontSize: 11,
    fontColorHex: xls.ExcelColor.fromHexString('FF00337C'),
  );

  /// Resolves the style for one body cell, or null to leave it as-is.
  static xls.CellStyle? _bodyStyle(
    ExcelSheet spec, {
    required int rowIndex,
    required int column,
  }) {
    if (spec.titleRows.contains(rowIndex)) return _titleStyle;
    if (spec.headerRows.contains(rowIndex)) return _headerStyle;
    if (spec.sectionRows.contains(rowIndex)) return _sectionStyle;

    final format = _numFormat(
      spec.cellFormats[(rowIndex, column)] ?? spec.columnFormats[column],
    );
    final bold = spec.boldRows.contains(rowIndex) ||
        (spec.boldFirstColumn && column == 0);

    if (format == null && !bold) return null;
    return xls.CellStyle(
      bold: bold,
      numberFormat: format ?? xls.NumFormat.standard_0,
    );
  }

  static xls.NumFormat? _numFormat(ExcelNumberFormat? format) {
    switch (format) {
      case null:
      case ExcelNumberFormat.plain:
        return null;
      case ExcelNumberFormat.rupees:
        // #,##,##0 is Excel's Indian lakh/crore grouping.
        return xls.NumFormat.custom(formatCode: r'"₹"#,##,##0');
      case ExcelNumberFormat.count:
        return xls.NumFormat.custom(formatCode: '#,##0');
      case ExcelNumberFormat.signedPercent:
        // Positive/negative/zero sections, so a fall reads "-12.4%" and a
        // flat month reads "0.0%" rather than an unsigned number.
        return xls.NumFormat.custom(formatCode: '+0.0%;-0.0%;0.0%');
    }
  }

  static void _styleCell(
    xls.Sheet sheet,
    int column,
    int row,
    xls.CellStyle style,
  ) {
    sheet
        .cell(xls.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
        .cellStyle = style;
  }

  static xls.CellValue? _toCellValue(Object? value) {
    if (value == null) return null;
    if (value is DateTime) {
      return xls.DateCellValue(
        year: value.year,
        month: value.month,
        day: value.day,
      );
    }
    if (value is int) return xls.IntCellValue(value);
    if (value is double) return xls.DoubleCellValue(value);
    if (value is bool) return xls.BoolCellValue(value);
    return xls.TextCellValue(value.toString());
  }

  /// Reads the first sheet of an .xlsx file and returns its data rows
  /// (the header row is skipped). Each cell comes back as [String], [num],
  /// [bool], [DateTime], or null, aligned to its column position.
  static Future<List<List<Object?>>> readDataRows(String path) async {
    final bytes = await File(path).readAsBytes();
    final workbook = xls.Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) return [];
    final sheet = workbook.tables[workbook.tables.keys.first]!;
    final rows = sheet.rows;
    if (rows.length <= 1) return [];
    return rows.skip(1).map((row) {
      return row.map(_fromCellData).toList();
    }).toList();
  }

  static Object? _fromCellData(xls.Data? data) {
    final value = data?.value;
    if (value == null) return null;
    if (value is xls.IntCellValue) return value.value;
    if (value is xls.DoubleCellValue) return value.value;
    if (value is xls.BoolCellValue) return value.value;
    if (value is xls.DateCellValue) return value.asDateTimeLocal();
    if (value is xls.DateTimeCellValue) return value.asDateTimeLocal();
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  /// True if every cell in [row] is null or an empty/whitespace string —
  /// used to skip blank trailing rows some spreadsheet apps leave behind.
  static bool isBlankRow(List<Object?> row) {
    return row.every((c) => c == null || c.toString().trim().isEmpty);
  }

  /// Cell at [index], or null if the row is too short / the value is blank.
  static Object? cell(List<Object?> row, int index) {
    if (index < 0 || index >= row.length) return null;
    return row[index];
  }

  /// Cell at [index] as trimmed text, or '' if absent.
  static String text(List<Object?> row, int index) {
    final v = cell(row, index);
    return v == null ? '' : v.toString().trim();
  }

  /// Parses a date-like cell value. A native Excel date comes back from
  /// [readDataRows] as a [DateTime] already; typed text is parsed as
  /// dd/mm/yyyy (matching what [buildBytes] produces) rather than with
  /// [DateTime.parse], which expects yyyy-mm-dd and would otherwise
  /// silently swap day and month for ambiguous input.
  static DateTime? date(List<Object?> row, int index) {
    final value = cell(row, index);
    if (value == null) return null;
    if (value is DateTime) return value;

    final str = value.toString().trim();
    if (str.isEmpty) return null;

    final dmy = RegExp(r'^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$').firstMatch(str);
    if (dmy != null) {
      final day = int.parse(dmy.group(1)!);
      final month = int.parse(dmy.group(2)!);
      final year = int.parse(dmy.group(3)!);
      return _safeDate(year, month, day);
    }

    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(str);
    if (iso != null) {
      return _safeDate(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
      );
    }

    return DateTime.tryParse(str);
  }

  /// Cell at [index] parsed as a date and formatted 'yyyy-MM-dd', or ''.
  static String isoDate(List<Object?> row, int index) {
    final d = date(row, index);
    if (d == null) return '';
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static DateTime? _safeDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final d = DateTime(year, month, day);
    return d;
  }
}
