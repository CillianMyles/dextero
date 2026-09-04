import 'dart:io';

const _errorMessage =
    'iOS CONTROL_URL must use HTTPS or an HTTP loopback host for the simulator.';

void main(List<String> arguments) {
  if (arguments.length == 1 && _isHttpLoopbackUrl(arguments.single)) {
    return;
  }

  stdout.writeln(_errorMessage);
  exitCode = 2;
}

bool _isHttpLoopbackUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'http' ||
      !uri.hasAuthority ||
      uri.userInfo.isNotEmpty) {
    return false;
  }

  if (uri.host.toLowerCase() == 'localhost') {
    return true;
  }

  return InternetAddress.tryParse(uri.host)?.isLoopback ?? false;
}
