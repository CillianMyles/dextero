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
  });

  test('make dev probes loopback for a wildcard bind address', () async {
    final result = await _dryRunDev('0.0.0.0');

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(
      result.stdout,
      contains('curl --silent --output /dev/null "http://127.0.0.1:8080/"'),
    );
  });
}

Future<ProcessResult> _dryRunDev(String bindAddress) {
  final workspace = Directory.current.parent.parent;
  return Process.run('make', [
    '--dry-run',
    '--no-print-directory',
    'dev',
    'BIND_ADDRESS=$bindAddress',
  ], workingDirectory: workspace.path);
}
