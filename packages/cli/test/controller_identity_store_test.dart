import 'dart:io';

import 'package:dextero_cli/dextero_cli.dart';
import 'package:test/test.dart';

void main() {
  test('persists and reuses the CLI controller identity', () async {
    final sandbox = await Directory.systemTemp.createTemp('dextero-cli-id-');
    addTearDown(() => sandbox.delete(recursive: true));
    final stateFile = File('${sandbox.path}/controller.json');

    final first = await CliControllerIdentityStore(
      stateFile: stateFile,
    ).load(const {});
    final second = await CliControllerIdentityStore(
      stateFile: stateFile,
    ).load(const {});

    expect(first.id, startsWith('controller_'));
    expect(second.id, first.id);
    expect(second.name, 'Dextero CLI');
  });

  test('serializes concurrent first-run identity creation', () async {
    final sandbox = await Directory.systemTemp.createTemp('dextero-cli-id-');
    addTearDown(() => sandbox.delete(recursive: true));
    final stateFile = File('${sandbox.path}/controller.json');

    final identities = await Future.wait([
      CliControllerIdentityStore(stateFile: stateFile).load(const {}),
      CliControllerIdentityStore(stateFile: stateFile).load(const {}),
    ]);
    final reloaded = await CliControllerIdentityStore(
      stateFile: stateFile,
    ).load(const {});

    expect(identities[1].id, identities[0].id);
    expect(reloaded.id, identities[0].id);
  });

  test('serializes first-run identity creation across processes', () async {
    final sandbox = await Directory.systemTemp.createTemp('dextero-cli-id-');
    addTearDown(() => sandbox.delete(recursive: true));
    final stateFile = File('${sandbox.path}/controller.json');
    final helper = File(
      '${Directory.current.path}/test/fixtures/load_controller_identity.dart',
    );

    Future<ProcessResult> startHelper() => Process.run(
      Platform.resolvedExecutable,
      [helper.path, stateFile.path],
      workingDirectory: Directory.current.path,
    );

    final results = await Future.wait([startHelper(), startHelper()]);
    for (final result in results) {
      expect(result.exitCode, 0, reason: result.stderr as String);
    }
    expect(
      (results[1].stdout as String).trim(),
      (results[0].stdout as String).trim(),
    );
  });

  test('fails closed rather than rotating a malformed identity', () async {
    final sandbox = await Directory.systemTemp.createTemp('dextero-cli-id-');
    addTearDown(() => sandbox.delete(recursive: true));
    final stateFile = File('${sandbox.path}/controller.json');
    await stateFile.writeAsString('{"version":1,"controllerId":"bad"}');

    await expectLater(
      CliControllerIdentityStore(stateFile: stateFile).load(const {}),
      throwsA(isA<FormatException>()),
    );
  });
}
