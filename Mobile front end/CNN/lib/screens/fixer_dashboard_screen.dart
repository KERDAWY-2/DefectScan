import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/status_chip.dart';

class FixerDashboardScreen extends StatefulWidget {
  const FixerDashboardScreen({super.key});

  @override
  State<FixerDashboardScreen> createState() => _FixerDashboardScreenState();
}

class _FixerDashboardScreenState extends State<FixerDashboardScreen> {
  List<dynamic> _reports = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      final reports = await ApiService.getAssignedReports(auth.token!);
      if (mounted) setState(() => _reports = reports);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markDone(int reportId) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      await ApiService.markFixerDone(reportId, auth.token!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Marked as done")));
      _fetch();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    return Scaffold(
      appBar: CustomAppBar(
        title: "My Tasks",
        actions: [
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
              ? _errorState()
              : _reports.isEmpty
                  ? _emptyState()
                  : RefreshIndicator(
                      onRefresh: _fetch,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        itemCount: _reports.length,
                        itemBuilder: (context, index) {
                          final r = _reports[index] as Map<String, dynamic>;
                          return _taskCard(r);
                        },
                      ),
                    ),
    );
  }

  Widget _taskCard(Map<String, dynamic> r) {
    final status = r['status'] as String;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r['result_image_path'] != null)
            Image.network(
              uploadsUrl(r['result_image_path']),
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  height: 180,
                  color: kSurface,
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(),
                );
              },
              errorBuilder: (context, error, stack) => Container(
                height: 180,
                color: kSurface,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined, size: 40, color: kInkMuted),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        r['result'] ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          color: kInk,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusChip(status: status),
                  ],
                ),
                const SizedBox(height: 12),
                _infoRow(Icons.location_on_outlined, r['location'] ?? 'No location'),
                const SizedBox(height: 6),
                _infoRow(Icons.priority_high, "Severity: ${r['severity'] ?? 'n/a'}"),
                if ((r['description'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _infoRow(Icons.notes_outlined, r['description']),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: _actionFor(status, r),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionFor(String status, Map<String, dynamic> r) {
    switch (status) {
      case 'assigned':
        return ElevatedButton.icon(
          icon: const Icon(Icons.check_circle_outline),
          label: const Text("Mark done"),
          onPressed: () => _markDone(r['id'] as int),
        );
      case 'fixer_done':
        return _statusPill(
          Icons.hourglass_top,
          "Awaiting admin",
          kStatusFixerDone,
        );
      case 'completed':
        return _statusPill(
          Icons.task_alt,
          "Completed",
          kStatusCompleted,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _statusPill(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: kInkMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: const TextStyle(color: kInk, fontSize: 14)),
        ),
      ],
    );
  }

  Widget _emptyState() {
    return LayoutBuilder(
      builder: (context, constraints) => RefreshIndicator(
        onRefresh: _fetch,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: kBrandBlue.withValues(alpha: 0.07),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.assignment_turned_in_outlined,
                          size: 54, color: kBrandBlue),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "No tasks assigned to you yet.",
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: kInk,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "New assignments will appear here. Pull down to refresh.",
                      style: TextStyle(color: kInkMuted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 54, color: kInkMuted),
            const SizedBox(height: 16),
            const Text(
              "Couldn't load your tasks",
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kInk),
            ),
            const SizedBox(height: 6),
            Text(
              "$_error",
              style: const TextStyle(color: kInkMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _fetch,
              icon: const Icon(Icons.refresh),
              label: const Text("Retry"),
            ),
          ],
        ),
      ),
    );
  }
}
