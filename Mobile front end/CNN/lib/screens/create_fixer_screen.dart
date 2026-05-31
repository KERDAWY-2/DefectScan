import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_app_bar.dart';

class CreateFixerScreen extends StatefulWidget {
  const CreateFixerScreen({super.key});

  @override
  State<CreateFixerScreen> createState() => _CreateFixerScreenState();
}

class _CreateFixerScreenState extends State<CreateFixerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _secondName = TextEditingController();
  final _nationalId = TextEditingController();
  final _mobile = TextEditingController();
  final _address = TextEditingController();

  List<String> _specialties = [];
  String? _specialty;
  bool _loading = false;
  bool _loadingSpecialties = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSpecialties();
  }

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _secondName.dispose();
    _nationalId.dispose();
    _mobile.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _loadSpecialties() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      final mapping = await ApiService.getSpecialties(auth.token!);
      // Distinct specialty values from the defect->specialty mapping.
      final set = <String>{};
      for (final m in mapping) {
        set.add(m['specialty'] as String);
      }
      if (!mounted) return;
      setState(() {
        _specialties = set.toList()..sort();
        _specialty = _specialties.isNotEmpty ? _specialties.first : null;
        _loadingSpecialties = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loadingSpecialties = false; });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _specialty == null) return;
    setState(() { _loading = true; _error = null; });
    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      await ApiService.createFixer(
        auth.token!,
        username: _username.text.trim(),
        email: _email.text.trim(),
        password: _password.text.trim(),
        specialty: _specialty!,
        secondName: _secondName.text.trim(),
        nationalId: _nationalId.text.trim(),
        mobile: _mobile.text.trim(),
        address: _address.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fixer created")));
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: "Create Fixer"),
      body: _loadingSpecialties
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            gradient: kBrandGradient,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.engineering,
                              color: Colors.white),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("New fixer account",
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge),
                              Text("Assign a specialty so reports route correctly",
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
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
                                      child: Text(_error!,
                                          style: const TextStyle(
                                              color: Color(0xFFD64545))),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            _field(_username, "Username", required: true),
                            _field(_email, "Email", required: true, validator: (v) {
                              if (v == null || v.trim().isEmpty) return "Email is required";
                              if (!v.contains('@')) return "Enter a valid email";
                              return null;
                            }),
                            _field(_password, "Password", required: true, obscure: true, validator: (v) {
                              if (v == null || v.trim().isEmpty) return "Password is required";
                              if (v.length < 6) return "At least 6 characters";
                              return null;
                            }),
                            _field(_secondName, "Second Name"),
                            _field(_nationalId, "National ID"),
                            _field(_mobile, "Mobile"),
                            _field(_address, "Address"),
                            const SizedBox(height: 4),
                            DropdownButtonFormField<String>(
                              initialValue: _specialty,
                              decoration: const InputDecoration(
                                labelText: "Specialty",
                                prefixIcon: Icon(Icons.handyman_outlined),
                              ),
                              items: _specialties
                                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                                  .toList(),
                              onChanged: (v) => setState(() => _specialty = v),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              height: 50,
                              child: _loading
                                  ? const Center(child: CircularProgressIndicator())
                                  : ElevatedButton.icon(
                                      onPressed: _submit,
                                      icon: const Icon(Icons.person_add_alt_1),
                                      label: const Text("Create Fixer"),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {bool required = false, bool obscure = false, String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: c,
        obscureText: obscure,
        decoration: InputDecoration(labelText: label),
        validator: validator ?? (required ? (v) => (v == null || v.trim().isEmpty) ? "$label is required" : null : null),
      ),
    );
  }
}
