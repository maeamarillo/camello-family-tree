import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import '../models/family_node.dart';

class PhotoViewerPage extends StatelessWidget {
  const PhotoViewerPage({super.key, required this.node});
  final FamilyNode node;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: PhotoView(
        imageProvider: node.photoProvider,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 2,
      ),
    );
  }
}
