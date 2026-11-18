import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

enum McpMode { local, remote }

class McpResolution {
  const McpResolution({
    required this.mode,
    required this.url,
    required this.reason,
  });

  final McpMode mode;
  final String url;
  final String reason;
}

class McpSessionMetadata {
  const McpSessionMetadata({
    required this.scopes,
    required this.issuer,
    required this.resource,
    required this.checkedAt,
    this.expiresAt,
  });

  final List<String> scopes;
  final String issuer;
  final String resource;
  final DateTime checkedAt;
  final DateTime? expiresAt;

  bool get isExpired =>
      expiresAt != null && DateTime.now().toUtc().isAfter(expiresAt!.toUtc());

  Map<String, dynamic> toJson() => {
    'scopes': scopes,
    'issuer': issuer,
    'resource': resource,
    'checkedAt': checkedAt.toUtc().toIso8601String(),
    if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
  };

  static McpSessionMetadata? fromJson(Map<String, dynamic> json) {
    final rawScopes = json['scopes'];
    if (rawScopes is! List) return null;
    final scopes = rawScopes.map((e) => e.toString()).toList();
    final issuer = json['issuer']?.toString() ?? McpEndpoint.clerkIssuer;
    final resource = json['resource']?.toString() ?? McpEndpoint.remoteUrl;
    final checkedAtRaw = json['checkedAt']?.toString();
    final checkedAt = checkedAtRaw != null
        ? DateTime.tryParse(checkedAtRaw) ?? DateTime.now().toUtc()
        : DateTime.now().toUtc();
    final expiresAtRaw = json['expiresAt']?.toString();
    final expiresAt = expiresAtRaw != null
        ? DateTime.tryParse(expiresAtRaw)
        : null;
    return McpSessionMetadata(
      scopes: scopes,
      issuer: issuer,
      resource: resource,
      checkedAt: checkedAt,
      expiresAt: expiresAt,
    );
  }
}

class McpEndpoint {
  static const String remoteUrl = 'https://mcp.agentchatrooms.dev/mcp';
  static const String clerkIssuer = 'https://clerk.agentchatrooms.dev';
  static const String resourceMetadataUrl =
      'https://mcp.agentchatrooms.dev/.well-known/oauth-protected-resource/mcp';
  static const List<String> requiredOAuthScopes = ['profile', 'email'];
  static const int defaultLocalPort = 20443;
  static const String defaultLocalUrl = 'http://127.0.0.1:20443';

  static String? resolveHomeDir({
    Map<String, String>? environment,
    String? homeDir,
  }) {
    if (homeDir != null && homeDir.trim().isNotEmpty) {
      return homeDir.trim();
    }
    final env = environment ?? Platform.environment;
    final candidate = env['USERPROFILE'] ?? env['HOME'];
    if (candidate != null && candidate.trim().isNotEmpty) {
      return candidate.trim();
    }
    return null;
  }

  /// Validates the pinned remote MCP gateway URL.
  /// No flag, env var, file, or redirect may alter the remote host or path.
  static void validateRemote(String raw) {
    if (raw.isEmpty || raw.trim() != raw) {
      throw const FormatException('remote: empty or surrounding whitespace');
    }
    if (raw.contains('@') ||
        raw.contains('?') ||
        raw.contains('#') ||
        raw.contains(r'\')) {
      throw const FormatException(
        'remote: userinfo, query, fragment, or backslash not allowed',
      );
    }
    final match = RegExp(
      r'^https://([^/:?#]+)(?::(\d+))?(/.*)$',
      caseSensitive: false,
    ).firstMatch(raw);
    if (match == null) {
      throw const FormatException(
        'remote: must be https://mcp.agentchatrooms.dev/mcp',
      );
    }
    final host = match.group(1)!;
    final portStr = match.group(2);
    final path = match.group(3)!;
    if (host.toLowerCase() != 'mcp.agentchatrooms.dev') {
      throw FormatException('remote: host "$host" is not allowlisted');
    }
    if (portStr != null && portStr != '443') {
      throw FormatException('remote: port "$portStr" is not allowlisted');
    }
    if (path != '/mcp') {
      throw FormatException('remote: path "$path" must be /mcp');
    }
  }

  /// Validates a local daemon URL, pinning `localhost` to `127.0.0.1`
  /// and rejecting non-loopback, alternate IP notations, userinfo, paths,
  /// queries, fragments, or out-of-range ports.
  static String validateLocal(String raw) {
    if (raw.isEmpty || raw.trim() != raw) {
      throw const FormatException('local: empty or surrounding whitespace');
    }
    if (raw.contains('@') ||
        raw.contains('?') ||
        raw.contains('#') ||
        raw.contains(r'\')) {
      throw const FormatException(
        'local: userinfo, query, fragment, or backslash not allowed',
      );
    }
    final match = RegExp(
      r'^http://(\[::1\]|127\.0\.0\.1|localhost)(?::(\d+))?(/?)$',
      caseSensitive: false,
    ).firstMatch(raw);
    if (match == null) {
      throw const FormatException(
        'local: host must be localhost, 127.0.0.1, or ::1 over http with optional port and no path',
      );
    }
    var host = match.group(1)!.toLowerCase();
    if (host == 'localhost') {
      host = '127.0.0.1';
    }
    final portStr = match.group(2);
    var port = defaultLocalPort;
    if (portStr != null) {
      final parsed = int.tryParse(portStr);
      if (parsed == null || parsed < 1024 || parsed > 65535) {
        throw FormatException('local: port must be 1024-65535, got "$portStr"');
      }
      port = parsed;
    }
    return 'http://$host:$port';
  }

  /// Resolves the local daemon URL candidate following precedence:
  /// explicit localUrl -> ACR_DAEMON_URL -> ~/.acr/ports.json -> 127.0.0.1:20443.
  static String resolveLocalUrlCandidate({
    String? localUrl,
    Map<String, String>? environment,
    String? homeDir,
  }) {
    if (localUrl != null && localUrl.trim().isNotEmpty) {
      return localUrl.trim();
    }
    final env = environment ?? Platform.environment;
    final envUrl = env['ACR_DAEMON_URL'];
    if (envUrl != null && envUrl.trim().isNotEmpty) {
      return envUrl.trim();
    }
    final resolvedHome = resolveHomeDir(environment: env, homeDir: homeDir);
    if (resolvedHome != null) {
      final portsFile = File(
        '$resolvedHome${Platform.pathSeparator}.acr${Platform.pathSeparator}ports.json',
      );
      if (portsFile.existsSync()) {
        try {
          final decoded = jsonDecode(portsFile.readAsStringSync());
          if (decoded is Map<String, dynamic>) {
            final ports = decoded['ports'];
            if (ports is Map<String, dynamic>) {
              final corePort = ports['acr-core'];
              if (corePort is num) {
                return 'http://127.0.0.1:${corePort.toInt()}';
              }
            }
          }
        } catch (_) {
          // Ignore malformed ports.json and fall back to default loopback URL.
        }
      }
    }
    return defaultLocalUrl;
  }

  /// Client-side MCP endpoint resolver.
  /// Always validates the local URL (even when remote mode wins).
  /// Uses Clerk OAuth scopes (`["profile", "email"]`) — never legacy `acr:*` scopes.
  static McpResolution resolve({
    String? override,
    List<String> grantedScopes = const [],
    String? localUrl,
    Map<String, String>? environment,
    String? homeDir,
  }) {
    final env = environment ?? Platform.environment;
    final candidate = resolveLocalUrlCandidate(
      localUrl: localUrl,
      environment: env,
      homeDir: homeDir,
    );
    final validatedLocal = validateLocal(candidate);

    final modeOverride = (override ?? env['ACR_MCP_MODE'] ?? '')
        .trim()
        .toLowerCase();
    if (modeOverride == 'local') {
      return McpResolution(
        mode: McpMode.local,
        url: validatedLocal,
        reason: 'explicit override',
      );
    }
    if (modeOverride == 'remote') {
      validateRemote(remoteUrl);
      return const McpResolution(
        mode: McpMode.remote,
        url: remoteUrl,
        reason: 'explicit override',
      );
    }
    if (modeOverride.isNotEmpty) {
      throw ArgumentError(
        'MCP mode override must be "local" or "remote", got "$modeOverride"',
      );
    }

    final scopeSet = grantedScopes.map((s) => s.trim()).toSet();
    final hasClerkScopes = requiredOAuthScopes.every(scopeSet.contains);
    if (hasClerkScopes) {
      validateRemote(remoteUrl);
      return const McpResolution(
        mode: McpMode.remote,
        url: remoteUrl,
        reason: 'granted Clerk OAuth scopes include profile, email',
      );
    }

    return McpResolution(
      mode: McpMode.local,
      url: validatedLocal,
      reason: 'no remote OAuth session; default local',
    );
  }

  static File _sessionFile({
    Map<String, String>? environment,
    String? homeDir,
  }) {
    final home =
        resolveHomeDir(environment: environment, homeDir: homeDir) ?? '.';
    return File(
      '$home${Platform.pathSeparator}.acr${Platform.pathSeparator}mcp-session.json',
    );
  }

  static McpSessionMetadata? loadSession({
    Map<String, String>? environment,
    String? homeDir,
  }) {
    final file = _sessionFile(environment: environment, homeDir: homeDir);
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, dynamic>) return null;
      final meta = McpSessionMetadata.fromJson(decoded);
      if (meta == null || meta.isExpired) return null;
      return meta;
    } catch (_) {
      return null;
    }
  }

  /// Stores ONLY non-secret session metadata (`scopes`, `issuer`, `resource`, timestamps).
  /// Never writes OAuth access or refresh tokens to disk.
  static void saveSession(
    McpSessionMetadata metadata, {
    Map<String, String>? environment,
    String? homeDir,
  }) {
    final file = _sessionFile(environment: environment, homeDir: homeDir);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(metadata.toJson()),
    );
  }

  static bool clearSession({
    Map<String, String>? environment,
    String? homeDir,
  }) {
    final file = _sessionFile(environment: environment, homeDir: homeDir);
    if (file.existsSync()) {
      file.deleteSync();
      return true;
    }
    return false;
  }

  static String generateCodeVerifier() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String pkceS256Challenge(String verifier) {
    final digest = sha256.convert(ascii.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }
}
