import 'dart:io';

import '../cancellation.dart';
import '../tool.dart';
import 'workspace_path.dart';

final class ListFilesTool implements Tool {
  ListFilesTool({required String root}) : _workspace = WorkspacePath(root);

  final WorkspacePath _workspace;

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'list_files',
    description:
        'List workspace files and directories without following symbolic links.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'path': {
          'type': 'string',
          'default': '.',
          'description': 'Directory relative to the workspace root.',
        },
        'recursive': {'type': 'boolean', 'default': false},
      },
      'additionalProperties': false,
    },
  );

  @override
  Future<Object?> call(
    JsonMap arguments, {
    CancellationToken? cancellationToken,
    ToolOutputSink? onOutput,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    final path = arguments['path'] ?? '.';
    final recursive = arguments['recursive'] ?? false;
    if (path is! String || path.isEmpty) {
      throw const FormatException('path must be a non-empty string');
    }
    if (recursive is! bool) {
      throw const FormatException('recursive must be a boolean');
    }

    final directoryPath = await _workspace.resolveExisting(
      path,
      expectedType: FileSystemEntityType.directory,
      allowRoot: true,
    );
    final rootPath = await _workspace.canonicalRoot();
    final entries = <JsonMap>[];
    await for (final entity in Directory(
      directoryPath,
    ).list(recursive: recursive, followLinks: false)) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      final relativePath = entity.path.substring(
        rootPath.length + Platform.pathSeparator.length,
      );
      entries.add({
        'path': relativePath,
        'type': switch (type) {
          FileSystemEntityType.file => 'file',
          FileSystemEntityType.directory => 'directory',
          FileSystemEntityType.link => 'link',
          _ => 'other',
        },
      });
    }
    entries.sort(
      (left, right) =>
          (left['path']! as String).compareTo(right['path']! as String),
    );
    return {'path': path, 'entries': entries};
  }
}
