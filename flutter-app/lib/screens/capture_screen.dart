import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/auction_service.dart';
import '../services/camera_service.dart';
import '../services/settings_service.dart';

class CaptureScreen extends StatefulWidget {
  final AuctionData auction;

  /// When set, captures are added to this specific lot. Next Lot is hidden.
  final int? lockedLotIndex;

  /// When set, new lots are inserted after this index rather than appended.
  final int? insertAfterIndex;

  const CaptureScreen({
    super.key,
    required this.auction,
    this.lockedLotIndex,
    this.insertAfterIndex,
  });

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  final _camera = CameraService();
  final _service = AuctionService();
  final _settings = SettingsService();
  late AuctionData _auction;

  bool _capturing = false;
  bool _cameraReady = false;
  bool _initializing = false;
  String? _error;

  // Insert mode: tracks which lot index is currently active
  int? _insertPosition;

  // Zoom
  double _currentZoom = 1.0;
  double _baseZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;

  // Flash
  FlashMode _flashMode = FlashMode.off;

  // Strip scroll
  final _stripScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    _auction = widget.auction;

    if (widget.insertAfterIndex != null) {
      _setupInsertMode();
    } else if (widget.lockedLotIndex == null && _auction.lots.isEmpty) {
      _addFirstLot();
    }

    _initCamera();
  }

  Future<void> _setupInsertMode() async {
    final updated =
        await _service.insertLot(_auction, widget.insertAfterIndex!);
    _insertPosition = widget.insertAfterIndex! + 1;
    if (mounted) setState(() => _auction = updated);
  }

  Future<void> _addFirstLot() async {
    final updated = await _service.addLot(_auction);
    if (mounted) setState(() => _auction = updated);
  }

  Future<void> _initCamera() async {
    if (_initializing) return;
    _initializing = true;

    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        setState(() =>
            _error = 'Camera permission denied.\nGo to Settings to enable it.');
      }
      _initializing = false;
      return;
    }

    try {
      final appSettings = await _settings.load();
      await _camera.initialize(preset: appSettings.cameraResolution);
      if (mounted) {
        _minZoom = await _camera.controller!.getMinZoomLevel();
        _maxZoom = await _camera.controller!.getMaxZoomLevel();
        await _camera.controller!.setFlashMode(_flashMode);
        setState(() => _cameraReady = true);
      }
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = 'Camera error: ${e.description}');
    }
    _initializing = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive && _cameraReady) {
      _camera.dispose();
      setState(() => _cameraReady = false);
    } else if (state == AppLifecycleState.resumed && !_cameraReady) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    WidgetsBinding.instance.removeObserver(this);
    _camera.dispose();
    _stripScroll.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    if (_capturing || !_cameraReady) return;
    setState(() => _capturing = true);
    try {
      final filename = _service.nextImageFilename(_auction);
      final path = await _camera.takePicture(_auction.folderPath, filename);
      if (path != null) {
        final updated =
            await _service.addImage(_auction, _activeLotIndex, filename);
        setState(() => _auction = updated);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_stripScroll.hasClients) {
            _stripScroll.animateTo(
              _stripScroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } finally {
      setState(() => _capturing = false);
    }
  }

  Future<void> _nextLot() async {
    if (_photoCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Take at least one photo first.')),
      );
      return;
    }

    if (_insertPosition != null) {
      // Insert mode: insert next lot immediately after current position
      final updated =
          await _service.insertLot(_auction, _insertPosition!);
      _insertPosition = _insertPosition! + 1;
      setState(() => _auction = updated);
    } else {
      // Normal mode: append to end
      final updated = await _service.addLot(_auction);
      setState(() => _auction = updated);
    }
  }

  Future<void> _toggleFlash() async {
    if (!_cameraReady) return;
    final next =
        _flashMode == FlashMode.off ? FlashMode.always : FlashMode.off;
    await _camera.controller!.setFlashMode(next);
    setState(() => _flashMode = next);
  }

  Future<void> _setZoom(double zoom) async {
    if (!_cameraReady) return;
    final clamped = zoom.clamp(_minZoom, _maxZoom);
    await _camera.controller!.setZoomLevel(clamped);
    setState(() => _currentZoom = clamped);
  }

  void _onScaleStart(ScaleStartDetails details) {
    _baseZoom = _currentZoom;
  }

  Future<void> _onScaleUpdate(ScaleUpdateDetails details) async {
    if (!_cameraReady) return;
    final zoom =
        (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);
    await _camera.controller!.setZoomLevel(zoom);
    setState(() => _currentZoom = zoom);
  }

  int get _activeLotIndex {
    if (_insertPosition != null) return _insertPosition!;
    if (widget.lockedLotIndex != null) return widget.lockedLotIndex!;
    return _auction.currentLotIndex;
  }

  Map<String, dynamic>? get _activeLot =>
      _activeLotIndex >= 0 && _activeLotIndex < _auction.lots.length
          ? _auction.lots[_activeLotIndex] as Map<String, dynamic>
          : null;

  int get _lotNumber {
    final lot = _activeLot;
    if (lot != null) return lot['sequence'] as int;
    return _activeLotIndex + 1;
  }

  int get _photoCount =>
      _activeLot == null ? 0 : (_activeLot!['images'] as List).length;

  bool get _inInsertMode => _insertPosition != null;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _auction);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => Navigator.pop(context, _auction),
          ),
          title: Text(_inInsertMode
              ? 'Lot $_lotNumber  ·  inserting'
              : 'Lot $_lotNumber'),
          actions: [
            if (_cameraReady)
              IconButton(
                icon: Icon(
                  _flashMode == FlashMode.off
                      ? Icons.flash_off
                      : Icons.flash_on,
                  color: _flashMode == FlashMode.off
                      ? Colors.white54
                      : Colors.yellow,
                ),
                onPressed: _toggleFlash,
              ),
            if (widget.lockedLotIndex == null)
              TextButton.icon(
                onPressed: _nextLot,
                icon: const Icon(Icons.skip_next, color: Colors.white),
                label: const Text(
                  'Next Lot',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            const SizedBox(width: 4),
          ],
        ),
        body: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 16),
                  ),
                ),
              )
            : !_cameraReady
                ? const Center(
                    child:
                        CircularProgressIndicator(color: Colors.white))
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      GestureDetector(
                        onScaleStart: _onScaleStart,
                        onScaleUpdate: _onScaleUpdate,
                        child: CameraPreview(_camera.controller!),
                      ),
                      // Thumbnail strip — always at top
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: _buildPhotoStrip(),
                      ),
                      // Photo count
                      Positioned(
                        top: _photoCount > 0 ? 108 : 12,
                        left: 0,
                        right: 0,
                        child: Text(
                          _photoCount == 0
                              ? 'No photos yet'
                              : '$_photoCount photo${_photoCount == 1 ? '' : 's'}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            shadows: [
                              Shadow(
                                  color: Colors.black, blurRadius: 6)
                            ],
                          ),
                        ),
                      ),
                      // Zoom presets — always above shutter
                      const Positioned(
                        bottom: 140,
                        left: 0,
                        right: 0,
                        child: SizedBox(), // placeholder — built below
                      ),
                      Positioned(
                        bottom: 140,
                        left: 0,
                        right: 0,
                        child: _buildZoomPresets(),
                      ),
                      // Shutter — always at bottom
                      Positioned(
                        bottom: 48,
                        left: 0,
                        right: 0,
                        child: Center(child: _buildShutterButton()),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildZoomPresets() {
    final presets = [1.0, 2.0, 5.0]
        .where((z) => z >= _minZoom && z <= _maxZoom)
        .toList();
    if (presets.length <= 1) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: presets.map((z) {
        final label =
            z == z.truncateToDouble() ? '${z.toInt()}×' : '$z×';
        final active = (_currentZoom - z).abs() < 0.3;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: GestureDetector(
            onTap: () => _setZoom(z),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: active
                    ? Colors.white
                    : Colors.black.withAlpha(140),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? Colors.white : Colors.white54,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: active ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildShutterButton() {
    return GestureDetector(
      onTap: _capturing ? null : _takePhoto,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
          color:
              _capturing ? Colors.white54 : Colors.white.withAlpha(30),
        ),
        child: _capturing
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : null,
      ),
    );
  }

  Widget _buildPhotoStrip() {
    if (_activeLot == null || _photoCount == 0) return const SizedBox.shrink();
    final images = (_activeLot!['images'] as List).cast<Map>();
    return Container(
      color: Colors.black54,
      height: 100,
      child: ListView.separated(
        controller: _stripScroll,
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: images.length,
        separatorBuilder: (_, i) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final filename = images[i]['filename'] as String;
          return ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              File('${_auction.folderPath}/$filename'),
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => Container(
                width: 80,
                height: 80,
                color: Colors.grey[800],
                child: const Icon(Icons.broken_image,
                    color: Colors.white38),
              ),
            ),
          );
        },
      ),
    );
  }
}
