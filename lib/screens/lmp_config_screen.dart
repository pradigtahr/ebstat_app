import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ble/protocol.dart';
import '../providers/ble_provider.dart';
import '../theme/app_theme.dart';

class LmpConfigScreen extends StatefulWidget {
  const LmpConfigScreen({super.key});

  @override
  State<LmpConfigScreen> createState() => _LmpConfigScreenState();
}

class _LmpConfigScreenState extends State<LmpConfigScreen> {
  // Current selections (default to index 0 of each list)
  int _gain     = 0;
  int _rload    = 0;
  int _intz     = 0;
  int _biasSign = 0; // 0 = negative, 1 = positive
  int _biasPct  = 0; // index into EbstatProtocol.biasPctValues
  int _refSrc   = 0; // 0 = internal, 1 = external

  bool _sending = false;
  bool _querying = false;
  String? _statusMsg;
  Map<String, String>? _capsMetadata;

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('LMP91000 Configuration'),
        actions: [
          if (ble.isConnected)
            IconButton(
              icon: _querying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.memory_outlined),
              tooltip: 'Query capabilities (CAPS)',
              onPressed: _querying ? null : () => _queryCaps(ble),
            ),
        ],
      ),
      body: Column(
        children: [
          if (!ble.isConnected) _NotConnectedBanner(),
          if (_statusMsg != null) _StatusBanner(message: _statusMsg!),
          if (_capsMetadata != null) _CapsCard(metadata: _capsMetadata!),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Gain ────────────────────────────────────────────────────
                _ConfigRow(
                  label: 'TIA Gain',
                  subtitle: 'Transimpedance amplifier feedback resistor',
                  child: _DropdownField<int>(
                    value: _gain,
                    items: EbstatProtocol.gainLabels.entries
                        .map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _gain = v!),
                  ),
                ),
                const _Divider(),

                // ── RLOAD ───────────────────────────────────────────────────
                _ConfigRow(
                  label: 'Rₗ₀ₐ₉ (Load Resistor)',
                  subtitle: 'Zero-bias load resistor value',
                  child: _DropdownField<int>(
                    value: _rload,
                    items: EbstatProtocol.rloadLabels.entries
                        .map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _rload = v!),
                  ),
                ),
                const _Divider(),

                // ── INTZ ────────────────────────────────────────────────────
                _ConfigRow(
                  label: 'Internal Zero',
                  subtitle: 'Reference voltage percentage of VREF',
                  child: _DropdownField<int>(
                    value: _intz,
                    items: EbstatProtocol.intzLabels.entries
                        .map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _intz = v!),
                  ),
                ),
                const _Divider(),

                // ── Bias sign + value ────────────────────────────────────────
                _ConfigRow(
                  label: 'Bias Voltage',
                  subtitle: 'Applied bias = sign × percent of VREF',
                  child: Row(
                    children: [
                      // Sign toggle
                      ToggleButtons(
                        isSelected: [_biasSign == 0, _biasSign == 1],
                        onPressed: (i) =>
                            setState(() => _biasSign = i),
                        borderRadius: BorderRadius.circular(8),
                        selectedColor: AppColors.accent1,
                        fillColor: AppColors.accent1.withOpacity(0.15),
                        borderColor: AppColors.divider,
                        selectedBorderColor: AppColors.accent1,
                        constraints: const BoxConstraints(
                            minWidth: 44, minHeight: 36),
                        children: const [
                          Text('−', style: TextStyle(fontSize: 16)),
                          Text('+', style: TextStyle(fontSize: 16)),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DropdownField<int>(
                          value: _biasPct,
                          items: List.generate(
                            EbstatProtocol.biasPctValues.length,
                            (i) => DropdownMenuItem(
                              value: i,
                              child: Text(
                                  '${EbstatProtocol.biasPctValues[i]} %'),
                            ),
                          ),
                          onChanged: (v) =>
                              setState(() => _biasPct = v!),
                        ),
                      ),
                    ],
                  ),
                ),
                const _Divider(),

                // ── Reference source ─────────────────────────────────────────
                _ConfigRow(
                  label: 'Reference Source',
                  subtitle: 'VREF source for the internal zero circuit',
                  child: _DropdownField<int>(
                    value: _refSrc,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Internal (50 %)')),
                      DropdownMenuItem(value: 1, child: Text('External')),
                    ],
                    onChanged: (v) => setState(() => _refSrc = v!),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Preview ───────────────────────────────────────────────────
                _PreviewCard(
                  gain:     _gain,
                  rload:    _rload,
                  intz:     _intz,
                  biasSign: _biasSign,
                  biasPct:  _biasPct,
                  refSrc:   _refSrc,
                ),
              ],
            ),
          ),

          // ── Bottom action bar ─────────────────────────────────────────────
          _ActionBar(
            enabled: ble.isConnected && !_sending,
            sending: _sending,
            onReset: () => setState(() {
              _gain = 0; _rload = 0; _intz = 0;
              _biasSign = 0; _biasPct = 0; _refSrc = 0;
            }),
            onApply: () => _applyConfig(ble),
          ),
        ],
      ),
    );
  }

  Future<void> _queryCaps(BleProvider ble) async {
    setState(() {
      _querying    = true;
      _statusMsg   = null;
      _capsMetadata = null;
    });
    try {
      final result = await ble.sendCommand(FwCmd.caps);
      setState(() {
        _capsMetadata = result.metadata.isEmpty ? null : result.metadata;
        _statusMsg = result.metadata.isEmpty
            ? 'No capability data received.'
            : 'Capabilities received.';
      });
    } catch (e) {
      setState(() => _statusMsg = 'Query failed: $e');
    } finally {
      setState(() => _querying = false);
    }
  }

  Future<void> _applyConfig(BleProvider ble) async {
    setState(() {
      _sending   = true;
      _statusMsg = null;
    });
    final cmd = EbstatProtocol.buildLmpCmd(
      gain:     _gain,
      rload:    _rload,
      intz:     _intz,
      biasSign: _biasSign,
      biasPct:  _biasPct,
      refSrc:   _refSrc,
    );
    try {
      final result = await ble.sendCommand(cmd);
      final hasError = result.comments.any(
        (c) => c.toLowerCase().contains('err'),
      );
      setState(() {
        _statusMsg = hasError
            ? 'Device reported an error applying configuration.'
            : 'Configuration applied.';
      });
    } catch (e) {
      setState(() => _statusMsg = 'Error: $e');
    } finally {
      setState(() => _sending = false);
    }
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _NotConnectedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.redAccent.withOpacity(0.1),
        child: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.redAccent, size: 14),
            SizedBox(width: 8),
            Text('Not connected — connect a device to apply settings.',
                style: TextStyle(color: Colors.redAccent, fontSize: 12)),
          ],
        ),
      );
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: AppColors.accent1.withOpacity(0.12),
        child: Text(message,
            style: const TextStyle(color: AppColors.accent1, fontSize: 12)),
      );
}

class _CapsCard extends StatelessWidget {
  const _CapsCard({required this.metadata});
  final Map<String, String> metadata;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('DEVICE CAPABILITIES',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
            const SizedBox(height: 8),
            ...metadata.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                        flex: 2,
                        child: Text(e.key,
                            style: const TextStyle(
                                color: AppColors.accent2,
                                fontSize: 12,
                                fontFamily: 'monospace'))),
                    Expanded(
                        flex: 3,
                        child: Text(e.value,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontFamily: 'monospace'))),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _ConfigRow extends StatelessWidget {
  const _ConfigRow(
      {required this.label, required this.subtitle, required this.child});
  final String label;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      const Divider(color: AppColors.divider, height: 1);
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField(
      {required this.value,
      required this.items,
      required this.onChanged});
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
        value: value,
        items: items,
        onChanged: onChanged,
        dropdownColor: AppColors.surface,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          filled: true,
          fillColor: AppColors.surface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
        ),
      );
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.gain,
    required this.rload,
    required this.intz,
    required this.biasSign,
    required this.biasPct,
    required this.refSrc,
  });
  final int gain, rload, intz, biasSign, biasPct, refSrc;

  @override
  Widget build(BuildContext context) {
    final cmd = EbstatProtocol.buildLmpCmd(
      gain:     gain,
      rload:    rload,
      intz:     intz,
      biasSign: biasSign,
      biasPct:  biasPct,
      refSrc:   refSrc,
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('COMMAND PREVIEW',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
          const SizedBox(height: 6),
          Text(cmd,
              style: const TextStyle(
                  color: AppColors.accent1,
                  fontFamily: 'monospace',
                  fontSize: 13)),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.enabled,
    required this.sending,
    required this.onReset,
    required this.onApply,
  });
  final bool enabled;
  final bool sending;
  final VoidCallback onReset;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        decoration: const BoxDecoration(
          color: AppColors.primary,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            OutlinedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: enabled ? onApply : null,
                icon: sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send),
                label: Text(sending ? 'Sending…' : 'Apply Configuration'),
              ),
            ),
          ],
        ),
      );
}
