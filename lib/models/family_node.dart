import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'gender.dart';

class FamilyNode {
  FamilyNode({
    required this.id,
    required this.name,
    required this.gender,
    required this.levelY,
    required this.slotX,
    this.ownerUid,
    this.isDeceased = false,
    this.birthday,
    this.deathDate,
    this.photoPath,
    this.photoBytes,
    this.photoUrl,
    this.barangay,
    this.city,
    this.province,
    this.phone,
    this.company,
    this.jobTitle,
    this.fb,
    this.ig,
    this.xAccount,
    this.tiktok,
  });

  final int id;
  String name;
  Gender gender;

  final Set<int> parents = {};
  final Set<int> children = {};
  final Set<int> spouses = {};

  int levelY;
  double slotX;

  String? ownerUid;
  bool isDeceased;
  Offset manualOffset = Offset.zero;
  DateTime? birthday;
  DateTime? deathDate;

  String? photoPath;
  Uint8List? photoBytes;
  String? photoUrl;

  String? barangay;
  String? city;
  String? province;
  String? phone;
  String? company;
  String? jobTitle;
  String? fb;
  String? ig;
  String? xAccount;
  String? tiktok;

  bool get hasPhoto {
    if (photoBytes != null) return true;
    if (photoUrl != null && photoUrl!.trim().isNotEmpty) return true;
    if (!kIsWeb && photoPath != null && photoPath!.trim().isNotEmpty) return true;
    return false;
  }

  bool get hasAnyDetails {
    bool has(String? s) => s != null && s.trim().isNotEmpty;
    return has(barangay) ||
    has(city) ||
    has(province) ||
        has(phone) ||
        has(company) ||
        has(jobTitle) ||
        has(fb) ||
        has(ig) ||
        has(xAccount) ||
        has(tiktok);
  }

  ImageProvider get photoProvider {
    if (photoBytes != null) return MemoryImage(photoBytes!);

    if (photoUrl != null && photoUrl!.trim().isNotEmpty) {
      return NetworkImage(photoUrl!);
    }

    if (!kIsWeb &&
        photoPath != null &&
        photoPath!.trim().isNotEmpty &&
        File(photoPath!).existsSync()) {
      return FileImage(File(photoPath!));
    }

    return const AssetImage('assets/placeholder.png');
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ownerUid': ownerUid,
      'name': name,
      'gender': gender.name,
      'levelY': levelY,
      'slotX': slotX,
      'manualOffset': {
        'dx': manualOffset.dx,
        'dy': manualOffset.dy,
      },
      'birthday': birthday?.millisecondsSinceEpoch,
      'deathDate': deathDate?.millisecondsSinceEpoch,
      'parents': parents.toList(),
      'children': children.toList(),
      'spouses': spouses.toList(),
      'barangay': barangay,
      'city': city,
      'province': province,
      'phone': phone,
      'company': company,
      'jobTitle': jobTitle,
      'fb': fb,
      'ig': ig,
      'xAccount': xAccount,
      'tiktok': tiktok,
      'photoUrl': photoUrl,
      'isDeceased': isDeceased,
    };
  }

  static FamilyNode fromMap(Map<dynamic, dynamic> m) {
    final manualOffsetMap = (m['manualOffset'] as Map?) ?? const {};
    final legacyDx = m['manualDx'];
    final legacyDy = m['manualDy'];

    final node = FamilyNode(
      id: (m['id'] as num).toInt(),
      name: (m['name'] ?? '') as String,
      gender: Gender.values.firstWhere(
        (g) => g.name == (m['gender'] ?? 'female'),
        orElse: () => Gender.female,
      ),
      levelY: ((m['levelY'] ?? 0) as num).toInt(),
      slotX: ((m['slotX'] ?? 0) as num).toDouble(),
      ownerUid: m['ownerUid'] as String?,
      isDeceased: (m['isDeceased'] as bool?) ?? false,
      birthday: (m['birthday'] == null)
          ? null
          : DateTime.fromMillisecondsSinceEpoch((m['birthday'] as num).toInt()),
      deathDate: (m['deathDate'] == null)
          ? null
          : DateTime.fromMillisecondsSinceEpoch((m['deathDate'] as num).toInt()),
      photoUrl: m['photoUrl'] as String?,
      photoPath: m['photoPath'] as String?,
    );

    node.manualOffset = Offset(
      ((manualOffsetMap['dx'] ?? legacyDx ?? 0) as num).toDouble(),
      ((manualOffsetMap['dy'] ?? legacyDy ?? 0) as num).toDouble(),
    );

    node.parents.addAll(
      ((m['parents'] as List?) ?? const []).map((e) => (e as num).toInt()),
    );
    node.children.addAll(
      ((m['children'] as List?) ?? const []).map((e) => (e as num).toInt()),
    );
    node.spouses.addAll(
      ((m['spouses'] as List?) ?? const []).map((e) => (e as num).toInt()),
    );

    node.barangay = m['barangay'] as String?;
    node.city = m['city'] as String?;
    node.province = m['province'] as String?;
    node.phone = m['phone'] as String?;
    node.company = m['company'] as String?;
    node.jobTitle = m['jobTitle'] as String?;
    node.fb = m['fb'] as String?;
    node.ig = m['ig'] as String?;
    node.xAccount = m['xAccount'] as String?;
    node.tiktok = m['tiktok'] as String?;

    return node;
  }
}