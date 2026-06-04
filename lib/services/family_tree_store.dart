// lib/services/family_tree_store.dart
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/family_node.dart';
import '../models/gender.dart';
import '../models/member_details.dart';
import 'family_tree_rtdb.dart';

class FamilyTreeStore extends ChangeNotifier {
  final Map<int, FamilyNode> _nodes = {};
  int _nextId = 1;
  int? lastAddedId;

  Map<int, FamilyNode> get nodes => _nodes;

  String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  bool canEditNodeId(int id) {
    final uid = currentUid;
    if (uid == null) return false;
    final n = _nodes[id];
    if (n == null) return false;
    return n.ownerUid == uid;
  }

  bool canEditNode(FamilyNode n) {
    final uid = currentUid;
    if (uid == null) return false;
    return n.ownerUid == uid;
  }

  // Shared interactions: anyone signed-in can move tiles and create links.
  bool get canEditLayout => currentUid != null;
  bool get canEditLinks => currentUid != null;

  bool get canClearAll {
    final uid = currentUid;
    if (uid == null) return false;
    for (final n in _nodes.values) {
      if (n.ownerUid != uid) return false;
    }
    return true;
  }

  final FamilyTreeRtdb _rtdb = FamilyTreeRtdb();
  Timer? _saveDebounce;
  bool _loadingFromCloud = false;
  bool _dirtySinceLastSave = false;

  final Set<int> _pendingDeletes = {};

  Map<int, Map<String, dynamic>> _exportMyUpserts() {
    final uid = currentUid;
    final out = <int, Map<String, dynamic>>{};
    if (uid == null) return out;

    for (final e in _nodes.entries) {
      final n = e.value;

      // If I own the node, I can save everything.
      if (n.ownerUid == uid) {
        out[e.key] = n.toMap();
        continue;
      }

      // If I DON'T own the node, only save shared fields.
      out[e.key] = <String, dynamic>{
        'levelY': n.levelY,
        'slotX': n.slotX,
        'manualOffset': {
          'dx': n.manualOffset.dx,
          'dy': n.manualOffset.dy,
        },
        'parents': n.parents.toList(),
        'children': n.children.toList(),
        'spouses': n.spouses.toList(),
      };
    }

    return out;
  }

  void _recomputeNextId() {
    if (_nodes.isEmpty) {
      _nextId = 1;
      return;
    }
    _nextId = _nodes.keys.reduce(max) + 1;
  }

  void _importTree(Map<dynamic, dynamic> root) {
    Map<dynamic, dynamic> tree = root;

    final treeWrap = root['tree'];
    if (treeWrap is Map) tree = Map<dynamic, dynamic>.from(treeWrap);

    final dataWrap = root['data'];
    if (dataWrap is Map) tree = Map<dynamic, dynamic>.from(dataWrap);

    dynamic nodesRaw = tree['nodes'] ?? root['nodes'];
    nodesRaw ??= tree['members'] ?? root['members'];
    nodesRaw ??= tree['people'] ?? root['people'];

    _nodes.clear();

    if (nodesRaw is Map) {
      nodesRaw.forEach((k, v) {
        final id = int.tryParse(k.toString());
        if (id == null) return;
        if (v is! Map) return;

        final node = FamilyNode.fromMap(Map<dynamic, dynamic>.from(v));
        _nodes[id] = node;
      });
    } else if (nodesRaw is List) {
      for (int i = 0; i < nodesRaw.length; i++) {
        final v = nodesRaw[i];
        if (v is! Map) continue;

        final map = Map<dynamic, dynamic>.from(v);
        final idRaw = map['id'];
        final id = (idRaw is num) ? idRaw.toInt() : i;

        final node = FamilyNode.fromMap(map);
        _nodes[id] = node;
      }
    }

    _recomputeNextId();

    final lastRaw = tree['lastAddedId'] ?? root['lastAddedId'];
    lastAddedId = (lastRaw is num) ? lastRaw.toInt() : null;

    _stabilizeLayout();
  }

  Future<void> loadFromCloud({String treeId = 'default'}) async {
    _loadingFromCloud = true;
    try {
      final data = await _rtdb.loadTree(treeId);

      if (data == null) {
        debugPrint('RTDB loadTree returned null (no data at trees/$treeId).');
        _nodes.clear();
        _recomputeNextId();
        lastAddedId = null;
        notifyListeners();
        return;
      }

      _importTree(data);
      notifyListeners();

      debugPrint('✅ RTDB loaded. nodes=${_nodes.length}');
    } catch (e, st) {
      debugPrint('❌ RTDB load failed: $e');
      debugPrint('$st');
      rethrow; // let the caller know so _loadedOnce stays false
    } finally {
      _loadingFromCloud = false;
      _dirtySinceLastSave = false;
      _pendingDeletes.clear();
    }
  }

  void scheduleSaveToCloud({String treeId = 'default'}) {
    if (_loadingFromCloud) return;

    final uid = currentUid;
    if (uid == null) {
      debugPrint('❌ Not saving: user is not signed in (uid is null).');
      return;
    }

    _dirtySinceLastSave = true;

    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 700), () async {
      if (!_dirtySinceLastSave) return;

      try {
        final upsertsById = _exportMyUpserts();
        final deletesById = Set<int>.from(_pendingDeletes);

        debugPrint(
          'Saving my changes: upserts=${upsertsById.length}, deletes=${deletesById.length}',
        );

        await _rtdb.saveMyChanges(
          treeId,
          upsertsById: upsertsById,
          deletesById: deletesById,
        );

        _dirtySinceLastSave = false;
        _pendingDeletes.clear();

        debugPrint('✅ Saved to RTDB at: trees/$treeId');
      } catch (e, st) {
        debugPrint('❌ RTDB save failed: $e');
        debugPrint('$st');
      }
    });
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  FamilyNode createNode({
    required String name,
    String? firstName,
    String? middleName,
    String? lastName,
    String? nickname,
    required Gender gender,
    required int levelY,
    required double slotX,
    DateTime? birthday,
    DateTime? deathDate,
    String? photoPath,
    Uint8List? photoBytes,
    String? photoUrl,
    String? barangay,
    String? city,
    String? province,
    String? country,
    String? phone,
    String? company,
    String? jobTitle,
    String? fb,
    String? ig,
    String? xAccount,
    String? tiktok,
  }) {
    final uid = currentUid;

    final node = FamilyNode(
      id: _nextId++,
      name: name,
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      nickname: nickname,
      gender: gender,
      levelY: levelY,
      slotX: slotX,
      ownerUid: uid,
      birthday: birthday,
      deathDate: deathDate,
      photoPath: photoPath,
      photoBytes: photoBytes,
      photoUrl: photoUrl,
      barangay: barangay,
      city: city,
      province: province,
      country: country,
      phone: phone,
      company: company,
      jobTitle: jobTitle,
      fb: fb,
      ig: ig,
      xAccount: xAccount,
      tiktok: tiktok,
    );

    _nodes[node.id] = node;
    lastAddedId = node.id;
    return node;
  }

  FamilyNode getNode(int id) => _nodes[id]!;

  void setGender(int id, Gender g) {
    if (!_nodes.containsKey(id)) return;
    if (!canEditNodeId(id)) return;
    getNode(id).gender = g;
    notifyListeners();
    scheduleSaveToCloud();
  }

  void setBirthday(int id, DateTime? date) {
    if (!_nodes.containsKey(id)) return;
    if (!canEditNodeId(id)) return;
    getNode(id).birthday = date;
    notifyListeners();
    scheduleSaveToCloud();
  }

  void setDeathDate(int id, DateTime? date) {
    if (!_nodes.containsKey(id)) return;
    if (!canEditNodeId(id)) return;
    getNode(id).deathDate = date;
    notifyListeners();
    scheduleSaveToCloud();
  }

  void setPhoto(int id, String? photoPath, [Uint8List? photoBytes]) {
    if (!_nodes.containsKey(id)) return;
    if (!canEditNodeId(id)) return;

    final node = getNode(id);
    node.photoPath = photoPath;
    node.photoBytes = photoBytes;
    node.photoUrl = null;

    notifyListeners();
    scheduleSaveToCloud();
  }

  void setPhotoUrl(int id, String? photoUrl) {
    if (!_nodes.containsKey(id)) return;
    if (!canEditNodeId(id)) return;

    final node = getNode(id);
    node.photoUrl = (photoUrl ?? '').trim().isEmpty ? null : photoUrl!.trim();
    node.photoPath = null;
    node.photoBytes = null;

    notifyListeners();
    scheduleSaveToCloud();
  }

  void removePhoto(int id) {
    if (!_nodes.containsKey(id)) return;
    if (!canEditNodeId(id)) return;

    final node = getNode(id);
    node.photoPath = null;
    node.photoBytes = null;
    node.photoUrl = null;

    notifyListeners();
    scheduleSaveToCloud();
  }

  void setDetails(int id, MemberDetails d) {
    if (!_nodes.containsKey(id)) return;
    if (!canEditNodeId(id)) return;
    final n = getNode(id);
    n.barangay = d.barangay;
    n.city = d.city;
    n.province = d.province;
    n.country = d.country;
    n.phone = d.phone;
    n.company = d.company;
    n.jobTitle = d.jobTitle;
    n.fb = d.fb;
    n.ig = d.ig;
    n.xAccount = d.xAccount;
    n.tiktok = d.tiktok;
    notifyListeners();
    scheduleSaveToCloud();
  }

  void toggleDeceased(int id) {
    if (!_nodes.containsKey(id)) return;
    if (!canEditNodeId(id)) return;
    getNode(id).isDeceased = !getNode(id).isDeceased;
    notifyListeners();
    scheduleSaveToCloud();
  }

  void linkParentChild({
    required int parentId,
    required int childId,
    bool notify = true,
  }) {
    if (parentId == childId) return;
    if (!_nodes.containsKey(parentId) || !_nodes.containsKey(childId)) return;
    if (!canEditLinks) return;

    final parent = getNode(parentId);
    final child = getNode(childId);

    parent.children.add(childId);
    child.parents.add(parentId);

    if (notify) {
      notifyListeners();
      scheduleSaveToCloud();
    }
  }

  void linkSpouses({
    required int aId,
    required int bId,
    bool notify = true,
  }) {
    if (aId == bId) return;
    if (!_nodes.containsKey(aId) || !_nodes.containsKey(bId)) return;
    if (!canEditLinks) return;

    final a = getNode(aId);
    final b = getNode(bId);

    a.spouses.add(bId);
    b.spouses.add(aId);

    if (notify) {
      notifyListeners();
      scheduleSaveToCloud();
    }
  }

  int? spouseOf(int personId) {
    final n = getNode(personId);
    if (n.spouses.isEmpty) return null;
    return n.spouses.first;
  }

  void renameNode(int id, String newName) {
    if (!_nodes.containsKey(id)) return;
    if (!canEditNodeId(id)) return;
    final nn = newName.trim();
    if (nn.isEmpty) return;

    // Legacy helper: parse a full name and keep the new name-part fields in sync.
    final parts = nn.split(RegExp(r'\s+')).where((p) => p.trim().isNotEmpty).toList();
    if (parts.length == 1) {
      setNameParts(id, firstName: parts.first, lastName: '');
      return;
    }

    setNameParts(
      id,
      firstName: parts.first,
      middleName: parts.length > 2 ? parts.sublist(1, parts.length - 1).join(' ') : null,
      lastName: parts.length > 1 ? parts.last : '',
    );
  }

  void setNameParts(
    int id, {
    required String firstName,
    String? middleName,
    required String lastName,
    String? nickname,
  }) {
    if (!_nodes.containsKey(id)) return;
    if (!canEditNodeId(id)) return;

    final fn = firstName.trim();
    final ln = lastName.trim();
    if (fn.isEmpty || ln.isEmpty) return;

    getNode(id).setNameParts(
      firstName: fn,
      middleName: middleName,
      lastName: ln,
      nickname: nickname,
    );

    notifyListeners();
    scheduleSaveToCloud();
  }

  (int? femaleParentId, int? maleParentId) parentPairForPerson(int personId) {
    int? femaleP;
    int? maleP;
    final person = getNode(personId);

    for (final pid in person.parents) {
      final p = getNode(pid);
      if (p.gender == Gender.female) femaleP ??= pid;
      if (p.gender == Gender.male) maleP ??= pid;
    }
    return (femaleP, maleP);
  }

  bool hasCoParentViaChildren(int personId) {
    final person = getNode(personId);
    for (final childId in person.children) {
      final child = getNode(childId);
      for (final pid in child.parents) {
        if (pid != personId) return true;
      }
    }
    return false;
  }

  int? _findCoParentBySharedChild(int fromNodeId) {
    final from = getNode(fromNodeId);
    for (final existingChildId in from.children) {
      final existingChild = getNode(existingChildId);
      for (final pid in existingChild.parents) {
        if (pid != from.id) return pid;
      }
    }
    return null;
  }

  int? _findCoParentPreferSpouse(int fromNodeId) {
    final sp = spouseOf(fromNodeId);
    if (sp != null) return sp;
    return _findCoParentBySharedChild(fromNodeId);
  }

  double _nearestFreeSlotAtLevel({
    required int levelY,
    required double anchorSlot,
    required bool preferLeft,
  }) {
    final taken = <int>{};
    for (final n in _nodes.values) {
      if (n.levelY == levelY) taken.add(n.slotX.toInt());
    }

    final base = anchorSlot.round();

    for (int d = 0; d < 500; d++) {
      final left = base - d;
      final right = base + d;

      if (d == 0) {
        if (!taken.contains(base)) return base.toDouble();
        continue;
      }

      if (preferLeft) {
        if (!taken.contains(left)) return left.toDouble();
        if (!taken.contains(right)) return right.toDouble();
      } else {
        if (!taken.contains(right)) return right.toDouble();
        if (!taken.contains(left)) return left.toDouble();
      }
    }

    return (base + 1).toDouble();
  }

  double _nextChildSlotSmart(int fromNodeId) {
    final from = getNode(fromNodeId);
    final childLevel = from.levelY + 1;

    final coparentId = _findCoParentPreferSpouse(fromNodeId);
    if (coparentId == null) {
      return _nearestFreeSlotAtLevel(
        levelY: childLevel,
        anchorSlot: from.slotX,
        preferLeft: true,
      );
    }

    final cp = getNode(coparentId);
    final anchor = (from.slotX + cp.slotX) / 2;
    final preferLeft = from.slotX <= cp.slotX;

    return _nearestFreeSlotAtLevel(
      levelY: childLevel,
      anchorSlot: anchor,
      preferLeft: preferLeft,
    );
  }

  double _newParentSlot({
    required int personId,
    required Gender newParentGender,
    required int? existingOtherParentId,
  }) {
    final person = getNode(personId);
    if (existingOtherParentId == null) return person.slotX;

    final other = getNode(existingOtherParentId);

    // Place new parent to the left of the existing one if female (or same-gender
    // first added), otherwise to the right.  For same-gender pairs we simply
    // always put the new one to the right so they don't collide.
    if (newParentGender == Gender.female && other.gender != Gender.female) {
      return min(other.slotX, person.slotX) - 1;
    } else {
      return max(other.slotX, person.slotX) + 1;
    }
  }

  void _linkNewParentToSharedChildren({
    required int newParentId,
    required Gender newParentGender,
    required int otherParentId,
  }) {
    final otherParent = getNode(otherParentId);

    for (final childId in otherParent.children) {
      if (!_nodes.containsKey(childId)) continue;

      if (childId == newParentId) continue;
      if (getNode(childId).parents.length >= 2) continue;

      linkParentChild(parentId: newParentId, childId: childId, notify: false);
    }
  }

  static const int _minSlotGap = 1;

  void _compactSlotsPerLevel() {
    if (_nodes.isEmpty) return;

    final byLevel = <int, List<int>>{};
    for (final n in _nodes.values) {
      byLevel.putIfAbsent(n.levelY, () => []).add(n.id);
    }

    for (final entry in byLevel.entries) {
      final ids = entry.value;
      ids.sort((a, b) => _nodes[a]!.slotX.compareTo(_nodes[b]!.slotX));

      final taken = <int>{};
      int? prevSlot;

      for (final id in ids) {
        final node = _nodes[id]!;
        int target = node.slotX.toInt();

        if (prevSlot != null) {
          final minAllowed = prevSlot + _minSlotGap;
          if (target < minAllowed) target = minAllowed;
        }

        while (taken.contains(target)) {
          target += 1;
        }

        taken.add(target);
        node.slotX = target.toDouble();
        prevSlot = target;
      }

      ids.sort((a, b) => _nodes[a]!.slotX.compareTo(_nodes[b]!.slotX));
      for (int i = ids.length - 2; i >= 0; i--) {
        final left = _nodes[ids[i]]!;
        final right = _nodes[ids[i + 1]]!;
        final maxAllowed = right.slotX.toInt() - _minSlotGap;
        final cur = left.slotX.toInt();
        if (cur > maxAllowed) left.slotX = maxAllowed.toDouble();
      }
    }
  }

  void _anchorToRoot() {
    if (_nodes.isEmpty) return;

    FamilyNode anchor = _nodes.values.first;
    for (final n in _nodes.values) {
      if (n.levelY < anchor.levelY) {
        anchor = n;
      } else if (n.levelY == anchor.levelY && n.id < anchor.id) {
        anchor = n;
      }
    }

    final shift = anchor.slotX.toInt();
    if (shift == 0) return;

    for (final n in _nodes.values) {
      n.slotX -= shift;
    }
  }

  void _stabilizeLayout() {
    _compactSlotsPerLevel();
    _anchorToRoot();
  }

  void deleteNode(int id) {
    if (!_nodes.containsKey(id)) return;
    if (!canEditNodeId(id)) return;

    final node = getNode(id);

    // Only ownership of the deleted node itself is required.
    // Unlinking it from connected nodes is a shared graph operation —
    // no ownership of parents/children/spouses is needed.

    for (final pid in node.parents.toList()) {
      _nodes[pid]?.children.remove(id);
    }
    for (final cid in node.children.toList()) {
      _nodes[cid]?.parents.remove(id);
    }
    for (final sid in node.spouses.toList()) {
      _nodes[sid]?.spouses.remove(id);
    }

    _nodes.remove(id);
    _pendingDeletes.add(id);

    if (lastAddedId == id) {
      lastAddedId = _nodes.isEmpty ? null : _nodes.keys.reduce(max);
    }

    _recomputeNextId();
    _stabilizeLayout();
    notifyListeners();
    scheduleSaveToCloud();
  }

  FamilyNode addRoot({
    required String name,
    String? firstName,
    String? middleName,
    String? lastName,
    String? nickname,
    required Gender gender,
    DateTime? birthday,
    DateTime? deathDate,
    Uint8List? photoBytes,
    String? photoUrl,
    String? barangay,
    String? city,
    String? province,
    String? country,
    String? phone,
    String? company,
    String? jobTitle,
    String? fb,
    String? ig,
    String? xAccount,
    String? tiktok,
  }) {
    final root = createNode(
      name: name,
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      nickname: nickname,
      gender: gender,
      levelY: 0,
      slotX: 0,
      birthday: birthday,
      deathDate: deathDate,
      photoBytes: photoBytes,
      photoUrl: photoUrl,
      barangay: barangay,
      city: city,
      province: province,
      country: country,
      phone: phone,
      company: company,
      jobTitle: jobTitle,
      fb: fb,
      ig: ig,
      xAccount: xAccount,
      tiktok: tiktok,
    );
    _stabilizeLayout();
    notifyListeners();
    scheduleSaveToCloud();
    return root;
  }

  FamilyNode addStandalone({
    required String name,
    String? firstName,
    String? middleName,
    String? lastName,
    String? nickname,
    required Gender gender,
    DateTime? birthday,
    DateTime? deathDate,
    Uint8List? photoBytes,
    String? photoUrl,
    String? barangay,
    String? city,
    String? province,
    String? country,
    String? phone,
    String? company,
    String? jobTitle,
    String? fb,
    String? ig,
    String? xAccount,
    String? tiktok,
  }) {
    const level = 0;

    double anchor = 0;
    bool anyAtLevel = false;

    for (final n in _nodes.values) {
      if (n.levelY == level) {
        anyAtLevel = true;
        anchor = max(anchor, n.slotX);
      }
    }

    final slot = _nearestFreeSlotAtLevel(
      levelY: level,
      anchorSlot: anyAtLevel ? (anchor + 1) : 0,
      preferLeft: false,
    );

    final node = createNode(
      name: name,
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      nickname: nickname,
      gender: gender,
      levelY: level,
      slotX: slot,
      birthday: birthday,
      deathDate: deathDate,
      photoBytes: photoBytes,
      photoUrl: photoUrl,
      barangay: barangay,
      city: city,
      province: province,
      country: country,
      phone: phone,
      company: company,
      jobTitle: jobTitle,
      fb: fb,
      ig: ig,
      xAccount: xAccount,
      tiktok: tiktok,
    );

    _stabilizeLayout();
    notifyListeners();
    scheduleSaveToCloud();
    return node;
  }

  void _backfillSpouseAsCoParent({required int personId, required int spouseId}) {
    final person = getNode(personId);
    final spouse = getNode(spouseId);

    for (final childId in person.children) {
      final (femaleP, maleP) = parentPairForPerson(childId);
      if (spouse.gender == Gender.female && femaleP == null) {
        linkParentChild(parentId: spouseId, childId: childId, notify: false);
      } else if (spouse.gender == Gender.male && maleP == null) {
        linkParentChild(parentId: spouseId, childId: childId, notify: false);
      }
    }

    for (final childId in spouse.children) {
      final (femaleP, maleP) = parentPairForPerson(childId);
      if (person.gender == Gender.female && femaleP == null) {
        linkParentChild(parentId: personId, childId: childId, notify: false);
      } else if (person.gender == Gender.male && maleP == null) {
        linkParentChild(parentId: personId, childId: childId, notify: false);
      }
    }
  }

  FamilyNode? addSpouse({
    required int personId,
    required String name,
    String? firstName,
    String? middleName,
    String? lastName,
    String? nickname,
    DateTime? birthday,
    DateTime? deathDate,
    Uint8List? photoBytes,
    String? photoUrl,
    String? barangay,
    String? city,
    String? province,
    String? country,
    String? phone,
    String? company,
    String? jobTitle,
    String? fb,
    String? ig,
    String? xAccount,
    String? tiktok,
  }) {
    if (!canEditNodeId(personId)) return null;

    final person = getNode(personId);
    if (person.spouses.isNotEmpty) return null;

    final spouseGender = person.gender.opposite;
    final preferLeft = spouseGender == Gender.female;
    final anchor = person.slotX + (preferLeft ? -1 : 1);

    final slot = _nearestFreeSlotAtLevel(
      levelY: person.levelY,
      anchorSlot: anchor,
      preferLeft: preferLeft,
    );

    final spouse = createNode(
      name: name,
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      nickname: nickname,
      gender: spouseGender,
      levelY: person.levelY,
      slotX: slot,
      birthday: birthday,
      deathDate: deathDate,
      photoBytes: photoBytes,
      photoUrl: photoUrl,
      barangay: barangay,
      city: city,
      province: province,
      country: country,
      phone: phone,
      company: company,
      jobTitle: jobTitle,
      fb: fb,
      ig: ig,
      xAccount: xAccount,
      tiktok: tiktok,
    );

    linkSpouses(aId: personId, bId: spouse.id, notify: false);
    _backfillSpouseAsCoParent(personId: personId, spouseId: spouse.id);

    _stabilizeLayout();
    notifyListeners();
    scheduleSaveToCloud();
    return spouse;
  }

  FamilyNode? addParent({
    required int personId,
    required Gender parentGender,
    required String name,
    String? firstName,
    String? middleName,
    String? lastName,
    String? nickname,
    DateTime? birthday,
    DateTime? deathDate,
    Uint8List? photoBytes,
    String? photoUrl,
    String? barangay,
    String? city,
    String? province,
    String? country,
    String? phone,
    String? company,
    String? jobTitle,
    String? fb,
    String? ig,
    String? xAccount,
    String? tiktok,
  }) {
    if (!canEditNodeId(personId)) return null;

    final person = getNode(personId);
    if (person.parents.length >= 2) return null;

    final (femaleP, maleP) = parentPairForPerson(personId);

    // For same-gender parents, pick the existing parent of either gender as
    // the "other" for slot/linking purposes (first one found, if any).
    final int? otherParentId;
    if (parentGender == Gender.female) {
      otherParentId = maleP ?? (femaleP);
    } else {
      otherParentId = femaleP ?? (maleP);
    }
    // No ownership check on otherParentId — linking alongside a foreign-owned
    // parent is a shared graph operation, not an edit of that parent node.


    final parent = createNode(
      name: name,
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      nickname: nickname,
      gender: parentGender,
      levelY: person.levelY - 1,
      slotX: _newParentSlot(
        personId: personId,
        newParentGender: parentGender,
        existingOtherParentId: otherParentId,
      ),
      birthday: birthday,
      deathDate: deathDate,
      photoBytes: photoBytes,
      photoUrl: photoUrl,
      barangay: barangay,
      city: city,
      province: province,
      country: country,
      phone: phone,
      company: company,
      jobTitle: jobTitle,
      fb: fb,
      ig: ig,
      xAccount: xAccount,
      tiktok: tiktok,
    );

    linkParentChild(parentId: parent.id, childId: personId, notify: false);

    if (otherParentId != null) {
      _linkNewParentToSharedChildren(
        newParentId: parent.id,
        newParentGender: parentGender,
        otherParentId: otherParentId,
      );
    }

    _stabilizeLayout();
    notifyListeners();
    scheduleSaveToCloud();
    return parent;
  }

  FamilyNode addChild({
    required int fromNodeId,
    required String name,
    String? firstName,
    String? middleName,
    String? lastName,
    String? nickname,
    required Gender childGender,
    DateTime? birthday,
    DateTime? deathDate,
    Uint8List? photoBytes,
    String? photoUrl,
    String? barangay,
    String? city,
    String? province,
    String? country,
    String? phone,
    String? company,
    String? jobTitle,
    String? fb,
    String? ig,
    String? xAccount,
    String? tiktok,
  }) {
    if (!canEditNodeId(fromNodeId)) {
      throw Exception('Not allowed to add child to a node you do not own.');
    }

    final from = getNode(fromNodeId);
    final slot = _nextChildSlotSmart(fromNodeId);

    final child = createNode(
      name: name,
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      nickname: nickname,
      gender: childGender,
      levelY: from.levelY + 1,
      slotX: slot,
      birthday: birthday,
      deathDate: deathDate,
      photoBytes: photoBytes,
      photoUrl: photoUrl,
      barangay: barangay,
      city: city,
      province: province,
      country: country,
      phone: phone,
      company: company,
      jobTitle: jobTitle,
      fb: fb,
      ig: ig,
      xAccount: xAccount,
      tiktok: tiktok,
    );

    linkParentChild(parentId: from.id, childId: child.id, notify: false);

    final coparentId = _findCoParentPreferSpouse(fromNodeId);
    if (coparentId != null) {
      linkParentChild(parentId: coparentId, childId: child.id, notify: false);
    }

    _stabilizeLayout();
    notifyListeners();
    scheduleSaveToCloud();
    return child;
  }

  void addManualOffset(int nodeId, Offset delta) {
    if (!_nodes.containsKey(nodeId)) return;
    if (!canEditLayout) return;
    getNode(nodeId).manualOffset += delta;
    notifyListeners();
    scheduleSaveToCloud();
  }

  void addManualOffsetBulk(Set<int> nodeIds, Offset delta) {
    if (!canEditLayout) return;
    bool changed = false;
    for (final id in nodeIds) {
      final n = _nodes[id];
      if (n == null) continue;
      n.manualOffset += delta;
      changed = true;
    }
    if (changed) {
      notifyListeners();
      scheduleSaveToCloud();
    }
  }

  void clearAll() {
    if (!canClearAll) return;

    for (final id in _nodes.keys) {
      _pendingDeletes.add(id);
    }

    _nodes.clear();
    _recomputeNextId();
    lastAddedId = null;

    notifyListeners();
    scheduleSaveToCloud();
  }

  bool tryLinkExistingParent({required int parentId, required int childId}) {
    if (!_nodes.containsKey(parentId) || !_nodes.containsKey(childId)) return false;
    if (parentId == childId) return false;

    if (!canEditLinks) return false;

    final parent = getNode(parentId);
    final child = getNode(childId);

    if (child.parents.length >= 2) return false;

    linkParentChild(parentId: parentId, childId: childId, notify: false);

    child.levelY = parent.levelY + 1;
    child.slotX = _nextChildSlotSmart(parentId);
    child.manualOffset = Offset.zero;

    _stabilizeLayout();
    notifyListeners();
    scheduleSaveToCloud();
    return true;
  }

  bool tryLinkExistingChild({required int parentId, required int childId}) {
    return tryLinkExistingParent(parentId: parentId, childId: childId);
  }

  bool tryLinkExistingSpouses({required int aId, required int bId}) {
    if (!_nodes.containsKey(aId) || !_nodes.containsKey(bId)) return false;
    if (aId == bId) return false;

    if (!canEditLinks) return false;

    final a = getNode(aId);
    final b = getNode(bId);

    if (a.spouses.isNotEmpty || b.spouses.isNotEmpty) return false;

    linkSpouses(aId: aId, bId: bId, notify: false);

    _stabilizeLayout();
    notifyListeners();
    scheduleSaveToCloud();
    return true;
  }
}