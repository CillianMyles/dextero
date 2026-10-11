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

abstract class SpokenReply
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  SpokenReply._({
    required this.entryId,
    required this.audio,
    required this.mimeType,
    required this.engine,
    required this.truncated,
  });

  factory SpokenReply({
    required String entryId,
    required _i2.ByteData audio,
    required String mimeType,
    required String engine,
    required bool truncated,
  }) = _SpokenReplyImpl;

  factory SpokenReply.fromJson(Map<String, dynamic> jsonSerialization) {
    return SpokenReply(
      entryId: jsonSerialization['entryId'] as String,
      audio: _i1.ByteDataJsonExtension.fromJson(jsonSerialization['audio']),
      mimeType: jsonSerialization['mimeType'] as String,
      engine: jsonSerialization['engine'] as String,
      truncated: _i1.BoolJsonExtension.fromJson(jsonSerialization['truncated']),
    );
  }

  String entryId;

  _i2.ByteData audio;

  String mimeType;

  String engine;

  bool truncated;

  /// Returns a shallow copy of this [SpokenReply]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  SpokenReply copyWith({
    String? entryId,
    _i2.ByteData? audio,
    String? mimeType,
    String? engine,
    bool? truncated,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'SpokenReply',
      'entryId': entryId,
      'audio': audio.toJson(),
      'mimeType': mimeType,
      'engine': engine,
      'truncated': truncated,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'SpokenReply',
      'entryId': entryId,
      'audio': audio.toJson(),
      'mimeType': mimeType,
      'engine': engine,
      'truncated': truncated,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _SpokenReplyImpl extends SpokenReply {
  _SpokenReplyImpl({
    required String entryId,
    required _i2.ByteData audio,
    required String mimeType,
    required String engine,
    required bool truncated,
  }) : super._(
         entryId: entryId,
         audio: audio,
         mimeType: mimeType,
         engine: engine,
         truncated: truncated,
       );

  /// Returns a shallow copy of this [SpokenReply]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  SpokenReply copyWith({
    String? entryId,
    _i2.ByteData? audio,
    String? mimeType,
    String? engine,
    bool? truncated,
  }) {
    return SpokenReply(
      entryId: entryId ?? this.entryId,
      audio: audio ?? this.audio.clone(),
      mimeType: mimeType ?? this.mimeType,
      engine: engine ?? this.engine,
      truncated: truncated ?? this.truncated,
    );
  }
}
