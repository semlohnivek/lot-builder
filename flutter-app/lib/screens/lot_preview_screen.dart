import 'dart:io';
import 'package:flutter/material.dart';
import '../services/session_service.dart';
import '../services/settings_service.dart';
import 'capture_screen.dart';
import 'image_viewer_screen.dart';

class LotPreviewScreen extends StatefulWidget {
  final SessionData session;

  const LotPreviewScreen({super.key, required this.session});

  @override
  State<LotPreviewScreen> createState() => _LotPreviewScreenState();
}

class _LotPreviewScreenState extends State<LotPreviewScreen> {
  final _service = SessionService();
  final _settingsService = SettingsService();
  late SessionData _session;
  double _thumbSize = 95;
  bool _quickDelete = true;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _cleanEmptyLastLot();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = await _settingsService.load();
    if (mounted) {
      setState(() {
        _thumbSize = s.thumbnailPixels;
        _quickDelete = s.quickDelete;
      });
    }
  }

  Future<void> _cleanEmptyLastLot() async {
    final cleaned = await _service.cleanEmptyLastLot(_session);
    if (mounted) setState(() => _session = cleaned);
  }

  Future<void> _deleteImage(int lotIndex, int imageIndex) async {
    final updated = await _service.deleteImage(_session, lotIndex, imageIndex);
    setState(() => _session = updated);
  }

  Future<void> _splitLot(int lotIndex, int splitAtIndex) async {
    final updated = await _service.splitLot(_session, lotIndex, splitAtIndex);
    setState(() => _session = updated);
  }

  Future<void> _updateNotes(int lotIndex, String notes) async {
    final updated = await _service.updateNotes(_session, lotIndex, notes);
    setState(() => _session = updated);
  }

  void _confirmRemoveLot(int lotIndex) {
    final lotNum = lotIndex + 1;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Lot?'),
        content: Text('Remove Lot $lotNum? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _doRemoveLot(lotIndex);
              },
              child: const Text('Remove',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  Future<void> _doRemoveLot(int lotIndex) async {
    final updated = await _service.removeLot(_session, lotIndex);
    if (mounted) setState(() => _session = updated);
  }

  Future<void> _insertAndShoot(int lotIndex) async {
    final result = await Navigator.push<SessionData>(
      context,
      MaterialPageRoute(
        builder: (_) => CaptureScreen(
          session: _session,
          insertAfterIndex: lotIndex - 1,
        ),
      ),
    );
    if (result != null && mounted) {
      final cleaned = await _service.cleanEmptyLastLot(result);
      if (mounted) setState(() => _session = cleaned);
    }
  }

  Future<void> _addImages(int lotIndex) async {
    final result = await Navigator.push<SessionData>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CaptureScreen(session: _session, lockedLotIndex: lotIndex),
      ),
    );
    if (result != null && mounted) setState(() => _session = result);
  }

  Future<void> _addNewLot() async {
    final nav = Navigator.of(context);
    var session = await _service.cleanEmptyLastLot(_session);
    session = await _service.addLot(session);
    if (!mounted) return;
    setState(() => _session = session);

    final result = await nav.push<SessionData>(
      MaterialPageRoute(builder: (_) => CaptureScreen(session: _session)),
    );
    if (result != null && mounted) {
      final cleaned = await _service.cleanEmptyLastLot(result);
      if (mounted) setState(() => _session = cleaned);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lots = _session.lots;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(
            _session.name.isNotEmpty ? _session.name : 'Session Preview'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        behavior: HitTestBehavior.translucent,
        child: lots.isEmpty
            ? const Center(
                child: Text(
                  'No lots yet.\nTap + to start capturing.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.only(top: 8, bottom: 100),
                itemCount: lots.length,
                separatorBuilder: (_, i) => const Divider(
                  thickness: 2,
                  height: 2,
                  color: Color(0xFFDDDDDD),
                ),
                itemBuilder: (_, lotIndex) {
                  return _LotItem(
                    key: ValueKey('${_session.folderPath}_$lotIndex'),
                    session: _session,
                    lotIndex: lotIndex,
                    thumbSize: _thumbSize,
                    quickDelete: _quickDelete,
                    onDeleteImage: (i) => _deleteImage(lotIndex, i),
                    onSplit: (i) => _splitLot(lotIndex, i),
                    onNotesChanged: (n) => _updateNotes(lotIndex, n),
                    onAddImages: () => _addImages(lotIndex),
                    onInsertAndShoot: () => _insertAndShoot(lotIndex),
                    onRemoveLot: () => _confirmRemoveLot(lotIndex),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addNewLot,
        backgroundColor: Colors.orange,
        icon: const Icon(Icons.camera_alt, color: Colors.white),
        label:
            const Text('Add Lots', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

// ─── Lot Item ────────────────────────────────────────────────────────────────

class _LotItem extends StatefulWidget {
  final SessionData session;
  final int lotIndex;
  final double thumbSize;
  final bool quickDelete;
  final Function(int imageIndex) onDeleteImage;
  final Function(int splitAtIndex) onSplit;
  final Function(String notes) onNotesChanged;
  final VoidCallback onAddImages;
  final VoidCallback onInsertAndShoot;
  final VoidCallback onRemoveLot;

  const _LotItem({
    super.key,
    required this.session,
    required this.lotIndex,
    required this.thumbSize,
    required this.quickDelete,
    required this.onDeleteImage,
    required this.onSplit,
    required this.onNotesChanged,
    required this.onAddImages,
    required this.onInsertAndShoot,
    required this.onRemoveLot,
  });

  @override
  State<_LotItem> createState() => _LotItemState();
}

class _LotItemState extends State<_LotItem> {
  late TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _notesCtrl =
        TextEditingController(text: _lot['notes'] as String? ?? '');
  }

  @override
  void didUpdateWidget(_LotItem old) {
    super.didUpdateWidget(old);
    final newNotes = _lot['notes'] as String? ?? '';
    if (_notesCtrl.text != newNotes) {
      _notesCtrl.text = newNotes;
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _lot =>
      widget.session.lots[widget.lotIndex] as Map<String, dynamic>;

  void _openViewer(List<String> images, int initialIndex) {
    final paths = images
        .map((filename) => '${widget.session.folderPath}/$filename')
        .toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(
          imagePaths: paths,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lot = _lot;
    final images = (lot['images'] as List).cast<String>();
    final lotNum = widget.lotIndex + 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text(
                'Lot $lotNum',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Text(
                '${images.length} photo${images.length == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Thumbnails
          if (images.isEmpty)
            Text('No photos',
                style: TextStyle(color: Colors.grey[400], fontSize: 13))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _buildThumbnailsWithSplitters(images),
            ),

          const SizedBox(height: 10),

          // Notes field
          TextField(
            controller: _notesCtrl,
            onChanged: widget.onNotesChanged,
            decoration: InputDecoration(
              hintText: 'Notes...',
              hintStyle: TextStyle(color: Colors.grey[400]),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            maxLines: 2,
            minLines: 1,
            style: const TextStyle(fontSize: 13),
          ),

          const SizedBox(height: 10),

          // Per-lot actions
          Row(
            children: [
              _LotAction(
                icon: Icons.add_photo_alternate_outlined,
                label: 'Add Images',
                onTap: widget.onAddImages,
              ),
              const SizedBox(width: 12),
              _LotAction(
                icon: Icons.camera_alt_outlined,
                label: 'Insert & Shoot',
                onTap: widget.onInsertAndShoot,
              ),
              const SizedBox(width: 12),
              _LotAction(
                icon: Icons.delete_outline,
                label: 'Remove Lot',
                color: Colors.red[700]!,
                onTap: widget.onRemoveLot,
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildThumbnailsWithSplitters(List<String> images) {
    return List.generate(
      images.length,
      (i) => _ThumbnailTile(
        file: File('${widget.session.folderPath}/${images[i]}'),
        size: widget.thumbSize,
        showQuickDelete: widget.quickDelete,
        onTap: () => _openViewer(images, i),
        onDelete: () => widget.onDeleteImage(i),
        onSplitBefore: i > 0 ? () => widget.onSplit(i) : null,
      ),
    );
  }
}

// ─── Thumbnail tile ───────────────────────────────────────────────────────────

class _ThumbnailTile extends StatelessWidget {
  final File file;
  final double size;
  final bool showQuickDelete;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onSplitBefore;

  const _ThumbnailTile({
    required this.file,
    required this.size,
    required this.showQuickDelete,
    required this.onTap,
    required this.onDelete,
    this.onSplitBefore,
  });

  void _showOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onSplitBefore != null)
              ListTile(
                leading: const Icon(Icons.content_cut),
                title: const Text('Split at this image'),
                subtitle: const Text(
                    'Everything from here onwards becomes a new lot'),
                onTap: () {
                  Navigator.pop(ctx);
                  onSplitBefore!();
                },
              ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete image',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showOptions(context),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              file,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => Container(
                width: size,
                height: size,
                color: Colors.grey[300],
                child: const Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
          ),
          if (showQuickDelete)
            Positioned(
              top: 3,
              right: 3,
              child: GestureDetector(
                onTap: onDelete,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(3),
                  child: const Icon(Icons.close,
                      color: Colors.white, size: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Lot action button ────────────────────────────────────────────────────────

class _LotAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _LotAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.black54,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}
