import 'package:app/screens/auth/auth_service.dart';
import 'package:app/screens/family_tree_screen.dart';
import 'package:flutter/material.dart';
import 'desktop_body.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: authService,
      builder: (context, svc, _) {
        return StreamBuilder(
          stream: svc.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final user = snapshot.data;
            if (user == null) {
              // not signed in -> show your Login/Register material app
              return const DesktopBody();
            }

            // signed in -> show dashboard
            return const FamilyTreeScreen();
          },
        );
      },
    );
  }
}
