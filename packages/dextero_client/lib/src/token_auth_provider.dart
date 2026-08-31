import 'package:serverpod_client/serverpod_client.dart';

/// Supplies the bootstrap bearer token expected by the local control plane.
///
/// Device pairing will replace this single-token MVP boundary. Applications
/// should source the token from protected storage rather than source code.
final class DexteroTokenAuthProvider implements ClientAuthKeyProvider {
  DexteroTokenAuthProvider(String token) : _token = token {
    if (token.length < 32) {
      throw ArgumentError.value(
        token,
        'token',
        'must contain at least 32 characters',
      );
    }
  }

  final String _token;

  @override
  Future<String> get authHeaderValue async =>
      wrapAsBearerAuthHeaderValue(_token);
}
