import 'chat_history.dart';

/// An agent failure with a stable category and a message safe to show users.
abstract interface class CategorizedAgentFailure implements Exception {
  ChatErrorCode get errorCode;
  String get userMessage;
}
