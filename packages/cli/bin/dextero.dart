import 'dart:io';

import 'package:dextero_cli/dextero_cli.dart';
import 'package:dextero_server/dextero_client.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await run(arguments);
}

Future<int> run(List<String> arguments) async {
  final token = Platform.environment['DEXTERO_CONTROL_TOKEN'];
  if (token == null || token.length < 32) {
    stderr.writeln(
      'DEXTERO_CONTROL_TOKEN is missing. Run the client with `make cli`.',
    );
    return 64;
  }

  final prompt = _readPrompt(arguments);
  if (prompt == null || prompt.trim().isEmpty) {
    stderr.writeln('A task prompt is required.');
    return 64;
  }

  final rawUrl =
      Platform.environment['DEXTERO_CONTROL_URL'] ?? 'http://localhost:8080/';
  final url = rawUrl.endsWith('/') ? rawUrl : '$rawUrl/';
  final client = Client(url)..authKeyProvider = DexteroTokenAuthProvider(token);
  const renderer = TerminalRenderer();
  final events = <TaskEvent>[];
  var failed = false;

  try {
    final status = await client.control.status();
    if (stdout.hasTerminal) {
      stdout.write('\x1b[?25l');
      stdout.write(
        renderer.frame(status: status, prompt: prompt, events: events),
      );
    } else {
      stdout.writeln('${status.name} ${status.version} — $prompt');
    }

    await for (final event in client.control.runTask(prompt)) {
      events.add(event);
      failed |= event.kind == TaskEventKind.failed;
      if (stdout.hasTerminal) {
        stdout.write(
          renderer.frame(status: status, prompt: prompt, events: events),
        );
      } else {
        stdout.writeln(renderer.plainEventLine(event));
      }
    }
  } on Object catch (error) {
    stderr.writeln('Dextero request failed: $error');
    return 1;
  } finally {
    if (stdout.hasTerminal) stdout.write('\x1b[?25h\n');
    client.close();
  }
  return failed ? 1 : 0;
}

String? _readPrompt(List<String> arguments) {
  if (arguments.isNotEmpty) return arguments.join(' ');
  stdout.write('What should Dextero do? ');
  return stdin.readLineSync();
}
