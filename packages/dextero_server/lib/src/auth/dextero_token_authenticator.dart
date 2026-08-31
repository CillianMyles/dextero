import 'dart:convert';

import 'package:serverpod/serverpod.dart';

/// Validates the bootstrap bearer token without exiting early on a mismatch.
final class DexteroTokenAuthenticator {
  DexteroTokenAuthenticator(String expectedToken)
    : _expectedToken = utf8.encode(expectedToken);

  final List<int> _expectedToken;

  Future<AuthenticationInfo?> authenticate(
    Session session,
    String token,
  ) async {
    if (!_constantTimeEquals(_expectedToken, utf8.encode(token))) return null;

    return AuthenticationInfo(
      'dextero-controller',
      const {},
      authId: 'bootstrap-token',
    );
  }

  bool _constantTimeEquals(List<int> expected, List<int> actual) {
    var difference = expected.length ^ actual.length;
    final comparisons = expected.length > actual.length
        ? expected.length
        : actual.length;
    for (var index = 0; index < comparisons; index++) {
      final expectedByte = index < expected.length ? expected[index] : 0;
      final actualByte = index < actual.length ? actual[index] : 0;
      difference |= expectedByte ^ actualByte;
    }
    return difference == 0;
  }
}
