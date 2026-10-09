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

abstract class ModelOption implements _i1.SerializableModel {
  ModelOption._({
    required this.id,
    required this.provider,
    required this.modelName,
    required this.label,
    required this.toolDescription,
    required this.authSource,
  });

  factory ModelOption({
    required String id,
    required String provider,
    required String modelName,
    required String label,
    required String toolDescription,
    required String authSource,
  }) = _ModelOptionImpl;

  factory ModelOption.fromJson(Map<String, dynamic> jsonSerialization) {
    return ModelOption(
      id: jsonSerialization['id'] as String,
      provider: jsonSerialization['provider'] as String,
      modelName: jsonSerialization['modelName'] as String,
      label: jsonSerialization['label'] as String,
      toolDescription: jsonSerialization['toolDescription'] as String,
      authSource: jsonSerialization['authSource'] as String,
    );
  }

  String id;

  String provider;

  String modelName;

  String label;

  String toolDescription;

  String authSource;

  /// Returns a shallow copy of this [ModelOption]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  ModelOption copyWith({
    String? id,
    String? provider,
    String? modelName,
    String? label,
    String? toolDescription,
    String? authSource,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'ModelOption',
      'id': id,
      'provider': provider,
      'modelName': modelName,
      'label': label,
      'toolDescription': toolDescription,
      'authSource': authSource,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _ModelOptionImpl extends ModelOption {
  _ModelOptionImpl({
    required String id,
    required String provider,
    required String modelName,
    required String label,
    required String toolDescription,
    required String authSource,
  }) : super._(
         id: id,
         provider: provider,
         modelName: modelName,
         label: label,
         toolDescription: toolDescription,
         authSource: authSource,
       );

  /// Returns a shallow copy of this [ModelOption]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  ModelOption copyWith({
    String? id,
    String? provider,
    String? modelName,
    String? label,
    String? toolDescription,
    String? authSource,
  }) {
    return ModelOption(
      id: id ?? this.id,
      provider: provider ?? this.provider,
      modelName: modelName ?? this.modelName,
      label: label ?? this.label,
      toolDescription: toolDescription ?? this.toolDescription,
      authSource: authSource ?? this.authSource,
    );
  }
}
