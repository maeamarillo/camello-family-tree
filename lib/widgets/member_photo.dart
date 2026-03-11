import 'package:app/models/gender.dart';
import 'package:flutter/material.dart';
import '../models/family_node.dart';

class MemberPhoto extends StatelessWidget {
  const MemberPhoto({
    super.key,
    required this.node,
  });

  final FamilyNode node;

  @override
  Widget build(BuildContext context) {
    // Using LayoutBuilder or simply an AspectRatio to ensure it 
    // expands to the height of the parent Row/Padding.
    return AspectRatio(
      aspectRatio: 1.0, // Keeps it square
      child: ClipRRect(
        // Matching the card's outer radius or keeping a slight internal curve
        borderRadius: BorderRadius.circular(12), 
        child: Container(
          // Removing hardcoded 42x42 so it fills the parent's height
          color: !node.hasPhoto ? node.gender.tone : null,
          child: !node.hasPhoto
              ? Icon(node.gender.icon, color: Colors.black87, size: 28)
              : Image(
                  image: node.photoProvider,
                  fit: BoxFit.cover, // Ensures the image fills the square
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: node.gender.tone,
                      child: Icon(node.gender.icon, color: Colors.black87),
                    );
                  },
                ),
        ),
      ),
    );
  }
}