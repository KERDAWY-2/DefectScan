import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;
  String _role = 'user';

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login() async {
    setState(() { _loading = true; _error = null; });
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final selectedRole = _role;
    final success = await auth.login(
      _usernameController.text.trim(),
      _passwordController.text.trim(),
    );
    if (success) {
      // Always route by the account's ACTUAL role, not the selected one.
      final role = auth.user?['role'];
      if (selectedRole != role) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              "Signed in as $role — this account isn't a $selectedRole.",
            ),
          ),
        );
      }
      if (role == 'admin') {
        navigator.pushReplacementNamed('/admin_dashboard');
      } else if (role == 'fixer') {
        navigator.pushReplacementNamed('/fixer_dashboard');
      } else {
        navigator.pushReplacementNamed('/home');
      }
    } else {
      setState(() { _error = "Invalid username or password"; });
    }
    if (mounted) setState(() { _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            // --- Gradient hero ---
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(gradient: kBrandGradient),
              padding: EdgeInsets.fromLTRB(
                24,
                MediaQuery.of(context).padding.top + 56,
                24,
                48,
              ),
              child: const Center(child: AppWordmark(onDark: true)),
            ),
            // --- Form card ---
            Transform.translate(
              offset: const Offset(0, -24),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          "Welcome back",
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Sign in to continue",
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 20),

                        // Role selector
                        Text(
                          "Sign in as",
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'user',
                                label: Text("User"),
                                icon: Icon(Icons.person),
                              ),
                              ButtonSegment(
                                value: 'fixer',
                                label: Text("Fixer"),
                                icon: Icon(Icons.engineering),
                              ),
                              ButtonSegment(
                                value: 'admin',
                                label: Text("Admin"),
                                icon: Icon(Icons.admin_panel_settings),
                              ),
                            ],
                            selected: {_role},
                            showSelectedIcon: false,
                            onSelectionChanged: (s) =>
                                setState(() => _role = s.first),
                          ),
                        ),
                        const SizedBox(height: 20),

                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD64545)
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: const Color(0xFFD64545)
                                      .withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: Color(0xFFD64545), size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                        color: Color(0xFFD64545)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        TextField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: "Username",
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          decoration: const InputDecoration(
                            labelText: "Password",
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          obscureText: true,
                          onSubmitted: (_) => _loading ? null : _login(),
                        ),
                        const SizedBox(height: 24),

                        SizedBox(
                          height: 50,
                          child: _loading
                              ? const Center(
                                  child: CircularProgressIndicator())
                              : ElevatedButton(
                                  onPressed: _login,
                                  child: const Text("Login"),
                                ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () =>
                              Navigator.pushNamed(context, '/register'),
                          child: const Text(
                              "Don't have an account? Register"),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
