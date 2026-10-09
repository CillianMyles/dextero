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
import 'control/chat_entry.dart' as _i2;
import 'control/chat_entry_kind.dart' as _i3;
import 'control/chat_entry_source.dart' as _i4;
import 'control/chat_entry_status.dart' as _i5;
import 'control/chat_event_family.dart' as _i6;
import 'control/chat_modality.dart' as _i7;
import 'control/chat_submission.dart' as _i8;
import 'control/chat_submit_request.dart' as _i9;
import 'control/host_status.dart' as _i10;
import 'control/model_option.dart' as _i11;
import 'control/spoken_reply.dart' as _i12;
import 'control/voice_submit_request.dart' as _i13;
import 'control/voice_turn_exception.dart' as _i14;
import 'package:dextero_server/src/protocol/control/chat_entry.dart' as _i15;
export 'control/chat_entry.dart';
export 'control/chat_entry_kind.dart';
export 'control/chat_entry_source.dart';
export 'control/chat_entry_status.dart';
export 'control/chat_event_family.dart';
export 'control/chat_modality.dart';
export 'control/chat_submission.dart';
export 'control/chat_submit_request.dart';
export 'control/host_status.dart';
export 'control/model_option.dart';
export 'control/spoken_reply.dart';
export 'control/voice_submit_request.dart';
export 'control/voice_turn_exception.dart';
export 'client.dart';

class Protocol extends _i1.SerializationManager {
  Protocol._();

  factory Protocol() => _instance;

  static final Protocol _instance = Protocol._();

  static String? getClassNameFromObjectJson(dynamic data) {
    if (data is! Map) return null;
    final className = data['__className__'] as String?;
    return className;
  }

  @override
  T deserialize<T>(dynamic data, [Type? t]) {
    t ??= T;

    final dataClassName = getClassNameFromObjectJson(data);
    if (dataClassName != null && dataClassName != getClassNameForType(t)) {
      try {
        return deserializeByClassName({
          'className': dataClassName,
          'data': data,
        });
      } on FormatException catch (_) {
        // If the className is not recognized (e.g., older client receiving
        // data with a new subtype), fall back to deserializing without the
        // className, using the expected type T.
      }
    }

    if (t == _i2.ChatEntry) {
      return _i2.ChatEntry.fromJson(data) as T;
    }
    if (t == _i3.ChatEntryKind) {
      return _i3.ChatEntryKind.fromJson(data) as T;
    }
    if (t == _i4.ChatEntrySource) {
      return _i4.ChatEntrySource.fromJson(data) as T;
    }
    if (t == _i5.ChatEntryStatus) {
      return _i5.ChatEntryStatus.fromJson(data) as T;
    }
    if (t == _i6.ChatEventFamily) {
      return _i6.ChatEventFamily.fromJson(data) as T;
    }
    if (t == _i7.ChatModality) {
      return _i7.ChatModality.fromJson(data) as T;
    }
    if (t == _i8.ChatSubmission) {
      return _i8.ChatSubmission.fromJson(data) as T;
    }
    if (t == _i9.ChatSubmitRequest) {
      return _i9.ChatSubmitRequest.fromJson(data) as T;
    }
    if (t == _i10.HostStatus) {
      return _i10.HostStatus.fromJson(data) as T;
    }
    if (t == _i11.ModelOption) {
      return _i11.ModelOption.fromJson(data) as T;
    }
    if (t == _i12.SpokenReply) {
      return _i12.SpokenReply.fromJson(data) as T;
    }
    if (t == _i13.VoiceSubmitRequest) {
      return _i13.VoiceSubmitRequest.fromJson(data) as T;
    }
    if (t == _i14.VoiceTurnException) {
      return _i14.VoiceTurnException.fromJson(data) as T;
    }
    if (t == _i1.getType<_i2.ChatEntry?>()) {
      return (data != null ? _i2.ChatEntry.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i3.ChatEntryKind?>()) {
      return (data != null ? _i3.ChatEntryKind.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i4.ChatEntrySource?>()) {
      return (data != null ? _i4.ChatEntrySource.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i5.ChatEntryStatus?>()) {
      return (data != null ? _i5.ChatEntryStatus.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i6.ChatEventFamily?>()) {
      return (data != null ? _i6.ChatEventFamily.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i7.ChatModality?>()) {
      return (data != null ? _i7.ChatModality.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i8.ChatSubmission?>()) {
      return (data != null ? _i8.ChatSubmission.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i9.ChatSubmitRequest?>()) {
      return (data != null ? _i9.ChatSubmitRequest.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i10.HostStatus?>()) {
      return (data != null ? _i10.HostStatus.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i11.ModelOption?>()) {
      return (data != null ? _i11.ModelOption.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i12.SpokenReply?>()) {
      return (data != null ? _i12.SpokenReply.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i13.VoiceSubmitRequest?>()) {
      return (data != null ? _i13.VoiceSubmitRequest.fromJson(data) : null)
          as T;
    }
    if (t == _i1.getType<_i14.VoiceTurnException?>()) {
      return (data != null ? _i14.VoiceTurnException.fromJson(data) : null)
          as T;
    }
    if (t == List<String>) {
      return (data as List).map((e) => deserialize<String>(e)).toList() as T;
    }
    if (t == List<_i11.ModelOption>) {
      return (data as List)
              .map((e) => deserialize<_i11.ModelOption>(e))
              .toList()
          as T;
    }
    if (t == List<_i15.ChatEntry>) {
      return (data as List).map((e) => deserialize<_i15.ChatEntry>(e)).toList()
          as T;
    }
    return super.deserialize<T>(data, t);
  }

  static String? getClassNameForType(Type type) {
    return switch (type) {
      _i2.ChatEntry => 'ChatEntry',
      _i3.ChatEntryKind => 'ChatEntryKind',
      _i4.ChatEntrySource => 'ChatEntrySource',
      _i5.ChatEntryStatus => 'ChatEntryStatus',
      _i6.ChatEventFamily => 'ChatEventFamily',
      _i7.ChatModality => 'ChatModality',
      _i8.ChatSubmission => 'ChatSubmission',
      _i9.ChatSubmitRequest => 'ChatSubmitRequest',
      _i10.HostStatus => 'HostStatus',
      _i11.ModelOption => 'ModelOption',
      _i12.SpokenReply => 'SpokenReply',
      _i13.VoiceSubmitRequest => 'VoiceSubmitRequest',
      _i14.VoiceTurnException => 'VoiceTurnException',
      _ => null,
    };
  }

  @override
  String? getClassNameForObject(Object? data) {
    String? className = super.getClassNameForObject(data);
    if (className != null) return className;

    if (data is Map<String, dynamic> && data['__className__'] is String) {
      return (data['__className__'] as String).replaceFirst('dextero.', '');
    }

    switch (data) {
      case _i2.ChatEntry():
        return 'ChatEntry';
      case _i3.ChatEntryKind():
        return 'ChatEntryKind';
      case _i4.ChatEntrySource():
        return 'ChatEntrySource';
      case _i5.ChatEntryStatus():
        return 'ChatEntryStatus';
      case _i6.ChatEventFamily():
        return 'ChatEventFamily';
      case _i7.ChatModality():
        return 'ChatModality';
      case _i8.ChatSubmission():
        return 'ChatSubmission';
      case _i9.ChatSubmitRequest():
        return 'ChatSubmitRequest';
      case _i10.HostStatus():
        return 'HostStatus';
      case _i11.ModelOption():
        return 'ModelOption';
      case _i12.SpokenReply():
        return 'SpokenReply';
      case _i13.VoiceSubmitRequest():
        return 'VoiceSubmitRequest';
      case _i14.VoiceTurnException():
        return 'VoiceTurnException';
    }
    return null;
  }

  @override
  dynamic deserializeByClassName(Map<String, dynamic> data) {
    var dataClassName = data['className'];
    if (dataClassName is! String) {
      return super.deserializeByClassName(data);
    }
    if (dataClassName == 'ChatEntry') {
      return deserialize<_i2.ChatEntry>(data['data']);
    }
    if (dataClassName == 'ChatEntryKind') {
      return deserialize<_i3.ChatEntryKind>(data['data']);
    }
    if (dataClassName == 'ChatEntrySource') {
      return deserialize<_i4.ChatEntrySource>(data['data']);
    }
    if (dataClassName == 'ChatEntryStatus') {
      return deserialize<_i5.ChatEntryStatus>(data['data']);
    }
    if (dataClassName == 'ChatEventFamily') {
      return deserialize<_i6.ChatEventFamily>(data['data']);
    }
    if (dataClassName == 'ChatModality') {
      return deserialize<_i7.ChatModality>(data['data']);
    }
    if (dataClassName == 'ChatSubmission') {
      return deserialize<_i8.ChatSubmission>(data['data']);
    }
    if (dataClassName == 'ChatSubmitRequest') {
      return deserialize<_i9.ChatSubmitRequest>(data['data']);
    }
    if (dataClassName == 'HostStatus') {
      return deserialize<_i10.HostStatus>(data['data']);
    }
    if (dataClassName == 'ModelOption') {
      return deserialize<_i11.ModelOption>(data['data']);
    }
    if (dataClassName == 'SpokenReply') {
      return deserialize<_i12.SpokenReply>(data['data']);
    }
    if (dataClassName == 'VoiceSubmitRequest') {
      return deserialize<_i13.VoiceSubmitRequest>(data['data']);
    }
    if (dataClassName == 'VoiceTurnException') {
      return deserialize<_i14.VoiceTurnException>(data['data']);
    }
    return super.deserializeByClassName(data);
  }

  /// Maps any `Record`s known to this [Protocol] to their JSON representation
  ///
  /// Throws in case the record type is not known.
  ///
  /// This method will return `null` (only) for `null` inputs.
  Map<String, dynamic>? mapRecordToJson(Record? record) {
    if (record == null) {
      return null;
    }
    throw Exception('Unsupported record type ${record.runtimeType}');
  }
}
