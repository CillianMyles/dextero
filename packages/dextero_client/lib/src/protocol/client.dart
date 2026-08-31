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
import 'dart:async' as _i2;
import 'package:dextero_client/src/protocol/control/host_status.dart' as _i3;
import 'package:dextero_client/src/protocol/control/task_event.dart' as _i4;
import 'protocol.dart' as _i5;

/// The first typed control-plane slice exposed to trusted controllers.
/// {@category Endpoint}
class EndpointControl extends _i1.EndpointRef {
  EndpointControl(_i1.EndpointCaller caller) : super(caller);

  @override
  String get name => 'control';

  /// Describes the local host and its intentionally volatile MVP storage.
  _i2.Future<_i3.HostStatus> status() =>
      caller.callServerEndpoint<_i3.HostStatus>('control', 'status', {});

  /// Streams a deterministic task lifecycle over Serverpod's method stream.
  ///
  /// This proves the generated client and WebSocket event path without giving
  /// the remote surface authority to run arbitrary tools yet.
  _i2.Stream<_i4.TaskEvent> runDemo(int steps) => caller
      .callStreamingServerEndpoint<_i2.Stream<_i4.TaskEvent>, _i4.TaskEvent>(
        'control',
        'runDemo',
        {'steps': steps},
        {},
      );
}

class Client extends _i1.ServerpodClientShared {
  Client(
    String host, {
    dynamic securityContext,
    @Deprecated(
      'Use authKeyProvider instead. This will be removed in future releases.',
    )
    super.authenticationKeyManager,
    Duration? streamingConnectionTimeout,
    Duration? connectionTimeout,
    Function(_i1.MethodCallContext, Object, StackTrace)? onFailedCall,
    Function(_i1.MethodCallContext)? onSucceededCall,
    bool? disconnectStreamsOnLostInternetConnection,
  }) : super(
         host,
         _i5.Protocol(),
         securityContext: securityContext,
         streamingConnectionTimeout: streamingConnectionTimeout,
         connectionTimeout: connectionTimeout,
         onFailedCall: onFailedCall,
         onSucceededCall: onSucceededCall,
         disconnectStreamsOnLostInternetConnection:
             disconnectStreamsOnLostInternetConnection,
       ) {
    control = EndpointControl(this);
  }

  late final EndpointControl control;

  @override
  Map<String, _i1.EndpointRef> get endpointRefLookup => {'control': control};

  @override
  Map<String, _i1.ModuleEndpointCaller> get moduleLookup => {};
}
