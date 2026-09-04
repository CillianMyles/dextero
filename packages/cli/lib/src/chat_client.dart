import 'dart:io';

import 'package:dextero_server/dextero_client.dart';

import 'controller_identity_store.dart';

abstract interface class TerminalChatClient {
  Future<HostStatus> status();

  Future<HostStatus> selectModel(String modelName);

  Future<List<ChatEntry>> history(String conversationId);

  Future<ChatSubmission> submit(ChatSubmitRequest request);

  Future<bool> cancelRun(String conversationId, String runId);

  Future<bool> approveWork(
    String conversationId,
    String runId,
    String approvalId,
  );

  Stream<ChatEntry> streamHistory(String conversationId, int afterSequence);

  Future<void> close();
}

final class ServerpodTerminalChatClient implements TerminalChatClient {
  ServerpodTerminalChatClient({
    required String serverUrl,
    required String token,
    Future<ControllerIdentity>? controller,
  }) : _controller =
           controller ??
           CliControllerIdentityStore.fromEnvironment(
             Platform.environment,
           ).load(Platform.environment) {
    final normalizedUrl = serverUrl.endsWith('/') ? serverUrl : '$serverUrl/';
    _client = Client(normalizedUrl)
      ..authKeyProvider = DexteroTokenAuthProvider(token);
  }

  late final Client _client;
  final Future<ControllerIdentity> _controller;

  @override
  Future<HostStatus> status() async =>
      _client.control.status(await _controller);

  @override
  Future<HostStatus> selectModel(String modelName) async =>
      _client.control.selectModel(await _controller, modelName);

  @override
  Future<List<ChatEntry>> history(String conversationId) async =>
      _client.control.history(await _controller, conversationId);

  @override
  Future<ChatSubmission> submit(ChatSubmitRequest request) async =>
      _client.control.submitMessage(await _controller, request);

  @override
  Future<bool> cancelRun(String conversationId, String runId) async =>
      _client.control.cancelRun(await _controller, conversationId, runId);

  @override
  Future<bool> approveWork(
    String conversationId,
    String runId,
    String approvalId,
  ) async => _client.control.approveWork(
    await _controller,
    conversationId,
    runId,
    approvalId,
  );

  @override
  Stream<ChatEntry> streamHistory(
    String conversationId,
    int afterSequence,
  ) async* {
    yield* _client.control.streamHistory(
      await _controller,
      conversationId,
      afterSequence,
    );
  }

  @override
  Future<void> close() async => _client.close();
}
