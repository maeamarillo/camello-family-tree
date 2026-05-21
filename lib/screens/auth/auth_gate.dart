// lib/screens/auth/auth_gate.dart
import 'dart:async';
import 'package:app/screens/auth/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ── Route constants ──────────────────────────────────────────────────────────
class AppRoutes {
  static const splash   = '/';
  static const preload  = '/preload';
  static const login    = '/login';
  static const register = '/register';
  static const home     = '/home';
}

// ── Auth guard ───────────────────────────────────────────────────────────────
//
// Mounted at '/'.  Listens to the Firebase auth stream exactly once and
// navigates to the correct route.  Using a StatefulWidget + StreamSubscription
// avoids the addPostFrameCallback-in-builder loop that caused the broken flow.
//
class AuthGate extends StatefulWidget {
  static const route = AppRoutes.splash;
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<User?>? _sub;

  @override
  void initState() {
    super.initState();

    // Delay navigation until after the first frame so Navigator is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sub = authService.value.authStateChanges().listen(_onAuthChanged);
    });
  }

  void _onAuthChanged(User? user) {
    if (!mounted) return;

    if (user == null) {
      // Not signed in → go through asset preloader then login
      Navigator.pushReplacementNamed(context, AppRoutes.preload);
    } else {
      // Already signed in → go straight to the app
      Navigator.pushReplacementNamed(context, AppRoutes.home);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: Colors.green)),
    );
  }
}