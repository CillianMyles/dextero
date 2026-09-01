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

enum ChatEventFamily implements _i1.SerializableModel {
  message,
  task,
  model,
  tool,
  approval,
  artifact,
  usage,
  warning,
  error;

  static ChatEventFamily fromJson(String name) {
    switch (name) {
      case 'message':
        return ChatEventFamily.message;
      case 'task':
        return ChatEventFamily.task;
      case 'model':
        return ChatEventFamily.model;
      case 'tool':
        return ChatEventFamily.tool;
      case 'approval':
        return ChatEventFamily.approval;
      case 'artifact':
        return ChatEventFamily.artifact;
      case 'usage':
        return ChatEventFamily.usage;
      case 'warning':
        return ChatEventFamily.warning;
      case 'error':
        return ChatEventFamily.error;
      default:
        throw ArgumentError(
          'Value "$name" cannot be converted to "ChatEventFamily"',
        );
    }
  }

  @override
  String toJson() => name;

  @override
  String toString() => name;
}
