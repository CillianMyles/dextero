import 'package:dextero_core/dextero_core.dart';

/// Process-local dependency used by Serverpod endpoint instances.
abstract final class TaskRuntime {
  static TaskRunner runner = _UnavailableTaskRunner();
}

final class _UnavailableTaskRunner implements TaskRunner {
  @override
  Stream<CoreTaskEvent> run(String prompt) => Stream.error(
    StateError('The Dextero task runtime has not been initialized.'),
  );
}
