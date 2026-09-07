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

abstract class ChatSubmitRequest
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  ChatSubmitRequest._({
    required this.conversationId,
    required this.message,
    required this.modelName,
    this.correlationId,
    required this.modelProvider,
  });

  factory ChatSubmitRequest({
    required String conversationId,
    required String message,
    required String modelName,
    String? correlationId,
    required String modelProvider,
  }) = _ChatSubmitRequestImpl;

  factory ChatSubmitRequest.fromJson(Map<String, dynamic> jsonSerialization) {
    return ChatSubmitRequest(
      conversationId: jsonSerialization['conversationId'] as String,
      message: jsonSerialization['message'] as String,
      modelName: jsonSerialization['modelName'] as String,
      correlationId: jsonSerialization['correlationId'] as String?,
      modelProvider: jsonSerialization['modelProvider'] as String,
    );
  }

  String conversationId;

  String message;

  String modelName;

  String? correlationId;

  String modelProvider;

  /// Returns a shallow copy of this [ChatSubmitRequest]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  ChatSubmitRequest copyWith({
    String? conversationId,
    String? message,
    String? modelName,
    String? correlationId,
    String? modelProvider,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'ChatSubmitRequest',
      'conversationId': conversationId,
      'message': message,
      'modelName': modelName,
      if (correlationId != null) 'correlationId': correlationId,
      'modelProvider': modelProvider,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'ChatSubmitRequest',
      'conversationId': conversationId,
      'message': message,
      'modelName': modelName,
      if (correlationId != null) 'correlationId': correlationId,
      'modelProvider': modelProvider,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _ChatSubmitRequestImpl extends ChatSubmitRequest {
  _ChatSubmitRequestImpl({
    required String conversationId,
    required String message,
    required String modelName,
    String? correlationId,
    required String modelProvider,
  }) : super._(
         conversationId: conversationId,
         message: message,
         modelName: modelName,
         correlationId: correlationId,
         modelProvider: modelProvider,
       );

  /// Returns a shallow copy of this [ChatSubmitRequest]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  ChatSubmitRequest copyWith({
    String? conversationId,
    String? message,
    String? modelName,
    Object? correlationId = _Undefined,
    String? modelProvider,
  }) {
    return ChatSubmitRequest(
      conversationId: conversationId ?? this.conversationId,
      message: message ?? this.message,
      modelName: modelName ?? this.modelName,
      correlationId: correlationId is String?
          ? correlationId
          : this.correlationId,
      modelProvider: modelProvider ?? this.modelProvider,
    );
  }
}
