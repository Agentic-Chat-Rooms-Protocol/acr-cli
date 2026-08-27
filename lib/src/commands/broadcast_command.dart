import 'dart:io';

import 'package:args/command_runner.dart';

import '../api/acr_client.dart';

class BroadcastCommand extends Command {
  @override
  final String name = 'broadcast';
  @override
  final String description =
      'Broadcast operator directive to all registered deliberation rooms.';

  BroadcastCommand({required this.client}) {
    argParser.addOption(
      'message',
      abbr: 'm',
      mandatory: true,
      help: 'Broadcast message content',
    );
  }

  final AcrClient client;

  @override
  Future<void> run() async {
    final message = argResults!['message'] as String;

    try {
      final rooms = await client.fetchRooms();
      int delivered = 0;
      for (final r in rooms) {
        final rId = r['id'] as String;
        try {
          await client.sendMessage(
            roomId: rId,
            content: '[BROADCAST] $message',
          );
          delivered++;
        } catch (_) {}
      }
      stdout.writeln(
        '\x1B[1;32m[OK] Broadcast delivered to $delivered of ${rooms.length} rooms.\x1B[0m',
      );
    } catch (e) {
      stderr.writeln(
        '\x1B[1;31m[ERROR] Failed to execute broadcast: $e\x1B[0m',
      );
      exit(1);
    }
  }
}
