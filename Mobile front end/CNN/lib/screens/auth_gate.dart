import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'admin_dashboard_screen.dart';
import 'fixer_dashboard_screen.dart';

/// Decides which screen to show based on saved token. This is the entry
/// point of the app instead of a fixed `initialRoute: '/login'` because
/// Android can kill MainActivity while ImagePicker is open; on relaunch
/// we need to honor the persisted token instead of forcing the user back
/// to the login screen.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (!auth.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!auth.isLoggedIn) {
      return const LoginScreen();
    }

    final role = auth.user?['role'];
    if (role == 'admin') {
      return const AdminDashboardScreen();
    }
    if (role == 'fixer') {
      return const FixerDashboardScreen();
    }
    return const HomeScreen();
  }
}
