import 'package:app/screens/auth/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DesktopBody extends StatelessWidget {
  const DesktopBody({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Camello Family",
      theme: ThemeData(
        primarySwatch: Colors.green,
        fontFamily: 'Inter',
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade200,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      // Start with the asset preloader instead of login
      initialRoute: AssetPreloadPage.route,
      routes: {
        AssetPreloadPage.route: (_) => const AssetPreloadPage(),
        LoginPage.route: (_) => const LoginPage(),
        RegisterPage.route: (_) => const RegisterPage(),
      },
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                         ASSET PRELOADER (NEW)                              */
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

  // URLs used in AuthScaffold and AppLogo
  static const _backgroundUrl =
      'https://raw.githubusercontent.com/maeamarillo/camello-family-tree/main/assets/images/camello-background.jpg';
  static const _logoUrl =
      'https://raw.githubusercontent.com/maeamarillo/camello-family-tree/main/assets/images/camello-logo.PNG';

  @override
  void initState() {
    super.initState();
    // Precache after the first frame so we have a valid BuildContext
    WidgetsBinding.instance.addPostFrameCallback((_) => _preloadAssets());
  }

  Future<void> _preloadAssets() async {
    try {
      await Future.wait([
        precacheImage(const NetworkImage(_backgroundUrl), context),
        precacheImage(const NetworkImage(_logoUrl), context),
      ]);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = null;
      });
      // Navigate to login, replacing the preload page
      Navigator.pushReplacementNamed(context, LoginPage.route);
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
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(
          color: Colors.green,
        )),
      );
    }

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
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isLoading = true;
                      _error = null;
                    });
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

    // Should never reach here because on success we navigate away immediately
    return const SizedBox.shrink();
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
  final email = TextEditingController();
  final password = TextEditingController();
  bool show = false;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      await authService.value.signIn(
        email: email.text,
        password: password.text,
      );
      // AuthGate will detect login and show DashboardPage automatically.
    } on FirebaseAuthException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.message ?? 'Login failed')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Login failed: $e')),
      );
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
            subtitle: "Sign in to continue!",
            titleStyle: TextStyle(
              fontFamily: 'Calistoga',
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 30),
          AuthTextField(
            controller: email,
            label: 'Username',
            icon: Icons.mail,
          ),
          const SizedBox(height: 15),
          AuthTextField(
            controller: password,
            label: 'Password',
            icon: Icons.lock,
            obscureText: !show,
            suffix: IconButton(
              onPressed: () => setState(() => show = !show),
              icon: Icon(show ? Icons.visibility : Icons.visibility_off),
            ),
          ),
          const SizedBox(height: 25),
          PrimaryButton(text: 'Log In', onPressed: login),
          const SizedBox(height: 15),
          Center(
            child: LinkRow(
              leading: "Don’t have an account? ",
              action: "Register",
              onTap: () =>
                  Navigator.pushReplacementNamed(context, RegisterPage.route),
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
  final email = TextEditingController();
  final password = TextEditingController();
  bool show = false;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> register() async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      await authService.value.createAccount(
        email: email.text,
        password: password.text,
      );

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, LoginPage.route);
    } on FirebaseAuthException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.message ?? 'Error Register')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Register failed: $e')),
      );
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
            subtitle: "Let's sign you up!",
            titleStyle: TextStyle(
              fontFamily: 'Calistoga',
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 30),
          AuthTextField(
            controller: email,
            label: 'Username',
            icon: Icons.mail,
          ),
          const SizedBox(height: 15),
          AuthTextField(
            controller: password,
            label: 'Password',
            icon: Icons.lock,
            obscureText: !show,
            suffix: IconButton(
              onPressed: () => setState(() => show = !show),
              icon: Icon(show ? Icons.visibility : Icons.visibility_off),
            ),
          ),
          const SizedBox(height: 25),
          PrimaryButton(text: 'Register', onPressed: register),
          const SizedBox(height: 15),
          Center(
            child: LinkRow(
              leading: "Already have an account? ",
              action: "Sign in",
              onTap: () =>
                  Navigator.pushReplacementNamed(context, LoginPage.route),
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
        Text(
          title,
          style: titleStyle ??
              const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: subtitleStyle ??
              TextStyle(color: Colors.grey.shade600, fontSize: 14),
        ),
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
  const PrimaryButton({super.key, required this.text, required this.onPressed});

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
        child: Text(
          text,
          style: const TextStyle(fontSize: 16, color: Colors.white),
        ),
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
          child: const Text(''),
        ),
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