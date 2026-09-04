import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('does not resolve Linux stat from the controlled workspace', () async {
    if (!Platform.isLinux) return;
    final workspace = await Directory.systemTemp.createTemp(
      'dextero-filesystem-identity-',
    );
    addTearDown(() => workspace.delete(recursive: true));
    final marker = File('${workspace.path}/fake-stat-ran');
    final fakeStat = File('${workspace.path}/stat');
    await fakeStat.writeAsString(
      '#!/bin/sh\n/usr/bin/touch "\$DEXTERO_FAKE_STAT_MARKER"\n'
      'printf "1:2:2000-01-01 00:00:00.000000000 +0000\\n"\n',
    );
    final chmod = await Process.run('/bin/chmod', ['+x', fakeStat.path]);
    expect(chmod.exitCode, 0, reason: chmod.stderr as String);
    final helper = File(
      '${Directory.current.path}/test/fixtures/'
      'resolve_filesystem_identity.dart',
    );

    final result = await Process.run(
      Platform.resolvedExecutable,
      [helper.path, workspace.path],
      workingDirectory: Directory.current.path,
      includeParentEnvironment: false,
      environment: {
        'PATH': workspace.path,
        'DEXTERO_FAKE_STAT_MARKER': marker.path,
      },
    );

    expect(result.exitCode, 0, reason: result.stderr as String);
    expect(result.stdout, startsWith('linux:'));
    expect(await marker.exists(), isFalse);
  });
}
