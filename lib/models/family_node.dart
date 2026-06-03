import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'gender.dart';

class FamilyNode {
  FamilyNode({
    required this.id,
    required String name,
    String? firstName,
    String? middleName,
    String? lastName,
    String? nickname,
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
    this.country,
    this.phone,
    this.company,
    this.jobTitle,
    this.fb,
    this.ig,
    this.xAccount,
    this.tiktok,
  }) {
    final parsed = _parseLegacyName(name);
    this.firstName = _cleanRequired(firstName) ?? parsed.$1;
    this.middleName = _cleanOptional(middleName) ?? parsed.$2;
    this.lastName = _cleanRequired(lastName) ?? parsed.$3;
    this.nickname = _cleanOptional(nickname) ?? parsed.$4;
    this.name = buildDisplayName(
      firstName: this.firstName,
      middleName: this.middleName,
      lastName: this.lastName,
      nickname: this.nickname,
      fallback: name,
    );
  }

  final int id;

  /// Display name used by existing UI/search code.
  /// It is rebuilt whenever name parts are updated.
  late String name;

  late String firstName;
  String? middleName;
  late String lastName;
  String? nickname;

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
  String? country;
  String? phone;
  String? company;
  String? jobTitle;
  String? fb;
  String? ig;
  String? xAccount;
  String? tiktok;

  static String? _cleanOptional(String? value) {
    final v = (value ?? '').trim();
    return v.isEmpty ? null : v;
  }

  static String? _cleanRequired(String? value) {
    final v = (value ?? '').trim();
    return v.isEmpty ? null : v;
  }

  static String buildDisplayName({
    required String firstName,
    String? middleName,
    required String lastName,
    String? nickname,
    String? fallback,
  }) {
    final parts = <String>[
      firstName.trim(),
      if ((middleName ?? '').trim().isNotEmpty) middleName!.trim(),
      lastName.trim(),
    ].where((p) => p.isNotEmpty).toList();

    var display = parts.join(' ').trim();
    if (display.isEmpty) display = (fallback ?? '').trim();
    if (display.isEmpty) display = 'Unnamed Member';

    final alias = (nickname ?? '').trim();
    if (alias.isNotEmpty) display = '$display ($alias)';

    return display;
  }

  static (String, String?, String, String?) _parseLegacyName(String name) {
    var raw = name.trim();
    String? alias;

    final aliasMatch = RegExp(r'\(([^)]+)\)\s*$').firstMatch(raw);
    if (aliasMatch != null) {
      alias = aliasMatch.group(1)?.trim();
      raw = raw.substring(0, aliasMatch.start).trim();
    }

    final parts = raw.split(RegExp(r'\s+')).where((p) => p.trim().isNotEmpty).toList();
    if (parts.isEmpty) return ('', null, '', alias);
    if (parts.length == 1) return (parts.first, null, '', alias);
    if (parts.length == 2) return (parts.first, null, parts.last, alias);

    return (
      parts.first,
      parts.sublist(1, parts.length - 1).join(' '),
      parts.last,
      alias,
    );
  }

  void setNameParts({
    required String firstName,
    String? middleName,
    required String lastName,
    String? nickname,
  }) {
    this.firstName = firstName.trim();
    this.middleName = _cleanOptional(middleName);
    this.lastName = lastName.trim();
    this.nickname = _cleanOptional(nickname);
    name = buildDisplayName(
      firstName: this.firstName,
      middleName: this.middleName,
      lastName: this.lastName,
      nickname: this.nickname,
    );
  }

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
        has(country) ||
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
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName,
      'nickname': nickname,
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
      'country': country,
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
      firstName: m['firstName'] as String?,
      middleName: m['middleName'] as String?,
      lastName: m['lastName'] as String?,
      nickname: (m['nickname'] ?? m['alias']) as String?,
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
    node.country = m['country'] as String?;
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
