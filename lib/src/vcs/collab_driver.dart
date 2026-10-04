import 'dart:convert';
import 'dart:io';

/// Type definition for mockable command execution.
typedef CommandExecutor = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
});

/// Default executor using dart:io Process.run.
Future<ProcessResult> defaultCommandExecutor(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  return Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
}

/// Recorded command for mock verification.
class RecordedCommand {
  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;

  RecordedCommand(
    this.executable,
    this.arguments, {
    this.workingDirectory,
    this.environment,
  });
}

/// Fake command executor for deterministic offline unit testing.
class FakeCommandExecutor {
  final List<RecordedCommand> invocations = [];
  final Map<String, ProcessResult> responses = {};
  ProcessResult defaultResult = ProcessResult(0, 0, '', '');

  void setResponse(String executable, List<String> arguments, ProcessResult result) {
    responses['$executable ${arguments.join(' ')}'] = result;
  }

  Future<ProcessResult> execute(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    invocations.add(RecordedCommand(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    ));

    final key = '$executable ${arguments.join(' ')}';
    if (responses.containsKey(key)) {
      return responses[key]!;
    }
    return defaultResult;
  }
}

/// Result of a VCS operation.
class VcsOperationResult {
  final bool success;
  final String output;
  final String? error;
  final int exitCode;
  final dynamic data;

  VcsOperationResult({
    required this.success,
    required this.output,
    this.error,
    required this.exitCode,
    this.data,
  });
}

/// Jujutsu change representation conforming to collab-vcs.contract.json.
class JujutsuChange {
  final String changeId;
  final String? commitId;
  final String description;
  final bool isWorkingCopy;

  JujutsuChange({
    required this.changeId,
    this.commitId,
    required this.description,
    this.isWorkingCopy = false,
  });

  Map<String, dynamic> toJson() => {
    'change_id': changeId,
    if (commitId != null) 'commit_id': commitId,
    'description': description,
    'is_working_copy': isWorkingCopy,
  };
}

/// Cross-Repository VCS Collaboration Driver.
/// Drives `gh` (GitHub) and `jj` (Jujutsu) CLI tools without credential leakage.
class VcsCollabDriver {
  final CommandExecutor executor;

  VcsCollabDriver({CommandExecutor? executor})
      : executor = executor ?? defaultCommandExecutor;

  // ==========================================
  // GitHub (gh CLI) Collaboration Operations
  // ==========================================

  /// List issues in a repository.
  Future<List<Map<String, dynamic>>> issueList(String repo) async {
    final args = [
      'issue',
      'list',
      '--repo',
      repo,
      '--json',
      'number,title,state,author,labels,createdAt',
    ];

    final res = await executor('gh', args);
    if (res.exitCode != 0) {
      throw ProcessException('gh', args, res.stderr.toString(), res.exitCode);
    }

    try {
      final raw = res.stdout.toString().trim();
      final parsed = jsonDecode(raw.isEmpty ? '[]' : raw);
      if (parsed is List) {
        return parsed.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Create an issue in a repository.
  Future<VcsOperationResult> issueCreate(
    String repo, {
    required String title,
    required String body,
  }) async {
    final args = [
      'issue',
      'create',
      '--repo',
      repo,
      '--title',
      title,
      '--body',
      body,
    ];

    final res = await executor('gh', args);
    if (res.exitCode != 0) {
      throw ProcessException('gh', args, res.stderr.toString(), res.exitCode);
    }

    final out = res.stdout.toString().trim();
    dynamic data;
    try {
      data = jsonDecode(out);
    } catch (_) {
      data = {'url': out};
    }

    return VcsOperationResult(
      success: true,
      output: out,
      exitCode: res.exitCode,
      data: data,
    );
  }

  /// Add a comment to an issue.
  Future<VcsOperationResult> issueComment(
    String repo, {
    required int number,
    required String body,
  }) async {
    final args = [
      'issue',
      'comment',
      number.toString(),
      '--repo',
      repo,
      '--body',
      body,
    ];

    final res = await executor('gh', args);
    if (res.exitCode != 0) {
      throw ProcessException('gh', args, res.stderr.toString(), res.exitCode);
    }

    return VcsOperationResult(
      success: true,
      output: res.stdout.toString().trim(),
      exitCode: res.exitCode,
    );
  }

  /// List pull requests in a repository.
  Future<List<Map<String, dynamic>>> prList(String repo) async {
    final args = [
      'pr',
      'list',
      '--repo',
      repo,
      '--json',
      'number,title,state,author,headRefName,baseRefName,createdAt,mergeable',
    ];

    final res = await executor('gh', args);
    if (res.exitCode != 0) {
      throw ProcessException('gh', args, res.stderr.toString(), res.exitCode);
    }

    try {
      final raw = res.stdout.toString().trim();
      final parsed = jsonDecode(raw.isEmpty ? '[]' : raw);
      if (parsed is List) {
        return parsed.map((item) {
          final m = Map<String, dynamic>.from(item as Map);
          if (m.containsKey('headRefName') && !m.containsKey('head_ref_name')) {
            m['head_ref_name'] = m['headRefName'];
          }
          return m;
        }).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Create a pull request in a repository.
  Future<VcsOperationResult> prCreate(
    String repo, {
    required String title,
    required String body,
    required String head,
    required String base,
  }) async {
    final args = [
      'pr',
      'create',
      '--repo',
      repo,
      '--title',
      title,
      '--body',
      body,
      '--head',
      head,
      '--base',
      base,
    ];

    final res = await executor('gh', args);
    if (res.exitCode != 0) {
      throw ProcessException('gh', args, res.stderr.toString(), res.exitCode);
    }

    final out = res.stdout.toString().trim();
    dynamic data;
    try {
      data = jsonDecode(out);
    } catch (_) {
      data = {'url': out};
    }

    return VcsOperationResult(
      success: true,
      output: out,
      exitCode: res.exitCode,
      data: data,
    );
  }

  /// Add a comment to a pull request.
  Future<VcsOperationResult> prComment(
    String repo, {
    required int number,
    required String body,
  }) async {
    final args = [
      'pr',
      'comment',
      number.toString(),
      '--repo',
      repo,
      '--body',
      body,
    ];

    final res = await executor('gh', args);
    if (res.exitCode != 0) {
      throw ProcessException('gh', args, res.stderr.toString(), res.exitCode);
    }

    return VcsOperationResult(
      success: true,
      output: res.stdout.toString().trim(),
      exitCode: res.exitCode,
    );
  }

  /// Merge a pull request using squash, merge, or rebase, with optional auto/admin flags.
  Future<VcsOperationResult> prMerge(
    String repo, {
    required int number,
    String method = 'squash',
    bool auto = false,
    bool admin = false,
    bool deleteBranch = false,
  }) async {
    final methodFlag = '--$method';
    final args = [
      'pr',
      'merge',
      number.toString(),
      '--repo',
      repo,
      methodFlag,
    ];
    if (auto) args.add('--auto');
    if (admin) args.add('--admin');
    if (deleteBranch) args.add('--delete-branch');

    final res = await executor('gh', args);
    if (res.exitCode != 0) {
      throw ProcessException('gh', args, res.stderr.toString(), res.exitCode);
    }

    return VcsOperationResult(
      success: true,
      output: res.stdout.toString().trim(),
      exitCode: res.exitCode,
    );
  }

  // ==========================================
  // Jujutsu (jj CLI) Collaboration Operations
  // ==========================================

  /// Check working copy status via `jj status`.
  Future<String> jjStatus({String? workingDirectory}) async {
    final args = ['status'];
    final res = await executor('jj', args, workingDirectory: workingDirectory);
    if (res.exitCode != 0) {
      throw ProcessException('jj', args, res.stderr.toString(), res.exitCode);
    }
    return res.stdout.toString().trim();
  }

  /// Show working copy diff via `jj diff`.
  Future<String> jjDiff({String? workingDirectory}) async {
    final args = ['diff'];
    final res = await executor('jj', args, workingDirectory: workingDirectory);
    if (res.exitCode != 0) {
      throw ProcessException('jj', args, res.stderr.toString(), res.exitCode);
    }
    return res.stdout.toString().trim();
  }

  /// Show revision log via `jj log`.
  Future<String> jjLog({int? limit, String? workingDirectory}) async {
    final args = ['log'];
    if (limit != null && limit > 0) {
      args.addAll(['-n', limit.toString()]);
    }
    final res = await executor('jj', args, workingDirectory: workingDirectory);
    if (res.exitCode != 0) {
      throw ProcessException('jj', args, res.stderr.toString(), res.exitCode);
    }
    return res.stdout.toString().trim();
  }

  /// Show revision log parsed into structured JujutsuChange records conforming to collab-vcs.contract.json.
  Future<List<JujutsuChange>> jjLogChanges({int? limit, String? workingDirectory}) async {
    const template = 'change_id ++ "\\t" ++ commit_id ++ "\\t" ++ (if(current_working_copy, "true", "false")) ++ "\\t" ++ description ++ "\\n"';
    final args = ['log', '-T', template];
    if (limit != null && limit > 0) {
      args.addAll(['-n', limit.toString()]);
    }
    final res = await executor('jj', args, workingDirectory: workingDirectory);
    if (res.exitCode != 0) {
      throw ProcessException('jj', args, res.stderr.toString(), res.exitCode);
    }

    final lines = res.stdout.toString().trim().split('\n').where((l) => l.trim().isNotEmpty);
    final changes = <JujutsuChange>[];
    for (final line in lines) {
      final parts = line.split('\t');
      if (parts.length >= 2) {
        changes.add(JujutsuChange(
          changeId: parts[0].trim(),
          commitId: parts[1].trim().isEmpty ? null : parts[1].trim(),
          isWorkingCopy: parts.length > 2 && parts[2].trim() == 'true',
          description: parts.length > 3 ? parts.sublist(3).join('\t').trim() : '',
        ));
      } else {
        final tokens = line.trim().split(RegExp(r'\s+'));
        changes.add(JujutsuChange(
          changeId: tokens.first,
          description: line.trim(),
        ));
      }
    }
    return changes;
  }

  /// Create new change via `jj new -m <message>`.
  Future<String> jjNewChange(String message, {String? workingDirectory}) async {
    final args = ['new', '-m', message];
    final res = await executor('jj', args, workingDirectory: workingDirectory);
    if (res.exitCode != 0) {
      throw ProcessException('jj', args, res.stderr.toString(), res.exitCode);
    }
    return res.stdout.toString().trim();
  }

  /// Describe current change via `jj describe -m <message>`.
  Future<String> jjDescribe(String message, {String? workingDirectory}) async {
    final args = ['describe', '-m', message];
    final res = await executor('jj', args, workingDirectory: workingDirectory);
    if (res.exitCode != 0) {
      throw ProcessException('jj', args, res.stderr.toString(), res.exitCode);
    }
    return res.stdout.toString().trim();
  }

  /// Push changes or bookmarks to git remote via `jj git push`.
  Future<String> jjGitPush({String? workingDirectory}) async {
    final args = ['git', 'push'];
    final res = await executor('jj', args, workingDirectory: workingDirectory);
    if (res.exitCode != 0) {
      throw ProcessException('jj', args, res.stderr.toString(), res.exitCode);
    }
    return res.stdout.toString().trim();
  }
}
