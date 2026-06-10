import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/lmp_constants.dart';
import '../models/voltammetry_mode.dart';
import '../providers/measurement_provider.dart';
import '../services/preset_service.dart';
import '../theme/app_theme.dart';
import 'measurement_screen.dart';


class ParametersScreen extends StatefulWidget {
  const ParametersScreen({super.key, required this.mode});
  final VoltammetryMode mode;

  @override
  State<ParametersScreen> createState() => _ParametersScreenState();
}

class _ParametersScreenState extends State<ParametersScreen> {
  final _formKey    = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};

  // SG filter display options: label → windowSize value
  static const _sgOptions = <String, int>{
    'None':            -1,
    'Spike rejection':  0,
    'Low':              5,
    'Medium':           9,
    'High':            15,
    'Very high':       25,
  };

  bool   _sgOn     = false;
  int    _sgWindow = -1;
  double _rtiaKOhm = 35.0;

  @override
  void initState() {
    super.initState();
    for (final p in modeParameters[widget.mode]!) {
      _controllers[p.key] = TextEditingController();
    }
    final mp = context.read<MeasurementProvider>();
    _sgOn     = mp.sgEnabled;
    _sgWindow = mp.sgFilterWindow;
    final gc = mp.selectedGainCode;
    _rtiaKOhm = kRtiaRanges
        .firstWhere(
          (r) => rtiaToGainCode(r.rtiaKOhm) == gc,
          orElse: () => kRtiaRanges[4], // 35 kΩ
        )
        .rtiaKOhm;
  }

  void _applyToProvider() {
    final mp = context.read<MeasurementProvider>();
    mp.setSgEnabled(_sgOn);
    mp.setSgFilterWindow(_sgOn ? _sgWindow : -1);
    mp.setSelectedGainCode(rtiaToGainCode(_rtiaKOhm));
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  // ── Hardware controls (current range + SG filter) ─────────────────────────

  Widget _buildHardwareControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('CURRENT RANGE',
            style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
        const SizedBox(height: 8),
        DropdownButtonFormField<double>(
          value: _rtiaKOhm,
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
            prefixIcon: const Icon(Icons.electric_bolt_outlined,
                color: AppColors.accent2, size: 18),
          ),
          items: kRtiaRanges
              .map((r) => DropdownMenuItem(
                    value: r.rtiaKOhm,
                    child: Text(
                      '±${r.rangeUA % 1 == 0 ? r.rangeUA.toInt() : r.rangeUA} µA',
                    ),
                  ))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() => _rtiaKOhm = v);
            _applyToProvider();
          },
        ),
        const SizedBox(height: 16),
        const Text('REAL-TIME SG FILTER',
            style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
        const SizedBox(height: 4),
        Row(
          children: [
            const Expanded(
              child: Text('Real-time SG Filter',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
            ),
            Switch(
              value: _sgOn,
              onChanged: (v) {
                setState(() => _sgOn = v);
                _applyToProvider();
              },
              activeColor: AppColors.accent1,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _sgOn
              ? Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: DropdownButtonFormField<int>(
                    value: _sgWindow,
                    dropdownColor: AppColors.surface,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: AppColors.divider),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: AppColors.divider),
                      ),
                    ),
                    items: _sgOptions.entries
                        .map((e) => DropdownMenuItem(
                              value: e.value,
                              child: Text(e.key),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _sgWindow = v);
                      _applyToProvider();
                    },
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final params = modeParameters[widget.mode]!;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.mode.abbreviation} Parameters'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmarks_outlined),
            tooltip: 'Presets',
            onPressed: _showPresetsSheet,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHardwareControls(),
                  const SizedBox(height: 8),
                  const Divider(color: AppColors.divider, height: 1),
                  const SizedBox(height: 16),
                  for (int i = 0; i < params.length; i++) ...[
                    _ParameterField(
                      parameter:  params[i],
                      controller: _controllers[params[i].key]!,
                    ),
                    if (i < params.length - 1) const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
            _StartButton(onPressed: _onStart),
          ],
        ),
      ),
    );
  }

  // ── Presets ───────────────────────────────────────────────────────────────

  Future<void> _showPresetsSheet() async {
    final tech = widget.mode.abbreviation;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _PresetsSheet(
        technique: tech,
        onLoad: _loadPreset,
        onSaveCurrent: () => _saveCurrentPreset(ctx),
      ),
    );
  }

  void _loadPreset(Preset preset) {
    for (final entry in preset.params.entries) {
      _controllers[entry.key]?.text =
          entry.value.toStringAsFixed(0);
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveCurrentPreset(BuildContext sheetCtx) async {
    final name = await _promptName();
    if (name == null || name.isEmpty) return;
    final currentParams = <String, double>{};
    for (final entry in _controllers.entries) {
      currentParams[entry.key] =
          double.tryParse(entry.value.text) ?? 0;
    }
    await PresetService.savePreset(
        widget.mode.abbreviation, name, currentParams);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Preset "$name" saved.')),
      );
    }
  }

  Future<String?> _promptName() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Preset name',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
              hintText: 'e.g. Default CV, High sensitivity…'),
          onSubmitted: (_) =>
              Navigator.of(ctx).pop(ctrl.text.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
  }

  // ── Start ─────────────────────────────────────────────────────────────────

  Future<void> _onStart() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<MeasurementProvider>();
    for (final entry in _controllers.entries) {
      final value = double.tryParse(entry.value.text);
      if (value != null) provider.updateParameter(entry.key, value);
    }

    final scanNumber = (provider.project?.measurements.length ?? 0) + 1;
    final label = await _showLabelDialog('Scan $scanNumber');
    if (label == null || !mounted) return;

    provider.setNextLabel(label.isEmpty ? 'Scan $scanNumber' : label);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MeasurementScreen()),
    );
  }

  Future<String?> _showLabelDialog(String defaultLabel) async {
    final controller = TextEditingController(text: defaultLabel);
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Label this measurement',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
              hintText: 'e.g. 5 µM, blank, standard…'),
          onSubmitted: (_) =>
              Navigator.of(ctx).pop(controller.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }
}

// ── Presets bottom sheet ──────────────────────────────────────────────────────
class _PresetsSheet extends StatefulWidget {
  const _PresetsSheet({
    required this.technique,
    required this.onLoad,
    required this.onSaveCurrent,
  });
  final String technique;
  final void Function(Preset) onLoad;
  final VoidCallback onSaveCurrent;

  @override
  State<_PresetsSheet> createState() => _PresetsSheetState();
}

class _PresetsSheetState extends State<_PresetsSheet> {
  List<Preset>? _presets;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await PresetService.loadPresets(widget.technique);
    if (mounted) setState(() => _presets = list);
  }

  Future<void> _delete(String name) async {
    await PresetService.deletePreset(widget.technique, name);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      builder: (_, ctrl) => Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Text('Presets',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onSaveCurrent();
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Save current'),
                ),
              ],
            ),
          ),
          const Divider(color: AppColors.divider, height: 1),
          Expanded(
            child: _presets == null
                ? const Center(child: CircularProgressIndicator())
                : _presets!.isEmpty
                    ? const Center(
                        child: Text('No saved presets.',
                            style: TextStyle(
                                color: AppColors.textSecondary)),
                      )
                    : ListView.separated(
                        controller: ctrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: _presets!.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final preset = _presets![i];
                          return ListTile(
                            tileColor: AppColors.cardBg,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            leading: const Icon(Icons.bookmark,
                                color: AppColors.accent2),
                            title: Text(preset.name,
                                style: const TextStyle(
                                    color: Colors.white)),
                            subtitle: Text(
                              preset.params.entries
                                  .map((e) =>
                                      '${e.key}: ${e.value.toStringAsFixed(0)}')
                                  .join(' · '),
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent, size: 18),
                              onPressed: () => _delete(preset.name),
                            ),
                            onTap: () {
                              Navigator.of(context).pop();
                              widget.onLoad(preset);
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Parameter field ───────────────────────────────────────────────────────────
class _ParameterField extends StatelessWidget {
  const _ParameterField(
      {required this.parameter, required this.controller});
  final VoltammetryParameter parameter;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: false, signed: true),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: parameter.label,
        hintText: 'e.g. ${parameter.hint}',
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
        suffixText: parameter.unit,
        suffixStyle: const TextStyle(color: AppColors.accent2),
        helperText: _rangeText,
        helperStyle:
            const TextStyle(color: AppColors.textSecondary, fontSize: 11),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Required';
        final num = double.tryParse(v.trim());
        if (num == null) return 'Enter a valid number';
        if (parameter.min != null && num < parameter.min!)
          return 'Min: ${parameter.min!.toStringAsFixed(0)}';
        if (parameter.max != null && num > parameter.max!)
          return 'Max: ${parameter.max!.toStringAsFixed(0)}';
        return null;
      },
    );
  }

  String? get _rangeText {
    if (parameter.min == null && parameter.max == null) return null;
    final parts = <String>[];
    if (parameter.min != null) {
      parts.add('min: ${parameter.min!.toStringAsFixed(0)}');
    }
    if (parameter.max != null) {
      parts.add('max: ${parameter.max!.toStringAsFixed(0)}');
    }
    return parts.join(' · ');
  }
}

// ── Start button ──────────────────────────────────────────────────────────────
class _StartButton extends StatelessWidget {
  const _StartButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        decoration: const BoxDecoration(
          color: AppColors.primary,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start Measurement'),
        ),
      );
}
