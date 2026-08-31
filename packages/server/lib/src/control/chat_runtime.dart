import 'package:dextero_core/dextero_core.dart';

/// Process-local dependencies used by Serverpod endpoint instances.
abstract final class ChatRuntime {
  static ChatService? _service;
  static String? _conversationId;

  static ChatService get service =>
      _service ?? (throw StateError('The chat runtime is not initialized.'));

  static String get conversationId =>
      _conversationId ??
      (throw StateError('The chat runtime is not initialized.'));

  static void configure({
    required ChatService chatService,
    required String defaultConversationId,
  }) {
    if (defaultConversationId.trim().isEmpty) {
      throw ArgumentError.value(
        defaultConversationId,
        'defaultConversationId',
        'must not be empty',
      );
    }
    _service = chatService;
    _conversationId = defaultConversationId;
  }
}
