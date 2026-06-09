import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/project_session.dart';

/// Exports all measurements in a PalmSens-compatible TXT format (firmware-style
/// raw text): header → separator → series header → units → data rows.
class TxtExportService {
  static Future<void> export(ProjectSession project) async {
    final buf = StringBuffer();

    for (int i = 0; i < project.measurements.length; i++) {
      final session = project.measurements[i];
      if (i > 0) buf.writeln('\n\n');

      final isCa = session.mode == 'CA';

      // Section 1 – header
      buf.writeln('Date and time:,${session.startedAt.toIso8601String()}');
      buf.writeln('Technique:,${session.mode}');
      if (session.label.isNotEmpty) buf.writeln('Label:,${session.label}');
      buf.writeln('Notes:');
      buf.writeln();

      // Section 2 – series name / date / units
      buf.writeln(isCa ? 'Time/Current' : 'Potential/Current');
      buf.writeln('Date');
      buf.writeln(isCa ? 's,µA' : 'V,µA');

      // Section 3 – data rows (convert mV→V, nA→µA)
      final isCv = session.mode == 'CV';
      if (isCv) {
        final cycles = session.cycles.toList()..sort();
        for (final cNum in cycles) {
          buf.writeln('Cycle $cNum');
          for (final pt in session.points.where((p) => p.cycle == cNum)) {
            final x = isCa ? pt.x / 1000 : pt.x / 1000; // ms→s or mV→V
            final y = pt.y / 1000; // nA→µA
            buf.writeln('${x.toStringAsFixed(6)},${y.toStringAsFixed(6)}');
          }
        }
      } else {
        for (final pt in session.points) {
          final x = isCa ? pt.x / 1000 : pt.x / 1000;
          final y = pt.y / 1000;
          buf.writeln('${x.toStringAsFixed(6)},${y.toStringAsFixed(6)}');
        }
      }
    }

    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final fileName = 'ebstat_${project.modeName}_$timestamp.txt';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(buf.toString());

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/plain')],
        subject: 'EbStat — ${project.modeName} measurement data',
      ),
    );
  }
}
