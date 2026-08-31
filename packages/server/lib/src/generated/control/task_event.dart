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
import '../control/task_event_kind.dart' as _i2;

abstract class TaskEvent
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  TaskEvent._({
    required this.taskId,
    required this.sequence,
    required this.kind,
    required this.message,
    required this.timestamp,
    required this.terminal,
  });

  factory TaskEvent({
    required String taskId,
    required int sequence,
    required _i2.TaskEventKind kind,
    required String message,
    required DateTime timestamp,
    required bool terminal,
  }) = _TaskEventImpl;

  factory TaskEvent.fromJson(Map<String, dynamic> jsonSerialization) {
    return TaskEvent(
      taskId: jsonSerialization['taskId'] as String,
      sequence: jsonSerialization['sequence'] as int,
      kind: _i2.TaskEventKind.fromJson((jsonSerialization['kind'] as String)),
      message: jsonSerialization['message'] as String,
      timestamp: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['timestamp'],
      ),
      terminal: _i1.BoolJsonExtension.fromJson(jsonSerialization['terminal']),
    );
  }

  String taskId;

  int sequence;

  _i2.TaskEventKind kind;

  String message;

  DateTime timestamp;

  bool terminal;

  /// Returns a shallow copy of this [TaskEvent]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  TaskEvent copyWith({
    String? taskId,
    int? sequence,
    _i2.TaskEventKind? kind,
    String? message,
    DateTime? timestamp,
    bool? terminal,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'TaskEvent',
      'taskId': taskId,
      'sequence': sequence,
      'kind': kind.toJson(),
      'message': message,
      'timestamp': timestamp.toJson(),
      'terminal': terminal,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'TaskEvent',
      'taskId': taskId,
      'sequence': sequence,
      'kind': kind.toJson(),
      'message': message,
      'timestamp': timestamp.toJson(),
      'terminal': terminal,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _TaskEventImpl extends TaskEvent {
  _TaskEventImpl({
    required String taskId,
    required int sequence,
    required _i2.TaskEventKind kind,
    required String message,
    required DateTime timestamp,
    required bool terminal,
  }) : super._(
         taskId: taskId,
         sequence: sequence,
         kind: kind,
         message: message,
         timestamp: timestamp,
         terminal: terminal,
       );

  /// Returns a shallow copy of this [TaskEvent]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  TaskEvent copyWith({
    String? taskId,
    int? sequence,
    _i2.TaskEventKind? kind,
    String? message,
    DateTime? timestamp,
    bool? terminal,
  }) {
    return TaskEvent(
      taskId: taskId ?? this.taskId,
      sequence: sequence ?? this.sequence,
      kind: kind ?? this.kind,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      terminal: terminal ?? this.terminal,
    );
  }
}
