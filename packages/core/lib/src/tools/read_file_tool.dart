import 'dart:convert';

import '../cancellation.dart';
import '../tool.dart';
import '../workspace_boundary.dart';
import 'workspace_path.dart';

final class ReadFileTool implements Tool {
  ReadFileTool({required String root, WorkspaceBoundary? boundary})
    : _workspace = WorkspacePath(root, boundary: boundary);

  final WorkspacePath _workspace;

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'read_file',
    description: 'Read a UTF-8 text file beneath the configured workspace.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'path': {
          'type': 'string',
          'description': 'Path relative to the workspace root.',
        },
      },
      'required': ['path'],
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
    final path = arguments['path'];
    if (path is! String || path.isEmpty) {
      throw const FormatException('path must be a non-empty string');
    }

    final file = await _workspace.openExistingFile(path);
    try {
      final content = utf8.decode(await file.read(await file.length()));
      return {'path': path, 'content': content};
    } finally {
      await file.close();
    }
  }
}
