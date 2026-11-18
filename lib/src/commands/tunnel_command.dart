import 'dart:io';

import 'package:args/command_runner.dart';

import '../api/acr_client.dart';

class TunnelCommand extends Command<void> {
  TunnelCommand({required this.client}) {
    argParser
      ..addOption(
        'cloud-url',
        defaultsTo:
            Platform.environment['ACR_CLOUD_URL'] ??
            'https://cloud.agentchatrooms.dev',
        help: 'ACR Cloud relay node URL',
      )
      ..addOption(
        'room',
        defaultsTo: 'ephemeral-sandbox',
        help: 'Target room ID or session identifier',
      )
      ..addFlag(
        'ephemeral',
        defaultsTo: true,
        help: 'Auto-expire tunnel after 15 minutes of inactivity',
      );
  }

  final AcrClient client;

  @override
  String get name => 'tunnel';

  @override
  String get description =>
      'Preflight check and delegate ephemeral reverse tunnel bridging via @acr-js/bridge.';

  @override
  Future<void> run() async {
    final String cloudUrl =
        (argResults?['cloud-url'] as String?) ??
        'https://cloud.agentchatrooms.dev';
    final String room = (argResults?['room'] as String?) ?? 'ephemeral-sandbox';
    final bool ephemeral = (argResults?['ephemeral'] as bool?) ?? true;

    final Uri? parsed = Uri.tryParse(cloudUrl);
    if (parsed == null ||
        parsed.scheme.toLowerCase() != 'https' ||
        parsed.host.isEmpty) {
      stderr.writeln(
        'Error: --cloud-url must be a valid HTTPS URL (plaintext http:// relays are forbidden).',
      );
      exitCode = 64;
      return;
    }

    stdout.writeln(
      '======================================================================',
    );
    stdout.writeln(' ACR SECURE REVERSE TUNNEL PREFLIGHT (v1.0.1)');
    stdout.writeln(
      '======================================================================',
    );
    stdout.writeln(' Local Daemon  : ${client.baseUrl}');
    stdout.writeln(' Cloud Relay   : $cloudUrl');
    stdout.writeln(' Sandbox Room  : $room');
    stdout.writeln(
      ' Auto-Purge TTL: ${ephemeral ? "15 minutes" : "Persistent"}',
    );
    stdout.writeln(
      '----------------------------------------------------------------------',
    );

    bool daemonReachable = false;
    try {
      final health = await client.fetchHealth();
      final status = health['status']?.toString().toUpperCase() ?? '';
      daemonReachable = status == 'HEALTHY' || status == 'UP';
    } catch (_) {
      daemonReachable = false;
    }
    stdout.writeln(
      ' Local Daemon  : ${daemonReachable ? "ONLINE" : "OFFLINE"}',
    );
    stderr.writeln(
      'Error: Interactive WebSocket tunnel transport is not bundled in acr-cli yet. '
      'Use `npx @acr-js/bridge tunnel --url wss://${parsed.host}/tunnel --token \$ACR_ROOM_TOKEN` for live tunneling.',
    );
    exitCode = 1;
  }
}
