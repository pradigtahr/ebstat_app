import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/measurement_point.dart';
import '../models/project_session.dart';

class CsvImportException implements Exception {
  final String message;
  const CsvImportException(this.message);
  @override
  String toString() => message;
}

/// Parses an EbStat PalmSens-style CSV back into a [ProjectSession].
///
/// Expected header format:
///   Date and time:,<ts>
///   Technique:,CV
///   Notes:
///   (empty row)
///   Series1,,Series2,,…
///   Date and time measurement:,ts1,Date and time measurement:,ts2,…
///   V,µA,V,µA,…   (or s,µA for CA)
///   x1,y1,x2,y2,…
class CsvImportService {
  static const _knownTechniques = {'CV', 'CA', 'SWV', 'DPV', 'NPV'};

  /// Read [filePath] (UTF-8 or UTF-16 LE with BOM) and parse.
  static Future<ProjectSession> importFromFile(String filePath) async {
    final rawBytes = await File(filePath).readAsBytes();
    return importFromBytes(rawBytes);
  }

  /// Decode [bytes] (UTF-8 or UTF-16 LE with BOM) and parse.
  static ProjectSession importFromBytes(Uint8List bytes) {
    String content;
    // UTF-16 LE BOM: 0xFF 0xFE
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      final u16 = bytes.sublist(2).buffer.asUint16List();
      content = String.fromCharCodes(u16);
    } else {
      content = utf8.decode(bytes, allowMalformed: true);
    }
    return importFromContent(content);
  }

  /// Parse already-decoded CSV text.
  static ProjectSession importFromContent(String content) {
    final lines = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');

    // ── 1. Header metadata ────────────────────────────────────────────────────
    String? technique;
    int li = 0;

    while (li < lines.length) {
      final line = lines[li];
      if (line.startsWith('Technique:,')) {
        technique = line.substring('Technique:,'.length).trim().toUpperCase();
        li++;
        continue;
      }
      if (line.startsWith('Date and time:,') || line.startsWith('Notes:')) {
        li++;
        continue;
      }
      if (line.trim().isEmpty) {
        li++; // empty separator row → switch to series section
        break;
      }
      li++;
    }

    if (technique == null) {
      throw const CsvImportException('Not a valid EbStat CSV file');
    }
    if (!_knownTechniques.contains(technique)) {
      throw CsvImportException('Unsupported technique: $technique');
    }

    // ── 2. Series names row ───────────────────────────────────────────────────
    if (li >= lines.length || lines[li].trim().isEmpty) {
      throw const CsvImportException('File contains no measurement data');
    }
    final nameCells = _parseCsvLine(lines[li++]);
    // Each series occupies columns [2*i, 2*i+1]; names are at even indices.
    final seriesNames = <String>[];
    for (int i = 0; i < nameCells.length; i += 2) {
      final name = nameCells[i].trim();
      if (name.isNotEmpty) seriesNames.add(name);
    }
    if (seriesNames.isEmpty) {
      throw const CsvImportException('File contains no measurement data');
    }
    final n = seriesNames.length;

    // ── 3. Measurement timestamps row ─────────────────────────────────────────
    final tsCells = li < lines.length ? _parseCsvLine(lines[li++]) : <String>[];
    final timestamps = List<DateTime>.generate(n, (i) {
      final col = 2 * i + 1; // "Date and time measurement:,<ts>"
      if (col < tsCells.length) {
        return _parseTimestamp(tsCells[col]) ?? DateTime.now();
      }
      return DateTime.now();
    });

    // ── 4. Units row (consumed to advance the line pointer) ──────────────────
    if (li < lines.length) li++;

    // ── 5. Data rows ──────────────────────────────────────────────────────────
    final seriesXs = List.generate(n, (_) => <double>[]);
    final seriesYs = List.generate(n, (_) => <double>[]);
    int totalRows  = 0;
    int skippedRows = 0;

    while (li < lines.length) {
      final line = lines[li++].trim();
      if (line.isEmpty) continue;
      final cells = _parseCsvLine(line);
      totalRows++;
      bool anyParsed = false;
      for (int si = 0; si < n; si++) {
        final xCol = 2 * si;
        final yCol = 2 * si + 1;
        final xStr = xCol < cells.length ? cells[xCol].trim() : '';
        final yStr = yCol < cells.length ? cells[yCol].trim() : '';
        if (xStr.isEmpty && yStr.isEmpty) continue; // series ended early
        final x = double.tryParse(xStr);
        final y = double.tryParse(yStr);
        if (x != null && y != null) {
          seriesXs[si].add(x);
          seriesYs[si].add(y);
          anyParsed = true;
        }
      }
      if (!anyParsed) skippedRows++;
    }

    if (totalRows > 0 && skippedRows / totalRows > 0.10) {
      // ignore: avoid_print
      print('[CsvImportService] Warning: $skippedRows/$totalRows rows skipped');
    }

    // ── 6. Reconstruct ProjectSession ─────────────────────────────────────────
    final isCv = technique == 'CV';
    final project = ProjectSession(modeName: technique);

    if (isCv) {
      // Group series by base measurement name; cycle series have "— Cycle N"
      final cycleRe  = RegExp(r'^(.*?)\s*—\s*Cycle\s+(\d+)\s*$');
      final measPts  = <String, Map<int, List<MeasurementPoint>>>{};
      final measTs   = <String, DateTime>{};
      final measOrder = <String>[];

      for (int si = 0; si < n; si++) {
        final name    = seriesNames[si];
        final match   = cycleRe.firstMatch(name);
        final baseName = match != null ? match.group(1)!.trim() : name;
        final cycleNum = match != null ? int.parse(match.group(2)!) : 1;

        if (!measPts.containsKey(baseName)) {
          measPts[baseName] = {};
          measTs[baseName]  = timestamps[si];
          measOrder.add(baseName);
        }

        final pts = <MeasurementPoint>[];
        final xs  = seriesXs[si];
        final ys  = seriesYs[si];
        for (int i = 0; i < xs.length; i++) {
          pts.add(MeasurementPoint(
            xs[i] * 1000, // V → mV
            ys[i] * 1000, // µA → nA
            cycle: cycleNum,
          ));
        }
        measPts[baseName]![cycleNum] = pts;
      }

      for (final baseName in measOrder) {
        final cycleMap = measPts[baseName]!;
        final allPts   = <MeasurementPoint>[];
        for (final cNum in (cycleMap.keys.toList()..sort())) {
          allPts.addAll(cycleMap[cNum]!);
        }
        if (allPts.isEmpty) continue;
        project.addMeasurement(MeasurementSession(
          mode:        technique,
          displayName: baseName,
          parameters:  {},
          startedAt:   measTs[baseName]!,
          points:      allPts,
        ));
      }
    } else {
      // Non-CV: one series → one measurement; CA: s→ms, others: V→mV
      for (int si = 0; si < n; si++) {
        final xs = seriesXs[si];
        final ys = seriesYs[si];
        if (xs.isEmpty) continue;
        final pts = <MeasurementPoint>[];
        for (int i = 0; i < xs.length; i++) {
          pts.add(MeasurementPoint(xs[i] * 1000, ys[i] * 1000));
        }
        project.addMeasurement(MeasurementSession(
          mode:        technique,
          displayName: seriesNames[si],
          parameters:  {},
          startedAt:   timestamps[si],
          points:      pts,
        ));
      }
    }

    if (project.measurements.isEmpty) {
      throw const CsvImportException('File contains no measurement data');
    }

    return project;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  static List<String> _parseCsvLine(String line) {
    final result = <String>[];
    final sb = StringBuffer();
    bool inQuote = false;
    for (int i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (inQuote && i + 1 < line.length && line[i + 1] == '"') {
          sb.write('"');
          i++;
        } else {
          inQuote = !inQuote;
        }
      } else if (c == ',' && !inQuote) {
        result.add(sb.toString());
        sb.clear();
      } else {
        sb.write(c);
      }
    }
    result.add(sb.toString());
    return result;
  }

  static DateTime? _parseTimestamp(String s) {
    try {
      return DateTime.parse(s.trim().replaceFirst(' ', 'T'));
    } catch (_) {
      return null;
    }
  }
}
