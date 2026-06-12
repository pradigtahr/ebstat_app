import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/measurement_point.dart';
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
      buf.writeln(isCa ? 'time_s/Current' : 'Potential/Current');
      buf.writeln('Date');
      buf.writeln(isCa ? 'time_s,µA' : 'V,µA');

      // Section 3 – data rows (convert mV→V or ms→s, nA→µA)
      final isCv = session.mode == 'CV';
      if (isCv) {
        int sgOffset = 0;
        final cycles = session.cycles.toList()..sort();
        for (final cNum in cycles) {
          final cyclePts = session.points.where((p) => p.cycle == cNum).toList();
          buf.writeln('Cycle $cNum');
          final ys = _buildYs(cyclePts, session, sgOffset);
          for (int j = 0; j < cyclePts.length; j++) {
            final x = cyclePts[j].x / 1000;
            buf.writeln('${x.toStringAsFixed(6)},${ys[j].toStringAsFixed(6)}');
          }
          sgOffset += cyclePts.length;
        }
      } else {
        final pts = session.points;
        final ys  = _buildYs(pts, session, 0);
        for (int j = 0; j < pts.length; j++) {
          final x = pts[j].x / 1000;
          buf.writeln('${x.toStringAsFixed(6)},${ys[j].toStringAsFixed(6)}');
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

  static List<double> _buildYs(
      List<MeasurementPoint> pts, MeasurementSession session, int sgOffset) {
    if (!session.sgEnabled || !session.hasSgData) {
      return pts.map((p) => p.y / 1000).toList();
    }
    return List.generate(pts.length, (i) {
      final sgIdx = sgOffset + i;
      final sg    = sgIdx < session.sgPoints.length ? session.sgPoints[sgIdx] : null;
      return (sg ?? pts[i].y) / 1000;
    });
  }
}
