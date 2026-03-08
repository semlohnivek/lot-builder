import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _service = SettingsService();
  AppSettings? _settings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await _service.load();
    setState(() => _settings = s);
  }

  Future<void> _save(AppSettings updated) async {
    await _service.save(updated);
    setState(() => _settings = updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.grey[100],
      body: _settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _sectionHeader('IMAGE QUALITY'),
                ...AppSettings.presetLabels.entries.map((e) => ListTile(
                      tileColor: Colors.white,
                      title: Text(e.value),
                      trailing: _settings!.resolutionPreset == e.key
                          ? const Icon(Icons.check, color: Colors.orange)
                          : null,
                      onTap: () => _save(
                          _settings!.copyWith(resolutionPreset: e.key)),
                    )),
                _hint('Higher quality = larger files and slower saves. '
                    '"Max" uses the full camera sensor resolution.'),

                _sectionHeader('PREVIEW THUMBNAIL SIZE'),
                ...AppSettings.thumbnailLabels.entries.map((e) => ListTile(
                      tileColor: Colors.white,
                      title: Text(e.value),
                      trailing: _settings!.thumbnailSize == e.key
                          ? const Icon(Icons.check, color: Colors.orange)
                          : null,
                      onTap: () =>
                          _save(_settings!.copyWith(thumbnailSize: e.key)),
                    )),

                _sectionHeader('THUMBNAIL ACTIONS'),
                SwitchListTile(
                  tileColor: Colors.white,
                  title: const Text('Show quick-delete button'),
                  subtitle: const Text(
                      'Shows × on each thumbnail for one-tap delete'),
                  value: _settings!.quickDelete,
                  activeThumbColor: Colors.orange,
                  onChanged: (v) =>
                      _save(_settings!.copyWith(quickDelete: v)),
                ),
                _hint('When off, use long-press on a thumbnail to delete.'),
              ],
            ),
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
            letterSpacing: 1,
          ),
        ),
      );

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(text,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      );
}
