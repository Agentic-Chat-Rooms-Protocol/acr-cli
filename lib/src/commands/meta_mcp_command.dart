import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:io/ansi.dart';
import 'package:io/io.dart';
import '../api/acr_client.dart';

class MetaMcpCommand extends Command<int> {
  @override
  final String name = 'meta-mcp';

  @override
  final String description =
      'Manage ACR Meta-MCP Forward Proxy, downstream servers, tool governance, and audit logs.';

  final AcrClient client;

  MetaMcpCommand({required this.client}) {
    addSubcommand(MetaMcpListCommand());
    addSubcommand(MetaMcpImportCommand());
    addSubcommand(MetaMcpToggleCommand(enable: true));
    addSubcommand(MetaMcpToggleCommand(enable: false));
    addSubcommand(MetaMcpToolsCommand());
    addSubcommand(MetaMcpCallCommand());
    addSubcommand(MetaMcpVaultCommand());
    addSubcommand(MetaMcpAuditCommand());
  }

  @override
  Future<int> run() async {
    printUsage();
    return ExitCode.success.code;
  }
}

class MetaMcpListCommand extends Command<int> {
  @override
  final String name = 'list';

  @override
  final String description = 'List all registered downstream MCP servers in the Meta-MCP registry.';

  @override
  Future<int> run() async {
    final metaUrl = Platform.environment['ACR_META_MCP_URL'] ?? 'http://localhost:20445';
    try {
      final res = await http.get(Uri.parse('$metaUrl/api/v1/meta-mcp/servers'));
      if (res.statusCode != 200) {
        stderr.writeln(red.wrap('[ERROR] Failed to fetch servers: HTTP ${res.statusCode}'));
        return ExitCode.software.code;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final servers = (data['servers'] as List<dynamic>?) ?? [];

      stdout.writeln('\n${cyan.wrap('======================================================================')}');
      stdout.writeln(bold.wrap(' ACR META-MCP FORWARD PROXY — REGISTERED SERVERS'));
      stdout.writeln('${cyan.wrap('======================================================================')}');

      if (servers.isEmpty) {
        stdout.writeln(darkGray.wrap('  (No servers registered)'));
      } else {
        for (final s in servers) {
          final id = s['id'] as String;
          final enabled = s['enabled'] as bool? ?? true;
          final quarantined = s['quarantined'] as bool? ?? false;
          final health = s['healthStatus'] as String? ?? 'OFFLINE';
          final transport = s['transport'] as String? ?? 'stdio';
          final displayName = s['displayName'] as String? ?? id;
          final tools = s['toolCount'] ?? 0;

          final badge = !enabled
              ? red.wrap('[DISABLED]')
              : (quarantined ? yellow.wrap('[QUARANTINE]') : green.wrap('[ONLINE]'));

          stdout.writeln('  $badge ${bold.wrap(id.padRight(22))} | ${transport.padRight(16)} | $displayName ($tools tools)');
        }
      }
      stdout.writeln('\nTotal: ${servers.length} servers registered\n');
      return ExitCode.success.code;
    } catch (e) {
      stderr.writeln(red.wrap('[ERROR] Meta-MCP Proxy unreachable at $metaUrl: $e'));
      return ExitCode.unavailable.code;
    }
  }
}

class MetaMcpImportCommand extends Command<int> {
  @override
  final String name = 'import';

  @override
  final String description = 'Import and compile standard mcp_config.json into versioned Install Manifest.';

  MetaMcpImportCommand() {
    argParser.addOption('file', abbr: 'f', help: 'Path to mcp_config.json');
  }

  @override
  Future<int> run() async {
    final metaUrl = Platform.environment['ACR_META_MCP_URL'] ?? 'http://localhost:20445';
    final filePath = argResults?['file'] as String? ?? (argResults?.rest.isNotEmpty == true ? argResults!.rest.first : null);

    if (filePath == null) {
      stderr.writeln(yellow.wrap('Usage: acr meta-mcp import <path/to/mcp_config.json>'));
      return ExitCode.usage.code;
    }

    final file = File(filePath);
    if (!file.existsSync()) {
      stderr.writeln(red.wrap('[ERROR] File not found: $filePath'));
      return ExitCode.noInput.code;
    }

    final content = file.readAsStringSync();
    try {
      final res = await http.post(
        Uri.parse('$metaUrl/api/v1/meta-mcp/servers/import'),
        headers: {'Content-Type': 'application/json', 'x-acr-agent-did': 'did:key:cli-admin'},
        body: content,
      );

      if (res.statusCode != 200) {
        stderr.writeln(red.wrap('[ERROR] Import failed: ${res.body}'));
        return ExitCode.software.code;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      stdout.writeln(green.wrap('✔ Successfully compiled and installed manifest!'));
      stdout.writeln('  Manifest Version: ${data['manifestVersion']}');
      stdout.writeln('  SHA-256 Fingerprint: ${data['fingerprintSha256']}');
      stdout.writeln('  Installed Servers: ${(data['installedServers'] as List).join(', ')}');
      stdout.writeln('  Redacted Secrets in Vault: ${data['secretCount']}\n');
      return ExitCode.success.code;
    } catch (e) {
      stderr.writeln(red.wrap('[ERROR] Meta-MCP Proxy unreachable at $metaUrl: $e'));
      return ExitCode.unavailable.code;
    }
  }
}

class MetaMcpToggleCommand extends Command<int> {
  final bool enable;

  @override
  String get name => enable ? 'enable' : 'disable';

  @override
  String get description => enable ? 'Enable a registered downstream MCP server.' : 'Disable a registered downstream MCP server.';

  MetaMcpToggleCommand({required this.enable});

  @override
  Future<int> run() async {
    final metaUrl = Platform.environment['ACR_META_MCP_URL'] ?? 'http://localhost:20445';
    final serverId = argResults?.rest.isNotEmpty == true ? argResults!.rest.first : null;

    if (serverId == null) {
      stderr.writeln(yellow.wrap('Usage: acr meta-mcp $name <serverId>'));
      return ExitCode.usage.code;
    }

    try {
      final res = await http.post(
        Uri.parse('$metaUrl/api/v1/meta-mcp/servers/$serverId/toggle'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'enabled': enable}),
      );

      if (res.statusCode != 200) {
        stderr.writeln(red.wrap('[ERROR] Failed to update server: ${res.body}'));
        return ExitCode.software.code;
      }

      stdout.writeln(green.wrap('✔ Server "$serverId" is now ${enable ? 'ENABLED' : 'DISABLED'}.'));
      return ExitCode.success.code;
    } catch (e) {
      stderr.writeln(red.wrap('[ERROR] Meta-MCP Proxy unreachable at $metaUrl: $e'));
      return ExitCode.unavailable.code;
    }
  }
}

class MetaMcpToolsCommand extends Command<int> {
  @override
  final String name = 'tools';

  @override
  final String description = 'List tools in Raw, Policy, or Projected catalog.';

  MetaMcpToolsCommand() {
    argParser.addOption('view', abbr: 'v', defaultsTo: 'projected', allowed: ['raw', 'policy', 'projected'], help: 'Catalog view layer');
  }

  @override
  Future<int> run() async {
    final metaUrl = Platform.environment['ACR_META_MCP_URL'] ?? 'http://localhost:20445';
    final view = argResults?['view'] as String? ?? 'projected';

    try {
      final res = await http.get(Uri.parse('$metaUrl/api/v1/meta-mcp/tools?view=$view'));
      if (res.statusCode != 200) {
        stderr.writeln(red.wrap('[ERROR] Failed to fetch tools: HTTP ${res.statusCode}'));
        return ExitCode.software.code;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final tools = (data['tools'] as List<dynamic>?) ?? [];

      stdout.writeln('\n${cyan.wrap('======================================================================')}');
      stdout.writeln(bold.wrap(' ACR META-MCP TOOL CATALOG (${view.toUpperCase()})'));
      stdout.writeln('${cyan.wrap('======================================================================')}');

      for (final t in tools) {
        final name = t['name'] as String;
        final serverId = t['serverId'] as String? ?? 'default';
        final desc = t['description'] as String? ?? '';
        stdout.writeln('  • ${bold.wrap(name.padRight(34))} | ${darkGray.wrap('[$serverId]')} $desc');
      }
      stdout.writeln('\nTotal tools: ${tools.length}\n');
      return ExitCode.success.code;
    } catch (e) {
      stderr.writeln(red.wrap('[ERROR] Meta-MCP Proxy unreachable at $metaUrl: $e'));
      return ExitCode.unavailable.code;
    }
  }
}

class MetaMcpCallCommand extends Command<int> {
  @override
  final String name = 'call';

  @override
  final String description = 'Execute a governed tool invocation through Meta-MCP policy engine.';

  @override
  Future<int> run() async {
    final metaUrl = Platform.environment['ACR_META_MCP_URL'] ?? 'http://localhost:20445';
    final rest = argResults?.rest ?? [];
    if (rest.isEmpty) {
      stderr.writeln(yellow.wrap('Usage: acr meta-mcp call <namespaced_tool_name> [json_arguments]'));
      return ExitCode.usage.code;
    }

    final toolName = rest[0];
    Map<String, dynamic> args = {};
    if (rest.length > 1) {
      try {
        args = jsonDecode(rest.sublist(1).join(' ')) as Map<String, dynamic>;
      } catch (e) {
        stderr.writeln(red.wrap('[ERROR] Invalid JSON arguments: $e'));
        return ExitCode.usage.code;
      }
    }

    try {
      final res = await http.post(
        Uri.parse('$metaUrl/api/v1/meta-mcp/tools/call'),
        headers: {'Content-Type': 'application/json', 'x-acr-agent-did': 'did:key:cli-agent'},
        body: jsonEncode({'toolName': toolName, 'args': args}),
      );

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(data));
      return ExitCode.success.code;
    } catch (e) {
      stderr.writeln(red.wrap('[ERROR] Meta-MCP Proxy unreachable at $metaUrl: $e'));
      return ExitCode.unavailable.code;
    }
  }
}

class MetaMcpAuditCommand extends Command<int> {
  @override
  final String name = 'audit';

  @override
  final String description = 'Display live cryptographic audit log trail for Meta-MCP operations.';

  @override
  Future<int> run() async {
    final metaUrl = Platform.environment['ACR_META_MCP_URL'] ?? 'http://localhost:20445';
    try {
      final res = await http.get(Uri.parse('$metaUrl/api/v1/meta-mcp/audit?limit=25'));
      if (res.statusCode != 200) {
        stderr.writeln(red.wrap('[ERROR] Failed to fetch audit logs: HTTP ${res.statusCode}'));
        return ExitCode.software.code;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final logs = (data['logs'] as List<dynamic>?) ?? [];

      stdout.writeln('\n${cyan.wrap('======================================================================')}');
      stdout.writeln(bold.wrap(' ACR META-MCP REPLAY AUDIT TRAIL'));
      stdout.writeln('${cyan.wrap('======================================================================')}');

      for (final a in logs) {
        final ts = (a['timestamp'] as String? ?? '').length > 19 ? (a['timestamp'] as String).substring(11, 19) : a['timestamp'];
        final event = (a['eventType'] as String? ?? '').padRight(18);
        final status = a['status'] == 'SUCCESS' ? green.wrap('SUCCESS ') : (a['status'] == 'DENIED' ? red.wrap('DENIED  ') : yellow.wrap(a['status']));
        final actor = a['actorDid'] as String? ?? 'unknown';
        final target = a['toolName'] ?? a['serverId'] ?? '';
        final latency = a['latencyMs'] != null ? '${(a['latencyMs'] as num).toStringAsFixed(2)}ms' : '-';

        stdout.writeln('  [$ts] $event | $status | $actor -> $target ($latency)');
      }
      return ExitCode.success.code;
    } catch (e) {
      stderr.writeln(red.wrap('[ERROR] Meta-MCP Proxy unreachable at $metaUrl: $e'));
      return ExitCode.unavailable.code;
    }
  }
}

class MetaMcpVaultCommand extends Command<int> {
  @override
  final String name = 'vault';

  @override
  final String description = 'Manage encrypted Auth Vault credentials (SQLite3MultipleCiphers & SQLCipher).';

  MetaMcpVaultCommand() {
    argParser.addOption('action', abbr: 'a', defaultsTo: 'list', allowed: ['list', 'set', 'delete', 'rotate']);
    argParser.addOption('server', abbr: 's', help: 'Server ID for secret');
    argParser.addOption('key', abbr: 'k', help: 'Secret key identifier');
    argParser.addOption('value', abbr: 'v', help: 'Secret plaintext value');
    argParser.addOption('domain', abbr: 'd', defaultsTo: 'personal', allowed: ['personal', 'org', 'enterprise', 'ephemeral']);
    argParser.addOption('cipher', abbr: 'c', defaultsTo: 'aes-256-gcm', allowed: ['aes-256-gcm', 'chacha20-poly1305', 'sqlcipher-v4']);
    argParser.addOption('ref-id', help: 'Ref ID for deletion');
    argParser.addOption('new-secret', help: 'New master passphrase for rotation');
  }

  @override
  Future<int> run() async {
    final metaUrl = Platform.environment['ACR_META_MCP_URL'] ?? 'http://localhost:20445';
    final action = argResults?['action'] as String? ?? (argResults?.rest.isNotEmpty == true ? argResults!.rest.first : 'list');

    try {
      if (action == 'list') {
        final res = await http.get(Uri.parse('$metaUrl/api/v1/meta-mcp/vault/secrets'));
        if (res.statusCode != 200) {
          stderr.writeln(red.wrap('[ERROR] Failed to list vault secrets: HTTP ${res.statusCode}'));
          return ExitCode.software.code;
        }

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final secrets = (data['secrets'] as List<dynamic>?) ?? [];

        stdout.writeln('\n${cyan.wrap('======================================================================')}');
        stdout.writeln(bold.wrap(' ACR META-MCP AUTH VAULT — ENCRYPTED SECRETS'));
        stdout.writeln('${cyan.wrap('======================================================================')}');

        if (secrets.isEmpty) {
          stdout.writeln(darkGray.wrap('  (No secrets stored in vault)'));
        } else {
          for (final s in secrets) {
            final domain = '[${s['domain'] ?? 'personal'}]'.padRight(12);
            final refId = (s['refId'] as String? ?? '').padRight(32);
            final serverId = (s['serverId'] as String? ?? '').padRight(18);
            final cipher = s['algorithm'] ?? 'aes-256-gcm';
            stdout.writeln('  ${magenta.wrap(domain)} ${bold.wrap(refId)} | $serverId | Cipher: $cipher');
          }
        }
        stdout.writeln('\nTotal: ${secrets.length} vaulted credentials\n');
        return ExitCode.success.code;
      } else if (action == 'set') {
        final server = argResults?['server'] as String? ?? (argResults?.rest.length ?? 0 > 1 ? argResults!.rest[1] : null);
        final key = argResults?['key'] as String? ?? (argResults?.rest.length ?? 0 > 2 ? argResults!.rest[2] : null);
        final value = argResults?['value'] as String? ?? (argResults?.rest.length ?? 0 > 3 ? argResults!.rest[3] : null);
        final domain = argResults?['domain'] as String? ?? 'personal';
        final cipher = argResults?['cipher'] as String? ?? 'aes-256-gcm';

        if (server == null || key == null || value == null) {
          stderr.writeln(yellow.wrap('Usage: acr meta-mcp vault --action=set --server=<id> --key=<key> --value=<val>'));
          return ExitCode.usage.code;
        }

        final res = await http.post(
          Uri.parse('$metaUrl/api/v1/meta-mcp/vault/secrets'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'serverId': server, 'key': key, 'value': value, 'domain': domain, 'cipher': cipher}),
        );
        stdout.writeln(green.wrap('[SUCCESS] Stored secret in encrypted vault: ${res.body}'));
        return ExitCode.success.code;
      } else if (action == 'delete') {
        final refId = argResults?['ref-id'] as String? ?? (argResults?.rest.length ?? 0 > 1 ? argResults!.rest[1] : null);
        if (refId == null) {
          stderr.writeln(yellow.wrap('Usage: acr meta-mcp vault --action=delete --ref-id=<ref_id>'));
          return ExitCode.usage.code;
        }
        final res = await http.delete(Uri.parse('$metaUrl/api/v1/meta-mcp/vault/secrets/$refId'));
        stdout.writeln(green.wrap('[SUCCESS] Deleted secret from vault: ${res.body}'));
        return ExitCode.success.code;
      } else if (action == 'rotate') {
        final newSecret = argResults?['new-secret'] as String? ?? (argResults?.rest.length ?? 0 > 1 ? argResults!.rest[1] : null);
        if (newSecret == null) {
          stderr.writeln(yellow.wrap('Usage: acr meta-mcp vault --action=rotate --new-secret=<passphrase>'));
          return ExitCode.usage.code;
        }
        final res = await http.post(
          Uri.parse('$metaUrl/api/v1/meta-mcp/vault/rotate'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'newMasterSecret': newSecret}),
        );
        stdout.writeln(green.wrap('[SUCCESS] Vault master passphrase rotated: ${res.body}'));
        return ExitCode.success.code;
      }
      return ExitCode.success.code;
    } catch (e) {
      stderr.writeln(red.wrap('[ERROR] Vault operation failed: $e'));
      return ExitCode.unavailable.code;
    }
  }
}

