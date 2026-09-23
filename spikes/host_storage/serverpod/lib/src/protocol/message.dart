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
import 'package:serverpod_client/serverpod_client.dart' as _isc;

abstract class Message
    implements _isc.SerializableModel, _isc.ProtocolSerialization {
  Message._({
    this.id,
    required this.conversationId,
    required this.sequence,
    required this.content,
    String? source,
  }) : source = source ?? 'user';

  factory Message({
    int? id,
    required int conversationId,
    required int sequence,
    required String content,
    String? source,
  }) = _MessageImpl;

  factory Message.fromJson(Map<String, dynamic> jsonSerialization) {
    return Message(
      id: jsonSerialization['id'] as int?,
      conversationId: jsonSerialization['conversationId'] as int,
      sequence: jsonSerialization['sequence'] as int,
      content: jsonSerialization['content'] as String,
      source: jsonSerialization['source'] as String?,
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  int? id;

  int conversationId;

  int sequence;

  String content;

  String source;

  /// Returns a shallow copy of this [Message]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  Message copyWith({
    int? id,
    int? conversationId,
    int? sequence,
    String? content,
    String? source,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'Message',
      if (id != null) 'id': id,
      'conversationId': conversationId,
      'sequence': sequence,
      'content': content,
      'source': source,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'Message',
      if (id != null) 'id': id,
      'conversationId': conversationId,
      'sequence': sequence,
      'content': content,
      'source': source,
    };
  }

  @override
  String toString() {
    return _isc.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _MessageImpl extends Message {
  _MessageImpl({
    int? id,
    required int conversationId,
    required int sequence,
    required String content,
    String? source,
  }) : super._(
         id: id,
         conversationId: conversationId,
         sequence: sequence,
         content: content,
         source: source,
       );

  /// Returns a shallow copy of this [Message]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  @override
  Message copyWith({
    Object? id = _Undefined,
    int? conversationId,
    int? sequence,
    String? content,
    String? source,
  }) {
    return Message(
      id: id is int? ? id : this.id,
      conversationId: conversationId ?? this.conversationId,
      sequence: sequence ?? this.sequence,
      content: content ?? this.content,
      source: source ?? this.source,
    );
  }
}
