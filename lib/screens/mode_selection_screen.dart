import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/lmp_constants.dart';
import '../models/voltammetry_mode.dart';
import '../providers/measurement_provider.dart';
import '../theme/app_theme.dart';
import 'lmp_config_screen.dart';
import 'parameters_screen.dart';

class ModeSelectionScreen extends StatefulWidget {
  const ModeSelectionScreen({super.key});

  @override
  State<ModeSelectionScreen> createState() => _ModeSelectionScreenState();
}

class _ModeSelectionScreenState extends State<ModeSelectionScreen> {
  static const _descriptions = {
    VoltammetryMode.cv:
        'Potential swept back and forth; reveals redox peak positions and reversibility.',
    VoltammetryMode.ca:
        'Potential stepped and current monitored over time; useful for kinetic studies.',
    VoltammetryMode.swv:
        'Square-wave excitation applied; high sensitivity with low background noise.',
    VoltammetryMode.dpv:
        'Differential pulses applied; excellent for trace analyte detection.',
    VoltammetryMode.npv:
        'Increasing pulse amplitudes applied from base potential; measures absolute current.',
  };

  static const _icons = {
    VoltammetryMode.cv:  Icons.loop,
    VoltammetryMode.ca:  Icons.timer_outlined,
    VoltammetryMode.swv: Icons.square_foot,
    VoltammetryMode.dpv: Icons.bar_chart,
    VoltammetryMode.npv: Icons.stacked_line_chart,
  };

  // SG filter display options: label → windowSize value
  static const _sgOptions = <String, int>{
    'None':            -1,
    'Spike rejection':  0,
    'Low':              5,
    'Medium':           9,
    'High':            15,
    'Very high':       25,
  };

  bool _sgOn       = false;
  int  _sgWindow   = -1; // -1 = None
  double _rtiaKOhm = 35.0; // default ±65 µA

  @override
  void initState() {
    super.initState();
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
  Widget build(BuildContext context) {
    final measurement = context.watch<MeasurementProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Voltammetry Mode'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_outlined),
            tooltip: 'LMP91000 Advanced Configuration',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LmpConfigScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Current range + SG filter selectors ──────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Current range
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
                              '±${r.rangeUA % 1 == 0 ? r.rangeUA.toInt() : r.rangeUA} µA'
                              '  (RTIA ${r.rtiaKOhm} kΩ)',
                            ),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _rtiaKOhm = v);
                    _applyToProvider();
                  },
                ),
                const SizedBox(height: 12),

                // SG filter
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
                          padding: const EdgeInsets.only(bottom: 4),
                          child: DropdownButtonFormField<int>(
                            value: _sgWindow,
                            dropdownColor: AppColors.surface,
                            style:
                                const TextStyle(color: Colors.white, fontSize: 14),
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
                const SizedBox(height: 8),
                const Divider(color: AppColors.divider, height: 1),
                const SizedBox(height: 4),
              ],
            ),
          ),

          // ── Mode cards ────────────────────────────────────────────────────
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: VoltammetryMode.values.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final mode       = VoltammetryMode.values[i];
                final isSelected = measurement.selectedMode == mode;
                return _ModeCard(
                  mode:        mode,
                  description: _descriptions[mode]!,
                  icon:        _icons[mode]!,
                  isSelected:  isSelected,
                  onTap: () {
                    context.read<MeasurementProvider>().selectMode(mode);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ParametersScreen(mode: mode)),
                    );
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

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.description,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final VoltammetryMode mode;
  final String          description;
  final IconData        icon;
  final bool            isSelected;
  final VoidCallback    onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.accent1 : AppColors.divider,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(
                  color: AppColors.accent1.withOpacity(0.2),
                  blurRadius: 8, spreadRadius: 1)]
              : [],
        ),
        child: Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.accent1.withOpacity(0.2)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: isSelected ? AppColors.accent1 : AppColors.accent2,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(
                    mode.abbreviation,
                    style: TextStyle(
                      color: isSelected ? AppColors.accent1 : Colors.white,
                      fontSize: 18, fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      mode.fullName,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(description,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        ]),
      ),
    );
  }
}
