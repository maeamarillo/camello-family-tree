// lib/screens/admin/admin_page.dart
//
// Self-contained Admin Panel.
//
// Flow:
//   /admin → _AdminLoginView  (if no admin session)
//          → _AdminDashboard  (if signed in AND uid exists in admins/{uid})
//
// The admin session is a real Firebase Auth sign-in, but gated so that only
// emails present in the Firestore `admins` collection can proceed past the
// login screen. The panel has its own logout that does NOT affect the main
// family-tree user session (they share the same FirebaseAuth instance, so
// logging out here logs out everyone — we handle that with a warning dialog).
//
// Tabs inside the dashboard:
//   1. Pending Registrations — approve / reject sign-up requests
//   2. Manage Admins         — add / remove admin email entries
//
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ─── Theme ───────────────────────────────────────────────────────────────────

class _T {
  static const Color scaffold     = Color(0xFFF3FBF5);
  static const Color surface      = Color(0xFFFFFFFF);
  static const Color primary      = Color(0xFF2E7D5A);
  static const Color border       = Color(0xFFCFE5D6);
  static const Color divider      = Color(0xFFD9EADF);
  static const Color textMuted    = Color(0xFF5F7468);
  static const Color approveGreen = Color(0xFF49A04A);
  static const Color rejectRed    = Color(0xFFD32F2F);
  static const Color pendingAmber = Color(0xFFF9A825);
  static const Color adminBlue    = Color(0xFF1565C0);
}

// ─── Entry point ─────────────────────────────────────────────────────────────

class AdminPage extends StatefulWidget {
  static const route = '/admin';
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  // null  = still checking
  // false = not an admin (show login)
  // true  = verified admin (show dashboard)
  bool? _isAdmin;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  // Check whether the currently signed-in Firebase user is in admins/{uid}.
  Future<void> _checkSession() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isAdmin = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('admins')
          .doc(uid)
          .get();
      if (mounted) setState(() => _isAdmin = doc.exists);
    } catch (_) {
      if (mounted) setState(() => _isAdmin = false);
    }
  }

  void _onLoginSuccess() => setState(() => _isAdmin = true);

  void _onLogout() => setState(() => _isAdmin = false);

  @override
  Widget build(BuildContext context) {
    // Still verifying
    if (_isAdmin == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.green)),
      );
    }

    if (_isAdmin == false) {
      return _AdminLoginView(onSuccess: _onLoginSuccess);
    }

    return _AdminDashboard(onLogout: _onLogout);
  }
}

// ─── Login view ──────────────────────────────────────────────────────────────

class _AdminLoginView extends StatefulWidget {
  final VoidCallback onSuccess;
  const _AdminLoginView({required this.onSuccess});

  @override
  State<_AdminLoginView> createState() => _AdminLoginViewState();
}

class _AdminLoginViewState extends State<_AdminLoginView> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _showPassword  = false;
  bool _loading       = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading) return;
    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter your email and password.');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      // 1. Sign in with Firebase Auth
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // 2. Verify the UID exists in the admins collection
      final doc = await FirebaseFirestore.instance
          .collection('admins')
          .doc(cred.user!.uid)
          .get();

      if (!doc.exists) {
        // Valid Firebase account but not an admin — sign back out and block.
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          setState(() {
            _loading = false;
            _error   = 'This account does not have admin access.';
          });
        }
        return;
      }

      if (mounted) {
        setState(() => _loading = false);
        widget.onSuccess();
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error   = e.message ?? 'Login failed.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error   = 'Login failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _T.scaffold,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(20),
              color: _T.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            // ignore: deprecated_member_use
                            color: _T.primary.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.admin_panel_settings,
                              color: _T.primary, size: 28),
                        ),
                        const SizedBox(width: 14),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Admin Panel',
                              style: TextStyle(
                                fontFamily: 'Calistoga',
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: _T.primary,
                              ),
                            ),
                            Text(
                              'Sign in to continue',
                              style: TextStyle(
                                fontSize: 13,
                                color: _T.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 30),

                    // Error banner
                    if (_error != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          // ignore: deprecated_member_use
                          color: _T.rejectRed.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              // ignore: deprecated_member_use
                              color: _T.rejectRed.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: _T.rejectRed, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                    color: _T.rejectRed, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],

                    // Email
                    _AdminTextField(
                      controller: _emailCtrl,
                      label: 'Admin Email',
                      icon: Icons.mail_outline,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 14),

                    // Password
                    _AdminTextField(
                      controller: _passwordCtrl,
                      label: 'Password',
                      icon: Icons.lock_outline,
                      obscureText: !_showPassword,
                      suffix: IconButton(
                        icon: Icon(_showPassword
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                      ),
                      onSubmitted: (_) => _login(),
                    ),

                    const SizedBox(height: 24),

                    // Login button
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _T.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Sign In',
                                style: TextStyle(fontSize: 15)),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Back link
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          '← Back to Family Tree',
                          style: TextStyle(color: _T.textMuted, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Dashboard (tabs) ─────────────────────────────────────────────────────────

class _AdminDashboard extends StatefulWidget {
  final VoidCallback onLogout;
  const _AdminDashboard({required this.onLogout});

  @override
  State<_AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<_AdminDashboard>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // Approve / reject callbacks are defined here so they can share _snack.

  Future<void> _approve(Map<String, dynamic> data, String docId) async {
    final email    = data['email']    as String? ?? '';
    final password = data['password'] as String? ?? '';
    final name     = data['name']     as String? ?? '';

    if (email.isEmpty || password.isEmpty) {
      _snack('Missing email or password in the request.', isError: true);
      return;
    }

    try {
      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(cred.user!.uid)
          .set({
        'email'     : email,
        'name'      : name,
        'approved'  : true,
        'approvedAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('pending_registrations')
          .doc(docId)
          .delete();

      _snack('$email approved successfully.');
    } on FirebaseAuthException catch (e) {
      _snack(e.message ?? 'Approval failed.', isError: true);
    } catch (e) {
      _snack('Approval failed: $e', isError: true);
    }
  }

  Future<void> _reject(String docId, String email) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject registration?'),
        content: Text('This will permanently delete the request for $email.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _T.rejectRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await FirebaseFirestore.instance
          .collection('pending_registrations')
          .doc(docId)
          .delete();
      _snack('Request for $email rejected.');
    } catch (e) {
      _snack('Reject failed: $e', isError: true);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign out of Admin Panel?'),
        content: const Text(
          'This will sign out the current Firebase session. '
          'Anyone currently logged in to the family tree will also be signed out.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _T.rejectRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await FirebaseAuth.instance.signOut();
    if (mounted) widget.onLogout();
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? _T.rejectRed : _T.approveGreen,
    ));
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentEmail =
        FirebaseAuth.instance.currentUser?.email ?? 'Admin';

    return Scaffold(
      backgroundColor: _T.scaffold,
      appBar: AppBar(
        backgroundColor: _T.primary,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Admin Panel',
              style: TextStyle(fontFamily: 'Calistoga', fontSize: 19),
            ),
            Text(
              currentEmail,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Back to Family Tree',
            icon: const Icon(Icons.home_outlined),
            onPressed: () => Navigator.pushNamedAndRemoveUntil(
              context,
              '/home',
              (route) => false,
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.pending_actions), text: 'Pending'),
            Tab(icon: Icon(Icons.manage_accounts), text: 'Manage Admins'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _PendingList(onApprove: _approve, onReject: _reject),
          _ManageAdmins(currentEmail: currentEmail),
        ],
      ),
    );
  }
}

// ─── Tab 1 — Pending registrations ───────────────────────────────────────────

class _PendingList extends StatelessWidget {
  final Future<void> Function(Map<String, dynamic> data, String docId) onApprove;
  final Future<void> Function(String docId, String email) onReject;

  const _PendingList({required this.onApprove, required this.onReject});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('pending_registrations')
          .orderBy('requestedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.green));
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.check_circle_outline,
                    size: 64, color: _T.approveGreen),
                SizedBox(height: 16),
                Text('No pending registrations',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
                SizedBox(height: 6),
                Text('All caught up!',
                    style: TextStyle(color: _T.textMuted)),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.pending_actions,
                      color: _T.pendingAmber, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '${docs.length} pending request${docs.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: _T.textMuted),
                  ),
                ],
              ),
            ),
            const Divider(color: _T.divider, height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                    vertical: 12, horizontal: 16),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final doc   = docs[i];
                  final data  = doc.data() as Map<String, dynamic>;
                  final email = data['email'] as String? ?? '(no email)';
                  final name  = data['name']  as String? ?? '(no name)';
                  final ts    = data['requestedAt'] as Timestamp?;
                  final date  = ts != null ? _fmt(ts.toDate()) : 'Unknown date';

                  return _PendingCard(
                    email    : email,
                    name     : name,
                    date     : date,
                    onApprove: () => onApprove(data, doc.id),
                    onReject : () => onReject(doc.id, email),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  static String _fmt(DateTime dt) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${p(dt.month)}-${p(dt.day)} ${p(dt.hour)}:${p(dt.minute)}';
  }
}

// ─── Tab 2 — Manage Admins ───────────────────────────────────────────────────

class _ManageAdmins extends StatefulWidget {
  final String currentEmail;
  const _ManageAdmins({required this.currentEmail});

  @override
  State<_ManageAdmins> createState() => _ManageAdminsState();
}

class _ManageAdminsState extends State<_ManageAdmins> {
  final _newEmailCtrl = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _newEmailCtrl.dispose();
    super.dispose();
  }

  // Add a new admin by email.
  // We look up the email in Firebase Auth via a Cloud Function — but since
  // Cloud Functions add complexity, we instead write a placeholder doc keyed
  // by email (no UID yet). On their next login the AdminPage._checkSession()
  // check looks up by UID; to bridge this gap we also store email in the doc
  // and do a secondary query by email in _checkSession (see note below).
  //
  // Simpler alternative used here: store the email in a sub-collection
  // `admin_emails/{email}` which is checked during login in addition to
  // `admins/{uid}`. When the invited person logs in for the first time their
  // UID gets written to `admins/{uid}` automatically.
  Future<void> _addAdmin() async {
    final email = _newEmailCtrl.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      _snack('Enter a valid email address.', isError: true);
      return;
    }

    setState(() => _adding = true);
    try {
      String? userId;
      
      // Attempt 1: Query users collection by 'email' field
      try {
        final userQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();

        if (userQuery.docs.isNotEmpty) {
          userId = userQuery.docs.first.id;
        }
      } catch (e) {
        // Query might fail - continue to next attempt
      }

      // Attempt 2: Query users collection by 'emailLower' field
      if (userId == null) {
        try {
          final userQuery = await FirebaseFirestore.instance
              .collection('users')
              .where('emailLower', isEqualTo: email)
              .limit(1)
              .get();

          if (userQuery.docs.isNotEmpty) {
            userId = userQuery.docs.first.id;
          }
        } catch (e) {
          // Query might fail - continue to next attempt
        }
      }

      // Attempt 3: Scan all users and find by email (slower but always works)
      if (userId == null) {
        try {
          final allUsers = await FirebaseFirestore.instance
              .collection('users')
              .get();

          for (var doc in allUsers.docs) {
            final data = doc.data();
            final docEmail = (data['email'] as String?)?.toLowerCase() ?? 
                            (data['emailLower'] as String?) ?? '';
            
            if (docEmail == email) {
              userId = doc.id;
              break;
            }
          }
        } catch (e) {
          // Scan failed
        }
      }

      // If still not found, inform user
      if (userId == null) {
        if (mounted) {
          _snack('User with email "$email" not found. They must sign up first.', isError: true);
        }
        return;
      }

      // Write to admins collection using userId as document ID
      await FirebaseFirestore.instance
          .collection('admins')
          .doc(userId)
          .set({
        'email'    : email,
        'addedBy'  : widget.currentEmail,
        'addedAt'  : FieldValue.serverTimestamp(),
      });

      _newEmailCtrl.clear();
      _snack('$email added to admin allowlist.');
    } catch (e) {
      _snack('Failed to add admin: $e', isError: true);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _removeAdmin(String docId, String email) async {
    // docId is the userId (document ID in admins collection)
    // Prevent removing yourself
    if (email == widget.currentEmail) {
      _snack('You cannot remove yourself.', isError: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove admin?'),
        content: Text(
            '$email will no longer have access to the Admin Panel.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _T.rejectRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await FirebaseFirestore.instance
          .collection('admins')
          .doc(docId)
          .delete();
      _snack('$email removed from admin allowlist.');
    } catch (e) {
      _snack('Remove failed: $e', isError: true);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? _T.rejectRed : _T.approveGreen,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Add new admin ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: Material(
            elevation: 1,
            borderRadius: BorderRadius.circular(14),
            color: _T.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add Admin',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: _T.primary),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Enter the email of the person you want to grant admin access.',
                    style: TextStyle(fontSize: 12, color: _T.textMuted),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _AdminTextField(
                          controller: _newEmailCtrl,
                          label: 'Email address',
                          icon: Icons.person_add_alt_1_outlined,
                          keyboardType: TextInputType.emailAddress,
                          onSubmitted: (_) => _addAdmin(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _adding ? null : _addAdmin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _T.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _adding
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Add'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 14),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Current Admins',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: _T.textMuted),
          ),
        ),
        const SizedBox(height: 6),
        const Divider(color: _T.divider, height: 1),

        // ── Admin list ──
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('admins')
                .orderBy('addedAt', descending: false)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: Colors.green));
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              final docs = snapshot.data?.docs ?? [];

              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.group_outlined,
                          size: 48, color: _T.textMuted),
                      SizedBox(height: 12),
                      Text('No admins in allowlist yet.',
                          style: TextStyle(color: _T.textMuted)),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(
                    vertical: 12, horizontal: 16),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final doc   = docs[i];
                  final data  = doc.data() as Map<String, dynamic>;
                  final email    = data['email']   as String? ?? doc.id;
                  final addedBy  = data['addedBy'] as String? ?? '—';
                  final isSelf   = email == widget.currentEmail;

                  return Material(
                    elevation: 1,
                    borderRadius: BorderRadius.circular(12),
                    color: _T.surface,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor:
                                // ignore: deprecated_member_use
                                _T.adminBlue.withOpacity(0.10),
                            child: Text(
                              email.isNotEmpty
                                  ? email[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  color: _T.adminBlue,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        email,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isSelf) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          // ignore: deprecated_member_use
                                          color: _T.primary.withOpacity(0.12),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          'You',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: _T.primary,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Text(
                                  'Added by $addedBy',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: _T.textMuted),
                                ),
                              ],
                            ),
                          ),
                          if (!isSelf)
                            IconButton(
                              tooltip: 'Remove admin',
                              icon: const Icon(Icons.remove_circle_outline,
                                  color: _T.rejectRed, size: 20),
                              onPressed: () =>
                                  _removeAdmin(doc.id, email),
                            ),
                        ],
                      ),
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
}

// ─── Pending request card ─────────────────────────────────────────────────────

class _PendingCard extends StatefulWidget {
  final String       email;
  final String       name;
  final String       date;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _PendingCard({
    required this.email,
    required this.name,
    required this.date,
    required this.onApprove,
    required this.onReject,
  });

  @override
  State<_PendingCard> createState() => _PendingCardState();
}

class _PendingCardState extends State<_PendingCard> {
  bool _busy = false;

  Future<void> _run(VoidCallback action) async {
    setState(() => _busy = true);
    try {
      await Future.microtask(action);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(14),
      color: _T.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              // ignore: deprecated_member_use
              backgroundColor: _T.primary.withOpacity(0.12),
              child: Text(
                widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _T.primary),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(widget.email,
                      style: const TextStyle(
                          fontSize: 13, color: _T.textMuted)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.access_time,
                          size: 12, color: _T.textMuted),
                      const SizedBox(width: 4),
                      Text(widget.date,
                          style: const TextStyle(
                              fontSize: 11, color: _T.textMuted)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (_busy)
              const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: 'Approve',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _run(widget.onApprove),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          // ignore: deprecated_member_use
                          color: _T.approveGreen.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.check_circle_outline,
                            color: _T.approveGreen, size: 22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Reject',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _run(widget.onReject),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          // ignore: deprecated_member_use
                          color: _T.rejectRed.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.cancel_outlined,
                            color: _T.rejectRed, size: 22),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared text-field widget ─────────────────────────────────────────────────

class _AdminTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;

  const _AdminTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText    = false,
    this.suffix,
    this.keyboardType,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller     : controller,
      obscureText    : obscureText,
      keyboardType   : keyboardType,
      onSubmitted    : onSubmitted,
      style          : const TextStyle(fontSize: 14, color: Colors.black87),
      decoration: InputDecoration(
        labelText         : label,
        prefixIcon        : Icon(icon, color: _T.primary, size: 20),
        suffixIcon        : suffix,
        floatingLabelStyle: const TextStyle(color: _T.primary),
        filled            : true,
        fillColor         : const Color(0xFFF5FAF6),
        contentPadding    : const EdgeInsets.symmetric(
            horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _T.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _T.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _T.primary, width: 1.5),
        ),
      ),
    );
  }
}