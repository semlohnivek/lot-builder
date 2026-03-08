import 'dart:io';
import 'package:camera/camera.dart';

class CameraService {
  CameraController? controller;

  Future<void> initialize({
    ResolutionPreset preset = ResolutionPreset.high,
  }) async {
    final cameras = await availableCameras();
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    controller = CameraController(
      back,
      preset,
      enableAudio: false,
    );
    await controller!.initialize();
  }

  Future<String?> takePicture(String folderPath, String filename) async {
    if (controller == null || !controller!.value.isInitialized) return null;
    final xfile = await controller!.takePicture();
    final dest = File('$folderPath/$filename');
    await File(xfile.path).copy(dest.path);
    return dest.path;
  }

  void dispose() {
    controller?.dispose();
    controller = null;
  }
}
