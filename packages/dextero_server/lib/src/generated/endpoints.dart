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
import '../control/control_endpoint.dart' as _i2;

class Endpoints extends _i1.EndpointDispatch {
  @override
  void initializeEndpoints(_i1.Server server) {
    var endpoints = <String, _i1.Endpoint>{
      'control': _i2.ControlEndpoint()..initialize(server, 'control', null),
    };
    connectors['control'] = _i1.EndpointConnector(
      name: 'control',
      endpoint: endpoints['control']!,
      methodConnectors: {
        'status': _i1.MethodConnector(
          name: 'status',
          params: {},
          call: (_i1.Session session, Map<String, dynamic> params) async =>
              (endpoints['control'] as _i2.ControlEndpoint).status(session),
        ),
        'runDemo': _i1.MethodStreamConnector(
          name: 'runDemo',
          params: {
            'steps': _i1.ParameterDescription(
              name: 'steps',
              type: _i1.getType<int>(),
              nullable: false,
            ),
          },
          streamParams: {},
          returnType: _i1.MethodStreamReturnType.streamType,
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
                Map<String, Stream> streamParams,
              ) => (endpoints['control'] as _i2.ControlEndpoint).runDemo(
                session,
                params['steps'],
              ),
        ),
      },
    );
  }
}
