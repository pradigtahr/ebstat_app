import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/voltammetry_mode.dart';
import '../providers/measurement_provider.dart';
import '../theme/app_theme.dart';
import 'measurement_screen.dart';

class ParametersScreen extends StatefulWidget {
  const ParametersScreen({super.key, required this.mode});
  final VoltammetryMode mode;

  @override
  State<ParametersScreen> createState() => _ParametersScreenState();
}

class _ParametersScreenState extends State<ParametersScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    final params = modeParameters[widget.mode]!;
    final provider = context.read<MeasurementProvider>();
    for (final p in params) {
      _controllers[p.key] = TextEditingController(
        text: (provider.parameters[p.key] ?? p.defaultValue).toString(),
      );
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final params = modeParameters[widget.mode]!;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.mode.abbreviation} Parameters'),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: params.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (_, i) {
                  final p = params[i];
                  return _ParameterField(
                    parameter: p,
                    controller: _controllers[p.key]!,
                  );
                },
              ),
            ),
            _StartButton(
              onPressed: _onStart,
            ),
          ],
        ),
      ),
    );
  }

  void _onStart() {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<MeasurementProvider>();
    for (final entry in _controllers.entries) {
      final value = double.tryParse(entry.value.text);
      if (value != null) provider.updateParameter(entry.key, value);
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MeasurementScreen()),
    );
  }
}

class _ParameterField extends StatelessWidget {
  const _ParameterField({
    required this.parameter,
    required this.controller,
  });

  final VoltammetryParameter parameter;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(
          decimal: true, signed: true),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: parameter.label,
        hintText: parameter.hint,
        suffixText: parameter.unit,
        suffixStyle: const TextStyle(color: AppColors.accent2),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Required';
        if (double.tryParse(v.trim()) == null) return 'Enter a valid number';
        return null;
      },
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
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
}
