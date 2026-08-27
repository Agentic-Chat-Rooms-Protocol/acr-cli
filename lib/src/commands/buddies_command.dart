import 'dart:io';

import 'package:args/command_runner.dart';

import '../api/acr_client.dart';

class BuddiesCommand extends Command {
  @override
  final String name = 'buddies';
  @override
  final String description =
      'Manage agent buddy relationships, friend requests, and blocking (GAP-02).';

  BuddiesCommand({required this.client}) {
    addSubcommand(BuddiesListSubcommand(client: client));
    addSubcommand(BuddiesActionSubcommand(action: 'request', client: client));
    addSubcommand(BuddiesActionSubcommand(action: 'accept', client: client));
    addSubcommand(BuddiesActionSubcommand(action: 'block', client: client));
  }

  final AcrClient client;

  @override
  Future<void> run() async {
    printUsage();
  }
}

class BuddiesListSubcommand extends Command {
  @override
  final String name = 'list';
  @override
  final String description =
      'List all buddies and status for the current operator.';

  BuddiesListSubcommand({required this.client});
  final AcrClient client;

  @override
  Future<void> run() async {
    try {
      final buddies = await client.fetchBuddies('did:key:z6Mka881...operator');
      stdout.writeln(
        '\x1B[1;36m=== OPERATOR BUDDY ROSTER (${buddies.length}) ===\x1B[0m',
      );
      if (buddies.isEmpty) {
        stdout.writeln('  \x1B[90mNo buddy relationships established.\x1B[0m');
        return;
      }
      for (final b in buddies) {
        final to = b['to_did'] ?? '';
        final status = (b['status'] as String? ?? 'pending').toUpperCase();
        final color = status == 'ACCEPTED'
            ? '\x1B[32m'
            : (status == 'BLOCKED' ? '\x1B[31m' : '\x1B[33m');
        stdout.writeln('  -> \x1B[1m$to\x1B[0m $color[$status]\x1B[0m');
      }
    } catch (e) {
      stderr.writeln('\x1B[1;31m[ERROR] Failed to fetch buddies: $e\x1B[0m');
      exit(1);
    }
  }
}

class BuddiesActionSubcommand extends Command {
  BuddiesActionSubcommand({required this.action, required this.client}) {
    argParser.addOption(
      'to',
      abbr: 't',
      mandatory: true,
      help: 'Target agent DID (e.g. did:key:z6Mkq5Xv...claude)',
    );
  }

  final String action;
  final AcrClient client;

  @override
  String get name => action;

  @override
  String get description =>
      '$action a buddy relationship with target agent DID.';

  @override
  Future<void> run() async {
    final toDid = argResults!['to'] as String;

    try {
      final res = await client.updateBuddy(
        action: action,
        fromDid: 'did:key:z6Mka881...operator',
        toDid: toDid,
      );
      stdout.writeln(
        '\x1B[1;32m[OK] Buddy $action completed: ${res['status']}\x1B[0m',
      );
      stdout.writeln('  Target DID: $toDid');
    } catch (e) {
      stderr.writeln('\x1B[1;31m[ERROR] Failed to $action buddy: $e\x1B[0m');
      exit(1);
    }
  }
}
