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
// Mounted at '/'.
// - Not signed in  → /home  (public, read-only view)
// - Signed in      → /home  (full edit access)
//
// /login and /register are only reached when the user explicitly
// chooses to sign in (e.g. from the "Log in to edit" prompt).
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sub = authService.value.authStateChanges().listen(_onAuthChanged);
    });
  }

  void _onAuthChanged(User? user) {
    if (!mounted) return;
    // Everyone goes to /home — unauthenticated users see read-only,
    // authenticated users get full edit access.
    Navigator.pushReplacementNamed(context, AppRoutes.home);
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