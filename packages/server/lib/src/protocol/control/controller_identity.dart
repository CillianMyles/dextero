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

abstract class ControllerIdentity implements _i1.SerializableModel {
  ControllerIdentity._({required this.id, required this.name});

  factory ControllerIdentity({required String id, required String name}) =
      _ControllerIdentityImpl;

  factory ControllerIdentity.fromJson(Map<String, dynamic> jsonSerialization) {
    return ControllerIdentity(
      id: jsonSerialization['id'] as String,
      name: jsonSerialization['name'] as String,
    );
  }

  String id;

  String name;

  /// Returns a shallow copy of this [ControllerIdentity]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  ControllerIdentity copyWith({String? id, String? name});
  @override
  Map<String, dynamic> toJson() {
    return {'__className__': 'ControllerIdentity', 'id': id, 'name': name};
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _ControllerIdentityImpl extends ControllerIdentity {
  _ControllerIdentityImpl({required String id, required String name})
    : super._(id: id, name: name);

  /// Returns a shallow copy of this [ControllerIdentity]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  ControllerIdentity copyWith({String? id, String? name}) {
    return ControllerIdentity(id: id ?? this.id, name: name ?? this.name);
  }
}
