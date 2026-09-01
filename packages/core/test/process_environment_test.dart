import 'dart:io';

import 'package:dextero_core/dextero_core.dart';
import 'package:test/test.dart';

void main() {
  test('generic process environment excludes ambient secrets', () {
    final filtered = filteredProcessEnvironment({
      'PATH': '/bin',
      'HOME': '/home/person',
      'OPENAI_API_KEY': 'secret',
      'DEXTERO_CONTROL_TOKEN': 'secret',
    });

    expect(filtered, {'PATH': '/bin', 'HOME': '/home/person'});
  });

  test('Codex ignores an unauthenticated isolated home', () async {
    final root = await Directory.systemTemp.createTemp('codex-home-');
    addTearDown(() => root.delete(recursive: true));

    final filtered = codexProcessEnvironment({
      'HOME': '/home/person',
      'CODEX_HOME': root.path,
    });

    expect(filtered['HOME'], '/home/person');
    expect(filtered, isNot(contains('CODEX_HOME')));
  });

  test('Codex preserves an authenticated explicit home', () async {
    final root = await Directory.systemTemp.createTemp('codex-home-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/auth.json').writeAsString('{}');

    expect(
      codexProcessEnvironment({'CODEX_HOME': root.path})['CODEX_HOME'],
      root.path,
    );
  });
}
