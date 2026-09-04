/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters
// ignore_for_file: invalid_use_of_internal_member

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:serverpod_client/serverpod_client.dart' as _i1;

enum ChatEntryKind implements _i1.SerializableModel {
  userMessage,
  assistantMessage,
  assistantDelta,
  toolCall,
  toolOutput,
  toolResult,
  approval,
  lifecycle,
  error;

  static ChatEntryKind fromJson(String name) {
    switch (name) {
      case 'userMessage':
        return ChatEntryKind.userMessage;
      case 'assistantMessage':
        return ChatEntryKind.assistantMessage;
      case 'assistantDelta':
        return ChatEntryKind.assistantDelta;
      case 'toolCall':
        return ChatEntryKind.toolCall;
      case 'toolOutput':
        return ChatEntryKind.toolOutput;
      case 'toolResult':
        return ChatEntryKind.toolResult;
      case 'approval':
        return ChatEntryKind.approval;
      case 'lifecycle':
        return ChatEntryKind.lifecycle;
      case 'error':
        return ChatEntryKind.error;
      default:
        throw ArgumentError(
          'Value "$name" cannot be converted to "ChatEntryKind"',
        );
    }
  }

  @override
  String toJson() => name;

  @override
  String toString() => name;
}
