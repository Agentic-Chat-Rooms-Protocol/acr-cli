import 'dart:io';

import 'package:args/command_runner.dart';

import '../api/acr_client.dart';

class HealthCommand extends Command {
  @override
  final String name = 'health';
  @override
  final String description =
      'Inspect ACR Daemon health, uptime, agent counts, and audit chain depth.';

  HealthCommand({required this.client});

  final AcrClient client;

  @override
  Future<void> run() async {
    try {
      final h = await client.fetchHealth();
      stdout.writeln(
        '\x1B[1;32m[HEALTH STATUS: ${(h['status'] as String? ?? 'healthy').toUpperCase()}]\x1B[0m',
      );
      stdout.writeln('  Version:            ${h['version']}');
      stdout.writeln('  Uptime:             ${h['uptime']}');
      stdout.writeln('  Mesh Latency:       ${h['mesh_latency_ms']} ms');
      stdout.writeln('  Active Agents:      ${h['agent_count']}');
      stdout.writeln('  Active Rooms:       ${h['room_count']}');
      stdout.writeln('  Audit Chain Depth:  ${h['audit_chain_depth']} blocks');
    } catch (e) {
      stderr.writeln(
        '\x1B[1;31m[ERROR] ACR Daemon unreachable at ${client.baseUrl}: $e\x1B[0m',
      );
      exit(1);
    }
  }
}
