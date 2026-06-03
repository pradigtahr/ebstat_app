import '../models/project_session.dart';
import '../models/voltammetry_mode.dart';

/// Produces a PalmSens PSTrace-compatible CSV.
///
/// Format:
///   Date and time:,<export timestamp>
///   Notes:
///   (empty row)
///   Series1,,Series2,,…        ← one pair of columns per series
///   Date and time measurement:,ts1,Date and time measurement:,ts2,…
///   V,µA,V,µA,…                ← or s,µA for CA
///   x1,y1,x2,y2,…
///   …
///
/// All mV→V and nA→µA conversions are applied on export.
class PalmsensCsvService {
  /// Build the CSV string.
  ///
  /// [project] — source data.
  /// [mode] — selected voltammetry mode (determines units/axis mapping).
  /// [selMeasurements] — set of measurement indices to include.
  /// [selCycles] — set of "$measIdx:$cycleNum" keys for CV cycle selection.
  ///   Ignored for non-CV modes.
  static String build(
    ProjectSession project,
    VoltammetryMode? mode, {
    required Set<int> selMeasurements,
    required Set<String> selCycles,
  }) {
    final isCv = mode == VoltammetryMode.cv;
    final isCa = mode == VoltammetryMode.ca;
    final xUnit = isCa ? 's' : 'V';
    final yUnit = 'µA';

    // Build ordered list of (name, timestamp, xs, ys)
    final series = <_Series>[];
    for (int mIdx = 0; mIdx < project.measurements.length; mIdx++) {
      if (!selMeasurements.contains(mIdx)) continue;
      final session = project.measurements[mIdx];

      if (isCv) {
        final cycles = session.cycles.toList()..sort();
        for (final cNum in cycles) {
          if (!selCycles.contains('$mIdx:$cNum')) continue;
          final pts =
              session.points.where((p) => p.cycle == cNum).toList();
          if (pts.isEmpty) continue;
          series.add(_Series(
            name: '${session.displayName} — Cycle $cNum',
            timestamp: session.startedAt,
            xs: pts.map((p) => p.x / 1000).toList(),
            ys: pts.map((p) => p.y / 1000).toList(),
          ));
        }
      } else {
        if (session.points.isEmpty) continue;
        series.add(_Series(
          name: session.displayName,
          timestamp: session.startedAt,
          xs: session.points.map((p) => p.x / 1000).toList(),
          ys: session.points.map((p) => p.y / 1000).toList(),
        ));
      }
    }

    if (series.isEmpty) return '';

    final sb = StringBuffer();
    final now = _fmt(DateTime.now());

    // Header block
    sb.writeln('Date and time:,$now');
    sb.writeln('Notes:');
    sb.writeln(); // empty separator row

    // Series name row: name,,name,,…
    sb.writeln(series.map((s) => '${_escapeCsv(s.name)},').join(','));

    // Measurement timestamp row
    sb.writeln(series
        .map((s) => 'Date and time measurement:,${_fmt(s.timestamp)}')
        .join(','));

    // Unit row
    sb.writeln(series.map((_) => '$xUnit,$yUnit').join(','));

    // Data rows
    final maxLen = series.map((s) => s.xs.length).reduce((a, b) => a > b ? a : b);
    for (int row = 0; row < maxLen; row++) {
      final cells = <String>[];
      for (final s in series) {
        if (row < s.xs.length) {
          cells.add(_fmtNum(s.xs[row]));
          cells.add(_fmtNum(s.ys[row]));
        } else {
          cells.add('');
          cells.add('');
        }
      }
      sb.writeln(cells.join(','));
    }

    return sb.toString();
  }

  static String _fmt(DateTime dt) {
    final y  = dt.year.toString().padLeft(4, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final d  = dt.day.toString().padLeft(2, '0');
    final h  = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final s  = dt.second.toString().padLeft(2, '0');
    return '$y-$mo-$d $h:$mi:$s';
  }

  /// Fixed-point with 6 decimal places — avoids scientific notation.
  static String _fmtNum(double v) => v.toStringAsFixed(6);

  /// Wrap in quotes only if the value contains a comma or quote.
  static String _escapeCsv(String s) {
    if (s.contains(',') || s.contains('"')) {
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
