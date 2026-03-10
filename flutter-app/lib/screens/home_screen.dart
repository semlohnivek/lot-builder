import 'package:flutter/material.dart';
import '../services/session_service.dart';
import '../services/settings_service.dart';
import 'auction_screen.dart';
import 'device_setup_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = SessionService();
  final _settingsService = SettingsService();
  List<AuctionFolder> _auctions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _service.requestStoragePermission();
    final settings = await _settingsService.load();
    if (settings.deviceId.isEmpty && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DeviceSetupScreen()),
      );
    }
    _load();
  }

  Future<void> _load() async {
    final auctions = await _service.listAuctions();
    setState(() {
      _auctions = auctions;
      _loading = false;
    });
  }

  Future<void> _newAuction() async {
    final name = await _promptName();
    if (name == null || !mounted) return;
    final folder = await _service.createAuction(name: name);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AuctionScreen(folder: folder)),
    );
    _load();
  }

  Future<String?> _promptName() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Auction'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Auction name'),
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

  void _confirmDeleteAuction(AuctionFolder folder) {
    final name =
        folder.displayName.isNotEmpty ? folder.displayName : folder.name;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Auction?'),
        content: Text(
            'Delete "$name" and all its sessions and photos? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteAuction(folder);
            },
            child:
                const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAuction(AuctionFolder folder) async {
    await _service.deleteAuction(folder.path);
    _load();
  }

  Future<void> _openAuction(AuctionFolder folder) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AuctionScreen(folder: folder)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const Icon(Icons.home, color: Colors.white54),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Lot Builder',
                style: TextStyle(fontSize: 13, color: Colors.white54)),
            Text('Auctions',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.grey[100],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _auctions.isEmpty
              ? const Center(
                  child: Text(
                    'No auctions yet.\nTap + to start one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _auctions.length,
                    separatorBuilder: (_, i) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final folder = _auctions[i];
                      return ListTile(
                        tileColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        leading:
                            const Icon(Icons.folder, color: Colors.orange),
                        title: Text(
                          folder.displayName.isNotEmpty
                              ? folder.displayName
                              : folder.name,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openAuction(folder),
                        onLongPress: () => _confirmDeleteAuction(folder),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newAuction,
        backgroundColor: Colors.orange,
        icon: const Icon(Icons.add, color: Colors.white),
        label:
            const Text('New Auction', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}
