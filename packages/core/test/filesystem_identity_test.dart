import 'dart:io';

import 'package:dextero_core/src/filesystem_identity.dart';
import 'package:dextero_core/src/trusted_executable.dart';
import 'package:test/test.dart';

void main() {
  test('accepts a non-FHS executable from an absolute Unix PATH', () async {
    if (Platform.isWindows) return;
    final sandbox = await Directory.systemTemp.createTemp(
      'dextero-non-fhs-probe-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final workspace = await Directory('${sandbox.path}/workspace').create();
    final bin = await Directory(
      '${sandbox.path}/nix/store/bin',
    ).create(recursive: true);
    final executable = await File('${bin.path}/stat').create();

    expect(
      await resolveTrustedExecutable(
        workspace,
        operatingSystemExecutableCandidates(
          'stat',
          environment: {'PATH': bin.path},
        ),
      ),
      await executable.resolveSymbolicLinks(),
    );
  });

  test('rejects an unavailable Linux filesystem birth time', () {
    expect(
      () => normalizeFilesystemIdentity(
        operatingSystem: 'linux',
        value: '7:9:-',
        path: '/workspace',
      ),
      throwsA(
        isA<FileSystemException>().having(
          (error) => error.message,
          'message',
          contains('filesystem birth time is unavailable'),
        ),
      ),
    );
  });

  test('retains Windows creation time in filesystem identity', () async {
    if (!Platform.isWindows) return;
    final directory = await Directory.systemTemp.createTemp(
      'dextero-windows-filesystem-identity-',
    );
    addTearDown(() => directory.delete(recursive: true));

    final identity = await resolveFilesystemIdentity(directory);
    final fields = identity.split(':');

    expect(fields, hasLength(4));
    expect(fields.first, 'windows');
    for (final field in fields.skip(1)) {
      expect(field, matches(RegExp(r'^[0-9a-f]{8,16}$')));
    }
  });

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
