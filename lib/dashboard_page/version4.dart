import 'dart:math';
import 'package:flutter/material.dart';

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

  /// ✅ Persistent layout metadata (NO global recompute).
  /// levelY increases downward (parents above children can be negative)
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

  /// ✅ Track newest node so ONLY it "snaps" (others don't rearrange)
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
  void linkParentChild({required int parentId, required int childId}) {
    if (parentId == childId) return;
    if (!_nodes.containsKey(parentId) || !_nodes.containsKey(childId)) return;

    final parent = getNode(parentId);
    final child = getNode(childId);

    parent.children.add(childId);
    child.parents.add(parentId);

    notifyListeners();
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

  /// Finds a co-parent for `from` (based on any shared existing child).
  int? _findCoParent(int fromNodeId) {
    final from = getNode(fromNodeId);
    for (final existingChildId in from.children) {
      final existingChild = getNode(existingChildId);
      for (final pid in existingChild.parents) {
        if (pid != from.id) return pid;
      }
    }
    return null;
  }

  /// ✅ Next slot for a new child: append right (old nodes never shift).
  double _nextChildSlot(int parentId) {
    final parent = getNode(parentId);
    if (parent.children.isEmpty) return parent.slotX;

    double maxSlot = -double.infinity;
    for (final cid in parent.children) {
      maxSlot = max(maxSlot, getNode(cid).slotX);
    }
    return maxSlot + 1;
  }

  /// ✅ Slot for a new parent: align as a pair when other parent exists.
  double _newParentSlot({
    required int personId,
    required Kind parentKind, // mother/father only
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

  /// ✅ When adding the missing parent, auto-link them to the other parent's existing children
  /// that still lack THIS role slot (female/male).
  void _linkNewParentToSharedChildren({
    required int newParentId,
    required Kind newParentKind, // mother/father
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

      linkParentChild(parentId: newParentId, childId: childId);
    }
  }

  /// Adds a parent (mother/father) to ANY person.
  FamilyNode? addParent({
    required int personId,
    required Kind parentKind, // must be mother/father
    required String name,
  }) {
    if (parentKind != Kind.mother && parentKind != Kind.father) return null;

    final (motherId, fatherId) = parentPairForPerson(personId);
    if (parentKind == Kind.mother && motherId != null) return null;
    if (parentKind == Kind.father && fatherId != null) return null;

    final person = getNode(personId);
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

    // Link to the selected person
    linkParentChild(parentId: parent.id, childId: personId);

    // ✅ If this completes a couple, connect new parent to the other parent's existing children
    if (otherParentId != null) {
      _linkNewParentToSharedChildren(
        newParentId: parent.id,
        newParentKind: parentKind,
        otherParentId: otherParentId,
      );
      notifyListeners();
    }

    return parent;
  }

  /// Adds a child (son/daughter) from ANY node.
  /// Auto-links the new child to BOTH parents if a co-parent exists.
  FamilyNode addChild({
    required int fromNodeId,
    required String name,
    required Kind childKind, // son/daughter
  }) {
    if (childKind != Kind.son && childKind != Kind.daughter) {
      throw ArgumentError('childKind must be Kind.son or Kind.daughter');
    }

    final from = getNode(fromNodeId);

    final child = createNode(
      name: name,
      kind: childKind,
      levelY: from.levelY + 1,
      slotX: _nextChildSlot(fromNodeId),
    );

    linkParentChild(parentId: from.id, childId: child.id);

    final coparentId = _findCoParent(fromNodeId);
    if (coparentId != null) {
      linkParentChild(parentId: coparentId, childId: child.id);

      // Optional: center new child between parents (only affects the new child)
      final cp = getNode(coparentId);
      child.slotX = (from.slotX + cp.slotX) / 2;
      notifyListeners();
    }

    return child;
  }

  /// Nudges a node manually (used after dragging).
  void addManualOffset(int nodeId, Offset delta) {
    getNode(nodeId).manualOffset += delta;
    notifyListeners();
  }
}

/// ✅ Layout uses stored slotX + levelY.
/// ✅ Only newest node is allowed to "snap" away from overlaps.
/// ✅ Then we translate everything so no node has negative left/top (Stack can't show negatives).
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

    // 1) Base positions from stable slots.
    for (final n in nodes.values) {
      pos[n.id] = Offset(n.slotX * xStep, n.levelY * yStep);
    }

    // 2) Overlap avoidance per level (ONLY shift the newest node).
    final newest = store.lastAddedId;
    final byLevel = <int, List<int>>{};
    for (final n in nodes.values) {
      byLevel.putIfAbsent(n.levelY, () => []).add(n.id);
    }

    for (final entry in byLevel.entries) {
      final ids = entry.value
        ..sort((a, b) => pos[a]!.dx.compareTo(pos[b]!.dx));

      for (int i = 1; i < ids.length; i++) {
        final a = ids[i - 1];
        final b = ids[i];

        final pa = pos[a]!;
        final pb = pos[b]!;
        final minX = pa.dx + cardSize.width + hGap * 0.6;

        if (pb.dx < minX) {
          if (newest == b) {
            pos[b] = Offset(minX, pb.dy);
          } else if (newest == a) {
            pos[a] = Offset(pa.dx + (minX - pb.dx), pa.dy);
          }
        }
      }
    }

    // 3) Apply manual offsets (drag nudges).
    for (final n in nodes.values) {
      pos[n.id] = pos[n.id]! + n.manualOffset;
    }

    // 4) Translate so nothing is negative.
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

    return pos;
  }
}

class FamilyTreePage extends StatefulWidget {
  const FamilyTreePage({super.key});

  @override
  State<FamilyTreePage> createState() => _FamilyTreePageState();
}

class _FamilyTreePageState extends State<FamilyTreePage> {
  late final FamilyTreeStore store;

  static const Size cardSize = Size(170, 72);
  static const double hGap = 40;
  static const double vGap = 70;

  final TransformationController _tc = TransformationController();

  @override
  void initState() {
    super.initState();
    store = FamilyTreeStore();

    // ✅ Seed node MUST be Son or Daughter (gender always known)
    store.createNode(name: 'Alex', kind: Kind.son, levelY: 0, slotX: 0);
  }

  @override
  void dispose() {
    store.dispose();
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final layout = FamilyTreeLayout(
          store: store,
          cardSize: cardSize,
          hGap: hGap,
          vGap: vGap,
        ).compute();

        final bounds = _computeBounds(layout);

        const double horizontalPadding = 1000;
        const double verticalPadding = 1000;

        final canvasSize = Size(
          max(MediaQuery.of(context).size.width * 2,
              bounds.width + horizontalPadding),
          max(MediaQuery.of(context).size.height * 2,
              bounds.height + verticalPadding),
        );

        return Scaffold(
          appBar: AppBar(
            title: const Text('Family Tree Builder'),
            actions: [
              IconButton(
                tooltip: 'Reset view',
                onPressed: () => _tc.value = Matrix4.identity(),
                icon: const Icon(Icons.center_focus_strong),
              ),
              IconButton(
                tooltip: 'Fit to screen',
                onPressed: () => _fitToScreen(bounds),
                icon: const Icon(Icons.fit_screen),
              ),
            ],
          ),
          body: InteractiveViewer(
            transformationController: _tc,
            minScale: 0.05,
            maxScale: 5.0,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(1000),
            child: SizedBox(
              width: canvasSize.width,
              height: canvasSize.height,
              child: Stack(
                children: [
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
                      onTap: () => _openNodeActions(context, entry.key),
                      onDragDelta: (delta) =>
                          store.addManualOffset(entry.key, delta),
                    ),
                ],
              ),
            ),
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

    _tc.value = Matrix4.identity()
      ..translate(screenSize.width / 2, screenSize.height / 2)
      ..scale(scale)
      ..translate(-bounds.center.dx, -bounds.center.dy);
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
              ],
            ),
          ),
        );
      },
    );
  }

  /// ✅ Only shows missing parent options based on existing parent GENDER.
  Future<void> _addParentFlow(BuildContext context,
      {required int personId}) async {
    final person = store.getNode(personId);
    final (motherId, fatherId) = store.parentPairForPerson(personId);

    final options = <Kind>[
      if (motherId == null) Kind.mother,
      if (fatherId == null) Kind.father,
    ];

    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('${person.name} already has a Mother and a Father.')),
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

    final name = await _promptText(context,
        title: '${chosen.label} Name', initial: 'New ${chosen.label}');
    if (name == null) return;

    final added =
        store.addParent(personId: personId, parentKind: chosen, name: name);
    if (added == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add ${chosen.label} (already exists).')),
      );
    }
  }

  /// ✅ Child is always Son or Daughter (gender always known)
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

  Future<String?> _promptText(BuildContext context,
      {required String title, required String initial}) async {
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
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, c.text),
                child: const Text('Save')),
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
  });

  final FamilyNode node;
  final Offset topLeft;
  final Size size;
  final VoidCallback onTap;
  final ValueChanged<Offset> onDragDelta;

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
      child: GestureDetector(
        onTap: widget.onTap,
        onPanUpdate: (d) => widget.onDragDelta(d.delta),
        child: _MemberCard(node: widget.node),
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.node});

  final FamilyNode node;

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
      child: InkWell(
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
                      style:
                          TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ✅ Connector painter (FIXED):
/// - Groups children by their parent set (1-parent or 2-parent couple).
/// - Draws a couple line when 2 parents exist, then ONE shared drop to a bus line.
/// - Bus line ALWAYS includes the parent/couple X so lines actually connect.
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

    Offset topCenterOf(int nodeId) {
      final p = positions[nodeId]!;
      return Offset(p.dx + cardSize.width / 2, p.dy);
    }

    Offset bottomCenterOf(int nodeId) {
      final p = positions[nodeId]!;
      return Offset(p.dx + cardSize.width / 2, p.dy + cardSize.height);
    }

    // Group children by parent set (so couples draw one shared connector)
    final Map<String, _Group> groups = {};

    for (final child in store.nodes.values) {
      if (child.parents.isEmpty) continue;

      final parentIds = child.parents.take(2).toList()..sort();
      final key = parentIds.join('_');

      final childPos = positions[child.id];
      bool parentsHavePos = true;
      for (final pid in parentIds) {
        if (!positions.containsKey(pid)) parentsHavePos = false;
      }
      if (childPos == null || !parentsHavePos) continue;

      groups.putIfAbsent(key, () => _Group(parentIds: parentIds));
      groups[key]!.childIds.add(child.id);
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

      // Single-child case
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

      // Multi-child case
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
