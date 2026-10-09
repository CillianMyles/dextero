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
import 'package:serverpod/protocol.dart' as _i2;
import 'control/chat_entry.dart' as _i3;
import 'control/chat_entry_kind.dart' as _i4;
import 'control/chat_entry_source.dart' as _i5;
import 'control/chat_entry_status.dart' as _i6;
import 'control/chat_error_code.dart' as _i7;
import 'control/chat_event_family.dart' as _i8;
import 'control/chat_run_usage.dart' as _i9;
import 'control/chat_submission.dart' as _i10;
import 'control/chat_submit_request.dart' as _i11;
import 'control/host_status.dart' as _i12;
import 'control/model_option.dart' as _i13;
import 'package:dextero_server/src/generated/control/chat_entry.dart' as _i14;
export 'control/chat_entry.dart';
export 'control/chat_entry_kind.dart';
export 'control/chat_entry_source.dart';
export 'control/chat_entry_status.dart';
export 'control/chat_error_code.dart';
export 'control/chat_event_family.dart';
export 'control/chat_run_usage.dart';
export 'control/chat_submission.dart';
export 'control/chat_submit_request.dart';
export 'control/host_status.dart';
export 'control/model_option.dart';

class Protocol extends _i1.SerializationManagerServer {
  Protocol._();

  factory Protocol() => _instance;

  static final Protocol _instance = Protocol._();

  static final List<_i2.TableDefinition> targetTableDefinitions = [
    ..._i2.Protocol.targetTableDefinitions,
  ];

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

    if (t == _i3.ChatEntry) {
      return _i3.ChatEntry.fromJson(data) as T;
    }
    if (t == _i4.ChatEntryKind) {
      return _i4.ChatEntryKind.fromJson(data) as T;
    }
    if (t == _i5.ChatEntrySource) {
      return _i5.ChatEntrySource.fromJson(data) as T;
    }
    if (t == _i6.ChatEntryStatus) {
      return _i6.ChatEntryStatus.fromJson(data) as T;
    }
    if (t == _i7.ChatErrorCode) {
      return _i7.ChatErrorCode.fromJson(data) as T;
    }
    if (t == _i8.ChatEventFamily) {
      return _i8.ChatEventFamily.fromJson(data) as T;
    }
    if (t == _i9.ChatRunUsage) {
      return _i9.ChatRunUsage.fromJson(data) as T;
    }
    if (t == _i10.ChatSubmission) {
      return _i10.ChatSubmission.fromJson(data) as T;
    }
    if (t == _i11.ChatSubmitRequest) {
      return _i11.ChatSubmitRequest.fromJson(data) as T;
    }
    if (t == _i12.HostStatus) {
      return _i12.HostStatus.fromJson(data) as T;
    }
    if (t == _i13.ModelOption) {
      return _i13.ModelOption.fromJson(data) as T;
    }
    if (t == _i1.getType<_i3.ChatEntry?>()) {
      return (data != null ? _i3.ChatEntry.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i4.ChatEntryKind?>()) {
      return (data != null ? _i4.ChatEntryKind.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i5.ChatEntrySource?>()) {
      return (data != null ? _i5.ChatEntrySource.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i6.ChatEntryStatus?>()) {
      return (data != null ? _i6.ChatEntryStatus.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i7.ChatErrorCode?>()) {
      return (data != null ? _i7.ChatErrorCode.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i8.ChatEventFamily?>()) {
      return (data != null ? _i8.ChatEventFamily.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i9.ChatRunUsage?>()) {
      return (data != null ? _i9.ChatRunUsage.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i10.ChatSubmission?>()) {
      return (data != null ? _i10.ChatSubmission.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i11.ChatSubmitRequest?>()) {
      return (data != null ? _i11.ChatSubmitRequest.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i12.HostStatus?>()) {
      return (data != null ? _i12.HostStatus.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i13.ModelOption?>()) {
      return (data != null ? _i13.ModelOption.fromJson(data) : null) as T;
    }
    if (t == List<String>) {
      return (data as List).map((e) => deserialize<String>(e)).toList() as T;
    }
    if (t == List<_i13.ModelOption>) {
      return (data as List)
              .map((e) => deserialize<_i13.ModelOption>(e))
              .toList()
          as T;
    }
    if (t == List<_i14.ChatEntry>) {
      return (data as List).map((e) => deserialize<_i14.ChatEntry>(e)).toList()
          as T;
    }
    try {
      return _i2.Protocol().deserialize<T>(data, t);
    } on _i1.DeserializationTypeNotFoundException catch (_) {}
    return super.deserialize<T>(data, t);
  }

  static String? getClassNameForType(Type type) {
    return switch (type) {
      _i3.ChatEntry => 'ChatEntry',
      _i4.ChatEntryKind => 'ChatEntryKind',
      _i5.ChatEntrySource => 'ChatEntrySource',
      _i6.ChatEntryStatus => 'ChatEntryStatus',
      _i7.ChatErrorCode => 'ChatErrorCode',
      _i8.ChatEventFamily => 'ChatEventFamily',
      _i9.ChatRunUsage => 'ChatRunUsage',
      _i10.ChatSubmission => 'ChatSubmission',
      _i11.ChatSubmitRequest => 'ChatSubmitRequest',
      _i12.HostStatus => 'HostStatus',
      _i13.ModelOption => 'ModelOption',
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
      case _i3.ChatEntry():
        return 'ChatEntry';
      case _i4.ChatEntryKind():
        return 'ChatEntryKind';
      case _i5.ChatEntrySource():
        return 'ChatEntrySource';
      case _i6.ChatEntryStatus():
        return 'ChatEntryStatus';
      case _i7.ChatErrorCode():
        return 'ChatErrorCode';
      case _i8.ChatEventFamily():
        return 'ChatEventFamily';
      case _i9.ChatRunUsage():
        return 'ChatRunUsage';
      case _i10.ChatSubmission():
        return 'ChatSubmission';
      case _i11.ChatSubmitRequest():
        return 'ChatSubmitRequest';
      case _i12.HostStatus():
        return 'HostStatus';
      case _i13.ModelOption():
        return 'ModelOption';
    }
    className = _i2.Protocol().getClassNameForObject(data);
    if (className != null) {
      return 'serverpod.$className';
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
      return deserialize<_i3.ChatEntry>(data['data']);
    }
    if (dataClassName == 'ChatEntryKind') {
      return deserialize<_i4.ChatEntryKind>(data['data']);
    }
    if (dataClassName == 'ChatEntrySource') {
      return deserialize<_i5.ChatEntrySource>(data['data']);
    }
    if (dataClassName == 'ChatEntryStatus') {
      return deserialize<_i6.ChatEntryStatus>(data['data']);
    }
    if (dataClassName == 'ChatErrorCode') {
      return deserialize<_i7.ChatErrorCode>(data['data']);
    }
    if (dataClassName == 'ChatEventFamily') {
      return deserialize<_i8.ChatEventFamily>(data['data']);
    }
    if (dataClassName == 'ChatRunUsage') {
      return deserialize<_i9.ChatRunUsage>(data['data']);
    }
    if (dataClassName == 'ChatSubmission') {
      return deserialize<_i10.ChatSubmission>(data['data']);
    }
    if (dataClassName == 'ChatSubmitRequest') {
      return deserialize<_i11.ChatSubmitRequest>(data['data']);
    }
    if (dataClassName == 'HostStatus') {
      return deserialize<_i12.HostStatus>(data['data']);
    }
    if (dataClassName == 'ModelOption') {
      return deserialize<_i13.ModelOption>(data['data']);
    }
    if (dataClassName.startsWith('serverpod.')) {
      data['className'] = dataClassName.substring(10);
      return _i2.Protocol().deserializeByClassName(data);
    }
    return super.deserializeByClassName(data);
  }

  @override
  _i1.Table? getTableForType(Type t) {
    {
      var table = _i2.Protocol().getTableForType(t);
      if (table != null) {
        return table;
      }
    }
    return null;
  }

  @override
  List<_i2.TableDefinition> getTargetTableDefinitions() =>
      targetTableDefinitions;

  @override
  String getModuleName() => 'dextero';

  /// Maps any `Record`s known to this [Protocol] to their JSON representation
  ///
  /// Throws in case the record type is not known.
  ///
  /// This method will return `null` (only) for `null` inputs.
  Map<String, dynamic>? mapRecordToJson(Record? record) {
    if (record == null) {
      return null;
    }
    try {
      return _i2.Protocol().mapRecordToJson(record);
    } catch (_) {}
    throw Exception('Unsupported record type ${record.runtimeType}');
  }
}
