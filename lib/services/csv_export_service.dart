import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/project_session.dart';

/// Exports measurements as a PalmSens PSTrace-compatible CSV.
///
/// Encoding: UTF-16 LE with BOM.
/// Format:
///   Date and time:,<ts>
///   Technique:,<mode>
///   Notes:
///   (empty)
///   Series1,,Series2,,…
///   Date and time measurement:,ts1,Date and time measurement:,ts2,…
///   V,µA,V,µA,…
///   x1,y1,x2,y2,…
///
/// Units: mV→V, nA→µA.
class CsvExportService {
  static Future<void> export(
    ProjectSession project, {
    Set<int>?    hiddenMeasurements,
    Set<String>? hiddenCycles,
  }) async {
    final hidden   = hiddenMeasurements ?? const <int>{};
    final hiddenCy = hiddenCycles       ?? const <String>{};
    final isCv     = project.modeName == 'CV';
    final isCa     = project.modeName == 'CA';
    final xUnit    = isCa ? 's' : 'V';
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

    final sb = StringBuffer();
    final now = _fmt(DateTime.now());

    sb.writeln('Date and time:,$now');
    sb.writeln('Technique:,${project.modeName}');
    sb.writeln('Notes:');
    sb.writeln();

    // Series name row
    sb.writeln(series.map((s) => '${_esc(s.name)},').join(','));

    // Measurement timestamp row
    sb.writeln(series.map((s) => 'Date and time measurement:,${_fmt(s.timestamp)}').join(','));

    // Unit row
    sb.writeln(series.map((_) => '$xUnit,$yUnit').join(','));

    // Data rows
    final maxLen = series.map((s) => s.xs.length).reduce((a, b) => a > b ? a : b);
    for (int row = 0; row < maxLen; row++) {
      final cells = <String>[];
      for (final s in series) {
        if (row < s.xs.length) {
          cells.add(_num(s.xs[row]));
          cells.add(_num(s.ys[row]));
        } else {
          cells.add('');
          cells.add('');
        }
      }
      sb.writeln(cells.join(','));
    }

    final bytes = _utf16Le(sb.toString());
    final dir   = await getTemporaryDirectory();
    final ts    = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final file  = File('${dir.path}/ebstat_${project.modeName}_$ts.csv');
    await file.writeAsBytes(bytes);

    await SharePlus.instance.share(ShareParams(
      files:   [XFile(file.path, mimeType: 'text/csv')],
      subject: 'EbStat — ${project.modeName} measurement data',
    ));
  }

  static Uint8List _utf16Le(String s) {
    final units  = s.codeUnits;
    final result = Uint8List(2 + units.length * 2);
    result[0] = 0xFF;
    result[1] = 0xFE; // BOM
    for (int i = 0; i < units.length; i++) {
      final c = units[i];
      result[2 + i * 2]     = c & 0xFF;
      result[2 + i * 2 + 1] = (c >> 8) & 0xFF;
    }
    return result;
  }

  static String _fmt(DateTime dt) {
    String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
    return '${p(dt.year, 4)}-${p(dt.month)}-${p(dt.day)} '
        '${p(dt.hour)}:${p(dt.minute)}:${p(dt.second)}';
  }

  static String _num(double v) => v.toStringAsFixed(6);

  static String _esc(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
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
