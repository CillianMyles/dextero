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
import '../control/controller_identity.dart' as _i2;
import 'package:dextero_server/src/protocol/protocol.dart' as _i3;

abstract class HostStatus implements _i1.SerializableModel {
  HostStatus._({
    required this.name,
    required this.version,
    required this.deviceId,
    required this.projectId,
    required this.projectName,
    required this.workspaceId,
    required this.workspaceName,
    required this.controller,
    required this.startedAt,
    required this.persistence,
    required this.conversationId,
    required this.retentionNotice,
    required this.databaseRequired,
    required this.streamingAvailable,
    required this.modelProvider,
    required this.modelName,
    required this.availableModels,
  });

  factory HostStatus({
    required String name,
    required String version,
    required String deviceId,
    required String projectId,
    required String projectName,
    required String workspaceId,
    required String workspaceName,
    required _i2.ControllerIdentity controller,
    required DateTime startedAt,
    required String persistence,
    required String conversationId,
    required String retentionNotice,
    required bool databaseRequired,
    required bool streamingAvailable,
    required String modelProvider,
    required String modelName,
    required List<String> availableModels,
  }) = _HostStatusImpl;

  factory HostStatus.fromJson(Map<String, dynamic> jsonSerialization) {
    return HostStatus(
      name: jsonSerialization['name'] as String,
      version: jsonSerialization['version'] as String,
      deviceId: jsonSerialization['deviceId'] as String,
      projectId: jsonSerialization['projectId'] as String,
      projectName: jsonSerialization['projectName'] as String,
      workspaceId: jsonSerialization['workspaceId'] as String,
      workspaceName: jsonSerialization['workspaceName'] as String,
      controller: _i3.Protocol().deserialize<_i2.ControllerIdentity>(
        jsonSerialization['controller'],
      ),
      startedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['startedAt'],
      ),
      persistence: jsonSerialization['persistence'] as String,
      conversationId: jsonSerialization['conversationId'] as String,
      retentionNotice: jsonSerialization['retentionNotice'] as String,
      databaseRequired: _i1.BoolJsonExtension.fromJson(
        jsonSerialization['databaseRequired'],
      ),
      streamingAvailable: _i1.BoolJsonExtension.fromJson(
        jsonSerialization['streamingAvailable'],
      ),
      modelProvider: jsonSerialization['modelProvider'] as String,
      modelName: jsonSerialization['modelName'] as String,
      availableModels: _i3.Protocol().deserialize<List<String>>(
        jsonSerialization['availableModels'],
      ),
    );
  }

  String name;

  String version;

  String deviceId;

  String projectId;

  String projectName;

  String workspaceId;

  String workspaceName;

  _i2.ControllerIdentity controller;

  DateTime startedAt;

  String persistence;

  String conversationId;

  String retentionNotice;

  bool databaseRequired;

  bool streamingAvailable;

  String modelProvider;

  String modelName;

  List<String> availableModels;

  /// Returns a shallow copy of this [HostStatus]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  HostStatus copyWith({
    String? name,
    String? version,
    String? deviceId,
    String? projectId,
    String? projectName,
    String? workspaceId,
    String? workspaceName,
    _i2.ControllerIdentity? controller,
    DateTime? startedAt,
    String? persistence,
    String? conversationId,
    String? retentionNotice,
    bool? databaseRequired,
    bool? streamingAvailable,
    String? modelProvider,
    String? modelName,
    List<String>? availableModels,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'HostStatus',
      'name': name,
      'version': version,
      'deviceId': deviceId,
      'projectId': projectId,
      'projectName': projectName,
      'workspaceId': workspaceId,
      'workspaceName': workspaceName,
      'controller': controller.toJson(),
      'startedAt': startedAt.toJson(),
      'persistence': persistence,
      'conversationId': conversationId,
      'retentionNotice': retentionNotice,
      'databaseRequired': databaseRequired,
      'streamingAvailable': streamingAvailable,
      'modelProvider': modelProvider,
      'modelName': modelName,
      'availableModels': availableModels.toJson(),
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
    required String deviceId,
    required String projectId,
    required String projectName,
    required String workspaceId,
    required String workspaceName,
    required _i2.ControllerIdentity controller,
    required DateTime startedAt,
    required String persistence,
    required String conversationId,
    required String retentionNotice,
    required bool databaseRequired,
    required bool streamingAvailable,
    required String modelProvider,
    required String modelName,
    required List<String> availableModels,
  }) : super._(
         name: name,
         version: version,
         deviceId: deviceId,
         projectId: projectId,
         projectName: projectName,
         workspaceId: workspaceId,
         workspaceName: workspaceName,
         controller: controller,
         startedAt: startedAt,
         persistence: persistence,
         conversationId: conversationId,
         retentionNotice: retentionNotice,
         databaseRequired: databaseRequired,
         streamingAvailable: streamingAvailable,
         modelProvider: modelProvider,
         modelName: modelName,
         availableModels: availableModels,
       );

  /// Returns a shallow copy of this [HostStatus]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  HostStatus copyWith({
    String? name,
    String? version,
    String? deviceId,
    String? projectId,
    String? projectName,
    String? workspaceId,
    String? workspaceName,
    _i2.ControllerIdentity? controller,
    DateTime? startedAt,
    String? persistence,
    String? conversationId,
    String? retentionNotice,
    bool? databaseRequired,
    bool? streamingAvailable,
    String? modelProvider,
    String? modelName,
    List<String>? availableModels,
  }) {
    return HostStatus(
      name: name ?? this.name,
      version: version ?? this.version,
      deviceId: deviceId ?? this.deviceId,
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      workspaceId: workspaceId ?? this.workspaceId,
      workspaceName: workspaceName ?? this.workspaceName,
      controller: controller ?? this.controller.copyWith(),
      startedAt: startedAt ?? this.startedAt,
      persistence: persistence ?? this.persistence,
      conversationId: conversationId ?? this.conversationId,
      retentionNotice: retentionNotice ?? this.retentionNotice,
      databaseRequired: databaseRequired ?? this.databaseRequired,
      streamingAvailable: streamingAvailable ?? this.streamingAvailable,
      modelProvider: modelProvider ?? this.modelProvider,
      modelName: modelName ?? this.modelName,
      availableModels:
          availableModels ?? this.availableModels.map((e0) => e0).toList(),
    );
  }
}
