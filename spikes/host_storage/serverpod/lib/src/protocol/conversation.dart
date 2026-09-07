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

abstract class Conversation
    implements _isc.SerializableModel, _isc.ProtocolSerialization {
  Conversation._({this.id, required this.publicId, required this.nextSequence});

  factory Conversation({
    int? id,
    required String publicId,
    required int nextSequence,
  }) = _ConversationImpl;

  factory Conversation.fromJson(Map<String, dynamic> jsonSerialization) {
    return Conversation(
      id: jsonSerialization['id'] as int?,
      publicId: jsonSerialization['publicId'] as String,
      nextSequence: jsonSerialization['nextSequence'] as int,
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  int? id;

  String publicId;

  int nextSequence;

  /// Returns a shallow copy of this [Conversation]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  Conversation copyWith({int? id, String? publicId, int? nextSequence});
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'Conversation',
      if (id != null) 'id': id,
      'publicId': publicId,
      'nextSequence': nextSequence,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'Conversation',
      if (id != null) 'id': id,
      'publicId': publicId,
      'nextSequence': nextSequence,
    };
  }

  @override
  String toString() {
    return _isc.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _ConversationImpl extends Conversation {
  _ConversationImpl({
    int? id,
    required String publicId,
    required int nextSequence,
  }) : super._(id: id, publicId: publicId, nextSequence: nextSequence);

  /// Returns a shallow copy of this [Conversation]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  @override
  Conversation copyWith({
    Object? id = _Undefined,
    String? publicId,
    int? nextSequence,
  }) {
    return Conversation(
      id: id is int? ? id : this.id,
      publicId: publicId ?? this.publicId,
      nextSequence: nextSequence ?? this.nextSequence,
    );
  }
}
