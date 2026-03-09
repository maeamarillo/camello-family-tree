class MemberDetails {
  final String? address;
  final String? phone;
  final String? company;
  final String? jobTitle;
  final String? fb;
  final String? ig;
  final String? xAccount;
  final String? tiktok;

  const MemberDetails({
    this.address,
    this.phone,
    this.company,
    this.jobTitle,
    this.fb,
    this.ig,
    this.xAccount,
    this.tiktok,
  });

  bool get isEmpty =>
      (address == null || address!.trim().isEmpty) &&
      (phone == null || phone!.trim().isEmpty) &&
      (company == null || company!.trim().isEmpty) &&
      (jobTitle == null || jobTitle!.trim().isEmpty) &&
      (fb == null || fb!.trim().isEmpty) &&
      (ig == null || ig!.trim().isEmpty) &&
      (xAccount == null || xAccount!.trim().isEmpty) &&
      (tiktok == null || tiktok!.trim().isEmpty);
}
