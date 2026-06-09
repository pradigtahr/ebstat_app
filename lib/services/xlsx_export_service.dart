import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/project_session.dart';

class XlsxExportService {
  static Future<void> export(ProjectSession project) async {
    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    for (var i = 0; i < project.measurements.length; i++) {
      final session   = project.measurements[i];
      final sheetName = 'Scan ${i + 1}';
      final sheet     = excel[sheetName];
      final isCa      = session.mode == 'CA';
      final isCv      = session.mode == 'CV';

      // ── Section 1: Header metadata ────────────────────────────────────────
      sheet.appendRow([TextCellValue('Date and time:'),
          TextCellValue(session.startedAt.toIso8601String())]);
      sheet.appendRow([TextCellValue('Technique:'), TextCellValue(session.mode)]);
      if (session.label.isNotEmpty) {
        sheet.appendRow([TextCellValue('Label:'), TextCellValue(session.label)]);
      }
      for (final entry in session.parameters.entries) {
        sheet.appendRow([TextCellValue('${entry.key}:'), DoubleCellValue(entry.value)]);
      }

      // ── Section 2: Experiment Summary ─────────────────────────────────────
      final ipa = project.ipa;
      final ipc = project.ipc;
      final epa = project.epa;
      final epc = project.epc;
      final hasSummary = ipa != null || ipc != null || epa != null || epc != null;
      if (hasSummary) {
        sheet.appendRow([TextCellValue('')]);
        sheet.appendRow([TextCellValue('Experiment Summary')]);
        if (ipa != null) sheet.appendRow([TextCellValue('Ipa (µA):'), DoubleCellValue(ipa)]);
        if (ipc != null) sheet.appendRow([TextCellValue('Ipc (µA):'), DoubleCellValue(ipc)]);
        if (epa != null) sheet.appendRow([TextCellValue('Epa (mV):'), DoubleCellValue(epa)]);
        if (epc != null) sheet.appendRow([TextCellValue('Epc (mV):'), DoubleCellValue(epc)]);
      }

      // ── Section 3: Raw data ───────────────────────────────────────────────
      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow([
        TextCellValue(isCa ? 'Time (ms)' : 'Potential (mV)'),
        TextCellValue('Current (nA)'),
      ]);

      if (isCv) {
        final cycles = session.cycles.toList()..sort();
        for (final cNum in cycles) {
          sheet.appendRow([TextCellValue('Cycle $cNum')]);
          for (final pt in session.points.where((p) => p.cycle == cNum)) {
            sheet.appendRow([DoubleCellValue(pt.x), DoubleCellValue(pt.y)]);
          }
        }
      } else {
        for (final pt in session.points) {
          sheet.appendRow([DoubleCellValue(pt.x), DoubleCellValue(pt.y)]);
        }
      }
    }

    // ── Peaks sheet (manual point annotations) ─────────────────────────────
    if (project.peaks.isNotEmpty) {
      final peakSheet = excel['Peak Annotations'];
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

    // ── Registered peaks sheet (tangent-method) ───────────────────────────
    if (project.registeredPeaks.isNotEmpty) {
      final regSheet = excel['Registered Peaks'];
      regSheet.appendRow([
        TextCellValue('Scan'),
        TextCellValue('Type'),
        TextCellValue('Ep (V)'),
        TextCellValue('ip (µA)'),
      ]);
      for (final pk in project.registeredPeaks) {
        regSheet.appendRow([
          IntCellValue(pk.measurementIdx + 1),
          TextCellValue(pk.effectivePeakType == PeakType.cathodic ? 'Cathodic' : 'Anodic'),
          DoubleCellValue(pk.ep),
          DoubleCellValue(pk.ip),
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

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
        subject: 'EbStat — ${project.modeName} project data',
      ),
    );
  }
}
