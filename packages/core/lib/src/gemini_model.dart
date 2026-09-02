import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'cancellation.dart';
import 'model.dart';
import 'tool.dart';

const defaultGeminiModel = 'gemini-3.7-flash';

abstract interface class GeminiTransport {
  Future<JsonMap> generateContent({
    required String model,
    required JsonMap request,
    CancellationToken? cancellationToken,
  });
}

/// Sends Gemini requests without placing the API key in the request URL.
final class GeminiHttpTransport implements GeminiTransport {
  GeminiHttpTransport({
    required String apiKey,
    Uri? apiEndpoint,
    this.timeout = const Duration(minutes: 5),
    this.maxResponseBytes = 4 * 1024 * 1024,
  }) : _apiKey = _validatedApiKey(apiKey),
       _apiEndpoint = _normalizeEndpoint(
         apiEndpoint ??
             Uri.parse('https://generativelanguage.googleapis.com/v1beta/'),
       ) {
    if (maxResponseBytes < 1) {
      throw ArgumentError.value(
        maxResponseBytes,
        'maxResponseBytes',
        'must be positive',
      );
    }
  }

  final String _apiKey;
  final Uri _apiEndpoint;
  final Duration timeout;
  final int maxResponseBytes;

  @override
  Future<JsonMap> generateContent({
    required String model,
    required JsonMap request,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    final uri = _apiEndpoint.resolve(
      'models/${Uri.encodeComponent(model)}:generateContent',
    );
    final client = HttpClient();
    try {
      final operation = _send(client, uri, request);
      if (cancellationToken == null) return await operation;
      try {
        return await Future.any([
          operation,
          cancellationToken.whenCancelled.then<JsonMap>((_) {
            client.close(force: true);
            throw const RunCancelledException();
          }),
        ]);
      } on Object {
        cancellationToken.throwIfCancellationRequested();
        rethrow;
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<JsonMap> _send(HttpClient client, Uri uri, JsonMap request) async {
    final encoded = utf8.encode(jsonEncode(request));
    final httpRequest = await client.postUrl(uri).timeout(timeout);
    httpRequest.headers
      ..contentType = ContentType.json
      ..set('x-goog-api-key', _apiKey)
      ..contentLength = encoded.length;
    httpRequest.add(encoded);
    final response = await httpRequest.close().timeout(timeout);
    final bytes = <int>[];
    await for (final chunk in response.timeout(timeout)) {
      if (bytes.length + chunk.length > maxResponseBytes) {
        throw const FormatException('Gemini response exceeded size limit.');
      }
      bytes.addAll(chunk);
    }
    final body = utf8.decode(bytes);
    final decoded = body.isEmpty ? null : jsonDecode(body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GeminiApiException(
        statusCode: response.statusCode,
        message: _apiErrorMessage(decoded),
      );
    }
    if (decoded is! Map) {
      throw const FormatException('Gemini returned non-object JSON.');
    }
    return decoded.cast<String, Object?>();
  }

  static String _validatedApiKey(String value) {
    final key = value.trim();
    if (key.isEmpty) {
      throw ArgumentError.value(value, 'apiKey', 'must not be empty');
    }
    return key;
  }

  static Uri _normalizeEndpoint(Uri endpoint) {
    if (!endpoint.hasScheme || endpoint.host.isEmpty) {
      throw ArgumentError.value(
        endpoint,
        'apiEndpoint',
        'must be an absolute HTTP(S) URI',
      );
    }
    if (!{'http', 'https'}.contains(endpoint.scheme)) {
      throw ArgumentError.value(
        endpoint,
        'apiEndpoint',
        'must use HTTP or HTTPS',
      );
    }
    final path = endpoint.path.endsWith('/')
        ? endpoint.path
        : '${endpoint.path}/';
    return endpoint.replace(path: path, query: null, fragment: null);
  }

  static String _apiErrorMessage(Object? decoded) {
    if (decoded is Map && decoded['error'] is Map) {
      final error = decoded['error']! as Map;
      if (error['message'] is String) return error['message']! as String;
      if (error['status'] is String) return error['status']! as String;
    }
    return 'The Gemini API rejected the request.';
  }
}

final class GeminiApiException implements Exception {
  const GeminiApiException({required this.statusCode, required this.message});

  final int statusCode;
  final String message;

  @override
  String toString() => 'Gemini API request failed (HTTP $statusCode): $message';
}

/// Gemini GenerateContent adapter for Dextero's provider-neutral model seam.
final class GeminiModel implements AgentModel {
  GeminiModel({
    required GeminiTransport transport,
    this.model = defaultGeminiModel,
    this.systemInstruction =
        'You are driving the Dextero workspace harness. Use the provided '
        'tools for file and command operations. Use run_command for normal '
        'CLI execution and run_shell only when shell syntax is required.',
  }) : _transport = transport {
    if (model.trim().isEmpty) {
      throw ArgumentError.value(model, 'model', 'must not be empty');
    }
  }

  final GeminiTransport _transport;
  final String model;
  final String systemInstruction;

  @override
  Future<ModelTurn> nextTurn({
    required List<AgentMessage> messages,
    required List<ToolDefinition> tools,
    CancellationToken? cancellationToken,
  }) async {
    if (messages.isEmpty) {
      throw ArgumentError.value(messages, 'messages', 'must not be empty');
    }
    final request = <String, Object?>{
      'contents': _encodeMessages(messages),
      if (systemInstruction.trim().isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': systemInstruction},
          ],
        },
      if (tools.isNotEmpty)
        'tools': [
          {
            'functionDeclarations': [
              for (final tool in tools)
                {
                  'name': tool.name,
                  'description': tool.description,
                  'parametersJsonSchema': tool.inputSchema,
                },
            ],
          },
        ],
    };
    final response = await _transport.generateContent(
      model: model,
      request: request,
      cancellationToken: cancellationToken,
    );
    return _decodeTurn(response, messages.length);
  }

  List<JsonMap> _encodeMessages(List<AgentMessage> messages) {
    final callsById = <String, ToolCall>{
      for (final message in messages)
        for (final call in message.toolCalls) call.id: call,
    };
    final contents = <JsonMap>[];
    var index = 0;
    while (index < messages.length) {
      final message = messages[index];
      switch (message.role) {
        case MessageRole.user:
          contents.add({
            'role': 'user',
            'parts': [
              {'text': message.content ?? ''},
            ],
          });
          index++;
        case MessageRole.assistant:
          final parts = <JsonMap>[];
          if (message.content case final content? when content.isNotEmpty) {
            parts.add({'text': content});
          }
          for (final call in message.toolCalls) {
            final apiCallId = call.providerMetadata['geminiApiCallId'];
            final part = <String, Object?>{
              'functionCall': {
                if (apiCallId is String) 'id': apiCallId,
                'name': call.name,
                'args': call.arguments,
              },
            };
            if (call.providerMetadata['geminiThoughtSignature']
                case final String signature) {
              part['thoughtSignature'] = signature;
            }
            parts.add(part);
          }
          contents.add({'role': 'model', 'parts': parts});
          index++;
        case MessageRole.tool:
          final parts = <JsonMap>[];
          while (index < messages.length &&
              messages[index].role == MessageRole.tool) {
            final result = messages[index].toolResult;
            if (result == null) {
              throw const FormatException('Tool message omitted its result.');
            }
            final call = callsById[result.callId];
            if (call == null) {
              throw FormatException(
                'Tool result has no matching call: ${result.callId}',
              );
            }
            final apiCallId = call.providerMetadata['geminiApiCallId'];
            parts.add({
              'functionResponse': {
                if (apiCallId is String) 'id': apiCallId,
                'name': call.name,
                'response': result.isError
                    ? {'error': _jsonValue(result.content)}
                    : {'output': _jsonValue(result.content)},
              },
            });
            index++;
          }
          contents.add({'role': 'user', 'parts': parts});
      }
    }
    return contents;
  }

  ModelTurn _decodeTurn(JsonMap response, int messageCount) {
    final candidates = response['candidates'];
    if (candidates is! List || candidates.isEmpty || candidates.first is! Map) {
      throw FormatException(
        'Gemini returned no candidates${_promptBlockDetail(response)}.',
      );
    }
    final candidate = candidates.first as Map;
    final content = candidate['content'];
    if (content is! Map || content['parts'] is! List) {
      throw FormatException(
        'Gemini candidate omitted content parts${_finishDetail(candidate)}.',
      );
    }

    final text = StringBuffer();
    final toolCalls = <ToolCall>[];
    var partIndex = 0;
    for (final rawPart in content['parts']! as List) {
      if (rawPart is! Map) {
        partIndex++;
        continue;
      }
      if (rawPart['thought'] != true && rawPart['text'] is String) {
        text.write(rawPart['text']! as String);
      }
      final rawCall = rawPart['functionCall'];
      if (rawCall is Map) {
        final name = rawCall['name'];
        final rawArguments = rawCall['args'];
        if (name is! String ||
            name.isEmpty ||
            (rawArguments != null && rawArguments is! Map)) {
          throw const FormatException(
            'Gemini returned a malformed function call.',
          );
        }
        final arguments = rawArguments == null
            ? const <String, Object?>{}
            : (rawArguments as Map).cast<String, Object?>();
        final rawId = rawCall['id'];
        final apiCallId = rawId is String && rawId.isNotEmpty ? rawId : null;
        toolCalls.add(
          ToolCall(
            id: apiCallId ?? 'gemini-call-$messageCount-$partIndex',
            name: name,
            arguments: arguments,
            providerMetadata: {
              'geminiApiCallId': ?apiCallId,
              if (rawPart['thoughtSignature'] case final String signature)
                'geminiThoughtSignature': signature,
            },
          ),
        );
      }
      partIndex++;
    }
    final output = text.toString();
    if (output.trim().isEmpty && toolCalls.isEmpty) {
      throw FormatException(
        'Gemini returned neither text nor function calls'
        '${_finishDetail(candidate)}.',
      );
    }
    return ModelTurn(
      content: output.isEmpty ? null : output,
      toolCalls: List.unmodifiable(toolCalls),
    );
  }

  String _promptBlockDetail(JsonMap response) {
    final feedback = response['promptFeedback'];
    if (feedback is Map && feedback['blockReason'] != null) {
      return ' (block reason: ${feedback['blockReason']})';
    }
    return '';
  }

  String _finishDetail(Map candidate) => candidate['finishReason'] == null
      ? ''
      : ' (finish reason: ${candidate['finishReason']})';

  Object? _jsonValue(Object? value) => switch (value) {
    null || bool() || num() || String() => value,
    List() => value.map(_jsonValue).toList(growable: false),
    Map() => {
      for (final entry in value.entries)
        entry.key.toString(): _jsonValue(entry.value),
    },
    _ => value.toString(),
  };
}
