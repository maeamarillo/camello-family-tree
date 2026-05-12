// lib/screens/family_tree_screen.dart
import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:app/screens/auth/auth_service.dart';
import 'package:app/screens/auth/desktop_body.dart';
import 'package:app/services/cloudinary_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/family_node.dart';
import '../models/gender.dart';
import '../models/member_details.dart';
import '../models/member_form_result.dart';
import '../pages/photo_viewer_page.dart';
import '../services/family_tree_store.dart';
import '../utilities/date_format.dart';
import '../utilities/geometry.dart';
import '../widgets/link_ports.dart';
import '../widgets/member_photo.dart';
import '../widgets/plus_port.dart';

class FamilyTreeScreen extends StatefulWidget {
  const FamilyTreeScreen({super.key});

  @override
  State<FamilyTreeScreen> createState() => _FamilyTreeScreenState();
}

class _TreeGreenTheme {
  static const Color scaffold = Color(0xFFF3FBF5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color softSurface = Color(0xFFF7FCF8);
  static const Color primary = Color(0xFF2E7D5A);
  static const Color accent = Color(0xFF67B37F);
  static const Color border = Color(0xFFCFE5D6);
  static const Color divider = Color(0xFFD9EADF);
  static const Color shadow = Color(0x1F1F3A29);
  static const Color textMuted = Color(0xFF5F7468);
  static const Color connector = Color(0xFFA6C9B1);
  static const Color selection = Color(0xFF4FA36D);
  static const Color actionBlue = Color(0xFF4F8F72);
  static const Color actionPink = Color(0xFF8FBF8A);
  static const Color actionPurple = Color(0xFF6DAA7F);
  static const Color actionTeal = Color(0xFF3D9B73);
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
    double minX = double.infinity;
    double minY = double.infinity;

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

class _MemberFormDrawerRequest {
  const _MemberFormDrawerRequest({
    required this.title,
    required this.showNameField,
    required this.initialName,
    required this.initialGender,
    required this.allowedGenders,
    required this.initialDetails,
    required this.initialBirthday,
    required this.initialPhotoBytes,
    required this.initialPhotoProvider,
    required this.allowRemovePhoto,
    required this.allowClearBirthday,
  });

  final String title;
  final bool showNameField;
  final String? initialName;
  final Gender initialGender;
  final List<Gender> allowedGenders;
  final MemberDetails initialDetails;
  final DateTime? initialBirthday;
  final Uint8List? initialPhotoBytes;
  final ImageProvider? initialPhotoProvider;
  final bool allowRemovePhoto;
  final bool allowClearBirthday;
}

class TreeBanner {
  TreeBanner({
    required this.id,
    required this.text,
    required this.position,
  });

  final int id;
  String text;
  Offset position;
}
class _FamilyTreeScreenState extends State<FamilyTreeScreen> {
  late final FamilyTreeStore store;
  final CloudinaryService _cloudinary = CloudinaryService();
  bool _previewMode = false;
  bool _isLoading = true;

  static const Size cardSize = Size(220, 84);
  static const double hGap = 40;
  static const double vGap = 70;
  static const double virtualSize = 100000;
  static const double _maxDrawerWidth = 420;

  final TransformationController _tc = TransformationController();

  static const double _minZoom = 0.3;
  static const double _maxZoom = 3.0;
  static const double _snapRadius = 70.0;

  bool _didInitialCenter = false;
  bool _syncingFromController = false;
  double _zoomValue = 1.0;

  bool _isLinking = false;
  int? _linkFromNodeId;
  LinkPort? _linkPort;
  Offset _linkStartScene = Offset.zero;
  Offset _linkCurrentViewport = Offset.zero;
  int? _hoverTargetId;
  Offset _snappedEndViewport = Offset.zero;

  int? _hoveredNodeId;
  int? _draggingNodeId;
  Map<int, Offset> _lastLayoutScene = {};

  /// Notifier for live drag positions — updated every pointer frame inside
  /// [_AnimatedNodeState] without triggering a parent setState.
  final ValueNotifier<Map<int, Offset>> _dragOverlayNotifier =
      ValueNotifier(<int, Offset>{});

  final Set<int> _ctrlSelectedIds = <int>{};

  StreamSubscription<User?>? _authSub;
  bool _loadedOnce = false;

  /// The padded tile image used by the watermark shader.
  /// Spacing between logos is baked in as transparent padding.
  ui.Image? _watermarkTile;
  ImageStream? _watermarkStream;
  late final ImageStreamListener _watermarkListener;

  _MemberFormDrawerRequest? _drawerRequest;
  Completer<MemberFormResult>? _drawerCompleter;

  // Key for coordinate conversion when the tree area is shifted
  final GlobalKey _viewerContainerKey = GlobalKey();

  // Search controller kept alive for the entire lifetime of the state
  final TextEditingController _searchController = TextEditingController();

  bool get _isDrawerOpen => _drawerRequest != null;

  bool get _ctrlPressed {
    final kb = HardwareKeyboard.instance;
    return kb.isLogicalKeyPressed(LogicalKeyboardKey.controlLeft) ||
        kb.isLogicalKeyPressed(LogicalKeyboardKey.controlRight);
  }

  @override
  void initState() {
    super.initState();
    store = FamilyTreeStore();

    Future.microtask(_ensureLoadedFromCloud);
    _loadWatermarkImage();

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (!mounted) return;
      if (user == null) return;
      await _ensureLoadedFromCloud();
    });

    _tc.addListener(() {
      if (!mounted || _syncingFromController) return;
      final s = _tc.value.getMaxScaleOnAxis().clamp(_minZoom, _maxZoom);
      if ((s - _zoomValue).abs() > 0.005) {
        setState(() => _zoomValue = s);
      }
    });
  }

  /// Loads the logo from the network, then composites it into a larger
  /// transparent tile (logo + padding) so spacing is baked into the shader.
  void _loadWatermarkImage() {
    const url =
        'https://raw.githubusercontent.com/maeamarillo/camello-family-tree/main/assets/images/camello-logo.PNG';
    _watermarkListener = ImageStreamListener((info, _) async {
      if (!mounted) return;
      final tile = await _buildDiamondTile(
        src: info.image,
        logoSize: 140,
        padding: 120,
      );
      if (!mounted) return;
      setState(() => _watermarkTile = tile);
    });
    _watermarkStream =
        NetworkImage(url).resolve(ImageConfiguration.empty);
    _watermarkStream!.addListener(_watermarkListener);
  }

  /// Builds a tile that produces a diamond (offset-row) pattern when repeated.
  ///
  /// The tile is [step] × [step*2] where step = logoSize + padding.
  ///   • Row A: one logo centred at (step/2, step/2)
  ///   • Row B: logo centred at x = 0 (edges wrap) and x = step, y = step*1.5
  ///
  /// When the GPU tiles this, row B is offset by step/2 horizontally, giving
  /// the classic diamond / brick stagger.
  static Future<ui.Image> _buildDiamondTile({
    required ui.Image src,
    required double logoSize,
    required double padding,
  }) async {
    final step = logoSize + padding;
    final tileW = step;
    final tileH = step * 2;

    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder);
    final srcRect =
        Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble());
    final paint = Paint()..filterQuality = FilterQuality.medium;

    // Row A — centred in the top half of the tile.
    c.drawImageRect(
      src, srcRect,
      Rect.fromCenter(
          center: Offset(step / 2, step / 2),
          width: logoSize, height: logoSize),
      paint,
    );

    // Row B — offset by step/2 horizontally; drawn at both edges so the
    // repeat seam is seamless.
    for (final x in [0.0, step]) {
      c.drawImageRect(
        src, srcRect,
        Rect.fromCenter(
            center: Offset(x, step * 1.5),
            width: logoSize, height: logoSize),
        paint,
      );
    }

    return (recorder.endRecording()).toImage(tileW.round(), tileH.round());
  }

  @override
  void dispose() {
    _watermarkStream?.removeListener(_watermarkListener);
    if (_drawerCompleter != null && !_drawerCompleter!.isCompleted) {
      _drawerCompleter!.complete(
        const MemberFormResult(
          saved: false,
          name: null,
          gender: Gender.female,
          details: MemberDetails(),
          birthday: null,
          clearBirthday: false,
          removePhoto: false,
          newPhotoBytes: null,
        ),
      );
    }

    _authSub?.cancel();
    _searchController.dispose();
    _dragOverlayNotifier.dispose();
    store.dispose();
    _tc.dispose();
    super.dispose();
  }

  int? _searchNodeId(String query) {
    final q = query.toLowerCase().trim();

    for (final entry in store.nodes.entries) {
      final node = entry.value;
      if (node.name.toLowerCase().contains(q)) {
        return entry.key;
      }
    }

    return null;
  }

  void _focusNode(int nodeId) {
    final pos = _lastLayoutScene[nodeId];
    if (pos == null) return;

    final screenSize = MediaQuery.of(context).size;
    final viewportCenter = Offset(screenSize.width / 2, screenSize.height / 2);
    final nodeCenter = pos + Offset(cardSize.width / 2, cardSize.height / 2);

    _syncingFromController = true;

    _tc.value = Matrix4.identity()
      ..translate(viewportCenter.dx, viewportCenter.dy)
      ..scale(_zoomValue)
      ..translate(-nodeCenter.dx, -nodeCenter.dy);

    _syncingFromController = false;

    setState(() {
      _hoveredNodeId = nodeId;
    });
  }

  void _handleSearch(String query) {
    final id = _searchNodeId(query);

    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member not found')),
      );
      return;
    }

    _focusNode(id);
  }

  int? _findNodeByExactName(String name) {
    final q = name.toLowerCase().trim();

    for (final entry in store.nodes.entries) {
      if (entry.value.name.toLowerCase().trim() == q) {
        return entry.key;
      }
    }
    return null;
  }

  void _placeNear(int newId, int targetId, Offset offset) {
    final targetPos = _lastLayoutScene[targetId];
    final newPos = _lastLayoutScene[newId];

    if (targetPos == null || newPos == null) return;

    final desired = targetPos + offset;
    final delta = desired - newPos;

    store.addManualOffset(newId, delta);
  }

  Future<void> _ensureLoadedFromCloud() async {
    if (_loadedOnce) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    _loadedOnce = true;
    try {
      await store.loadFromCloud(treeId: 'default');
      debugPrint('✅ RTDB loaded. nodes=${store.nodes.length}');
    } catch (e) {
      debugPrint('❌ loadFromCloud error: $e');
      _loadedOnce = false;
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Widget buildClickableRelation({
    required String label,
    required List<int> ids,
  }) {
    if (ids.isEmpty) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 4,
        children: [
          Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          ...ids.map((id) {
            final n = store.getNode(id);
            return InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () {
                Navigator.pop(context);
                _focusNode(id);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _TreeGreenTheme.softSurface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _TreeGreenTheme.border),
                ),
                child: Text(
                  n.name,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _TreeGreenTheme.primary,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
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

  Future<MemberFormResult> _openMemberFormDrawer({
    required String title,
    required bool showNameField,
    required String? initialName,
    required Gender initialGender,
    required List<Gender> allowedGenders,
    MemberDetails? initialDetails,
    DateTime? initialBirthday,
    Uint8List? initialPhotoBytes,
    ImageProvider? initialPhotoProvider,
    required bool allowRemovePhoto,
    required bool allowClearBirthday,
  }) async {
    if (_drawerCompleter != null && !_drawerCompleter!.isCompleted) {
      _drawerCompleter!.complete(
        MemberFormResult(
          saved: false,
          name: null,
          gender: initialGender,
          details: initialDetails ?? const MemberDetails(),
          birthday: initialBirthday,
          clearBirthday: false,
          removePhoto: false,
          newPhotoBytes: null,
        ),
      );
    }

    final completer = Completer<MemberFormResult>();

    setState(() {
      _drawerCompleter = completer;
      _drawerRequest = _MemberFormDrawerRequest(
        title: title,
        showNameField: showNameField,
        initialName: initialName,
        initialGender: initialGender,
        allowedGenders: allowedGenders,
        initialDetails: initialDetails ?? const MemberDetails(),
        initialBirthday: initialBirthday,
        initialPhotoBytes: initialPhotoBytes,
        initialPhotoProvider: initialPhotoProvider,
        allowRemovePhoto: allowRemovePhoto,
        allowClearBirthday: allowClearBirthday,
      );
    });

    final result = await completer.future;
    if (!mounted) return result;

    setState(() {
      _drawerRequest = null;
      _drawerCompleter = null;
    });

    return result;
  }

  void _closeDrawerUnsaved() {
    final completer = _drawerCompleter;
    if (completer == null || completer.isCompleted) return;

    final req = _drawerRequest;
    completer.complete(
      MemberFormResult(
        saved: false,
        name: req?.initialName,
        gender: req?.initialGender ?? Gender.female,
        details: req?.initialDetails ?? const MemberDetails(),
        birthday: req?.initialBirthday,
        clearBirthday: false,
        removePhoto: false,
        newPhotoBytes: null,
      ),
    );
  }

  void _saveDrawer(MemberFormResult result) {
    final completer = _drawerCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
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

  /// Correctly converts a global pointer position to the shifted container's local coordinates.
  Offset _globalToViewport(Offset global) {
    final box =
        _viewerContainerKey.currentContext?.findRenderObject() as RenderBox?;
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
    return bestDist <= _snapRadius ? bestId : null;
  }

  void _startLink({
    required int fromNodeId,
    required LinkPort port,
    required Offset startScene,
    required Offset startViewport,
  }) {
    setState(() {
      if (_previewMode) return;
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

    final beforePositions = Map<int, Offset>.from(_lastLayoutScene);

    setState(() {
      _isLinking = false;
      _linkFromNodeId = null;
      _linkPort = null;
      _hoverTargetId = null;
    });

    if (fromId == null || port == null || targetId == null) return;

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
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final afterPositions = Map<int, Offset>.from(_lastLayoutScene);

      for (final id in beforePositions.keys) {
        final before = beforePositions[id];
        final after = afterPositions[id];
        if (before == null || after == null) continue;

        final delta = before - after;
        if (delta.distance > 0.5) {
          store.addManualOffset(id, delta);
        }
      }
    });
  }

  Future<void> _handlePortTap(int nodeId, LinkPort port) async {
    if (_isLinking) return;
    if (_previewMode) return;

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
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will be signed out. Your saved tree will remain in the database.',
        ),
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

    if (!mounted || ok != true) return;

    try {
      await authService.value.signOut();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Logout failed: $e')));
      return;
    }

    if (!mounted) return;
    navigator.pushNamedAndRemoveUntil(LoginPage.route, (route) => false);
  }

Future<void> _applyFormToNode(int nodeId, MemberFormResult r) async {
  if (!r.saved) return;

  // 1. Update basic details immediately
  store.setGender(nodeId, r.gender);
  store.setDetails(nodeId, r.details);
  store.setBirthday(nodeId, r.clearBirthday ? null : r.birthday);

  if (r.removePhoto) {
    store.removePhoto(nodeId);
    return;
  }

  // 2. OPTIMISTIC UPDATE: Set local bytes immediately for instant preview
  if (r.newPhotoBytes != null) {
    setState(() {
      final node = store.getNode(nodeId);
      node.photoBytes = r.newPhotoBytes; // Show local version immediately
      node.photoUrl = null;             // Ensure widget uses bytes
    });

    // 3. Trigger background upload without 'awaiting' it for the UI
    _uploadPhotoBackground(nodeId, r.newPhotoBytes!);
  }
}

// Add this helper method to handle background upload
Future<void> _uploadPhotoBackground(int nodeId, Uint8List bytes) async {
  try {
    final photoUrl = await _cloudinary.uploadBytes(
      bytes,
      fileName: 'node_$nodeId.jpg',
    );
    if (mounted) {
      store.setPhotoUrl(nodeId, photoUrl); // Sync with cloud URL once done
    }
  } catch (e) {
    debugPrint('Background photo upload failed: $e');
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

    final r = await _openMemberFormDrawer(
      title: 'Edit Member Details',
      showNameField: true,
      initialName: n.name,
      initialGender: n.gender,
      allowedGenders: const [Gender.female, Gender.male],
      initialDetails: initial,
      initialBirthday: n.birthday,
      initialPhotoBytes: n.photoBytes,
      initialPhotoProvider: n.hasPhoto ? n.photoProvider : null,
      allowRemovePhoto: true,
      allowClearBirthday: true,
    );

    if (!mounted || !r.saved) return;

    final newName = (r.name ?? '').trim();
    if (newName.isNotEmpty && newName != n.name) {
      store.renameNode(nodeId, newName);
    }

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

    final messenger = ScaffoldMessenger.of(context);

    try {
      final url = await _cloudinary.uploadBytes(
        bytes,
        fileName: '${filePrefix}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      return url;
    } catch (e) {
      if (!mounted) return null;
      messenger.showSnackBar(
        SnackBar(content: Text('Photo upload failed: $e')),
      );
      return null;
    }
  }

  Future<void> _addFirstMemberFlow() async {
    final r = await _openMemberFormDrawer(
      title: 'Add Member Info',
      showNameField: true,
      initialName: 'New Member',
      initialGender: Gender.female,
      allowedGenders: const [Gender.female, Gender.male],
      allowRemovePhoto: false,
      allowClearBirthday: true,
    );
    if (!mounted || !r.saved) return;

    final name = (r.name ?? '').trim();
    if (name.isEmpty) return;

    final existingId = _findNodeByExactName(name);
    if (existingId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name already exists. Redirecting...')),
      );
      _focusNode(existingId);
      return;
    }

    final photoUrl = await _uploadPhotoIfNeeded(r.newPhotoBytes, 'member');
    if (!mounted) return;

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
    final r = await _openMemberFormDrawer(
      title: 'Add Member Info',
      showNameField: true,
      initialName: 'New Member',
      initialGender: Gender.female,
      allowedGenders: const [Gender.female, Gender.male],
      allowRemovePhoto: false,
      allowClearBirthday: true,
    );
    if (!mounted || !r.saved) return;

    final name = (r.name ?? '').trim();
    if (name.isEmpty) return;

    final existingId = _findNodeByExactName(name);
    if (existingId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name already exists. Redirecting...')),
      );
      _focusNode(existingId);
      return;
    }

    final photoUrl = await _uploadPhotoIfNeeded(r.newPhotoBytes, 'member');
    if (!mounted) return;

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

  Future<void> _showDetailsPopup({
    required int nodeId,
    required Offset globalTapPosition,
  }) async {
    final node = store.getNode(nodeId);

    final parentIds = node.parents.toList();
    final childrenIds = node.children.toList();

    final siblingIds = store.nodes.values
        .where((n) =>
            n.id != node.id &&
            n.parents.any((p) => node.parents.contains(p)))
        .map((n) => n.id)
        .toList();

    String? line(String label, String? value) {
      final v = (value ?? '').trim();
      if (v.isEmpty) return null;
      return '$label: $v';
    }

    final infoLines = <String>[
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

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    final position = RelativeRect.fromRect(
      Rect.fromLTWH(globalTapPosition.dx, globalTapPosition.dy, 1, 1),
      Offset.zero & overlay.size,
    );

    await showMenu<String>(
      context: context,
      position: position,
      color: Colors.transparent,
      elevation: 0,
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 340),
      items: [
        PopupMenuItem<String>(
          value: '__details__',
          enabled: false,
          padding: EdgeInsets.zero,
          child: Container(
            width: 320,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _TreeGreenTheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _TreeGreenTheme.border),
              boxShadow: [
                BoxShadow(
                  color: _TreeGreenTheme.shadow,
                  blurRadius: 18,
                  offset: const Offset(0, 8),
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
                      onTap: node.hasPhoto
                          ? () => _viewPhotoFullScreen(node)
                          : null,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: !node.hasPhoto ? node.gender.tone : null,
                          border: Border.all(color: _TreeGreenTheme.border),
                        ),
                        child: !node.hasPhoto
                            ? Icon(node.gender.icon,
                                size: 26, color: _TreeGreenTheme.textMuted)
                            : ClipOval(
                                child: Image(
                                  image: node.photoProvider,
                                  fit: BoxFit.cover,
                                ),
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
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(node.gender.icon,
                                  size: 14, color: _TreeGreenTheme.textMuted),
                              const SizedBox(width: 4),
                              Text(
                                node.gender.label,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _TreeGreenTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                if (parentIds.isNotEmpty)
                  buildClickableRelation(label: 'Parents', ids: parentIds),

                if (siblingIds.isNotEmpty)
                  buildClickableRelation(label: 'Siblings', ids: siblingIds),

                if (childrenIds.isNotEmpty)
                  buildClickableRelation(label: 'Children', ids: childrenIds),

                if (parentIds.isNotEmpty ||
                    siblingIds.isNotEmpty ||
                    childrenIds.isNotEmpty)
                  const SizedBox(height: 6),

                if (infoLines.isEmpty)
                  const Text(
                    'No additional details provided.',
                    style: TextStyle(color: _TreeGreenTheme.textMuted),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.4,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final t in infoLines)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                t,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openNodeActions({
    required int nodeId,
    required Offset globalTapPosition,
  }) async {
    if (_ctrlSelectedIds.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selection active. Ctrl+Click tiles to unselect first.')),
      );
      return;
    }

    if (!store.canEditNodeId(nodeId)) {
      await _showDetailsPopup(
        nodeId: nodeId,
        globalTapPosition: globalTapPosition,
      );
      return;
    }

    final node = store.getNode(nodeId);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    final position = RelativeRect.fromRect(
      Rect.fromLTWH(globalTapPosition.dx, globalTapPosition.dy, 1, 1),
      Offset.zero & overlay.size,
    );

    final selected = await showMenu<String>(
      context: context,
      position: position,
      color: Colors.transparent,
      elevation: 0,
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 340),
      items: [
        PopupMenuItem<String>(
          value: '__actions__',
          enabled: false,
          padding: EdgeInsets.zero,
          child: Container(
            width: 320,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _TreeGreenTheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _TreeGreenTheme.border),
              boxShadow: [
                BoxShadow(
                  color: _TreeGreenTheme.shadow,
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: node.hasPhoto ? () => _viewPhotoFullScreen(node) : null,
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: !node.hasPhoto ? node.gender.tone : null,
                          border: Border.all(color: _TreeGreenTheme.border, width: 1),
                        ),
                        child: !node.hasPhoto
                            ? Icon(node.gender.icon, size: 24, color: _TreeGreenTheme.textMuted)
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
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(node.gender.icon, size: 14, color: _TreeGreenTheme.textMuted),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  node.gender.label,
                                  style: TextStyle(
                                    color: _TreeGreenTheme.textMuted,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (node.birthday != null) ...[
                                const SizedBox(width: 8),
                                const Icon(Icons.cake_outlined, size: 14),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    formatDate(node.birthday!),
                                    style: TextStyle(
                                      color: _TreeGreenTheme.textMuted,
                                      fontSize: 12,
                                    ),
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
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _PopupActionButton(
                      icon: Icons.badge_outlined,
                      label: 'Edit Details',
                      color: _TreeGreenTheme.actionBlue,
                      onTap: () => Navigator.pop(context, 'details'),
                    ),
                    _PopupActionButton(
                      icon: Icons.favorite,
                      label: 'Add Spouse',
                      color: _TreeGreenTheme.actionPink,
                      enabled: node.spouses.isEmpty,
                      onTap: () => Navigator.pop(context, 'spouse'),
                    ),
                    _PopupActionButton(
                      icon: Icons.person,
                      label: 'Add Parent',
                      color: _TreeGreenTheme.actionPurple,
                      enabled: node.parents.length < 2,
                      onTap: () => Navigator.pop(context, 'parent'),
                    ),
                    _PopupActionButton(
                      icon: Icons.boy,
                      label: 'Add Son',
                      color: _TreeGreenTheme.actionTeal,
                      onTap: () => Navigator.pop(context, 'son'),
                    ),
                    _PopupActionButton(
                      icon: Icons.girl,
                      label: 'Add Daughter',
                      color: _TreeGreenTheme.actionTeal,
                      onTap: () => Navigator.pop(context, 'daughter'),
                    ),
                    _PopupActionButton(
                      icon: Icons.delete,
                      label: 'Delete',
                      color: Colors.red,
                      onTap: () => Navigator.pop(context, 'delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );

    if (!mounted || selected == null) return;

    switch (selected) {
      case 'details':
        await _editDetailsFlow(nodeId);
        break;
      case 'spouse':
        await _addSpouseFlow(personId: nodeId);
        break;
      case 'parent':
        await _addParentFlow(personId: nodeId);
        break;
      case 'son':
        await _addSonFlow(fromNodeId: nodeId);
        break;
      case 'daughter':
        await _addDaughterFlow(fromNodeId: nodeId);
        break;
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (dctx) => AlertDialog(
            title: const Text('Delete member?'),
            content: const Text('This will remove the member and all related links.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () => Navigator.pop(dctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );

        if (ok == true && mounted) {
    setState(() {
      store.deleteNode(nodeId);
    });
  }
        break;
    }
  }

  Future<void> _addSpouseFlow({required int personId}) async {
    final messenger = ScaffoldMessenger.of(context);
    final person = store.getNode(personId);

    if (person.spouses.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text('${person.name} already has a spouse.')),
      );
      return;
    }

    if (store.hasCoParentViaChildren(personId)) {
      messenger.showSnackBar(
        SnackBar(content: Text('${person.name} already has a co-parent.')),
      );
      return;
    }

    final spouseGender = person.gender.opposite;

    final r = await _openMemberFormDrawer(
      title: 'Add Spouse Info',
      showNameField: true,
      initialName: 'New Spouse',
      initialGender: spouseGender,
      allowedGenders: [spouseGender],
      allowRemovePhoto: false,
      allowClearBirthday: true,
    );
    if (!mounted || !r.saved) return;

    final name = (r.name ?? '').trim();
    if (name.isEmpty) return;

    final existingId = _findNodeByExactName(name);
    if (existingId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name already exists. Redirecting...')),
      );
      _focusNode(existingId);
      return;
    }

    final photoUrl = await _uploadPhotoIfNeeded(r.newPhotoBytes, 'spouse');
    if (!mounted) return;

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
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not add spouse.')),
      );
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final person = store.getNode(personId);
      final isMale = person.gender == Gender.male;
      _placeNear(
        added.id,
        personId,
        Offset(
          isMale ? cardSize.width + 40 : -(cardSize.width + 40),
          0,
        ),
      );
    });
  }

  Future<void> _addParentFlow({required int personId}) async {
    final messenger = ScaffoldMessenger.of(context);
    final person = store.getNode(personId);

    if (person.parents.length >= 2) {
      messenger.showSnackBar(
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
      messenger.showSnackBar(
        SnackBar(content: Text('${person.name} already has 2 parents.')),
      );
      return;
    }

    final r = await _openMemberFormDrawer(
      title: 'Add Parent Info',
      showNameField: true,
      initialName: 'New Parent',
      initialGender: options.first,
      allowedGenders: options,
      allowRemovePhoto: false,
      allowClearBirthday: true,
    );
    if (!mounted || !r.saved) return;

    final name = (r.name ?? '').trim();
    if (name.isEmpty) return;

    final existingId = _findNodeByExactName(name);
    if (existingId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name already exists. Redirecting...')),
      );
      _focusNode(existingId);
      return;
    }

    final photoUrl = await _uploadPhotoIfNeeded(r.newPhotoBytes, 'parent');
    if (!mounted) return;

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
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not add parent (blocked).')),
      );
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _placeNear(
        added.id,
        personId,
        Offset(0, -(cardSize.height + 40)),
      );
    });
  }

  Future<void> _addChildFlow({required int fromNodeId}) async {
    final r = await _openMemberFormDrawer(
      title: 'Add Child Info',
      showNameField: true,
      initialName: 'New Child',
      initialGender: Gender.female,
      allowedGenders: const [Gender.female, Gender.male],
      allowRemovePhoto: false,
      allowClearBirthday: true,
    );
    if (!mounted || !r.saved) return;

    final name = (r.name ?? '').trim();
    if (name.isEmpty) return;

    final existingId = _findNodeByExactName(name);
    if (existingId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name already exists. Redirecting...')),
      );
      _focusNode(existingId);
      return;
    }

    final photoUrl = await _uploadPhotoIfNeeded(r.newPhotoBytes, 'child');
    if (!mounted) return;

    final child = store.addChild(
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _placeNear(
        child.id,
        fromNodeId,
        Offset(0, cardSize.height + 40),
      );
    });
  }

  Future<void> _addSonFlow({required int fromNodeId}) async {
    await _addChildWithGender(
      fromNodeId: fromNodeId,
      gender: Gender.male,
      title: 'Add Son',
    );
  }

  Future<void> _addDaughterFlow({required int fromNodeId}) async {
    await _addChildWithGender(
      fromNodeId: fromNodeId,
      gender: Gender.female,
      title: 'Add Daughter',
    );
  }

  Future<void> _addChildWithGender({
    required int fromNodeId,
    required Gender gender,
    required String title,
  }) async {
    final r = await _openMemberFormDrawer(
      title: title,
      showNameField: true,
      initialName: gender == Gender.male ? 'New Son' : 'New Daughter',
      initialGender: gender,
      allowedGenders: [gender],
      allowRemovePhoto: false,
      allowClearBirthday: true,
    );

    if (!mounted || !r.saved) return;

    final name = (r.name ?? '').trim();
    if (name.isEmpty) return;

    final existingId = _findNodeByExactName(name);
    if (existingId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name already exists. Redirecting...')),
      );
      _focusNode(existingId);
      return;
    }

    final photoUrl = await _uploadPhotoIfNeeded(r.newPhotoBytes, 'child');
    if (!mounted) return;

    final child = store.addChild(
      fromNodeId: fromNodeId,
      name: name,
      childGender: gender,
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _placeNear(
        child.id,
        fromNodeId,
        Offset(0, cardSize.height + 40),
      );
    });
  }

  // New method: focus on the topmost node at zoom 1.0
  void _focusOnTopNode() {
    if (_lastLayoutScene.isEmpty) return;

    // Find the node with the smallest Y (topmost)
    int? topNodeId;
    double minY = double.infinity;
    for (final e in _lastLayoutScene.entries) {
      if (e.value.dy < minY) {
        minY = e.value.dy;
        topNodeId = e.key;
      }
    }

    if (topNodeId == null) return;

    final pos = _lastLayoutScene[topNodeId]!;
    final screenSize = MediaQuery.of(context).size;
    final viewportCenter = Offset(screenSize.width / 2, screenSize.height / 2);
    final nodeCenter = pos + Offset(cardSize.width / 2, cardSize.height / 2);

    _syncingFromController = true;
    _tc.value = Matrix4.identity()
      ..translate(viewportCenter.dx, viewportCenter.dy)
      ..scale(1.0) // reset zoom to 1.0
      ..translate(-nodeCenter.dx, -nodeCenter.dy);
    _syncingFromController = false;

    setState(() => _zoomValue = 1.0);
  }

  @override
  Widget build(BuildContext context) {
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

    // No auto-fit anymore; focus on top node if not done yet
    if (!_didInitialCenter && layout.isNotEmpty) {
      _didInitialCenter = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusOnTopNode(); // replaces _fitToScreen(bounds)
      });
    }

    final canvasSize = const Size(virtualSize, virtualSize);
    final isEmpty = store.nodes.isEmpty;

    // --- Responsive drawer width ---
    final screenWidth = MediaQuery.of(context).size.width;
    final drawerWidth = min(_maxDrawerWidth, screenWidth);

    return Scaffold(
      backgroundColor: _TreeGreenTheme.scaffold,
      // No AppBar
      body: Stack(
        children: [
          // ===== SHIFTING AREA =====
          AnimatedPositioned(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutQuart,
            left: _isDrawerOpen ? drawerWidth : 0,
            top: 0,
            right: 0,
            bottom: 0,
            child: Stack(
              key: _viewerContainerKey,
              children: [
                // Tree and interactions
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
                          // ── Watermark: lives inside the virtual canvas so
                          //    it pans/zooms with the nodes. ImageShader means
                          //    one GPU draw call; Skia only rasterizes the
                          //    visible clip region — no loop, no lag.
                          if (_watermarkTile != null)
                            CustomPaint(
                              size: canvasSize,
                              painter: _WatermarkPainter(_watermarkTile!),
                            ),
                          // Single connector layer: ValueListenableBuilder merges
                          // live drag positions over the base layout so the
                          // static ghost line is never visible.
                          if (!isEmpty)
                            _LiveConnectorOverlay(
                              store: store,
                              basePositions: layout,
                              dragOverlayNotifier: _dragOverlayNotifier,
                              cardSize: cardSize,
                              canvasSize: canvasSize,
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
                              // Mark nodes as dragging: the dragged node itself, plus any ctrl-selected
                              // When isDragging=true, AnimatedPositioned uses Duration.zero for instant updates
                              isDragging: _draggingNodeId != null &&
                                  (_ctrlSelectedIds.contains(entry.key) || _draggingNodeId == entry.key),
                              dragEnabled: !_isLinking && !_previewMode,
                              showPortsEnabled: !_previewMode && store.canEditNodeId(entry.key),
                              zoomScale: _zoomValue,
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
                              onTapSelect: (id, globalPosition) {
                                if (_previewMode) {
                                  _showDetailsPopup(
                                    nodeId: id,
                                    globalTapPosition: globalPosition,
                                  );
                                  return;
                                }

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

                                _openNodeActions(
                                  nodeId: id,
                                  globalTapPosition: globalPosition,
                                );
                              },
                              dragOverlayNotifier: _dragOverlayNotifier,
                              onDragStart: () {
                                if (_isLinking) return;
                                // Mark as dragging — only triggers one setState here
                                setState(() => _draggingNodeId = entry.key);
                                if (_ctrlPressed && !_ctrlSelectedIds.contains(entry.key)) {
                                  _toggleCtrlSelect(entry.key);
                                }
                              },
                              onDragEnd: () {
                                if (!mounted) return;
                                setState(() => _draggingNodeId = null);
                              },
                              onDragAccumulated: (totalDelta) {
                                if (_isLinking) return;
                                final draggedId = entry.key;

                                // Handle single vs. multiple selected nodes
                                final ids = (_ctrlSelectedIds.isNotEmpty &&
                                        _ctrlSelectedIds.contains(draggedId))
                                    ? _ctrlSelectedIds
                                    : <int>{draggedId};

                                // Commit to store only once per drag gesture — no per-frame rebuilds
                                if (ids.length == 1) {
                                  store.addManualOffset(draggedId, totalDelta);
                                } else {
                                  store.addManualOffsetBulk(ids, totalDelta);
                                }
                              },
                              onStartPortDrag: (port, globalStart) {
                                final topLeft = layout[entry.key]!;
                                final startScene = switch (port) {
                                  LinkPort.parentTop =>
                                    Offset(topLeft.dx + cardSize.width / 2, topLeft.dy),
                                  LinkPort.childBottom => Offset(
                                      topLeft.dx + cardSize.width / 2,
                                      topLeft.dy + cardSize.height,
                                    ),
                                  LinkPort.spouseLeft =>
                                    Offset(topLeft.dx, topLeft.dy + cardSize.height / 2),
                                  LinkPort.spouseRight => Offset(
                                      topLeft.dx + cardSize.width,
                                      topLeft.dy + cardSize.height / 2,
                                    ),
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

                // Link dragging preview
                if (_isLinking)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: LinkPreviewPainter(
                          start: _sceneToViewport(_linkStartScene),
                          end: _hoverTargetId != null
                              ? _snappedEndViewport
                              : _linkCurrentViewport,
                        ),
                      ),
                    ),
                  ),

                // Loading / Empty state
                if (_isLoading)
                  const Center(child: CircularProgressIndicator( color: Colors.green,))
                else if (isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Material(
                        elevation: 2,
                        borderRadius: BorderRadius.circular(18),
                        color: _TreeGreenTheme.surface,
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
                              const Text(
                                'Add your first member to begin.',
                                style: TextStyle(color: _TreeGreenTheme.textMuted),
                              ),
                              const SizedBox(height: 14),
                              FilledButton.icon(
  style: FilledButton.styleFrom(
    backgroundColor: _TreeGreenTheme.primary,    // green background
    foregroundColor: Colors.white,               // white text/icon
  ),
  onPressed: _addFirstMemberFlow,
  icon: const Icon(Icons.person_add),
  label: const Text('Add First Member'),
)
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Zoom controls & add standalone button (bottom right)
                if (!isEmpty)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: Material(
                      elevation: 2,
                      color: _TreeGreenTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Zoom out',
                              icon: const Icon(Icons.remove, size: 18),
                              onPressed: () {
                                final next = (_zoomValue / 1.15).clamp(_minZoom, _maxZoom);
                                _setZoom(next);
                              },
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Zoom in',
                              icon: const Icon(Icons.add, size: 18),
                              onPressed: () {
                                final next = (_zoomValue * 1.15).clamp(_minZoom, _maxZoom);
                                _setZoom(next);
                              },
                            ),
                            const SizedBox(width: 8),
                            Container(width: 1, height: 22, color: _TreeGreenTheme.divider),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Add standalone member',
                              icon: const Icon(Icons.person_add_alt_1, size: 18),
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                              padding: const EdgeInsets.all(8),
                              onPressed: _addStandaloneMemberFlow,
                            ),
                            IconButton(
                              tooltip: _previewMode ? 'Exit Preview Mode' : 'Preview Mode',
                              icon: Icon(
                                _previewMode ? Icons.visibility_off : Icons.visibility,
                                size: 18,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                              padding: const EdgeInsets.all(8),
                              onPressed: () {
                                setState(() {
                                  _previewMode = !_previewMode;
                                });
                              },
                            ),
                            IconButton(
                              tooltip: 'Log out',
                              icon: const Icon(Icons.logout, size: 18),
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                              padding: const EdgeInsets.all(8),
                              onPressed: _logout,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // ===== FLOATING SEARCH BAR (top right) =====
                if (!isEmpty)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Material(
                      elevation: 2,
                      color: _TreeGreenTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        width: 250,
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search member...',
                            prefixIcon: const Icon(Icons.search, color: _TreeGreenTheme.textMuted),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {});
                                    },
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: _TreeGreenTheme.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: _TreeGreenTheme.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: _TreeGreenTheme.primary, width: 1.4),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 14),
                          onSubmitted: _handleSearch,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ===== SIDEBAR (does not shift) =====
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: drawerWidth,
            child: IgnorePointer(
              ignoring: !_isDrawerOpen || _drawerRequest == null,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutQuart,
                offset: _isDrawerOpen && _drawerRequest != null
                    ? Offset.zero
                    : const Offset(-1.0, 0),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  opacity: _isDrawerOpen && _drawerRequest != null ? 1 : 0,
                  child: Material(
                    elevation: 16,
                    shadowColor: _TreeGreenTheme.shadow,
                    color: _TreeGreenTheme.surface,
                    child: SafeArea(
                      child: _drawerRequest == null
                          ? const SizedBox.shrink()
                          : _MemberFormSidebar(
                              title: _drawerRequest!.title,
                              showNameField: _drawerRequest!.showNameField,
                              initialName: _drawerRequest!.initialName,
                              initialGender: _drawerRequest!.initialGender,
                              allowedGenders: _drawerRequest!.allowedGenders,
                              initialDetails: _drawerRequest!.initialDetails,
                              initialBirthday: _drawerRequest!.initialBirthday,
                              initialPhotoBytes: _drawerRequest!.initialPhotoBytes,
                              initialPhotoProvider: _drawerRequest!.initialPhotoProvider,
                              allowRemovePhoto: _drawerRequest!.allowRemovePhoto,
                              allowClearBirthday: _drawerRequest!.allowClearBirthday,
                              onCancel: _closeDrawerUnsaved,
                              onSave: _saveDrawer,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Removed _computeBounds and _fitToScreen as they are no longer used
}

// The rest of the file remains the same: _MemberFormSidebar, AnimatedNode, MemberCard, etc.
// Include them exactly as provided in the previous full code.
// (Repeated below for completeness)

/* =========================
   Drawer form
   ========================= */

class _MemberFormSidebar extends StatefulWidget {
  const _MemberFormSidebar({
    required this.title,
    required this.showNameField,
    required this.initialName,
    required this.initialGender,
    required this.allowedGenders,
    required this.initialDetails,
    required this.initialBirthday,
    required this.initialPhotoBytes,
    required this.initialPhotoProvider,
    required this.allowRemovePhoto,
    required this.allowClearBirthday,
    required this.onCancel,
    required this.onSave,
  });

  final String title;
  final bool showNameField;
  final String? initialName;
  final Gender initialGender;
  final List<Gender> allowedGenders;
  final MemberDetails initialDetails;
  final DateTime? initialBirthday;
  final Uint8List? initialPhotoBytes;
  final ImageProvider? initialPhotoProvider;
  final bool allowRemovePhoto;
  final bool allowClearBirthday;
  final VoidCallback onCancel;
  final ValueChanged<MemberFormResult> onSave;

  @override
  State<_MemberFormSidebar> createState() => _MemberFormSidebarState();
}

class _MemberFormSidebarState extends State<_MemberFormSidebar> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _phoneController;
  late final TextEditingController _companyController;
  late final TextEditingController _jobTitleController;
  late final TextEditingController _fbController;
  late final TextEditingController _igController;
  late final TextEditingController _xController;
  late final TextEditingController _tiktokController;

  late Gender _gender;
  DateTime? _birthday;
  bool _clearBirthday = false;
  bool _removePhoto = false;
  Uint8List? _newPhotoBytes;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _addressController = TextEditingController(text: widget.initialDetails.address ?? '');
    _phoneController = TextEditingController(text: widget.initialDetails.phone ?? '');
    _companyController = TextEditingController(text: widget.initialDetails.company ?? '');
    _jobTitleController = TextEditingController(text: widget.initialDetails.jobTitle ?? '');
    _fbController = TextEditingController(text: widget.initialDetails.fb ?? '');
    _igController = TextEditingController(text: widget.initialDetails.ig ?? '');
    _xController = TextEditingController(text: widget.initialDetails.xAccount ?? '');
    _tiktokController = TextEditingController(text: widget.initialDetails.tiktok ?? '');
    _gender = widget.initialGender;
    _birthday = widget.initialBirthday;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _companyController.dispose();
    _jobTitleController.dispose();
    _fbController.dispose();
    _igController.dispose();
    _xController.dispose();
    _tiktokController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1800,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (!mounted) return;

      setState(() {
        _newPhotoBytes = bytes;
        _removePhoto = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not pick photo: $e')),
      );
    }
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final initial = _birthday ?? DateTime(now.year - 20, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1800),
      lastDate: now,
    );

    if (picked == null) return;

    setState(() {
      _birthday = picked;
      _clearBirthday = false;
    });
  }

  InputDecoration _dec(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _TreeGreenTheme.textMuted),
      prefixIconConstraints: const BoxConstraints(minWidth: 42),
      prefixIcon: icon != null ? Icon(icon, size: 18, color: _TreeGreenTheme.primary) : null,
      filled: true,
      fillColor: _TreeGreenTheme.softSurface,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _TreeGreenTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _TreeGreenTheme.primary, width: 1.4),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      isDense: true,
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final details = MemberDetails(
      address: _addressController.text.trim(),
      phone: _phoneController.text.trim(),
      company: _companyController.text.trim(),
      jobTitle: _jobTitleController.text.trim(),
      fb: _fbController.text.trim(),
      ig: _igController.text.trim(),
      xAccount: _xController.text.trim(),
      tiktok: _tiktokController.text.trim(),
    );

    widget.onSave(
      MemberFormResult(
        saved: true,
        name: widget.showNameField ? _nameController.text.trim() : null,
        gender: _gender,
        details: details,
        birthday: _clearBirthday ? null : _birthday,
        clearBirthday: _clearBirthday,
        removePhoto: _removePhoto,
        newPhotoBytes: _removePhoto ? null : _newPhotoBytes,
      ),
    );
  }

  Widget _buildPhotoPreview() {
    if (_removePhoto) {
      return Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          color: _TreeGreenTheme.softSurface,
          shape: BoxShape.circle,
          border: Border.all(color: _TreeGreenTheme.border),
        ),
        child: const Icon(Icons.person_outline, size: 34),
      );
    }

    if (_newPhotoBytes != null) {
      return Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _TreeGreenTheme.border),
          image: DecorationImage(
            image: MemoryImage(_newPhotoBytes!),
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    if (widget.initialPhotoBytes != null) {
      return Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _TreeGreenTheme.border),
          image: DecorationImage(
            image: MemoryImage(widget.initialPhotoBytes!),
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    if (widget.initialPhotoProvider != null) {
      return Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _TreeGreenTheme.border),
          image: DecorationImage(
            image: widget.initialPhotoProvider!,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        color: _TreeGreenTheme.softSurface,
        shape: BoxShape.circle,
        border: Border.all(color: _TreeGreenTheme.border),
      ),
      child: Icon(_gender.icon, size: 34, color: _TreeGreenTheme.textMuted),
    );
  }

  @override
  Widget build(BuildContext context) {
    final birthdayText = _clearBirthday
        ? 'No birthday'
        : (_birthday != null ? formatDate(_birthday!) : 'Select birthday');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: widget.onCancel,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Center(child: _buildPhotoPreview()),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [OutlinedButton.icon(
  style: OutlinedButton.styleFrom(
    foregroundColor: _TreeGreenTheme.primary,   // changes icon + text color
    side: const BorderSide(color: _TreeGreenTheme.primary),
  ),
  onPressed: _pickPhoto,
  icon: const Icon(Icons.photo_library_outlined),
  label: const Text('Choose Photo'),
),
                    if (widget.allowRemovePhoto)
                      OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _removePhoto = true;
                            _newPhotoBytes = null;
                          });
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Remove Photo'),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                if (widget.showNameField) ...[
                  TextFormField(
                    controller: _nameController,
                    decoration: _dec('Name', icon: Icons.person_outline),
                    validator: (v) {
                      if (!widget.showNameField) return null;
                      if ((v ?? '').trim().isEmpty) return 'Name is required';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                ],
                DropdownButtonFormField<Gender>(
                  value: _gender,
                  decoration: _dec('Gender', icon: Icons.wc),
                  items: widget.allowedGenders
                      .map(
                        (g) => DropdownMenuItem<Gender>(
                          value: g,
                          child: Text(g.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _gender = value);
                  },
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: _pickBirthday,
                  borderRadius: BorderRadius.circular(14),
                  child: InputDecorator(
                    decoration: _dec('Birthday', icon: Icons.cake_outlined),
                    child: Row(
                      children: [
                        Expanded(child: Text(birthdayText)),
                        const Icon(Icons.calendar_month_outlined, size: 18),
                      ],
                    ),
                  ),
                ),
                if (widget.allowClearBirthday) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _clearBirthday,
                    title: const Text('Clear birthday'),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) {
                      setState(() {
                        _clearBirthday = v ?? false;
                      });
                    },
                  ),
                ],
                const SizedBox(height: 8),
                TextFormField(
                  controller: _addressController,
                  decoration: _dec('Address', icon: Icons.home_outlined),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phoneController,
                  decoration: _dec('Phone', icon: Icons.phone_outlined),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _companyController,
                  decoration: _dec('Company', icon: Icons.business_outlined),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _jobTitleController,
                  decoration: _dec('Job Title', icon: Icons.badge_outlined),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _fbController,
                  decoration: _dec('Facebook', icon: Icons.facebook),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _igController,
                  decoration: _dec('Instagram', icon: Icons.camera_alt_outlined),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _xController,
                  decoration: _dec('X', icon: Icons.alternate_email),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _tiktokController,
                  decoration: _dec('TikTok', icon: Icons.music_note_outlined),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: _TreeGreenTheme.surface,
            boxShadow: [
              BoxShadow(
                color: _TreeGreenTheme.shadow.withAlpha(18),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
  style: OutlinedButton.styleFrom(
    foregroundColor: _TreeGreenTheme.primary,
    side: const BorderSide(color: _TreeGreenTheme.primary),
  ),
  onPressed: widget.onCancel,
  child: const Text('Cancel'),
),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
  style: FilledButton.styleFrom(
    backgroundColor: _TreeGreenTheme.primary,
    foregroundColor: Colors.white,
  ),
  onPressed: _submit,
  icon: const Icon(Icons.save_outlined),
  label: const Text('Save'),
)
              ),
            ],
          ),
        ),
      ],
    );
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
    required this.onDragAccumulated,
    required this.onDragStart,
    required this.onDragEnd,
    this.dragOverlayNotifier,
    required this.onStartPortDrag,
    required this.onUpdatePortDrag,
    required this.onEndPortDrag,
    required this.onTapPort,
    required this.isHovered,
    required this.isSelected,
    required this.isDragging,
    required this.onHoverChanged,
    required this.dragEnabled,
    required this.showPortsEnabled,
    this.zoomScale = 1.0,
  });

  final FamilyNode node;
  final Offset topLeft;
  final Size size;

  final void Function(int id, Offset globalPosition) onTapSelect;

  /// Called once on drag-end with the total accumulated delta (scene-space).
  /// The parent commits it to the store only at this point, avoiding a full
  /// rebuild + layout recompute on every pointer event.
  final ValueChanged<Offset> onDragAccumulated;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;

  /// Notifier updated every pointer frame so the connector painter can
  /// follow the dragged node without rebuilding anything else.
  final ValueNotifier<Map<int, Offset>>? dragOverlayNotifier;

  final void Function(LinkPort port, Offset globalStart) onStartPortDrag;
  final void Function(Offset globalPos) onUpdatePortDrag;
  final void Function(Offset globalPos) onEndPortDrag;

  final void Function(int nodeId, LinkPort port) onTapPort;

  final bool isHovered;
  final bool isSelected;
  final bool isDragging;
  final ValueChanged<bool> onHoverChanged;
  final bool dragEnabled;
  final bool showPortsEnabled;

  /// Current zoom level from TransformationController.
  /// Used to convert screen-space drag deltas to scene-space.
  final double zoomScale;

  @override
  State<AnimatedNode> createState() => _AnimatedNodeState();
}

class _AnimatedNodeState extends State<AnimatedNode> {
  Offset? _hoverLocal;

  // Per-node position notifier: only the Positioned widget listens to this,
  // so moving a node costs zero rebuilds of its children or siblings.
  late final ValueNotifier<Offset> _posNotifier =
      ValueNotifier(widget.topLeft);

  // Accumulated scene-space delta for the current gesture.
  Offset _localDrag = Offset.zero;

  @override
  void didUpdateWidget(AnimatedNode old) {
    super.didUpdateWidget(old);
    // After drag commits to store, topLeft changes. Snap the notifier to
    // the new layout position (only runs once per gesture, not per frame).
    if (!widget.isDragging) {
      _posNotifier.value = widget.topLeft;
    }
  }

  @override
  void dispose() {
    _posNotifier.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails _) {
    _localDrag = Offset.zero;
    widget.onDragStart();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    // DragUpdateDetails.delta is always in *screen* pixels.
    // Divide by zoom so the node tracks the pointer 1-to-1 in scene space.
    final zoom = widget.zoomScale;
    final sceneDelta = zoom > 0 ? d.delta / zoom : d.delta;
    _localDrag += sceneDelta;

    // Update only the Positioned — no setState, no widget rebuild.
    _posNotifier.value = widget.topLeft + _localDrag;

    // Update shared connector notifier (mutate in place, then reassign
    // so ValueListenableBuilder detects the change).
    final n = widget.dragOverlayNotifier;
    if (n != null) {
      n.value[widget.node.id] = _posNotifier.value;
      n.value = n.value;
    }
  }

  void _onPanEnd(DragEndDetails _) {
    final committed = _localDrag;
    _localDrag = Offset.zero;

    // Remove this node from the live overlay.
    final n = widget.dragOverlayNotifier;
    if (n != null) {
      n.value = Map<int, Offset>.from(n.value)..remove(widget.node.id);
    }

    // Commit to store once. This triggers a parent build → didUpdateWidget
    // which snaps _posNotifier to the final layout position.
    widget.onDragAccumulated(committed);
    widget.onDragEnd();
  }

  @override
  Widget build(BuildContext context) {
    final lifted = widget.isHovered || widget.isSelected || widget.isDragging;

    return ValueListenableBuilder<Offset>(
      valueListenable: _posNotifier,
      // `child` is built once and reused — MemberCard never rebuilds during drag.
      child: MouseRegion(
        onEnter: (_) => widget.onHoverChanged(true),
        onExit: (_) {
          setState(() => _hoverLocal = null);
          widget.onHoverChanged(false);
        },
        onHover: (e) => setState(() => _hoverLocal = e.localPosition),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          scale: lifted ? 1.015 : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _TreeGreenTheme.shadow.withAlpha(lifted ? 38 : 18),
                  blurRadius: lifted ? 18 : 8,
                  offset: Offset(0, lifted ? 8 : 3),
                ),
              ],
            ),
            child: GestureDetector(
              onTapUp: (details) => widget.onTapSelect(
                widget.node.id,
                details.globalPosition,
              ),
              onPanStart: widget.dragEnabled ? _onPanStart : null,
              onPanUpdate: widget.dragEnabled ? _onPanUpdate : null,
              onPanEnd:   widget.dragEnabled ? _onPanEnd   : null,
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
        ),
      ),
      builder: (_, pos, child) => Positioned(
        left: pos.dx,
        top: pos.dy,
        width: widget.size.width,
        height: widget.size.height,
        child: child!,
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
        border: isSelected ? Border.all(color: _TreeGreenTheme.selection, width: 2) : null,
      ),
      child: Material(
        elevation: 2,
        shadowColor: _TreeGreenTheme.shadow,
        borderRadius: BorderRadius.circular(16),
        color: _TreeGreenTheme.surface,
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
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.visible,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (node.birthday != null) ...[
                            const SizedBox(height: 2),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.cake,
                                  size: 14,
                                  color: _TreeGreenTheme.textMuted,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    formatDate(node.birthday!),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: _TreeGreenTheme.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
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

class _PopupActionButton extends StatelessWidget {
  const _PopupActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final bg = enabled ? color.withAlpha(31) : _TreeGreenTheme.softSurface;
    final fg = enabled ? color : _TreeGreenTheme.textMuted;

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 135,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: enabled ? color.withAlpha(51) : _TreeGreenTheme.border,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: fg, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
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
      ..color = _TreeGreenTheme.accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    final ctrl = Offset(mid.dx, min(start.dy, end.dy) - 40);

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);

    canvas.drawPath(path, paint);
    canvas.drawCircle(end, 4.5, Paint()..color = _TreeGreenTheme.accent);
  }

  @override
  bool shouldRepaint(covariant LinkPreviewPainter oldDelegate) {
    return oldDelegate.start != start || oldDelegate.end != end;
  }
}

// ─── Live connector overlay ───────────────────────────────────────────────────
//
// Listens to [dragOverlayNotifier] and repaints only the connector lines that
// need to move during a drag — without touching any node widgets or running
// FamilyTreeLayout.compute().
//
class _LiveConnectorOverlay extends StatelessWidget {
  const _LiveConnectorOverlay({
    required this.store,
    required this.basePositions,
    required this.dragOverlayNotifier,
    required this.cardSize,
    required this.canvasSize,
  });

  final FamilyTreeStore store;
  final Map<int, Offset> basePositions;
  final ValueNotifier<Map<int, Offset>> dragOverlayNotifier;
  final Size cardSize;
  final Size canvasSize;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<int, Offset>>(
      valueListenable: dragOverlayNotifier,
      builder: (_, livePositions, __) {
        // Always render: when nothing is dragging, livePositions is empty and
        // merged == basePositions. When dragging, live positions override the
        // stale base positions so no ghost line appears.
        final merged = livePositions.isEmpty
            ? basePositions
            : {...basePositions, ...livePositions};
        return CustomPaint(
          size: canvasSize,
          painter: ConnectorPainter(
            store: store,
            positions: merged,
            cardSize: cardSize,
          ),
        );
      },
    );
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
      ..color = _TreeGreenTheme.connector
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final spousePaint = Paint()
      ..color = _TreeGreenTheme.connector
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

      final parentIds = <int>[
        if (femaleP != null) femaleP,
        if (maleP != null) maleP,
      ]..sort();

      if (parentIds.length == 1) {
        final onlyParentId = parentIds.first;
        final onlyParent = store.nodes[onlyParentId];

        if (onlyParent != null && onlyParent.spouses.isNotEmpty) {
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
            style: TextStyle(fontSize: 12, color: _TreeGreenTheme.connector),
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

// ─── Watermark painter ────────────────────────────────────────────────────────
//
// Uses ui.ImageShader with TileMode.repeated — a single GPU draw call.
// Spacing between logos is baked into the tile image itself (transparent
// padding), so there's nothing to loop over here.
//
class _WatermarkPainter extends CustomPainter {
  const _WatermarkPainter(this.tile);

  final ui.Image tile;

  static const double _opacity = 0.07;

  @override
  void paint(Canvas canvas, Size size) {
    // The shader matrix maps tile pixels 1-to-1 to canvas (scene) pixels.
    // Because the tile already contains the logo + padding, the GPU repeats
    // it perfectly across the entire 100 000 × 100 000 virtual canvas.
    final shader = ui.ImageShader(
      tile,
      TileMode.repeated,
      TileMode.repeated,
      Matrix4.identity().storage,
    );

    // saveLayer applies opacity cheaply in one composite pass.
    canvas.saveLayer(
      Offset.zero & size,
      // ignore: deprecated_member_use
      Paint()..color = const Color(0xFFFFFFFF).withOpacity(_opacity),
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WatermarkPainter old) => old.tile != tile;
}