import '../cancellation.dart';
import '../tool.dart';
import '../workspace_boundary.dart';
import 'tool_process_runner.dart';

final class RunCommandTool implements Tool {
  RunCommandTool({
    required String workingDirectory,
    WorkspaceBoundary? workspaceBoundary,
    Duration timeout = const Duration(seconds: 30),
    int maxOutputBytes = 1024 * 1024,
  }) : _runner = ToolProcessRunner(
         workingDirectory: workingDirectory,
         workspaceBoundary: workspaceBoundary,
         timeout: timeout,
         maxOutputBytes: maxOutputBytes,
       );

  final ToolProcessRunner _runner;

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'run_command',
    description:
        'Run a command with structured arguments, without a shell. '
        'Use this by default for CLI execution.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'command': {'type': 'string'},
        'arguments': {
          'type': 'array',
          'items': {'type': 'string'},
          'default': <String>[],
        },
      },
      'required': ['command'],
      'additionalProperties': false,
    },
  );

  @override
  Future<Object?> call(
    JsonMap arguments, {
    CancellationToken? cancellationToken,
    ToolOutputSink? onOutput,
  }) async {
    final command = arguments['command'];
    final rawArguments = arguments['arguments'] ?? const <Object?>[];
    if (command is! String || command.trim().isEmpty) {
      throw const FormatException('command must be a non-empty string');
    }
    if (rawArguments is! List ||
        rawArguments.any((value) => value is! String)) {
      throw const FormatException('arguments must be an array of strings');
    }

    return _runner.run(
      command,
      rawArguments.cast<String>(),
      cancellationToken: cancellationToken,
      onOutput: onOutput,
    );
  }
}
