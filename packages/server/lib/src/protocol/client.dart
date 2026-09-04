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
import 'package:dextero_server/src/protocol/control/host_status.dart' as _i3;
import 'package:dextero_server/src/protocol/control/controller_identity.dart'
    as _i4;
import 'package:dextero_server/src/protocol/control/chat_submission.dart'
    as _i5;
import 'package:dextero_server/src/protocol/control/chat_submit_request.dart'
    as _i6;
import 'package:dextero_server/src/protocol/control/chat_entry.dart' as _i7;
import 'protocol.dart' as _i8;

/// The first typed control-plane slice exposed to trusted controllers.
/// {@category Endpoint}
class EndpointControl extends _i1.EndpointRef {
  EndpointControl(_i1.EndpointCaller caller) : super(caller);

  @override
  String get name => 'control';

  /// Describes the local host and its intentionally volatile MVP storage.
  _i2.Future<_i3.HostStatus> status(_i4.ControllerIdentity controller) =>
      caller.callServerEndpoint<_i3.HostStatus>('control', 'status', {
        'controller': controller,
      });

  /// Selects the model before this process-local conversation has started.
  _i2.Future<_i3.HostStatus> selectModel(
    _i4.ControllerIdentity controller,
    String modelName,
  ) => caller.callServerEndpoint<_i3.HostStatus>('control', 'selectModel', {
    'controller': controller,
    'modelName': modelName,
  });

  /// Canonically accepts a user message before starting assistant work.
  _i2.Future<_i5.ChatSubmission> submitMessage(
    _i4.ControllerIdentity controller,
    _i6.ChatSubmitRequest request,
  ) => caller.callServerEndpoint<_i5.ChatSubmission>(
    'control',
    'submitMessage',
    {'controller': controller, 'request': request},
  );

  /// Requests cancellation of the matching active run.
  _i2.Future<bool> cancelRun(
    _i4.ControllerIdentity controller,
    String conversationId,
    String runId,
  ) => caller.callServerEndpoint<bool>('control', 'cancelRun', {
    'controller': controller,
    'conversationId': conversationId,
    'runId': runId,
  });

  /// Approves one pending tool action for the matching active run.
  _i2.Future<bool> approveWork(
    _i4.ControllerIdentity controller,
    String conversationId,
    String runId,
    String approvalId,
  ) => caller.callServerEndpoint<bool>('control', 'approveWork', {
    'controller': controller,
    'conversationId': conversationId,
    'runId': runId,
    'approvalId': approvalId,
  });

  /// Returns the complete process-local history for one conversation.
  _i2.Future<List<_i7.ChatEntry>> history(
    _i4.ControllerIdentity controller,
    String conversationId,
  ) => caller.callServerEndpoint<List<_i7.ChatEntry>>('control', 'history', {
    'controller': controller,
    'conversationId': conversationId,
  });

  /// Replays entries after the cursor, then streams future appends.
  _i2.Stream<_i7.ChatEntry> streamHistory(
    _i4.ControllerIdentity controller,
    String conversationId,
    int afterSequence,
  ) => caller
      .callStreamingServerEndpoint<_i2.Stream<_i7.ChatEntry>, _i7.ChatEntry>(
        'control',
        'streamHistory',
        {
          'controller': controller,
          'conversationId': conversationId,
          'afterSequence': afterSequence,
        },
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
         _i8.Protocol(),
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
