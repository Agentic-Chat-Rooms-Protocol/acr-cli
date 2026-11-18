import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:io/ansi.dart';
import 'package:io/io.dart';

import '../mcp/mcp_endpoint.dart';

class LoginCommand extends Command {
  LoginCommand({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client() {
    argParser
      ..addOption(
        'scopes',
        defaultsTo: 'profile email',
        help: 'Clerk OAuth scopes to request for Remote MCP (profile email).',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Discover RFC 9728 metadata and print PKCE authorization parameters without waiting for callback.',
      )
      ..addOption(
        'home-dir',
        hide: true,
        help: 'Override home directory for session metadata storage (testing).',
      );
  }

  final http.Client _httpClient;

  @override
  final String name = 'login';

  @override
  final String description =
      'Authenticate for Remote MCP via Clerk OAuth 2.1 (PKCE S256, scopes: profile email).';

  static Future<Map<String, dynamic>> discoverMetadata(
    http.Client client,
  ) async {
    final uri = Uri.parse(McpEndpoint.resourceMetadataUrl);
    final req = http.Request('GET', uri)
      ..followRedirects = false
      ..maxRedirects = 0;
    final streamed = await client
        .send(req)
        .timeout(const Duration(seconds: 10));
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode >= 300 && res.statusCode < 400) {
      throw HttpException(
        'Redirect blocked (HTTP ${res.statusCode}): redirects are not followed',
        uri: uri,
      );
    }
    if (res.statusCode != 200) {
      throw HttpException(
        'RFC 9728 metadata discovery failed: HTTP ${res.statusCode}',
        uri: uri,
      );
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid RFC 9728 metadata payload');
    }
    final resource = decoded['resource']?.toString() ?? '';
    if (resource != McpEndpoint.remoteUrl) {
      throw FormatException(
        'Protected resource mismatch: expected ${McpEndpoint.remoteUrl}, got "$resource"',
      );
    }
    return decoded;
  }

  @override
  Future<int> run() async {
    final scopesRaw = (argResults?['scopes'] as String?) ?? 'profile email';
    final requestedScopes = scopesRaw
        .split(RegExp(r'[\s,]+'))
        .where((s) => s.isNotEmpty)
        .toList();

    for (final s in requestedScopes) {
      if (s == 'acr:rooms' || s == 'acr:cloud:pro') {
        stderr.writeln(
          red.wrap(
            '[ERROR] Legacy scope "$s" is deprecated. Clerk OAuth for Remote MCP strictly uses: profile email',
          ),
        );
        exitCode = ExitCode.usage.code;
        return ExitCode.usage.code;
      }
    }
    if (!McpEndpoint.requiredOAuthScopes.every(requestedScopes.contains)) {
      stderr.writeln(
        red.wrap(
          '[ERROR] Remote MCP requires Clerk OAuth scopes: ${McpEndpoint.requiredOAuthScopes.join(' ')}',
        ),
      );
      exitCode = ExitCode.usage.code;
      return ExitCode.usage.code;
    }

    final dryRun = (argResults?['dry-run'] as bool?) ?? false;
    final verifier = McpEndpoint.generateCodeVerifier();
    final challenge = McpEndpoint.pkceS256Challenge(verifier);

    String issuer = McpEndpoint.clerkIssuer;
    try {
      final metadata = await discoverMetadata(_httpClient);
      final authServers = metadata['authorization_servers'];
      if (authServers is List && authServers.isNotEmpty) {
        issuer = authServers.first.toString();
      }
    } on FormatException catch (e) {
      stderr.writeln(
        red.wrap('[ERROR] RFC 9728 metadata verification failed: $e'),
      );
      exitCode = ExitCode.data.code;
      return ExitCode.data.code;
    } on HttpException catch (e) {
      if (e.message.contains('Redirect blocked')) {
        stderr.writeln(
          red.wrap('[ERROR] RFC 9728 metadata discovery failed: $e'),
        );
        exitCode = ExitCode.software.code;
        return ExitCode.software.code;
      }
      if (!dryRun) {
        stderr.writeln(
          yellow.wrap(
            '[WARN] Could not fetch RFC 9728 metadata ($e); using pinned Clerk issuer $issuer.',
          ),
        );
      }
    } catch (e) {
      if (!dryRun) {
        stderr.writeln(
          yellow.wrap(
            '[WARN] Could not fetch RFC 9728 metadata ($e); using pinned Clerk issuer $issuer.',
          ),
        );
      }
    }

    stdout.writeln(
      cyan.wrap(
        '======================================================================',
      ),
    );
    stdout.writeln(
      styleBold.wrap(' ACR REMOTE MCP — CLERK OAUTH 2.1 (PKCE S256)'),
    );
    stdout.writeln(
      cyan.wrap(
        '======================================================================',
      ),
    );
    stdout.writeln('  Resource      : ${McpEndpoint.remoteUrl}');
    stdout.writeln('  Issuer        : $issuer');
    stdout.writeln('  Scopes        : ${requestedScopes.join(' ')}');
    stdout.writeln('  PKCE Method   : S256');
    stdout.writeln('  Code Challenge: $challenge');
    stdout.writeln(
      '  Storage Policy: Non-secret session metadata only (~/.acr/mcp-session.json);',
    );
    stdout.writeln(
      '                  MCP host manages OAuth tokens directly via `acr mcp install`.',
    );

    if (dryRun) {
      stdout.writeln(
        '\nDry run complete. Run `acr mcp install` to register host-managed OAuth.',
      );
      return ExitCode.success.code;
    }

    final homeDir = argResults?['home-dir'] as String?;
    McpEndpoint.saveSession(
      McpSessionMetadata(
        scopes: requestedScopes,
        issuer: issuer,
        resource: McpEndpoint.remoteUrl,
        checkedAt: DateTime.now().toUtc(),
      ),
      homeDir: homeDir,
    );
    stdout.writeln(
      green.wrap(
        '\n✔ Remote MCP routing preference recorded (scopes: ${requestedScopes.join(', ')}).',
      ),
    );
    stdout.writeln(
      '  Run `acr mcp install` to register `acr-remote` (${McpEndpoint.remoteUrl}) in your MCP client.',
    );
    return ExitCode.success.code;
  }
}

class LogoutCommand extends Command {
  LogoutCommand() {
    argParser.addOption(
      'home-dir',
      hide: true,
      help: 'Override home directory for session metadata storage (testing).',
    );
  }

  @override
  final String name = 'logout';

  @override
  final String description =
      'Clear local Remote MCP session metadata and revert routing to local daemon.';

  @override
  Future<int> run() async {
    final homeDir = argResults?['home-dir'] as String?;
    final removed = McpEndpoint.clearSession(homeDir: homeDir);
    if (removed) {
      stdout.writeln(
        green.wrap(
          '✔ Cleared Remote MCP session metadata. Active MCP routing reverted to local daemon.',
        ),
      );
    } else {
      stdout.writeln(
        'No active Remote MCP session metadata found; routing remains local.',
      );
    }
    stdout.writeln('  Local ACR rooms and daemon state are unchanged.');
    return ExitCode.success.code;
  }
}
