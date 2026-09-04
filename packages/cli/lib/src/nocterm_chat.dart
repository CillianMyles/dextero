import 'dart:async';

import 'package:dextero_server/dextero_client.dart';
import 'package:nocterm/nocterm.dart';

import 'chat_client.dart';
import 'terminal_renderer.dart';

typedef TuiExit = void Function(int exitCode);

Future<int> runNoctermChat({
  required TerminalChatClient client,
  String? modelName,
  String Function()? correlationIdFactory,
}) async {
  var exitCode = 0;
  try {
    await runApp(
      DexteroTui(
        client: client,
        modelName: modelName,
        correlationIdFactory: correlationIdFactory,
        onExit: (code) {
          exitCode = code;
          shutdownApp(code);
        },
      ),
      enableHotReload: false,
    );
    return exitCode;
  } finally {
    await client.close();
  }
}

final class DexteroTui extends StatefulComponent {
  DexteroTui({
    required this.client,
    required this.onExit,
    this.modelName,
    String Function()? correlationIdFactory,
    super.key,
  }) : correlationIdFactory =
           correlationIdFactory ??
           (() =>
               'cli-${DateTime.now().toUtc().microsecondsSinceEpoch.toString()}');

  final TerminalChatClient client;
  final TuiExit onExit;
  final String? modelName;
  final String Function() correlationIdFactory;

  @override
  State<DexteroTui> createState() => _DexteroTuiState();
}

final class _DexteroTuiState extends State<DexteroTui> {
  static const _background = Color.fromRGB(13, 17, 23);
  static const _panel = Color.fromRGB(22, 27, 34);
  static const _muted = Color.fromRGB(139, 148, 158);
  static const _accent = Color.fromRGB(88, 166, 255);

  final _entries = <ChatEntry>[];
  final _inputController = TextEditingController();
  final _scrollController = AutoScrollController();
  final _renderer = const TerminalRenderer();

  HostStatus? _status;
  String _notice = 'Connecting to the local Dextero host…';
  bool _sending = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      var status = await component.client.status();
      final requestedModel = component.modelName;
      if (requestedModel != null && requestedModel != status.modelName) {
        status = await component.client.selectModel(requestedModel);
      }
      final history = await component.client.history(status.conversationId);
      history.sort((left, right) => left.sequence.compareTo(right.sequence));
      if (!mounted) return;
      setState(() {
        _status = status;
        _entries
          ..clear()
          ..addAll(history);
        _notice = 'Ready';
      });
    } on Object catch (error) {
      _showError('Unable to connect: $error');
    }
  }

  Future<void> _submit(String value) async {
    final message = value.trim();
    if (message == '/exit') {
      _quit();
      return;
    }
    if (message.isEmpty || _sending || _status == null) return;

    if (message == '/models' ||
        message == '/model' ||
        message.startsWith('/model ')) {
      _inputController.clear();
      await _selectModel(message);
      return;
    }

    _inputController.clear();
    setState(() {
      _sending = true;
      _notice = 'Dextero is working…';
    });

    try {
      final status = _status!;
      final submission = await component.client.submit(
        ChatSubmitRequest(
          conversationId: status.conversationId,
          message: message,
          modelName: status.modelName,
          correlationId: component.correlationIdFactory(),
        ),
      );
      _add(submission.userEntry);

      var terminalSeen = false;
      var succeeded = true;
      final afterSequence = _entries.last.sequence;
      await for (final entry in component.client.streamHistory(
        status.conversationId,
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
        if (!terminal) continue;
        terminalSeen = true;
        succeeded &= entry.status == ChatEntryStatus.completed;
        break;
      }

      if (!terminalSeen) {
        throw StateError(
          'Chat history stream ended before the response completed.',
        );
      }
      if (!mounted) return;
      setState(() {
        _sending = false;
        _failed |= !succeeded;
        _notice = succeeded ? 'Ready' : 'The last run failed';
      });
    } on Object catch (error) {
      _showError('Request failed: $error');
    }
  }

  Future<void> _selectModel(String command) async {
    final status = _status!;
    if (_entries.isNotEmpty) {
      _showNotice('Model selection is locked after the first message.');
      return;
    }
    final parts = command.split(RegExp(r'\s+'));
    if (parts.length != 2 || command == '/models') {
      _showNotice('Models: ${status.availableModels.join(', ')}');
      return;
    }
    final modelName = parts[1];
    if (!status.availableModels.contains(modelName)) {
      _showNotice(
        'Unknown model. Choose: ${status.availableModels.join(', ')}',
      );
      return;
    }
    if (modelName == status.modelName) {
      _showNotice('Already using $modelName');
      return;
    }
    setState(() {
      _sending = true;
      _notice = 'Selecting $modelName…';
    });
    try {
      final selected = await component.client.selectModel(modelName);
      if (!mounted) return;
      setState(() {
        _status = selected;
        _sending = false;
        _notice = 'Using ${selected.modelName}';
      });
    } on Object catch (error) {
      _showError('Model selection failed: $error');
    }
  }

  void _showNotice(String message) {
    if (!mounted) return;
    setState(() => _notice = message);
  }

  void _add(ChatEntry entry) {
    if (!mounted ||
        _entries.any((existing) => existing.entryId == entry.entryId)) {
      return;
    }
    setState(() {
      _entries.add(entry);
      _entries.sort((left, right) => left.sequence.compareTo(right.sequence));
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _failed = true;
      _sending = false;
      _notice = message;
    });
  }

  void _quit() => component.onExit(_failed ? 1 : 0);

  bool _handleGlobalKey(KeyboardEvent event) {
    if (event.isControlPressed &&
        {LogicalKey.keyC, LogicalKey.keyD}.contains(event.logicalKey)) {
      _quit();
      return true;
    }
    return false;
  }

  @override
  Component build(BuildContext context) {
    final status = _status;
    return Focusable(
      focused: true,
      onKeyEvent: _handleGlobalKey,
      child: Container(
        color: _background,
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              decoration: BoxDecoration(
                color: _panel,
                border: BoxBorder(bottom: BorderSide(color: _accent)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        status == null
                            ? 'DEXTERO'
                            : 'DEXTERO  ${_renderer.safeText(status.name)} ${_renderer.safeText(status.version)}',
                        style: TextStyle(
                          color: Colors.brightWhite,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (status != null)
                        Text(
                          '${_renderer.safeText(status.modelProvider)} · ${_renderer.safeText(status.modelName)}',
                          style: TextStyle(color: _muted),
                        ),
                    ],
                  ),
                  if (status != null)
                    Text(
                      _renderer.safeText(
                        '${status.projectName}/${status.workspaceName} · '
                        '${status.controller.name} · ${status.retentionNotice}',
                      ),
                      style: TextStyle(color: _muted),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _entries.isEmpty
                  ? Center(
                      child: Text(
                        status == null
                            ? 'Connecting…'
                            : 'No messages yet. Use /model <name> or type a message.',
                        style: TextStyle(color: _muted),
                      ),
                    )
                  : Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.symmetric(
                          horizontal: 1,
                          vertical: 1,
                        ),
                        itemCount: _entries.length,
                        itemBuilder: (context, index) => _EntryView(
                          entry: _entries[index],
                          renderer: _renderer,
                        ),
                      ),
                    ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 1, vertical: 1),
              decoration: BoxDecoration(
                color: _panel,
                border: BoxBorder(top: BorderSide(color: Colors.brightBlack)),
              ),
              child: Row(
                children: [
                  Text('you › ', style: TextStyle(color: Colors.brightMagenta)),
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      focused: !_sending,
                      enabled: !_sending,
                      placeholder: status == null
                          ? _failed
                                ? 'Type /exit to leave'
                                : 'Waiting for host…'
                          : _sending
                          ? 'Waiting for Dextero…'
                          : 'Ask Dextero…',
                      style: TextStyle(color: Colors.brightWhite),
                      placeholderStyle: TextStyle(color: _muted),
                      onSubmitted: _submit,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 2),
              color: _failed ? Color.fromRGB(82, 32, 36) : _panel,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _renderer.safeText(_notice),
                      style: TextStyle(
                        color: _failed ? Colors.brightRed : _muted,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  Text(
                    'Enter send  ·  /models list  ·  /exit or Ctrl+C quit',
                    style: TextStyle(color: _muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _EntryView extends StatelessComponent {
  const _EntryView({required this.entry, required this.renderer});

  final ChatEntry entry;
  final TerminalRenderer renderer;

  @override
  Component build(BuildContext context) {
    final presentation = _presentation(entry);
    final content = renderer.entryContent(entry);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 16,
            child: Text(
              '${presentation.symbol} ${renderer.safeText(presentation.label)}',
              style: TextStyle(color: presentation.color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: entry.kind == ChatEntryKind.assistantMessage
                ? MarkdownText(content)
                : Text(content, style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  ({String symbol, String label, Color color}) _presentation(ChatEntry entry) {
    return switch (entry.kind) {
      ChatEntryKind.userMessage => (
        symbol: 'YOU',
        label: 'you',
        color: Colors.brightMagenta,
      ),
      ChatEntryKind.assistantMessage => (
        symbol: 'DEX',
        label: 'dextero',
        color: Colors.brightCyan,
      ),
      ChatEntryKind.assistantDelta => (
        symbol: '…',
        label: 'model output',
        color: Colors.cyan,
      ),
      ChatEntryKind.toolCall => (
        symbol: '›',
        label: entry.toolName ?? 'tool',
        color: Colors.brightBlue,
      ),
      ChatEntryKind.toolOutput => (
        symbol: '│',
        label: entry.toolName ?? 'tool output',
        color: Colors.blue,
      ),
      ChatEntryKind.toolResult => (
        symbol: entry.status == ChatEntryStatus.failed ? '×' : '✓',
        label: entry.toolName ?? 'tool',
        color: entry.status == ChatEntryStatus.failed
            ? Colors.brightRed
            : Colors.brightGreen,
      ),
      ChatEntryKind.approval => switch (entry.status) {
        ChatEntryStatus.pending => (
          symbol: '?',
          label: 'approval',
          color: Colors.brightYellow,
        ),
        ChatEntryStatus.approved => (
          symbol: '✓',
          label: 'approved',
          color: Colors.brightGreen,
        ),
        ChatEntryStatus.cancelled => (
          symbol: '×',
          label: 'cancelled',
          color: Colors.brightYellow,
        ),
        _ => (symbol: '!', label: 'approval', color: Colors.brightYellow),
      },
      ChatEntryKind.lifecycle => (
        symbol: '·',
        label: entry.status.name,
        color: Colors.brightYellow,
      ),
      ChatEntryKind.error => (
        symbol: '×',
        label: 'error',
        color: Colors.brightRed,
      ),
    };
  }
}
