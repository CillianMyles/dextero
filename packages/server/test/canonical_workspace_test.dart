import 'dart:io';

import 'package:dextero_server/src/control/canonical_workspace.dart';
import 'package:test/test.dart';

void main() {
  test('pins a symbolic workspace to its original target', () async {
    if (Platform.isWindows) return;
    final sandbox = await Directory.systemTemp.createTemp(
      'dextero-canonical-workspace-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final original = await Directory('${sandbox.path}/original').create();
    final replacement = await Directory('${sandbox.path}/replacement').create();
    final link = Link('${sandbox.path}/workspace');
    await link.create(original.path);

    final pinned = await canonicalWorkspacePath(link.path);
    await link.delete();
    await link.create(replacement.path);

    expect(pinned, await original.resolveSymbolicLinks());
    expect(pinned, isNot(await link.resolveSymbolicLinks()));
  });
}
