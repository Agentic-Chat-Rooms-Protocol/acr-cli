import 'dart:convert';
import 'dart:io';
import 'package:acr_cli/src/api/acr_client.dart';
import 'package:test/test.dart';

void main() {
  group('ACR Dart Native CLI Integration Tests', () {
    late HttpServer mockDaemon;
    late String baseUrl;
    const String testToken = 'test-local-daemon-token-20443';
    bool enableCors = true;
    bool enablePna = true;

    setUpAll(() async {
      mockDaemon = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUrl = 'http://127.0.0.1:${mockDaemon.port}';

      mockDaemon.listen((HttpRequest req) async {
        final path = req.uri.path;
        final isPublic = path == '/api/v1/health' || path == '/health';

        if (!isPublic &&
            req.headers.value(HttpHeaders.authorizationHeader) !=
                'Bearer $testToken') {
          req.response.statusCode = HttpStatus.unauthorized;
          req.response.write('unauthorized');
          await req.response.close();
          return;
        }

        req.response.headers.contentType = ContentType.json;
        if (path == '/api/v1/health') {
          req.response.statusCode = HttpStatus.ok;
          req.response.write(
            jsonEncode({
              'status': 'healthy',
              'mesh_latency_ms': 0.25,
              'uptime': '1m',
              'audit_chain_depth': 2,
            }),
          );
        } else if (path == '/api/v1/rooms') {
          req.response.statusCode = HttpStatus.ok;
          req.response.write(
            jsonEncode([
              {
                'id': 'consensus-main',
                'name': 'Consensus Main',
                'topic': 'Byzantine Deliberation',
                'is_private': false,
                'message_count': 1,
              },
            ]),
          );
        } else if (path == '/api/v1/proposals') {
          req.response.statusCode = HttpStatus.ok;
          req.response.write(
            jsonEncode([
              {
                'id': 'prop-1',
                'room_id': 'consensus-main',
                'title': 'Enforce Loopback Auth',
                'status': 'open',
                'votes': <String, dynamic>{},
                'dissent_logs': <dynamic>[],
              },
            ]),
          );
        } else if (path == '/api/v1/audit' || path == '/api/v1/audit/chain') {
          req.response.statusCode = HttpStatus.ok;
          req.response.write(
            jsonEncode({
              'trail': [
                {
                  'index': 0,
                  'event_type': 'GENESIS',
                  'prev_hash': '',
                  'state_hash': 'hash_0',
                  'timestamp': '2026-11-18T00:00:00Z',
                },
                {
                  'index': 1,
                  'event_type': 'ROOM_CREATED',
                  'prev_hash': 'hash_0',
                  'state_hash': 'hash_1',
                  'timestamp': '2026-11-18T00:00:01Z',
                },
              ],
            }),
          );
        } else if (path == '/api/v1/config/security') {
          if (req.method == 'POST') {
            final raw = await utf8.decoder.bind(req).join();
            final body = jsonDecode(raw) as Map<String, dynamic>;
            if (body['enable_cors'] is bool) {
              enableCors = body['enable_cors'] as bool;
            }
            if (body['enable_pna'] is bool) {
              enablePna = body['enable_pna'] as bool;
            }
          }
          req.response.statusCode = HttpStatus.ok;
          req.response.write(
            jsonEncode({
              'enable_cors': enableCors,
              'enable_pna': enablePna,
              'cors_status': enableCors ? 'active' : 'disabled',
              'pna_status': enablePna ? 'active' : 'disabled',
              'version': 'v1.0.0',
            }),
          );
        } else {
          req.response.statusCode = HttpStatus.notFound;
          req.response.write(jsonEncode({'error': 'not found'}));
        }
        await req.response.close();
      });
    });

    tearDownAll(() async {
      await mockDaemon.close(force: true);
    });

    test('Displays usage help text with all registered commands', () async {
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
      expect(out, contains('mcp'));
      expect(out, contains('login'));
      expect(out, contains('logout'));
    });

    test('Prints version flag correctly', () async {
      final res = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/acr.dart', '--version'],
      );

      expect(res.exitCode, equals(0));
      expect(res.stdout.toString(), contains('1.0.0'));
    });

    test('Rejects dissent voting without rationale with exit code 64', () async {
      final res = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/acr.dart', 'proposals', 'vote', '-i', 'prop-test', '-c', 'DISSENT'],
      );

      expect(res.exitCode, equals(64));
      expect(res.stderr.toString(), contains('--rationale is mandatory when voting DISSENT'));
    });

    test('Rejects insecure non-HTTPS tunnel cloud-url with exit code 64', () async {
      final res = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/acr.dart', 'tunnel', '--cloud-url', 'http://143.198.98.229:20443'],
      );

      expect(res.exitCode, equals(64));
      expect(res.stderr.toString(), contains('HTTPS URL'));
      expect(res.stdout.toString(), isNot(contains('[OK]')));
    });

    test('Queries live ACR daemon health successfully', () async {
      final res = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/acr.dart', 'health'],
        environment: {'ACR_DAEMON_URL': baseUrl, 'ACR_API_TOKEN': testToken},
      );

      expect(res.exitCode, equals(0));
      final out = res.stdout.toString();
      expect(out, contains('HEALTH STATUS: HEALTHY'));
      expect(out, contains('Audit Chain Depth:'));
    });

    test('Lists registered deliberation rooms with Bearer auth', () async {
      final res = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/acr.dart', 'rooms', 'list'],
        environment: {'ACR_DAEMON_URL': baseUrl, 'ACR_API_TOKEN': testToken},
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
        environment: {'ACR_DAEMON_URL': baseUrl, 'ACR_API_TOKEN': testToken},
      );

      expect(res.exitCode, equals(0));
      final out = res.stdout.toString();
      expect(out, contains('CONSENSUS PROPOSALS'));
    });

    test('Verifies cryptographic audit chain continuity', () async {
      final res = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/acr.dart', 'audit', '--verify'],
        environment: {'ACR_DAEMON_URL': baseUrl, 'ACR_API_TOKEN': testToken},
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
      final client = AcrClient(baseUrl: baseUrl, apiToken: testToken);
      final res = await client.verifyAuditChain();
      expect(res['is_valid'], isTrue);
    });

    test('Queries and updates security config via AcrClient', () async {
      final client = AcrClient(baseUrl: baseUrl, apiToken: testToken);
      final config = await client.fetchSecurityConfig();
      expect(config.containsKey('enable_cors'), isTrue);
      expect(config.containsKey('enable_pna'), isTrue);

      final updated = await client.updateSecurityConfig(enableCors: true, enablePna: true);
      expect(updated['enable_cors'], isTrue);
      expect(updated['enable_pna'], isTrue);
    });
  });
}
