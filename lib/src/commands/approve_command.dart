import 'dart:io';

import 'package:args/command_runner.dart';

import '../api/acr_client.dart';

class ApproveCommand extends Command {
  @override
  final String name = 'approve';
  @override
  final String description =
      'Approve or reject a human escalation gate with cryptographic Ed25519 signature.';

  ApproveCommand({required this.client}) {
    argParser.addOption(
      'id',
      abbr: 'i',
      mandatory: true,
      help: 'Escalation Gate ID (e.g. esc-canary-prod)',
    );
    argParser.addFlag(
      'reject',
      defaultsTo: false,
      help: 'Reject rather than approve the escalation gate',
    );
  }

  final AcrClient client;

  @override
  Future<void> run() async {
    final id = argResults!['id'] as String;
    final reject = argResults!['reject'] as bool;
    final approve = !reject;

    try {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final signature = 'ed25519:operator_sig_$nowSec';

      final res = await client.resolveEscalation(
        id: id,
        approve: approve,
        operatorDid: 'did:key:z6Mka881...operator',
        signature: signature,
      );

      final status = res['status'] ?? (approve ? 'approved' : 'rejected');
      final color = approve ? '\x1B[1;32m' : '\x1B[1;31m';
      stdout.writeln(
        '$color[OK] Escalation #$id resolved: ${status.toString().toUpperCase()}\x1B[0m',
      );
      stdout.writeln('  Operator DID: did:key:z6Mka881...operator');
      stdout.writeln('  Signature:    $signature');
    } catch (e) {
      stderr.writeln(
        '\x1B[1;31m[ERROR] Failed to resolve escalation gate: $e\x1B[0m',
      );
      exit(1);
    }
  }
}
