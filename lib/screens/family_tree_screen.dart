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
import 'package:url_launcher/url_launcher.dart';

import '../models/family_node.dart';
import '../models/gender.dart';
import '../models/member_details.dart';
import '../models/member_form_result.dart';
import '../pages/photo_viewer_page.dart';
import '../services/family_tree_store.dart';
import '../utilities/date_format.dart';
import '../widgets/member_photo.dart';

/// Returns the age in whole years from [birthday] to [endDate].
///
/// If [endDate] is null, age is calculated up to today.
/// Use the member's date of death as [endDate] for deceased members.
int? _calcAge(DateTime? birthday, {DateTime? endDate}) {
  if (birthday == null) return null;

  final referenceDate = endDate ?? DateTime.now();
  int age = referenceDate.year - birthday.year;

  if (referenceDate.month < birthday.month ||
      (referenceDate.month == birthday.month &&
          referenceDate.day < birthday.day)) {
    age--;
  }

  return age < 0 ? 0 : age;
}

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
  static const Color border = Color(0xFFCFE5D6);
  static const Color divider = Color(0xFFD9EADF);
  static const Color shadow = Color(0x1F1F3A29);
  static const Color textMuted = Color(0xFF5F7468);
  static const Color connector = Color(0xFF1B6B3A);
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
    required this.initialFirstName,
    required this.initialMiddleName,
    required this.initialLastName,
    required this.initialNickname,
    required this.initialGender,
    required this.allowedGenders,
    required this.initialDetails,
    required this.initialBirthday,
    required this.initialDeathDate,
    required this.initialPhotoBytes,
    required this.initialPhotoProvider,
    required this.allowRemovePhoto,
    required this.allowClearBirthday,
  });

  final String title;
  final bool showNameField;
  final String? initialName;
  final String? initialFirstName;
  final String? initialMiddleName;
  final String? initialLastName;
  final String? initialNickname;
  final Gender initialGender;
  final List<Gender> allowedGenders;
  final MemberDetails initialDetails;
  final DateTime? initialBirthday;
  final DateTime? initialDeathDate;
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
  bool _didInitialCenter = false;
  bool _syncingFromController = false;
  double _zoomValue = 1.0;


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
      // Rebuild toolbar so auth-conditional buttons update immediately.
      setState(() {});
      // Load for both authenticated and unauthenticated users.
      await _ensureLoadedFromCloud();
    });

    _tc.addListener(() {
      if (!mounted || _syncingFromController) return;
      // Update _zoomValue without setState — InteractiveViewer renders the
      // zoom transform itself; we only need _zoomValue current for drag-delta
      // correction and programmatic navigation, not for widget rebuilds.
      final s = _tc.value.getMaxScaleOnAxis().clamp(_minZoom, _maxZoom);
      _zoomValue = s;
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
          deathDate: null,
          clearDeathDate: false,
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
      final searchable = <String>[
        node.name,
        node.firstName,
        node.middleName ?? '',
        node.lastName,
        node.nickname ?? '',
      ].join(' ').toLowerCase();

      if (searchable.contains(q)) {
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

    if (mounted) setState(() => _isLoading = true);

    try {
      await store.loadFromCloud(treeId: 'default');
      _loadedOnce = true; // only mark done on success
      debugPrint('✅ RTDB loaded. nodes=${store.nodes.length}');
    } catch (e) {
      debugPrint('❌ loadFromCloud error: $e');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Widget buildClickableRelation({
    required String label,
    required List<int> ids,
    required ValueNotifier<Set<String>> expandedSections,
  }) {
    if (ids.isEmpty) return const SizedBox();

    const int previewCount = 2;
    final bool needsToggle = ids.length > previewCount;
    final String sectionKey = label;

    return ValueListenableBuilder<Set<String>>(
      valueListenable: expandedSections,
      builder: (context, expanded, _) {
        final bool isExpanded = expanded.contains(sectionKey);
        final visibleIds =
            needsToggle && !isExpanded ? ids.take(previewCount).toList() : ids;
        final hiddenCount = ids.length - previewCount;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  Text(
                    '$label:',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  ...visibleIds.map((id) {
                    final n = store.getNode(id);
                    return InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        Navigator.pop(context);
                        _focusNode(id);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
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
              if (needsToggle)
                GestureDetector(
                  onTap: () {
                    final next = Set<String>.from(expanded);
                    if (isExpanded) {
                      next.remove(sectionKey);
                    } else {
                      next.add(sectionKey);
                    }
                    expandedSections.value = next;
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 16,
                          color: _TreeGreenTheme.primary,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          isExpanded
                              ? 'Show less'
                              : '+$hiddenCount more',
                          style: const TextStyle(
                            fontSize: 12,
                            color: _TreeGreenTheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
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
    String? initialFirstName,
    String? initialMiddleName,
    String? initialLastName,
    String? initialNickname,
    required Gender initialGender,
    required List<Gender> allowedGenders,
    MemberDetails? initialDetails,
    DateTime? initialBirthday,
    DateTime? initialDeathDate,
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
          firstName: initialFirstName,
          middleName: initialMiddleName,
          lastName: initialLastName,
          nickname: initialNickname,
          gender: initialGender,
          details: initialDetails ?? const MemberDetails(),
          birthday: initialBirthday,
          clearBirthday: false,
          deathDate: initialDeathDate,
          clearDeathDate: false,
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
        initialFirstName: initialFirstName,
        initialMiddleName: initialMiddleName,
        initialLastName: initialLastName,
        initialNickname: initialNickname,
        initialGender: initialGender,
        allowedGenders: allowedGenders,
        initialDetails: initialDetails ?? const MemberDetails(),
        initialBirthday: initialBirthday,
        initialDeathDate: initialDeathDate,
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
        firstName: req?.initialFirstName,
        middleName: req?.initialMiddleName,
        lastName: req?.initialLastName,
        nickname: req?.initialNickname,
        gender: req?.initialGender ?? Gender.female,
        details: req?.initialDetails ?? const MemberDetails(),
        birthday: req?.initialBirthday,
        clearBirthday: false,
        deathDate: req?.initialDeathDate,
        clearDeathDate: false,
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

  Offset _currentViewportSceneCenter() {
    final box =
        _viewerContainerKey.currentContext?.findRenderObject() as RenderBox?;

    final viewportCenter = box == null
        ? Offset(
            MediaQuery.of(context).size.width / 2,
            MediaQuery.of(context).size.height / 2,
          )
        : Offset(box.size.width / 2, box.size.height / 2);

    return _tc.toScene(viewportCenter);
  }

  void _placeNodeAtSceneCenter(int nodeId, Offset sceneCenter) {
    final currentTopLeft = _lastLayoutScene[nodeId];
    if (currentTopLeft == null) return;

    final desiredTopLeft = sceneCenter -
        Offset(cardSize.width / 2, cardSize.height / 2);
    final delta = desiredTopLeft - currentTopLeft;

    setState(() {
      store.addManualOffset(nodeId, delta);
      _hoveredNodeId = nodeId;
    });
  }

  bool _memberMatchesSearch(FamilyNode node, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;

    final searchable = <String>[
      node.name,
      node.firstName,
      node.middleName ?? '',
      node.lastName,
      node.nickname ?? '',
      node.gender.label,
    ].join(' ').toLowerCase();

    return searchable.contains(q);
  }

  Future<int?> _pickExistingMemberToConnect({
    required String title,
    required String emptyMessage,
    required List<FamilyNode> candidates,
  }) async {
    final sortedCandidates = candidates.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (sortedCandidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(emptyMessage)),
      );
      return null;
    }

    final controller = TextEditingController();

    try {
      return await showDialog<int>(
        context: context,
        builder: (dialogContext) {
          String query = '';

          return StatefulBuilder(
            builder: (context, setDialogState) {
              final filtered = sortedCandidates
                  .where((node) => _memberMatchesSearch(node, query))
                  .toList();

              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: Text(title),
                content: SizedBox(
                  width: 420,
                  height: 430,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: controller,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Search member name...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          isDense: true,
                        ),
                        onChanged: (value) {
                          setDialogState(() => query = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(
                                child: Text(
                                  'No matching members found.',
                                  style: TextStyle(
                                    color: _TreeGreenTheme.textMuted,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final member = filtered[index];
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: member.gender.tone,
                                      child: Icon(
                                        member.gender.icon,
                                        color: _TreeGreenTheme.textMuted,
                                      ),
                                    ),
                                    title: Text(
                                      member.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(member.gender.label),
                                    trailing: const Icon(Icons.link),
                                    onTap: () =>
                                        Navigator.pop(dialogContext, member.id),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: _TreeGreenTheme.primary),
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Set<int> _collectConnectedFamilyIds(int rootId) {
    final visited = <int>{};
    final queue = <int>[rootId];

    while (queue.isNotEmpty) {
      final id = queue.removeAt(0);
      if (!visited.add(id)) continue;

      final node = store.nodes[id];
      if (node == null) continue;

      for (final nextId in <int>{
        ...node.parents,
        ...node.children,
        ...node.spouses,
      }) {
        if (!visited.contains(nextId) && store.nodes.containsKey(nextId)) {
          queue.add(nextId);
        }
      }
    }

    return visited;
  }

  void _preserveLayoutPositionsAfterRelayout(
    Map<int, Offset> beforePositions, {
    Set<int> exceptIds = const <int>{},
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final afterPositions = Map<int, Offset>.from(_lastLayoutScene);

      for (final id in beforePositions.keys) {
        if (exceptIds.contains(id)) continue;

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

  void _placeConnectedMemberLikeNewAfterRelayout({
    required Map<int, Offset> beforePositions,
    required Set<int> movingIds,
    required int movingRootId,
    required int anchorId,
    required Offset offset,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final afterPositions = Map<int, Offset>.from(_lastLayoutScene);

      // Keep everyone else where they were before the relationship relayout.
      for (final id in beforePositions.keys) {
        if (movingIds.contains(id)) continue;

        final before = beforePositions[id];
        final after = afterPositions[id];
        if (before == null || after == null) continue;

        final delta = before - after;
        if (delta.distance > 0.5) {
          store.addManualOffset(id, delta);
        }
      }

      // Then move the connected member/component to the same relative spot
      // used by Add Parent / Add Son / Add Daughter.
      final anchorPos = beforePositions[anchorId] ?? afterPositions[anchorId];
      final movingRootPos = afterPositions[movingRootId];
      if (anchorPos == null || movingRootPos == null) return;

      final idsToMove = movingIds
          .where((id) => id != anchorId && afterPositions.containsKey(id))
          .toSet();
      if (idsToMove.isEmpty) return;

      final desiredRootPos = anchorPos + offset;
      final delta = desiredRootPos - movingRootPos;
      if (delta.distance <= 0.5) return;

      if (idsToMove.length == 1) {
        store.addManualOffset(idsToMove.first, delta);
      } else {
        store.addManualOffsetBulk(idsToMove, delta);
      }
    });
  }


  int? _preferredCoParentForConnectedChild({
    required int parentId,
    required int childId,
  }) {
    final parent = store.nodes[parentId];
    final child = store.nodes[childId];
    if (parent == null || child == null) return null;

    // If connecting this parent already gives the child two parents, do not
    // force another relationship. This keeps the normal two-parent limit.
    if (child.parents.length >= 2) return null;

    final coParentCounts = <int, int>{};

    // Look at the parent's existing children and find the other parent most
    // commonly shared with those children. This is intentionally gender-neutral:
    // it works for mother+father, mother+mother, father+father, and any custom
    // same-gender parent pairing.
    for (final existingChildId in parent.children) {
      if (existingChildId == childId) continue;

      final existingChild = store.nodes[existingChildId];
      if (existingChild == null) continue;
      if (!existingChild.parents.contains(parentId)) continue;

      for (final otherParentId in existingChild.parents) {
        if (otherParentId == parentId) continue;
        if (otherParentId == childId) continue;
        if (!store.nodes.containsKey(otherParentId)) continue;
        if (child.parents.contains(otherParentId)) continue;

        coParentCounts[otherParentId] =
            (coParentCounts[otherParentId] ?? 0) + 1;
      }
    }

    if (coParentCounts.isEmpty) return null;

    // Prefer an explicitly linked spouse if one is also the common co-parent,
    // otherwise use the most common co-parent among existing siblings.
    for (final spouseId in parent.spouses) {
      if (coParentCounts.containsKey(spouseId)) return spouseId;
    }

    final ranked = coParentCounts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });

    return ranked.first.key;
  }

  void _placeConnectedChildWithSiblingsAfterRelayout({
    required Map<int, Offset> beforePositions,
    required Set<int> movingIds,
    required int parentId,
    required int childId,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final afterPositions = Map<int, Offset>.from(_lastLayoutScene);

      // Keep existing nodes fixed after the relationship relayout. Only the
      // connected child/component is moved into the existing sibling row.
      for (final id in beforePositions.keys) {
        if (movingIds.contains(id)) continue;

        final before = beforePositions[id];
        final after = afterPositions[id];
        if (before == null || after == null) continue;

        final delta = before - after;
        if (delta.distance > 0.5) {
          store.addManualOffset(id, delta);
        }
      }

      final parentPos = beforePositions[parentId] ?? afterPositions[parentId];
      final childPos = afterPositions[childId];
      if (parentPos == null || childPos == null) return;

      final idsToMove = movingIds
          .where((id) => id != parentId && afterPositions.containsKey(id))
          .toSet();
      if (idsToMove.isEmpty) return;

      final xStep = cardSize.width + hGap;

      final siblingPositions = store.nodes.values
          .where((node) =>
              node.id != childId &&
              node.parents.contains(parentId) &&
              (beforePositions.containsKey(node.id) ||
                  afterPositions.containsKey(node.id)))
          .map((node) => beforePositions[node.id] ?? afterPositions[node.id]!)
          .toList()
        ..sort((a, b) => a.dx.compareTo(b.dx));

      late final Offset desiredChildPos;
      if (siblingPositions.isEmpty) {
        desiredChildPos = parentPos + Offset(0, cardSize.height + 40);
      } else {
        final minSiblingX = siblingPositions.first.dx;
        final maxSiblingX = siblingPositions.last.dx;
        final averageSiblingY = siblingPositions
                .map((p) => p.dy)
                .reduce((a, b) => a + b) /
            siblingPositions.length;

        final parentTargetX = parentPos.dx;
        final leftCandidateX = minSiblingX - xStep;
        final rightCandidateX = maxSiblingX + xStep;

        final useLeft =
            (parentTargetX - leftCandidateX).abs() <
                (parentTargetX - rightCandidateX).abs();

        desiredChildPos = Offset(
          useLeft ? leftCandidateX : rightCandidateX,
          averageSiblingY,
        );
      }

      final delta = desiredChildPos - childPos;
      if (delta.distance <= 0.5) return;

      if (idsToMove.length == 1) {
        store.addManualOffset(idsToMove.first, delta);
      } else {
        store.addManualOffsetBulk(idsToMove, delta);
      }
    });
  }

  Future<void> _connectExistingParentFlow({required int personId}) async {
    if (_previewMode) return;
    if (!await _requireLogin()) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final person = store.getNode(personId);

    if (person.parents.length >= 2) {
      messenger.showSnackBar(
        SnackBar(content: Text('${person.name} already has 2 parents.')),
      );
      return;
    }

    final candidates = store.nodes.values.where((candidate) {
      if (candidate.id == personId) return false;
      if (person.parents.contains(candidate.id)) return false;
      return true;
    }).toList();

    final parentId = await _pickExistingMemberToConnect(
      title: 'Connect Existing Parent',
      emptyMessage: 'No available members can be connected as a parent.',
      candidates: candidates,
    );

    if (!mounted || parentId == null) return;

    final beforePositions = Map<int, Offset>.from(_lastLayoutScene);
    final movingIds = _collectConnectedFamilyIds(parentId)..remove(personId);
    if (movingIds.isEmpty) movingIds.add(parentId);

    final ok = store.tryLinkExistingParent(
      parentId: parentId,
      childId: personId,
    );

    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Cannot connect this parent (rules blocked).')),
      );
      return;
    }

    setState(() => _hoveredNodeId = parentId);
    _placeConnectedMemberLikeNewAfterRelayout(
      beforePositions: beforePositions,
      movingIds: movingIds,
      movingRootId: parentId,
      anchorId: personId,
      offset: Offset(0, -(cardSize.height + 40)),
    );
  }

  Future<void> _connectExistingChildFlow({required int parentId}) async {
    if (_previewMode) return;
    if (!await _requireLogin()) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final parent = store.getNode(parentId);

    final candidates = store.nodes.values.where((candidate) {
      if (candidate.id == parentId) return false;
      if (parent.children.contains(candidate.id)) return false;
      if (candidate.parents.length >= 2) return false;
      return true;
    }).toList();

    final childId = await _pickExistingMemberToConnect(
      title: 'Connect Existing Child',
      emptyMessage: 'No available members can be connected as a child.',
      candidates: candidates,
    );

    if (!mounted || childId == null) return;

    final beforePositions = Map<int, Offset>.from(_lastLayoutScene);
    final movingIds = _collectConnectedFamilyIds(childId)..remove(parentId);
    if (movingIds.isEmpty) movingIds.add(childId);

    final ok = store.tryLinkExistingChild(
      parentId: parentId,
      childId: childId,
    );

    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Cannot connect this child (rules blocked).')),
      );
      return;
    }

    // Match Add Son / Add Daughter behavior: if this parent already has
    // children with a co-parent, attach that same co-parent to the connected
    // child too. This is gender-neutral, so same-gender parent pairs are
    // handled the same as mother/father pairs.
    final coParentId = _preferredCoParentForConnectedChild(
      parentId: parentId,
      childId: childId,
    );
    if (coParentId != null) {
      store.tryLinkExistingChild(
        parentId: coParentId,
        childId: childId,
      );
    }

    setState(() => _hoveredNodeId = childId);
    _placeConnectedChildWithSiblingsAfterRelayout(
      beforePositions: beforePositions,
      movingIds: movingIds,
      parentId: parentId,
      childId: childId,
    );
  }

  Future<void> _connectExistingSpouseFlow({required int personId}) async {
    if (_previewMode) return;
    if (!await _requireLogin()) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final person = store.getNode(personId);

    if (person.spouses.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text('${person.name} already has a spouse.')),
      );
      return;
    }

    final candidates = store.nodes.values.where((candidate) {
      if (candidate.id == personId) return false;
      if (candidate.spouses.isNotEmpty) return false;
      return true;
    }).toList();

    final spouseId = await _pickExistingMemberToConnect(
      title: 'Connect Existing Spouse',
      emptyMessage: 'No available members can be connected as a spouse.',
      candidates: candidates,
    );

    if (!mounted || spouseId == null) return;

    final originalPersonGender = person.gender;
    final originalSpouseGender = store.getNode(spouseId).gender;
    final beforePositions = Map<int, Offset>.from(_lastLayoutScene);
    final ok = store.tryLinkExistingSpouses(
      aId: personId,
      bId: spouseId,
    );

    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Cannot connect this spouse (rules blocked).')),
      );
      return;
    }

    // Keep both members' chosen genders. Spouse links should not auto-flip
    // either person to the opposite gender.
    store.setGender(personId, originalPersonGender);
    store.setGender(spouseId, originalSpouseGender);

    setState(() => _hoveredNodeId = spouseId);
    _preserveLayoutPositionsAfterRelayout(beforePositions);
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
            style: TextButton.styleFrom(foregroundColor: _TreeGreenTheme.primary),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _TreeGreenTheme.primary,
            ),
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

  final newDeathDate = r.clearDeathDate ? null : r.deathDate;

  // 1. Update basic details immediately
  store.setGender(nodeId, r.gender);
  store.setDetails(nodeId, r.details);
  store.setBirthday(nodeId, r.clearBirthday ? null : r.birthday);
  store.setDeathDate(nodeId, newDeathDate);

  // A filled date of death should automatically mark the member as deceased.
  // Clearing the date of death should automatically mark the member as living.
  final afterDeathDateUpdate = store.getNode(nodeId);
  if (newDeathDate != null && !afterDeathDateUpdate.isDeceased) {
    store.toggleDeceased(nodeId);
    store.setDeathDate(nodeId, newDeathDate);
  } else if (newDeathDate == null && afterDeathDateUpdate.isDeceased) {
    store.toggleDeceased(nodeId);
  }

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

Future<void> _pickDeathDateAndMarkDeceased(int nodeId) async {
  final node = store.getNode(nodeId);
  final now = DateTime.now();
  final initial = node.deathDate ?? now;

  final picked = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(1800),
    lastDate: now,
    helpText: 'Select date of death',
    builder: (context, child) => Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.light(
          primary: _TreeGreenTheme.primary,
          onPrimary: Colors.white,
          surface: _TreeGreenTheme.surface,
          onSurface: Color(0xFF1A2E22),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: _TreeGreenTheme.primary),
        ),
      ),
      child: child!,
    ),
  );

  if (picked == null || !mounted) return;

  setState(() {
    final current = store.getNode(nodeId);
    if (!current.isDeceased) {
      store.toggleDeceased(nodeId);
    }
    store.setDeathDate(nodeId, picked);
  });
}

Future<void> _handleLivingDeceasedAction(int nodeId) async {
  final node = store.getNode(nodeId);

  if (node.isDeceased) {
    setState(() => store.toggleDeceased(nodeId));
    return;
  }

  if (node.deathDate == null) {
    await _pickDeathDateAndMarkDeceased(nodeId);
    return;
  }

  final existingDeathDate = node.deathDate;
  setState(() {
    final current = store.getNode(nodeId);
    if (!current.isDeceased) {
      store.toggleDeceased(nodeId);
    }
    if (existingDeathDate != null) {
      store.setDeathDate(nodeId, existingDeathDate);
    }
  });
}

  Future<void> _editDetailsFlow(int nodeId) async {
    final n = store.getNode(nodeId);
    final initial = MemberDetails(
      barangay: n.barangay,
      city: n.city,
      province: n.province,
      country: n.country,
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
      initialFirstName: n.firstName,
      initialMiddleName: n.middleName,
      initialLastName: n.lastName,
      initialNickname: n.nickname,
      initialGender: n.gender,
      allowedGenders: const [Gender.female, Gender.male],
      initialDetails: initial,
      initialBirthday: n.birthday,
      initialDeathDate: n.deathDate,
      initialPhotoBytes: n.photoBytes,
      initialPhotoProvider: n.hasPhoto ? n.photoProvider : null,
      allowRemovePhoto: true,
      allowClearBirthday: true,
    );

    if (!mounted || !r.saved) return;

    final firstName = (r.firstName ?? '').trim();
    final lastName = (r.lastName ?? '').trim();
    if (firstName.isNotEmpty && lastName.isNotEmpty) {
      store.setNameParts(
        nodeId,
        firstName: firstName,
        middleName: r.middleName,
        lastName: lastName,
        nickname: r.nickname,
      );
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

  /// Returns true if the user is signed in.
  /// If not, shows a dialog prompting them to log in and returns false.
  Future<bool> _requireLogin() async {
    if (FirebaseAuth.instance.currentUser != null) return true;
    if (!mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign in required'),
        content: const Text(
          'You need to be signed in to edit the family tree.',
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: _TreeGreenTheme.primary),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF49A04A),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushReplacementNamed(context, LoginPage.route);
            },
            child: const Text('Log In',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return false;
  }

  Future<void> _addFirstMemberFlow() async {
    if (!await _requireLogin()) return;
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

    final firstName = (r.firstName ?? '').trim();
    final lastName = (r.lastName ?? '').trim();
    final name = r.displayName.trim();
    if (firstName.isEmpty || lastName.isEmpty || name.isEmpty) return;

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
      firstName: firstName,
      middleName: r.middleName,
      lastName: lastName,
      nickname: r.nickname,
      gender: r.gender,
      birthday: r.clearBirthday ? null : r.birthday,
      photoUrl: photoUrl,
      photoBytes: null,
      barangay: r.details.barangay,
      city: r.details.city,
      province: r.details.province,
      country: r.details.country,
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
    if (!await _requireLogin()) return;

    // Capture where the user is currently looking before the drawer opens.
    // The new standalone member will be placed here after it is created.
    final targetSceneCenter = _currentViewportSceneCenter();

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

    final firstName = (r.firstName ?? '').trim();
    final lastName = (r.lastName ?? '').trim();
    final name = r.displayName.trim();
    if (firstName.isEmpty || lastName.isEmpty || name.isEmpty) return;

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

    final newNode = store.addStandalone(
      name: name,
      firstName: firstName,
      middleName: r.middleName,
      lastName: lastName,
      nickname: r.nickname,
      gender: r.gender,
      birthday: r.clearBirthday ? null : r.birthday,
      photoUrl: photoUrl,
      photoBytes: null,
      barangay: r.details.barangay,
      city: r.details.city,
      province: r.details.province,
      country: r.details.country,
      phone: r.details.phone,
      company: r.details.company,
      jobTitle: r.details.jobTitle,
      fb: r.details.fb,
      ig: r.details.ig,
      xAccount: r.details.xAccount,
      tiktok: r.details.tiktok,
    );

    // Force one rebuild so _lastLayoutScene contains the new node.
    setState(() => _hoveredNodeId = newNode.id);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _placeNodeAtSceneCenter(newNode.id, targetSceneCenter);
    });
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

  // Always-visible info (birthday, death date + address)
  final basicInfoLines = <String>[
    if (node.birthday != null) 'Birthday: ${formatDate(node.birthday!)}',
    if (node.deathDate != null) 'Date of Death: ${formatDate(node.deathDate!)}',
    if (node.birthday != null)
      node.deathDate != null
          ? 'Age: Died at ${_calcAge(node.birthday, endDate: node.deathDate)}'
          : 'Age: ${_calcAge(node.birthday)}',
    ...[
      line('Street/Brgy/District', node.barangay),
      line('Town/Municipality/City', node.city),
      line('Province/State', node.province),
      line('Country', node.country),
    ].whereType<String>(),
  ];

  // Extra info (phone, work, social)
  final extraInfoLines = <String>[
    ...[
      line('Phone', node.phone),
      line('Company', node.company),
      line('Job Title', node.jobTitle),
      line('Facebook', node.fb),
      line('Instagram', node.ig),
      line('X', node.xAccount),
      line('TikTok', node.tiktok),
    ].whereType<String>(),
  ];

  // URL resolver for social lines
  String? socialUrl(String infoLine) {
    if (infoLine.startsWith('Facebook: ')) {
      final h = infoLine.substring('Facebook: '.length).trim().replaceFirst(RegExp(r'^@'), '');
      return 'https://facebook.com/${Uri.encodeComponent(h)}';
    }
    if (infoLine.startsWith('Instagram: ')) {
      final h = infoLine.substring('Instagram: '.length).trim().replaceFirst(RegExp(r'^@'), '');
      return 'https://instagram.com/${Uri.encodeComponent(h)}';
    }
    if (infoLine.startsWith('X: ')) {
      final h = infoLine.substring('X: '.length).trim().replaceFirst(RegExp(r'^@'), '');
      return 'https://x.com/${Uri.encodeComponent(h)}';
    }
    if (infoLine.startsWith('TikTok: ')) {
      final h = infoLine.substring('TikTok: '.length).trim().replaceFirst(RegExp(r'^@'), '');
      return 'https://tiktok.com/@$h';
    }
    return null;
  }

  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final position = RelativeRect.fromRect(
    Rect.fromLTWH(globalTapPosition.dx, globalTapPosition.dy, 1, 1),
    Offset.zero & overlay.size,
  );

  final showAllNotifier = ValueNotifier<bool>(false);
  final expandedSectionsNotifier = ValueNotifier<Set<String>>({});

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
        child: ValueListenableBuilder<bool>(
          valueListenable: showAllNotifier,
          builder: (context, showAllDetails, _) {
            return ValueListenableBuilder<Set<String>>(
              valueListenable: expandedSectionsNotifier,
              builder: (context, _, __) {
              return Container(
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
                  // Header (photo, name, gender)
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

                  // Family relations (always visible)
                  if (parentIds.isNotEmpty)
                    buildClickableRelation(label: 'Parents', ids: parentIds, expandedSections: expandedSectionsNotifier),
                  if (siblingIds.isNotEmpty)
                    buildClickableRelation(label: 'Siblings', ids: siblingIds, expandedSections: expandedSectionsNotifier),
                  if (childrenIds.isNotEmpty)
                    buildClickableRelation(label: 'Children', ids: childrenIds, expandedSections: expandedSectionsNotifier),
                  if (parentIds.isNotEmpty ||
                      siblingIds.isNotEmpty ||
                      childrenIds.isNotEmpty)
                    const SizedBox(height: 6),

                  // Basic details (birthday, address)
                  if (basicInfoLines.isNotEmpty) ...[
                    for (final line in basicInfoLines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(line, style: const TextStyle(fontSize: 14)),
                      ),
                  ],

                  // Extra details section: details then button (or just button)
                  if (extraInfoLines.isNotEmpty) ...[
                    if (showAllDetails)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final infoLine in extraInfoLines)
                            Builder(builder: (context) {
                              final url = socialUrl(infoLine);
                              if (url != null) {
                                // Split into "Label: " and the handle
                                final colonIdx = infoLine.indexOf(': ');
                                final label = colonIdx != -1 ? infoLine.substring(0, colonIdx + 2) : '';
                                final handle = colonIdx != -1 ? infoLine.substring(colonIdx + 2) : infoLine;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: GestureDetector(
                                    onTap: () async {
                                      final uri = Uri.parse(url);
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                                      }
                                    },
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: label,
                                            style: const TextStyle(fontSize: 14),
                                          ),
                                          TextSpan(
                                            text: handle,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: _TreeGreenTheme.primary,
                                              decoration: TextDecoration.underline,
                                              decorationColor: _TreeGreenTheme.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(infoLine, style: const TextStyle(fontSize: 14)),
                              );
                            }),
                          const SizedBox(height: 8),
                        ],
                      ),
                    Center(
                      child: TextButton.icon(
                        onPressed: () =>
                            showAllNotifier.value = !showAllDetails,
                        icon: Icon(showAllDetails
                            ? Icons.expand_less
                            : Icons.expand_more),
                        label: Text(showAllDetails
                            ? 'Show less'
                            : 'Show all details'),
                        style: TextButton.styleFrom(
                          foregroundColor: _TreeGreenTheme.primary,
                        ),
                      ),
                    ),
                  ],

                  // Fallback when no details at all
                  if (basicInfoLines.isEmpty && extraInfoLines.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No additional details provided.',
                        style: TextStyle(color: _TreeGreenTheme.textMuted),
                      ),
                    ),

                  // Log in prompt for guests (always at the bottom)
                  if (FirebaseAuth.instance.currentUser == null) ...[
                    const Divider(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF49A04A),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.lock_open,
                            color: Colors.white, size: 18),
                        label: const Text(
                          'Log in to edit this member',
                          style: TextStyle(color: Colors.white),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.pushReplacementNamed(
                              context, LoginPage.route);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            );
            },
          );
          },
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

    // Unauthenticated visitors always see the read-only details popup
    // (which includes a 'Log in to edit' button).
    // Authenticated users who don't own the node also see the details popup.
    if (FirebaseAuth.instance.currentUser == null ||
        !store.canEditNodeId(nodeId)) {
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
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PopupActionButton(
                      label: 'Edit Details',
                      color: _TreeGreenTheme.actionBlue,
                      width: 280,
                      onTap: () => Navigator.pop(context, 'details'),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _PopupActionButton(
                          label: 'Add Parent',
                          color: _TreeGreenTheme.actionPurple,
                          enabled: node.parents.length < 2,
                          onTap: () => Navigator.pop(context, 'parent'),
                        ),
                        _PopupActionButton(
                          label: 'Connect Parent',
                          color: _TreeGreenTheme.actionPurple,
                          enabled: node.parents.length < 2,
                          onTap: () => Navigator.pop(context, 'connect_parent'),
                        ),
                        _PopupActionButton(
                          label: 'Add Spouse',
                          color: _TreeGreenTheme.actionPink,
                          enabled: node.spouses.isEmpty,
                          onTap: () => Navigator.pop(context, 'spouse'),
                        ),
                        _PopupActionButton(
                          label: 'Connect Spouse',
                          color: _TreeGreenTheme.actionPink,
                          enabled: node.spouses.isEmpty,
                          onTap: () => Navigator.pop(context, 'connect_spouse'),
                        ),
                        _PopupActionButton(
                          label: 'Add Son',
                          color: _TreeGreenTheme.actionTeal,
                          onTap: () => Navigator.pop(context, 'son'),
                        ),
                        _PopupActionButton(
                          label: 'Add Daughter',
                          color: _TreeGreenTheme.actionTeal,
                          onTap: () => Navigator.pop(context, 'daughter'),
                        ),
                        _PopupActionButton(
                          label: 'Connect Child',
                          color: _TreeGreenTheme.actionTeal,
                          onTap: () => Navigator.pop(context, 'connect_child'),
                        ),
                        _PopupActionButton(
                          label: node.isDeceased ? 'Living' : 'Deceased',
                          color: node.isDeceased
                              ? _TreeGreenTheme.actionTeal
                              : const Color(0xFF7A7A8C),
                          onTap: () => Navigator.pop(context, 'deceased'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _PopupActionButton(
                      label: 'Delete',
                      color: Colors.red,
                      width: 280,
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
      case 'connect_spouse':
        await _connectExistingSpouseFlow(personId: nodeId);
        break;
      case 'parent':
        await _addParentFlow(personId: nodeId);
        break;
      case 'connect_parent':
        await _connectExistingParentFlow(personId: nodeId);
        break;
      case 'son':
        await _addSonFlow(fromNodeId: nodeId);
        break;
      case 'daughter':
        await _addDaughterFlow(fromNodeId: nodeId);
        break;
      case 'connect_child':
        await _connectExistingChildFlow(parentId: nodeId);
        break;
      case 'deceased':
        await _handleLivingDeceasedAction(nodeId);
        break;
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (dctx) => AlertDialog(
            title: const Text('Delete member?'),
            content: const Text('This will remove the member and all related links.'),
            actions: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: _TreeGreenTheme.primary),
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

    final r = await _openMemberFormDrawer(
      title: 'Add Spouse Info',
      showNameField: true,
      initialName: 'New Spouse',
      initialGender: person.gender,
      allowedGenders: const [Gender.female, Gender.male],
      allowRemovePhoto: false,
      allowClearBirthday: true,
    );
    if (!mounted || !r.saved) return;

    final firstName = (r.firstName ?? '').trim();
    final lastName = (r.lastName ?? '').trim();
    final name = r.displayName.trim();
    if (firstName.isEmpty || lastName.isEmpty || name.isEmpty) return;

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
      firstName: firstName,
      middleName: r.middleName,
      lastName: lastName,
      nickname: r.nickname,
      birthday: r.clearBirthday ? null : r.birthday,
      photoUrl: photoUrl,
      photoBytes: null,
      barangay: r.details.barangay,
      city: r.details.city,
      province: r.details.province,
      country: r.details.country,
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

    // Keep the gender selected in the form. Some store implementations create
    // spouses as the opposite gender by default, so overwrite it here.
    store.setGender(added.id, r.gender);

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

    const options = <Gender>[Gender.female, Gender.male];

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

    final firstName = (r.firstName ?? '').trim();
    final lastName = (r.lastName ?? '').trim();
    final name = r.displayName.trim();
    if (firstName.isEmpty || lastName.isEmpty || name.isEmpty) return;

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
      firstName: firstName,
      middleName: r.middleName,
      lastName: lastName,
      nickname: r.nickname,
      birthday: r.clearBirthday ? null : r.birthday,
      photoUrl: photoUrl,
      photoBytes: null,
      barangay: r.details.barangay,
      city: r.details.city,
      province: r.details.province,
      country: r.details.country,
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

    final firstName = (r.firstName ?? '').trim();
    final lastName = (r.lastName ?? '').trim();
    final name = r.displayName.trim();
    if (firstName.isEmpty || lastName.isEmpty || name.isEmpty) return;

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
      firstName: firstName,
      middleName: r.middleName,
      lastName: lastName,
      nickname: r.nickname,
      childGender: gender,
      birthday: r.clearBirthday ? null : r.birthday,
      photoUrl: photoUrl,
      photoBytes: null,
      barangay: r.details.barangay,
      city: r.details.city,
      province: r.details.province,
      country: r.details.country,
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
                                  entry.key == _hoveredNodeId,
                              // Mark nodes as dragging: the dragged node itself, plus any ctrl-selected
                              // When isDragging=true, AnimatedPositioned uses Duration.zero for instant updates
                              isDragging: _draggingNodeId != null &&
                                  (_ctrlSelectedIds.contains(entry.key) || _draggingNodeId == entry.key),
                              dragEnabled: !_previewMode,
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
                            ),
                        ],
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
                            if (FirebaseAuth.instance.currentUser != null) ...[
                              // Logged-in controls
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
                            ] else ...[
                              // Guest controls
                              TextButton.icon(
                                onPressed: () => Navigator.pushNamed(
                                    context, RegisterPage.route),
                                icon: const Icon(
                                  Icons.person_add_outlined,
                                  size: 18,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  'Register',
                                  style: TextStyle(color: Colors.white),
                                ),
                                style: TextButton.styleFrom(
                                  backgroundColor: const Color(0xFF49A04A),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                              ),
                            ],
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
                              initialFirstName: _drawerRequest!.initialFirstName,
                              initialMiddleName: _drawerRequest!.initialMiddleName,
                              initialLastName: _drawerRequest!.initialLastName,
                              initialNickname: _drawerRequest!.initialNickname,
                              initialGender: _drawerRequest!.initialGender,
                              allowedGenders: _drawerRequest!.allowedGenders,
                              initialDetails: _drawerRequest!.initialDetails,
                              initialBirthday: _drawerRequest!.initialBirthday,
                              initialDeathDate: _drawerRequest!.initialDeathDate,
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
    required this.initialFirstName,
    required this.initialMiddleName,
    required this.initialLastName,
    required this.initialNickname,
    required this.initialGender,
    required this.allowedGenders,
    required this.initialDetails,
    required this.initialBirthday,
    required this.initialDeathDate,
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
  final String? initialFirstName;
  final String? initialMiddleName;
  final String? initialLastName;
  final String? initialNickname;
  final Gender initialGender;
  final List<Gender> allowedGenders;
  final MemberDetails initialDetails;
  final DateTime? initialBirthday;
  final DateTime? initialDeathDate;
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

  late final TextEditingController _firstNameController;
  late final TextEditingController _middleNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _nicknameController;
  late final TextEditingController _barangayController;
  late final TextEditingController _cityController;
  late final TextEditingController _provinceController;
  late final TextEditingController _countryController;
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
  String? _birthdayError;
  DateTime? _deathDate;
  bool _clearDeathDate = false;
  bool _removePhoto = false;
  Uint8List? _newPhotoBytes;

  static String? _nullIfBlank(String value) {
    final v = value.trim();
    return v.isEmpty ? null : v;
  }

  static String _buildDisplayName({
    required String firstName,
    required String lastName,
    String? middleName,
    String? nickname,
  }) {
    final parts = <String>[
      firstName.trim(),
      if ((middleName ?? '').trim().isNotEmpty) middleName!.trim(),
      lastName.trim(),
    ].where((p) => p.isNotEmpty).toList();

    var display = parts.join(' ').trim();
    final alias = (nickname ?? '').trim();
    if (display.isNotEmpty && alias.isNotEmpty) display = '$display ($alias)';
    return display;
  }

  static (String, String?, String, String?) _parseInitialName(String? name) {
    var raw = (name ?? '').trim();
    String? alias;

    final aliasMatch = RegExp(r'\(([^)]+)\)\s*$').firstMatch(raw);
    if (aliasMatch != null) {
      alias = aliasMatch.group(1)?.trim();
      raw = raw.substring(0, aliasMatch.start).trim();
    }

    final parts = raw.split(RegExp(r'\s+')).where((p) => p.trim().isNotEmpty).toList();
    if (parts.isEmpty) return ('', null, '', alias);
    if (parts.length == 1) return (parts.first, null, '', alias);
    if (parts.length == 2) return (parts.first, null, parts.last, alias);

    return (
      parts.first,
      parts.sublist(1, parts.length - 1).join(' '),
      parts.last,
      alias,
    );
  }

  @override
  void initState() {
    super.initState();
    final parsed = _parseInitialName(widget.initialName);
    _firstNameController = TextEditingController(
      text: widget.initialFirstName ?? parsed.$1,
    );
    _middleNameController = TextEditingController(
      text: widget.initialMiddleName ?? parsed.$2 ?? '',
    );
    _lastNameController = TextEditingController(
      text: widget.initialLastName ?? parsed.$3,
    );
    _nicknameController = TextEditingController(
      text: widget.initialNickname ?? parsed.$4 ?? '',
    );
    _barangayController = TextEditingController(text: widget.initialDetails.barangay ?? '');
    _cityController = TextEditingController(text: widget.initialDetails.city ?? '');
    _provinceController = TextEditingController(text: widget.initialDetails.province ?? '');
    _countryController = TextEditingController(text: widget.initialDetails.country ?? '');
    _phoneController = TextEditingController(text: widget.initialDetails.phone ?? '');
    _companyController = TextEditingController(text: widget.initialDetails.company ?? '');
    _jobTitleController = TextEditingController(text: widget.initialDetails.jobTitle ?? '');
    _fbController = TextEditingController(text: widget.initialDetails.fb ?? '');
    _igController = TextEditingController(text: widget.initialDetails.ig ?? '');
    _xController = TextEditingController(text: widget.initialDetails.xAccount ?? '');
    _tiktokController = TextEditingController(text: widget.initialDetails.tiktok ?? '');
    _gender = widget.initialGender;
    _birthday = widget.initialBirthday;
    _deathDate = widget.initialDeathDate;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _nicknameController.dispose();
    _barangayController.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    _countryController.dispose();
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
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _TreeGreenTheme.primary,
            onPrimary: Colors.white,
            surface: _TreeGreenTheme.surface,
            onSurface: Color(0xFF1A2E22),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: _TreeGreenTheme.primary),
          ),
        ),
        child: child!,
      ),
    );

    if (picked == null || !mounted) return;

    setState(() {
      _birthday = picked;
      _clearBirthday = false;
    });
  }

  Future<void> _pickDeathDate() async {
    final now = DateTime.now();
    final initial = _deathDate ?? now;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1800),
      lastDate: now,
      helpText: 'Select date of death',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _TreeGreenTheme.primary,
            onPrimary: Colors.white,
            surface: _TreeGreenTheme.surface,
            onSurface: Color(0xFF1A2E22),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: _TreeGreenTheme.primary),
          ),
        ),
        child: child!,
      ),
    );

    if (picked == null || !mounted) return;

    setState(() {
      _deathDate = picked;
      _clearDeathDate = false;
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

  bool get _isAddMode => widget.title.startsWith('Add');

  void _submit() {
    // Validate birthday for add mode
    if (_isAddMode && _birthday == null && !_clearBirthday) {
      setState(() => _birthdayError = 'Date of birth is required');
    } else {
      setState(() => _birthdayError = null);
    }
    if (!_formKey.currentState!.validate()) return;
    if (_isAddMode && _birthday == null && !_clearBirthday) return;

    final details = MemberDetails(
      barangay: _barangayController.text.trim(),
      city: _cityController.text.trim(),
      province: _provinceController.text.trim(),
      country: _countryController.text.trim(),
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
        name: widget.showNameField
            ? _buildDisplayName(
                firstName: _firstNameController.text,
                middleName: _middleNameController.text,
                lastName: _lastNameController.text,
                nickname: _nicknameController.text,
              )
            : null,
        firstName: widget.showNameField ? _firstNameController.text.trim() : null,
        middleName: widget.showNameField ? _nullIfBlank(_middleNameController.text) : null,
        lastName: widget.showNameField ? _lastNameController.text.trim() : null,
        nickname: widget.showNameField ? _nullIfBlank(_nicknameController.text) : null,
        gender: _gender,
        details: details,
        birthday: _clearBirthday ? null : _birthday,
        clearBirthday: _clearBirthday,
        deathDate: _clearDeathDate ? null : _deathDate,
        clearDeathDate: _clearDeathDate,
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
    final birthdayText = (_clearBirthday || _birthday == null)
        ? 'Select birthday'
        : formatDate(_birthday!);

    final deathDateText = (_clearDeathDate || _deathDate == null)
        ? 'Select date of death'
        : formatDate(_deathDate!);

        

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
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _TreeGreenTheme.primary,
                          side: const BorderSide(color: _TreeGreenTheme.primary),
                        ),
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
                    controller: _firstNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: _dec('First name *', icon: Icons.person_outline),
                    validator: (v) {
                      if (!widget.showNameField) return null;
                      if ((v ?? '').trim().isEmpty) return 'First name is required';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _middleNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: _dec('Middle name (optional)', icon: Icons.badge_outlined),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _lastNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: _dec('Last name *', icon: Icons.person_outline),
                    validator: (v) {
                      if (!widget.showNameField) return null;
                      if ((v ?? '').trim().isEmpty) return 'Last name is required';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _nicknameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: _dec('Nickname / Alias (optional)', icon: Icons.alternate_email),
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
                  onTap: () async {
                    await _pickBirthday();
                    if (_birthday != null) setState(() => _birthdayError = null);
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InputDecorator(
                        decoration: _dec(
                          _isAddMode ? 'Date of Birth *' : 'Birthday',
                          icon: Icons.cake_outlined,
                        ).copyWith(
                          errorText: _birthdayError,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          enabledBorder: _birthdayError != null
                              ? OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: Colors.red),
                                )
                              : null,
                        ),
                        child: Row(
                          children: [
                            Expanded(child: Text(birthdayText)),
                            if (widget.allowClearBirthday && _birthday != null && !_clearBirthday)
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _clearBirthday = true;
                                    _birthday = null;
                                    _birthdayError = null;
                                  });
                                },
                                child: const Padding(
                                  padding: EdgeInsets.only(left: 4),
                                  child: Icon(Icons.close, size: 16, color: _TreeGreenTheme.textMuted),
                                ),
                              )
                            else
                              const Icon(Icons.calendar_month_outlined, size: 18),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: _pickDeathDate,
                  borderRadius: BorderRadius.circular(14),
                  child: InputDecorator(
                    decoration: _dec(
                      'Date of Death',
                      icon: Icons.sentiment_very_dissatisfied_outlined,
                    ).copyWith(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: Text(deathDateText)),
                        if (_deathDate != null && !_clearDeathDate)
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _clearDeathDate = true;
                                _deathDate = null;
                              });
                            },
                            child: const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.close, size: 16, color: _TreeGreenTheme.textMuted),
                            ),
                          )
                        else
                          const Icon(Icons.calendar_month_outlined, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _barangayController,
                  decoration: _dec(_isAddMode ? 'Street/Brgy/District *' : 'Street/Brgy/District', icon: Icons.home_outlined),
                  validator: (v) {
                    if (_isAddMode && (v ?? '').trim().isEmpty) return 'Street/Brgy/District is required';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _cityController,
                  decoration: _dec(_isAddMode ? 'Town/Municipality/City *' : 'Town/Municipality/City', icon: Icons.location_city_outlined),
                  validator: (v) {
                    if (_isAddMode && (v ?? '').trim().isEmpty) return 'Town/Municipality/City is required';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _provinceController,
                  decoration: _dec(_isAddMode ? 'Province/State *' : 'Province/State', icon: Icons.map_outlined),
                  validator: (v) {
                    if (_isAddMode && (v ?? '').trim().isEmpty) return 'Province/State is required';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _countryController,
                  decoration: _dec(_isAddMode ? 'Country *' : 'Country', icon: Icons.public_outlined),
                  validator: (v) {
                    if (_isAddMode && (v ?? '').trim().isEmpty) return 'Country is required';
                    return null;
                  },
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
    required this.isHovered,
    required this.isSelected,
    required this.isDragging,
    required this.onHoverChanged,
    required this.dragEnabled,
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

  final bool isHovered;
  final bool isSelected;
  final bool isDragging;
  final ValueChanged<bool> onHoverChanged;
  final bool dragEnabled;

  @override
  State<AnimatedNode> createState() => _AnimatedNodeState();
}

class _AnimatedNodeState extends State<AnimatedNode> {
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
    // d.delta is already in scene coordinates — Flutter transforms pointer
    // events through the InteractiveViewer's render transform automatically.
    // Dividing by zoom would double-correct and cause nodes to move at the
    // wrong speed depending on zoom level.
    _localDrag += d.delta;

    // Update only the Positioned — no setState, no widget rebuild.
    _posNotifier.value = widget.topLeft + _localDrag;

    // Always assign a new Map so ValueNotifier's identical() check sees a
    // change and notifies listeners every frame — on mobile this is the
    // difference between connectors updating in real time vs. not at all.
    final n = widget.dragOverlayNotifier;
    if (n != null) {
      n.value = {...n.value, widget.node.id: _posNotifier.value};
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
        onExit: (_) => widget.onHoverChanged(false),
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
                size: widget.size,
                isSelected: widget.isSelected,
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
    required this.size,
    required this.isSelected,
  });

  final FamilyNode node;
  final Size size;
  final bool isSelected;


  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: isSelected ? Border.all(color: _TreeGreenTheme.selection, width: 2) : null,
      ),
      child: Material(
        elevation: 2,
        shadowColor: _TreeGreenTheme.shadow,
        borderRadius: BorderRadius.circular(16),
        color: node.isDeceased ? const Color(0xFFEEEEEE) : _TreeGreenTheme.surface,
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
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                              color: node.isDeceased
                                  ? Colors.grey.shade500
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (node.birthday != null) ...[
                            const SizedBox(height: 2),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: Center(
                                    child: node.isDeceased
                                        ? Text(
                                            '✝',
                                            style: TextStyle(
                                              fontSize: 13,
                                              height: 1,
                                              color: _TreeGreenTheme.textMuted,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.cake,
                                            size: 14,
                                            color: _TreeGreenTheme.textMuted,
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    node.isDeceased && node.deathDate != null
                                        ? 'Died ${formatDate(node.deathDate!)}'
                                        : formatDate(node.birthday!),
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
          ],
        ),
      ),
    );
  }
}

class _PopupActionButton extends StatelessWidget {
  const _PopupActionButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.enabled = true,
    this.width = 135,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;
  final double width;

  @override
  Widget build(BuildContext context) {
    // Determine if this is the delete button
    final isDelete = color == Colors.red;
    
    // Use green theme for enabled buttons (except delete stays red), gray for disabled
    final buttonColor = enabled 
        ? (isDelete ? Colors.red : _TreeGreenTheme.primary)
        : const Color(0xFFB0B0B0); // Gray color for disabled
    
    final bg = enabled 
        ? buttonColor.withAlpha(31) 
        : const Color(0xFFE8E8E8); // Lighter gray background for disabled
    
    final fg = enabled 
        ? buttonColor 
        : const Color(0xFF808080); // Darker gray text for disabled

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: enabled ? buttonColor.withAlpha(51) : const Color(0xFFD0D0D0),
          ),
        ),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
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
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final spousePaint = Paint()
      ..color = _TreeGreenTheme.connector
      ..strokeWidth = 3
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

    List<int> visibleParentIdsOf(FamilyNode child) {
      return child.parents
          .where((pid) => store.nodes.containsKey(pid))
          .where((pid) => positions.containsKey(pid))
          .toList()
        ..sort();
    }

    List<int> connectorParentIdsFor(FamilyNode child) {
      final parentIds = visibleParentIdsOf(child);
      if (parentIds.isEmpty) return parentIds;

      if (parentIds.length == 1) {
        final onlyParentId = parentIds.first;

        // If this is a newly connected child with only one explicit parent,
        // but existing siblings share this parent plus a co-parent, draw it on
        // that same family bus. This is intentionally gender-neutral and does
        // not depend on female/male parent pairing.
        final siblingParentSetCounts = <String, int>{};
        final siblingParentSets = <String, List<int>>{};

        for (final sibling in store.nodes.values) {
          if (sibling.id == child.id) continue;
          if (!positions.containsKey(sibling.id)) continue;
          if (!sibling.parents.contains(onlyParentId)) continue;

          final siblingParents = visibleParentIdsOf(sibling);
          if (siblingParents.length <= 1) continue;

          final key = siblingParents.join('_');
          siblingParentSetCounts[key] =
              (siblingParentSetCounts[key] ?? 0) + 1;
          siblingParentSets[key] = siblingParents;
        }

        if (siblingParentSetCounts.isNotEmpty) {
          final bestKey = siblingParentSetCounts.entries.toList()
            ..sort((a, b) {
              final byCount = b.value.compareTo(a.value);
              if (byCount != 0) return byCount;
              return a.key.compareTo(b.key);
            });
          return siblingParentSets[bestKey.first.key]!;
        }

        // Fallback for spouse pairs where the child has only one parent saved.
        final onlyParent = store.nodes[onlyParentId];
        if (onlyParent != null && onlyParent.spouses.isNotEmpty) {
          final spouseId = onlyParent.spouses.firstWhere(
            (sid) => positions.containsKey(sid),
            orElse: () => -1,
          );

          if (spouseId != -1) {
            return (<int>[onlyParentId, spouseId]..sort());
          }
        }
      }

      return parentIds;
    }

    for (final child in store.nodes.values) {
      if (child.parents.isEmpty) continue;
      if (!positions.containsKey(child.id)) continue;

      final parentIds = connectorParentIdsFor(child);
      if (parentIds.isEmpty) continue;

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