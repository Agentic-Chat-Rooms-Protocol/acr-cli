import 'dart:convert';
import 'dart:io';
import 'package:acr_cli/src/vcs/collab_driver.dart';
import 'package:test/test.dart';

void main() {
  group('Dart CLI VCS Collab Driver - GitHub (gh CLI)', () {
    late FakeCommandExecutor fakeExecutor;
    late VcsCollabDriver driver;

    setUp(() {
      fakeExecutor = FakeCommandExecutor();
      driver = VcsCollabDriver(executor: fakeExecutor.execute);
    });

    test('issueList constructs exact arguments and parses JSON', () async {
      fakeExecutor.setResponse(
        'gh',
        ['issue', 'list', '--repo', 'owner/repo', '--json', 'number,title,state,author,labels,createdAt'],
        ProcessResult(
          0,
          0,
          jsonEncode([
            {
              'number': 42,
              'title': 'Add 3-pane layout',
              'state': 'OPEN',
              'author': {'login': 'operator'},
            }
          ]),
          '',
        ),
      );

      final issues = await driver.issueList('owner/repo');
      expect(issues.length, equals(1));
      expect(issues.first['number'], equals(42));
      expect(issues.first['title'], equals('Add 3-pane layout'));

      expect(fakeExecutor.invocations.length, equals(1));
      final inv = fakeExecutor.invocations.first;
      expect(inv.executable, equals('gh'));
      expect(inv.arguments, equals([
        'issue',
        'list',
        '--repo',
        'owner/repo',
        '--json',
        'number,title,state,author,labels,createdAt',
      ]));
    });

    test('issueCreate builds command and returns parsed URL', () async {
      fakeExecutor.defaultResult = ProcessResult(0, 0, 'https://github.com/owner/repo/issues/99', '');

      final res = await driver.issueCreate(
        'owner/repo',
        title: 'New incident reported',
        body: 'Database latency spike',
      );

      expect(res.success, isTrue);
      expect(res.output, equals('https://github.com/owner/repo/issues/99'));
      expect(res.data['url'], equals('https://github.com/owner/repo/issues/99'));

      final inv = fakeExecutor.invocations.first;
      expect(inv.arguments, equals([
        'issue',
        'create',
        '--repo',
        'owner/repo',
        '--title',
        'New incident reported',
        '--body',
        'Database latency spike',
      ]));
    });

    test('issueComment builds comment command correctly', () async {
      fakeExecutor.defaultResult = ProcessResult(0, 0, 'Comment recorded', '');

      final res = await driver.issueComment(
        'owner/repo',
        number: 99,
        body: 'Approved by human operator',
      );

      expect(res.success, isTrue);
      expect(fakeExecutor.invocations.first.arguments, equals([
        'issue',
        'comment',
        '99',
        '--repo',
        'owner/repo',
        '--body',
        'Approved by human operator',
      ]));
    });

    test('prList constructs exact argument vector', () async {
      fakeExecutor.setResponse(
        'gh',
        ['pr', 'list', '--repo', 'owner/repo', '--json', 'number,title,state,author,headRefName,baseRefName,createdAt'],
        ProcessResult(
          0,
          0,
          jsonEncode([
            {
              'number': 15,
              'title': 'feat: vcs collab driver',
              'state': 'OPEN',
              'headRefName': 'feat/vcs',
              'baseRefName': 'main',
            }
          ]),
          '',
        ),
      );

      final prs = await driver.prList('owner/repo');
      expect(prs.length, equals(1));
      expect(prs.first['number'], equals(15));
      expect(prs.first['headRefName'], equals('feat/vcs'));
    });

    test('prCreate and prComment construct arguments correctly', () async {
      fakeExecutor.defaultResult = ProcessResult(0, 0, 'https://github.com/owner/repo/pull/16', '');

      final prRes = await driver.prCreate(
        'owner/repo',
        title: 'feat: agent battle view',
        body: 'Prompt battle arena',
        head: 'feat/battle',
        base: 'main',
      );

      expect(prRes.success, isTrue);
      expect(fakeExecutor.invocations[0].arguments, equals([
        'pr',
        'create',
        '--repo',
        'owner/repo',
        '--title',
        'feat: agent battle view',
        '--body',
        'Prompt battle arena',
        '--head',
        'feat/battle',
        '--base',
        'main',
      ]));

      final commentRes = await driver.prComment(
        'owner/repo',
        number: 16,
        body: 'Automated test suite passed',
      );

      expect(commentRes.success, isTrue);
      expect(fakeExecutor.invocations[1].arguments, equals([
        'pr',
        'comment',
        '16',
        '--repo',
        'owner/repo',
        '--body',
        'Automated test suite passed',
      ]));
    });

    test('prMerge supports squash, merge, and rebase strategies', () async {
      fakeExecutor.defaultResult = ProcessResult(0, 0, 'Merged', '');

      await driver.prMerge('owner/repo', number: 16, method: 'squash');
      expect(fakeExecutor.invocations[0].arguments, equals(['pr', 'merge', '16', '--repo', 'owner/repo', '--squash']));

      await driver.prMerge('owner/repo', number: 17, method: 'merge');
      expect(fakeExecutor.invocations[1].arguments, equals(['pr', 'merge', '17', '--repo', 'owner/repo', '--merge']));

      await driver.prMerge('owner/repo', number: 18, method: 'rebase');
      expect(fakeExecutor.invocations[2].arguments, equals(['pr', 'merge', '18', '--repo', 'owner/repo', '--rebase']));
    });

    test('throws ProcessException when gh command fails', () async {
      fakeExecutor.defaultResult = ProcessResult(1, 1, '', 'Permission denied');

      expect(
        () => driver.issueList('private/repo'),
        throwsA(isA<ProcessException>()),
      );
    });
  });

  group('Dart CLI VCS Collab Driver - Jujutsu (jj CLI)', () {
    late FakeCommandExecutor fakeExecutor;
    late VcsCollabDriver driver;

    setUp(() {
      fakeExecutor = FakeCommandExecutor();
      driver = VcsCollabDriver(executor: fakeExecutor.execute);
    });

    test('jjStatus and jjDiff return output strings', () async {
      fakeExecutor.setResponse('jj', ['status'], ProcessResult(0, 0, 'Working copy clean', ''));
      fakeExecutor.setResponse('jj', ['diff'], ProcessResult(0, 0, 'diff --git a/file b/file', ''));

      final status = await driver.jjStatus();
      expect(status, equals('Working copy clean'));

      final diff = await driver.jjDiff();
      expect(diff, contains('diff --git'));

      expect(fakeExecutor.invocations[0].arguments, equals(['status']));
      expect(fakeExecutor.invocations[1].arguments, equals(['diff']));
    });

    test('jjLog handles limit flag optionally', () async {
      fakeExecutor.defaultResult = ProcessResult(0, 0, 'log output', '');

      await driver.jjLog();
      expect(fakeExecutor.invocations[0].arguments, equals(['log']));

      await driver.jjLog(limit: 10);
      expect(fakeExecutor.invocations[1].arguments, equals(['log', '-n', '10']));
    });

    test('jjNewChange, jjDescribe, and jjGitPush construct exact argument vectors', () async {
      fakeExecutor.defaultResult = ProcessResult(0, 0, 'OK', '');

      await driver.jjNewChange('feat: automated commit');
      expect(fakeExecutor.invocations[0].arguments, equals(['new', '-m', 'feat: automated commit']));

      await driver.jjDescribe('feat: refined description');
      expect(fakeExecutor.invocations[1].arguments, equals(['describe', '-m', 'feat: refined description']));

      await driver.jjGitPush();
      expect(fakeExecutor.invocations[2].arguments, equals(['git', 'push']));
    });

    test('throws ProcessException when jj command fails', () async {
      fakeExecutor.defaultResult = ProcessResult(2, 2, '', 'Error: Not a jujutsu repository');

      expect(
        () => driver.jjStatus(),
        throwsA(isA<ProcessException>()),
      );
    });
  });
}
