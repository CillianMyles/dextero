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
import 'dart:typed_data' as _i2;

abstract class VoiceSubmitRequest
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  VoiceSubmitRequest._({
    required this.conversationId,
    required this.audio,
    required this.mimeType,
    required this.modelName,
    required this.modelProvider,
    this.correlationId,
  });

  factory VoiceSubmitRequest({
    required String conversationId,
    required _i2.ByteData audio,
    required String mimeType,
    required String modelName,
    required String modelProvider,
    String? correlationId,
  }) = _VoiceSubmitRequestImpl;

  factory VoiceSubmitRequest.fromJson(Map<String, dynamic> jsonSerialization) {
    return VoiceSubmitRequest(
      conversationId: jsonSerialization['conversationId'] as String,
      audio: _i1.ByteDataJsonExtension.fromJson(jsonSerialization['audio']),
      mimeType: jsonSerialization['mimeType'] as String,
      modelName: jsonSerialization['modelName'] as String,
      modelProvider: jsonSerialization['modelProvider'] as String,
      correlationId: jsonSerialization['correlationId'] as String?,
    );
  }

  String conversationId;

  _i2.ByteData audio;

  String mimeType;

  String modelName;

  String modelProvider;

  String? correlationId;

  /// Returns a shallow copy of this [VoiceSubmitRequest]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  VoiceSubmitRequest copyWith({
    String? conversationId,
    _i2.ByteData? audio,
    String? mimeType,
    String? modelName,
    String? modelProvider,
    String? correlationId,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'VoiceSubmitRequest',
      'conversationId': conversationId,
      'audio': audio.toJson(),
      'mimeType': mimeType,
      'modelName': modelName,
      'modelProvider': modelProvider,
      if (correlationId != null) 'correlationId': correlationId,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'VoiceSubmitRequest',
      'conversationId': conversationId,
      'audio': audio.toJson(),
      'mimeType': mimeType,
      'modelName': modelName,
      'modelProvider': modelProvider,
      if (correlationId != null) 'correlationId': correlationId,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _VoiceSubmitRequestImpl extends VoiceSubmitRequest {
  _VoiceSubmitRequestImpl({
    required String conversationId,
    required _i2.ByteData audio,
    required String mimeType,
    required String modelName,
    required String modelProvider,
    String? correlationId,
  }) : super._(
         conversationId: conversationId,
         audio: audio,
         mimeType: mimeType,
         modelName: modelName,
         modelProvider: modelProvider,
         correlationId: correlationId,
       );

  /// Returns a shallow copy of this [VoiceSubmitRequest]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  VoiceSubmitRequest copyWith({
    String? conversationId,
    _i2.ByteData? audio,
    String? mimeType,
    String? modelName,
    String? modelProvider,
    Object? correlationId = _Undefined,
  }) {
    return VoiceSubmitRequest(
      conversationId: conversationId ?? this.conversationId,
      audio: audio ?? this.audio.clone(),
      mimeType: mimeType ?? this.mimeType,
      modelName: modelName ?? this.modelName,
      modelProvider: modelProvider ?? this.modelProvider,
      correlationId: correlationId is String?
          ? correlationId
          : this.correlationId,
    );
  }
}
