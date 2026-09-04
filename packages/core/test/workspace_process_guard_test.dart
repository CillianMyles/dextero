import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dextero_core/src/control_identity.dart';
import 'package:dextero_core/src/filesystem_identity.dart';
import 'package:test/test.dart';

void main() {
  test('rejects repository changes inside the child guard', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'dextero-process-topology-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final workspace = await Directory('${sandbox.path}/workspace').create();
    final gitDirectory = await Directory('${workspace.path}/.git').create();
    final registry = LocalIdentityRegistry(
      stateFile: File('${sandbox.path}/state/identities.json'),
    );
    await registry.resolve(workspace.path);
    final expectedFilesystemIdentity = await resolveFilesystemIdentity(
      workspace,
    );
    final expectedRepositoryTopology = await resolveRepositoryTopologyIdentity(
      workspace,
    );
    final launched = File('${workspace.path}/launched');
    final command = File('${workspace.path}/command.dart');
    await command.writeAsString(
      "import 'dart:io';\n"
      "void main() => File('launched').writeAsStringSync('yes');\n",
    );
    await File(
      '${gitDirectory.path}/dextero-project-identity-v1',
    ).writeAsString('repository_0000000000000000\n');
    final guard = File.fromUri(
      (await Isolate.resolvePackageUri(
        Uri.parse('package:dextero_core/src/workspace_process_guard.dart'),
      ))!,
    );
    final startup = File('${sandbox.path}/startup.json');

    final result = await Process.run(Platform.resolvedExecutable, [
      guard.path,
      expectedFilesystemIdentity,
      expectedRepositoryTopology,
      startup.path,
      Platform.resolvedExecutable,
      command.path,
    ], workingDirectory: workspace.path);

    expect(result.exitCode, 126, reason: result.stderr as String);
    expect(result.stderr, contains('Configured workspace changed'));
    expect(jsonDecode(await startup.readAsString()), {'status': 'rejected'});
    expect(await launched.exists(), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
