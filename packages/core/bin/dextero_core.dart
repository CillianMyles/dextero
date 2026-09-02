import 'dart:io';

import 'package:dextero_core/dextero_core.dart';

Future<void> main(List<String> arguments) async {
  final prompt = arguments.isEmpty
      ? 'List the Dart files in lib, read one, and briefly describe it.'
      : arguments.join(' ');
  final root = Directory.current.path;
  final tools = <Tool>[
    ListFilesTool(root: root),
    ReadFileTool(root: root),
    EditFileTool(root: root),
    RunCommandTool(workingDirectory: root),
    RunShellTool(workingDirectory: root),
  ];
  try {
    final geminiApiKey = Platform.environment['GEMINI_API_KEY']?.trim();
    if (geminiApiKey != null && geminiApiKey.isNotEmpty) {
      final model =
          Platform.environment['DEXTERO_GEMINI_MODEL']?.trim().isNotEmpty ==
              true
          ? Platform.environment['DEXTERO_GEMINI_MODEL']!.trim()
          : defaultGeminiModel;
      final run = await AgentLoop(
        model: GeminiModel(
          model: model,
          transport: GeminiHttpTransport(apiKey: geminiApiKey),
        ),
        tools: tools,
      ).run(prompt);
      stdout.writeln(run.output);
      stdout.writeln('($model, ${run.turns} model turns)');
      return;
    }
    final run = await CodexAppServerAgent(
      workingDirectory: root,
    ).run(prompt, tools: tools);
    stdout.writeln(run.output);
    stdout.writeln(
      '(thread ${run.threadId}, ${run.toolCalls} dynamic tool calls)',
    );
  } on Object catch (error) {
    stderr.writeln('Agent failed: $error');
    stderr.writeln(
      'Configure GEMINI_API_KEY or authenticate Codex with `codex login`.',
    );
    exitCode = 1;
  }
}
