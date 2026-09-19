import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart';
import 'package:stack_trace/stack_trace.dart';
import 'package:acr_cli/acr_cli.dart';

const String acrCliVersion = '0.9.0';

void main(List<String> args) {
  Chain.capture(
    () async {
      final defaultUrl =
          Platform.environment['ACR_DAEMON_URL'] ?? 'http://localhost:20443';

      final runner = CommandRunner(
        'acr',
        'Agentic Chat Rooms (ACR) Protocol - High-Performance Native CLI\n'
            'Real-time deliberation, rooms management, voting, file transfer, and cryptographic audit replay.',
      );

      runner.argParser
        ..addOption(
          'url',
          abbr: 'u',
          defaultsTo: defaultUrl,
          help: 'Target ACR Daemon HTTP endpoint',
        )
        ..addFlag(
          'version',
          negatable: false,
          help: 'Print CLI and Protocol version',
        );

      // Parse top-level options to get URL
      String daemonUrl = defaultUrl;
      try {
        final topResults = runner.argParser.parse(args);
        if (topResults['version'] == true) {
          stdout.writeln(
            'ACR Native CLI v$acrCliVersion (Protocol ACP v2 / W3C DID)',
          );
          exit(ExitCode.success.code);
        }
        daemonUrl = topResults['url'] as String? ?? defaultUrl;
      } catch (_) {
        // Defer to runner.run to report accurate usage/parsing errors
      }

      final client = AcrClient(baseUrl: daemonUrl);

      runner
        ..addCommand(StatusCommand(client: client))
        ..addCommand(HealthCommand(client: client))
        ..addCommand(RoomsCommand(client: client))
        ..addCommand(SendCommand(client: client))
        ..addCommand(BroadcastCommand(client: client))
        ..addCommand(ProposalsCommand(client: client))
        ..addCommand(FilesCommand(client: client))
        ..addCommand(BuddiesCommand(client: client))
        ..addCommand(ApproveCommand(client: client))
        ..addCommand(AuditCommand(client: client))
        ..addCommand(ConfigCommand(client: client))
        ..addCommand(TunnelCommand(client: client))
        ..addCommand(MetaMcpCommand(client: client))
        ..addCommand(PortsCommand(client: client))
        ..addCommand(OpsRoomCommand(client: client));

      if (args.isEmpty) {
        // Default to status dashboard when no subcommand given
        await runner.run(['status']);
        return;
      }

      await runner.run(args);
    },
    onError: (error, chain) {
      if (error is UsageException) {
        stderr.writeln(error.message);
        stderr.writeln(error.usage);
        exit(ExitCode.usage.code);
      } else {
        stderr.writeln('\x1B[1;31m[FATAL ERROR] $error\x1B[0m');
        stderr.writeln(chain.terse);
        exit(1);
      }
    },
  );
}
