import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/project_session.dart';

class CsvExportService {
  /// Export all measurements in [project] to a single CSV file with header
  /// metadata, optional experiment summary, and grouped raw data.
  static Future<void> export(ProjectSession project) async {
    final rows = <List<dynamic>>[];

    for (int mIdx = 0; mIdx < project.measurements.length; mIdx++) {
      final session = project.measurements[mIdx];
      if (mIdx > 0) {
        // Visual separator between measurements
        rows.add(['---']);
        rows.add([]);
      }

      // ── Section 1: Header metadata ────────────────────────────────────────
      rows.add(['Date and time:', session.startedAt.toIso8601String()]);
      rows.add(['Technique:', session.mode]);
      if (session.label.isNotEmpty) rows.add(['Label:', session.label]);
      for (final e in session.parameters.entries) {
        rows.add(['${e.key}:', e.value]);
      }

      // ── Section 2: Experiment Summary (only if peaks registered) ─────────
      final ipa = project.ipa;
      final ipc = project.ipc;
      final epa = project.epa;
      final epc = project.epc;
      final hasSummary = ipa != null || ipc != null || epa != null || epc != null;
      if (hasSummary) {
        rows.add([]);
        rows.add(['Experiment Summary']);
        if (ipa != null) rows.add(['Ipa (µA):', ipa.toStringAsFixed(4)]);
        if (ipc != null) rows.add(['Ipc (µA):', ipc.toStringAsFixed(4)]);
        if (epa != null) rows.add(['Epa (mV):', epa.toStringAsFixed(2)]);
        if (epc != null) rows.add(['Epc (mV):', epc.toStringAsFixed(2)]);
      }

      // ── Section 3: Raw data ───────────────────────────────────────────────
      rows.add([]);
      final isCa = session.mode == 'CA';
      final isCv = session.mode == 'CV';
      rows.add([
        isCa ? 'Time (ms)' : 'Potential (mV)',
        'Current (nA)',
      ]);

      if (isCv) {
        final cycles = session.cycles.toList()..sort();
        for (final cNum in cycles) {
          rows.add(['Cycle $cNum']);
          for (final pt in session.points.where((p) => p.cycle == cNum)) {
            rows.add([pt.x, pt.y]);
          }
        }
      } else {
        for (final pt in session.points) {
          rows.add([pt.x, pt.y]);
        }
      }
    }

    final csvString = const ListToCsvConverter().convert(rows);
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final fileName = 'ebstat_${project.modeName}_$timestamp.csv';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(csvString);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'EbStat — ${project.modeName} measurement data',
      ),
    );
  }
}
