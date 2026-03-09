// lib/models/member_form_result.dart
import 'dart:typed_data';
import 'gender.dart';
import 'member_details.dart';

class MemberFormResult {
  const MemberFormResult({
    required this.saved,
    required this.gender,
    required this.details,
    this.name, // ✅ NEW
    this.birthday,
    this.clearBirthday = false,
    this.newPhotoBytes,
    this.removePhoto = false,
  });

  final bool saved;

  // ✅ NEW
  final String? name;

  final Gender gender;
  final MemberDetails details;

  final DateTime? birthday;
  final bool clearBirthday;

  final Uint8List? newPhotoBytes;
  final bool removePhoto;

  factory MemberFormResult.cancel({required Gender gender}) {
    return MemberFormResult(
      saved: false,
      gender: gender,
      name: null,
      details: const MemberDetails(),
      birthday: null,
      clearBirthday: false,
      newPhotoBytes: null,
      removePhoto: false,
    );
  }
}
