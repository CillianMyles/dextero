import 'dart:convert';
import 'dart:io';

import '../cancellation.dart';
import '../tool.dart';
import '../workspace_boundary.dart';
import 'workspace_path.dart';

final class EditFileTool implements Tool {
  EditFileTool({required String root, WorkspaceBoundary? boundary})
    : _workspace = WorkspacePath(root, boundary: boundary);

  final WorkspacePath _workspace;

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'edit_file',
    description:
        'Replace one exact text occurrence in an existing UTF-8 workspace file.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string'},
        'oldText': {
          'type': 'string',
          'description': 'Exact text that must occur exactly once.',
        },
        'newText': {'type': 'string'},
      },
      'required': ['path', 'oldText', 'newText'],
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
    final oldText = arguments['oldText'];
    final newText = arguments['newText'];
    if (path is! String || path.isEmpty) {
      throw const FormatException('path must be a non-empty string');
    }
    if (oldText is! String || oldText.isEmpty) {
      throw const FormatException('oldText must be a non-empty string');
    }
    if (newText is! String) {
      throw const FormatException('newText must be a string');
    }

    final file = await _workspace.openExistingFile(path, mode: FileMode.append);
    try {
      await file.setPosition(0);
      final content = utf8.decode(await file.read(await file.length()));
      final matches = _countOccurrences(content, oldText);
      if (matches == 0) {
        throw StateError('oldText was not found in $path');
      }
      if (matches > 1) {
        throw StateError(
          'oldText occurs $matches times in $path; edit is ambiguous',
        );
      }

      final updated = content.replaceFirst(oldText, newText);
      await file.truncate(0);
      await file.setPosition(0);
      await file.writeFrom(utf8.encode(updated));
      await file.flush();
      return {
        'path': path,
        'replacements': 1,
        'bytes': utf8.encode(updated).length,
      };
    } finally {
      await file.close();
    }
  }

  int _countOccurrences(String content, String pattern) {
    var count = 0;
    var start = 0;
    while (true) {
      final match = content.indexOf(pattern, start);
      if (match == -1) return count;
      count++;
      start = match + 1;
    }
  }
}
