import 'package:dextero_server/dextero_client.dart';

import 'chat_client.dart';
import 'jsonl_renderer.dart';
import 'terminal_io.dart';
import 'terminal_renderer.dart';

enum TerminalOutputMode { human, jsonl }

final class TerminalChat {
  TerminalChat({
    required TerminalChatClient client,
    required TerminalIo io,
    TerminalRenderer renderer = const TerminalRenderer(),
    JsonlRenderer jsonlRenderer = const JsonlRenderer(),
    this.outputMode = TerminalOutputMode.human,
    String Function()? correlationIdFactory,
  }) : _client = client,
       _io = io,
       _renderer = renderer,
       _jsonlRenderer = jsonlRenderer,
       _correlationIdFactory =
           correlationIdFactory ??
           (() =>
               'cli-${DateTime.now().toUtc().microsecondsSinceEpoch.toString()}');

  final TerminalChatClient _client;
  final TerminalIo _io;
  final TerminalRenderer _renderer;
  final JsonlRenderer _jsonlRenderer;
  final TerminalOutputMode outputMode;
  final String Function() _correlationIdFactory;
  final List<ChatEntry> _entries = [];
  final Set<String> _plainRenderedEntryIds = {};
  var _plainHeaderRendered = false;
  late HostStatus _status;

  Future<int> run({
    String? initialMessage,
    String? cancelRunId,
    String? approveRunId,
    String? approvalId,
    String? modelName,
  }) async {
    var failed = false;
    try {
      _status = await _client.status();
      if (modelName != null && modelName != _status.modelName) {
        _status = await _client.selectModel(modelName);
      }
      if (cancelRunId != null) {
        final cancelled = await _client.cancelRun(
          _status.conversationId,
          cancelRunId,
        );
        _io.writeln(
          outputMode == TerminalOutputMode.jsonl
              ? _jsonlRenderer.cancellationResult(
                  conversationId: _status.conversationId,
                  runId: cancelRunId,
                  accepted: cancelled,
                )
              : cancelled
              ? 'Cancellation requested for $cancelRunId.'
              : 'Run $cancelRunId is not active.',
        );
        return cancelled ? 0 : 1;
      }
      if (approveRunId != null && approvalId != null) {
        final approved = await _client.approveWork(
          _status.conversationId,
          approveRunId,
          approvalId,
        );
        _io.writeln(
          outputMode == TerminalOutputMode.jsonl
              ? _jsonlRenderer.approvalResult(
                  conversationId: _status.conversationId,
                  runId: approveRunId,
                  approvalId: approvalId,
                  accepted: approved,
                )
              : approved
              ? 'Approved $approvalId for $approveRunId.'
              : 'Approval $approvalId is not pending for $approveRunId.',
        );
        return approved ? 0 : 1;
      }
      _entries.addAll(await _client.history(_status.conversationId));
      _entries.sort((left, right) => left.sequence.compareTo(right.sequence));
      _render();

      if (initialMessage != null) {
        return await _send(initialMessage) ? 0 : 1;
      }

      while (true) {
        _io.write('you> ');
        final line = _io.readLine();
        if (line == null || line.trim() == '/exit') break;
        if (line.trim().isEmpty) continue;
        failed |= !await _send(line);
      }
      return failed ? 1 : 0;
    } on Object catch (error) {
      if (outputMode == TerminalOutputMode.jsonl) {
        _io.writeln(_jsonlRenderer.error(error));
      } else {
        _io.error('Dextero request failed: $error');
      }
      return 1;
    } finally {
      await _client.close();
    }
  }

  Future<bool> _send(String message) async {
    final normalized = message.trim();
    if (normalized.isEmpty) return true;
    final submission = await _client.submit(
      ChatSubmitRequest(
        conversationId: _status.conversationId,
        message: normalized,
        modelName: _status.modelName,
        correlationId: _correlationIdFactory(),
      ),
    );
    _add(submission.userEntry);
    _render();

    var succeeded = true;
    var terminalSeen = false;
    final afterSequence = _entries.isEmpty ? -1 : _entries.last.sequence;
    await for (final entry in _client.streamHistory(
      _status.conversationId,
      afterSequence,
    )) {
      _add(entry);
      if (entry.kind == ChatEntryKind.error &&
          entry.status == ChatEntryStatus.failed) {
        succeeded = false;
      }
      final terminal =
          entry.runId == submission.runId &&
          entry.kind == ChatEntryKind.lifecycle &&
          {
            ChatEntryStatus.completed,
            ChatEntryStatus.failed,
            ChatEntryStatus.cancelled,
          }.contains(entry.status);
      _render();
      if (terminal) {
        terminalSeen = true;
        succeeded &= entry.status == ChatEntryStatus.completed;
        break;
      }
    }
    if (!terminalSeen) {
      _io.error('Chat history stream ended before the response completed.');
      return false;
    }
    return succeeded;
  }

  void _add(ChatEntry entry) {
    if (_entries.any((existing) => existing.entryId == entry.entryId)) return;
    _entries.add(entry);
    _entries.sort((left, right) => left.sequence.compareTo(right.sequence));
  }

  void _render() {
    if (outputMode == TerminalOutputMode.jsonl) {
      for (final entry in _entries) {
        if (!_plainRenderedEntryIds.add(entry.entryId)) continue;
        _io.writeln(_jsonlRenderer.entry(entry));
      }
      return;
    }
    if (!_plainHeaderRendered) {
      _plainHeaderRendered = true;
      _io.writeln(
        '${_status.name} ${_status.version} — '
        '${_status.modelProvider} · ${_status.modelName}'
        '${_entries.isEmpty ? ' — no messages yet' : ''}',
      );
    }
    if (_entries.isEmpty) return;
    for (final entry in _entries) {
      if (!_plainRenderedEntryIds.add(entry.entryId)) continue;
      _io.writeln(_renderer.plainEntryLine(entry));
    }
  }
}
