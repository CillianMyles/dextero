import 'package:dextero_core/dextero_core.dart';

/// Process-local dependencies used by Serverpod endpoint instances.
abstract final class ChatRuntime {
  static ChatService? _service;
  static String? _conversationId;
  static String? _modelProvider;
  static String? _modelName;

  static ChatService get service =>
      _service ?? (throw StateError('The chat runtime is not initialized.'));

  static String get conversationId =>
      _conversationId ??
      (throw StateError('The chat runtime is not initialized.'));

  static String get modelProvider =>
      _modelProvider ??
      (throw StateError('The chat runtime is not initialized.'));

  static String get modelName =>
      _modelName ?? (throw StateError('The chat runtime is not initialized.'));

  static void configure({
    required ChatService chatService,
    required String defaultConversationId,
    String modelProvider = 'codex',
    String modelName = 'default',
  }) {
    if (defaultConversationId.trim().isEmpty) {
      throw ArgumentError.value(
        defaultConversationId,
        'defaultConversationId',
        'must not be empty',
      );
    }
    if (modelProvider.trim().isEmpty) {
      throw ArgumentError.value(
        modelProvider,
        'modelProvider',
        'must not be empty',
      );
    }
    if (modelName.trim().isEmpty) {
      throw ArgumentError.value(modelName, 'modelName', 'must not be empty');
    }
    _service = chatService;
    _conversationId = defaultConversationId;
    _modelProvider = modelProvider;
    _modelName = modelName;
  }
}
