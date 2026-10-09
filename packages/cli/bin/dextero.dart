import 'dart:io';

import 'package:dextero_cli/dextero_cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await run(arguments);
}

typedef TerminalClientFactory =
    TerminalChatClient Function({
      required String serverUrl,
      required String token,
    });

typedef TuiRunner =
    Future<int> Function({
      required TerminalChatClient client,
      String? modelName,
    });

TerminalChatClient _createClient({
  required String serverUrl,
  required String token,
}) => ServerpodTerminalChatClient(serverUrl: serverUrl, token: token);

Future<int> _runTui({required TerminalChatClient client, String? modelName}) =>
    runNoctermChat(client: client, modelName: modelName);

Future<int> run(
  List<String> arguments, {
  TerminalIo io = const SystemTerminalIo(),
  Map<String, String>? environment,
  TerminalClientFactory clientFactory = _createClient,
  TuiRunner tuiRunner = _runTui,
}) async {
  final effectiveEnvironment = environment ?? Platform.environment;
  final token = effectiveEnvironment['DEXTERO_CONTROL_TOKEN'];
  if (token == null || token.length < 32) {
    io.error(
      'DEXTERO_CONTROL_TOKEN is missing. Run the client with `make cli`.',
    );
    return 64;
  }

  final rawUrl =
      effectiveEnvironment['DEXTERO_CONTROL_URL'] ?? 'http://localhost:8080/';
  var jsonl = false;
  String? modelName;
  String? voicePath;
  String? replyAudioPath;
  String? cancelRunId;
  String? approveRunId;
  String? approvalId;
  final message = <String>[];
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    switch (argument) {
      case '--jsonl':
        jsonl = true;
      case '--model':
        if (index + 1 >= arguments.length) {
          io.error('Usage: dextero [--jsonl] [--model <name>] [message]');
          return 64;
        }
        modelName = arguments[++index];
      case '--voice':
        if (index + 1 >= arguments.length) {
          io.error(
            'Usage: dextero --voice <recording.wav> [--reply-audio <out.wav>]',
          );
          return 64;
        }
        voicePath = arguments[++index];
      case '--reply-audio':
        if (index + 1 >= arguments.length) {
          io.error('Usage: dextero --reply-audio <out.wav> <message>');
          return 64;
        }
        replyAudioPath = arguments[++index];
      case '--cancel':
        if (index + 1 >= arguments.length) {
          io.error('Usage: dextero --cancel <run-id>');
          return 64;
        }
        cancelRunId = arguments[++index];
      case '--approve':
        if (index + 2 >= arguments.length) {
          io.error('Usage: dextero --approve <run-id> <approval-id>');
          return 64;
        }
        approveRunId = arguments[++index];
        approvalId = arguments[++index];
      default:
        message.add(argument);
    }
  }
  final actionCount = [
    cancelRunId,
    approveRunId,
  ].where((value) => value != null).length;
  if (actionCount > 1) {
    io.error('Cancellation and approval requests cannot be combined.');
    return 64;
  }
  if (actionCount != 0 && message.isNotEmpty) {
    io.error('A cancellation or approval request cannot include a message.');
    return 64;
  }
  if (actionCount != 0 && modelName != null) {
    io.error('A cancellation or approval request cannot select a model.');
    return 64;
  }
  if (voicePath != null && (actionCount != 0 || message.isNotEmpty)) {
    io.error('A voice turn cannot be combined with a message or request.');
    return 64;
  }
  if (replyAudioPath != null && voicePath == null && message.isEmpty) {
    io.error('--reply-audio needs a message or --voice recording.');
    return 64;
  }
  VoiceFile? voice;
  if (voicePath != null) {
    try {
      voice = await VoiceFile.read(voicePath);
    } on Object catch (error) {
      io.error('Cannot read the voice recording: $error');
      return 66;
    }
  }
  final client = clientFactory(serverUrl: rawUrl, token: token);
  if (io.hasInputTerminal &&
      io.hasOutputTerminal &&
      !jsonl &&
      message.isEmpty &&
      voice == null &&
      actionCount == 0) {
    return tuiRunner(client: client, modelName: modelName);
  }
  final chat = TerminalChat(
    client: client,
    io: io,
    outputMode: jsonl ? TerminalOutputMode.jsonl : TerminalOutputMode.human,
  );
  return chat.run(
    initialMessage: message.isEmpty ? null : message.join(' '),
    voice: voice,
    replyAudioPath: replyAudioPath,
    cancelRunId: cancelRunId,
    approveRunId: approveRunId,
    approvalId: approvalId,
    modelName: modelName,
  );
}
