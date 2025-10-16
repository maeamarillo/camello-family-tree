import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

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

        // 👇 Global textfield styling
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade200, // default background
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none, // no outline
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none, // still no outline
          ),
        ),
      ),
      initialRoute: LoginPage.route,
      routes: {
        LoginPage.route: (_) => const LoginPage(),
        RegisterPage.route: (_) => const RegisterPage(),
      },
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
  final email = TextEditingController();
  final password = TextEditingController();
  bool show = false;

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: const AppLogo()),
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
            icon: LucideIcons.mail,
          ),
          const SizedBox(height: 15),
          AuthTextField(
            controller: password,
            label: 'Password',
            icon: LucideIcons.lock,
            obscureText: !show,
            suffix: IconButton(
              onPressed: () => setState(() => show = !show),
              icon: Icon(show ? Icons.visibility : Icons.visibility_off),
            ),
          ),
          const SizedBox(height: 25),
          PrimaryButton(text: 'Log In', onPressed: () {}),
          const SizedBox(height: 15),
          Center(
            child: LinkRow(
              leading: "Don’t have an account? ",
              action: "Register",
              onTap:
                  () => Navigator.pushReplacementNamed(
                    context,
                    RegisterPage.route,
                  ),
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
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(child: const AppLogo()),
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
            icon: LucideIcons.mail,
          ),
          const SizedBox(height: 15),
          AuthTextField(
            controller: password,
            label: 'Password',
            icon: LucideIcons.lock,
            obscureText: !show,
            suffix: IconButton(
              onPressed: () => setState(() => show = !show),
              icon: Icon(show ? Icons.visibility : Icons.visibility_off),
            ),
          ),
          const SizedBox(height: 25),
          PrimaryButton(text: 'Register', onPressed: () {}),
          const SizedBox(height: 15),
          Center(
            child: LinkRow(
              leading: "Already have an account? ",
              action: "Sign in",
              onTap:
                  () =>
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
            image: AssetImage('images/camello-background.jpg'),
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
    return Column(
      children: [
        Image.asset('images/camello-logo.png', width: 200, height: 200),
      ],
    );
  }
}

class AuthHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final TextStyle? titleStyle; // 👈 add this
  final TextStyle? subtitleStyle; // (optional, for future use)

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
          style:
              titleStyle ??
              const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style:
              subtitleStyle ??
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
        // contentPadding: const EdgeInsets.only(
        //   left: 30, // shift right
        // ),
        // No need for fillColor, border, focusedBorder, etc.
        // They come from ThemeData.inputDecorationTheme
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
