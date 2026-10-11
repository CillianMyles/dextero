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
import '../control/chat_event_family.dart' as _i2;
import '../control/chat_modality.dart' as _i3;
import '../control/chat_entry_kind.dart' as _i4;
import '../control/chat_entry_status.dart' as _i5;
import '../control/chat_entry_source.dart' as _i6;

abstract class ChatEntry
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
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
    this.approvalId,
    _i3.ChatModality? modality,
    this.transcriptionEngine,
  }) : eventVersion = eventVersion ?? 1,
       family = family ?? _i2.ChatEventFamily.task,
       modality = modality ?? _i3.ChatModality.text;

  factory ChatEntry({
    int? eventVersion,
    _i2.ChatEventFamily? family,
    required String conversationId,
    required String entryId,
    required int sequence,
    required _i4.ChatEntryKind kind,
    required _i5.ChatEntryStatus status,
    required String content,
    required DateTime createdAt,
    required String correlationId,
    required _i6.ChatEntrySource source,
    required bool truncated,
    String? runId,
    String? toolCallId,
    String? toolName,
    String? approvalId,
    _i3.ChatModality? modality,
    String? transcriptionEngine,
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
      kind: _i4.ChatEntryKind.fromJson((jsonSerialization['kind'] as String)),
      status: _i5.ChatEntryStatus.fromJson(
        (jsonSerialization['status'] as String),
      ),
      content: jsonSerialization['content'] as String,
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      correlationId: jsonSerialization['correlationId'] as String,
      source: _i6.ChatEntrySource.fromJson(
        (jsonSerialization['source'] as String),
      ),
      truncated: _i1.BoolJsonExtension.fromJson(jsonSerialization['truncated']),
      runId: jsonSerialization['runId'] as String?,
      toolCallId: jsonSerialization['toolCallId'] as String?,
      toolName: jsonSerialization['toolName'] as String?,
      approvalId: jsonSerialization['approvalId'] as String?,
      modality: jsonSerialization['modality'] == null
          ? null
          : _i3.ChatModality.fromJson(
              (jsonSerialization['modality'] as String),
            ),
      transcriptionEngine: jsonSerialization['transcriptionEngine'] as String?,
    );
  }

  int eventVersion;

  _i2.ChatEventFamily family;

  String conversationId;

  String entryId;

  int sequence;

  _i4.ChatEntryKind kind;

  _i5.ChatEntryStatus status;

  String content;

  DateTime createdAt;

  String correlationId;

  _i6.ChatEntrySource source;

  bool truncated;

  String? runId;

  String? toolCallId;

  String? toolName;

  String? approvalId;

  _i3.ChatModality modality;

  String? transcriptionEngine;

  /// Returns a shallow copy of this [ChatEntry]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  ChatEntry copyWith({
    int? eventVersion,
    _i2.ChatEventFamily? family,
    String? conversationId,
    String? entryId,
    int? sequence,
    _i4.ChatEntryKind? kind,
    _i5.ChatEntryStatus? status,
    String? content,
    DateTime? createdAt,
    String? correlationId,
    _i6.ChatEntrySource? source,
    bool? truncated,
    String? runId,
    String? toolCallId,
    String? toolName,
    String? approvalId,
    _i3.ChatModality? modality,
    String? transcriptionEngine,
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
      if (approvalId != null) 'approvalId': approvalId,
      'modality': modality.toJson(),
      if (transcriptionEngine != null)
        'transcriptionEngine': transcriptionEngine,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
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
      if (approvalId != null) 'approvalId': approvalId,
      'modality': modality.toJson(),
      if (transcriptionEngine != null)
        'transcriptionEngine': transcriptionEngine,
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
    required _i4.ChatEntryKind kind,
    required _i5.ChatEntryStatus status,
    required String content,
    required DateTime createdAt,
    required String correlationId,
    required _i6.ChatEntrySource source,
    required bool truncated,
    String? runId,
    String? toolCallId,
    String? toolName,
    String? approvalId,
    _i3.ChatModality? modality,
    String? transcriptionEngine,
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
         approvalId: approvalId,
         modality: modality,
         transcriptionEngine: transcriptionEngine,
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
    _i4.ChatEntryKind? kind,
    _i5.ChatEntryStatus? status,
    String? content,
    DateTime? createdAt,
    String? correlationId,
    _i6.ChatEntrySource? source,
    bool? truncated,
    Object? runId = _Undefined,
    Object? toolCallId = _Undefined,
    Object? toolName = _Undefined,
    Object? approvalId = _Undefined,
    _i3.ChatModality? modality,
    Object? transcriptionEngine = _Undefined,
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
      approvalId: approvalId is String? ? approvalId : this.approvalId,
      modality: modality ?? this.modality,
      transcriptionEngine: transcriptionEngine is String?
          ? transcriptionEngine
          : this.transcriptionEngine,
    );
  }
}
