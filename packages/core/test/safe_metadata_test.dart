import 'package:dextero_core/dextero_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'preserves message formatting while redacting and removing controls',
    () {
      final summary = SafeMetadata.message(
        'Line one\n\n  code\tvalue\nsecret=hidden\x1b[2J',
      );

      expect(summary.text, 'Line one\n\n  code  value\nsecret=[REDACTED]');
      expect(summary.truncated, isFalse);
    },
  );

  test('never includes unstructured tool failure output', () {
    final summary = SafeMetadata.toolResult(
      'run_command',
      'password=hunter2 and raw stderr',
      success: false,
    );

    expect(summary.text, 'run_command failed');
    expect(summary.text, isNot(contains('hunter2')));
    expect(summary.text, isNot(contains('stderr')));
  });
}
