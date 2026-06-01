import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/project_session.dart';

class XlsxExportService {
  static Future<void> export(ProjectSession project) async {
    final excel = Excel.createExcel();
    // Remove the default blank sheet
    excel.delete('Sheet1');

    for (var i = 0; i < project.measurements.length; i++) {
      final session = project.measurements[i];
      final sheetName = 'Scan ${i + 1}';
      final sheet = excel[sheetName];

      // Header rows
      sheet.appendRow([
        TextCellValue('EbStat — ${session.mode} measurement'),
      ]);
      sheet.appendRow([
        TextCellValue('Started'),
        TextCellValue(session.startedAt.toIso8601String()),
      ]);
      sheet.appendRow([TextCellValue('--- Parameters ---')]);
      for (final entry in session.parameters.entries) {
        sheet.appendRow([
          TextCellValue(entry.key),
          DoubleCellValue(entry.value),
        ]);
      }
      sheet.appendRow([TextCellValue('--- Data ---')]);
      sheet.appendRow([
        TextCellValue(session.mode == 'CA' ? 'Time (ms)' : 'Potential (mV)'),
        TextCellValue('Current (nA)'),
      ]);
      for (final pt in session.points) {
        sheet.appendRow([
          DoubleCellValue(pt.x),
          DoubleCellValue(pt.y),
        ]);
      }
    }

    // Peaks sheet
    if (project.peaks.isNotEmpty) {
      final peakSheet = excel['Peaks'];
      peakSheet.appendRow([
        TextCellValue('Scan'),
        TextCellValue('Type'),
        TextCellValue('Potential (mV)'),
        TextCellValue('Current (nA)'),
      ]);
      for (final peak in project.peaks) {
        peakSheet.appendRow([
          IntCellValue(peak.measurementIndex + 1),
          TextCellValue(peak.type == PeakType.cathodic ? 'Cathodic' : 'Anodic'),
          DoubleCellValue(peak.point.x),
          DoubleCellValue(peak.point.y),
        ]);
      }
    }

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Failed to encode workbook');

    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final fileName = 'ebstat_${project.modeName}_$timestamp.xlsx';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
      subject: 'EbStat — ${project.modeName} project data',
    );
  }
}
