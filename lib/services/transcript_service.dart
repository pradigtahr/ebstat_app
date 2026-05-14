import 'dart:io';
import 'package:path_provider/path_provider.dart';

import '../ble/protocol.dart';
import '../models/measurement_point.dart';

class TranscriptService {
  static Future<File> save({
    required RunResult result,
    required String technique,
    required String label,
    required DateTime startedAt,
    required List<MeasurementPoint> points,
  }) async {
    final dir  = await getApplicationDocumentsDirectory();
    final ts   = _fmtDate(startedAt);
    final file = File('${dir.path}/${technique}_$ts.csv');

    final buf = StringBuffer();
    buf.writeln('# EbStat transcript');
    buf.writeln('# technique=$technique');
    buf.writeln('# label=${label.isNotEmpty ? label : "unlabelled"}');
    buf.writeln('# started=${startedAt.toIso8601String()}');
    buf.writeln('# status=${result.aborted ? "ABORTED" : "DONE"}');
    for (final kv in result.metadata.entries) {
      buf.writeln('# ${kv.key}=${kv.value}');
    }
    if (result.header.isNotEmpty) {
      buf.writeln(result.header.join(','));
      for (final row in result.rawRows) {
        buf.writeln(row);
      }
    } else {
      // Fallback when firmware sends no header (shouldn't happen)
      buf.writeln('x,y_uA');
      for (final pt in points) {
        buf.writeln('${pt.x.toStringAsFixed(4)},${pt.y.toStringAsFixed(6)}');
      }
    }

    await file.writeAsString(buf.toString());
    return file;
  }

  static Future<List<TranscriptInfo>> listTranscripts() async {
    final dir = await getApplicationDocumentsDirectory();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.csv'))
        .map((f) => TranscriptInfo(f))
        .toList()
      ..sort((a, b) => b.file.lastModifiedSync()
          .compareTo(a.file.lastModifiedSync()));
    return files;
  }

  static Future<void> delete(File file) => file.delete();

  static String _fmtDate(DateTime dt) {
    String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
    return '${p(dt.year, 4)}${p(dt.month)}${p(dt.day)}'
        '_${p(dt.hour)}${p(dt.minute)}${p(dt.second)}';
  }
}

class TranscriptInfo {
  final File file;

  TranscriptInfo(this.file);

  String get basename => file.path.split('/').last;

  /// Parse technique from filename like "CV_20250514_123456.csv"
  String get technique {
    final name = basename.replaceAll('.csv', '');
    final parts = name.split('_');
    return parts.isNotEmpty ? parts.first : 'Unknown';
  }

  /// Parse timestamp from filename
  String get timestampLabel {
    final name = basename.replaceAll('.csv', '');
    // Format: TECHNIQUE_yyyymmdd_HHmmss
    final parts = name.split('_');
    if (parts.length >= 3) {
      final date = parts[parts.length - 2]; // yyyymmdd
      final time = parts[parts.length - 1]; // HHmmss
      if (date.length == 8 && time.length == 6) {
        return '${date.substring(0, 4)}-${date.substring(4, 6)}-${date.substring(6, 8)}'
            ' ${time.substring(0, 2)}:${time.substring(2, 4)}:${time.substring(4, 6)}';
      }
    }
    return basename;
  }

  int get sizeBytes => file.lengthSync();

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    return '${(sizeBytes / 1024).toStringAsFixed(1)} kB';
  }
}
