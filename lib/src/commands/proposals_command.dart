import 'dart:io';

import 'package:args/command_runner.dart';

import '../api/acr_client.dart';

class ProposalsCommand extends Command {
  @override
  final String name = 'proposals';
  @override
  final String description =
      'Manage consensus proposals, casting ballots, and recording dissent.';

  ProposalsCommand({required this.client}) {
    addSubcommand(ProposalsListSubcommand(client: client));
    addSubcommand(ProposalsCreateSubcommand(client: client));
    addSubcommand(ProposalsVoteSubcommand(client: client));
    addSubcommand(ProposalsCloseSubcommand(client: client));
  }

  final AcrClient client;

  @override
  Future<void> run() async {
    printUsage();
  }
}

class ProposalsListSubcommand extends Command {
  @override
  final String name = 'list';
  @override
  final String description =
      'List consensus proposals for a deliberation room.';

  ProposalsListSubcommand({required this.client}) {
    argParser.addOption(
      'room',
      abbr: 'r',
      defaultsTo: 'consensus-main',
      help: 'Target room ID',
    );
  }

  final AcrClient client;

  @override
  Future<void> run() async {
    final roomId = argResults!['room'] as String;

    try {
      final proposals = await client.fetchProposals(roomId);
      stdout.writeln(
        '\x1B[1;36m=== ROOM #$roomId CONSENSUS PROPOSALS (${proposals.length}) ===\x1B[0m',
      );
      if (proposals.isEmpty) {
        stdout.writeln('  \x1B[90mNo active proposals.\x1B[0m');
        return;
      }

      for (final p in proposals) {
        final id = p['id'];
        final title = p['title'];
        final status = (p['status'] as String? ?? 'open').toUpperCase();
        final statusColor = status == 'OPEN' ? '\x1B[32m' : '\x1B[90m';
        final votes = p['votes'] as Map<String, dynamic>? ?? {};
        final dissents = p['dissent_logs'] as List<dynamic>? ?? [];

        int approves = 0;
        int rejects = 0;
        int dissentCount = 0;
        for (final v in votes.values) {
          final u = v.toString().toUpperCase();
          if (u == 'APPROVE' || u == 'YES') approves++;
          if (u == 'REJECT' || u == 'NO') rejects++;
          if (u == 'DISSENT') dissentCount++;
        }

        stdout.writeln(
          '  \x1B[1m#$id\x1B[0m $statusColor[$status]\x1B[0m \x1B[1m$title\x1B[0m',
        );
        stdout.writeln(
          '    Tally: \x1B[32mApprove: $approves\x1B[0m | \x1B[31mReject: $rejects\x1B[0m | \x1B[33mDissent: $dissentCount\x1B[0m',
        );

        if (dissents.isNotEmpty) {
          stdout.writeln(
            '    \x1B[33mRecorded Dissents (${dissents.length}):\x1B[0m',
          );
          for (final d in dissents) {
            final voter = d['agent_name'] ?? d['voter_did'] ?? 'Unknown';
            stdout.writeln('      ↳ \x1B[1m$voter:\x1B[0m "${d['rationale']}"');
          }
        }
      }
    } catch (e) {
      stderr.writeln('\x1B[1;31m[ERROR] Failed to list proposals: $e\x1B[0m');
      exit(1);
    }
  }
}

class ProposalsCreateSubcommand extends Command {
  @override
  final String name = 'create';
  @override
  final String description = 'Create a new consensus proposal ballot.';

  ProposalsCreateSubcommand({required this.client}) {
    argParser.addOption(
      'room',
      abbr: 'r',
      defaultsTo: 'consensus-main',
      help: 'Target room ID',
    );
    argParser.addOption(
      'title',
      abbr: 't',
      mandatory: true,
      help: 'Proposal title',
    );
    argParser.addOption(
      'description',
      abbr: 'd',
      defaultsTo: '',
      help: 'Proposal description & scope',
    );
  }

  final AcrClient client;

  @override
  Future<void> run() async {
    final room = argResults!['room'] as String;
    final title = argResults!['title'] as String;
    final desc = argResults!['description'] as String;

    try {
      final res = await client.createProposal(
        roomId: room,
        title: title,
        description: desc,
        proposerDid: 'did:key:z6Mka881...operator',
      );
      stdout.writeln('\x1B[1;32m[OK] Proposal created successfully!\x1B[0m');
      stdout.writeln('  ID:     ${res['id']}');
      stdout.writeln('  Title:  ${res['title']}');
      stdout.writeln('  Status: ${res['status']}');
    } catch (e) {
      stderr.writeln('\x1B[1;31m[ERROR] Failed to create proposal: $e\x1B[0m');
      exit(1);
    }
  }
}

class ProposalsVoteSubcommand extends Command {
  @override
  final String name = 'vote';
  @override
  final String description =
      'Cast ballot on proposal (APPROVE, REJECT, or DISSENT with rationale).';

  ProposalsVoteSubcommand({required this.client}) {
    argParser.addOption(
      'id',
      abbr: 'i',
      mandatory: true,
      help: 'Proposal ID (e.g. prop-101)',
    );
    argParser.addOption(
      'choice',
      abbr: 'c',
      mandatory: true,
      allowed: ['APPROVE', 'REJECT', 'DISSENT'],
      help: 'Ballot choice',
    );
    argParser.addOption(
      'rationale',
      help: 'Required when choice is DISSENT to preserve rationale into audit blocks',
    );
  }

  final AcrClient client;

  @override
  Future<void> run() async {
    final id = argResults!['id'] as String;
    final choice = (argResults!['choice'] as String).toUpperCase();
    final rationale = argResults?['rationale'] as String?;

    if (choice == 'DISSENT' &&
        (rationale == null || rationale.trim().isEmpty)) {
      stderr.writeln(
        '\x1B[1;31m[ERROR] --rationale is mandatory when voting DISSENT (GAP-08 Invariant).\x1B[0m',
      );
      exit(64);
    }

    try {
      final res = await client.castVote(
        proposalId: id,
        voterDid: 'did:key:z6Mka881...operator',
        choice: choice,
        rationale: rationale,
      );
      stdout.writeln(
        '\x1B[1;32m[OK] Ballot cast for Proposal $id: $choice\x1B[0m',
      );
      if (rationale != null) {
        stdout.writeln(
          '  \x1B[33mDissent rationale anchored into state hash chain.\x1B[0m',
        );
      }
      stdout.writeln('  Total Votes: ${(res['votes'] as Map).length}');
    } catch (e) {
      stderr.writeln('\x1B[1;31m[ERROR] Failed to cast vote: $e\x1B[0m');
      exit(1);
    }
  }
}

class ProposalsCloseSubcommand extends Command {
  @override
  final String name = 'close';
  @override
  final String description = 'Finalize consensus and close proposal.';

  ProposalsCloseSubcommand({required this.client}) {
    argParser.addOption(
      'id',
      abbr: 'i',
      mandatory: true,
      help: 'Proposal ID to close',
    );
  }

  final AcrClient client;

  @override
  Future<void> run() async {
    final id = argResults!['id'] as String;

    try {
      final res = await client.closeProposal(
        proposalId: id,
        closerDid: 'did:key:z6Mka881...operator',
      );
      stdout.writeln(
        '\x1B[1;32m[OK] Proposal $id closed with outcome: ${(res['status'] as String).toUpperCase()}\x1B[0m',
      );
    } catch (e) {
      stderr.writeln('\x1B[1;31m[ERROR] Failed to close proposal: $e\x1B[0m');
      exit(1);
    }
  }
}
