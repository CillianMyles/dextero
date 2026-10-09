import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dextero_cli/dextero_cli.dart';
import 'package:dextero_core/dextero_core.dart';
import 'package:dextero_server/dextero_server.dart';
import 'package:test/test.dart';

void main() {
  test(
    'a voice turn crosses the network into the shared conversation',
    () async {
      const token = 'acceptance-token-0123456789-0123456789';
      final store = InMemoryChatHistoryStore();
      final editTool = _EditFileTool();
      final transport = _GeminiTransport();
      final transcriber = _Transcriber();
      final service = ChatService(
        store: store,
        agent: ModelConversationAgent(
          model: GeminiModel(transport: transport),
          tools: [editTool],
          providerName: 'Gemini',
          approvalRequiredTools: const {'edit_file'},
        ),
      );
      final conversation = await service.createConversation();
      final portProbe = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final apiPort = portProbe.port;
      await portProbe.close();
      final pod = await startControlServer(
        token: token,
        chatService: service,
        defaultConversationId: conversation.id,
        modelProvider: 'gemini',
        modelName: defaultGeminiModel,
        voiceService: VoiceService(
          store: store,
          transcriber: transcriber,
          synthesizer: _Synthesizer(),
        ),
        apiPort: apiPort,
        runInGuardedZone: false,
      );
      final directory = Directory.systemTemp.createTempSync('dextero-voice-');
      addTearDown(() async {
        await pod.shutdown(exitProcess: false);
        await store.close();
        directory.deleteSync(recursive: true);
      });
      final url = 'http://localhost:${pod.server.port}/';
      ServerpodTerminalChatClient client() =>
          ServerpodTerminalChatClient(serverUrl: url, token: token);
      // Twenty seconds of 16 kHz speech-level audio exceeds Serverpod's
      // default 512 KiB request limit once base64-encoded.
      final recording = _tone(seconds: 20);
      final replyPath = '${directory.path}/reply.wav';

      final statusClient = client();
      final status = await statusClient.status();
      await statusClient.close();
      expect(status.voiceInputAvailable, isTrue);
      expect(status.voiceOutputAvailable, isTrue);
      expect(status.voiceNotice, contains('deleted after transcription'));

      final voiceIo = _Io();
      final voiceTurn =
          TerminalChat(
            client: client(),
            io: voiceIo,
            correlationIdFactory: () => 'acceptance-voice',
          ).run(
            voice: VoiceFile(bytes: recording, mimeType: 'audio/wav'),
            replyAudioPath: replyPath,
          );
      final pending = await store
          .watch(conversation.id)
          .firstWhere(
            (entry) =>
                entry.kind == ChatEntryKind.approval &&
                entry.status == ChatEntryStatus.pending,
          );
      expect(editTool.calls, 0);
      final approver = client();
      expect(
        await approver.approveWork(
          conversation.id,
          pending.runId!,
          pending.approvalId!,
        ),
        isTrue,
      );
      await approver.close();

      expect(await voiceTurn, 0);
      expect(voiceIo.errors, isEmpty);
      expect(transcriber.received, recording);
      expect(editTool.calls, 1);
      expect(voiceIo.text, contains('[you · voice] Please update the README.'));
      expect(
        voiceIo.text,
        contains('(transcribed by fake whisper on this host)'),
      );
      expect(voiceIo.text, contains('[approval] edit_file approved'));
      expect(voiceIo.text, contains('[dextero] README updated.'));
      expect(
        utf8.decode(File(replyPath).readAsBytesSync()),
        'spoken:README updated.',
      );
      expect(
        voiceIo.text,
        contains('Spoken reply saved to $replyPath (fake voice on this host)'),
      );

      final textIo = _Io();
      expect(
        await TerminalChat(
          client: client(),
          io: textIo,
          correlationIdFactory: () => 'acceptance-text',
        ).run(initialMessage: 'Was that change spoken?'),
        0,
      );
      expect(textIo.text, contains('[you] Was that change spoken?'));
      expect(textIo.text, contains('[dextero] Yes, by voice.'));

      final history = await store.history(conversation.id);
      expect(
        history.map((entry) => entry.sequence),
        List.generate(history.length, (index) => index),
      );
      final users = history
          .where((entry) => entry.kind == ChatEntryKind.userMessage)
          .toList();
      expect(users.map((entry) => entry.modality), [
        ChatModality.voice,
        ChatModality.text,
      ]);
      expect(users.map((entry) => entry.transcriptionEngine), [
        'fake whisper on this host',
        null,
      ]);
      expect(users.map((entry) => entry.correlationId), [
        'acceptance-voice',
        'acceptance-text',
      ]);
      expect(
        history
            .where((entry) => entry.runId == users.first.runId)
            .map((entry) => entry.kind),
        containsAllInOrder([
          ChatEntryKind.userMessage,
          ChatEntryKind.toolCall,
          ChatEntryKind.approval,
          ChatEntryKind.approval,
          ChatEntryKind.toolResult,
          ChatEntryKind.assistantMessage,
          ChatEntryKind.lifecycle,
        ]),
      );
      expect(transport.prompts, [
        'Please update the README.',
        'Was that change spoken?',
      ]);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

Uint8List _tone({required int seconds}) {
  const sampleRate = 16000;
  final samples = sampleRate * seconds;
  final data = ByteData(44 + samples * 2);
  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      data.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (var index = 0; index < samples; index++) {
    final value = sin(2 * pi * 220 * index / sampleRate) * 8000;
    data.setInt16(44 + index * 2, value.round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

final class _Transcriber implements SpeechTranscriber {
  Uint8List? received;

  @override
  String get engine => 'fake whisper on this host';

  @override
  Set<String> get supportedMimeTypes => const {'audio/wav'};

  @override
  Future<SpeechTranscript> transcribe(
    SpeechAudio audio, {
    CancellationToken? cancellationToken,
  }) async {
    received = audio.bytes;
    return SpeechTranscript(
      text: ' Please update the README. [BLANK_AUDIO]',
      engine: engine,
    );
  }
}

final class _Synthesizer implements SpeechSynthesizer {
  @override
  String get engine => 'fake voice on this host';

  @override
  Future<SynthesizedSpeech> synthesize(
    String text, {
    CancellationToken? cancellationToken,
  }) async => SynthesizedSpeech(
    bytes: Uint8List.fromList(utf8.encode('spoken:$text')),
    mimeType: 'audio/wav',
    engine: engine,
  );
}

/// Requests a gated edit for the voice prompt and answers the follow-up.
final class _GeminiTransport implements GeminiTransport {
  final prompts = <String>[];

  @override
  Future<JsonMap> generateContent({
    required String model,
    required JsonMap request,
    CancellationToken? cancellationToken,
  }) async {
    final contents = request['contents']! as List;
    final prompt =
        (((contents.first as Map)['parts'] as List).first as Map)['text']
            as String;
    final toolTurn = (((contents.last as Map)['parts'] as List).first as Map)
        .containsKey('functionResponse');
    if (contents.length == 1) prompts.add(prompt);
    final part = switch (prompt) {
      'Please update the README.' when !toolTurn => {
        'functionCall': {
          'id': 'voice-edit-1',
          'name': 'edit_file',
          'args': {'path': 'README.md', 'oldText': 'old', 'newText': 'new'},
        },
      },
      'Please update the README.' => {'text': 'README updated.'},
      _ => {'text': 'Yes, by voice.'},
    };
    return {
      'candidates': [
        {
          'content': {
            'parts': [part],
          },
        },
      ],
    };
  }
}

final class _EditFileTool implements Tool {
  var calls = 0;

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'edit_file',
    description: 'Edit a file.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string'},
        'oldText': {'type': 'string'},
        'newText': {'type': 'string'},
      },
      'additionalProperties': false,
    },
  );

  @override
  Object? call(
    JsonMap arguments, {
    CancellationToken? cancellationToken,
    ToolOutputSink? onOutput,
  }) {
    calls++;
    return {'path': arguments['path']};
  }
}

final class _Io implements TerminalIo {
  final output = <String>[];
  final errors = <String>[];

  String get text => output.join();

  @override
  bool get hasInputTerminal => false;

  @override
  bool get hasOutputTerminal => false;

  @override
  void error(String value) => errors.add(value);

  @override
  String? readLine() => null;

  @override
  void write(String value) => output.add(value);

  @override
  void writeln(String value) => output.add('$value\n');
}
