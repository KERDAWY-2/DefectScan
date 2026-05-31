import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart' show XFile;

const String baseUrl = "http://54.162.33.191";

// Derived once from baseUrl so screens never hardcode a host again.
// "http://..." -> "ws://...", "https://..." -> "wss://...".
final String wsBaseUrl = baseUrl.replaceFirst('http', 'ws');

// Build a full URL for an image stored under the server's uploads/ dir.
String uploadsUrl(String path) => "$baseUrl/uploads/$path";

class ApiService {
  static Map<String, String> _authHeaders(String token, {bool json = false}) => {
        "Authorization": "Bearer $token",
        if (json) "Content-Type": "application/json",
      };

  // Register
  static Future<Map<String, dynamic>> register(
      String username, String email, String password, String secondName, String nationalId, String mobile, String address) async {
    final response = await http.post(
      Uri.parse("$baseUrl/auth/register"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "username": username,
        "email": email,
        "password": password,
        "second_name": secondName,
        "national_id": nationalId,
        "mobile": mobile,
        "address": address
      }),
    );
    return jsonDecode(response.body);
  }

  // Login
  static Future<Map<String, dynamic>> login(
      String username, String password) async {
    final response = await http.post(
      Uri.parse("$baseUrl/auth/login"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"username": username, "password": password}),
    );
    return jsonDecode(response.body);
  }

  // Get current user
  static Future<Map<String, dynamic>> getMe(String token) async {
    final response = await http.get(
      Uri.parse("$baseUrl/auth/me"),
      headers: _authHeaders(token),
    );
    return jsonDecode(response.body);
  }

  // Predict defect from image. On success returns:
  //   { "result": String, "image_b64": String?, "num_detections": int,
  //     "report_id": int, "image_url": String, "result_image_url": String? }
  // On failure (413/415/429/...) returns { "result": "Error: ...", "image_b64": null }
  // with no "report_id", so the caller skips the metadata form.
  static Future<Map<String, dynamic>> predict(XFile imageFile, String token) async {
    // fromBytes works on every platform (web has no real filesystem path).
    // The backend re-derives the image format from the bytes via PIL,
    // so we don't need to set a content-type header here.
    final bytes = await imageFile.readAsBytes();
    final request = http.MultipartRequest('POST', Uri.parse("$baseUrl/predict/"));
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: imageFile.name));

    final response = await request.send();
    final body = await response.stream.bytesToString();
    final decoded = jsonDecode(body);

    if (response.statusCode == 200 && decoded is Map<String, dynamic>) {
      return decoded;
    }
    final detail = (decoded is Map && decoded['detail'] != null) ? decoded['detail'].toString() : body;
    return {"result": "Error: $detail", "image_b64": null, "num_detections": 0};
  }

  // --- REPORTS (F5 / F6) ---

  static Future<List<dynamic>> getMyReports(String token) async {
    final response = await http.get(Uri.parse("$baseUrl/reports/me"), headers: _authHeaders(token));
    if (response.statusCode == 200) return jsonDecode(response.body) as List<dynamic>;
    throw Exception("Failed to load reports: ${response.statusCode}");
  }

  static Future<void> updateReportMetadata(
      int reportId, String token, {String? location, String? severity, String? description}) async {
    final response = await http.patch(
      Uri.parse("$baseUrl/reports/$reportId"),
      headers: _authHeaders(token, json: true),
      body: jsonEncode({
        "location": ?location,
        "severity": ?severity,
        "description": ?description,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception("Failed to save metadata: ${response.statusCode}");
    }
  }

  // Admin: list all reports with optional filter/sort.
  static Future<List<dynamic>> getAllReports(String token,
      {String? location, String? status, String sortBy = "created_at", String order = "desc"}) async {
    final params = <String, String>{"sort_by": sortBy, "order": order};
    if (location != null && location.isNotEmpty) params["location"] = location;
    if (status != null && status.isNotEmpty) params["status"] = status;
    final uri = Uri.parse("$baseUrl/reports/").replace(queryParameters: params);
    final response = await http.get(uri, headers: _authHeaders(token));
    if (response.statusCode == 200) return jsonDecode(response.body) as List<dynamic>;
    throw Exception("Failed to load reports: ${response.statusCode}");
  }

  static Future<List<dynamic>> getSuggestedFixers(int reportId, String token) async {
    final response = await http.get(
      Uri.parse("$baseUrl/reports/$reportId/suggested-fixers"),
      headers: _authHeaders(token),
    );
    if (response.statusCode == 200) return jsonDecode(response.body) as List<dynamic>;
    throw Exception("Failed to load suggested fixers: ${response.statusCode}");
  }

  static Future<void> assignFixer(int reportId, int fixerId, String token) async {
    final response = await http.post(
      Uri.parse("$baseUrl/reports/$reportId/assign"),
      headers: _authHeaders(token, json: true),
      body: jsonEncode({"fixer_id": fixerId}),
    );
    if (response.statusCode != 200) throw Exception("Failed to assign fixer: ${response.statusCode}");
  }

  static Future<void> completeReport(int reportId, String token) async {
    final response = await http.post(
      Uri.parse("$baseUrl/reports/$reportId/complete"),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) throw Exception("Failed to complete report: ${response.statusCode}");
  }

  static Future<void> deleteReport(int reportId, String token) async {
    final response = await http.delete(
      Uri.parse("$baseUrl/reports/$reportId"),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception("Failed to delete report: ${response.statusCode}");
    }
  }

  // Fixer
  static Future<List<dynamic>> getAssignedReports(String token) async {
    final response = await http.get(Uri.parse("$baseUrl/reports/assigned"), headers: _authHeaders(token));
    if (response.statusCode == 200) return jsonDecode(response.body) as List<dynamic>;
    throw Exception("Failed to load assigned reports: ${response.statusCode}");
  }

  static Future<void> markFixerDone(int reportId, String token) async {
    final response = await http.post(
      Uri.parse("$baseUrl/reports/$reportId/fixer-done"),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) throw Exception("Failed to mark done: ${response.statusCode}");
  }

  // --- ADMIN: users + fixers + specialties ---

  static Future<List<dynamic>> getUsers(String token) async {
    final response = await http.get(Uri.parse("$baseUrl/admin/users"), headers: _authHeaders(token));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    } else {
      throw Exception("Failed to load users: ${response.statusCode}");
    }
  }

  static Future<void> deleteUser(int userId, String token) async {
    final response = await http.delete(
      Uri.parse("$baseUrl/admin/users/$userId"),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception("Failed to delete user: ${response.statusCode}");
    }
  }

  static Future<List<dynamic>> getSpecialties(String token) async {
    final response = await http.get(Uri.parse("$baseUrl/admin/specialties"), headers: _authHeaders(token));
    if (response.statusCode == 200) return jsonDecode(response.body) as List<dynamic>;
    throw Exception("Failed to load specialties: ${response.statusCode}");
  }

  static Future<Map<String, dynamic>> createFixer(String token,
      {required String username,
      required String email,
      required String password,
      required String specialty,
      String? secondName,
      String? nationalId,
      String? mobile,
      String? address}) async {
    final response = await http.post(
      Uri.parse("$baseUrl/admin/fixers"),
      headers: _authHeaders(token, json: true),
      body: jsonEncode({
        "username": username,
        "email": email,
        "password": password,
        "specialty": specialty,
        "second_name": secondName,
        "national_id": nationalId,
        "mobile": mobile,
        "address": address,
      }),
    );
    final decoded = jsonDecode(response.body);
    if (response.statusCode == 200) return decoded as Map<String, dynamic>;
    final detail = (decoded is Map && decoded['detail'] != null) ? decoded['detail'].toString() : response.body;
    throw Exception(detail);
  }

  // --- CHAT ---

  static Future<List<dynamic>> getChatHistory(int userId, String token) async {
    final response = await http.get(
      Uri.parse("$baseUrl/chat/history/$userId"),
      headers: _authHeaders(token),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    } else {
      throw Exception("Failed to load chat history: ${response.statusCode}");
    }
  }

  // AI assistant mode (F4): returns the assistant's reply text.
  static Future<String> askAi(int roomUserId, String message, String token) async {
    final response = await http.post(
      Uri.parse("$baseUrl/chat/ai"),
      headers: _authHeaders(token, json: true),
      body: jsonEncode({"room_user_id": roomUserId, "message": message}),
    );
    final decoded = jsonDecode(response.body);
    if (response.statusCode == 200) return decoded["reply"] as String;
    final detail = (decoded is Map && decoded['detail'] != null) ? decoded['detail'].toString() : response.body;
    throw Exception(detail);
  }

  // --- COMMUNITY (F3) ---

  static Future<List<dynamic>> getCommunityPosts(String token) async {
    final response = await http.get(Uri.parse("$baseUrl/community/posts"), headers: _authHeaders(token));
    if (response.statusCode == 200) return jsonDecode(response.body) as List<dynamic>;
    throw Exception("Failed to load community posts: ${response.statusCode}");
  }

  // Returns the relative image path to attach to a post.
  static Future<String> uploadCommunityImage(XFile imageFile, String token) async {
    final bytes = await imageFile.readAsBytes();
    final request = http.MultipartRequest('POST', Uri.parse("$baseUrl/community/upload-image"));
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: imageFile.name));
    final response = await request.send();
    final body = await response.stream.bytesToString();
    final decoded = jsonDecode(body);
    if (response.statusCode == 200) return decoded["image_path"] as String;
    throw Exception("Failed to upload image: ${response.statusCode}");
  }
}
