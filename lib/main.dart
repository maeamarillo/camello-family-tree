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

      initialRoute: AuthGate.route, // '/' → always lands on /home

      routes: {
        // Splash — checks auth then sends everyone to /home
        AuthGate.route:         (_) => const AuthGate(),

        // Public family tree — readable by anyone
        AppRoutes.home:         (_) => const FamilyTreeScreen(),

        // Auth flow — only reached via explicit "Log in" action
        AssetPreloadPage.route: (_) => const AssetPreloadPage(),
        LoginPage.route:        (_) => const LoginPage(),
        RegisterPage.route:     (_) => const RegisterPage(),
      },

      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (_) => const AuthGate(),
      ),
    );
  }
}