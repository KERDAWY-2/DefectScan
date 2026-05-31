import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/status_chip.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  List<dynamic> _reports = [];
  bool _loading = true;
  String? _error;

  final _locationController = TextEditingController();
  String _status = "";       // "" = all
  String _sortBy = "created_at";
  String _order = "desc";

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      final reports = await ApiService.getAllReports(
        auth.token!,
        location: _locationController.text.trim(),
        status: _status,
        sortBy: _sortBy,
        order: _order,
      );
      if (mounted) setState(() => _reports = reports);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _assign(int reportId) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    List<dynamic> fixers;
    try {
      fixers = await ApiService.getSuggestedFixers(reportId, auth.token!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      return;
    }

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: fixers.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text("No fixers match this defect's specialty yet. Create one first."),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text("Suggested fixers", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  ...fixers.map((f) => ListTile(
                        leading: const Icon(Icons.engineering),
                        title: Text(f['username'] ?? ''),
                        subtitle: Text(f['specialty'] ?? ''),
                        trailing: const Icon(Icons.assignment_ind),
                        onTap: () async {
                          Navigator.pop(ctx);
                          try {
                            await ApiService.assignFixer(reportId, f['id'] as int, auth.token!);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Assigned to ${f['username']}")));
                            _fetch();
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                          }
                        },
                      )),
                ],
              ),
      ),
    );
  }

  Future<void> _complete(int reportId) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      await ApiService.completeReport(reportId, auth.token!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Report completed")));
      _fetch();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _delete(int reportId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete report"),
        content: const Text(
            "Delete this report? This removes its images permanently."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      await ApiService.deleteReport(reportId, auth.token!);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Report deleted")));
      _fetch();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Widget _filters() {
    return Container(
      color: kCardSurface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          TextField(
            controller: _locationController,
            decoration: InputDecoration(
              labelText: "Filter by location",
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: _fetch,
              ),
            ),
            onSubmitted: (_) => _fetch(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _status,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: "Status", isDense: true),
                  items: const [
                    DropdownMenuItem(value: "", child: Text("All statuses")),
                    DropdownMenuItem(value: "pending", child: Text("Pending")),
                    DropdownMenuItem(value: "assigned", child: Text("Assigned")),
                    DropdownMenuItem(value: "fixer_done", child: Text("Fixer done")),
                    DropdownMenuItem(value: "completed", child: Text("Completed")),
                  ],
                  onChanged: (v) { setState(() => _status = v ?? ""); _fetch(); },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _sortBy,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: "Sort by", isDense: true),
                  items: const [
                    DropdownMenuItem(value: "created_at", child: Text("Date")),
                    DropdownMenuItem(value: "location", child: Text("Location")),
                    DropdownMenuItem(value: "severity", child: Text("Severity")),
                    DropdownMenuItem(value: "status", child: Text("Status")),
                  ],
                  onChanged: (v) { setState(() => _sortBy = v ?? "created_at"); _fetch(); },
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                icon: Icon(_order == "desc" ? Icons.arrow_downward : Icons.arrow_upward),
                tooltip: _order == "desc" ? "Descending" : "Ascending",
                onPressed: () { setState(() => _order = _order == "desc" ? "asc" : "desc"); _fetch(); },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: kInkMuted),
          const SizedBox(width: 6),
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 13.5, color: kInk))),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.assignment_outlined, size: 64, color: kInkMuted),
        const SizedBox(height: 12),
        Center(
          child: Text("No reports match.",
              style: TextStyle(color: kInkMuted, fontSize: 15)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: "Defect Reports"),
      body: Column(
        children: [
          _filters(),
          Expanded(
            child: _loading
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
                              Text("Error: $_error",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: kInkMuted)),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _fetch,
                                icon: const Icon(Icons.refresh),
                                label: const Text("Retry"),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetch,
                        child: _reports.isEmpty
                            ? _emptyState()
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _reports.length,
                                itemBuilder: (context, index) {
                                  final r = _reports[index] as Map<String, dynamic>;
                                  final status = r['status'] as String;
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (r['result_image_path'] != null)
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(12),
                                              child: Image.network(
                                                uploadsUrl(r['result_image_path']),
                                                height: 180,
                                                width: double.infinity,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, _, _) => Container(
                                                  height: 180,
                                                  color: kSurface,
                                                  child: const Center(
                                                    child: Icon(Icons.broken_image_outlined,
                                                        color: kInkMuted, size: 40),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          const SizedBox(height: 12),
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  r['result'] ?? '',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium,
                                                ),
                                              ),
                                              StatusChip(status: status),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          _infoRow(Icons.location_on_outlined,
                                              "Location: ${r['location'] ?? 'n/a'}"),
                                          _infoRow(Icons.warning_amber_outlined,
                                              "Severity: ${r['severity'] ?? 'n/a'}"),
                                          if ((r['description'] ?? '').toString().isNotEmpty)
                                            _infoRow(Icons.notes_outlined,
                                                "Description: ${r['description']}"),
                                          _infoRow(Icons.person_outline,
                                              "Reporter: #${r['user_id']}"),
                                          const Divider(),
                                          Row(
                                            children: [
                                              if (status == 'pending' || status == 'assigned')
                                                Expanded(
                                                  child: ElevatedButton.icon(
                                                    icon: const Icon(Icons.assignment_ind),
                                                    label: Text(status == 'assigned' ? "Reassign" : "Assign"),
                                                    onPressed: () => _assign(r['id'] as int),
                                                  ),
                                                )
                                              else if (status == 'fixer_done')
                                                Expanded(
                                                  child: ElevatedButton.icon(
                                                    icon: const Icon(Icons.done_all),
                                                    label: const Text("Mark finished"),
                                                    onPressed: () => _complete(r['id'] as int),
                                                  ),
                                                )
                                              else
                                                const Spacer(),
                                              const SizedBox(width: 8),
                                              IconButton(
                                                icon: const Icon(Icons.delete_outline),
                                                color: Colors.red,
                                                tooltip: "Delete report",
                                                onPressed: () => _delete(r['id'] as int),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}
