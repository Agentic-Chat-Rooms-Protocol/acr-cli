import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class AcrClient {
  AcrClient({String? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? 'http://localhost:20443',
      _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<Map<String, dynamic>> fetchHealth() async {
    final res = await _client.get(Uri.parse('$baseUrl/api/v1/health'));
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> fetchRooms() async {
    final res = await _client.get(Uri.parse('$baseUrl/api/v1/rooms'));
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    final List<dynamic> list = jsonDecode(res.body) as List<dynamic>;
    return list.map((e) => e as Map<String, dynamic>).toList();
  }

  Future<Map<String, dynamic>> createRoom({
    required String name,
    required String description,
    required String topic,
    required bool isPrivate,
    String creatorDid = 'did:key:z6Mka881...operator',
  }) async {
    final res = await _client.post(
      Uri.parse(
        '$baseUrl/api/v1/rooms?creator_did=${Uri.encodeComponent(creatorDid)}',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'description': description,
        'topic': topic,
        'is_private': isPrivate,
      }),
    );
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> fetchMessages(
    String roomId, {
    int limit = 50,
  }) async {
    final res = await _client.get(
      Uri.parse('$baseUrl/api/v1/rooms/$roomId/messages?limit=$limit'),
    );
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    final List<dynamic> list = jsonDecode(res.body) as List<dynamic>;
    return list.map((e) => e as Map<String, dynamic>).toList();
  }

  Future<Map<String, dynamic>> sendMessage({
    required String roomId,
    required String content,
    String senderDid = 'did:key:z6Mka881...operator',
    Map<String, dynamic>? attachment,
  }) async {
    final body = {
      'sender_did': senderDid,
      'content': content,
      // ignore: use_null_aware_elements
      if (attachment != null) 'attachment': attachment,
    };
    final res = await _client.post(
      Uri.parse('$baseUrl/api/v1/rooms/$roomId/messages'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> fetchAgents() async {
    final res = await _client.get(Uri.parse('$baseUrl/api/v1/agents'));
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    final List<dynamic> list = jsonDecode(res.body) as List<dynamic>;
    return list.map((e) => e as Map<String, dynamic>).toList();
  }

  Future<List<Map<String, dynamic>>> fetchBuddies(String did) async {
    final res = await _client.get(
      Uri.parse('$baseUrl/api/v1/buddies?did=${Uri.encodeComponent(did)}'),
    );
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    final decoded = jsonDecode(res.body);
    if (decoded == null) return <Map<String, dynamic>>[];
    final List<dynamic> list = decoded as List<dynamic>;
    return list.map((e) => e as Map<String, dynamic>).toList();
  }

  Future<Map<String, dynamic>> updateBuddy({
    required String action, // request, accept, block
    required String fromDid,
    required String toDid,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/api/v1/buddies/$action'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'from_did': fromDid, 'to_did': toDid}),
    );
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> fetchProposals(String roomId) async {
    final res = await _client.get(
      Uri.parse('$baseUrl/api/v1/proposals?room_id=$roomId'),
    );
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    final List<dynamic> list = jsonDecode(res.body) as List<dynamic>;
    return list.map((e) => e as Map<String, dynamic>).toList();
  }

  Future<Map<String, dynamic>> createProposal({
    required String roomId,
    required String title,
    required String description,
    required String proposerDid,
    List<String>? options,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/api/v1/proposals'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'room_id': roomId,
        'title': title,
        'description': description,
        'proposer_did': proposerDid,
        'options': options ?? ['APPROVE', 'REJECT', 'DISSENT'],
      }),
    );
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> castVote({
    required String proposalId,
    required String voterDid,
    required String choice,
    String? rationale,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/api/v1/proposals/$proposalId/vote'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'voter_did': voterDid,
        'choice': choice,
        // ignore: use_null_aware_elements
        if (rationale != null) 'rationale': rationale,
      }),
    );
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> closeProposal({
    required String proposalId,
    required String closerDid,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/api/v1/proposals/$proposalId/close'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'closer_did': closerDid}),
    );
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> uploadFile(
    String filePath, {
    String? mimeType,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('File not found', filePath);
    }
    final bytes = await file.readAsBytes();
    final filename = file.uri.pathSegments.last;
    final mime = mimeType ?? 'application/octet-stream';

    final uri = Uri.parse(
      '$baseUrl/api/v1/files/upload?filename=${Uri.encodeComponent(filename)}&mime_type=${Uri.encodeComponent(mime)}',
    );
    final res = await _client.post(
      uri,
      headers: {'Content-Type': mime},
      body: bytes,
    );
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<int>> downloadFile(String fileId) async {
    final res = await _client.get(Uri.parse('$baseUrl/api/v1/files/$fileId'));
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    return res.bodyBytes;
  }

  Future<List<Map<String, dynamic>>> fetchAudit({int limit = 50}) async {
    final res = await _client.get(
      Uri.parse('$baseUrl/api/v1/audit?limit=$limit'),
    );
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    final decoded = jsonDecode(res.body);
    if (decoded == null) return <Map<String, dynamic>>[];
    final List<dynamic> list = decoded as List<dynamic>;
    return list.map((e) => e as Map<String, dynamic>).toList();
  }

  Future<List<Map<String, dynamic>>> fetchEscalations() async {
    final res = await _client.get(Uri.parse('$baseUrl/api/v1/escalations'));
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    final decoded = jsonDecode(res.body);
    if (decoded == null) return <Map<String, dynamic>>[];
    final List<dynamic> list = decoded as List<dynamic>;
    return list.map((e) => e as Map<String, dynamic>).toList();
  }

  Future<Map<String, dynamic>> resolveEscalation({
    required String id,
    required bool approve,
    required String operatorDid,
    required String signature,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/api/v1/escalations/$id/resolve'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'approve': approve,
        'operator_did': operatorDid,
        'signature': signature,
      }),
    );
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
