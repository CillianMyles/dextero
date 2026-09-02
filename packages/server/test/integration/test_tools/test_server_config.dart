import 'package:serverpod/serverpod.dart';

/// Keeps endpoint tests isolated from a locally running development server.
ServerpodConfig useEphemeralApiPort(ServerpodConfig config) => config.copyWith(
  apiServer: ServerConfig(
    port: 0,
    publicScheme: config.apiServer.publicScheme,
    publicHost: config.apiServer.publicHost,
    publicPort: 0,
  ),
);
