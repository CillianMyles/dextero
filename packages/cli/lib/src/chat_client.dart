import 'package:dextero_server/dextero_client.dart';

abstract interface class TerminalChatClient {
  Future<HostStatus> status();

  Future<List<ChatEntry>> history(String conversationId);

  Future<ChatSubmission> submit(ChatSubmitRequest request);

  Stream<ChatEntry> streamHistory(String conversationId, int afterSequence);

  Future<void> close();
}

final class ServerpodTerminalChatClient implements TerminalChatClient {
  ServerpodTerminalChatClient({
    required String serverUrl,
    required String token,
  }) {
    final normalizedUrl = serverUrl.endsWith('/') ? serverUrl : '$serverUrl/';
    _client = Client(normalizedUrl)
      ..authKeyProvider = DexteroTokenAuthProvider(token);
  }

  late final Client _client;

  @override
  Future<HostStatus> status() => _client.control.status();

  @override
  Future<List<ChatEntry>> history(String conversationId) =>
      _client.control.history(conversationId);

  @override
  Future<ChatSubmission> submit(ChatSubmitRequest request) =>
      _client.control.submitMessage(request);

  @override
  Stream<ChatEntry> streamHistory(String conversationId, int afterSequence) =>
      _client.control.streamHistory(conversationId, afterSequence);

  @override
  Future<void> close() async => _client.close();
}
