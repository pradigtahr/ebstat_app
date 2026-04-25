import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/voltammetry_mode.dart';
import '../providers/measurement_provider.dart';
import '../theme/app_theme.dart';
import 'parameters_screen.dart';

class ModeSelectionScreen extends StatelessWidget {
  const ModeSelectionScreen({super.key});

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
    VoltammetryMode.cv: Icons.loop,
    VoltammetryMode.ca: Icons.timer_outlined,
    VoltammetryMode.swv: Icons.square_foot,
    VoltammetryMode.dpv: Icons.bar_chart,
    VoltammetryMode.npv: Icons.stacked_line_chart,
  };

  @override
  Widget build(BuildContext context) {
    final measurement = context.watch<MeasurementProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Select Voltammetry Mode')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: VoltammetryMode.values.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final mode = VoltammetryMode.values[i];
          final isSelected = measurement.selectedMode == mode;
          return _ModeCard(
            mode: mode,
            description: _descriptions[mode]!,
            icon: _icons[mode]!,
            isSelected: isSelected,
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
  final String description;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

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
              ? [
                  BoxShadow(
                    color: AppColors.accent1.withOpacity(0.2),
                    blurRadius: 8,
                    spreadRadius: 1,
                  )
                ]
              : [],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
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
                  Row(
                    children: [
                      Text(
                        mode.abbreviation,
                        style: TextStyle(
                          color: isSelected
                              ? AppColors.accent1
                              : Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          mode.fullName,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
