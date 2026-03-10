import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../services/session_service.dart';
import '../services/camera_service.dart';
import '../services/settings_service.dart';

class CaptureScreen extends StatefulWidget {
  final SessionData session;

  /// When set, captures are added to this specific lot. Next Lot is hidden.
  final int? lockedLotIndex;

  /// When set, new lots are inserted after this index rather than appended.
  final int? insertAfterIndex;

  const CaptureScreen({
    super.key,
    required this.session,
    this.lockedLotIndex,
    this.insertAfterIndex,
  });

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _camera = CameraService();
  final _service = SessionService();
  final _settings = SettingsService();
  late SessionData _session;
  String _deviceId = 'device01';

  bool _capturing = false;
  bool _cameraReady = false;
  bool _initializing = false;
  bool _useNativeCamera = false;
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

  // Orientation
  StreamSubscription<AccelerometerEvent>? _accelSub;
  DeviceOrientation _captureOrientation = DeviceOrientation.portraitUp;

  // Lot number animation
  late AnimationController _lotNumController;
  late Animation<double> _lotNumScale;
  late Animation<Color?> _lotNumColor;

  @override
  void initState() {
    super.initState();
    _lotNumController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _lotNumScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.8), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.8, end: 1.0), weight: 70),
    ]).animate(CurvedAnimation(
        parent: _lotNumController, curve: Curves.easeInOut));
    _lotNumColor = TweenSequence<Color?>([
      TweenSequenceItem<Color?>(
          tween: ColorTween(begin: Colors.white, end: Colors.orange),
          weight: 30),
      TweenSequenceItem<Color?>(
          tween: ColorTween(begin: Colors.orange, end: Colors.white),
          weight: 70),
    ]).animate(_lotNumController);
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    _session = widget.session;

    if (widget.insertAfterIndex != null) {
      _setupInsertMode();
    } else if (widget.lockedLotIndex == null && _session.lots.isEmpty) {
      _addFirstLot();
    }

    _initCamera();
  }

  Future<void> _setupInsertMode() async {
    final updated =
        await _service.insertLot(_session, widget.insertAfterIndex!);
    _insertPosition = widget.insertAfterIndex! + 1;
    if (mounted) setState(() => _session = updated);
  }

  Future<void> _addFirstLot() async {
    final updated = await _service.addLot(_session);
    if (mounted) setState(() => _session = updated);
  }

  Future<void> _initCamera() async {
    if (_initializing) return;
    _initializing = true;

    final appSettings = await _settings.load();
    if (mounted) setState(() => _deviceId = appSettings.deviceId);

    if (appSettings.useNativeCamera) {
      if (mounted) {
        setState(() {
          _useNativeCamera = true;
          _cameraReady = true;
        });
      }
      _initializing = false;
      return;
    }

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
      await _camera.initialize(preset: appSettings.cameraResolution);
      if (mounted) {
        _minZoom = await _camera.controller!.getMinZoomLevel();
        _maxZoom = await _camera.controller!.getMaxZoomLevel();
        await _camera.controller!.setFlashMode(_flashMode);
        setState(() => _cameraReady = true);
        _startOrientationListener();
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollStripToEnd());
      }
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = 'Camera error: ${e.description}');
    }
    _initializing = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_useNativeCamera) return;
    if (state == AppLifecycleState.inactive && _cameraReady) {
      _camera.dispose();
      setState(() => _cameraReady = false);
    } else if (state == AppLifecycleState.resumed && !_cameraReady) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    _lotNumController.dispose();
    _accelSub?.cancel();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    WidgetsBinding.instance.removeObserver(this);
    _camera.dispose();
    _stripScroll.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    if (_capturing || !_cameraReady) return;
    if (_useNativeCamera) {
      await _takePhotoNative();
      return;
    }
    setState(() => _capturing = true);
    try {
      await _camera.controller!.lockCaptureOrientation(_captureOrientation);
      final filename = _service.nextImageFilename(_deviceId);
      final path = await _camera.takePicture(_session.folderPath, filename);
      await _camera.controller!.unlockCaptureOrientation();
      if (path != null) {
        final updated =
            await _service.addImage(_session, _activeLotIndex, filename);
        setState(() => _session = updated);
        _scrollStripToEnd();
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _takePhotoNative() async {
    setState(() => _capturing = true);
    try {
      while (mounted) {
        final xfile = await ImagePicker().pickImage(source: ImageSource.camera);
        if (xfile == null || !mounted) break;
        final filename = _service.nextImageFilename(_deviceId);
        await File(xfile.path).copy('${_session.folderPath}/$filename');
        final updated =
            await _service.addImage(_session, _activeLotIndex, filename);
        if (mounted) setState(() => _session = updated);
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _scrollStripToEnd() {
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
          await _service.insertLot(_session, _insertPosition!);
      _insertPosition = _insertPosition! + 1;
      setState(() => _session = updated);
    } else {
      // Normal mode: append to end
      final updated = await _service.addLot(_session);
      setState(() => _session = updated);
    }
    _lotNumController.forward(from: 0);
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
    return _session.currentLotIndex;
  }

  Map<String, dynamic>? get _activeLot =>
      _activeLotIndex >= 0 && _activeLotIndex < _session.lots.length
          ? _session.lots[_activeLotIndex] as Map<String, dynamic>
          : null;

  int get _lotNumber => _activeLotIndex + 1;

  int get _photoCount =>
      _activeLot == null ? 0 : (_activeLot!['images'] as List).length;

  bool get _inInsertMode => _insertPosition != null;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _session);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => Navigator.pop(context, _session),
          ),
          title: AnimatedBuilder(
            animation: _lotNumController,
            builder: (context, _) => Transform.scale(
              scale: _lotNumScale.value,
              child: Text(
                _inInsertMode
                    ? 'Lot $_lotNumber  ·  inserting'
                    : 'Lot $_lotNumber',
                style: TextStyle(color: _lotNumColor.value),
              ),
            ),
          ),
          actions: [
            if (_cameraReady && !_useNativeCamera)
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
                : _useNativeCamera
                ? _buildNativeCameraBody()
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: AspectRatio(
                          aspectRatio: 1.0 / _camera.controller!.value.aspectRatio,
                          child: GestureDetector(
                            onScaleStart: _onScaleStart,
                            onScaleUpdate: _onScaleUpdate,
                            child: CameraPreview(_camera.controller!),
                          ),
                        ),
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
                        top: _photoCount > 0 ? 100 : 12,
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

  void _startOrientationListener() {
    _accelSub = accelerometerEventStream().listen((event) {
      const threshold = 5.0;
      if (event.x.abs() > threshold && event.x.abs() > event.y.abs()) {
        _captureOrientation = event.x > 0
            ? DeviceOrientation.landscapeLeft
            : DeviceOrientation.landscapeRight;
      } else if (event.y.abs() > threshold && event.y.abs() > event.x.abs()) {
        _captureOrientation = DeviceOrientation.portraitUp;
      }
      // ambiguous angle — keep last known orientation
    });
  }

  Widget _buildNativeCameraBody() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: 0, left: 0, right: 0,
          child: _buildPhotoStrip(),
        ),
        Positioned(
          top: _photoCount > 0 ? 108 : 12,
          left: 0,
          right: 0,
          child: Text(
            _photoCount == 0
                ? 'Tap to photograph'
                : '$_photoCount photo${_photoCount == 1 ? '' : 's'}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              shadows: [Shadow(color: Colors.black, blurRadius: 6)],
            ),
          ),
        ),
        Positioned(
          bottom: 48, left: 0, right: 0,
          child: Center(child: _buildShutterButton()),
        ),
      ],
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
    final images = (_activeLot!['images'] as List).cast<String>();
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
          return ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              File('${_session.folderPath}/${images[i]}'),
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
