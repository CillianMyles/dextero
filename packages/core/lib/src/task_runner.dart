import 'dart:io';

import 'approval.dart';
import 'codex_app_server_agent.dart';
import 'tool.dart';
import 'tools/edit_file_tool.dart';
import 'tools/list_files_tool.dart';
import 'tools/read_file_tool.dart';
import 'tools/run_command_tool.dart';
import 'tools/run_shell_tool.dart';

enum CoreTaskEventKind { queued, running, output, completed, failed }

final class CoreTaskEvent {
  const CoreTaskEvent({
    required this.taskId,
    required this.sequence,
    required this.kind,
    required this.message,
    required this.timestamp,
    required this.terminal,
  });

  final String taskId;
  final int sequence;
  final CoreTaskEventKind kind;
  final String message;
  final DateTime timestamp;
  final bool terminal;
}

abstract interface class TaskRunner {
  Stream<CoreTaskEvent> run(String prompt);
}

/// Runs one task through Codex app-server with workspace-scoped host tools.
final class CodexTaskRunner implements TaskRunner {
  CodexTaskRunner({
    required String workspace,
    String? model,
    String codexExecutable = 'codex',
    CodexTransportFactory? transportFactory,
    ToolApprovalRequester? onApprovalRequest,
  }) : workspace = Directory(workspace).absolute.path,
       _onApprovalRequest = onApprovalRequest,
       _agent = CodexAppServerAgent(
         model: model,
         workingDirectory: Directory(workspace).absolute.path,
         codexExecutable: codexExecutable,
         transportFactory: transportFactory,
       );

  final String workspace;
  final CodexAppServerAgent _agent;
  final ToolApprovalRequester? _onApprovalRequest;

  static int _taskSequence = 0;

  @override
  Stream<CoreTaskEvent> run(String prompt) async* {
    final normalizedPrompt = prompt.trim();
    if (normalizedPrompt.isEmpty) {
      throw ArgumentError.value(prompt, 'prompt', 'must not be empty');
    }

    final taskId =
        'task-${DateTime.now().microsecondsSinceEpoch}-${++_taskSequence}';
    var sequence = 0;
    CoreTaskEvent event(
      CoreTaskEventKind kind,
      String message, {
      bool terminal = false,
    }) => CoreTaskEvent(
      taskId: taskId,
      sequence: sequence++,
      kind: kind,
      message: message,
      timestamp: DateTime.now().toUtc(),
      terminal: terminal,
    );

    yield event(CoreTaskEventKind.queued, 'Task queued');
    yield event(CoreTaskEventKind.running, 'Codex is working');

    try {
      final run = await _agent.run(
        normalizedPrompt,
        tools: _tools(),
        approvalRequiredTools: const {'edit_file'},
        onApprovalRequest: _onApprovalRequest,
      );
      yield event(CoreTaskEventKind.output, run.output);
      yield event(
        CoreTaskEventKind.completed,
        'Completed with ${run.toolCalls} tool calls',
        terminal: true,
      );
    } on Object catch (error) {
      yield event(CoreTaskEventKind.failed, error.toString(), terminal: true);
    }
  }

  List<Tool> _tools() => [
    ListFilesTool(root: workspace),
    ReadFileTool(root: workspace),
    EditFileTool(root: workspace),
    RunCommandTool(workingDirectory: workspace),
    RunShellTool(workingDirectory: workspace),
  ];
}
