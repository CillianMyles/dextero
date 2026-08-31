import 'dart:io';

import 'package:serverpod/serverpod.dart';

import 'src/auth/dextero_token_authenticator.dart';
import 'src/generated/endpoints.dart';
import 'src/generated/protocol.dart';

/// Starts the database-free local control plane.
Future<void> run(List<String> arguments) async {
  final token = Platform.environment['DEXTERO_CONTROL_TOKEN'];
  if (token == null || token.length < 32) {
    throw StateError(
      'DEXTERO_CONTROL_TOKEN must contain at least 32 characters. '
      'Generate one before starting the server.',
    );
  }

  final authenticator = DexteroTokenAuthenticator(token);
  final pod = Serverpod(
    arguments,
    Protocol(),
    Endpoints(),
    authenticationHandler: authenticator.authenticate,
  );
  await pod.start();
}
