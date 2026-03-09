// lib/screens/family_tree_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:app/screens/auth/auth_service.dart';
import 'package:app/screens/auth/desktop_body.dart';
import 'package:app/services/cloudinary_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/family_node.dart';
import '../models/gender.dart';
import '../models/member_details.dart';
import '../models/member_form_result.dart';
import '../services/family_tree_store.dart';
import '../utilities/date_format.dart';
import '../utilities/geometry.dart';
import '../pages/member_form_sheet.dart';
import '../pages/photo_viewer_page.dart';
import '../widgets/horizontal_action_tile.dart';
import '../widgets/link_ports.dart';
import '../widgets/member_photo.dart';
import '../widgets/plus_port.dart';

class FamilyTreeScreen extends StatefulWidget {
  const FamilyTreeScreen({super.key});

  @override
  State<FamilyTreeScreen> createState() => _FamilyTreeScreenState();
}

class FamilyTreeLayout {
  FamilyTreeLayout({
    required this.store,
    required this.cardSize,
    required this.hGap,
    required this.vGap,
  });

  final FamilyTreeStore store;
  final // spacing
      Size cardSize;
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

    // Keep everything away from origin so we have room to pan around
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

    // Apply manual offsets (drag reposition)
    for (final n in nodes.values) {
      pos[n.id] = pos[n.id]! + n.manualOffset;
    }

    return pos;
  }
}

class _FamilyTreeScreenState extends State<FamilyTreeScreen> {
  late final FamilyTreeStore store;
  final CloudinaryService _cloudinary = CloudinaryService();

  static const Size cardSize = Size(170, 84);
  static const double hGap = 40;
  static const double vGap = 70;
  static const double virtualSize = 100000;

  final TransformationController _tc = TransformationController();
  bool _didInitialCenter = false;

  static const double _minZoom = 0.3;
  static const double _maxZoom = 3.0;

  double _zoomValue = 1.0;
  bool _syncingFromController = false;

  // Linking state
  bool _isLinking = false;
  int? _linkFromNodeId;
  LinkPort? _linkPort;
  Offset _linkStartScene = Offset.zero;
  Offset _linkCurrentViewport = Offset.zero;

  int? _hoverTargetId;
  Offset _snappedEndViewport = Offset.zero;

  static const double _snapRadius = 70.0;

  int? _hoveredNodeId;
  Map<int, Offset> _lastLayoutScene = {};

  // Multi-select (Ctrl)
  final Set<int> _ctrlSelectedIds = <int>{};

  final ScrollController _actionsCtrl = ScrollController();

  // Auth-load
  StreamSubscription<User?>? _authSub;
  bool _loadedOnce = false;

  bool get _ctrlPressed {
    final kb = HardwareKeyboard.instance;
    return kb.isLogicalKeyPressed(LogicalKeyboardKey.controlLeft) ||
        kb.isLogicalKeyPressed(LogicalKeyboardKey.controlRight);
  }

  void _toggleCtrlSelect(int id) {
    setState(() {
      if (_ctrlSelectedIds.contains(id)) {
        _ctrlSelectedIds.remove(id);
      } else {
        _ctrlSelectedIds.add(id);
      }
    });
  }

  void _clearCtrlSelection() {
    if (_ctrlSelectedIds.isEmpty) return;
    setState(() => _ctrlSelectedIds.clear());
  }

  Future<void> _ensureLoadedFromCloud() async {
    if (_loadedOnce) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _loadedOnce = true;
    try {
      await store.loadFromCloud(treeId: 'default');
      debugPrint('✅ RTDB loaded. nodes=${store.nodes.length}');
    } catch (e) {
      debugPrint('❌ loadFromCloud error: $e');
      _loadedOnce = false; // allow retry if it failed
    }
  }

  @override
  void initState() {
    super.initState();
    store = FamilyTreeStore();

    // If user already signed in, load immediately
    Future.microtask(_ensureLoadedFromCloud);

    // If auth arrives later, load once
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (!mounted) return;
      if (user == null) return;
      await _ensureLoadedFromCloud();
    });

    // Keep slider in sync with controller
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
    _authSub?.cancel();
    store.dispose();
    _tc.dispose();
    _actionsCtrl.dispose();
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

      final d = distancePointToRect(viewportPoint, rectVp);
      if (d < bestDist) {
        bestDist = d;
        bestId = e.key;
      }
    }

    if (bestId == null) return null;
    return (bestDist <= _snapRadius) ? bestId : null;
  }

  void _startLink({
    required int fromNodeId,
    required LinkPort port,
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

      snapped = nearestPointOnRect(viewportPoint, rectVp);
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
      case LinkPort.parentTop:
        ok = store.tryLinkExistingParent(parentId: targetId, childId: fromId);
        break;
      case LinkPort.childBottom:
        ok = store.tryLinkExistingChild(parentId: fromId, childId: targetId);
        break;
      case LinkPort.spouseLeft:
      case LinkPort.spouseRight:
        ok = store.tryLinkExistingSpouses(aId: fromId, bId: targetId);
        break;
    }

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot connect these tiles (rules blocked).')),
      );
    }
  }

  Future<void> _handlePortTap(int nodeId, LinkPort port) async {
    if (_isLinking) return;

    if (_ctrlSelectedIds.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selection active. Ctrl+Click tiles to unselect first.')),
      );
      return;
    }

    switch (port) {
      case LinkPort.parentTop:
        await _addParentFlow(personId: nodeId);
        break;
      case LinkPort.childBottom:
        await _addChildFlow(fromNodeId: nodeId);
        break;
      case LinkPort.spouseLeft:
      case LinkPort.spouseRight:
        await _addSpouseFlow(personId: nodeId);
        break;
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will be signed out. Your saved tree will remain in the database.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
        ],
      ),
    );

    if (!mounted) return;
    if (ok != true) return;

    try {
      await authService.value.signOut();
      // or: await FirebaseAuth.instance.signOut();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logout failed: $e')),
      );
      return;
    }

    if (!mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil(
      LoginPage.route,
      (route) => false,
    );
  }

  Future<String?> _promptText({required String title, required String initial}) async {
    final c = TextEditingController(text: initial);

    final res = await showDialog<String>(
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
          ],
        );
      },
    );

    c.dispose();
    return res;
  }

  Future<void> _applyFormToNode(int nodeId, MemberFormResult r) async {
    debugPrint('APPLY FORM CALLED nodeId=$nodeId saved=${r.saved}');

    if (!r.saved) return;

    store.setGender(nodeId, r.gender);
    store.setDetails(nodeId, r.details);

    if (r.clearBirthday) {
      store.setBirthday(nodeId, null);
    } else {
      store.setBirthday(nodeId, r.birthday);
    }

    if (r.removePhoto) {
      store.removePhoto(nodeId);
      return;
    }

    if (r.newPhotoBytes != null) {
      debugPrint('Uploading photo for node $nodeId ...');

      try {
        final photoUrl = await _cloudinary.uploadBytes(
          r.newPhotoBytes!,
          fileName: 'node_$nodeId.jpg',
        );

        debugPrint('Upload success: $photoUrl');
        store.setPhotoUrl(nodeId, photoUrl);
      } catch (e) {
        debugPrint('Cloudinary upload failed: $e');

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photo upload failed: $e')),
        );
      }
    }
  }
  Future<void> _editDetailsFlow(int nodeId) async {
    final n = store.getNode(nodeId);
    final initial = MemberDetails(
      address: n.address,
      phone: n.phone,
      company: n.company,
      jobTitle: n.jobTitle,
      fb: n.fb,
      ig: n.ig,
      xAccount: n.xAccount,
      tiktok: n.tiktok,
    );

    final r = await MemberFormSheet(context).open(
      showNameField: false,
      initialName: null,
      initialGender: n.gender,
      allowedGenders: const [Gender.female, Gender.male],
      initialDetails: initial,
      initialBirthday: n.birthday,
      initialPhotoBytes: n.photoBytes,
      allowRemovePhoto: true,
      allowClearBirthday: true,
      title: 'View / Edit Details',
    );

    if (!mounted) return;
    await _applyFormToNode(nodeId, r);
  }

  void _viewPhotoFullScreen(FamilyNode node) {
    if (!node.hasPhoto) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PhotoViewerPage(node: node)),
    );
  }

  Future<String?> _uploadPhotoIfNeeded(Uint8List? bytes, String filePrefix) async {
    if (bytes == null) return null;

    try {
      debugPrint('Uploading photo to Cloudinary...');

      final url = await _cloudinary.uploadBytes(
        bytes,
        fileName: '${filePrefix}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      debugPrint('Upload success: $url');
      return url;
    } catch (e) {
      debugPrint('Cloudinary upload failed: $e');

      if (!mounted) return null;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Photo upload failed: $e')),
      );
      return null;
    }
  }


  Future<void> _addFirstMemberFlow() async {
    final r = await MemberFormSheet(context).open(
      showNameField: true,
      initialName: 'New Member',
      initialGender: Gender.female,
      allowedGenders: const [Gender.female, Gender.male],
      title: 'Add Member Info',
      allowRemovePhoto: false,
      allowClearBirthday: true,
    );
    if (!mounted) return;
    if (!r.saved) return;

    final name = (r.name ?? '').trim();
    if (name.isEmpty) return;

    final photoUrl = await _uploadPhotoIfNeeded(r.newPhotoBytes, 'member');

    store.addRoot(
      name: name,
      gender: r.gender,
      birthday: r.clearBirthday ? null : r.birthday,
      photoUrl: photoUrl,
      photoBytes: null,
      address: r.details.address,
      phone: r.details.phone,
      company: r.details.company,
      jobTitle: r.details.jobTitle,
      fb: r.details.fb,
      ig: r.details.ig,
      xAccount: r.details.xAccount,
      tiktok: r.details.tiktok,
    );
  }

  Future<void> _addStandaloneMemberFlow() async {
    final r = await MemberFormSheet(context).open(
      showNameField: true,
      initialName: 'New Member',
      initialGender: Gender.female,
      allowedGenders: const [Gender.female, Gender.male],
      title: 'Add Member Info',
      allowRemovePhoto: false,
      allowClearBirthday: true,
    );
    if (!mounted) return;
    if (!r.saved) return;

    final name = (r.name ?? '').trim();
    if (name.isEmpty) return;

    final photoUrl = await _uploadPhotoIfNeeded(r.newPhotoBytes, 'member');

    store.addStandalone(
      name: name,
      gender: r.gender,
      birthday: r.clearBirthday ? null : r.birthday,
      photoUrl: photoUrl,
      photoBytes: null,
      address: r.details.address,
      phone: r.details.phone,
      company: r.details.company,
      jobTitle: r.details.jobTitle,
      fb: r.details.fb,
      ig: r.details.ig,
      xAccount: r.details.xAccount,
      tiktok: r.details.tiktok,
    );
  }

  // ✅ Read-only details popup for non-owners
  Future<void> _showDetailsPopup(int nodeId) async {
    final node = store.getNode(nodeId);

    String? line(String label, String? value) {
      final v = (value ?? '').trim();
      if (v.isEmpty) return null;
      return '$label: $v';
    }

    final lines = <String>[
      if (node.birthday != null) 'Birthday: ${formatDate(node.birthday!)}',
      ...[
        line('Address', node.address),
        line('Phone', node.phone),
        line('Company', node.company),
        line('Job Title', node.jobTitle),
        line('Facebook', node.fb),
        line('Instagram', node.ig),
        line('X', node.xAccount),
        line('TikTok', node.tiktok),
      ].whereType<String>(),
    ];

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: node.hasPhoto ? () => _viewPhotoFullScreen(node) : null,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: !node.hasPhoto ? node.gender.tone : null,
                          border: Border.all(color: Colors.grey.shade300, width: 1),
                        ),
                        child: !node.hasPhoto
                            ? Icon(node.gender.icon, size: 26, color: Colors.grey.shade700)
                            : ClipOval(
                                child: Image(image: node.photoProvider, fit: BoxFit.cover),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            node.name,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(node.gender.icon, size: 14, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(
                                node.gender.label,
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Read-only',
                                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (lines.isEmpty)
                  Text(
                    'No additional details provided.',
                    style: TextStyle(color: Colors.grey.shade700),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.55,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final t in lines)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(t, style: const TextStyle(fontSize: 14, height: 1.25)),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.check),
                    label: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openNodeActions(int nodeId) async {
    if (_ctrlSelectedIds.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selection active. Ctrl+Click tiles to unselect first.')),
      );
      return;
    }

    // ✅ Not owner -> show read-only details instead of edit options
    if (!store.canEditNodeId(nodeId)) {
      await _showDetailsPopup(nodeId);
      return;
    }

    final node = store.getNode(nodeId);

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      isScrollControlled: false,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.close, color: Colors.black54),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: node.hasPhoto ? () => _viewPhotoFullScreen(node) : null,
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: !node.hasPhoto ? node.gender.tone : null,
                                border: Border.all(color: Colors.grey.shade300, width: 1),
                              ),
                              child: !node.hasPhoto
                                  ? Icon(node.gender.icon, size: 24, color: Colors.grey.shade700)
                                  : ClipOval(
                                      child: Image(image: node.photoProvider, fit: BoxFit.cover),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  node.name,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(node.gender.icon, size: 14, color: Colors.grey.shade600),
                                    const SizedBox(width: 4),
                                    Text(
                                      node.gender.label,
                                      style:
                                          TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                    ),
                                    if (node.birthday != null) ...[
                                      const SizedBox(width: 10),
                                      const Icon(Icons.cake_outlined, size: 14),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          formatDate(node.birthday!),
                                          style: TextStyle(
                                              color: Colors.grey.shade600, fontSize: 12),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 120,
                      child: Scrollbar(
                        controller: _actionsCtrl,
                        thumbVisibility: true,
                        child: ListView(
                          controller: _actionsCtrl,
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.only(left: 4, right: 20),
                          children: [
                            HorizontalActionTile(
                              icon: Icons.badge_outlined,
                              title: 'Details',
                              subtitle: 'View / Edit',
                              color: Colors.indigo,
                              onTap: () async {
                                Navigator.pop(ctx);
                                await _editDetailsFlow(nodeId);
                              },
                            ),
                            HorizontalActionTile(
                              icon: Icons.edit,
                              title: 'Edit',
                              subtitle: 'Name',
                              color: Colors.green,
                              onTap: () async {
                                Navigator.pop(ctx);
                                final name = await _promptText(
                                    title: 'Edit Name', initial: node.name);
                                if (!mounted) return;
                                if (name != null) store.renameNode(nodeId, name);
                              },
                            ),
                            HorizontalActionTile(
                              icon: Icons.favorite,
                              title: 'Add',
                              subtitle: 'Spouse',
                              color: Colors.pink,
                              enabled: node.spouses.isEmpty,
                              onTap: () async {
                                Navigator.pop(ctx);
                                await _addSpouseFlow(personId: nodeId);
                              },
                            ),
                            HorizontalActionTile(
                              icon: Icons.arrow_upward,
                              title: 'Add',
                              subtitle: 'Parent',
                              color: Colors.purple,
                              enabled: node.parents.length < 2,
                              onTap: () async {
                                Navigator.pop(ctx);
                                await _addParentFlow(personId: nodeId);
                              },
                            ),
                            HorizontalActionTile(
                              icon: Icons.arrow_downward,
                              title: 'Add',
                              subtitle: 'Child',
                              color: Colors.teal,
                              onTap: () async {
                                Navigator.pop(ctx);
                                await _addChildFlow(fromNodeId: nodeId);
                              },
                            ),
                            HorizontalActionTile(
                              icon: Icons.delete,
                              title: 'Delete',
                              subtitle: 'Member',
                              color: Colors.red,
                              onTap: () async {
                                Navigator.pop(ctx);

                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (dctx) => AlertDialog(
                                    title: const Text('Delete member?'),
                                    content: const Text(
                                        'This will remove the member and all related links.'),
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

                                if (!mounted) return;
                                if (ok == true) store.deleteNode(nodeId);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addSpouseFlow({required int personId}) async {
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

    final spouseGender = person.gender.opposite;

    final r = await MemberFormSheet(context).open(
      showNameField: true,
      initialName: 'New Spouse',
      initialGender: spouseGender,
      allowedGenders: [spouseGender],
      title: 'Add Spouse Info',
      allowRemovePhoto: false,
      allowClearBirthday: true,
    );
    if (!mounted) return;
    if (!r.saved) return;

    final name = (r.name ?? '').trim();
    if (name.isEmpty) return;

    final photoUrl = await _uploadPhotoIfNeeded(r.newPhotoBytes, 'spouse');

    final added = store.addSpouse(
      personId: personId,
      name: name,
      birthday: r.clearBirthday ? null : r.birthday,
      photoUrl: photoUrl,
      photoBytes: null,
      address: r.details.address,
      phone: r.details.phone,
      company: r.details.company,
      jobTitle: r.details.jobTitle,
      fb: r.details.fb,
      ig: r.details.ig,
      xAccount: r.details.xAccount,
      tiktok: r.details.tiktok,
    );

    if (added == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not add spouse.')),
      );
    }
  }

  Future<void> _addParentFlow({required int personId}) async {
    final person = store.getNode(personId);

    if (person.parents.length >= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${person.name} already has 2 parents.')),
      );
      return;
    }

    final (femaleP, maleP) = store.parentPairForPerson(personId);

    final options = <Gender>[
      if (femaleP == null) Gender.female,
      if (maleP == null) Gender.male,
    ];

    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${person.name} already has 2 parents.')),
      );
      return;
    }

    final r = await MemberFormSheet(context).open(
      showNameField: true,
      initialName: 'New Parent',
      initialGender: options.first,
      allowedGenders: options,
      title: 'Add Parent Info',
      allowRemovePhoto: false,
      allowClearBirthday: true,
    );
    if (!mounted) return;
    if (!r.saved) return;

    final name = (r.name ?? '').trim();
    if (name.isEmpty) return;

    final photoUrl = await _uploadPhotoIfNeeded(r.newPhotoBytes, 'parent');

    final added = store.addParent(
      personId: personId,
      parentGender: r.gender,
      name: name,
      birthday: r.clearBirthday ? null : r.birthday,
      photoUrl: photoUrl,
      photoBytes: null,
      address: r.details.address,
      phone: r.details.phone,
      company: r.details.company,
      jobTitle: r.details.jobTitle,
      fb: r.details.fb,
      ig: r.details.ig,
      xAccount: r.details.xAccount,
      tiktok: r.details.tiktok,
    );

    if (added == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not add parent (blocked).')),
      );
    }
  }

  Future<void> _addChildFlow({required int fromNodeId}) async {
    final r = await MemberFormSheet(context).open(
      showNameField: true,
      initialName: 'New Child',
      initialGender: Gender.female,
      allowedGenders: const [Gender.female, Gender.male],
      title: 'Add Child Info',
      allowRemovePhoto: false,
      allowClearBirthday: true,
    );
    if (!mounted) return;
    if (!r.saved) return;

    final name = (r.name ?? '').trim();
    if (name.isEmpty) return;

    final photoUrl = await _uploadPhotoIfNeeded(r.newPhotoBytes, 'child');

    store.addChild(
      fromNodeId: fromNodeId,
      name: name,
      childGender: r.gender,
      birthday: r.clearBirthday ? null : r.birthday,
      photoUrl: photoUrl,
      photoBytes: null,
      address: r.details.address,
      phone: r.details.phone,
      company: r.details.company,
      jobTitle: r.details.jobTitle,
      fb: r.details.fb,
      ig: r.details.ig,
      xAccount: r.details.xAccount,
      tiktok: r.details.tiktok,
    );
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

        // Center everything in a big virtual canvas
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
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapDown: (_) {
                  if (_isLinking) return;
                  if (_ctrlPressed) return;
                  _clearCtrlSelection();
                },
                child: InteractiveViewer(
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
                            painter: ConnectorPainter(
                              store: store,
                              positions: layout,
                              cardSize: cardSize,
                            ),
                          ),
                        for (final entry in layout.entries)
                          AnimatedNode(
                            node: store.getNode(entry.key),
                            topLeft: entry.value,
                            size: cardSize,
                            isSelected: _ctrlSelectedIds.contains(entry.key),
                            isHovered: _ctrlSelectedIds.contains(entry.key) ||
                                entry.key == _hoveredNodeId ||
                                (_isLinking && _linkFromNodeId == entry.key),
                            dragEnabled: !_isLinking,
                            showPortsEnabled: store.canEditNodeId(entry.key),
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
                            onTapSelect: (id) {
                              if (_isLinking) return;

                              if (_ctrlPressed) {
                                _toggleCtrlSelect(id);
                                return;
                              }

                              if (_ctrlSelectedIds.isNotEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Selection active. Ctrl+Click tiles to unselect.'),
                                  ),
                                );
                                return;
                              }

                              _openNodeActions(id);
                            },
                            onDragStart: () {
                              if (_isLinking) return;

                              if (_ctrlPressed && !_ctrlSelectedIds.contains(entry.key)) {
                                _toggleCtrlSelect(entry.key);
                              }
                            },
                            onDragEnd: () {},
                            onDragDelta: (delta) {
                              if (_isLinking) return;

                              final draggedId = entry.key;
                              final ids = (_ctrlSelectedIds.isNotEmpty &&
                                      _ctrlSelectedIds.contains(draggedId))
                                  ? _ctrlSelectedIds
                                  : <int>{draggedId};

                              if (ids.length == 1) {
                                store.addManualOffset(draggedId, delta);
                              } else {
                                store.addManualOffsetBulk(ids, delta);
                              }
                            },
                            onStartPortDrag: (port, globalStart) {
                              final topLeft = layout[entry.key]!;
                              final startScene = switch (port) {
                                LinkPort.parentTop =>
                                  Offset(topLeft.dx + cardSize.width / 2, topLeft.dy),
                                LinkPort.childBottom => Offset(
                                    topLeft.dx + cardSize.width / 2, topLeft.dy + cardSize.height),
                                LinkPort.spouseLeft =>
                                  Offset(topLeft.dx, topLeft.dy + cardSize.height / 2),
                                LinkPort.spouseRight => Offset(
                                    topLeft.dx + cardSize.width, topLeft.dy + cardSize.height / 2),
                              };

                              _startLink(
                                fromNodeId: entry.key,
                                port: port,
                                startScene: startScene,
                                startViewport: _globalToViewport(globalStart),
                              );
                            },
                            onUpdatePortDrag: (g) => _updateLink(_globalToViewport(g)),
                            onEndPortDrag: (g) => _endLink(_globalToViewport(g)),
                            onTapPort: _handlePortTap,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_isLinking)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: LinkPreviewPainter(
                        start: _sceneToViewport(_linkStartScene),
                        end: (_hoverTargetId != null) ? _snappedEndViewport : _linkCurrentViewport,
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
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Add your first member to begin.',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: _addFirstMemberFlow,
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: SizedBox(
                        width: 290,
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Zoom out',
                              icon: const Icon(Icons.remove, size: 18),
                              onPressed: () {
                                final next = (_zoomValue / 1.15).clamp(_minZoom, _maxZoom);
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
                                final next = (_zoomValue * 1.15).clamp(_minZoom, _maxZoom);
                                _setZoom(next);
                              },
                            ),
                            const SizedBox(width: 6),
                            Container(width: 1, height: 22, color: const Color(0xFFE2E6EE)),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: 'Add standalone member',
                              icon: const Icon(Icons.person_add_alt_1, size: 18),
                              onPressed: _addStandaloneMemberFlow,
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
    return Rect.fromLTRB(minX - margin, minY - margin, maxX + margin, maxY + margin);
  }

  void _fitToScreen(Rect bounds) {
    final screenSize = MediaQuery.of(context).size;
    final scale = min(screenSize.width / bounds.width, screenSize.height / bounds.height) * 0.8;

    _syncingFromController = true;
    _tc.value = Matrix4.identity()
      ..translate(screenSize.width / 2, screenSize.height / 2)
      ..scale(scale)
      ..translate(-bounds.center.dx, -bounds.center.dy);
    _syncingFromController = false;

    final clamped = scale.clamp(_minZoom, _maxZoom);
    setState(() => _zoomValue = clamped);
  }
}

/* =========================
   Widgets + Painters (local)
   ========================= */

class AnimatedNode extends StatefulWidget {
  const AnimatedNode({
    super.key,
    required this.node,
    required this.topLeft,
    required this.size,
    required this.onTapSelect,
    required this.onDragDelta,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onStartPortDrag,
    required this.onUpdatePortDrag,
    required this.onEndPortDrag,
    required this.onTapPort,
    required this.isHovered,
    required this.isSelected,
    required this.onHoverChanged,
    required this.dragEnabled,
    required this.showPortsEnabled,
  });

  final FamilyNode node;
  final Offset topLeft;
  final Size size;

  final ValueChanged<int> onTapSelect;

  final ValueChanged<Offset> onDragDelta;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;

  final void Function(LinkPort port, Offset globalStart) onStartPortDrag;
  final void Function(Offset globalPos) onUpdatePortDrag;
  final void Function(Offset globalPos) onEndPortDrag;

  final void Function(int nodeId, LinkPort port) onTapPort;

  final bool isHovered;
  final bool isSelected;
  final ValueChanged<bool> onHoverChanged;
  final bool dragEnabled;
  final bool showPortsEnabled;

  @override
  State<AnimatedNode> createState() => _AnimatedNodeState();
}

class _AnimatedNodeState extends State<AnimatedNode> {
  Offset? _hoverLocal;

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
        onExit: (_) {
          setState(() => _hoverLocal = null);
          widget.onHoverChanged(false);
        },
        onHover: (e) => setState(() => _hoverLocal = e.localPosition),
        child: GestureDetector(
          onTap: () => widget.onTapSelect(widget.node.id),
          onPanStart: widget.dragEnabled ? (_) => widget.onDragStart() : null,
          onPanUpdate: widget.dragEnabled ? (d) => widget.onDragDelta(d.delta) : null,
          onPanEnd: widget.dragEnabled ? (_) => widget.onDragEnd() : null,
          child: MemberCard(
            node: widget.node,
            showPorts: widget.isHovered && widget.showPortsEnabled,
            hoverLocal: _hoverLocal,
            size: widget.size,
            isSelected: widget.isSelected,
            onStartPortDrag: widget.onStartPortDrag,
            onUpdatePortDrag: widget.onUpdatePortDrag,
            onEndPortDrag: widget.onEndPortDrag,
            onTapPort: widget.onTapPort,
          ),
        ),
      ),
    );
  }
}

class MemberCard extends StatelessWidget {
  const MemberCard({
    super.key,
    required this.node,
    required this.showPorts,
    required this.hoverLocal,
    required this.size,
    required this.isSelected,
    required this.onStartPortDrag,
    required this.onUpdatePortDrag,
    required this.onEndPortDrag,
    required this.onTapPort,
  });

  final FamilyNode node;
  final bool showPorts;
  final Offset? hoverLocal;
  final Size size;
  final bool isSelected;

  final void Function(LinkPort port, Offset globalStart) onStartPortDrag;
  final void Function(Offset globalPos) onUpdatePortDrag;
  final void Function(Offset globalPos) onEndPortDrag;
  final void Function(int nodeId, LinkPort port) onTapPort;

  bool get _canShowParent => showPorts && node.parents.length < 2;
  bool get _canShowChild => showPorts;
  bool get _canShowSpouse => showPorts && node.spouses.isEmpty;

  static const double _edgeThreshold = 26.0;

  LinkPort? _nearestAllowedPort() {
    if (!showPorts) return null;
    final p = hoverLocal;
    if (p == null) return null;

    final w = size.width;
    final h = size.height;

    final dTop = p.dy;
    final dBottom = (h - p.dy).abs();
    final dLeft = p.dx;
    final dRight = (w - p.dx).abs();

    final minDist = [dTop, dBottom, dLeft, dRight].reduce(min);
    if (minDist > _edgeThreshold) return null;

    final candidates = <(LinkPort port, double dist)>[
      (LinkPort.parentTop, dTop),
      (LinkPort.childBottom, dBottom),
      (LinkPort.spouseLeft, dLeft),
      (LinkPort.spouseRight, dRight),
    ]..sort((a, b) => a.$2.compareTo(b.$2));

    for (final c in candidates) {
      switch (c.$1) {
        case LinkPort.parentTop:
          if (_canShowParent) return c.$1;
          break;
        case LinkPort.childBottom:
          if (_canShowChild) return c.$1;
          break;
        case LinkPort.spouseLeft:
        case LinkPort.spouseRight:
          if (_canShowSpouse) return c.$1;
          break;
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final activePort = showPorts ? _nearestAllowedPort() : null;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: isSelected ? Border.all(color: const Color(0xFF4C7DFF), width: 2) : null,
      ),
      child: Material(
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
                    MemberPhoto(node: node),
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
                            node.gender.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                          ),
                          if (node.birthday != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              formatDate(node.birthday!),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (activePort == LinkPort.parentTop)
              Positioned(
                top: -10,
                left: (size.width / 2) - 10,
                child: PlusPort(
                  tooltip: 'Add Parent',
                  onTap: () => onTapPort(node.id, LinkPort.parentTop),
                  onStart: (g) => onStartPortDrag(LinkPort.parentTop, g),
                  onUpdate: onUpdatePortDrag,
                  onEnd: onEndPortDrag,
                ),
              ),
            if (activePort == LinkPort.childBottom)
              Positioned(
                bottom: -10,
                left: (size.width / 2) - 10,
                child: PlusPort(
                  tooltip: 'Add Child',
                  onTap: () => onTapPort(node.id, LinkPort.childBottom),
                  onStart: (g) => onStartPortDrag(LinkPort.childBottom, g),
                  onUpdate: onUpdatePortDrag,
                  onEnd: onEndPortDrag,
                ),
              ),
            if (activePort == LinkPort.spouseLeft)
              Positioned(
                left: -10,
                top: (size.height / 2) - 10,
                child: PlusPort(
                  tooltip: 'Add Spouse',
                  onTap: () => onTapPort(node.id, LinkPort.spouseLeft),
                  onStart: (g) => onStartPortDrag(LinkPort.spouseLeft, g),
                  onUpdate: onUpdatePortDrag,
                  onEnd: onEndPortDrag,
                ),
              ),
            if (activePort == LinkPort.spouseRight)
              Positioned(
                right: -10,
                top: (size.height / 2) - 10,
                child: PlusPort(
                  tooltip: 'Add Spouse',
                  onTap: () => onTapPort(node.id, LinkPort.spouseRight),
                  onStart: (g) => onStartPortDrag(LinkPort.spouseRight, g),
                  onUpdate: onUpdatePortDrag,
                  onEnd: onEndPortDrag,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class LinkPreviewPainter extends CustomPainter {
  LinkPreviewPainter({required this.start, required this.end});
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
  bool shouldRepaint(covariant LinkPreviewPainter oldDelegate) {
    return oldDelegate.start != start || oldDelegate.end != end;
  }
}

class _Group {
  _Group({required this.parentIds});
  final List<int> parentIds;
  final List<int> childIds = [];
}

class ConnectorPainter extends CustomPainter {
  ConnectorPainter({
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

      final (femaleP, maleP) = store.parentPairForPerson(child.id);

      // Start with the known parents from the child's data
      final parentIds = <int>[
        if (femaleP != null) femaleP,
        if (maleP != null) maleP,
      ]..sort();

      // ✅ VISUAL FIX:
      // If the child only has ONE parent recorded, try to attach them visually to that
      // parent's spouse line (so they share the horizontal children bus with siblings).
      // (This does NOT change the database; it only affects drawing.)
      if (parentIds.length == 1) {
        final onlyParentId = parentIds.first;
        final onlyParent = store.nodes[onlyParentId];

        if (onlyParent != null && onlyParent.spouses.isNotEmpty) {
          // pick a spouse that is positioned (visible)
          final spouseId = onlyParent.spouses.firstWhere(
            (sid) => positions.containsKey(sid),
            orElse: () => -1,
          );

          if (spouseId != -1) {
            parentIds.add(spouseId);
            parentIds.sort();
          }
        }
      }

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
        canvas.drawLine(Offset(leftX, coupleY), Offset(rightX, coupleY), spousePaint);

        final heart = TextPainter(
          text: const TextSpan(
            text: '❤',
            style: TextStyle(fontSize: 12, color: Color(0xFFB9C0CC)),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        heart.paint(canvas, Offset(midX - heart.width / 2, coupleY - heart.height / 2));
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
      final anchorX =
          isCouple ? (parentBottoms[0].dx + parentBottoms[1].dx) / 2 : parentBottoms.first.dx;

      minX = min(minX, anchorX);
      maxX = max(maxX, anchorX);

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
  bool shouldRepaint(covariant ConnectorPainter oldDelegate) {
    return oldDelegate.positions != positions ||
        oldDelegate.store != store ||
        oldDelegate.cardSize != cardSize;
  }
}