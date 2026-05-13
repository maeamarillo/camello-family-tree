// lib/pages/family_history_page.dart
import 'package:flutter/material.dart';

// ─── Theme (mirrors _TreeGreenTheme) ─────────────────────────────────────────
class _T {
  static const Color scaffold    = Color(0xFFF3FBF5);
  static const Color surface     = Color(0xFFFFFFFF);
  static const Color softSurface = Color(0xFFF7FCF8);
  static const Color primary     = Color(0xFF2E7D5A);
  static const Color accent      = Color(0xFF67B37F);
  static const Color border      = Color(0xFFCFE5D6);
  static const Color divider     = Color(0xFFD9EADF);
  static const Color textMuted   = Color(0xFF5F7468);
  static const Color textDark    = Color(0xFF1A2E25);
}

// ─── Breakpoint helper ───────────────────────────────────────────────────────
class _Screen {
  static bool isMobile(BuildContext ctx) => MediaQuery.of(ctx).size.width < 600;

  static double hPad(BuildContext ctx) {
    final w = MediaQuery.of(ctx).size.width;
    if (w < 600) return 16;
    if (w < 900) return 32;
    return 64;
  }

  static int galleryCols(BuildContext ctx) {
    final w = MediaQuery.of(ctx).size.width;
    if (w < 480) return 2;
    if (w < 900) return 3;
    return 4;
  }
}

// ─── Data models ─────────────────────────────────────────────────────────────

class FamilyHistorySection {
  const FamilyHistorySection({
    required this.title,
    required this.body,
    this.icon = Icons.menu_book_outlined,
  });

  final String title;
  final String body;
  final IconData icon;
}

class FamilyPhoto {
  const FamilyPhoto({
    required this.imageProvider,
    this.caption,
    this.year,
  });

  final ImageProvider imageProvider;
  final String? caption;
  final String? year;
}

// ─── Default placeholder content ─────────────────────────────────────────────

const List<FamilyHistorySection> _defaultSections = [
  FamilyHistorySection(
    title: 'Our Origins',
    icon: Icons.public,
    body:
        'The family traces its roots back to the early 1900s in the province of '
        'Batangas, Philippines. The patriarch, Lolo Andres, moved to Manila in '
        '1923 seeking work and eventually settled in Quiapo, where the family '
        'home still stands today.\n\n'
        'His wife, Lola Nena, was known throughout the neighbourhood for her '
        'generosity and her legendary sinigang. Together they raised seven '
        'children, each of whom would go on to build their own branch of the '
        'family tree.',
  ),
  FamilyHistorySection(
    title: 'Growing Through the Generations',
    icon: Icons.people_outline,
    body:
        'By the 1960s the family had spread across Luzon. Several of Lolo '
        "Andres' children studied at UP Diliman and went into medicine, law, "
        'and education. The eldest son, Tito Ben, served in the military and '
        'later became a community leader in Quezon City.\n\n'
        'The second generation kept close ties through annual reunions held '
        'every Holy Week at the Batangas ancestral home — a tradition that '
        'continues to this day.',
  ),
  FamilyHistorySection(
    title: 'Traditions & Values',
    icon: Icons.favorite_border,
    body:
        "Faith, education, and bayanihan are the cornerstones of the family's "
        'identity. Every major milestone — from baptisms to graduations — is '
        'celebrated together, often with a long table set out in the front yard '
        'and food that feeds twice the number of guests expected.\n\n'
        'The family motto, passed down by Lola Nena, is simple: '
        '"Ang pamilya ay kayamanan." (The family is our wealth.)',
  ),
  FamilyHistorySection(
    title: 'Looking Forward',
    icon: Icons.star_outline,
    body:
        'Today the family spans three continents, with members living in the '
        'Philippines, the United States, Canada, and Australia. Despite the '
        'distance, the WhatsApp group chat never sleeps.\n\n'
        'This family tree app was created to preserve these stories and '
        'connections for the generations still to come.',
  ),
];

// ─── Page ────────────────────────────────────────────────────────────────────

class FamilyHistoryPage extends StatefulWidget {
  const FamilyHistoryPage({
    super.key,
    this.familyName = 'Our Family History',
    this.coverSubtitle = 'A story told across generations',
    this.sections = _defaultSections,
    this.photos = const [],
  });

  final String familyName;
  final String coverSubtitle;
  final List<FamilyHistorySection> sections;
  final List<FamilyPhoto> photos;

  @override
  State<FamilyHistoryPage> createState() => _FamilyHistoryPageState();
}

class _FamilyHistoryPageState extends State<FamilyHistoryPage> {
  int? _expandedSection;
  int? _galleryIndex;

  @override
  Widget build(BuildContext context) {
    final hPad    = _Screen.hPad(context);
    final mobile  = _Screen.isMobile(context);
    final galCols = _Screen.galleryCols(context);

    return Scaffold(
      backgroundColor: _T.scaffold,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              _buildAppBar(context, mobile),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 40),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    SizedBox(height: mobile ? 20 : 28),

                    // ── Photo gallery ──────────────────────────────────────
                    if (widget.photos.isNotEmpty) ...[
                      _SectionHeader(
                        icon: Icons.photo_library_outlined,
                        label: 'Photo Gallery',
                        mobile: mobile,
                      ),
                      SizedBox(height: mobile ? 10 : 14),
                      _PhotoGallery(
                        photos: widget.photos,
                        columns: galCols,
                        onTap: (i) => setState(() => _galleryIndex = i),
                      ),
                      SizedBox(height: mobile ? 24 : 32),
                      const _FadeDivider(),
                      SizedBox(height: mobile ? 24 : 32),
                    ],

                    // ── Written sections ───────────────────────────────────
                    _SectionHeader(
                      icon: Icons.auto_stories_outlined,
                      label: 'Family Stories',
                      mobile: mobile,
                    ),
                    SizedBox(height: mobile ? 10 : 14),
                    ...List.generate(widget.sections.length, (i) {
                      return _ExpandableSection(
                        section: widget.sections[i],
                        isExpanded: _expandedSection == i,
                        mobile: mobile,
                        onTap: () => setState(() {
                          _expandedSection = _expandedSection == i ? null : i;
                        }),
                      );
                    }),
                  ]),
                ),
              ),
            ],
          ),

          // Full-screen photo overlay
          if (_galleryIndex != null)
            _FullScreenPhoto(
              photos: widget.photos,
              initialIndex: _galleryIndex!,
              onClose: () => setState(() => _galleryIndex = null),
            ),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context, bool mobile) {
    final expandedHeight = mobile ? 180.0 : 220.0;
    final iconSize       = mobile ? 52.0  : 64.0;
    final titleFontSize  = mobile ? 18.0  : 22.0;
    final subtitleSize   = mobile ? 12.0  : 13.0;

    return SliverAppBar(
      expandedHeight: expandedHeight,
      pinned: true,
      backgroundColor: _T.primary,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.white),
        onPressed: () => Navigator.of(context).pop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1B5E3B), Color(0xFF4FA36D)],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: mobile ? 30 : 40),
                    Container(
                      width: iconSize,
                      height: iconSize,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white30, width: 2),
                      ),
                      child: Icon(
                        Icons.account_tree,
                        color: Colors.white,
                        size: iconSize * 0.46,
                      ),
                    ),
                    SizedBox(height: mobile ? 10 : 12),
                    Text(
                      widget.familyName,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.coverSubtitle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: subtitleSize,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
       
        titlePadding: const EdgeInsets.only(left: 56, bottom: 16),
        collapseMode: CollapseMode.pin,
      ),
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.mobile,
  });

  final IconData icon;
  final String label;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: _T.primary, size: mobile ? 18 : 20),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: mobile ? 15 : 16,
            fontWeight: FontWeight.w800,
            color: _T.primary,
          ),
        ),
      ],
    );
  }
}

// ─── Fade divider ─────────────────────────────────────────────────────────────

class _FadeDivider extends StatelessWidget {
  const _FadeDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _T.divider.withValues(alpha: 0),
            _T.divider,
            _T.divider.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

// ─── Expandable written section ───────────────────────────────────────────────

class _ExpandableSection extends StatelessWidget {
  const _ExpandableSection({
    required this.section,
    required this.isExpanded,
    required this.mobile,
    required this.onTap,
  });

  final FamilyHistorySection section;
  final bool isExpanded;
  final bool mobile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = mobile ? 12.0 : 14.0;

    return Padding(
      padding: EdgeInsets.only(bottom: mobile ? 8 : 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _T.surface,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: isExpanded ? _T.accent : _T.border,
            width: isExpanded ? 1.5 : 1,
          ),
          boxShadow: isExpanded
              ? [
                  BoxShadow(
                    color: _T.primary.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  const BoxShadow(
                    color: Color(0x0A1F3A29),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          children: [
            // Header tap target — taller on mobile for easier tapping
            InkWell(
              borderRadius: BorderRadius.circular(radius),
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: mobile ? 16 : 14,
                ),
                child: Row(
                  children: [
                    Container(
                      width: mobile ? 40 : 36,
                      height: mobile ? 40 : 36,
                      decoration: BoxDecoration(
                        color: isExpanded
                            ? _T.primary.withValues(alpha: 0.12)
                            : _T.softSurface,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        section.icon,
                        size: mobile ? 20 : 18,
                        color: isExpanded ? _T.primary : _T.textMuted,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        section.title,
                        style: TextStyle(
                          fontSize: mobile ? 14 : 15,
                          fontWeight: FontWeight.w700,
                          color: isExpanded ? _T.primary : _T.textDark,
                        ),
                      ),
                    ),
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: _T.textMuted,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),

            // Body
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState: isExpanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: Padding(
                padding: EdgeInsets.fromLTRB(14, 0, 14, mobile ? 16 : 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 1, color: _T.divider),
                    SizedBox(height: mobile ? 12 : 14),
                    Text(
                      section.body,
                      style: TextStyle(
                        fontSize: mobile ? 13.5 : 14,
                        height: 1.75,
                        color: _T.textDark,
                      ),
                    ),
                  ],
                ),
              ),
              secondChild: const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Photo gallery grid ───────────────────────────────────────────────────────

class _PhotoGallery extends StatelessWidget {
  const _PhotoGallery({
    required this.photos,
    required this.columns,
    required this.onTap,
  });

  final List<FamilyPhoto> photos;
  final int columns;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: photos.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemBuilder: (_, i) {
        final p = photos[i];
        return GestureDetector(
          onTap: () => onTap(i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image(image: p.imageProvider, fit: BoxFit.cover),
                if (p.caption != null || p.year != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xCC000000), Colors.transparent],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (p.year != null)
                            Text(
                              p.year!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (p.caption != null)
                            Text(
                              p.caption!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
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
      },
    );
  }
}

// ─── Full-screen photo viewer ─────────────────────────────────────────────────

class _FullScreenPhoto extends StatefulWidget {
  const _FullScreenPhoto({
    required this.photos,
    required this.initialIndex,
    required this.onClose,
  });

  final List<FamilyPhoto> photos;
  final int initialIndex;
  final VoidCallback onClose;

  @override
  State<_FullScreenPhoto> createState() => _FullScreenPhotoState();
}

class _FullScreenPhotoState extends State<_FullScreenPhoto> {
  late final PageController _pc;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pc = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo      = widget.photos[_current];
    final safeTop    = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return GestureDetector(
      onTap: widget.onClose,
      child: Container(
        color: Colors.black.withValues(alpha: 0.92),
        child: Stack(
          children: [
            // Swipeable photos
            PageView.builder(
              controller: _pc,
              itemCount: widget.photos.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (_, i) => Center(
                child: InteractiveViewer(
                  child: Image(
                    image: widget.photos[i].imageProvider,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),

            // Caption — respects safe area on notched phones
            if (photo.caption != null || photo.year != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: safeBottom + 40,
                child: Column(
                  children: [
                    if (photo.year != null)
                      Text(
                        photo.year!,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    if (photo.caption != null)
                      Text(
                        photo.caption!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),

            // Close button — respects status bar / notch
            Positioned(
              top: safeTop + 12,
              right: 16,
              child: GestureDetector(
                onTap: widget.onClose,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),

            // Page indicator dots
            if (widget.photos.length > 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: safeBottom + 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.photos.length, (i) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: _current == i ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _current == i ? Colors.white : Colors.white38,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}