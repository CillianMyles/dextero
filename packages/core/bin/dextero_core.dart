import 'dart:io';

import 'package:dextero_core/dextero_core.dart';

Future<void> main(List<String> arguments) async {
  final prompt = arguments.isEmpty
      ? 'List the Dart files in lib, read one, and briefly describe it.'
      : arguments.join(' ');
  final root = Directory.current.path;
  try {
    final configuration = AgentRuntimeConfiguration.fromEnvironment(
      Platform.environment,
    );
    final workspace = await WorkspaceBoundary.capture(root);
    final cancellation = CancellationController();
    final run = await configuration
        .createAgent(workspace: workspace)
        .run(prompt, onEvent: (_) {}, cancellationToken: cancellation.token);
    stdout.writeln(run.output);
    stdout.writeln(
      '(${configuration.providerName}, ${configuration.modelName})',
    );
  } on Object catch (error) {
    stderr.writeln('Agent failed: $error');
    stderr.writeln(
      'Configure GEMINI_API_KEY or authenticate Codex with `codex login`.',
    );
    exitCode = 1;
  }
}
