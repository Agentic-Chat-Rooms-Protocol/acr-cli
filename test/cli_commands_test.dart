import 'dart:io';
import 'package:acr_cli/src/api/acr_client.dart';
import 'package:test/test.dart';

void main() {
  group('ACR Dart Native CLI Integration Tests', () {
    test('Displays usage help text with all 10 registered commands', () async {
      final res = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/acr.dart', '--help'],
      );

      expect(res.exitCode, equals(0));
      final out = res.stdout.toString();
      expect(out, contains('Agentic Chat Rooms (ACR) Protocol'));
      expect(out, contains('status'));
      expect(out, contains('health'));
      expect(out, contains('rooms'));
      expect(out, contains('send'));
      expect(out, contains('broadcast'));
      expect(out, contains('proposals'));
      expect(out, contains('files'));
      expect(out, contains('buddies'));
      expect(out, contains('approve'));
      expect(out, contains('audit'));
      expect(out, contains('config'));
      expect(out, contains('tunnel'));
      expect(out, contains('opsroom'));
    });

    test('Prints version flag correctly', () async {
      final res = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/acr.dart', '--version'],
      );

      expect(res.exitCode, equals(0));
      expect(res.stdout.toString(), contains('0.9.0'));
    });

    test('Rejects dissent voting without rationale with exit code 64', () async {
      final res = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/acr.dart', 'proposals', 'vote', '-i', 'prop-test', '-c', 'DISSENT'],
      );

      expect(res.exitCode, equals(64));
      expect(res.stderr.toString(), contains('--rationale is mandatory when voting DISSENT'));
    });

    test('Queries live ACR daemon health successfully', () async {
      final res = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/acr.dart', 'health'],
      );

      expect(res.exitCode, equals(0));
      final out = res.stdout.toString();
      expect(out, contains('HEALTH STATUS: HEALTHY'));
      expect(out, contains('Audit Chain Depth:'));
    });

    test('Lists registered deliberation rooms', () async {
      final res = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/acr.dart', 'rooms', 'list'],
      );

      expect(res.exitCode, equals(0));
      final out = res.stdout.toString();
      expect(out, contains('ACTIVE DELIBERATION ROOMS'));
      expect(out, contains('#consensus-main'));
    });

    test('Lists consensus proposals in active room', () async {
      final res = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/acr.dart', 'proposals', 'list', '-r', 'consensus-main'],
      );

      expect(res.exitCode, equals(0));
      final out = res.stdout.toString();
      expect(out, contains('CONSENSUS PROPOSALS'));
    });

    test('Verifies cryptographic audit chain continuity', () async {
      final res = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/acr.dart', 'audit', '--verify'],
      );

      expect(res.exitCode, equals(0));
      final out = res.stdout.toString();
      expect(out, contains('TLA+ VERIFIED AUDIT CHAIN'));
      expect(out, contains('Cryptographic State Chain Invariant Valid'));
    });

    test('AcrClient client-side validation rejects DISSENT without rationale before HTTP', () async {
      final client = AcrClient();
      expect(
        () => client.castVote(
          proposalId: 'prop-1',
          voterDid: 'did:key:test',
          choice: 'DISSENT',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('AcrClient client-side validation rejects empty room name', () async {
      final client = AcrClient();
      expect(
        () => client.createRoom(
          name: '   ',
          description: '',
          topic: '',
          isPrivate: false,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('AcrClient verifyAuditChain recomputes continuity successfully', () async {
      final client = AcrClient();
      final res = await client.verifyAuditChain();
      expect(res['is_valid'], isTrue);
    });

    test('Queries and updates security config via AcrClient', () async {
      final client = AcrClient();
      final config = await client.fetchSecurityConfig();
      expect(config.containsKey('enable_cors'), isTrue);
      expect(config.containsKey('enable_pna'), isTrue);

      final updated = await client.updateSecurityConfig(enableCors: true, enablePna: true);
      expect(updated['enable_cors'], isTrue);
      expect(updated['enable_pna'], isTrue);
    });
  });
}
