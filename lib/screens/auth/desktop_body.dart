// lib/screens/auth/desktop_body.dart
//
// Auth screens: preloader → login → register.
// Plain screens only — no nested MaterialApp.
// All route strings come from AppRoutes in auth_gate.dart.
//
import 'package:app/screens/auth/auth_gate.dart';
import 'package:app/screens/auth/auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/* -------------------------------------------------------------------------- */
/*                         ASSET PRELOADER                                    */
/* -------------------------------------------------------------------------- */

class AssetPreloadPage extends StatefulWidget {
  static const route = '/preload';
  const AssetPreloadPage({super.key});

  @override
  State<AssetPreloadPage> createState() => _AssetPreloadPageState();
}

class _AssetPreloadPageState extends State<AssetPreloadPage> {
  bool _isLoading = true;
  String? _error;

  static const _backgroundUrl =
      'https://raw.githubusercontent.com/maeamarillo/camello-family-tree/main/assets/images/camello-background.jpg';
  static const _logoUrl =
      'https://raw.githubusercontent.com/maeamarillo/camello-family-tree/main/assets/images/camello-logo.PNG';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _preloadAssets());
  }

  Future<void> _preloadAssets() async {
    try {
      await Future.wait([
        precacheImage(const NetworkImage(_backgroundUrl), context),
        precacheImage(const NetworkImage(_logoUrl), context),
      ]);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.login);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load required assets. Check your connection.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() { _isLoading = true; _error = null; });
                    _preloadAssets();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Loading (default) — spinner while assets download
    return Scaffold(
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.green)
            : const SizedBox.shrink(),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                                   LOGIN                                    */
/* -------------------------------------------------------------------------- */

class LoginPage extends StatefulWidget {
  static const route = '/login';
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email    = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      await authService.value.signIn(
        email: _email.text.trim(),
        password: _password.text,
      );
      // Firebase auth stream fires → AuthGate is NOT in the stack anymore
      // (we used pushReplacement to get here), so we navigate to /home
      // directly here as well, for reliability.
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.home);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Login failed')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: AppLogo()),
          const SizedBox(height: 20),
          const AuthHeader(
            title: 'Log In',
            subtitle: 'Sign in to continue!',
            titleStyle: TextStyle(
              fontFamily: 'Calistoga',
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 30),
          AuthTextField(
            controller: _email,
            label: 'Email',
            icon: Icons.mail,
          ),
          const SizedBox(height: 15),
          AuthTextField(
            controller: _password,
            label: 'Password',
            icon: Icons.lock,
            obscureText: !_showPassword,
            suffix: IconButton(
              onPressed: () => setState(() => _showPassword = !_showPassword),
              icon: Icon(_showPassword ? Icons.visibility : Icons.visibility_off),
            ),
          ),
          const SizedBox(height: 25),
          PrimaryButton(
            text: _loading ? 'Signing in…' : 'Log In',
            onPressed: _loading ? () {} : _login,
          ),
          const SizedBox(height: 15),
          Center(
            child: LinkRow(
              leading: "Don't have an account? ",
              action: 'Register',
              onTap: () => Navigator.pushReplacementNamed(
                  context, AppRoutes.register),
            ),
          ),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                                  REGISTER                                  */
/* -------------------------------------------------------------------------- */

class RegisterPage extends StatefulWidget {
  static const route = '/register';
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _name     = TextEditingController();
  final _email    = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  // Submits a pending registration request to Firestore.
  // An admin must approve it from the Admin Panel before the user can log in.
  Future<void> _register() async {
    if (_loading) return;

    final email    = _email.text.trim();
    final password = _password.text;
    final name     = _name.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields.')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      await FirebaseFirestore.instance
          .collection('pending_registrations')
          .add({
        'name'       : name,
        'email'      : email,
        // ⚠️  Storing the password in Firestore is a simplified approach.
        // For production consider Firebase sendSignInLinkToEmail instead.
        'password'   : password,
        'status'     : 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Text('Request Submitted'),
          content: const Text(
            'Your registration request has been sent for admin approval. '
            'You will be able to log in once it is approved.',
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF49A04A),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.login);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Request failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Center(child: AppLogo()),
          const SizedBox(height: 20),
          const AuthHeader(
            title: 'Register',
            subtitle: "Request an account — pending admin approval.",
            titleStyle: TextStyle(
              fontFamily: 'Calistoga',
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 30),
          AuthTextField(
            controller: _name,
            label: 'Full Name',
            icon: Icons.person,
          ),
          const SizedBox(height: 15),
          AuthTextField(
            controller: _email,
            label: 'Email',
            icon: Icons.mail,
          ),
          const SizedBox(height: 15),
          AuthTextField(
            controller: _password,
            label: 'Password',
            icon: Icons.lock,
            obscureText: !_showPassword,
            suffix: IconButton(
              onPressed: () =>
                  setState(() => _showPassword = !_showPassword),
              icon: Icon(
                  _showPassword ? Icons.visibility : Icons.visibility_off),
            ),
          ),
          const SizedBox(height: 25),
          PrimaryButton(
            text: _loading ? 'Creating account…' : 'Register',
            onPressed: _loading ? () {} : _register,
          ),
          const SizedBox(height: 15),
          Center(
            child: LinkRow(
              leading: 'Already have an account? ',
              action: 'Sign in',
              onTap: () => Navigator.pushReplacementNamed(
                  context, AppRoutes.login),
            ),
          ),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                            SHARED COMPONENTS                               */
/* -------------------------------------------------------------------------- */

class AuthScaffold extends StatelessWidget {
  final Widget child;
  const AuthScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        alignment: Alignment.center,
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: NetworkImage(
              'https://raw.githubusercontent.com/maeamarillo/camello-family-tree/main/assets/images/camello-background.jpg',
            ),
            fit: BoxFit.cover,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class AppLogo extends StatelessWidget {
  const AppLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.network(
      'https://raw.githubusercontent.com/maeamarillo/camello-family-tree/main/assets/images/camello-logo.PNG',
      width: 200,
      height: 200,
    );
  }
}

class AuthHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;

  const AuthHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.titleStyle,
    this.subtitleStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: titleStyle ??
                const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(subtitle,
            style: subtitleStyle ??
                TextStyle(color: Colors.grey.shade600, fontSize: 14)),
      ],
    );
  }
}

class AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final Widget? suffix;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: const TextStyle(
        fontSize: 16,
        color: Colors.black,
        fontWeight: FontWeight.w500,
        fontFamily: 'Inter',
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.green),
        suffixIcon: suffix,
        floatingLabelStyle: const TextStyle(color: Colors.green),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  const PrimaryButton(
      {super.key, required this.text, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF49A04A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 16, color: Colors.white)),
      ),
    );
  }
}

class LinkRow extends StatelessWidget {
  final String leading;
  final String action;
  final VoidCallback onTap;

  const LinkRow({
    super.key,
    required this.leading,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(leading, style: const TextStyle(color: Colors.grey)),
        GestureDetector(
          onTap: onTap,
          child: Text(
            action,
            style: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}