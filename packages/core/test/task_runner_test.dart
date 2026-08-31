import 'package:dextero_core/dextero_core.dart';
import 'package:test/test.dart';

void main() {
  test('rejects an empty task before launching Codex', () async {
    final runner = CodexTaskRunner(workspace: '.');

    await expectLater(runner.run('   '), emitsError(isA<ArgumentError>()));
  });
}
