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
}
