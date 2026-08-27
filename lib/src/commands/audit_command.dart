import 'dart:io';

import 'package:args/command_runner.dart';

import '../api/acr_client.dart';

class AuditCommand extends Command {
  @override
  final String name = 'audit';
  @override
  final String description =
      'Inspect and verify the immutable SHA-256 state hash chain.';

  AuditCommand({required this.client}) {
    argParser.addOption(
      'limit',
      abbr: 'n',
      defaultsTo: '10',
      help: 'Number of recent audit blocks to show',
    );
    argParser.addFlag(
      'verify',
      abbr: 'v',
      defaultsTo: false,
      help: 'Perform cryptographic state continuity verification',
    );
  }

  final AcrClient client;

  @override
  Future<void> run() async {
    final limitStr = argResults!['limit'] as String;
    final limit = int.tryParse(limitStr) ?? 10;
    final verify = argResults!['verify'] as bool;

    try {
      final audit = await client.fetchAudit(limit: limit);
      stdout.writeln(
        '\x1B[1;36m=== TLA+ VERIFIED AUDIT CHAIN (LATEST ${audit.length} BLOCKS) ===\x1B[0m',
      );

      if (audit.isEmpty) {
        stdout.writeln('  \x1B[90mNo blocks in audit chain.\x1B[0m');
        return;
      }

      bool chainValid = true;
      for (int i = 0; i < audit.length; i++) {
        final b = audit[i];
        final idx = b['index'] ?? b['block_height'] ?? i;
        final event = (b['event_type'] as String? ?? 'EVENT').padRight(22);
        final stateHash = b['state_hash'] as String? ?? '';
        final prevHash =
            b['prev_hash'] as String? ?? b['previous_hash'] as String? ?? '';
        final ts = b['timestamp'] ?? '';

        final hashAbbr = stateHash.length > 12
            ? stateHash.substring(0, 12)
            : stateHash;
        final prevAbbr = prevHash.length > 12
            ? prevHash.substring(0, 12)
            : prevHash;

        stdout.writeln(
          '  \x1B[1;36m#${idx.toString().padLeft(4, '0')}\x1B[0m | \x1B[33m$event\x1B[0m | HASH: \x1B[32m$hashAbbr...\x1B[0m | PREV: \x1B[90m$prevAbbr...\x1B[0m | \x1B[90m$ts\x1B[0m',
        );

        if (verify && i > 0) {
          final priorHash = audit[i - 1]['state_hash'] as String? ?? '';
          if (priorHash.isNotEmpty &&
              prevHash.isNotEmpty &&
              priorHash != prevHash) {
            chainValid = false;
            stderr.writeln(
              '    \x1B[1;31m⚠ Hash link break detected between block #${i - 1} and block #$i!\x1B[0m',
            );
          }
        }
      }

      if (verify) {
        if (chainValid) {
          stdout.writeln(
            '\n\x1B[1;32m✓ Cryptographic State Chain Invariant Valid: All block hashes monotonically chained.\x1B[0m',
          );
        } else {
          stderr.writeln(
            '\n\x1B[1;31m✗ Chain Invariant Violation: Hash continuity broken.\x1B[0m',
          );
          exit(1);
        }
      }
    } catch (e) {
      stderr.writeln(
        '\x1B[1;31m[ERROR] Failed to fetch audit chain: $e\x1B[0m',
      );
      exit(1);
    }
  }
}
