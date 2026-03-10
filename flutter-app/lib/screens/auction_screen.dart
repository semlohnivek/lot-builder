import 'package:flutter/material.dart';
import '../services/session_service.dart';
import '../services/settings_service.dart';
import 'capture_screen.dart';
import 'lot_preview_screen.dart';

class AuctionScreen extends StatefulWidget {
  final AuctionFolder folder;

  const AuctionScreen({super.key, required this.folder});

  @override
  State<AuctionScreen> createState() => _AuctionScreenState();
}

class _AuctionScreenState extends State<AuctionScreen> {
  final _service = SessionService();
  final _settingsService = SettingsService();
  List<SessionFolder> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await _service.listSessions(widget.folder.path);
    setState(() {
      _sessions = sessions;
      _loading = false;
    });
  }

  Future<void> _newSession() async {
    final settings = await _settingsService.load();
    if (!mounted) return;

    final name = await _promptSessionName();
    if (name == null || !mounted) return;

    final session = await _service.createSession(
      widget.folder.path,
      name: name,
      deviceId: settings.deviceId,
      sessionNumber: _sessions.length + 1,
    );
    if (!mounted) return;

    final result = await Navigator.push<SessionData>(
      context,
      MaterialPageRoute(builder: (_) => CaptureScreen(session: session)),
    );

    if (result != null && result.lots.isNotEmpty && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => LotPreviewScreen(session: result)),
      );
    }
    _load();
  }

  Future<String?> _promptSessionName() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Session'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'Session ${_sessions.length + 1}',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSession(SessionFolder folder) async {
    final session = await _service.loadSession(folder.path);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LotPreviewScreen(session: session)),
    );
    _load();
  }

  void _confirmDeleteSession(SessionFolder folder) {
    final name =
        folder.displayName.isNotEmpty ? folder.displayName : folder.name;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Session?'),
        content: Text(
            'Delete "$name" and all its photos? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteSession(folder);
            },
            child:
                const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSession(SessionFolder folder) async {
    await _service.deleteSession(folder.path);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.folder.displayName.isNotEmpty
        ? widget.folder.displayName
        : widget.folder.name;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Lot Builder',
                style: TextStyle(fontSize: 13, color: Colors.white54)),
            Text('$title  ›  Sessions',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.grey[100],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? const Center(
                  child: Text(
                    'No sessions yet.\nTap + to start one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _sessions.length,
                    separatorBuilder: (_, i) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final session = _sessions[i];
                      final label = session.displayName.isNotEmpty
                          ? session.displayName
                          : session.name;
                      return ListTile(
                        tileColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        leading: Icon(Icons.camera_alt,
                            color: Colors.deepOrange[700]),
                        title: Text(label),
                        subtitle: Text(
                          '${session.photoCount} photo${session.photoCount == 1 ? '' : 's'}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openSession(session),
                        onLongPress: () => _confirmDeleteSession(session),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newSession,
        backgroundColor: Colors.deepOrange[700],
        icon: const Icon(Icons.camera_alt, color: Colors.white),
        label: const Text('New Session',
            style: TextStyle(color: Colors.white)),
      ),
    );
  }
}
