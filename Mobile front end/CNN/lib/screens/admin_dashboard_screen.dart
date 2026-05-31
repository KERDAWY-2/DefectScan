import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_app_bar.dart';
import 'chat_screen.dart';
import 'admin_reports_screen.dart';
import 'create_fixer_screen.dart';
import 'community_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  List<dynamic> _users = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() { _loading = true; _error = null; });
    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      final users = await ApiService.getUsers(auth.token!);
      setState(() { _users = users; });
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _deleteUser(int userId, String username) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Deletion"),
        content: Text("Are you sure you want to delete user '$username'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red))
          ),
        ],
      )
    );

    if (confirm != true || !mounted) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      await ApiService.deleteUser(userId, auth.token!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("User deleted successfully")));
      _fetchUsers(); // Refresh the list
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final currentAdminId = auth.user?['id'];

    return Scaffold(
      appBar: CustomAppBar(
        title: "Admin Dashboard",
        actions: [
          IconButton(
            icon: const Icon(Icons.assignment),
            tooltip: "Defect reports",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminReportsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.engineering),
            tooltip: "Create fixer",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateFixerScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.groups),
            tooltip: "Community",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CommunityScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final navigator = Navigator.of(context);
              await auth.logout();
              navigator.pushReplacementNamed('/login');
            },
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_off,
                            size: 56, color: kInkMuted),
                        const SizedBox(height: 12),
                        Text("Error loading users",
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text("$_error",
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _fetchUsers,
                          icon: const Icon(Icons.refresh),
                          label: const Text("Retry"),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchUsers,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _users.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12, left: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.groups,
                                  size: 20, color: kBrandBlue),
                              const SizedBox(width: 8),
                              Text(
                                "${_users.length} ${_users.length == 1 ? 'user' : 'users'}",
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium,
                              ),
                            ],
                          ),
                        );
                      }
                      final user = _users[index - 1];
                      final isMe = user['id'] == currentAdminId;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                user['username'] ?? '',
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                            ),
                                            if (isMe) ...[
                                              const SizedBox(width: 8),
                                              Text("(you)",
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        _roleBadge(user['role'] ?? 'user'),
                                      ],
                                    ),
                                  ),
                                  if (!isMe) ...[
                                    IconButton(
                                      icon: const Icon(Icons.chat_bubble_outline,
                                          color: kBrandBlue),
                                      tooltip: "Chat with user",
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => ChatScreen(chatUserId: user['id']))
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                                      tooltip: "Delete user",
                                      onPressed: () => _deleteUser(user['id'], user['username']),
                                    )
                                  ]
                                ],
                              ),
                              const Divider(),
                              _buildInfoRow(Icons.email_outlined, user['email']),
                              _buildInfoRow(Icons.credit_card, "National ID: ${user['national_id'] ?? 'N/A'}"),
                              _buildInfoRow(Icons.phone_outlined, "Mobile: ${user['mobile'] ?? 'N/A'}"),
                              _buildInfoRow(Icons.location_on_outlined, "Address: ${user['address'] ?? 'N/A'}"),
                              _buildInfoRow(Icons.badge_outlined, "Second Name: ${user['second_name'] ?? 'N/A'}"),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _roleBadge(String role) {
    late final Color color;
    late final IconData icon;
    switch (role) {
      case 'admin':
        color = kBrandBlue;
        icon = Icons.admin_panel_settings;
        break;
      case 'fixer':
        color = kBrandAmberDark;
        icon = Icons.engineering;
        break;
      default:
        color = kStatusCompleted;
        icon = Icons.person;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            role,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: kInkMuted),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 14, color: kInk))),
        ],
      ),
    );
  }
}
