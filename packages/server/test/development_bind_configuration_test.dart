import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('make dev probes the configured concrete bind address', () async {
    final result = await _dryRunDev('192.0.2.10');

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(
      result.stdout,
      contains('curl --silent --output /dev/null "http://192.0.2.10:8080/"'),
    );
    expect(
      result.stdout,
      contains('--dart-define="DEXTERO_CONTROL_URL=http://192.0.2.10:8080/"'),
    );
  });

  test('make dev probes loopback for a wildcard bind address', () async {
    final result = await _dryRunDev('0.0.0.0');

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(
      result.stdout,
      contains('curl --silent --output /dev/null "http://127.0.0.1:8080/"'),
    );
    expect(
      result.stdout,
      contains('--dart-define="DEXTERO_CONTROL_URL=http://127.0.0.1:8080/"'),
    );
  });

  test('make dev brackets a concrete IPv6 readiness address', () async {
    final result = await _dryRunDev('::1');

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(
      result.stdout,
      contains('curl --silent --output /dev/null "http://[::1]:8080/"'),
    );
    expect(
      result.stdout,
      contains('--dart-define="DEXTERO_CONTROL_URL=http://[::1]:8080/"'),
    );
  });

  test('make dev probes IPv6 loopback for an IPv6 wildcard bind', () async {
    final result = await _dryRunDev('::');

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(
      result.stdout,
      contains('curl --silent --output /dev/null "http://[::1]:8080/"'),
    );
    expect(
      result.stdout,
      contains('--dart-define="DEXTERO_CONTROL_URL=http://[::1]:8080/"'),
    );
  });

  test('iOS validation accepts the derived IPv6 loopback URL', () async {
    for (final bindAddress in ['::1', '::']) {
      final result = await _validateIosControlUrl(bindAddress: bindAddress);

      expect(
        result.exitCode,
        0,
        reason: 'BIND_ADDRESS=$bindAddress\n${result.stderr}',
      );
    }
  });

  test('iOS validation still rejects a non-loopback HTTP IPv6 URL', () async {
    final result = await _validateIosControlUrl(
      controlUrl: 'http://[2001:db8::1]:8080/',
    );

    expect(result.exitCode, 2);
    expect(
      result.stdout,
      contains(
        'iOS CONTROL_URL must use HTTPS or an HTTP loopback host for the simulator.',
      ),
    );
  });

  test('make dev preserves an explicit client URL override', () async {
    final result = await _dryRunDev(
      '192.0.2.10',
      controlUrl: 'https://controller.example/',
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(
      result.stdout,
      contains(
        '--dart-define="DEXTERO_CONTROL_URL=https://controller.example/"',
      ),
    );
  });

  test('make approve injects connection settings and identifiers', () async {
    final workspace = Directory.current.parent.parent;
    final result = await Process.run('make', [
      '--dry-run',
      '--no-print-directory',
      'approve',
      'RUN_ID=run-42',
      'APPROVAL_ID=approval-7',
      'CONTROL_URL=https://controller.example/',
    ], workingDirectory: workspace.path);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout, contains('DEXTERO_CONTROL_TOKEN='));
    expect(
      result.stdout,
      contains('DEXTERO_CONTROL_URL="https://controller.example/"'),
    );
    expect(result.stdout, contains('--approve "run-42" "approval-7"'));
  });
}

Future<ProcessResult> _dryRunDev(String bindAddress, {String? controlUrl}) {
  final workspace = Directory.current.parent.parent;
  return Process.run('make', [
    '--dry-run',
    '--no-print-directory',
    'dev',
    'BIND_ADDRESS=$bindAddress',
    if (controlUrl != null) 'CONTROL_URL=$controlUrl',
  ], workingDirectory: workspace.path);
}

Future<ProcessResult> _validateIosControlUrl({
  String? bindAddress,
  String? controlUrl,
}) {
  final workspace = Directory.current.parent.parent;
  return Process.run('make', [
    '--no-print-directory',
    'validate-ios-control-url',
    if (bindAddress != null) 'BIND_ADDRESS=$bindAddress',
    if (controlUrl != null) 'CONTROL_URL=$controlUrl',
  ], workingDirectory: workspace.path);
}
