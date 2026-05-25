// lib/main.dart
import 'package:app/screens/admin/admin_page.dart';
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

      // /home is the default landing page for everyone.
      // /login and /register are accessed directly — no redirect intercepts them.
      initialRoute: AppRoutes.home,

      routes: {
        AppRoutes.home:         (_) => const FamilyTreeScreen(),
        AppRoutes.login:        (_) => const LoginPage(),
        AppRoutes.register:     (_) => const RegisterPage(),
        AppRoutes.admin:        (_) => const AdminPage(),
        AssetPreloadPage.route: (_) => const AssetPreloadPage(),
      },

      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (_) => const FamilyTreeScreen(),
      ),
    );
  }
}