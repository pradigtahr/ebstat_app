// =============================================================================
// EBstat firmware protocol definitions and parsers.
// All constants and comment-labels mirror EBstat_BLE/src/main.c so the
// firmware author can cross-validate this file directly.
// =============================================================================

// ── NUS (Nordic UART Service) UUIDs ──────────────────────────────────────────
// Bluetooth SIG–assigned UUIDs for the Nordic Semiconductor UART profile.
// Matches the UUIDs registered in the firmware via BT_UUID_DECLARE_128.
class NusUuids {
  /// Primary service UUID (6E400001-…)
  static const service = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';

  /// RX characteristic — app WRITES commands TO the device
  /// (firmware: NUS RX UUID 6E400002-…; device receives here)
  static const rx = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';

  /// TX characteristic — device SENDS data TO the app (notifications)
  /// (firmware: NUS TX UUID 6E400003-…; device notifies here)
  static const tx = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';
}

// ── Firmware command strings ──────────────────────────────────────────────────
// Matches the case-insensitive string comparisons in cmd_dispatch() in main.c
class FwCmd {
  static const stop   = 'STOP';
  static const status = 'STATUS';
  static const caps   = 'CAPS';
  static const help   = 'HELP';
  static const lmp    = 'LMP';
  static const ca     = 'CA';
  static const cv     = 'CV';
  static const npv    = 'NPV';
  static const dpv    = 'DPV';
  static const swv    = 'SWV';
}

// ── Response terminators ──────────────────────────────────────────────────────
// Firmware emits exactly one of these at end of every command response:
//   ebs_log("DONE\n")     — successful completion
//   ebs_log("ABORTED\n")  — aborted by STOP command
class FwTerminator {
  static const done    = 'DONE';
  static const aborted = 'ABORTED';
  static bool is_(String line) => line == done || line == aborted;
}

// ── Result of a completed firmware command ────────────────────────────────────
class RunResult {
  /// True if the run ended with ABORTED instead of DONE
  final bool aborted;

  /// All accumulated "# key=val" metadata (merged across all metadata lines)
  final Map<String, String> metadata;

  /// CSV column names from the first non-# line (empty if no CSV output)
  final List<String> header;

  /// Raw CSV data rows (each is a comma-separated string; excludes header)
  final List<String> rawRows;

  const RunResult({
    required this.aborted,
    this.metadata = const {},
    this.header = const [],
    this.rawRows = const [],
  });

  bool get hasData => header.isNotEmpty && rawRows.isNotEmpty;

  /// Convenience: parse rawRows using header into [{colName: value}, …]
  List<Map<String, String>> get parsedRows => rawRows.map((row) {
        final vals = row.split(',');
        return {
          for (var i = 0; i < header.length; i++)
            header[i]: i < vals.length ? vals[i].trim() : '',
        };
      }).toList();

  /// Convenience: get a double column by name from a parsed row
  static double? num(Map<String, String> row, String col) =>
      double.tryParse(row[col] ?? '');
}

// ── Progress update ───────────────────────────────────────────────────────────
// Firmware: ebs_log("# progress=%d/%d\n", idx + 1, total)
// Emitted every PROGRESS_EVERY_N rows (= 25 in firmware).
class ProgressUpdate {
  final int current;
  final int total;
  double get fraction => total > 0 ? current / total : 0.0;
  const ProgressUpdate(this.current, this.total);
}

// ── All parsing logic ─────────────────────────────────────────────────────────
class EbstatProtocol {
  // ── Metadata lines ────────────────────────────────────────────────────────
  // Firmware: ebs_log("# key1=val1, key2=val2\n")
  // Each "# …" line may contain multiple comma-separated key=val pairs.

  static bool isMetadata(String line) => line.startsWith('#');

  /// Parse "# key1=val1, key2=val2, …" → {key1: val1, key2: val2, …}
  /// Free-text comment lines (no '=' tokens) return an empty map.
  static Map<String, String> parseMetadata(String line) {
    final body = line.startsWith('#') ? line.substring(1).trim() : line;
    // Skip decorator lines like "# === Capabilities ==="
    if (body.startsWith('===') || body.startsWith('---')) return {};
    final result = <String, String>{};
    for (final token in body.split(',')) {
      final eq = token.indexOf('=');
      if (eq < 0) continue;
      final key   = token.substring(0, eq).trim();
      final value = token.substring(eq + 1).trim();
      if (key.isNotEmpty) result[key] = value;
    }
    return result;
  }

  /// Extract a ProgressUpdate from a parsed metadata map, or null.
  /// Firmware: ebs_log("# progress=%d/%d\n", idx + 1, total)
  static ProgressUpdate? extractProgress(Map<String, String> meta) {
    final raw = meta['progress'];
    if (raw == null) return null;
    final parts = raw.split('/');
    if (parts.length != 2) return null;
    final cur = int.tryParse(parts[0].trim());
    final tot = int.tryParse(parts[1].trim());
    if (cur == null || tot == null) return null;
    return ProgressUpdate(cur, tot);
  }

  // ── CSV lines ─────────────────────────────────────────────────────────────
  // The FIRST non-# non-terminator line after a command is the CSV header.
  // Subsequent lines until DONE/ABORTED are data rows.
  // Firmware emits headers with trailing comma in some versions — trim handles it.

  static List<String> parseCsvLine(String line) =>
      line.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  // ── LMP91000 configuration tables ────────────────────────────────────────
  // Mirrors the code→label tables in main.c (gain_name(), etc.)

  /// gain_code → Ω label  (firmware: LMP91000_GAIN_* constants)
  static const Map<int, String> gainLabels = {
    0: 'External',
    1: '2.75 kΩ',
    2: '3.5 kΩ',
    3: '7 kΩ',
    4: '14 kΩ',
    5: '35 kΩ',
    6: '120 kΩ',
    7: '350 kΩ',
  };

  /// rload_code → label  (firmware: LMP91000_RLOAD_* constants)
  static const Map<int, String> rloadLabels = {
    0: '10 Ω',
    1: '33 Ω',
    2: '50 Ω',
    3: '100 Ω',
  };

  /// intz_code → label  (firmware: LMP91000_INTZ_* constants)
  static const Map<int, String> intzLabels = {
    0: '20 %',
    1: '50 %',
    2: '67 %',
    3: 'Bypass',
  };

  /// bias_pct_code → actual % value
  /// (firmware: lmp91000_bias_pct_x10 table, 14 entries)
  static const List<int> biasPctValues = [
    0, 1, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24,
  ];

  // ── Technique command builder ─────────────────────────────────────────────

  /// Default parameter values for each technique (mV / ms / Hz).
  /// Matches the firmware's built-in safe defaults.
  static const Map<String, List<dynamic>> techniqueDefaults = {
    FwCmd.ca:  [0,    200,  2000, 100, 50],   // E_quiet, E_step, quiet_ms, step_ms, samples
    FwCmd.cv:  [-200, 500,  5,    50,  1],     // V_start, V_vertex, step_mV, rate, n_cycles
    FwCmd.npv: [-200, 600,  10,   50,  5],     // E_start, E_end, dE_step, dE_pulse, freq_hz
    FwCmd.dpv: [-200, 600,  10,   50,  5],
    FwCmd.swv: [-200, 600,  10,   50,  25],
  };

  static const Map<String, List<String>> techniqueParamNames = {
    FwCmd.ca:  ['E_quiet_mV', 'E_step_mV', 'quiet_ms', 'step_ms', 'samples'],
    FwCmd.cv:  ['V_start_mV', 'V_vertex_mV', 'step_mV', 'scan_rate_mV_s', 'n_cycles'],
    FwCmd.npv: ['E_start_mV', 'E_end_mV', 'dE_step_mV', 'dE_pulse_mV', 'freq_hz'],
    FwCmd.dpv: ['E_start_mV', 'E_end_mV', 'dE_step_mV', 'dE_pulse_mV', 'freq_hz'],
    FwCmd.swv: ['E_start_mV', 'E_end_mV', 'dE_step_mV', 'dE_pulse_mV', 'freq_hz'],
  };

  /// Build a firmware command string, e.g. "CV,-200,500,5,50,1\n"
  static String buildMeasurementCmd(
    String technique,
    Map<String, dynamic> params, {
    int? id,
  }) {
    final names    = techniqueParamNames[technique.toUpperCase()] ?? [];
    final defaults = techniqueDefaults[technique.toUpperCase()] ?? [];
    final args = List.generate(names.length, (i) {
      final key = names[i];
      return params.containsKey(key) ? params[key] : (i < defaults.length ? defaults[i] : 0);
    });
    final cmd = '${technique.toUpperCase()},${args.join(',')}';
    return id != null ? 'ID:$id,$cmd' : cmd;
  }

  /// Build an LMP configuration command string.
  /// Firmware: LMP,<gain>,<rload>,<intz>,<biassign>,<biaspct>,<refsrc>
  static String buildLmpCmd({
    required int gain,
    required int rload,
    required int intz,
    required int biasSign,
    required int biasPct,
    required int refSrc,
  }) =>
      'LMP,$gain,$rload,$intz,$biasSign,$biasPct,$refSrc';
}
