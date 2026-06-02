// lib/models/member_form_result.dart
import 'dart:typed_data';
import 'gender.dart';
import 'member_details.dart';

class MemberFormResult {
  const MemberFormResult({
    required this.saved,
    required this.gender,
    required this.details,
    this.name,
    this.firstName,
    this.middleName,
    this.lastName,
    this.nickname,
    this.birthday,
    this.clearBirthday = false,
    this.deathDate,
    this.clearDeathDate = false,
    this.newPhotoBytes,
    this.removePhoto = false,
  });

  final bool saved;

  /// Backward-compatible display name.
  final String? name;

  final String? firstName;
  final String? middleName;
  final String? lastName;
  final String? nickname;

  final Gender gender;
  final MemberDetails details;

  final DateTime? birthday;
  final bool clearBirthday;

  final DateTime? deathDate;
  final bool clearDeathDate;

  final Uint8List? newPhotoBytes;
  final bool removePhoto;

  String get displayName {
    final parts = <String>[
      (firstName ?? '').trim(),
      if ((middleName ?? '').trim().isNotEmpty) middleName!.trim(),
      (lastName ?? '').trim(),
    ].where((p) => p.isNotEmpty).toList();

    var display = parts.join(' ').trim();
    if (display.isEmpty) display = (name ?? '').trim();

    final alias = (nickname ?? '').trim();
    if (display.isNotEmpty && alias.isNotEmpty) display = '$display ($alias)';

    return display;
  }

  factory MemberFormResult.cancel({required Gender gender}) {
    return MemberFormResult(
      saved: false,
      gender: gender,
      name: null,
      firstName: null,
      middleName: null,
      lastName: null,
      nickname: null,
      details: const MemberDetails(),
      birthday: null,
      clearBirthday: false,
      deathDate: null,
      clearDeathDate: false,
      newPhotoBytes: null,
      removePhoto: false,
    );
  }
}
