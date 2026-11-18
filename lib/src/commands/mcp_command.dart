import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/ansi.dart';
import 'package:io/io.dart';

import '../api/acr_client.dart';
import '../mcp/mcp_endpoint.dart';

class McpCommand extends Command {
  McpCommand({required this.client}) {
    addSubcommand(McpStatusCommand(client: client));
    addSubcommand(McpInstallCommand(client: client));
  }

  final AcrClient client;

  @override
  final String name = 'mcp';

  @override
  final String description =
      'Inspect client-side MCP endpoint resolution and configure MCP host integrations.';

  @override
  Future<int> run() async {
    printUsage();
    return ExitCode.success.code;
  }
}

class McpStatusCommand extends Command {
  McpStatusCommand({required this.client}) {
    argParser
      ..addOption(
        'mode',
        allowed: ['local', 'remote'],
        help: 'Override active MCP endpoint mode (local or remote).',
      )
      ..addOption(
        'home-dir',
        hide: true,
        help: 'Override home directory (testing).',
      );
  }

  final AcrClient client;

  @override
  final String name = 'status';

  @override
  final String description =
      'Show the active MCP endpoint, resolution reason, and local/remote posture.';

  @override
  Future<int> run() async {
    final modeOverride = argResults?['mode'] as String?;
    final homeDir = argResults?['home-dir'] as String?;
    final session = McpEndpoint.loadSession(homeDir: homeDir);

    final McpResolution resolution;
    try {
      resolution = McpEndpoint.resolve(
        override: modeOverride,
        grantedScopes: session?.scopes ?? const [],
        localUrl: client.baseUrl,
        homeDir: homeDir,
      );
    } catch (e) {
      stderr.writeln(
        red.wrap('[ERROR] Invalid MCP endpoint configuration: $e'),
      );
      exitCode = ExitCode.usage.code;
      return ExitCode.usage.code;
    }

    final validatedLocal = McpEndpoint.validateLocal(client.baseUrl);
    final hasLocalToken =
        client.apiToken != null && client.apiToken!.isNotEmpty;

    stdout.writeln(
      cyan.wrap(
        '======================================================================',
      ),
    );
    stdout.writeln(styleBold.wrap(' ACR MCP ENDPOINT RESOLUTION STATUS'));
    stdout.writeln(
      cyan.wrap(
        '======================================================================',
      ),
    );
    stdout.writeln('  Active Mode     : ${resolution.mode.name.toUpperCase()}');
    stdout.writeln('  Active Endpoint : ${resolution.url}');
    stdout.writeln('  Reason          : ${resolution.reason}');
    stdout.writeln('  Local Daemon    : $validatedLocal');
    stdout.writeln(
      '  Local API Token : ${hasLocalToken ? 'configured (redacted)' : 'not set'}',
    );
    stdout.writeln('  Remote Gateway  : ${McpEndpoint.remoteUrl}');
    stdout.writeln(
      '  Clerk OAuth     : ${McpEndpoint.clerkIssuer} (scopes: ${McpEndpoint.requiredOAuthScopes.join(', ')})',
    );
    stdout.writeln(
      '  Active Scopes   : ${(session?.scopes.isNotEmpty ?? false) ? session!.scopes.join(', ') : 'none'}',
    );
    stdout.writeln(
      cyan.wrap(
        '======================================================================',
      ),
    );
    return ExitCode.success.code;
  }
}

class McpInstallCommand extends Command {
  McpInstallCommand({required this.client}) {
    argParser
      ..addOption(
        'client',
        defaultsTo: 'claude-code',
        allowed: ['claude-code', 'claude-desktop', 'cursor'],
        help: 'Target MCP host client.',
      )
      ..addOption(
        'mode',
        allowed: ['local', 'remote'],
        help: 'Force local-only or include remote ACR Cloud MCP entry.',
      )
      ..addOption(
        'config-path',
        help: 'Custom path to the MCP client config JSON file.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help:
            'Print generated MCP client configuration without modifying files.',
      )
      ..addOption(
        'home-dir',
        hide: true,
        help: 'Override home directory (testing).',
      );
  }

  final AcrClient client;

  @override
  final String name = 'install';

  @override
  final String description =
      'Register local ACR MCP server (and remote gateway when entitled) in an MCP client config.';

  static String defaultConfigPath(String clientName, {String? homeDir}) {
    final home = McpEndpoint.resolveHomeDir(homeDir: homeDir) ?? '.';
    final sep = Platform.pathSeparator;
    switch (clientName) {
      case 'claude-code':
        return '$home$sep.claude.json';
      case 'cursor':
        return '$home$sep.cursor${sep}mcp.json';
      case 'claude-desktop':
        if (Platform.isWindows) {
          final appData =
              Platform.environment['APPDATA'] ??
              '$home${sep}AppData${sep}Roaming';
          return '$appData${sep}Claude${sep}claude_desktop_config.json';
        }
        if (Platform.isMacOS) {
          return '$home${sep}Library${sep}Application Support${sep}Claude${sep}claude_desktop_config.json';
        }
        return '$home$sep.config${sep}Claude${sep}claude_desktop_config.json';
      default:
        throw ArgumentError('Unsupported client: $clientName');
    }
  }

  @override
  Future<int> run() async {
    final clientName = (argResults?['client'] as String?) ?? 'claude-code';
    final modeOverride = argResults?['mode'] as String?;
    final homeDir = argResults?['home-dir'] as String?;
    final dryRun = (argResults?['dry-run'] as bool?) ?? false;
    final configPath =
        (argResults?['config-path'] as String?) ??
        defaultConfigPath(clientName, homeDir: homeDir);

    final session = McpEndpoint.loadSession(homeDir: homeDir);
    final McpResolution resolution;
    try {
      resolution = McpEndpoint.resolve(
        override: modeOverride,
        grantedScopes: session?.scopes ?? const [],
        localUrl: client.baseUrl,
        homeDir: homeDir,
      );
    } catch (e) {
      stderr.writeln(
        red.wrap('[ERROR] Invalid MCP endpoint configuration: $e'),
      );
      exitCode = ExitCode.usage.code;
      return ExitCode.usage.code;
    }

    final validatedLocal = McpEndpoint.validateLocal(client.baseUrl);
    final file = File(configPath);
    Map<String, dynamic> root = {};
    if (file.existsSync()) {
      try {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is Map<String, dynamic>) {
          root = decoded;
        }
      } catch (e) {
        stderr.writeln(
          red.wrap('[ERROR] Failed to parse existing config $configPath: $e'),
        );
        exitCode = ExitCode.data.code;
        return ExitCode.data.code;
      }
    }

    final servers = (root['mcpServers'] is Map<String, dynamic>)
        ? Map<String, dynamic>.from(root['mcpServers'] as Map<String, dynamic>)
        : <String, dynamic>{};

    servers['acr'] = {
      'command': 'acr-mcp-server',
      'env': {'ACR_DAEMON_URL': validatedLocal},
    };

    if (resolution.mode == McpMode.remote) {
      servers['acr-remote'] = {'type': 'http', 'url': McpEndpoint.remoteUrl};
    } else {
      servers.remove('acr-remote');
    }

    root['mcpServers'] = servers;
    final formatted = const JsonEncoder.withIndent('  ').convert(root);

    if (dryRun) {
      stdout.writeln(formatted);
      return ExitCode.success.code;
    }

    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    file.writeAsStringSync('$formatted\n');

    stdout.writeln(
      green.wrap('✔ Updated $clientName MCP config at $configPath'),
    );
    stdout.writeln('  Local server  : acr -> $validatedLocal');
    if (resolution.mode == McpMode.remote) {
      stdout.writeln(
        '  Remote server : acr-remote -> ${McpEndpoint.remoteUrl} (host-managed Clerk OAuth)',
      );
    } else {
      stdout.writeln('  Remote server : not registered (mode: local)');
    }
    return ExitCode.success.code;
  }
}
