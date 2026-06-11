import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/project_session.dart';

/// Exports all visible measurements as an XLSX workbook.
///
/// Sheet layout (PalmSens-compatible, side-by-side):
///   Row 1 (labels):  SeriesName1,,SeriesName2,,…  (alternating A/C/E…)
///   Row 2 (units):   V,µA,V,µA,…
///   Row 3+  (data):  x1,y1,x2,y2,…
///
/// Units: mV→V, nA→µA.
class XlsxExportService {
  static Future<void> export(
    ProjectSession project, {
    Set<int>?    hiddenMeasurements,
    Set<String>? hiddenCycles,
  }) async {
    final hidden   = hiddenMeasurements ?? const <int>{};
    final hiddenCy = hiddenCycles       ?? const <String>{};
    final isCv     = project.modeName == 'CV';
    final isCa     = project.modeName == 'CA';
    final xUnit    = isCa ? 'time_s' : 'V';
    const yUnit    = 'µA';

    final series = <_Series>[];
    int sn = 1;
    for (int mIdx = 0; mIdx < project.measurements.length; mIdx++) {
      if (hidden.contains(mIdx)) continue;
      final session = project.measurements[mIdx];

      if (isCv) {
        final cycles = session.cycles.toList()..sort();
        for (final cNum in cycles) {
          if (hiddenCy.contains('$mIdx:$cNum')) continue;
          final pts = session.points.where((p) => p.cycle == cNum).toList();
          if (pts.isEmpty) continue;
          final name = cycles.length == 1
              ? 'Cyclic Voltammetry [$sn]: ${session.displayName}'
              : 'Cyclic Voltammetry [$sn]: ${session.displayName} — Cycle $cNum';
          series.add(_Series(
            name:      name,
            timestamp: session.startedAt,
            xs:        pts.map((p) => p.x / 1000).toList(),
            ys:        pts.map((p) => p.y / 1000).toList(),
          ));
          sn++;
        }
      } else {
        if (session.points.isEmpty) continue;
        final pts = session.points
            .where((p) => p.cycle == null || !hiddenCy.contains('$mIdx:${p.cycle}'))
            .toList();
        if (pts.isEmpty) continue;
        series.add(_Series(
          name:      '${project.modeName} [$sn]: ${session.displayName}',
          timestamp: session.startedAt,
          xs:        pts.map((p) => p.x / 1000).toList(),
          ys:        pts.map((p) => p.y / 1000).toList(),
        ));
        sn++;
      }
    }

    if (series.isEmpty) throw Exception('No visible data to export');

    final excel = Excel.createExcel();
    excel.delete('Sheet1');
    final sheet = excel[project.modeName];

    // Row 1: label row — series names in columns A, C, E, …
    final labelRow = <CellValue?>[];
    for (final s in series) {
      labelRow.add(TextCellValue(s.name));
      labelRow.add(TextCellValue(''));
    }
    sheet.appendRow(labelRow);

    // Row 2: unit row — V, µA alternating
    final unitRow = <CellValue?>[];
    for (int i = 0; i < series.length; i++) {
      unitRow.add(TextCellValue(xUnit));
      unitRow.add(TextCellValue(yUnit));
    }
    sheet.appendRow(unitRow);

    // Data rows
    final maxLen = series.map((s) => s.xs.length).reduce((a, b) => a > b ? a : b);
    for (int row = 0; row < maxLen; row++) {
      final dataRow = <CellValue?>[];
      for (final s in series) {
        if (row < s.xs.length) {
          dataRow.add(DoubleCellValue(s.xs[row]));
          dataRow.add(DoubleCellValue(s.ys[row]));
        } else {
          dataRow.add(null);
          dataRow.add(null);
        }
      }
      sheet.appendRow(dataRow);
    }

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Failed to encode workbook');

    final dir  = await getTemporaryDirectory();
    final ts   = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final file = File('${dir.path}/ebstat_${project.modeName}_$ts.xlsx');
    await file.writeAsBytes(bytes);

    await SharePlus.instance.share(ShareParams(
      files:   [XFile(file.path,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
      subject: 'EbStat — ${project.modeName} project data',
    ));
  }
}

class _Series {
  final String name;
  final DateTime timestamp;
  final List<double> xs;
  final List<double> ys;
  const _Series({
    required this.name,
    required this.timestamp,
    required this.xs,
    required this.ys,
  });
}
