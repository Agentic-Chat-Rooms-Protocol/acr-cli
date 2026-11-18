import 'dart:convert';
import 'dart:io';

import 'package:acr_cli/src/api/acr_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('AcrClient defaults and token resolution', () {
    test('defaults baseUrl to loopback literal http://127.0.0.1:20443', () {
      final client = AcrClient(environment: const {}, homeDir: '');
      expect(client.baseUrl, equals('http://127.0.0.1:20443'));
      expect(client.apiToken, isNull);
    });

    test('loads token from ACR_API_TOKEN env var before ~/.acr/api-token', () {
      final tempHome = Directory.systemTemp.createTempSync('acr_token_test_');
      try {
        final acrDir = Directory(
          '${tempHome.path}${Platform.pathSeparator}.acr',
        )..createSync(recursive: true);
        File('${acrDir.path}${Platform.pathSeparator}api-token')
            .writeAsStringSync('file-token-abc\n');

        final fromEnv = AcrClient(
          environment: {'ACR_API_TOKEN': '  env-token-123  '},
          homeDir: tempHome.path,
        );
        expect(fromEnv.apiToken, equals('env-token-123'));

        final fromFile = AcrClient(
          environment: const {},
          homeDir: tempHome.path,
        );
        expect(fromFile.apiToken, equals('file-token-abc'));

        final fromExplicit = AcrClient(
          apiToken: 'explicit-token',
          environment: {'ACR_API_TOKEN': 'env-token-123'},
          homeDir: tempHome.path,
        );
        expect(fromExplicit.apiToken, equals('explicit-token'));
      } finally {
        tempHome.deleteSync(recursive: true);
      }
    });

    test('ignores blank token files and empty ACR_API_TOKEN', () {
      final tempHome = Directory.systemTemp.createTempSync('acr_blank_tok_');
      try {
        final acrDir = Directory(
          '${tempHome.path}${Platform.pathSeparator}.acr',
        )..createSync(recursive: true);
        File('${acrDir.path}${Platform.pathSeparator}api-token')
            .writeAsStringSync('   \n  ');

        final client = AcrClient(
          environment: {'ACR_API_TOKEN': '   '},
          homeDir: tempHome.path,
        );
        expect(client.apiToken, isNull);
      } finally {
        tempHome.deleteSync(recursive: true);
      }
    });

    test(
      'attaches Authorization Bearer header and disables redirects on requests',
      () async {
        String? capturedAuth;
        bool? capturedFollowRedirects;

        final mockHttp = MockClient((http.Request req) async {
          capturedAuth = req.headers['Authorization'];
          capturedFollowRedirects = req.followRedirects;
          return http.Response(
            jsonEncode([
              {'id': 'room-1'},
            ]),
            200,
          );
        });

        final client = AcrClient(
          apiToken: 'secret-local-token',
          client: mockHttp,
          environment: const {},
        );
        final rooms = await client.fetchRooms();
        expect(rooms, hasLength(1));
        expect(capturedAuth, equals('Bearer secret-local-token'));
        expect(capturedFollowRedirects, isFalse);
      },
    );

    test(
      'does not attach Authorization header when no token is configured',
      () async {
        bool hasAuthHeader = true;

        final mockHttp = MockClient((http.Request req) async {
          hasAuthHeader = req.headers.containsKey('Authorization');
          return http.Response(jsonEncode({'status': 'healthy'}), 200);
        });

        final tempHome = Directory.systemTemp.createTempSync('acr_notok_');
        try {
          final client = AcrClient(
            client: mockHttp,
            environment: const {},
            homeDir: tempHome.path,
          );
          await client.fetchHealth();
          expect(hasAuthHeader, isFalse);
        } finally {
          tempHome.deleteSync(recursive: true);
        }
      },
    );

    test(
      'blocks 3xx redirects without forwarding Bearer token to target',
      () async {
        bool targetHit = false;
        final targetServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        targetServer.listen((HttpRequest req) async {
          targetHit = true;
          req.response.statusCode = 200;
          req.response.write('[]');
          await req.response.close();
        });

        final redirectServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        redirectServer.listen((HttpRequest req) async {
          req.response.statusCode = HttpStatus.found;
          req.response.headers.set(
            HttpHeaders.locationHeader,
            'http://127.0.0.1:${targetServer.port}/api/v1/rooms',
          );
          await req.response.close();
        });

        try {
          final client = AcrClient(
            baseUrl: 'http://127.0.0.1:${redirectServer.port}',
            apiToken: 'canary-bearer-token',
            environment: const {},
          );
          await expectLater(
            client.fetchRooms(),
            throwsA(
              isA<HttpException>().having(
                (e) => e.message,
                'message',
                contains('Redirect blocked'),
              ),
            ),
          );
          expect(targetHit, isFalse);
        } finally {
          await redirectServer.close(force: true);
          await targetServer.close(force: true);
        }
      },
    );
  });
}
