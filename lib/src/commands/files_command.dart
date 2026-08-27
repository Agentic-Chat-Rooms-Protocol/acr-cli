import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../api/acr_client.dart';

class FilesCommand extends Command {
  @override
  final String name = 'files';
  @override
  final String description =
      'Manage object store file uploads, downloads, and inspection (GAP-17).';

  FilesCommand({required this.client}) {
    addSubcommand(FilesUploadSubcommand(client: client));
    addSubcommand(FilesDownloadSubcommand(client: client));
    addSubcommand(FilesCatSubcommand(client: client));
  }

  final AcrClient client;

  @override
  Future<void> run() async {
    printUsage();
  }
}

class FilesUploadSubcommand extends Command {
  @override
  final String name = 'upload';
  @override
  final String description = 'Upload a local file to ACR object store.';

  FilesUploadSubcommand({required this.client}) {
    argParser.addOption(
      'path',
      abbr: 'p',
      mandatory: true,
      help: 'Local file path to upload',
    );
    argParser.addOption(
      'mime',
      abbr: 'm',
      help: 'MIME type override (defaults to detected or octet-stream)',
    );
  }

  final AcrClient client;

  @override
  Future<void> run() async {
    final path = argResults!['path'] as String;
    final mime = argResults?['mime'] as String?;

    try {
      final res = await client.uploadFile(path, mimeType: mime);
      stdout.writeln('\x1B[1;32m[OK] File uploaded successfully!\x1B[0m');
      stdout.writeln('  File ID:    ${res['id']}');
      stdout.writeln('  Filename:   ${res['filename']}');
      stdout.writeln('  Size:       ${res['size']} bytes');
      stdout.writeln('  MIME Type:  ${res['mime_type']}');
      stdout.writeln('  URL:        ${res['url']}');
    } catch (e) {
      stderr.writeln('\x1B[1;31m[ERROR] Failed to upload file: $e\x1B[0m');
      exit(1);
    }
  }
}

class FilesDownloadSubcommand extends Command {
  @override
  final String name = 'download';
  @override
  final String description = 'Download a file from ACR object store.';

  FilesDownloadSubcommand({required this.client}) {
    argParser.addOption(
      'id',
      abbr: 'i',
      mandatory: true,
      help: 'File ID to download',
    );
    argParser.addOption(
      'out',
      abbr: 'o',
      mandatory: true,
      help: 'Destination file path',
    );
  }

  final AcrClient client;

  @override
  Future<void> run() async {
    final id = argResults!['id'] as String;
    final outPath = argResults!['out'] as String;

    try {
      final bytes = await client.downloadFile(id);
      final outFile = File(outPath);
      await outFile.writeAsBytes(bytes);
      stdout.writeln(
        '\x1B[1;32m[OK] Downloaded file $id to $outPath (${bytes.length} bytes)\x1B[0m',
      );
    } catch (e) {
      stderr.writeln('\x1B[1;31m[ERROR] Failed to download file: $e\x1B[0m');
      exit(1);
    }
  }
}

class FilesCatSubcommand extends Command {
  @override
  final String name = 'cat';
  @override
  final String description = 'Print file contents directly to standard output.';

  FilesCatSubcommand({required this.client}) {
    argParser.addOption(
      'id',
      abbr: 'i',
      mandatory: true,
      help: 'File ID to inspect',
    );
  }

  final AcrClient client;

  @override
  Future<void> run() async {
    final id = argResults!['id'] as String;

    try {
      final bytes = await client.downloadFile(id);
      stdout.writeln(utf8.decode(bytes, allowMalformed: true));
    } catch (e) {
      stderr.writeln('\x1B[1;31m[ERROR] Failed to cat file: $e\x1B[0m');
      exit(1);
    }
  }
}
