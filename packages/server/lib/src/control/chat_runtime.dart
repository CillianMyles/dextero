import 'package:dextero_core/dextero_core.dart';

typedef ModelSelector = Future<void> Function(String modelName);

/// Process-local dependencies used by Serverpod endpoint instances.
abstract final class ChatRuntime {
  static ChatService? _service;
  static String? _conversationId;
  static String? _modelProvider;
  static String? _modelName;
  static List<String>? _availableModels;
  static ModelSelector? _modelSelector;

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

  static List<String> get availableModels =>
      _availableModels ??
      (throw StateError('The chat runtime is not initialized.'));

  static void configure({
    required ChatService chatService,
    required String defaultConversationId,
    String modelProvider = 'codex',
    String modelName = 'default',
    List<String>? availableModels,
    ModelSelector? modelSelector,
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
    final models = List<String>.unmodifiable(availableModels ?? [modelName]);
    if (models.isEmpty ||
        models.any((model) => model.trim().isEmpty) ||
        !models.contains(modelName)) {
      throw ArgumentError.value(
        availableModels,
        'availableModels',
        'must contain the selected non-empty model',
      );
    }
    _service = chatService;
    _conversationId = defaultConversationId;
    _modelProvider = modelProvider;
    _modelName = modelName;
    _availableModels = models;
    _modelSelector = modelSelector;
  }

  static Future<void> selectModel(String modelName) async {
    final normalized = modelName.trim();
    if (!availableModels.contains(normalized)) {
      throw ArgumentError.value(
        modelName,
        'modelName',
        'must be one of ${availableModels.join(', ')}',
      );
    }
    if (normalized == ChatRuntime.modelName) return;
    final selector = _modelSelector;
    if (selector == null) {
      throw StateError('Model selection is not available on this host.');
    }
    await selector(normalized);
    _modelName = normalized;
  }
}
