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
import '../control/chat_event_family.dart' as _i2;
import '../control/chat_entry_kind.dart' as _i3;
import '../control/chat_entry_status.dart' as _i4;
import '../control/chat_entry_source.dart' as _i5;

abstract class ChatEntry implements _i1.SerializableModel {
  ChatEntry._({
    int? eventVersion,
    _i2.ChatEventFamily? family,
    required this.conversationId,
    required this.entryId,
    required this.sequence,
    required this.kind,
    required this.status,
    required this.content,
    required this.createdAt,
    required this.correlationId,
    required this.source,
    required this.truncated,
    this.runId,
    this.toolCallId,
    this.toolName,
  }) : eventVersion = eventVersion ?? 1,
       family = family ?? _i2.ChatEventFamily.task;

  factory ChatEntry({
    int? eventVersion,
    _i2.ChatEventFamily? family,
    required String conversationId,
    required String entryId,
    required int sequence,
    required _i3.ChatEntryKind kind,
    required _i4.ChatEntryStatus status,
    required String content,
    required DateTime createdAt,
    required String correlationId,
    required _i5.ChatEntrySource source,
    required bool truncated,
    String? runId,
    String? toolCallId,
    String? toolName,
  }) = _ChatEntryImpl;

  factory ChatEntry.fromJson(Map<String, dynamic> jsonSerialization) {
    return ChatEntry(
      eventVersion: jsonSerialization['eventVersion'] as int?,
      family: jsonSerialization['family'] == null
          ? null
          : _i2.ChatEventFamily.fromJson(
              (jsonSerialization['family'] as String),
            ),
      conversationId: jsonSerialization['conversationId'] as String,
      entryId: jsonSerialization['entryId'] as String,
      sequence: jsonSerialization['sequence'] as int,
      kind: _i3.ChatEntryKind.fromJson((jsonSerialization['kind'] as String)),
      status: _i4.ChatEntryStatus.fromJson(
        (jsonSerialization['status'] as String),
      ),
      content: jsonSerialization['content'] as String,
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      correlationId: jsonSerialization['correlationId'] as String,
      source: _i5.ChatEntrySource.fromJson(
        (jsonSerialization['source'] as String),
      ),
      truncated: _i1.BoolJsonExtension.fromJson(jsonSerialization['truncated']),
      runId: jsonSerialization['runId'] as String?,
      toolCallId: jsonSerialization['toolCallId'] as String?,
      toolName: jsonSerialization['toolName'] as String?,
    );
  }

  int eventVersion;

  _i2.ChatEventFamily family;

  String conversationId;

  String entryId;

  int sequence;

  _i3.ChatEntryKind kind;

  _i4.ChatEntryStatus status;

  String content;

  DateTime createdAt;

  String correlationId;

  _i5.ChatEntrySource source;

  bool truncated;

  String? runId;

  String? toolCallId;

  String? toolName;

  /// Returns a shallow copy of this [ChatEntry]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  ChatEntry copyWith({
    int? eventVersion,
    _i2.ChatEventFamily? family,
    String? conversationId,
    String? entryId,
    int? sequence,
    _i3.ChatEntryKind? kind,
    _i4.ChatEntryStatus? status,
    String? content,
    DateTime? createdAt,
    String? correlationId,
    _i5.ChatEntrySource? source,
    bool? truncated,
    String? runId,
    String? toolCallId,
    String? toolName,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'ChatEntry',
      'eventVersion': eventVersion,
      'family': family.toJson(),
      'conversationId': conversationId,
      'entryId': entryId,
      'sequence': sequence,
      'kind': kind.toJson(),
      'status': status.toJson(),
      'content': content,
      'createdAt': createdAt.toJson(),
      'correlationId': correlationId,
      'source': source.toJson(),
      'truncated': truncated,
      if (runId != null) 'runId': runId,
      if (toolCallId != null) 'toolCallId': toolCallId,
      if (toolName != null) 'toolName': toolName,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _ChatEntryImpl extends ChatEntry {
  _ChatEntryImpl({
    int? eventVersion,
    _i2.ChatEventFamily? family,
    required String conversationId,
    required String entryId,
    required int sequence,
    required _i3.ChatEntryKind kind,
    required _i4.ChatEntryStatus status,
    required String content,
    required DateTime createdAt,
    required String correlationId,
    required _i5.ChatEntrySource source,
    required bool truncated,
    String? runId,
    String? toolCallId,
    String? toolName,
  }) : super._(
         eventVersion: eventVersion,
         family: family,
         conversationId: conversationId,
         entryId: entryId,
         sequence: sequence,
         kind: kind,
         status: status,
         content: content,
         createdAt: createdAt,
         correlationId: correlationId,
         source: source,
         truncated: truncated,
         runId: runId,
         toolCallId: toolCallId,
         toolName: toolName,
       );

  /// Returns a shallow copy of this [ChatEntry]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  ChatEntry copyWith({
    int? eventVersion,
    _i2.ChatEventFamily? family,
    String? conversationId,
    String? entryId,
    int? sequence,
    _i3.ChatEntryKind? kind,
    _i4.ChatEntryStatus? status,
    String? content,
    DateTime? createdAt,
    String? correlationId,
    _i5.ChatEntrySource? source,
    bool? truncated,
    Object? runId = _Undefined,
    Object? toolCallId = _Undefined,
    Object? toolName = _Undefined,
  }) {
    return ChatEntry(
      eventVersion: eventVersion ?? this.eventVersion,
      family: family ?? this.family,
      conversationId: conversationId ?? this.conversationId,
      entryId: entryId ?? this.entryId,
      sequence: sequence ?? this.sequence,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      correlationId: correlationId ?? this.correlationId,
      source: source ?? this.source,
      truncated: truncated ?? this.truncated,
      runId: runId is String? ? runId : this.runId,
      toolCallId: toolCallId is String? ? toolCallId : this.toolCallId,
      toolName: toolName is String? ? toolName : this.toolName,
    );
  }
}
