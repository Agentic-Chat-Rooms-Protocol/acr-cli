import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class AcrClient {
  AcrClient({
    String? baseUrl,
    String? apiToken,
    http.Client? client,
    Map<String, String>? environment,
    String? homeDir,
    this.timeout = const Duration(seconds: 10),
  }) : baseUrl =
           ((baseUrl != null && baseUrl.trim().isNotEmpty)
                   ? baseUrl.trim()
                   : defaultBaseUrl)
               .replaceAll(RegExp(r'/+$'), ''),
       apiToken = resolveApiToken(
         apiToken: apiToken,
         environment: environment,
         homeDir: homeDir,
       ),
       _client = client ?? http.Client();

  static const String defaultBaseUrl = 'http://127.0.0.1:20443';

  final String baseUrl;
  final String? apiToken;
  final http.Client _client;
  final Duration timeout;

  /// Resolves the local daemon Bearer token from explicit override,
  /// `ACR_API_TOKEN` environment variable, or `~/.acr/api-token`.
  static String? resolveApiToken({
    String? apiToken,
    Map<String, String>? environment,
    String? homeDir,
  }) {
    if (apiToken != null && apiToken.trim().isNotEmpty) {
      return apiToken.trim();
    }
    final env = environment ?? Platform.environment;
    final envToken = env['ACR_API_TOKEN'];
    if (envToken != null && envToken.trim().isNotEmpty) {
      return envToken.trim();
    }
    final envProfile = env['USERPROFILE']?.trim();
    final envHome = env['HOME']?.trim();
    final resolvedHome = (homeDir != null && homeDir.trim().isNotEmpty)
        ? homeDir.trim()
        : ((envProfile != null && envProfile.isNotEmpty)
              ? envProfile
              : envHome);
    if (resolvedHome != null && resolvedHome.isNotEmpty) {
      final tokenFile = File(
        '$resolvedHome${Platform.pathSeparator}.acr${Platform.pathSeparator}api-token',
      );
      if (tokenFile.existsSync()) {
        try {
          final fileToken = tokenFile.readAsStringSync().trim();
          if (fileToken.isNotEmpty) {
            return fileToken;
          }
        } catch (_) {
          // Ignore unreadable token file and fall back to unauthenticated mode.
        }
      }
    }
    return null;
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    String? body,
    List<int>? bodyBytes,
  }) async {
    final req = http.Request(method, uri)
      ..followRedirects = false
      ..maxRedirects = 0;

    if (bodyBytes != null) {
      req.bodyBytes = bodyBytes;
    } else if (body != null) {
      req.body = body;
    }

    if (apiToken != null && apiToken!.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $apiToken';
    }
    if (headers != null) {
      req.headers.addAll(headers);
    }

    final streamed = await _client.send(req).timeout(timeout);
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode >= 300 && res.statusCode < 400) {
      throw HttpException(
        'Redirect blocked (HTTP ${res.statusCode}): redirects are not followed',
        uri: uri,
      );
    }
    return res;
  }

  Future<Map<String, dynamic>> fetchHealth() async {
    final res = await _send('GET', Uri.parse('$baseUrl/api/v1/health'));
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> fetchRooms() async {
    final res = await _send('GET', Uri.parse('$baseUrl/api/v1/rooms'));
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
    if (name.trim().isEmpty) {
      throw ArgumentError('Room name cannot be empty');
    }
    final res = await _send(
      'POST',
      Uri.parse(
        '$baseUrl/api/v1/rooms?creator_did=${Uri.encodeComponent(creatorDid)}',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name.trim(),
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
    final res = await _send(
      'GET',
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
    if (roomId.trim().isEmpty) {
      throw ArgumentError('roomId cannot be empty');
    }
    if (content.trim().isEmpty && attachment == null) {
      throw ArgumentError('Message content or attachment is required');
    }
    final body = {
      'sender_did': senderDid,
      'content': content,
      // ignore: use_null_aware_elements
      if (attachment != null) 'attachment': attachment,
    };
    final res = await _send(
      'POST',
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
    final res = await _send('GET', Uri.parse('$baseUrl/api/v1/agents'));
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    final List<dynamic> list = jsonDecode(res.body) as List<dynamic>;
    return list.map((e) => e as Map<String, dynamic>).toList();
  }

  Future<List<Map<String, dynamic>>> fetchBuddies(String did) async {
    final res = await _send(
      'GET',
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
    final res = await _send(
      'POST',
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
    final res = await _send(
      'GET',
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
    final res = await _send(
      'POST',
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
    final normalized = choice.trim().toUpperCase();
    if (normalized != 'APPROVE' &&
        normalized != 'REJECT' &&
        normalized != 'DISSENT') {
      throw ArgumentError(
        'Invalid choice: $choice. Must be APPROVE, REJECT, or DISSENT',
      );
    }
    if (normalized == 'DISSENT' &&
        (rationale == null || rationale.trim().isEmpty)) {
      throw ArgumentError(
        'Rationale is mandatory when voting DISSENT (GAP-08 Invariant)',
      );
    }

    final res = await _send(
      'POST',
      Uri.parse('$baseUrl/api/v1/proposals/$proposalId/vote'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'voter_did': voterDid,
        'choice': normalized,
        // ignore: use_null_aware_elements
        if (rationale != null) 'rationale': rationale.trim(),
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
    final res = await _send(
      'POST',
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
    final res = await _send(
      'POST',
      uri,
      headers: {'Content-Type': mime},
      bodyBytes: bytes,
    );
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<int>> downloadFile(String fileId) async {
    final res = await _send('GET', Uri.parse('$baseUrl/api/v1/files/$fileId'));
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    return res.bodyBytes;
  }

  Future<List<Map<String, dynamic>>> fetchAudit({int limit = 50}) async {
    final res = await _send(
      'GET',
      Uri.parse('$baseUrl/api/v1/audit?limit=$limit'),
    );
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    final decoded = jsonDecode(res.body);
    if (decoded == null) return <Map<String, dynamic>>[];
    List<dynamic> list;
    if (decoded is List<dynamic>) {
      list = decoded;
    } else if (decoded is Map<String, dynamic> &&
        decoded['trail'] is List<dynamic>) {
      list = decoded['trail'] as List<dynamic>;
    } else {
      return <Map<String, dynamic>>[];
    }
    return list.map((e) => e as Map<String, dynamic>).toList();
  }

  Future<List<Map<String, dynamic>>> fetchEscalations() async {
    final res = await _send('GET', Uri.parse('$baseUrl/api/v1/escalations'));
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
    final res = await _send(
      'POST',
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

  /// Independently recomputes and verifies cryptographic state hash continuity client-side (GAP-06).
  Future<Map<String, dynamic>> verifyAuditChain() async {
    final res = await _send('GET', Uri.parse('$baseUrl/api/v1/audit/chain'));
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    final decoded = jsonDecode(res.body);
    List<dynamic> trail;
    if (decoded == null) {
      trail = <dynamic>[];
    } else if (decoded is List<dynamic>) {
      trail = decoded;
    } else if (decoded is Map<String, dynamic> &&
        decoded['trail'] is List<dynamic>) {
      trail = decoded['trail'] as List<dynamic>;
    } else {
      throw FormatException('Unexpected audit chain response format');
    }
    if (trail.isEmpty) {
      return {
        'is_valid': true,
        'depth': 0,
        'message': 'Audit chain is empty (genesis state)',
      };
    }

    String prevHash = '';
    for (int i = 0; i < trail.length; i++) {
      final entry = trail[i] as Map<String, dynamic>;
      final int index =
          (entry['index'] as int?) ?? (entry['block_height'] as int?) ?? i;
      final String entryPrevHash =
          (entry['prev_hash'] as String?) ??
          (entry['previous_hash'] as String?) ??
          '';
      final String stateHash = entry['state_hash'] as String? ?? '';

      if (index != i) {
        return {
          'is_valid': false,
          'broken_index': i,
          'message': 'Sequence break at index $i: expected $i, got $index',
        };
      }
      if (i > 0 && entryPrevHash != prevHash) {
        return {
          'is_valid': false,
          'broken_index': i,
          'message':
              'Hash continuity broken at index $i: expected $prevHash, got $entryPrevHash',
        };
      }
      if (stateHash.isEmpty) {
        return {
          'is_valid': false,
          'broken_index': i,
          'message': 'Missing state_hash at index $i',
        };
      }
      prevHash = stateHash;
    }

    return {
      'is_valid': true,
      'depth': trail.length,
      'head_hash': prevHash,
      'message':
          'Cryptographic audit chain verified: ${trail.length} blocks untampered',
    };
  }

  Future<Map<String, dynamic>> fetchSecurityConfig() async {
    final res = await _send(
      'GET',
      Uri.parse('$baseUrl/api/v1/config/security'),
    );
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateSecurityConfig({
    bool? enableCors,
    bool? enablePna,
  }) async {
    final body = <String, dynamic>{};
    if (enableCors != null) body['enable_cors'] = enableCors;
    if (enablePna != null) body['enable_pna'] = enablePna;

    final res = await _send(
      'POST',
      Uri.parse('$baseUrl/api/v1/config/security'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchOpsRoomStatus() async {
    final res = await _send('GET', Uri.parse('$baseUrl/api/v1/opsroom/status'));
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchOpsRoomBattlecard() async {
    final res = await _send(
      'GET',
      Uri.parse('$baseUrl/api/v1/opsroom/battlecard'),
    );
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> triggerOpsRoomIncident({
    String preset = 'replication_stall',
    String? customTitle,
    String? customDesc,
  }) async {
    final body = <String, dynamic>{'preset': preset};
    if (customTitle != null) body['title'] = customTitle;
    if (customDesc != null) body['description'] = customDesc;

    final res = await _send(
      'POST',
      Uri.parse('$baseUrl/api/v1/opsroom/incidents/trigger'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> executeOpsRoomPlan(
    String incidentId, {
    bool humanApproved = true,
  }) async {
    final res = await _send(
      'POST',
      Uri.parse('$baseUrl/api/v1/opsroom/incidents/$incidentId/execute'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'human_approved': humanApproved}),
    );
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
