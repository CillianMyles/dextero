import 'dart:io';

import '../tool.dart';
import 'tool_process_runner.dart';

final class RunShellTool implements Tool {
  RunShellTool({
    required String workingDirectory,
    Duration timeout = const Duration(seconds: 30),
    int maxOutputBytes = 1024 * 1024,
  }) : _runner = ToolProcessRunner(
         workingDirectory: workingDirectory,
         timeout: timeout,
         maxOutputBytes: maxOutputBytes,
       );

  final ToolProcessRunner _runner;

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'run_shell',
    description:
        'Run a single command string through the platform shell. '
        'Use only when shell syntax is required.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'command': {'type': 'string'},
      },
      'required': ['command'],
      'additionalProperties': false,
    },
  );

  @override
  Future<Object?> call(JsonMap arguments) async {
    final command = arguments['command'];
    if (command is! String || command.trim().isEmpty) {
      throw const FormatException('command must be a non-empty string');
    }

    final shell = Platform.isWindows ? 'cmd.exe' : '/bin/sh';
    final shellArguments = Platform.isWindows
        ? ['/d', '/s', '/c', command]
        : ['-c', command];
    return _runner.run(shell, shellArguments);
  }
}
