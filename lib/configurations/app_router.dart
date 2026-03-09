
import 'package:app/screens/auth/desktop_body.dart';
import 'package:flutter/material.dart';
import '../screens/family_tree_screen.dart';

class AppRouter {
  static const String initialRoute = '/login';

  static final Map<String, WidgetBuilder> routes = {
    '/login': (_) => const LoginPage(),
    '/': (_) => const FamilyTreeScreen(),
  };
}
