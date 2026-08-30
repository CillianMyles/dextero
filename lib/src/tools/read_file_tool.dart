import 'dart:io';

import '../tool.dart';

final class ReadFileTool implements Tool {
  ReadFileTool({required String root}) : _root = Directory(root).absolute;

  final Directory _root;

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
  Future<Object?> call(JsonMap arguments) async {
    final path = arguments['path'];
    if (path is! String || path.isEmpty) {
      throw const FormatException('path must be a non-empty string');
    }

    final rootPath = await _root.resolveSymbolicLinks();
    final file = File('${_root.path}${Platform.pathSeparator}$path');
    final filePath = await file.resolveSymbolicLinks();
    final prefix = '$rootPath${Platform.pathSeparator}';
    if (!filePath.startsWith(prefix)) {
      throw ArgumentError('path escapes the configured workspace');
    }

    return {'path': path, 'content': await File(filePath).readAsString()};
  }
}
