import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PresetService {
  static String _key(String technique) => 'presets_$technique';

  static Future<List<Preset>> loadPresets(String technique) async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_key(technique));
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => Preset.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> savePreset(
      String technique, String name, Map<String, double> params) async {
    final presets = await loadPresets(technique);
    presets.removeWhere((p) => p.name == name);
    presets.add(Preset(name: name, params: Map.from(params)));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(technique), jsonEncode(presets.map((p) => p.toJson()).toList()));
  }

  static Future<void> deletePreset(String technique, String name) async {
    final presets = await loadPresets(technique);
    presets.removeWhere((p) => p.name == name);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(technique), jsonEncode(presets.map((p) => p.toJson()).toList()));
  }
}

class Preset {
  final String name;
  final Map<String, double> params;

  const Preset({required this.name, required this.params});

  factory Preset.fromJson(Map<String, dynamic> json) => Preset(
        name: json['name'] as String,
        params: (json['params'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as num).toDouble())),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'params': params,
      };
}
