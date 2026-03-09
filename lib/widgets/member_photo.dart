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
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 42,
        height: 42,
        color: !node.hasPhoto ? node.gender.tone : null,
        child: !node.hasPhoto
            ? Icon(node.gender.icon, color: Colors.black87)
            : Image(
                image: node.photoProvider,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: node.gender.tone,
                    child: Icon(node.gender.icon, color: Colors.black87),
                  );
                },
              ),
      ),
    );
  }
}
