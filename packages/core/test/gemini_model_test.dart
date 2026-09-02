import 'dart:convert';
import 'dart:io';

import 'package:dextero_core/dextero_core.dart';
import 'package:test/test.dart';

void main() {
  test('drives the agent loop through a Gemini function call', () async {
    final transport = _QueueTransport([
      {
        'candidates': [
          {
            'content': {
              'role': 'model',
              'parts': [
                {'thought': true, 'text': 'private reasoning'},
                {
                  'functionCall': {
                    'id': 'gemini-call-1',
                    'name': 'echo',
                    'args': {'value': 'hello'},
                  },
                  'thoughtSignature': 'opaque-signature',
                },
              ],
            },
            'finishReason': 'STOP',
          },
        ],
      },
      {
        'candidates': [
          {
            'content': {
              'role': 'model',
              'parts': [
                {'text': 'Workspace ready.'},
              ],
            },
            'finishReason': 'STOP',
          },
        ],
      },
    ]);
    final activities = <AgentLoopActivity>[];

    final run = await AgentLoop(
      model: GeminiModel(transport: transport),
      tools: [_EchoTool()],
    ).run('Inspect it', onActivity: activities.add);

    expect(run.output, 'Workspace ready.');
    expect(run.turns, 2);
    expect(transport.models, [defaultGeminiModel, defaultGeminiModel]);
    expect(activities.map((activity) => activity.kind), [
      AgentLoopActivityKind.toolCallStarted,
      AgentLoopActivityKind.toolCallCompleted,
    ]);

    final first = transport.requests.first;
    expect(first['systemInstruction'], isA<Map>());
    final declarations =
        ((first['tools']! as List).single as Map)['functionDeclarations']
            as List;
    expect((declarations.single as Map)['parametersJsonSchema'], {
      'type': 'object',
      'properties': {
        'value': {'type': 'string'},
      },
      'additionalProperties': false,
    });

    final contents = transport.requests.last['contents']! as List;
    expect(contents, hasLength(3));
    final modelPart = (((contents[1] as Map)['parts'] as List).single as Map);
    expect(modelPart['thoughtSignature'], 'opaque-signature');
    expect((modelPart['functionCall'] as Map)['id'], 'gemini-call-1');
    expect(modelPart, isNot(contains('text')));
    final response =
        ((((contents[2] as Map)['parts'] as List).single
                as Map)['functionResponse']
            as Map);
    expect(response['id'], 'gemini-call-1');
    expect(response['name'], 'echo');
    expect(response['response'], {
      'output': {'echo': 'hello'},
    });
  });

  test(
    'groups parallel function responses into one Gemini user turn',
    () async {
      final transport = _QueueTransport([
        {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'functionCall': {
                      'id': 'call-1',
                      'name': 'echo',
                      'args': {'value': 'one'},
                    },
                  },
                  {
                    'functionCall': {'id': 'call-2', 'name': 'echo'},
                  },
                ],
              },
            },
          ],
        },
        {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'Done'},
                ],
              },
            },
          ],
        },
      ]);

      await AgentLoop(
        model: GeminiModel(transport: transport),
        tools: [_EchoTool()],
      ).run('Go');

      final contents = transport.requests.last['contents']! as List;
      final responseParts = (contents.last as Map)['parts'] as List;
      expect(responseParts, hasLength(2));
      expect(
        responseParts.map(
          (part) => ((part as Map)['functionResponse'] as Map)['id'],
        ),
        ['call-1', 'call-2'],
      );
    },
  );

  test('reports prompt blocking without fabricating a model turn', () async {
    final model = GeminiModel(
      transport: _QueueTransport([
        {
          'promptFeedback': {'blockReason': 'SAFETY'},
        },
      ]),
    );

    await expectLater(
      model.nextTurn(messages: [AgentMessage.user('blocked')], tools: const []),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('SAFETY'),
        ),
      ),
    );
  });

  test('HTTP transport sends the key only in the header', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = server.first.then((request) async {
      final body = await utf8.decoder.bind(request).join();
      final result = (
        path: request.uri.path,
        query: request.uri.query,
        key: request.headers.value('x-goog-api-key'),
        body: jsonDecode(body),
      );
      request.response
        ..headers.contentType = ContentType.json
        ..write('{"candidates":[]}');
      await request.response.close();
      return result;
    });
    final transport = GeminiHttpTransport(
      apiKey: 'test-secret-key',
      apiEndpoint: Uri.parse('http://localhost:${server.port}/v1beta/'),
    );

    final response = await transport.generateContent(
      model: 'gemini-test',
      request: {
        'contents': [
          {
            'parts': [
              {'text': 'hello'},
            ],
          },
        ],
      },
    );
    final request = await received;

    expect(response['candidates'], isEmpty);
    expect(request.path, '/v1beta/models/gemini-test:generateContent');
    expect(request.query, isEmpty);
    expect(request.key, 'test-secret-key');
    expect(request.body, isA<Map>());
  });
}

final class _QueueTransport implements GeminiTransport {
  _QueueTransport(this._responses);

  final List<JsonMap> _responses;
  final requests = <JsonMap>[];
  final models = <String>[];

  @override
  Future<JsonMap> generateContent({
    required String model,
    required JsonMap request,
  }) async {
    models.add(model);
    requests.add(request);
    return _responses.removeAt(0);
  }
}

final class _EchoTool implements Tool {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'echo',
    description: 'Echo a value.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'value': {'type': 'string'},
      },
      'additionalProperties': false,
    },
  );

  @override
  Object? call(
    JsonMap arguments, {
    CancellationToken? cancellationToken,
    ToolOutputSink? onOutput,
  }) => {'echo': arguments['value']};
}
