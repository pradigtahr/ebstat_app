import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/project_session.dart';

class CsvExportService {
  static Future<void> export(MeasurementSession session) async {
    final rows = session.toCsv();
    final csvString = const ListToCsvConverter().convert(rows);

    final dir = await getTemporaryDirectory();
    final timestamp = session.startedAt
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final fileName = 'ebstat_${session.mode}_$timestamp.csv';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(csvString);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'EbStat — ${session.mode} measurement data',
    );
  }
}
