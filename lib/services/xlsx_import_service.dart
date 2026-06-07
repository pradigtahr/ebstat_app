import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../models/measurement_point.dart';
import '../models/project_session.dart';

class XlsxImportException implements Exception {
  final String message;
  const XlsxImportException(this.message);
  @override
  String toString() => message;
}

class XlsxImportService {
  static const _knownTechniques = {'CV', 'CA', 'SWV', 'DPV', 'NPV'};

  static ProjectSession importFromBytes(Uint8List bytes) {
    final Excel workbook;
    try {
      workbook = Excel.decodeBytes(bytes);
    } catch (e) {
      throw XlsxImportException('Failed to open XLSX file: $e');
    }

    final scanRe = RegExp(r'^Scan \d+$');
    final scanEntries = workbook.sheets.entries
        .where((e) => scanRe.hasMatch(e.key))
        .toList()
      ..sort((a, b) {
        final na = int.parse(a.key.substring(5));
        final nb = int.parse(b.key.substring(5));
        return na.compareTo(nb);
      });

    if (scanEntries.isEmpty) {
      throw const XlsxImportException('No scan sheets found in XLSX file');
    }

    final sessions = <MeasurementSession>[];
    String? mode;

    for (final entry in scanEntries) {
      final session = _parseSheet(entry.value, entry.key);
      if (session == null) continue;
      mode ??= session.mode;
      sessions.add(session);
    }

    if (sessions.isEmpty) {
      throw const XlsxImportException('File contains no measurement data');
    }

    if (!_knownTechniques.contains(mode)) {
      throw XlsxImportException('Unsupported technique: $mode');
    }

    final project = ProjectSession(modeName: mode!);
    for (final s in sessions) project.addMeasurement(s);
    return project;
  }

  static MeasurementSession? _parseSheet(Sheet sheet, String sheetName) {
    final rows = sheet.rows;
    if (rows.isEmpty) return null;

    // Row 0: "EbStat — {mode} measurement"
    final title = _cellStr(rows[0], 0);
    final modeRe = RegExp(
      r'EbStat\s*[—–-]+\s*(\w+)\s+measurement',
      caseSensitive: false,
    );
    final modeMatch = modeRe.firstMatch(title);
    if (modeMatch == null) return null;
    final mode = modeMatch.group(1)!.toUpperCase();

    // Row 1: "Started", "<iso_timestamp>"
    DateTime startedAt = DateTime.now();
    if (rows.length > 1) {
      final tsStr = _cellStr(rows[1], 1);
      final ts = DateTime.tryParse(tsStr);
      if (ts != null) startedAt = ts;
    }

    // Scan for --- Parameters --- and --- Data --- markers
    int dataMarkerIdx = -1;
    final parameters = <String, double>{};
    bool inParams = false;

    for (int i = 2; i < rows.length; i++) {
      final cell0 = _cellStr(rows[i], 0);
      if (cell0.contains('--- Parameters ---')) {
        inParams = true;
        continue;
      }
      if (cell0.contains('--- Data ---')) {
        dataMarkerIdx = i;
        inParams = false;
        break;
      }
      if (inParams && cell0.isNotEmpty) {
        final val = _cellDouble(rows[i], 1);
        if (val != null) parameters[cell0] = val;
      }
    }

    if (dataMarkerIdx == -1) return null;

    // Row after marker is the column-header row — skip it
    final dataStartIdx = dataMarkerIdx + 2;
    if (dataStartIdx >= rows.length) return null;

    final points = <MeasurementPoint>[];
    for (int i = dataStartIdx; i < rows.length; i++) {
      final x = _cellDouble(rows[i], 0);
      final y = _cellDouble(rows[i], 1);
      if (x == null || y == null) continue;
      // XLSX export does not store per-point cycle numbers; default to cycle 1 for CV.
      points.add(MeasurementPoint(x, y, cycle: mode == 'CV' ? 1 : null));
    }

    if (points.isEmpty) return null;

    return MeasurementSession(
      mode: mode,
      displayName: sheetName,
      parameters: parameters,
      startedAt: startedAt,
      points: points,
    );
  }

  static String _cellStr(List<Data?> row, int col) {
    if (col >= row.length) return '';
    final v = row[col]?.value;
    if (v == null) return '';
    if (v is TextCellValue) return v.value.toString();
    return v.toString();
  }

  static double? _cellDouble(List<Data?> row, int col) {
    if (col >= row.length) return null;
    final v = row[col]?.value;
    if (v == null) return null;
    if (v is DoubleCellValue) return v.value;
    if (v is IntCellValue) return v.value.toDouble();
    if (v is TextCellValue) return double.tryParse(v.value.toString());
    return double.tryParse(v.toString());
  }
}
