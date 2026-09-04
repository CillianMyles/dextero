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

enum ChatEntryStatus implements _i1.SerializableModel {
  submitted,
  queued,
  pending,
  running,
  warning,
  approved,
  completed,
  failed,
  cancelled;

  static ChatEntryStatus fromJson(String name) {
    switch (name) {
      case 'submitted':
        return ChatEntryStatus.submitted;
      case 'queued':
        return ChatEntryStatus.queued;
      case 'pending':
        return ChatEntryStatus.pending;
      case 'running':
        return ChatEntryStatus.running;
      case 'warning':
        return ChatEntryStatus.warning;
      case 'approved':
        return ChatEntryStatus.approved;
      case 'completed':
        return ChatEntryStatus.completed;
      case 'failed':
        return ChatEntryStatus.failed;
      case 'cancelled':
        return ChatEntryStatus.cancelled;
      default:
        throw ArgumentError(
          'Value "$name" cannot be converted to "ChatEntryStatus"',
        );
    }
  }

  @override
  String toJson() => name;

  @override
  String toString() => name;
}
