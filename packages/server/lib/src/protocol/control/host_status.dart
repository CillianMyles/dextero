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

abstract class HostStatus implements _i1.SerializableModel {
  HostStatus._({
    required this.name,
    required this.version,
    required this.startedAt,
    required this.persistence,
    required this.databaseRequired,
    required this.streamingAvailable,
  });

  factory HostStatus({
    required String name,
    required String version,
    required DateTime startedAt,
    required String persistence,
    required bool databaseRequired,
    required bool streamingAvailable,
  }) = _HostStatusImpl;

  factory HostStatus.fromJson(Map<String, dynamic> jsonSerialization) {
    return HostStatus(
      name: jsonSerialization['name'] as String,
      version: jsonSerialization['version'] as String,
      startedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['startedAt'],
      ),
      persistence: jsonSerialization['persistence'] as String,
      databaseRequired: _i1.BoolJsonExtension.fromJson(
        jsonSerialization['databaseRequired'],
      ),
      streamingAvailable: _i1.BoolJsonExtension.fromJson(
        jsonSerialization['streamingAvailable'],
      ),
    );
  }

  String name;

  String version;

  DateTime startedAt;

  String persistence;

  bool databaseRequired;

  bool streamingAvailable;

  /// Returns a shallow copy of this [HostStatus]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  HostStatus copyWith({
    String? name,
    String? version,
    DateTime? startedAt,
    String? persistence,
    bool? databaseRequired,
    bool? streamingAvailable,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'HostStatus',
      'name': name,
      'version': version,
      'startedAt': startedAt.toJson(),
      'persistence': persistence,
      'databaseRequired': databaseRequired,
      'streamingAvailable': streamingAvailable,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _HostStatusImpl extends HostStatus {
  _HostStatusImpl({
    required String name,
    required String version,
    required DateTime startedAt,
    required String persistence,
    required bool databaseRequired,
    required bool streamingAvailable,
  }) : super._(
         name: name,
         version: version,
         startedAt: startedAt,
         persistence: persistence,
         databaseRequired: databaseRequired,
         streamingAvailable: streamingAvailable,
       );

  /// Returns a shallow copy of this [HostStatus]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  HostStatus copyWith({
    String? name,
    String? version,
    DateTime? startedAt,
    String? persistence,
    bool? databaseRequired,
    bool? streamingAvailable,
  }) {
    return HostStatus(
      name: name ?? this.name,
      version: version ?? this.version,
      startedAt: startedAt ?? this.startedAt,
      persistence: persistence ?? this.persistence,
      databaseRequired: databaseRequired ?? this.databaseRequired,
      streamingAvailable: streamingAvailable ?? this.streamingAvailable,
    );
  }
}
