// lib/pages/member_form_sheet.dart
import 'package:app/models/member_form_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/gender.dart';
import '../models/member_details.dart';
import '../utilities/date_format.dart';

class MemberFormSheet {
  MemberFormSheet(this.context) : _messenger = ScaffoldMessenger.of(context);

  final BuildContext context;
  final ScaffoldMessengerState _messenger;
  final ImagePicker _picker = ImagePicker();

  void _showError(String message) {
    _messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<Uint8List?> _readBytes(XFile file) async {
    try {
      return await file.readAsBytes();
    } catch (e) {
      _showError('Failed to read image: $e');
      return null;
    }
  }

  Future<Uint8List?> _pickGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (image == null) return null;
      return _readBytes(image);
    } catch (e) {
      _showError('Failed to pick image: $e');
      return null;
    }
  }

  Future<Uint8List?> _pickCamera() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (image == null) return null;
      return _readBytes(image);
    } catch (e) {
      _showError('Failed to take photo: $e');
      return null;
    }
  }

  Future<DateTime?> _pickBirthday({DateTime? initial}) async {
    final now = DateTime.now();
    final firstDate = DateTime(1900, 1, 1);
    final lastDate = DateTime(now.year, now.month, now.day);

    final init = initial ?? DateTime(1990, 1, 1);
    final clampedInit =
        init.isBefore(firstDate) ? firstDate : (init.isAfter(lastDate) ? lastDate : init);

    return showDatePicker(
      context: context,
      initialDate: clampedInit,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Select birthday (or cancel to skip)',
    );
  }

  Future<DateTime?> _pickDeathDate({DateTime? initial}) async {
    final now = DateTime.now();
    final firstDate = DateTime(1900, 1, 1);
    final lastDate = DateTime(now.year, now.month, now.day);

    final init = initial ?? DateTime(now.year, now.month, now.day);
    final clampedInit =
        init.isBefore(firstDate) ? firstDate : (init.isAfter(lastDate) ? lastDate : init);

    return showDatePicker(
      context: context,
      initialDate: clampedInit,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Select date of death (or cancel to skip)',
    );
  }

  Widget _photoPreview(Uint8List? bytes, Gender g) {
    final has = bytes != null;
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: !has ? g.tone : null,
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: !has
          ? Icon(g.icon, size: 26, color: Colors.grey.shade700)
          : ClipOval(child: Image.memory(bytes, fit: BoxFit.cover)),
    );
  }

  Future<MemberFormResult> open({
    // ✅ NEW (name moved into the sheet)
    String? initialName,
    bool showNameField = false,

    required Gender initialGender,
    List<Gender> allowedGenders = const [Gender.female, Gender.male],
    MemberDetails? initialDetails,
    DateTime? initialBirthday,
    DateTime? initialDeathDate,
    Uint8List? initialPhotoBytes,
    bool allowRemovePhoto = true,
    bool allowClearBirthday = true,
    String title = 'Member Info',
  }) async {
    final init = initialDetails ?? const MemberDetails();

    // ✅ NEW
    final nameCtrl = TextEditingController(text: (initialName ?? '').trim());

    final barangayCtrl = TextEditingController(text: init.barangay?? '');
    final cityCtrl = TextEditingController(text: init.city ?? '');
    final provinceCtrl = TextEditingController(text: init.province ?? '');
    final phoneCtrl = TextEditingController(text: init.phone ?? '');
    final companyCtrl = TextEditingController(text: init.company ?? '');
    final jobTitleCtrl = TextEditingController(text: init.jobTitle ?? '');
    final fbCtrl = TextEditingController(text: init.fb ?? '');
    final igCtrl = TextEditingController(text: init.ig ?? '');
    final xCtrl = TextEditingController(text: init.xAccount ?? '');
    final tiktokCtrl = TextEditingController(text: init.tiktok ?? '');

    String? norm(TextEditingController c) {
      final t = c.text.trim();
      return t.isEmpty ? null : t;
    }

    // ✅ NEW
    String? normName() {
      final t = nameCtrl.text.trim();
      return t.isEmpty ? null : t;
    }

    final safeAllowed = allowedGenders.isEmpty ? const [Gender.female, Gender.male] : allowedGenders;
    final initGender = safeAllowed.contains(initialGender) ? initialGender : safeAllowed.first;

    final result = await showModalBottomSheet<MemberFormResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;

        Gender selectedGender = initGender;
        Uint8List? photoBytes = initialPhotoBytes;
        DateTime? birthday = initialBirthday;
        DateTime? deathDate = initialDeathDate;
        bool removePhoto = false;
        bool clearBirthday = false;
        bool clearDeathDate = false;

        final canChangeGender = safeAllowed.length > 1;

        InputDecoration deco(String hint) => const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ).copyWith(hintText: hint);

        Widget field(String label, TextEditingController c, {TextInputType? type}) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  controller: c,
                  keyboardType: type,
                  decoration: deco(label),
                ),
              ],
            ),
          );
        }

        return StatefulBuilder(
          builder: (ctx2, setSheetState) {
            Future<void> pickGallery() async {
              final bytes = await _pickGallery();
              if (bytes == null) return;
              setSheetState(() {
                photoBytes = bytes;
                removePhoto = false;
              });
            }

            Future<void> pickCamera() async {
              final bytes = await _pickCamera();
              if (bytes == null) return;
              setSheetState(() {
                photoBytes = bytes;
                removePhoto = false;
              });
            }

            Future<void> pickBday() async {
              final picked = await _pickBirthday(initial: birthday);
              if (picked == null) return;
              setSheetState(() {
                birthday = picked;
                clearBirthday = false;
              });
            }

            Future<void> pickDeathDate() async {
              final picked = await _pickDeathDate(initial: deathDate);
              if (picked == null) return;
              setSheetState(() {
                deathDate = picked;
                clearDeathDate = false;
              });
            }

            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.badge_outlined),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(
                              ctx2,
                              MemberFormResult.cancel(gender: initGender),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // ✅ NEW: Name field (optional)
                      if (showNameField) ...[
                        Text(
                          'Name',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: nameCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                            hintText: 'Enter full name',
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Divider(),
                        const SizedBox(height: 10),
                      ],

                      Text(
                        'Gender',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<Gender>(
                        segments: [
                          for (final g in safeAllowed)
                            ButtonSegment<Gender>(
                              value: g,
                              label: Text(g.label),
                              icon: Icon(g.icon, size: 18),
                            ),
                        ],
                        selected: {selectedGender},
                        onSelectionChanged:
                            canChangeGender ? (s) => setSheetState(() => selectedGender = s.first) : null,
                      ),

                      const SizedBox(height: 14),
                      const Divider(),
                      const SizedBox(height: 10),

                      Text(
                        'Photo',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _photoPreview(removePhoto ? null : photoBytes, selectedGender),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.tonalIcon(
                                  onPressed: pickGallery,
                                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                                  label: const Text('Gallery'),
                                ),
                                FilledButton.tonalIcon(
                                  onPressed: pickCamera,
                                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                                  label: const Text('Camera'),
                                ),
                                if (allowRemovePhoto)
                                  TextButton.icon(
                                    onPressed: () => setSheetState(() {
                                      removePhoto = true;
                                      photoBytes = null;
                                    }),
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Remove'),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),
                      const Divider(),
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Birthday',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ),
                          if (allowClearBirthday)
                            TextButton(
                              onPressed: () => setSheetState(() {
                                birthday = null;
                                clearBirthday = true;
                              }),
                              child: const Text('Clear'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: pickBday,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.cake_outlined, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  birthday == null ? 'Tap to select birthday' : formatDate(birthday!),
                                  style: TextStyle(
                                    color: birthday == null ? Colors.grey.shade600 : Colors.black87,
                                  ),
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),
                      const Divider(),
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Date of Death',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ),
                          if (allowClearBirthday)
                            TextButton(
                              onPressed: () => setSheetState(() {
                                deathDate = null;
                                clearDeathDate = true;
                              }),
                              child: const Text('Clear'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: pickDeathDate,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.sentiment_very_dissatisfied_outlined, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  deathDate == null
                                      ? 'Tap to select date of death'
                                      : formatDate(deathDate!),
                                  style: TextStyle(
                                    color: deathDate == null
                                        ? Colors.grey.shade600
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),
                      const Divider(),
                      const SizedBox(height: 10),

                      field('Barangay', barangayCtrl),
                      field('City', cityCtrl),
                      field('Province', provinceCtrl),
                      field('Tel / Cell No.', phoneCtrl, type: TextInputType.phone),
                      field('Company', companyCtrl),
                      field('Job Title', jobTitleCtrl),

                      const SizedBox(height: 6),
                      const Divider(),
                      const SizedBox(height: 10),

                      field('Facebook', fbCtrl),
                      field('Instagram', igCtrl),
                      field('X / Twitter', xCtrl),
                      field('TikTok', tiktokCtrl),

                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                // ✅ NEW: require name if showNameField
                                if (showNameField) {
                                  final n = normName();
                                  if (n == null) {
                                    _showError('Name is required.');
                                    return;
                                  }
                                }

                                Navigator.pop(
                                  ctx2,
                                  MemberFormResult(
                                    saved: true,
                                    name: showNameField ? normName() : null, // ✅ NEW
                                    gender: selectedGender,
                                    birthday: birthday,
                                    clearBirthday: clearBirthday,
                                    deathDate: deathDate,
                                    clearDeathDate: clearDeathDate,
                                    newPhotoBytes: photoBytes,
                                    removePhoto: removePhoto,
                                    details: MemberDetails(
                                      barangay: norm(barangayCtrl),
                                      city: norm(cityCtrl),
                                      province: norm(provinceCtrl),
                                      phone: norm(phoneCtrl),
                                      company: norm(companyCtrl),
                                      jobTitle: norm(jobTitleCtrl),
                                      fb: norm(fbCtrl),
                                      ig: norm(igCtrl),
                                      xAccount: norm(xCtrl),
                                      tiktok: norm(tiktokCtrl),
                                    ),
                                  ),
                                );
                              },
                              child: const Text('Save'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          TextButton(
                            onPressed: () => Navigator.pop(
                              ctx2,
                              MemberFormResult.cancel(gender: initGender),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    // ✅ dispose
    nameCtrl.dispose();
    barangayCtrl.dispose();
    cityCtrl.dispose();
    provinceCtrl.dispose();
    phoneCtrl.dispose();
    companyCtrl.dispose();
    jobTitleCtrl.dispose();
    fbCtrl.dispose();
    igCtrl.dispose();
    xCtrl.dispose();
    tiktokCtrl.dispose();

    return result ?? MemberFormResult.cancel(gender: initGender);
  }
}

bool ctrlPressed() {
  final kb = HardwareKeyboard.instance;
  return kb.isLogicalKeyPressed(LogicalKeyboardKey.controlLeft) ||
      kb.isLogicalKeyPressed(LogicalKeyboardKey.controlRight);
}