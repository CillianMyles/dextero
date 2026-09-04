import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'control_identity.dart';
import 'filesystem_identity.dart';

/// Pins a workspace to one canonical filesystem object for an agent lifetime.
final class WorkspaceBoundary {
  const WorkspaceBoundary._({
    required this.root,
    required String identity,
    required String repositoryTopologyIdentity,
  }) : _identity = identity,
       _repositoryTopologyIdentity = repositoryTopologyIdentity;

  static Future<WorkspaceBoundary> capture(String workspace) async {
    final directory = Directory(workspace).absolute;
    if (!await directory.exists()) {
      throw ArgumentError.value(
        workspace,
        'workspace',
        'must be an existing directory',
      );
    }
    final root = await directory.resolveSymbolicLinks();
    final boundary = WorkspaceBoundary._(
      root: root,
      identity: await resolveFilesystemIdentity(Directory(root)),
      repositoryTopologyIdentity: await resolveRepositoryTopologyIdentity(
        Directory(root),
      ),
    );
    await boundary.validate();
    return boundary;
  }

  final String root;
  final String _identity;
  final String _repositoryTopologyIdentity;

  Future<void> validate() async {
    try {
      final directory = Directory(root);
      if (await directory.resolveSymbolicLinks() != root ||
          await resolveFilesystemIdentity(directory) != _identity ||
          await resolveRepositoryTopologyIdentity(directory) !=
              _repositoryTopologyIdentity) {
        throw const _WorkspaceChanged();
      }
    } on Object {
      throw FileSystemException(
        'Configured workspace changed after identity resolution',
        root,
      );
    }
  }

  /// Starts a child only after it verifies the filesystem-bound working dir.
  Future<Process> startProcess(
    String executable,
    List<String> arguments, {
    required Map<String, String> environment,
  }) async {
    await validate();
    final guardUri = await Isolate.resolvePackageUri(
      Uri.parse('package:dextero_core/src/workspace_process_guard.dart'),
    );
    if (guardUri == null || guardUri.scheme != 'file') {
      throw StateError('Cannot resolve the workspace process guard');
    }
    final startupDirectory = await Directory.systemTemp.createTemp(
      'dextero-process-start-',
    );
    final startupFile = File('${startupDirectory.path}/status.json');
    try {
      final guard = await Process.start(
        Platform.resolvedExecutable,
        [
          guardUri.toFilePath(),
          _identity,
          _repositoryTopologyIdentity,
          startupFile.path,
          executable,
          ...arguments,
        ],
        workingDirectory: root,
        runInShell: false,
        includeParentEnvironment: false,
        environment: environment,
      );
      final startup = await _waitForGuardStartup(guard, startupFile);
      if (startup.status == 'launchError') {
        await guard.exitCode;
        throw ProcessException(
          executable,
          arguments,
          startup.message ?? 'Failed to start guarded process',
          startup.errorCode ?? 0,
        );
      }
      return guard;
    } finally {
      await startupDirectory.delete(recursive: true);
    }
  }
}

Future<_GuardStartup> _waitForGuardStartup(
  Process guard,
  File startupFile,
) async {
  var exited = false;
  unawaited(guard.exitCode.then((_) => exited = true));
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    if (await startupFile.exists()) {
      final decoded = jsonDecode(await startupFile.readAsString());
      if (decoded is! Map<String, Object?> || decoded['status'] is! String) {
        throw const FormatException('Invalid workspace guard startup status');
      }
      return _GuardStartup(
        status: decoded['status']! as String,
        message: decoded['message'] as String?,
        errorCode: decoded['errorCode'] as int?,
      );
    }
    if (exited) {
      throw ProcessException(
        Platform.resolvedExecutable,
        const [],
        'Workspace process guard exited before reporting startup',
        await guard.exitCode,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  guard.kill();
  await guard.exitCode;
  throw ProcessException(
    Platform.resolvedExecutable,
    const [],
    'Workspace process guard did not report startup',
  );
}

final class _GuardStartup {
  const _GuardStartup({
    required this.status,
    required this.message,
    required this.errorCode,
  });

  final String status;
  final String? message;
  final int? errorCode;
}

final class _WorkspaceChanged implements Exception {
  const _WorkspaceChanged();
}
