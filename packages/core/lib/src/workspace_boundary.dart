import 'dart:io';

import 'filesystem_identity.dart';

/// Pins a workspace to one canonical filesystem object for an agent lifetime.
final class WorkspaceBoundary {
  const WorkspaceBoundary._({required this.root, required String identity})
    : _identity = identity;

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
    return WorkspaceBoundary._(
      root: root,
      identity: await resolveFilesystemIdentity(Directory(root)),
    );
  }

  final String root;
  final String _identity;

  Future<void> validate() async {
    try {
      final directory = Directory(root);
      if (await directory.resolveSymbolicLinks() != root ||
          await resolveFilesystemIdentity(directory) != _identity) {
        throw const _WorkspaceChanged();
      }
    } on Object {
      throw FileSystemException(
        'Configured workspace changed after identity resolution',
        root,
      );
    }
  }
}

final class _WorkspaceChanged implements Exception {
  const _WorkspaceChanged();
}
