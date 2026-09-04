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
    return Process.start(
      Platform.resolvedExecutable,
      [
        guardUri.toFilePath(),
        _identity,
        _repositoryTopologyIdentity,
        executable,
        ...arguments,
      ],
      workingDirectory: root,
      runInShell: false,
      includeParentEnvironment: false,
      environment: environment,
    );
  }
}

final class _WorkspaceChanged implements Exception {
  const _WorkspaceChanged();
}
