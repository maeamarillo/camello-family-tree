import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'; // ✅ MatrixUtils

void main() => runApp(const DashboardPage());

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Family Tree Builder',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        scaffoldBackgroundColor: const Color(0xFFF6F7F9),
      ),
      home: const FamilyTreePage(),
    );
  }
}

/// ✅ Every member has gender via Kind (no "unknown").
enum Gender { female, male }

/// ✅ Replace "child" with "son/daughter". Parents are still mother/father.
enum Kind { mother, father, son, daughter }

extension KindUi on Kind {
  Gender get gender => switch (this) {
        Kind.mother => Gender.female,
        Kind.daughter => Gender.female,
        Kind.father => Gender.male,
        Kind.son => Gender.male,
      };

  String get label => switch (this) {
        Kind.mother => 'Mother',
        Kind.father => 'Father',
        Kind.son => 'Son',
        Kind.daughter => 'Daughter',
      };

  IconData get icon => switch (this) {
        Kind.mother => Icons.female,
        Kind.daughter => Icons.girl,
        Kind.father => Icons.male,
        Kind.son => Icons.boy,
      };
}

/// In-memory node model (bi-directional relationships).
class FamilyNode {
  FamilyNode({
    required this.id,
    required this.name,
    required this.kind,
    required this.levelY,
    required this.slotX,
  });

  final int id;
  String name;

  /// ✅ Fixed label (Mother/Father/Son/Daughter) and implies gender.
  Kind kind;

  Gender get gender => kind.gender;

  /// Parents/children stored as IDs for simplicity & stability.
  final Set<int> parents = {};
  final Set<int> children = {};

  /// ✅ Spouse links (bi-directional)
  final Set<int> spouses = {};

  /// ✅ Persistent layout metadata (NO global recompute).
  int levelY;

  /// Stable horizontal "slot" (like a column)
  double slotX;

  /// Optional manual offset: drag a node and it nudges from auto-layout.
  Offset manualOffset = Offset.zero;
}

/// Simple in-memory graph store + relationship helpers.
class FamilyTreeStore extends ChangeNotifier {
  final Map<int, FamilyNode> _nodes = {};
  int _nextId = 1;

  int? lastAddedId;

  Map<int, FamilyNode> get nodes => _nodes;

  FamilyNode createNode({
    required String name,
    required Kind kind,
    required int levelY,
    required double slotX,
  }) {
    final node = FamilyNode(
      id: _nextId++,
      name: name,
      kind: kind,
      levelY: levelY,
      slotX: slotX,
    );
    _nodes[node.id] = node;
    lastAddedId = node.id;
    return node;
  }

  FamilyNode getNode(int id) => _nodes[id]!;

  /// Ensures parent<->child linkage is always bi-directional.
  void linkParentChild({
    required int parentId,
    required int childId,
    bool notify = true,
  }) {
    if (parentId == childId) return;
    if (!_nodes.containsKey(parentId) || !_nodes.containsKey(childId)) return;

    final parent = getNode(parentId);
    final child = getNode(childId);

    parent.children.add(childId);
    child.parents.add(parentId);

    if (notify) notifyListeners();
  }

  /// ✅ Spouse linkage is always bi-directional.
  void linkSpouses({required int aId, required int bId, bool notify = true}) {
    if (aId == bId) return;
    if (!_nodes.containsKey(aId) || !_nodes.containsKey(bId)) return;

    final a = getNode(aId);
    final b = getNode(bId);

    a.spouses.add(bId);
    b.spouses.add(aId);

    if (notify) notifyListeners();
  }

  int? spouseOf(int personId) {
    final n = getNode(personId);
    if (n.spouses.isEmpty) return null;
    return n.spouses.first;
  }

  void renameNode(int id, String newName) {
    getNode(id).name =
        newName.trim().isEmpty ? getNode(id).name : newName.trim();
    notifyListeners();
  }

  /// ✅ "Mother/Father slot" is determined by parent gender (from Kind).
  (int? motherId, int? fatherId) parentPairForPerson(int personId) {
    int? mother;
    int? father;
    final person = getNode(personId);

    for (final pid in person.parents) {
      final p = getNode(pid);
      if (p.gender == Gender.female) mother ??= pid;
      if (p.gender == Gender.male) father ??= pid;
    }
    return (mother, father);
  }

  /// ✅ NEW: true if this person already has a co-parent via any shared child.
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

  /// Finds a co-parent for `from` (based on any shared existing child).
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

  /// Prefer spouse as co-parent (if present), otherwise fall back to shared-child logic.
  int? _findCoParentPreferSpouse(int fromNodeId) {
    final sp = spouseOf(fromNodeId);
    if (sp != null) return sp;
    return _findCoParentBySharedChild(fromNodeId);
  }

  /// ✅ Spouse kind options (opposite gender) — NO "Son" and NO "Daughter"
  List<Kind> allowedSpouseKindsFor(Kind personKind) {
    final wantsFemale = personKind.gender == Gender.male;
    if (wantsFemale) return const [Kind.mother];
    return const [Kind.father];
  }

  // -------------------------------------------------------------------
  // ✅ Slot picking that avoids drift + avoids overlaps when crowded
  // -------------------------------------------------------------------

  /// ✅ Find nearest free slot at a given level, centered around an anchor slot.
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
    required Kind parentKind,
    required int? existingOtherParentId,
  }) {
    final person = getNode(personId);
    if (existingOtherParentId == null) return person.slotX;

    final other = getNode(existingOtherParentId);
    if (parentKind == Kind.mother) {
      return min(other.slotX, person.slotX) - 1;
    } else {
      return max(other.slotX, person.slotX) + 1;
    }
  }

  void _linkNewParentToSharedChildren({
    required int newParentId,
    required Kind newParentKind,
    required int otherParentId,
  }) {
    final otherParent = getNode(otherParentId);
    final newGender = newParentKind.gender;

    for (final childId in otherParent.children) {
      final child = getNode(childId);

      if (child.parents.contains(newParentId)) continue;

      final (motherId, fatherId) = parentPairForPerson(childId);
      if (newGender == Gender.female && motherId != null) continue;
      if (newGender == Gender.male && fatherId != null) continue;

      linkParentChild(parentId: newParentId, childId: childId, notify: false);
    }
  }

  // -------------------------------------------------------------------
  // ✅ Anti-overlap + Anti-drift stabilization (slot-based, stable)
  // -------------------------------------------------------------------

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

  /// ✅ NEW: Delete a member and remove all related links.
  void deleteNode(int id) {
    if (!_nodes.containsKey(id)) return;

    final node = getNode(id);

    for (final pid in node.parents.toList()) {
      final p = _nodes[pid];
      if (p != null) p.children.remove(id);
    }

    for (final cid in node.children.toList()) {
      final c = _nodes[cid];
      if (c != null) c.parents.remove(id);
    }

    for (final sid in node.spouses.toList()) {
      final s = _nodes[sid];
      if (s != null) s.spouses.remove(id);
    }

    _nodes.remove(id);

    if (lastAddedId == id) {
      lastAddedId = _nodes.isEmpty ? null : _nodes.keys.reduce(max);
    }

    _stabilizeLayout();
    notifyListeners();
  }

  FamilyNode addRoot({
    required String name,
    required Kind kind,
  }) {
    final root = createNode(
      name: name,
      kind: kind,
      levelY: 0,
      slotX: 0,
    );
    _stabilizeLayout();
    notifyListeners();
    return root;
  }

  void _backfillSpouseAsCoParent({
    required int personId,
    required int spouseId,
  }) {
    final person = getNode(personId);
    final spouse = getNode(spouseId);

    for (final childId in person.children) {
      final (motherId, fatherId) = parentPairForPerson(childId);

      if (spouse.gender == Gender.female && motherId == null) {
        linkParentChild(parentId: spouseId, childId: childId, notify: false);
      } else if (spouse.gender == Gender.male && fatherId == null) {
        linkParentChild(parentId: spouseId, childId: childId, notify: false);
      }
    }

    for (final childId in spouse.children) {
      final (motherId, fatherId) = parentPairForPerson(childId);

      if (person.gender == Gender.female && motherId == null) {
        linkParentChild(parentId: personId, childId: childId, notify: false);
      } else if (person.gender == Gender.male && fatherId == null) {
        linkParentChild(parentId: personId, childId: childId, notify: false);
      }
    }
  }

  FamilyNode? addSpouse({
    required int personId,
    required Kind spouseKind,
    required String name,
  }) {
    final person = getNode(personId);

    if (person.spouses.isNotEmpty) return null;
    if (spouseKind.gender == person.gender) return null;

    final preferLeft = spouseKind.gender == Gender.female;
    final anchor = person.slotX + (preferLeft ? -1 : 1);

    final slot = _nearestFreeSlotAtLevel(
      levelY: person.levelY,
      anchorSlot: anchor,
      preferLeft: preferLeft,
    );

    final spouse = createNode(
      name: name,
      kind: spouseKind,
      levelY: person.levelY,
      slotX: slot,
    );

    linkSpouses(aId: personId, bId: spouse.id, notify: false);
    _backfillSpouseAsCoParent(personId: personId, spouseId: spouse.id);

    _stabilizeLayout();
    notifyListeners();
    return spouse;
  }

  FamilyNode? addParent({
    required int personId,
    required Kind parentKind,
    required String name,
  }) {
    if (parentKind != Kind.mother && parentKind != Kind.father) return null;

    final person = getNode(personId);

    if (person.parents.length >= 2) return null;

    final (motherId, fatherId) = parentPairForPerson(personId);
    if (parentKind == Kind.mother && motherId != null) return null;
    if (parentKind == Kind.father && fatherId != null) return null;

    final otherParentId = parentKind == Kind.mother ? fatherId : motherId;

    final parent = createNode(
      name: name,
      kind: parentKind,
      levelY: person.levelY - 1,
      slotX: _newParentSlot(
        personId: personId,
        parentKind: parentKind,
        existingOtherParentId: otherParentId,
      ),
    );

    linkParentChild(parentId: parent.id, childId: personId, notify: false);

    if (otherParentId != null) {
      _linkNewParentToSharedChildren(
        newParentId: parent.id,
        newParentKind: parentKind,
        otherParentId: otherParentId,
      );
    }

    _stabilizeLayout();
    notifyListeners();
    return parent;
  }

  FamilyNode addChild({
    required int fromNodeId,
    required String name,
    required Kind childKind,
  }) {
    if (childKind != Kind.son && childKind != Kind.daughter) {
      throw ArgumentError('childKind must be Kind.son or Kind.daughter');
    }

    final from = getNode(fromNodeId);
    final slot = _nextChildSlotSmart(fromNodeId);

    final child = createNode(
      name: name,
      kind: childKind,
      levelY: from.levelY + 1,
      slotX: slot,
    );

    linkParentChild(parentId: from.id, childId: child.id, notify: false);

    final coparentId = _findCoParentPreferSpouse(fromNodeId);
    if (coparentId != null) {
      linkParentChild(parentId: coparentId, childId: child.id, notify: false);
    }

    _stabilizeLayout();
    notifyListeners();
    return child;
  }

  void addManualOffset(int nodeId, Offset delta) {
    getNode(nodeId).manualOffset += delta;
    notifyListeners();
  }

  void clearAll() {
    _nodes.clear();
    _nextId = 1;
    lastAddedId = null;
    notifyListeners();
  }

  // -------------------------------------------------------------------
  // ✅ Connect EXISTING tiles by drag-to-connect (ports)
  // -------------------------------------------------------------------

  bool tryLinkExistingParent({required int parentId, required int childId}) {
    if (!_nodes.containsKey(parentId) || !_nodes.containsKey(childId)) {
      return false;
    }
    if (parentId == childId) return false;

    final parent = getNode(parentId);
    final child = getNode(childId);

    if (parent.kind != Kind.mother && parent.kind != Kind.father) return false;
    if (child.parents.length >= 2) return false;

    final (motherId, fatherId) = parentPairForPerson(childId);

    if (parent.gender == Gender.female && motherId != null) return false;
    if (parent.gender == Gender.male && fatherId != null) return false;

    linkParentChild(parentId: parentId, childId: childId, notify: true);
    _stabilizeLayout();
    notifyListeners();
    return true;
  }

  bool tryLinkExistingChild({required int parentId, required int childId}) {
    if (!_nodes.containsKey(parentId) || !_nodes.containsKey(childId)) {
      return false;
    }
    if (parentId == childId) return false;

    final parent = getNode(parentId);
    final child = getNode(childId);

    if (child.kind != Kind.son && child.kind != Kind.daughter) return false;
    if (child.parents.length >= 2) return false;

    final (motherId, fatherId) = parentPairForPerson(childId);

    if (parent.gender == Gender.female && motherId != null) return false;
    if (parent.gender == Gender.male && fatherId != null) return false;

    linkParentChild(parentId: parentId, childId: childId, notify: true);

    final sp = spouseOf(parentId);
    if (sp != null) {
      _backfillSpouseAsCoParent(personId: parentId, spouseId: sp);
    }

    _stabilizeLayout();
    notifyListeners();
    return true;
  }

  bool tryLinkExistingSpouses({required int aId, required int bId}) {
    if (!_nodes.containsKey(aId) || !_nodes.containsKey(bId)) return false;
    if (aId == bId) return false;

    final a = getNode(aId);
    final b = getNode(bId);

    if (a.spouses.isNotEmpty || b.spouses.isNotEmpty) return false;
    if (a.gender == b.gender) return false;

    if (hasCoParentViaChildren(aId) || hasCoParentViaChildren(bId)) return false;

    linkSpouses(aId: aId, bId: bId, notify: false);

    // ✅ Backfill BOTH ways
    _backfillSpouseAsCoParent(personId: aId, spouseId: bId);
    _backfillSpouseAsCoParent(personId: bId, spouseId: aId);

    _stabilizeLayout();
    notifyListeners();
    return true;
  }
}

class FamilyTreeLayout {
  FamilyTreeLayout({
    required this.store,
    required this.cardSize,
    required this.hGap,
    required this.vGap,
  });

  final FamilyTreeStore store;
  final Size cardSize;
  final double hGap;
  final double vGap;

  Map<int, Offset> compute() {
    final nodes = store.nodes;
    if (nodes.isEmpty) return {};

    final pos = <int, Offset>{};
    final xStep = cardSize.width + hGap;
    final yStep = cardSize.height + vGap;

    for (final n in nodes.values) {
      pos[n.id] = Offset(n.slotX * xStep, n.levelY * yStep);
    }

    const double pad = 400;
    double minX = double.infinity, minY = double.infinity;
    for (final p in pos.values) {
      minX = min(minX, p.dx);
      minY = min(minY, p.dy);
    }

    final shiftX = (minX < pad) ? (pad - minX) : 0.0;
    final shiftY = (minY < pad) ? (pad - minY) : 0.0;

    if (shiftX != 0 || shiftY != 0) {
      for (final id in pos.keys) {
        pos[id] = pos[id]! + Offset(shiftX, shiftY);
      }
    }

    for (final n in nodes.values) {
      pos[n.id] = pos[n.id]! + n.manualOffset;
    }

    return pos;
  }
}

class FamilyTreePage extends StatefulWidget {
  const FamilyTreePage({super.key});

  @override
  State<FamilyTreePage> createState() => _FamilyTreePageState();
}

/// ✅ Ports meaning:
/// - Top    => Parents
/// - Bottom => Children
/// - Sides  => Spouse
enum _LinkPort { parentTop, childBottom, spouseLeft, spouseRight }

class _FamilyTreePageState extends State<FamilyTreePage> {
  late final FamilyTreeStore store;

  static const Size cardSize = Size(170, 72);
  static const double hGap = 40;
  static const double vGap = 70;

  static const double virtualSize = 100000;

  final TransformationController _tc = TransformationController();
  bool _didInitialCenter = false;

  static const double _minZoom = 0.3;
  static const double _maxZoom = 3.0;

  double _zoomValue = 1.0;
  bool _syncingFromController = false;

  // ✅ Drag-to-connect state
  bool _isLinking = false;
  int? _linkFromNodeId;
  _LinkPort? _linkPort;
  Offset _linkStartScene = Offset.zero;
  Offset _linkCurrentViewport = Offset.zero;

  // ✅ Snap state
  int? _hoverTargetId;
  Offset _snappedEndViewport = Offset.zero;

  static const double _snapRadius = 70.0;

  // ✅ Tile hover id (desktop/web)
  int? _hoveredNodeId;

  // ✅ Keep last computed layout (scene coords)
  Map<int, Offset> _lastLayoutScene = {};

  @override
  void initState() {
    super.initState();
    store = FamilyTreeStore();

    _tc.addListener(() {
      if (!mounted) return;
      if (_syncingFromController) return;

      final s = _tc.value.getMaxScaleOnAxis().clamp(_minZoom, _maxZoom);
      if ((s - _zoomValue).abs() > 0.005) {
        setState(() => _zoomValue = s);
      }
    });
  }

  @override
  void dispose() {
    store.dispose();
    _tc.dispose();
    super.dispose();
  }

  void _setZoom(double newZoom) {
    final screenSize = MediaQuery.of(context).size;
    final viewportCenter = Offset(screenSize.width / 2, screenSize.height / 2);
    final sceneCenter = _tc.toScene(viewportCenter);

    _syncingFromController = true;
    _tc.value = Matrix4.identity()
      ..translate(viewportCenter.dx, viewportCenter.dy)
      ..scale(newZoom)
      ..translate(-sceneCenter.dx, -sceneCenter.dy);
    _syncingFromController = false;

    setState(() => _zoomValue = newZoom);
  }

  Offset _sceneToViewport(Offset scenePoint) {
    final o = MatrixUtils.transformPoint(_tc.value, scenePoint);
    return Offset(o.dx, o.dy);
  }

  Offset _globalToViewport(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;
    return box.globalToLocal(global);
  }

  // ---------------- SNAP / MAGNET HELPERS ----------------

  double _distancePointToRect(Offset p, Rect r) {
    final dx = (p.dx < r.left)
        ? (r.left - p.dx)
        : (p.dx > r.right)
            ? (p.dx - r.right)
            : 0.0;

    final dy = (p.dy < r.top)
        ? (r.top - p.dy)
        : (p.dy > r.bottom)
            ? (p.dy - r.bottom)
            : 0.0;

    return sqrt(dx * dx + dy * dy);
  }

  Offset _nearestPointOnRect(Offset p, Rect r) {
    final x = p.dx.clamp(r.left, r.right);
    final y = p.dy.clamp(r.top, r.bottom);
    return Offset(x, y);
  }

  int? _nearestNodeInViewport(Offset viewportPoint, {int? excludeId}) {
    int? bestId;
    double bestDist = double.infinity;

    for (final e in _lastLayoutScene.entries) {
      if (excludeId != null && e.key == excludeId) continue;

      final rectScene = Rect.fromLTWH(
        e.value.dx,
        e.value.dy,
        cardSize.width,
        cardSize.height,
      );

      final tl = _sceneToViewport(rectScene.topLeft);
      final br = _sceneToViewport(rectScene.bottomRight);
      final rectVp = Rect.fromPoints(tl, br);

      final d = _distancePointToRect(viewportPoint, rectVp);
      if (d < bestDist) {
        bestDist = d;
        bestId = e.key;
      }
    }

    if (bestId == null) return null;
    return (bestDist <= _snapRadius) ? bestId : null;
  }

  // ---------------- LINKING (FAST + SNAP) ----------------

  void _startLink({
    required int fromNodeId,
    required _LinkPort port,
    required Offset startScene,
    required Offset startViewport,
  }) {
    setState(() {
      _isLinking = true;
      _linkFromNodeId = fromNodeId;
      _linkPort = port;
      _linkStartScene = startScene;
      _linkCurrentViewport = startViewport;
      _hoverTargetId = null;
      _snappedEndViewport = startViewport;

      _hoveredNodeId = fromNodeId;
    });

    _updateLink(startViewport);
  }

  void _updateLink(Offset viewportPoint) {
    if (!_isLinking) return;

    final fromId = _linkFromNodeId;
    if (fromId == null) return;

    final targetId = _nearestNodeInViewport(viewportPoint, excludeId: fromId);

    Offset snapped = viewportPoint;

    if (targetId != null) {
      final topLeftScene = _lastLayoutScene[targetId]!;
      final rectScene = Rect.fromLTWH(
        topLeftScene.dx,
        topLeftScene.dy,
        cardSize.width,
        cardSize.height,
      );

      final tl = _sceneToViewport(rectScene.topLeft);
      final br = _sceneToViewport(rectScene.bottomRight);
      final rectVp = Rect.fromPoints(tl, br);

      snapped = _nearestPointOnRect(viewportPoint, rectVp);
    }

    setState(() {
      _linkCurrentViewport = viewportPoint;
      _hoverTargetId = targetId;
      _snappedEndViewport = snapped;
    });
  }

  void _endLink(Offset viewportPoint) {
    if (!_isLinking) return;

    final fromId = _linkFromNodeId;
    final port = _linkPort;
    final targetId = _hoverTargetId;

    setState(() {
      _isLinking = false;
      _linkFromNodeId = null;
      _linkPort = null;
      _hoverTargetId = null;
    });

    if (fromId == null || port == null) return;
    if (targetId == null) return;

    bool ok = false;

    switch (port) {
      case _LinkPort.parentTop:
        ok = store.tryLinkExistingParent(parentId: targetId, childId: fromId);
        break;
      case _LinkPort.childBottom:
        ok = store.tryLinkExistingChild(parentId: fromId, childId: targetId);
        break;
      case _LinkPort.spouseLeft:
      case _LinkPort.spouseRight:
        ok = store.tryLinkExistingSpouses(aId: fromId, bId: targetId);
        break;
    }

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot connect these tiles (rules blocked).'),
        ),
      );
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('This will clear the current family tree.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    store.clearAll();
    _didInitialCenter = false;
    _syncingFromController = true;
    _tc.value = Matrix4.identity();
    _syncingFromController = false;
    setState(() => _zoomValue = 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final layoutRaw = FamilyTreeLayout(
          store: store,
          cardSize: cardSize,
          hGap: hGap,
          vGap: vGap,
        ).compute();

        final origin = const Offset(virtualSize / 2, virtualSize / 2);
        final layout = <int, Offset>{
          for (final e in layoutRaw.entries) e.key: e.value + origin,
        };

        _lastLayoutScene = layout;

        final bounds = _computeBounds(layout);

        if (!_didInitialCenter && layout.isNotEmpty) {
          _didInitialCenter = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _fitToScreen(bounds);
          });
        }

        final canvasSize = const Size(virtualSize, virtualSize);
        final isEmpty = store.nodes.isEmpty;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Family Tree Builder'),
            actions: [
              IconButton(
                tooltip: 'Log out',
                onPressed: _logout,
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          body: Stack(
            children: [
              InteractiveViewer(
                transformationController: _tc,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(1000000),
                clipBehavior: Clip.none,
                minScale: _minZoom,
                maxScale: _maxZoom,
                child: SizedBox(
                  width: canvasSize.width,
                  height: canvasSize.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (!isEmpty)
                        CustomPaint(
                          size: canvasSize,
                          painter: _ConnectorPainter(
                            store: store,
                            positions: layout,
                            cardSize: cardSize,
                          ),
                        ),
                      for (final entry in layout.entries)
                        _AnimatedNode(
                          node: store.getNode(entry.key),
                          topLeft: entry.value,
                          size: cardSize,
                          isHovered: entry.key == _hoveredNodeId ||
                              (_isLinking && _linkFromNodeId == entry.key),
                          dragEnabled:
                              !_isLinking, // ✅ FIX: prevent tile drag while linking
                          onHoverChanged: (hovering) {
                            if (!mounted) return;
                            setState(() {
                              if (hovering) {
                                _hoveredNodeId = entry.key;
                              } else if (_hoveredNodeId == entry.key) {
                                _hoveredNodeId = null;
                              }
                            });
                          },
                          onTap: () => _openNodeActions(context, entry.key),
                          onDragDelta: (delta) =>
                              store.addManualOffset(entry.key, delta),
                          onStartPortDrag: (port, globalStart) {
                            final topLeft = layout[entry.key]!;
                            final startScene = switch (port) {
                              _LinkPort.parentTop => Offset(
                                  topLeft.dx + cardSize.width / 2, topLeft.dy),
                              _LinkPort.childBottom => Offset(
                                  topLeft.dx + cardSize.width / 2,
                                  topLeft.dy + cardSize.height),
                              _LinkPort.spouseLeft => Offset(topLeft.dx,
                                  topLeft.dy + cardSize.height / 2),
                              _LinkPort.spouseRight => Offset(
                                  topLeft.dx + cardSize.width,
                                  topLeft.dy + cardSize.height / 2),
                            };

                            _startLink(
                              fromNodeId: entry.key,
                              port: port,
                              startScene: startScene,
                              startViewport: _globalToViewport(globalStart),
                            );
                          },
                          onUpdatePortDrag: (g) =>
                              _updateLink(_globalToViewport(g)),
                          onEndPortDrag: (g) => _endLink(_globalToViewport(g)),
                        ),
                    ],
                  ),
                ),
              ),

              if (_isLinking)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _LinkPreviewPainter(
                        start: _sceneToViewport(_linkStartScene),
                        end: (_hoverTargetId != null)
                            ? _snappedEndViewport
                            : _linkCurrentViewport,
                      ),
                    ),
                  ),
                ),

              if (isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(18),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.account_tree, size: 42),
                            const SizedBox(height: 10),
                            const Text(
                              'Start your family tree',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Add your first member to begin.',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: () => _addFirstMemberFlow(context),
                              icon: const Icon(Icons.person_add),
                              label: const Text('Add First Member'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              if (!isEmpty)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Material(
                    elevation: 2,
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: SizedBox(
                        width: 240,
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Zoom out',
                              icon: const Icon(Icons.remove, size: 18),
                              onPressed: () {
                                final next = (_zoomValue / 1.15)
                                    .clamp(_minZoom, _maxZoom);
                                _setZoom(next);
                              },
                            ),
                            Expanded(
                              child: Slider(
                                value: _zoomValue.clamp(_minZoom, _maxZoom),
                                min: _minZoom,
                                max: _maxZoom,
                                onChanged: (v) => _setZoom(v),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Zoom in',
                              icon: const Icon(Icons.add, size: 18),
                              onPressed: () {
                                final next = (_zoomValue * 1.15)
                                    .clamp(_minZoom, _maxZoom);
                                _setZoom(next);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Rect _computeBounds(Map<int, Offset> pos) {
    if (pos.isEmpty) return const Rect.fromLTWH(0, 0, 800, 600);

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = -double.infinity;
    double maxY = -double.infinity;

    for (final p in pos.values) {
      minX = min(minX, p.dx);
      minY = min(minY, p.dy);
      maxX = max(maxX, p.dx + cardSize.width);
      maxY = max(maxY, p.dy + cardSize.height);
    }

    const double margin = 300;
    return Rect.fromLTRB(
      minX - margin,
      minY - margin,
      maxX + margin,
      maxY + margin,
    );
  }

  void _fitToScreen(Rect bounds) {
    final screenSize = MediaQuery.of(context).size;
    final scale =
        min(screenSize.width / bounds.width, screenSize.height / bounds.height) *
            0.8;

    _syncingFromController = true;
    _tc.value = Matrix4.identity()
      ..translate(screenSize.width / 2, screenSize.height / 2)
      ..scale(scale)
      ..translate(-bounds.center.dx, -bounds.center.dy);
    _syncingFromController = false;

    final clamped = scale.clamp(_minZoom, _maxZoom);
    setState(() => _zoomValue = clamped);
  }

  Future<void> _addFirstMemberFlow(BuildContext context) async {
    final chosen = await showModalBottomSheet<Kind>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 6),
              const Text('Select Member Type',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              for (final k
                  in const [Kind.mother, Kind.father, Kind.son, Kind.daughter])
                ListTile(
                  leading: Icon(k.icon),
                  title: Text(k.label),
                  onTap: () => Navigator.pop(ctx, k),
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (chosen == null) return;

    final name = await _promptText(
      context,
      title: '${chosen.label} Name',
      initial: 'New ${chosen.label}',
    );
    if (name == null) return;

    store.addRoot(name: name, kind: chosen);
  }

  Future<void> _openNodeActions(BuildContext context, int nodeId) async {
    final node = store.getNode(nodeId);

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(node.kind.icon),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        node.name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Edit Name'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final name = await _promptText(context,
                        title: 'Edit Name', initial: node.name);
                    if (name != null) store.renameNode(nodeId, name);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.favorite),
                  title: const Text('Add Spouse'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _addSpouseFlow(context, personId: nodeId);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.arrow_upward),
                  title: const Text('Add Parent'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _addParentFlow(context, personId: nodeId);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.arrow_downward),
                  title: const Text('Add Child'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _addChildFlow(context, fromNodeId: nodeId);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline,
                      color: Colors.redAccent),
                  title: const Text('Delete'),
                  onTap: () async {
                    Navigator.pop(ctx);

                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        title: const Text('Delete member?'),
                        content: const Text(
                          'This will remove the member and all related links (parents, children, spouse).',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dctx, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.redAccent),
                            onPressed: () => Navigator.pop(dctx, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );

                    if (ok != true) return;
                    store.deleteNode(nodeId);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _addSpouseFlow(BuildContext context,
      {required int personId}) async {
    final person = store.getNode(personId);

    if (person.spouses.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${person.name} already has a spouse.')),
      );
      return;
    }

    if (store.hasCoParentViaChildren(personId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${person.name} already has a co-parent.')),
      );
      return;
    }

    final options = store.allowedSpouseKindsFor(person.kind);

    final chosen = await showModalBottomSheet<Kind>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 6),
              const Text('Select Spouse Type',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              for (final k in options)
                ListTile(
                  leading: Icon(k.icon),
                  title: Text(k.label),
                  onTap: () => Navigator.pop(ctx, k),
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (chosen == null) return;

    final name = await _promptText(
      context,
      title: '${chosen.label} Name',
      initial: 'New ${chosen.label}',
    );
    if (name == null) return;

    final added =
        store.addSpouse(personId: personId, spouseKind: chosen, name: name);

    if (added == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not add spouse.')),
      );
    }
  }

  Future<void> _addParentFlow(BuildContext context,
      {required int personId}) async {
    final person = store.getNode(personId);

    if (person.parents.length >= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${person.name} already has 2 parents.')),
      );
      return;
    }

    final (motherId, fatherId) = store.parentPairForPerson(personId);

    final options = <Kind>[
      if (motherId == null) Kind.mother,
      if (fatherId == null) Kind.father,
    ];

    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${person.name} already has a Mother and a Father.'),
        ),
      );
      return;
    }

    final chosen = await showModalBottomSheet<Kind>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 6),
              const Text('Select Missing Parent',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              for (final k in options)
                ListTile(
                  leading: Icon(k.icon),
                  title: Text(k.label),
                  onTap: () => Navigator.pop(ctx, k),
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (chosen == null) return;

    final name = await _promptText(
      context,
      title: '${chosen.label} Name',
      initial: 'New ${chosen.label}',
    );
    if (name == null) return;

    final added =
        store.addParent(personId: personId, parentKind: chosen, name: name);
    if (added == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add ${chosen.label} (blocked).')),
      );
    }
  }

  Future<void> _addChildFlow(BuildContext context,
      {required int fromNodeId}) async {
    final chosen = await showModalBottomSheet<Kind>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 6),
              const Text('Select Child',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              for (final k in const [Kind.son, Kind.daughter])
                ListTile(
                  leading: Icon(k.icon),
                  title: Text(k.label),
                  onTap: () => Navigator.pop(ctx, k),
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (chosen == null) return;

    final name = await _promptText(context,
        title: '${chosen.label} Name', initial: 'New ${chosen.label}');
    if (name == null) return;

    store.addChild(fromNodeId: fromNodeId, name: name, childKind: chosen);
  }

  Future<String?> _promptText(
    BuildContext context, {
    required String title,
    required String initial,
  }) async {
    final c = TextEditingController(text: initial);

    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Enter name',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => Navigator.pop(ctx, c.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}

class _AnimatedNode extends StatefulWidget {
  const _AnimatedNode({
    required this.node,
    required this.topLeft,
    required this.size,
    required this.onTap,
    required this.onDragDelta,
    required this.onStartPortDrag,
    required this.onUpdatePortDrag,
    required this.onEndPortDrag,
    required this.isHovered,
    required this.onHoverChanged,
    required this.dragEnabled, // ✅ NEW
  });

  final FamilyNode node;
  final Offset topLeft;
  final Size size;
  final VoidCallback onTap;
  final ValueChanged<Offset> onDragDelta;

  final void Function(_LinkPort port, Offset globalStart) onStartPortDrag;
  final void Function(Offset globalPos) onUpdatePortDrag;
  final void Function(Offset globalPos) onEndPortDrag;

  final bool isHovered;
  final ValueChanged<bool> onHoverChanged;

  final bool dragEnabled; // ✅ NEW

  @override
  State<_AnimatedNode> createState() => _AnimatedNodeState();
}

class _AnimatedNodeState extends State<_AnimatedNode> {
  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      left: widget.topLeft.dx,
      top: widget.topLeft.dy,
      width: widget.size.width,
      height: widget.size.height,
      child: MouseRegion(
        onEnter: (_) => widget.onHoverChanged(true),
        onExit: (_) => widget.onHoverChanged(false),
        child: GestureDetector(
          onTap: widget.onTap,
          // ✅ FIX: don't drag the tile while you are linking
          onPanUpdate:
              widget.dragEnabled ? (d) => widget.onDragDelta(d.delta) : null,
          child: _MemberCard(
            node: widget.node,
            showPorts: widget.isHovered,
            onStartPortDrag: widget.onStartPortDrag,
            onUpdatePortDrag: widget.onUpdatePortDrag,
            onEndPortDrag: widget.onEndPortDrag,
          ),
        ),
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.node,
    required this.showPorts,
    required this.onStartPortDrag,
    required this.onUpdatePortDrag,
    required this.onEndPortDrag,
  });

  final FamilyNode node;
  final bool showPorts;

  final void Function(_LinkPort port, Offset globalStart) onStartPortDrag;
  final void Function(Offset globalPos) onUpdatePortDrag;
  final void Function(Offset globalPos) onEndPortDrag;

  bool get _showParentPort => showPorts && node.parents.length < 2;
  bool get _showChildPort => showPorts;
  bool get _showSpousePorts => showPorts && node.spouses.isEmpty;

  @override
  Widget build(BuildContext context) {
    final tone = switch (node.gender) {
      Gender.female => const Color(0xFFEAF3FF),
      Gender.male => const Color(0xFFEFF8F1),
    };

    return Material(
      elevation: 2,
      shadowColor: Colors.black12,
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: tone,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(node.kind.icon, color: Colors.black87),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          node.kind.label,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_showParentPort)
            Positioned(
              top: -10,
              left: (170 / 2) - 10,
              child: _PlusPort(
                tooltip: 'Connect Parent',
                onStart: (g) => onStartPortDrag(_LinkPort.parentTop, g),
                onUpdate: onUpdatePortDrag,
                onEnd: onEndPortDrag,
              ),
            ),

          if (_showChildPort)
            Positioned(
              bottom: -10,
              left: (170 / 2) - 10,
              child: _PlusPort(
                tooltip: 'Connect Child',
                onStart: (g) => onStartPortDrag(_LinkPort.childBottom, g),
                onUpdate: onUpdatePortDrag,
                onEnd: onEndPortDrag,
              ),
            ),

          if (_showSpousePorts) ...[
            Positioned(
              left: -10,
              top: (72 / 2) - 10,
              child: _PlusPort(
                tooltip: 'Connect Spouse',
                onStart: (g) => onStartPortDrag(_LinkPort.spouseLeft, g),
                onUpdate: onUpdatePortDrag,
                onEnd: onEndPortDrag,
              ),
            ),
            Positioned(
              right: -10,
              top: (72 / 2) - 10,
              child: _PlusPort(
                tooltip: 'Connect Spouse',
                onStart: (g) => onStartPortDrag(_LinkPort.spouseRight, g),
                onUpdate: onUpdatePortDrag,
                onEnd: onEndPortDrag,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// ✅ FIXED: Clicking the + no longer flashes the connector.
/// Only starts linking once the pointer MOVES a few pixels.
class _PlusPort extends StatefulWidget {
  const _PlusPort({
    required this.tooltip,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final String tooltip;
  final void Function(Offset globalPos) onStart;
  final void Function(Offset globalPos) onUpdate;
  final void Function(Offset globalPos) onEnd;

  @override
  State<_PlusPort> createState() => _PlusPortState();
}

class _PlusPortState extends State<_PlusPort> {
  static const double _dragStartThreshold = 6.0;

  Offset? _downGlobal;
  Offset? _lastGlobal;
  bool _started = false;

  void _reset() {
    _downGlobal = null;
    _lastGlobal = null;
    _started = false;
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) {
          _downGlobal = e.position;
          _lastGlobal = e.position;
          _started = false;
        },
        onPointerMove: (e) {
          if (_downGlobal == null) return;
          _lastGlobal = e.position;

          final dist = (e.position - _downGlobal!).distance;

          if (!_started && dist >= _dragStartThreshold) {
            _started = true;
            widget.onStart(_downGlobal!);
          }

          if (_started) {
            widget.onUpdate(e.position);
          }
        },
        onPointerUp: (_) {
          if (_started) {
            widget.onEnd(_lastGlobal ?? Offset.zero);
          }
          _reset();
        },
        onPointerCancel: (_) {
          if (_started) {
            widget.onEnd(_lastGlobal ?? Offset.zero);
          }
          _reset();
        },
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFB9C0CC), width: 1),
            boxShadow: const [
              BoxShadow(
                blurRadius: 6,
                offset: Offset(0, 2),
                color: Colors.black12,
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.add, size: 14, color: Color(0xFF6E7685)),
          ),
        ),
      ),
    );
  }
}

class _LinkPreviewPainter extends CustomPainter {
  _LinkPreviewPainter({required this.start, required this.end});
  final Offset start;
  final Offset end;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF6E7685)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    final ctrl = Offset(mid.dx, min(start.dy, end.dy) - 40);

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);

    canvas.drawPath(path, paint);
    canvas.drawCircle(end, 4.5, Paint()..color = const Color(0xFF6E7685));
  }

  @override
  bool shouldRepaint(covariant _LinkPreviewPainter oldDelegate) {
    return oldDelegate.start != start || oldDelegate.end != end;
  }
}

class _ConnectorPainter extends CustomPainter {
  _ConnectorPainter({
    required this.store,
    required this.positions,
    required this.cardSize,
  });

  final FamilyTreeStore store;
  final Map<int, Offset> positions;
  final Size cardSize;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFB9C0CC)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final spousePaint = Paint()
      ..color = const Color(0xFFB9C0CC)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    Offset topCenterOf(int nodeId) {
      final p = positions[nodeId]!;
      return Offset(p.dx + cardSize.width / 2, p.dy);
    }

    Offset bottomCenterOf(int nodeId) {
      final p = positions[nodeId]!;
      return Offset(p.dx + cardSize.width / 2, p.dy + cardSize.height);
    }

    final Map<String, _Group> groups = {};
    final Set<String> couplesWithChildren = {};

    for (final child in store.nodes.values) {
      if (child.parents.isEmpty) continue;
      if (!positions.containsKey(child.id)) continue;

      final (motherId, fatherId) = store.parentPairForPerson(child.id);
      final parentIds = <int>[
        if (motherId != null) motherId,
        if (fatherId != null) fatherId,
      ]..sort();

      if (parentIds.isEmpty) continue;

      bool parentsHavePos = true;
      for (final pid in parentIds) {
        if (!positions.containsKey(pid)) parentsHavePos = false;
      }
      if (!parentsHavePos) continue;

      final key = parentIds.join('_');
      couplesWithChildren.add(key);

      groups.putIfAbsent(key, () => _Group(parentIds: parentIds));
      groups[key]!.childIds.add(child.id);
    }

    final drawnSpousePairs = <String>{};

    for (final a in store.nodes.values) {
      if (!positions.containsKey(a.id)) continue;

      for (final bId in a.spouses) {
        if (!positions.containsKey(bId)) continue;

        final lo = min(a.id, bId);
        final hi = max(a.id, bId);

        final pairKey = '${lo}_$hi';
        if (drawnSpousePairs.contains(pairKey)) continue;
        drawnSpousePairs.add(pairKey);

        if (couplesWithChildren.contains(pairKey)) continue;

        final p1 = bottomCenterOf(a.id);
        final p2 = bottomCenterOf(bId);

        const double coupleGap = 18;
        final coupleY = max(p1.dy, p2.dy) + coupleGap;

        final leftX = min(p1.dx, p2.dx);
        final rightX = max(p1.dx, p2.dx);
        final midX = (p1.dx + p2.dx) / 2;

        canvas.drawLine(p1, Offset(p1.dx, coupleY), spousePaint);
        canvas.drawLine(p2, Offset(p2.dx, coupleY), spousePaint);
        canvas.drawLine(
          Offset(leftX, coupleY),
          Offset(rightX, coupleY),
          spousePaint,
        );

        final heart = TextPainter(
          text: const TextSpan(
            text: '❤',
            style: TextStyle(fontSize: 12, color: Color(0xFFB9C0CC)),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        heart.paint(
          canvas,
          Offset(midX - heart.width / 2, coupleY - heart.height / 2),
        );
      }
    }

    for (final g in groups.values) {
      final childTops = <Offset>[];
      for (final cid in g.childIds) {
        if (!positions.containsKey(cid)) continue;
        childTops.add(topCenterOf(cid));
      }
      if (childTops.isEmpty) continue;

      final parentBottoms = <Offset>[];
      for (final pid in g.parentIds) {
        if (!positions.containsKey(pid)) continue;
        parentBottoms.add(bottomCenterOf(pid));
      }
      if (parentBottoms.isEmpty) continue;

      final parentsBottomY = parentBottoms.map((p) => p.dy).reduce(max);
      final minChildTopY = childTops.map((e) => e.dy).reduce(min);
      final busY = (parentsBottomY + minChildTopY) / 2;

      double minX = childTops.map((e) => e.dx).reduce(min);
      double maxX = childTops.map((e) => e.dx).reduce(max);

      final isCouple = parentBottoms.length >= 2;
      final anchorX = isCouple
          ? (parentBottoms[0].dx + parentBottoms[1].dx) / 2
          : parentBottoms.first.dx;

      minX = min(minX, anchorX);
      maxX = max(maxX, anchorX);

      if (childTops.length == 1) {
        final childTop = childTops.first;

        if (!isCouple) {
          final pb = parentBottoms.first;
          final midY = (pb.dy + childTop.dy) / 2;
          canvas.drawLine(pb, Offset(pb.dx, midY), paint);
          canvas.drawLine(Offset(pb.dx, midY), Offset(childTop.dx, midY), paint);
          canvas.drawLine(Offset(childTop.dx, midY), childTop, paint);
        } else {
          final p1 = parentBottoms[0];
          final p2 = parentBottoms[1];
          final coupleY = p1.dy + (busY - p1.dy) * 0.35;
          final midX = (p1.dx + p2.dx) / 2;

          canvas.drawLine(p1, Offset(p1.dx, coupleY), paint);
          canvas.drawLine(p2, Offset(p2.dx, coupleY), paint);
          canvas.drawLine(
            Offset(min(p1.dx, p2.dx), coupleY),
            Offset(max(p1.dx, p2.dx), coupleY),
            paint,
          );

          final midY = (coupleY + childTop.dy) / 2;
          canvas.drawLine(Offset(midX, coupleY), Offset(midX, midY), paint);
          canvas.drawLine(Offset(midX, midY), Offset(childTop.dx, midY), paint);
          canvas.drawLine(Offset(childTop.dx, midY), childTop, paint);
        }
        continue;
      }

      if (!isCouple) {
        final pb = parentBottoms.first;
        canvas.drawLine(pb, Offset(pb.dx, busY), paint);
        canvas.drawLine(Offset(minX, busY), Offset(maxX, busY), paint);
      } else {
        final p1 = parentBottoms[0];
        final p2 = parentBottoms[1];

        final coupleY = p1.dy + (busY - p1.dy) * 0.35;
        final leftX = min(p1.dx, p2.dx);
        final rightX = max(p1.dx, p2.dx);
        final midX = (p1.dx + p2.dx) / 2;

        canvas.drawLine(p1, Offset(p1.dx, coupleY), paint);
        canvas.drawLine(p2, Offset(p2.dx, coupleY), paint);
        canvas.drawLine(Offset(leftX, coupleY), Offset(rightX, coupleY), paint);

        canvas.drawLine(Offset(midX, coupleY), Offset(midX, busY), paint);
        canvas.drawLine(Offset(minX, busY), Offset(maxX, busY), paint);
      }

      for (final ct in childTops) {
        canvas.drawLine(Offset(ct.dx, busY), ct, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectorPainter oldDelegate) {
    return oldDelegate.positions != positions ||
        oldDelegate.store != store ||
        oldDelegate.cardSize != cardSize;
  }
}

class _Group {
  _Group({required this.parentIds});
  final List<int> parentIds;
  final List<int> childIds = [];
}
