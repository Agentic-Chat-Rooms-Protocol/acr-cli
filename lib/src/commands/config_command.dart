import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:io/io.dart';
import '../api/acr_client.dart';

class ConfigCommand extends Command<void> {
  ConfigCommand({required this.client}) {
    addSubcommand(ConfigSecurityCommand(client: client));
  }

  final AcrClient client;

  @override
  String get name => 'config';

  @override
  String get description => 'Manage ACR Daemon security policies, CORS, PNA, and runtime settings.';

  @override
  Future<void> run() async {
    printUsage();
  }
}

class ConfigSecurityCommand extends Command<void> {
  ConfigSecurityCommand({required this.client}) {
    argParser
      ..addFlag(
        'cors',
        defaultsTo: null,
        help: 'Enable or disable Cross-Origin Resource Sharing (CORS)',
      )
      ..addFlag(
        'pna',
        defaultsTo: null,
        help: 'Enable or disable Private Network Access (PNA) for public HTTPS origins',
      );
  }

  final AcrClient client;

  @override
  String get name => 'security';

  @override
  String get description => 'Inspect and configure Private Network Access (PNA) and CORS on the daemon.';

  @override
  Future<void> run() async {
    final bool? corsFlag = argResults?['cors'] as bool?;
    final bool? pnaFlag = argResults?['pna'] as bool?;

    try {
      if (corsFlag != null || pnaFlag != null) {
        stdout.writeln('\x1B[1;36mUpdating ACR Security Policy...\x1B[0m');
        final updated = await client.updateSecurityConfig(
          enableCors: corsFlag,
          enablePna: pnaFlag,
        );
        _renderSecurityConfig(updated);
        exit(ExitCode.success.code);
      }

      final config = await client.fetchSecurityConfig();
      _renderSecurityConfig(config);
    } catch (e) {
      stderr.writeln('\x1B[1;31m[ERROR] Failed to communicate with ACR Daemon at ${client.baseUrl}: $e\x1B[0m');
      exit(1);
    }
  }

  void _renderSecurityConfig(Map<String, dynamic> config) {
    final bool enableCors = config['enable_cors'] as bool? ?? false;
    final bool enablePna = config['enable_pna'] as bool? ?? false;
    final String corsStatus = config['cors_status'] as String? ?? (enableCors ? 'active' : 'disabled');
    final String pnaStatus = config['pna_status'] as String? ?? (enablePna ? 'active' : 'disabled');
    final String version = config['version'] as String? ?? 'v0.8.2';

    stdout.writeln('======================================================================');
    stdout.writeln(' ACR DAEMON SECURITY & NETWORK POLICY ($version)');
    stdout.writeln(' Target Daemon: ${client.baseUrl}');
    stdout.writeln('======================================================================');
    stdout.writeln(
      '  Cross-Origin Resource Sharing (CORS) : ${enableCors ? "\x1B[1;32m[ENABLED - $corsStatus]\x1B[0m" : "\x1B[1;31m[DISABLED]\x1B[0m"}',
    );
    stdout.writeln(
      '  Private Network Access (PNA)        : ${enablePna ? "\x1B[1;32m[ENABLED - $pnaStatus]\x1B[0m" : "\x1B[1;31m[DISABLED]\x1B[0m"}',
    );
    stdout.writeln('----------------------------------------------------------------------');
    stdout.writeln('  • PNA allows public HTTPS clients (e.g. Vercel) to discover local daemon.');
    stdout.writeln('  • Use `acr config security --no-cors` or `--no-pna` to restrict access.');
    stdout.writeln('======================================================================');
  }
}
