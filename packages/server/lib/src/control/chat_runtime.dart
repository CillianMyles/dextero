import 'dart:async';
import 'dart:typed_data';

import 'package:dextero_core/dextero_core.dart';

typedef ModelSelector = Future<void> Function(String modelName);

/// Process-local dependencies used by Serverpod endpoint instances.
abstract final class ChatRuntime {
  static ChatService? _service;
  static VoiceService? _voice;
  static String? _conversationId;
  static String? _modelProvider;
  static String? _modelName;
  static List<String>? _availableModels;
  static ModelSelector? _modelSelector;
  static List<AgentModelOption> _modelOptions = [];
  static bool _qualifiedSelection = false;

  static List<AgentModelOption> get modelOptions => _modelOptions;
  static Future<void> _operationLock = Future.value();

  static ChatService get service =>
      _service ?? (throw StateError('The chat runtime is not initialized.'));

  static VoiceService get voice =>
      _voice ?? (throw StateError('The chat runtime is not initialized.'));

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
    List<AgentModelOption>? modelOptions,
    VoiceService? voiceService,
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
    final options = List<AgentModelOption>.unmodifiable(
      modelOptions ??
          [
            for (final model in models)
              AgentModelOption(
                provider: AgentProvider.values.byName(modelProvider),
                modelName: model,
              ),
          ],
    );
    if (!options.any(
          (option) =>
              option.provider.name == modelProvider &&
              option.modelName == modelName,
        ) ||
        options.map((option) => option.id).toSet().length != options.length ||
        options.any((option) => option.modelName.trim().isEmpty)) {
      throw ArgumentError(
        'Model options must be unique and contain the selected combination.',
      );
    }
    _modelOptions = options;
    _qualifiedSelection = modelOptions != null;
    _service = chatService;
    _voice = voiceService ?? VoiceService(store: chatService.store);
    _conversationId = defaultConversationId;
    _modelProvider = modelProvider;
    _modelName = modelName;
    _availableModels = models;
    _modelSelector = modelSelector;
    _operationLock = Future.value();
  }

  static Future<void> selectModel(
    String modelName,
  ) => _withOperationLock(() async {
    final normalized = modelName.trim();
    final matches = modelOptions
        .where(
          (option) => option.id == normalized || option.modelName == normalized,
        )
        .toList();
    if (matches.length != 1) {
      throw ArgumentError.value(
        modelName,
        'modelName',
        'must identify one of ${modelOptions.map((option) => option.id).join(', ')}',
      );
    }
    final selected = matches.single;
    if (selected.modelName == ChatRuntime.modelName &&
        selected.provider.name == ChatRuntime.modelProvider) {
      return;
    }
    final selector = _modelSelector;
    if (selector == null) {
      throw StateError('Model selection is not available on this host.');
    }
    await selector(_qualifiedSelection ? selected.id : selected.modelName);
    _modelName = selected.modelName;
    _modelProvider = selected.provider.name;
    _availableModels = List.unmodifiable(
      modelOptions
          .where((option) => option.provider == selected.provider)
          .map((option) => option.modelName),
    );
  });

  static Future<ChatSubmission> submit({
    required String conversationId,
    required String message,
    required String modelName,
    required String modelProvider,
    String? correlationId,
  }) => _withOperationLock(() async {
    _ensureSelectedModel(modelName, modelProvider);
    return service.submit(
      conversationId: conversationId,
      message: message,
      correlationId: correlationId,
    );
  });

  /// Transcribes push-to-talk audio, then accepts the transcript as an
  /// ordinary message in the same conversation.
  static Future<ChatSubmission> submitVoice({
    required String conversationId,
    required Uint8List audio,
    required String mimeType,
    required String modelName,
    required String modelProvider,
    String? correlationId,
  }) async {
    _ensureSelectedModel(modelName, modelProvider);
    if (await service.store.conversation(conversationId) == null) {
      throw StateError('Unknown conversation: $conversationId');
    }
    if (service.hasActiveRun(conversationId)) {
      throw StateError('A response is already running for this conversation.');
    }
    final transcript = await voice.transcribe(
      SpeechAudio(bytes: audio, mimeType: mimeType),
    );
    return _withOperationLock(() async {
      _ensureSelectedModel(modelName, modelProvider);
      return service.submit(
        conversationId: conversationId,
        message: transcript.text,
        correlationId: correlationId,
        modality: ChatModality.voice,
        transcriptionEngine: transcript.engine,
      );
    });
  }

  static void _ensureSelectedModel(String modelName, String modelProvider) {
    if (modelName != ChatRuntime.modelName ||
        modelProvider != ChatRuntime.modelProvider) {
      throw StateError(
        'The selected model changed to ${ChatRuntime.modelProvider}:${ChatRuntime.modelName}. '
        'Refresh the conversation before submitting.',
      );
    }
  }

  static Future<T> _withOperationLock<T>(Future<T> Function() action) async {
    final previous = _operationLock;
    final completer = Completer<void>();
    _operationLock = completer.future;
    await previous;
    try {
      return await action();
    } finally {
      completer.complete();
    }
  }
}
