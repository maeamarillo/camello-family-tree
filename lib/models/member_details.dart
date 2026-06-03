// lib/models/member_details.dart
// Add `country` to your existing MemberDetails model.
// Keep any other existing methods you may have; this is the minimum version
// needed by the updated family tree files.

class MemberDetails {
  const MemberDetails({
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
  });

  final String? barangay; // UI label: Street/Brgy/District
  final String? city; // UI label: Town/Municipality/City
  final String? province; // UI label: Province/State
  final String? country;
  final String? phone;
  final String? company;
  final String? jobTitle;
  final String? fb;
  final String? ig;
  final String? xAccount;
  final String? tiktok;
}
