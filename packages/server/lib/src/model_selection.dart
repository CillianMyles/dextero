import 'protocol/protocol.dart';

/// Shared identity and CLI alias resolution for the advertised choices.
extension HostModelSelection on HostStatus {
  String get selectedModelId => '$modelProvider:$modelName';

  ModelOption? resolveModel(String value) {
    final matches = modelOptions
        .where((option) => option.id == value || option.modelName == value)
        .toList();
    return matches.length == 1 ? matches.single : null;
  }

  ModelOption? get selectedModelOption => resolveModel(selectedModelId);

  /// Provider, model, and credential source for the current selection.
  String get selectedModelSummary => switch (selectedModelOption) {
    final option? => '${option.label} · ${option.authSource}',
    null => '$modelProvider · $modelName',
  };
}

/// Client-side presentation shared by the Flutter app and terminal clients.
extension ChatEntryPresentation on ChatEntry {
  /// A short label for categorized failures, or null for generic errors.
  String? get errorCodeLabel => switch (errorCode) {
    ChatErrorCode.creditExhausted => 'Out of credit',
    ChatErrorCode.authenticationFailed => 'Key rejected',
    ChatErrorCode.rateLimited => 'Rate limited',
    null => null,
  };
}
