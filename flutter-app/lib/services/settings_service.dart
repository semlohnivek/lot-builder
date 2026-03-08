import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';

class SettingsService {
  static const _filename = 'settings.json';

  Future<File> get _file async {
    final ext = await getExternalStorageDirectory();
    final root = ext!.parent.parent.parent.parent;
    final dir = Directory('${root.path}/Documents/lot-builder');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$_filename');
  }

  Future<AppSettings> load() async {
    try {
      final file = await _file;
      if (!await file.exists()) return AppSettings();
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return AppSettings.fromJson(data);
    } catch (_) {
      return AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    final file = await _file;
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
      flush: true,
    );
  }
}

class AppSettings {
  final String resolutionPreset;
  final String thumbnailSize;
  final bool quickDelete;

  AppSettings({
    this.resolutionPreset = 'high',
    this.thumbnailSize = 'medium',
    this.quickDelete = true,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        resolutionPreset: json['resolution_preset'] as String? ?? 'high',
        thumbnailSize: json['thumbnail_size'] as String? ?? 'medium',
        quickDelete: json['quick_delete'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'resolution_preset': resolutionPreset,
        'thumbnail_size': thumbnailSize,
        'quick_delete': quickDelete,
      };

  AppSettings copyWith({
    String? resolutionPreset,
    String? thumbnailSize,
    bool? quickDelete,
  }) =>
      AppSettings(
        resolutionPreset: resolutionPreset ?? this.resolutionPreset,
        thumbnailSize: thumbnailSize ?? this.thumbnailSize,
        quickDelete: quickDelete ?? this.quickDelete,
      );

  ResolutionPreset get cameraResolution {
    switch (resolutionPreset) {
      case 'veryHigh':
        return ResolutionPreset.veryHigh;
      case 'ultraHigh':
        return ResolutionPreset.ultraHigh;
      case 'max':
        return ResolutionPreset.max;
      default:
        return ResolutionPreset.high;
    }
  }

  double get thumbnailPixels {
    switch (thumbnailSize) {
      case 'small':
        return 70;
      case 'large':
        return 130;
      default:
        return 95;
    }
  }

  static const presetLabels = {
    'high': 'High (1080p)',
    'veryHigh': 'Very High (2160p)',
    'ultraHigh': 'Ultra High (4K)',
    'max': 'Max (full sensor)',
  };

  static const thumbnailLabels = {
    'small': 'Small',
    'medium': 'Medium',
    'large': 'Large',
  };
}
