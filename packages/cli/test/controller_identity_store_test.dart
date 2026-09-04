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
