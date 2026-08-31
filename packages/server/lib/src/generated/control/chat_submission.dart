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

import 'package:serverpod/serverpod.dart' as _i1;
import '../control/chat_entry.dart' as _i2;
import 'package:dextero_server/src/generated/protocol.dart' as _i3;

abstract class ChatSubmission
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  ChatSubmission._({
    required this.conversationId,
    required this.runId,
    required this.correlationId,
    required this.userEntry,
  });

  factory ChatSubmission({
    required String conversationId,
    required String runId,
    required String correlationId,
    required _i2.ChatEntry userEntry,
  }) = _ChatSubmissionImpl;

  factory ChatSubmission.fromJson(Map<String, dynamic> jsonSerialization) {
    return ChatSubmission(
      conversationId: jsonSerialization['conversationId'] as String,
      runId: jsonSerialization['runId'] as String,
      correlationId: jsonSerialization['correlationId'] as String,
      userEntry: _i3.Protocol().deserialize<_i2.ChatEntry>(
        jsonSerialization['userEntry'],
      ),
    );
  }

  String conversationId;

  String runId;

  String correlationId;

  _i2.ChatEntry userEntry;

  /// Returns a shallow copy of this [ChatSubmission]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  ChatSubmission copyWith({
    String? conversationId,
    String? runId,
    String? correlationId,
    _i2.ChatEntry? userEntry,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'ChatSubmission',
      'conversationId': conversationId,
      'runId': runId,
      'correlationId': correlationId,
      'userEntry': userEntry.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'ChatSubmission',
      'conversationId': conversationId,
      'runId': runId,
      'correlationId': correlationId,
      'userEntry': userEntry.toJsonForProtocol(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _ChatSubmissionImpl extends ChatSubmission {
  _ChatSubmissionImpl({
    required String conversationId,
    required String runId,
    required String correlationId,
    required _i2.ChatEntry userEntry,
  }) : super._(
         conversationId: conversationId,
         runId: runId,
         correlationId: correlationId,
         userEntry: userEntry,
       );

  /// Returns a shallow copy of this [ChatSubmission]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  ChatSubmission copyWith({
    String? conversationId,
    String? runId,
    String? correlationId,
    _i2.ChatEntry? userEntry,
  }) {
    return ChatSubmission(
      conversationId: conversationId ?? this.conversationId,
      runId: runId ?? this.runId,
      correlationId: correlationId ?? this.correlationId,
      userEntry: userEntry ?? this.userEntry.copyWith(),
    );
  }
}
