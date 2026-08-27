import 'dart:io';

import 'package:args/command_runner.dart';

import '../api/acr_client.dart';

class RoomsCommand extends Command {
  @override
  final String name = 'rooms';
  @override
  final String description =
      'Manage deliberation rooms (list, create with private ACLs).';

  RoomsCommand({required this.client}) {
    addSubcommand(RoomsListSubcommand(client: client));
    addSubcommand(RoomsCreateSubcommand(client: client));
  }

  final AcrClient client;

  @override
  Future<void> run() async {
    printUsage();
  }
}

class RoomsListSubcommand extends Command {
  @override
  final String name = 'list';
  @override
  final String description = 'List all registered deliberation rooms.';

  RoomsListSubcommand({required this.client});
  final AcrClient client;

  @override
  Future<void> run() async {
    try {
      final rooms = await client.fetchRooms();
      stdout.writeln(
        '\x1B[1;36m=== ACTIVE DELIBERATION ROOMS (${rooms.length}) ===\x1B[0m',
      );
      for (final r in rooms) {
        final id = r['id'] as String? ?? '';
        final isPriv = r['is_private'] == true;
        final privTag = isPriv
            ? '\x1B[33m[PRIVATE]\x1B[0m'
            : '\x1B[32m[PUBLIC] \x1B[0m';
        final name = r['name'] as String? ?? '';
        final msgs = r['message_count'] ?? 0;
        final topic = r['topic'] as String? ?? '';
        stdout.writeln(
          '  #${id.padRight(20)} $privTag $name — \x1B[36m$topic\x1B[0m ($msgs msgs)',
        );
      }
    } catch (e) {
      stderr.writeln('\x1B[1;31m[ERROR] Failed to fetch rooms: $e\x1B[0m');
      exit(1);
    }
  }
}

class RoomsCreateSubcommand extends Command {
  @override
  final String name = 'create';
  @override
  final String description = 'Create a new deliberation room.';

  RoomsCreateSubcommand({required this.client}) {
    argParser.addOption(
      'name',
      abbr: 'n',
      mandatory: true,
      help: 'Room display name',
    );
    argParser.addOption(
      'description',
      abbr: 'd',
      defaultsTo: 'Custom deliberation channel',
      help: 'Room description',
    );
    argParser.addOption(
      'topic',
      abbr: 't',
      defaultsTo: 'General Deliberation',
      help: 'Room consensus topic',
    );
    argParser.addFlag(
      'private',
      defaultsTo: false,
      help: 'Restrict room to authorized participants (ACL)',
    );
  }

  final AcrClient client;

  @override
  Future<void> run() async {
    final name = argResults!['name'] as String;
    final desc = argResults!['description'] as String;
    final topic = argResults!['topic'] as String;
    final isPrivate = argResults!['private'] as bool;

    try {
      final res = await client.createRoom(
        name: name,
        description: desc,
        topic: topic,
        isPrivate: isPrivate,
      );
      stdout.writeln('\x1B[1;32m[OK] Room created successfully!\x1B[0m');
      stdout.writeln('  ID:       #${res['id']}');
      stdout.writeln('  Name:     ${res['name']}');
      stdout.writeln('  Topic:    ${res['topic']}');
      stdout.writeln('  Private:  ${res['is_private']}');
    } catch (e) {
      stderr.writeln('\x1B[1;31m[ERROR] Failed to create room: $e\x1B[0m');
      exit(1);
    }
  }
}
