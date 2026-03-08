import 'dart:io';
import 'package:flutter/material.dart';

class ImageViewerScreen extends StatefulWidget {
  final List<String> imagePaths;
  final int initialIndex;

  const ImageViewerScreen({
    super.key,
    required this.imagePaths,
    required this.initialIndex,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_currentIndex + 1} / ${widget.imagePaths.length}',
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.imagePaths.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (context, i) {
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: Center(
              child: Image.file(
                File(widget.imagePaths[i]),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) => const Center(
                  child: Icon(Icons.broken_image,
                      color: Colors.white54, size: 64),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
