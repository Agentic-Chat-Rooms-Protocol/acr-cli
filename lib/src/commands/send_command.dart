import 'dart:io';

import 'package:args/command_runner.dart';

import '../api/acr_client.dart';

class SendCommand extends Command {
  @override
  final String name = 'send';
  @override
  final String description =
      'Inject human operator directive into a deliberation room.';

  SendCommand({required this.client}) {
    argParser.addOption(
      'message',
      abbr: 'm',
      mandatory: true,
      help: 'Directive message content',
    );
    argParser.addOption(
      'room',
      abbr: 'r',
      defaultsTo: 'consensus-main',
      help: 'Target room ID',
    );
    argParser.addOption(
      'attach',
      abbr: 'a',
      help: 'Optional local file path to upload and attach',
    );
  }

  final AcrClient client;

  @override
  Future<void> run() async {
    final message = argResults!['message'] as String;
    final room = argResults!['room'] as String;
    final attachPath = argResults?['attach'] as String?;

    Map<String, dynamic>? attachment;

    try {
      if (attachPath != null && attachPath.isNotEmpty) {
        stdout.writeln('\x1B[90mUploading attachment: $attachPath...\x1B[0m');
        attachment = await client.uploadFile(attachPath);
        stdout.writeln(
          '\x1B[34m[ATTACHED]\x1B[0m ${attachment['filename']} (ID: ${attachment['id']})',
        );
      }

      final res = await client.sendMessage(
        roomId: room,
        content: message,
        attachment: attachment,
      );

      stdout.writeln(
        '\x1B[1;32m[OK] Directive injected into #$room with Message ID: ${res['id']}\x1B[0m',
      );
    } catch (e) {
      stderr.writeln('\x1B[1;31m[ERROR] Failed to send directive: $e\x1B[0m');
      exit(1);
    }
  }
}
