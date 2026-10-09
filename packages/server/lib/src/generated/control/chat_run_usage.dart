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

abstract class ChatRunUsage
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  ChatRunUsage._({
    required this.provider,
    required this.model,
    required this.authSource,
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheCreationInputTokens,
    required this.cacheReadInputTokens,
    required this.modelRequests,
    this.costMicrosUsd,
  });

  factory ChatRunUsage({
    required String provider,
    required String model,
    required String authSource,
    required int inputTokens,
    required int outputTokens,
    required int cacheCreationInputTokens,
    required int cacheReadInputTokens,
    required int modelRequests,
    int? costMicrosUsd,
  }) = _ChatRunUsageImpl;

  factory ChatRunUsage.fromJson(Map<String, dynamic> jsonSerialization) {
    return ChatRunUsage(
      provider: jsonSerialization['provider'] as String,
      model: jsonSerialization['model'] as String,
      authSource: jsonSerialization['authSource'] as String,
      inputTokens: jsonSerialization['inputTokens'] as int,
      outputTokens: jsonSerialization['outputTokens'] as int,
      cacheCreationInputTokens:
          jsonSerialization['cacheCreationInputTokens'] as int,
      cacheReadInputTokens: jsonSerialization['cacheReadInputTokens'] as int,
      modelRequests: jsonSerialization['modelRequests'] as int,
      costMicrosUsd: jsonSerialization['costMicrosUsd'] as int?,
    );
  }

  String provider;

  String model;

  String authSource;

  int inputTokens;

  int outputTokens;

  int cacheCreationInputTokens;

  int cacheReadInputTokens;

  int modelRequests;

  int? costMicrosUsd;

  /// Returns a shallow copy of this [ChatRunUsage]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  ChatRunUsage copyWith({
    String? provider,
    String? model,
    String? authSource,
    int? inputTokens,
    int? outputTokens,
    int? cacheCreationInputTokens,
    int? cacheReadInputTokens,
    int? modelRequests,
    int? costMicrosUsd,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'ChatRunUsage',
      'provider': provider,
      'model': model,
      'authSource': authSource,
      'inputTokens': inputTokens,
      'outputTokens': outputTokens,
      'cacheCreationInputTokens': cacheCreationInputTokens,
      'cacheReadInputTokens': cacheReadInputTokens,
      'modelRequests': modelRequests,
      if (costMicrosUsd != null) 'costMicrosUsd': costMicrosUsd,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'ChatRunUsage',
      'provider': provider,
      'model': model,
      'authSource': authSource,
      'inputTokens': inputTokens,
      'outputTokens': outputTokens,
      'cacheCreationInputTokens': cacheCreationInputTokens,
      'cacheReadInputTokens': cacheReadInputTokens,
      'modelRequests': modelRequests,
      if (costMicrosUsd != null) 'costMicrosUsd': costMicrosUsd,
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _ChatRunUsageImpl extends ChatRunUsage {
  _ChatRunUsageImpl({
    required String provider,
    required String model,
    required String authSource,
    required int inputTokens,
    required int outputTokens,
    required int cacheCreationInputTokens,
    required int cacheReadInputTokens,
    required int modelRequests,
    int? costMicrosUsd,
  }) : super._(
         provider: provider,
         model: model,
         authSource: authSource,
         inputTokens: inputTokens,
         outputTokens: outputTokens,
         cacheCreationInputTokens: cacheCreationInputTokens,
         cacheReadInputTokens: cacheReadInputTokens,
         modelRequests: modelRequests,
         costMicrosUsd: costMicrosUsd,
       );

  /// Returns a shallow copy of this [ChatRunUsage]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  ChatRunUsage copyWith({
    String? provider,
    String? model,
    String? authSource,
    int? inputTokens,
    int? outputTokens,
    int? cacheCreationInputTokens,
    int? cacheReadInputTokens,
    int? modelRequests,
    Object? costMicrosUsd = _Undefined,
  }) {
    return ChatRunUsage(
      provider: provider ?? this.provider,
      model: model ?? this.model,
      authSource: authSource ?? this.authSource,
      inputTokens: inputTokens ?? this.inputTokens,
      outputTokens: outputTokens ?? this.outputTokens,
      cacheCreationInputTokens:
          cacheCreationInputTokens ?? this.cacheCreationInputTokens,
      cacheReadInputTokens: cacheReadInputTokens ?? this.cacheReadInputTokens,
      modelRequests: modelRequests ?? this.modelRequests,
      costMicrosUsd: costMicrosUsd is int? ? costMicrosUsd : this.costMicrosUsd,
    );
  }
}
