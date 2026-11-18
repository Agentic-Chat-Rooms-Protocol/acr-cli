import 'dart:convert';
import 'dart:io';

import 'package:acr_cli/acr_cli.dart';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('Shared endpoint-vectors.json compliance', () {
    final fixtureFile = File('test/fixtures/endpoint-vectors.json');
    final vectors =
        jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;

    test(
      'matches pinned remoteUrl, defaultLocalUrl, and Clerk OAuth contract',
      () {
        expect(McpEndpoint.remoteUrl, equals(vectors['remoteUrl']));
        expect(McpEndpoint.defaultLocalUrl, equals(vectors['defaultLocalUrl']));
        final oauth = vectors['oauth'] as Map<String, dynamic>;
        expect(McpEndpoint.clerkIssuer, equals(oauth['issuer']));
        expect(
          McpEndpoint.requiredOAuthScopes,
          equals(List<String>.from(oauth['scopesSupported'] as List)),
        );
      },
    );

    test('passes all validateLocal vectors from endpoint-vectors.json', () {
      final cases = vectors['validateLocal'] as List<dynamic>;
      for (final rawCase in cases) {
        final c = rawCase as Map<String, dynamic>;
        final name = c['name'] as String;
        final input = c['input'] as String;
        final valid = c['valid'] as bool;
        if (valid) {
          expect(
            McpEndpoint.validateLocal(input),
            equals(c['normalized']),
            reason: 'validateLocal vector "$name" failed',
          );
        } else {
          expect(
            () => McpEndpoint.validateLocal(input),
            throwsFormatException,
            reason: 'validateLocal vector "$name" should reject $input',
          );
        }
      }
    });

    test('passes all validateRemote vectors from endpoint-vectors.json', () {
      final cases = vectors['validateRemote'] as List<dynamic>;
      for (final rawCase in cases) {
        final c = rawCase as Map<String, dynamic>;
        final name = c['name'] as String;
        final input = c['input'] as String;
        final valid = c['valid'] as bool;
        if (valid) {
          expect(
            () => McpEndpoint.validateRemote(input),
            returnsNormally,
            reason: 'validateRemote vector "$name" failed',
          );
        } else {
          expect(
            () => McpEndpoint.validateRemote(input),
            throwsFormatException,
            reason: 'validateRemote vector "$name" should reject $input',
          );
        }
      }
    });

    test('passes all resolveMode vectors from endpoint-vectors.json', () {
      final cases = vectors['resolveMode'] as List<dynamic>;
      for (final rawCase in cases) {
        final c = rawCase as Map<String, dynamic>;
        final name = c['name'] as String;
        final override = c['override'] as String;
        final entitlement = c['entitlement'] as String;
        final localUrl = c['localUrl'] as String;
        final expectError = c['expectError'] as bool;
        if (expectError) {
          expect(
            () => McpEndpoint.resolve(
              override: override,
              entitlement: entitlement,
              localUrl: localUrl,
              environment: const {},
            ),
            throwsA(anyOf(isA<FormatException>(), isA<ArgumentError>())),
            reason: 'resolveMode vector "$name" should throw',
          );
        } else {
          final res = McpEndpoint.resolve(
            override: override,
            entitlement: entitlement,
            localUrl: localUrl,
            environment: const {},
          );
          expect(
            res.mode.name,
            equals(c['expectMode']),
            reason: 'resolveMode vector "$name" mode mismatch',
          );
          expect(
            res.url,
            equals(c['expectUrl']),
            reason: 'resolveMode vector "$name" url mismatch',
          );
        }
      }
    });
  });

  group('McpEndpoint URL validation', () {
    test('validateRemote accepts pinned remote URL variants and rejects lookalikes', () {
      expect(
        () => McpEndpoint.validateRemote('https://mcp.agentchatrooms.dev/mcp'),
        returnsNormally,
      );
      expect(
        () => McpEndpoint.validateRemote('https://MCP.AgentChatRooms.DEV/mcp'),
        returnsNormally,
      );
      expect(
        () => McpEndpoint.validateRemote(
          'https://mcp.agentchatrooms.dev:443/mcp',
        ),
        returnsNormally,
      );

      const badRemote = [
        'http://mcp.agentchatrooms.dev/mcp',
        'https://mcp.agentchatrooms.dev.evil.com/mcp',
        'https://mcp.agentchatrooms.dev./mcp',
        'https://mcp.agentchatrooms.dev@evil.com/mcp',
        'https://user:pw@mcp.agentchatrooms.dev/mcp',
        'https://mcp.agentchatrooms.dev:8443/mcp',
        'https://mcp.agentchatrooms.dev/mcp/',
        'https://mcp.agentchatrooms.dev/%6dcp',
        'https://mcp.agentchatrooms.dev/mcp?next=//evil.com',
        'https://mcp.agentchatrooms.dev/mcp#frag',
        '//mcp.agentchatrooms.dev/mcp',
        ' https://mcp.agentchatrooms.dev/mcp',
        '',
      ];
      for (final raw in badRemote) {
        expect(
          () => McpEndpoint.validateRemote(raw),
          throwsFormatException,
          reason: 'Should reject remote URL: $raw',
        );
      }
    });

    test('validateLocal pins localhost to 127.0.0.1 and rejects hostile local forms', () {
      expect(
        McpEndpoint.validateLocal('http://127.0.0.1:20443'),
        equals('http://127.0.0.1:20443'),
      );
      expect(
        McpEndpoint.validateLocal('http://localhost:20443'),
        equals('http://127.0.0.1:20443'),
      );
      expect(
        McpEndpoint.validateLocal('http://localhost'),
        equals('http://127.0.0.1:20443'),
      );
      expect(
        McpEndpoint.validateLocal('http://localhost:20499/'),
        equals('http://127.0.0.1:20499'),
      );
      expect(
        McpEndpoint.validateLocal('http://127.0.0.1:29443/'),
        equals('http://127.0.0.1:29443'),
      );
      expect(
        McpEndpoint.validateLocal('http://[::1]:20443'),
        equals('http://[::1]:20443'),
      );
      expect(
        McpEndpoint.validateLocal('http://[::1]'),
        equals('http://[::1]:20443'),
      );

      const badLocal = [
        'https://127.0.0.1:20443',
        'http://0.0.0.0:20443',
        'http://192.168.1.5:20443',
        'http://localhost.evil.com:20443',
        'http://localhost.:20443',
        'http://127.0.0.1.evil.com:20443',
        'http://2130706433:20443',
        'http://0x7f.0.0.1:20443',
        'http://127.1:20443',
        'http://[::ffff:127.0.0.1]:20443',
        'http://user:pw@127.0.0.1:20443',
        'http://127.0.0.1:20443/api',
        'http://127.0.0.1:20443?next=//evil.com',
        'http://127.0.0.1:20443#frag',
        'http://127.0.0.1:80',
        'http://127.0.0.1:65536',
        '',
      ];
      for (final raw in badLocal) {
        expect(
          () => McpEndpoint.validateLocal(raw),
          throwsFormatException,
          reason: 'Should reject local URL: $raw',
        );
      }
    });
  });

  group('McpEndpoint resolution & Clerk OAuth scopes', () {
    test('uses Clerk OAuth scopes ["profile", "email"] and ignores legacy acr:* scopes', () {
      final noCreds = McpEndpoint.resolve(environment: const {});
      expect(noCreds.mode, equals(McpMode.local));
      expect(noCreds.url, equals('http://127.0.0.1:20443'));

      final legacyScopes = McpEndpoint.resolve(
        grantedScopes: const ['acr:rooms', 'acr:cloud:pro'],
        environment: const {},
      );
      expect(legacyScopes.mode, equals(McpMode.local));

      final partialScope = McpEndpoint.resolve(
        grantedScopes: const ['profile'],
        environment: const {},
      );
      expect(partialScope.mode, equals(McpMode.local));

      final clerkScopes = McpEndpoint.resolve(
        grantedScopes: const ['profile', 'email'],
        environment: const {},
      );
      expect(clerkScopes.mode, equals(McpMode.remote));
      expect(clerkScopes.url, equals('https://mcp.agentchatrooms.dev/mcp'));
    });

    test(
      'honors local/remote mode overrides and always validates local URL',
      () {
        final forcedLocal = McpEndpoint.resolve(
          override: 'local',
          grantedScopes: const ['profile', 'email'],
          environment: const {},
        );
        expect(forcedLocal.mode, equals(McpMode.local));

        final forcedRemote = McpEndpoint.resolve(
          override: 'remote',
          grantedScopes: const [],
          environment: const {},
        );
        expect(forcedRemote.mode, equals(McpMode.remote));
        expect(forcedRemote.url, equals('https://mcp.agentchatrooms.dev/mcp'));

        expect(
          () => McpEndpoint.resolve(override: 'cloud', environment: const {}),
          throwsArgumentError,
        );
        expect(
          () => McpEndpoint.resolve(
            override: 'remote',
            localUrl: 'http://0.0.0.0:20443',
            environment: const {},
          ),
          throwsFormatException,
        );
      },
    );

    test('follows local URL precedence: arg > ACR_DAEMON_URL > ~/.acr/ports.json > default', () {
      final tempHome = Directory.systemTemp.createTempSync('acr_ports_test_');
      try {
        final acrDir = Directory(
          '${tempHome.path}${Platform.pathSeparator}.acr',
        )..createSync(recursive: true);
        File('${acrDir.path}${Platform.pathSeparator}ports.json')
            .writeAsStringSync(
              jsonEncode({
                'ports': {'acr-core': 21443},
              }),
            );

        final fromPorts = McpEndpoint.resolve(
          environment: const {},
          homeDir: tempHome.path,
        );
        expect(fromPorts.url, equals('http://127.0.0.1:21443'));

        final fromEnv = McpEndpoint.resolve(
          environment: {'ACR_DAEMON_URL': 'http://localhost:22443'},
          homeDir: tempHome.path,
        );
        expect(fromEnv.url, equals('http://127.0.0.1:22443'));

        final fromArg = McpEndpoint.resolve(
          localUrl: 'http://[::1]:23443',
          environment: {'ACR_DAEMON_URL': 'http://localhost:22443'},
          homeDir: tempHome.path,
        );
        expect(fromArg.url, equals('http://[::1]:23443'));
      } finally {
        tempHome.deleteSync(recursive: true);
      }
    });
  });

  group('CLI login/logout/mcp commands', () {
    test(
      'acr login, mcp status, mcp install, and logout work with non-secret metadata',
      timeout: const Timeout(Duration(seconds: 120)),
      () async {
        final tempHome = Directory.systemTemp.createTempSync(
          'acr_mcp_cmd_test_',
        );
        try {
          final configPath =
              '${tempHome.path}${Platform.pathSeparator}claude_config.json';

          // Reject legacy scopes
          final badLogin = await Process.run(Platform.resolvedExecutable, [
            'run',
            'bin/acr.dart',
            'login',
            '--scopes',
            'acr:rooms acr:cloud:pro',
          ]);
          expect(badLogin.exitCode, equals(64));

          // Login dry-run with Clerk scopes
          final loginRes = await Process.run(Platform.resolvedExecutable, [
            'run',
            'bin/acr.dart',
            'login',
            '--dry-run',
            '--home-dir',
            tempHome.path,
          ]);
          expect(loginRes.exitCode, equals(0));
          expect(
            loginRes.stdout.toString(),
            contains('https://clerk.agentchatrooms.dev'),
          );
          expect(loginRes.stdout.toString(), contains('profile email'));

          // Record session metadata (without --dry-run, using offline-safe fallback)
          McpEndpoint.saveSession(
            McpSessionMetadata(
              scopes: const ['profile', 'email'],
              issuer: McpEndpoint.clerkIssuer,
              resource: McpEndpoint.remoteUrl,
              checkedAt: DateTime.now().toUtc(),
            ),
            homeDir: tempHome.path,
          );

          // mcp status reflects remote mode without printing any token
          final statusRes = await Process.run(
            Platform.resolvedExecutable,
            [
              'run',
              'bin/acr.dart',
              'mcp',
              'status',
              '--home-dir',
              tempHome.path,
            ],
            environment: {'ACR_API_TOKEN': 'super-secret-canary-value'},
          );
          expect(statusRes.exitCode, equals(0));
          expect(statusRes.stdout.toString(), contains('REMOTE'));
          expect(
            statusRes.stdout.toString(),
            contains('https://mcp.agentchatrooms.dev/mcp'),
          );
          expect(
            statusRes.stdout.toString(),
            isNot(contains('super-secret-canary-value')),
          );

          // mcp install registers both acr and acr-remote with no secrets
          final installRemote = await Process.run(Platform.resolvedExecutable, [
            'run',
            'bin/acr.dart',
            'mcp',
            'install',
            '--client',
            'claude-code',
            '--config-path',
            configPath,
            '--home-dir',
            tempHome.path,
          ]);
          expect(installRemote.exitCode, equals(0));
          final installedJson = jsonDecode(
            File(configPath).readAsStringSync(),
          ) as Map<String, dynamic>;
          final servers = installedJson['mcpServers'] as Map<String, dynamic>;
          expect(servers.containsKey('acr'), isTrue);
          expect(servers.containsKey('acr-remote'), isTrue);
          expect(
            (servers['acr-remote'] as Map<String, dynamic>)['url'],
            equals('https://mcp.agentchatrooms.dev/mcp'),
          );

          // Logout clears session and mcp install removes acr-remote on downgrade
          final logoutRes = await Process.run(Platform.resolvedExecutable, [
            'run',
            'bin/acr.dart',
            'logout',
            '--home-dir',
            tempHome.path,
          ]);
          expect(logoutRes.exitCode, equals(0));

          final installLocal = await Process.run(Platform.resolvedExecutable, [
            'run',
            'bin/acr.dart',
            'mcp',
            'install',
            '--client',
            'claude-code',
            '--config-path',
            configPath,
            '--home-dir',
            tempHome.path,
          ]);
          expect(installLocal.exitCode, equals(0));
          final downgradedJson = jsonDecode(
            File(configPath).readAsStringSync(),
          ) as Map<String, dynamic>;
          final downgradedServers =
              downgradedJson['mcpServers'] as Map<String, dynamic>;
          expect(downgradedServers.containsKey('acr'), isTrue);
          expect(downgradedServers.containsKey('acr-remote'), isFalse);
        } finally {
          tempHome.deleteSync(recursive: true);
        }
      },
    );

    test('LoginCommand blocks RFC 9728 redirects and resource mismatches without saving session', () async {
      final tempHome = Directory.systemTemp.createTempSync('acr_login_sec_');
      try {
        final redirectClient = MockClient((req) async {
          expect(req.followRedirects, isFalse);
          expect(req.maxRedirects, equals(0));
          return http.Response(
            '',
            302,
            headers: {'location': 'https://evil.example/metadata'},
          );
        });
        final runnerRedirect = CommandRunner('acr', 'test')
          ..addCommand(LoginCommand(httpClient: redirectClient));
        final redirectExit = await runnerRedirect.run([
          'login',
          '--home-dir',
          tempHome.path,
        ]);
        expect(redirectExit, isNot(equals(0)));
        expect(McpEndpoint.loadSession(homeDir: tempHome.path), isNull);

        final mismatchClient = MockClient((req) async {
          return http.Response(
            jsonEncode({
              'resource': 'https://evil.example/mcp',
              'authorization_servers': ['https://clerk.agentchatrooms.dev'],
            }),
            200,
          );
        });
        final runnerMismatch = CommandRunner('acr', 'test')
          ..addCommand(LoginCommand(httpClient: mismatchClient));
        final mismatchExit = await runnerMismatch.run([
          'login',
          '--home-dir',
          tempHome.path,
        ]);
        expect(mismatchExit, isNot(equals(0)));
        expect(McpEndpoint.loadSession(homeDir: tempHome.path), isNull);

        final validClient = MockClient((req) async {
          return http.Response(
            jsonEncode({
              'resource': 'https://mcp.agentchatrooms.dev/mcp',
              'authorization_servers': ['https://clerk.agentchatrooms.dev'],
            }),
            200,
          );
        });
        final runnerValid = CommandRunner('acr', 'test')
          ..addCommand(LoginCommand(httpClient: validClient));
        final validExit = await runnerValid.run([
          'login',
          '--home-dir',
          tempHome.path,
        ]);
        expect(validExit, equals(0));
        final saved = McpEndpoint.loadSession(homeDir: tempHome.path);
        expect(saved, isNotNull);
        expect(saved!.scopes, equals(['profile', 'email']));
        expect(saved.resource, equals('https://mcp.agentchatrooms.dev/mcp'));
      } finally {
        tempHome.deleteSync(recursive: true);
      }
    });
  });
}
