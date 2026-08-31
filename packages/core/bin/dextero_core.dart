import 'dart:io';

import 'package:dextero_core/dextero_core.dart';

Future<void> main(List<String> arguments) async {
  final prompt = arguments.isEmpty
      ? 'List the Dart files in lib, read one, and briefly describe it.'
      : arguments.join(' ');
  final root = Directory.current.path;
  try {
    final run = await CodexAppServerAgent(workingDirectory: root).run(
      prompt,
      tools: [
        ListFilesTool(root: root),
        ReadFileTool(root: root),
        EditFileTool(root: root),
        RunProcessTool(workingDirectory: root),
        BashTool(workingDirectory: root),
      ],
    );
    stdout.writeln(run.output);
    stdout.writeln(
      '(thread ${run.threadId}, ${run.toolCalls} dynamic tool calls)',
    );
  } on StateError catch (error) {
    stderr.writeln('Codex app-server failed: ${error.message}');
    stderr.writeln('If authentication is missing, run `codex login` first.');
    exitCode = 1;
  }
}
