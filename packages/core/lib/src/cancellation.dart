import 'dart:async';

final class RunCancelledException implements Exception {
  const RunCancelledException([this.message = 'Run cancelled']);

  final String message;

  @override
  String toString() => message;
}

final class CancellationToken {
  CancellationToken._(this._cancelled);

  final Future<void> _cancelled;
  var _isCancellationRequested = false;

  Future<void> get whenCancelled => _cancelled;
  bool get isCancellationRequested => _isCancellationRequested;

  void throwIfCancellationRequested() {
    if (_isCancellationRequested) throw const RunCancelledException();
  }
}

final class CancellationController {
  CancellationController() : _completer = Completer<void>() {
    token = CancellationToken._(_completer.future);
  }

  final Completer<void> _completer;
  late final CancellationToken token;

  bool cancel() {
    if (_completer.isCompleted) return false;
    token._isCancellationRequested = true;
    _completer.complete();
    return true;
  }
}
