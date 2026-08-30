import 'dart:io';

import 'package:dart_harness_cli_spike/harness.dart';

Future<void> main() async {
  final loop = AgentLoop(
    model: _ScriptedDemoModel(),
    tools: [
      ReadFileTool(root: Directory.current.path),
      RunProcessTool(workingDirectory: Directory.current.path),
    ],
  );

  final run = await loop.run('Inspect this spike and check the Dart version.');
  stdout.writeln(run.output);
}

/// A deterministic stand-in showing the protocol an LLM adapter implements.
final class _ScriptedDemoModel implements AgentModel {
  var _turn = 0;

  @override
  Future<ModelTurn> nextTurn({
    required List<AgentMessage> messages,
    required List<ToolDefinition> tools,
  }) async {
    _turn++;
    return switch (_turn) {
      1 => const ModelTurn(
        toolCalls: [
          ToolCall(
            id: 'read-1',
            name: 'read_file',
            arguments: {'path': 'README.md'},
          ),
        ],
      ),
      2 => const ModelTurn(
        toolCalls: [
          ToolCall(
            id: 'dart-1',
            name: 'run_process',
            arguments: {
              'executable': 'dart',
              'arguments': ['--version'],
            },
          ),
        ],
      ),
      _ => ModelTurn(
        content:
            'Demo complete: executed ${messages.where((m) => m.role == MessageRole.tool).length} tools across the typed agent loop.',
      ),
    };
  }
}
