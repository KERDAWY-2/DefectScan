import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_app_bar.dart';
import 'chat_screen.dart';
import 'community_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _maxUploadBytes = 10 * 1024 * 1024; // 10 MB — matches the backend limit

  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;        // cross-platform (mobile + web)
  Uint8List? _selectedBytes;    // cached for preview (Image.memory works on web)
  Map<String, dynamic>? _result;
  bool _loading = false;

  Future<void> _pickImage(ImageSource source) async {
    // maxWidth + imageQuality bound the upload size and re-encode to JPEG,
    // which keeps us well under the backend's 10 MB / image-type limits.
    final XFile? image = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (image == null) return;

    // Client-side size guard — instant feedback, mirrors the backend's 413.
    final sizeBytes = await image.length();
    if (sizeBytes > _maxUploadBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Image is too large (max 10 MB).")),
        );
      }
      return;
    }

    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(() {
      _selectedImage = image;
      _selectedBytes = bytes;
      _result = null;
    });
    await _predict();
  }

  Future<void> _predict() async {
    if (_selectedImage == null) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    setState(() => _loading = true);
    try {
      final result = await ApiService.predict(_selectedImage!, auth.token!);
      setState(() => _result = result);
      // Only prompt for metadata when a report was actually created.
      final reportId = result['report_id'];
      if (reportId != null && mounted) {
        await _showMetadataForm(reportId as int);
      }
    } catch (e) {
      setState(() => _result = {"result": "Error: $e", "image_b64": null});
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showMetadataForm(int reportId) async {
    final locationController = TextEditingController();
    final descriptionController = TextEditingController();
    String severity = "medium";

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.assignment_outlined, color: kBrandAmberDark),
              SizedBox(width: 10),
              Text("Report details"),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: locationController,
                  decoration: const InputDecoration(
                    labelText: "Location",
                    hintText: "e.g. Building A, 3rd floor",
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: severity,
                  decoration: const InputDecoration(
                    labelText: "Severity",
                    prefixIcon: Icon(Icons.priority_high),
                  ),
                  items: const [
                    DropdownMenuItem(value: "low", child: Text("Low")),
                    DropdownMenuItem(value: "medium", child: Text("Medium")),
                    DropdownMenuItem(value: "high", child: Text("High")),
                  ],
                  onChanged: (v) => setLocal(() => severity = v ?? "medium"),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: "Description (optional)",
                    hintText: "Add any extra detail for the team...",
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Skip")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Save")),
          ],
        ),
      ),
    );

    if (saved == true) {
      if (!mounted) return;
      final auth = Provider.of<AuthProvider>(context, listen: false);
      try {
        await ApiService.updateReportMetadata(
          reportId,
          auth.token!,
          location: locationController.text.trim(),
          severity: severity,
          description: descriptionController.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Report details saved")));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Could not save details: $e")));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.user;

    return Scaffold(
      appBar: CustomAppBar(
        title: "CNN Defect Detection",
        actions: [
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
      body: SingleChildScrollView(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _welcomeHeader(user),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Section label
                  Row(
                    children: const [
                      Icon(Icons.image_search, size: 20, color: kBrandBlue),
                      SizedBox(width: 8),
                      Text(
                        "Inspect an image",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: kInk,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Capture or pick a photo to scan for defects.",
                    style: TextStyle(color: kInkMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 16),

                  // Buttons — Camera (primary) + Gallery (amber accent).
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text("Camera"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library),
                          label: const Text("Gallery"),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Image preview — annotated image once available, else original.
                  // Wrapped in InteractiveViewer for pinch-to-zoom + drag-to-pan.
                  if (_result != null && _result!['image_b64'] != null)
                    _previewFrame(
                      height: 320,
                      child: InteractiveViewer(
                        minScale: 1.0,
                        maxScale: 6.0,
                        clipBehavior: Clip.hardEdge,
                        child: Image.memory(
                          base64Decode(_result!['image_b64']),
                          fit: BoxFit.contain,
                        ),
                      ),
                    )
                  else if (_selectedBytes != null)
                    _previewFrame(
                      height: 250,
                      child: InteractiveViewer(
                        minScale: 1.0,
                        maxScale: 6.0,
                        clipBehavior: Clip.hardEdge,
                        child: Image.memory(_selectedBytes!, fit: BoxFit.cover),
                      ),
                    )
                  else
                    _previewPlaceholder(),

                  const SizedBox(height: 18),

                  // Loading / Result
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text("Analyzing image...",
                                style: TextStyle(color: kInkMuted)),
                          ],
                        ),
                      ),
                    ),
                  if (_result != null) _resultCard(),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (user != null) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ChatScreen(chatUserId: user['id']))
            );
          }
        },
        icon: const Icon(Icons.chat),
        label: const Text("Support"),
      ),
    );
  }

  /// Gradient hero header: avatar, welcome line, email and a role chip.
  Widget _welcomeHeader(Map<String, dynamic>? user) {
    final role = (user?['role'] ?? '').toString();
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: kBrandGradient),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 26),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Welcome, ${user?['username'] ?? ''}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  "${user?['email'] ?? ''}",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (role.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: kBrandAmber,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.verified_user, size: 13, color: Color(0xFF3A2A05)),
                        const SizedBox(width: 4),
                        Text(
                          role.toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFF3A2A05),
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Rounded, bordered frame for an image preview.
  Widget _previewFrame({required double height, required Widget child}) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBrandBlue.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: kBrandBlue.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  /// Dashed-feel placeholder shown before any image is picked.
  Widget _previewPlaceholder() {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: kCardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBrandBlue.withValues(alpha: 0.12)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_a_photo_outlined, size: 44, color: kInkMuted.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          const Text(
            "No image selected yet",
            style: TextStyle(color: kInkMuted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            "Use Camera or Gallery to begin",
            style: TextStyle(color: kInkMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// Result card — amber-tinted when a defect is detected, neutral otherwise.
  Widget _resultCard() {
    final resultText = (_result!['result'] ?? '').toString();
    final isError = resultText.startsWith("Error:");
    final detections = _result!['num_detections'];
    final hasDefect = !isError &&
        (detections is int ? detections > 0 : resultText.trim().isNotEmpty &&
            !resultText.toLowerCase().contains("no defect"));

    final Color accent = isError
        ? const Color(0xFFD64545)
        : hasDefect
            ? kBrandAmberDark
            : kStatusCompleted;
    final IconData icon = isError
        ? Icons.error_outline
        : hasDefect
            ? Icons.warning_amber_rounded
            : Icons.verified_outlined;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isError ? "Something went wrong" : "Result",
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  resultText,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: kInk,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
