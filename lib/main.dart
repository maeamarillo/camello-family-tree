// lib/main.dart
import 'package:app/screens/auth/auth_gate.dart';
import 'package:app/screens/auth/desktop_body.dart';
import 'package:app/screens/family_tree_screen.dart';
import 'package:app/services/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const CamelloApp());
}

class CamelloApp extends StatelessWidget {
  const CamelloApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Camello Family',
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

      initialRoute: AuthGate.route,

      routes: {
        // Entry point — checks auth and redirects
        AuthGate.route:         (_) => const AuthGate(),

        // Auth flow (public)
        AssetPreloadPage.route: (_) => const AssetPreloadPage(),
        LoginPage.route:        (_) => const LoginPage(),
        RegisterPage.route:     (_) => const RegisterPage(),

        // Public — shows the family tree regardless of auth state
        AppRoutes.home:         (_) => const FamilyTreeScreen(),
      },

      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (_) => const AuthGate(),
      ),
    );
  }
}