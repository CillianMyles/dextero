import 'dart:io';

import '../tool.dart';

final class RunProcessTool implements Tool {
  RunProcessTool({String? workingDirectory})
    : _workingDirectory = workingDirectory;

  final String? _workingDirectory;

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'run_process',
    description: 'Run an executable directly without invoking a shell.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'executable': {'type': 'string'},
        'arguments': {
          'type': 'array',
          'items': {'type': 'string'},
          'default': <String>[],
        },
      },
      'required': ['executable'],
      'additionalProperties': false,
    },
  );

  @override
  Future<Object?> call(JsonMap arguments) async {
    final executable = arguments['executable'];
    final rawArguments = arguments['arguments'] ?? const <Object?>[];
    if (executable is! String || executable.isEmpty) {
      throw const FormatException('executable must be a non-empty string');
    }
    if (rawArguments is! List ||
        rawArguments.any((value) => value is! String)) {
      throw const FormatException('arguments must be an array of strings');
    }

    final result = await Process.run(
      executable,
      rawArguments.cast<String>(),
      workingDirectory: _workingDirectory,
    );
    return {
      'exitCode': result.exitCode,
      'stdout': result.stdout.toString().trimRight(),
      'stderr': result.stderr.toString().trimRight(),
    };
  }
}
