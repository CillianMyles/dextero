import 'package:dextero_server/dextero_client.dart';
import 'package:flutter/material.dart';

import 'src/dextero_controller.dart';

const _controlToken = String.fromEnvironment('DEXTERO_CONTROL_TOKEN');
const _controlUrl = String.fromEnvironment(
  'DEXTERO_CONTROL_URL',
  defaultValue: 'http://localhost:8080/',
);

void main() {
  runApp(
    DexteroApp(
      controller: DexteroController.fromEnvironment({
        if (_controlToken.isNotEmpty) 'DEXTERO_CONTROL_TOKEN': _controlToken,
        'DEXTERO_CONTROL_URL': _controlUrl,
      }),
    ),
  );
}

class DexteroApp extends StatelessWidget {
  const DexteroApp({required this.controller, super.key});

  final DexteroController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Dextero',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff335c67),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff7f5f0),
        useMaterial3: true,
      ),
      home: DexteroHomePage(controller: controller),
    );
  }
}

class DexteroHomePage extends StatefulWidget {
  const DexteroHomePage({required this.controller, super.key});

  final DexteroController controller;

  @override
  State<DexteroHomePage> createState() => _DexteroHomePageState();
}

class _DexteroHomePageState extends State<DexteroHomePage> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    _messageController.addListener(_refresh);
    widget.controller.initialize();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    widget.controller.dispose();
    _messageController
      ..removeListener(_refresh)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final sent = await widget.controller.submitMessage(_messageController.text);
    if (sent) _messageController.clear();
  }

  Future<void> _cancel() => widget.controller.cancelActiveRun();

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final canSend =
        controller.hostStatus != null &&
        !controller.busy &&
        _messageController.text.trim().isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(controller: controller),
                  const SizedBox(height: 18),
                  if (controller.error case final error?) ...[
                    _ErrorBanner(message: error),
                    const SizedBox(height: 12),
                  ],
                  Expanded(
                    child: _ConversationView(
                      state: controller.loadState,
                      entries: controller.entries,
                      scrollController: _scrollController,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _Composer(
                    messageController: _messageController,
                    enabled: controller.hostStatus != null && !controller.busy,
                    canSend: canSend,
                    submitting: controller.submitting,
                    cancelling: controller.cancelling,
                    working: controller.busy && !controller.submitting,
                    onSend: _send,
                    onCancel: _cancel,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final DexteroController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.hostStatus;
    final badges = <Widget>[
      if (status != null)
        Chip(
          key: const Key('model-provider'),
          avatar: const Icon(Icons.psychology_outlined, size: 16),
          label: Text(
            '${_displayName(status.modelProvider)} · ${status.modelName}',
          ),
        ),
      if (status != null)
        Tooltip(
          message: status.retentionNotice,
          child: const Chip(
            avatar: Icon(Icons.memory, size: 16),
            label: Text('Until restart'),
          ),
        ),
      Chip(
        avatar: Icon(
          status == null ? Icons.cloud_off_outlined : Icons.circle,
          size: 14,
          color: status == null ? null : Colors.green.shade700,
        ),
        label: Text(
          status == null ? 'Disconnected' : '${status.name} ${status.version}',
        ),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            key: const Key('compact-header'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Brand(),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: badges),
            ],
          );
        }
        return Row(
          children: [
            const Expanded(child: _Brand()),
            ...badges.expand((badge) => [const SizedBox(width: 8), badge]),
          ],
        );
      },
    );
  }

  String _displayName(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.auto_awesome,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
      const SizedBox(width: 14),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dextero',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            Text('One local conversation'),
          ],
        ),
      ),
    ],
  );
}

class _ConversationView extends StatelessWidget {
  const _ConversationView({
    required this.state,
    required this.entries,
    required this.scrollController,
  });

  final ChatLoadState state;
  final List<ChatEntry> entries;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    if (state == ChatLoadState.loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(key: Key('history-loading')),
            SizedBox(height: 12),
            Text('Loading conversation…'),
          ],
        ),
      );
    }
    if (state == ChatLoadState.empty || entries.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 38),
            SizedBox(height: 12),
            Text(
              'Start a conversation with Dextero.',
              key: Key('empty-history'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 4),
            Text('Messages and safe activity summaries will appear here.'),
          ],
        ),
      );
    }
    return ListView.separated(
      key: const Key('chat-history'),
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _ChatEntryCard(entry: entries[index]),
    );
  }
}

class _ChatEntryCard extends StatelessWidget {
  const _ChatEntryCard({required this.entry});

  final ChatEntry entry;

  @override
  Widget build(BuildContext context) {
    return switch (entry.kind) {
      ChatEntryKind.userMessage => _MessageBubble(entry: entry, user: true),
      ChatEntryKind.assistantMessage => _MessageBubble(
        entry: entry,
        user: false,
      ),
      _ => _ActivityRow(entry: entry),
    };
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.entry, required this.user});

  final ChatEntry entry;
  final bool user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Material(
          color: user ? scheme.primaryContainer : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user ? 'You' : 'Dextero',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 4),
                SelectableText(
                  entry.content,
                  key: Key('entry-${entry.entryId}'),
                  style: const TextStyle(fontSize: 16, height: 1.4),
                ),
                if (entry.truncated) ...[
                  const SizedBox(height: 5),
                  Text(
                    'Summary truncated',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});

  final ChatEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isError =
        entry.kind == ChatEntryKind.error ||
        entry.status == ChatEntryStatus.failed;
    final isWarning = entry.status == ChatEntryStatus.warning;
    final background = isError
        ? scheme.errorContainer
        : isWarning
        ? const Color(0xffffefd1)
        : scheme.surfaceContainerHighest;
    final foreground = isError
        ? scheme.onErrorContainer
        : isWarning
        ? const Color(0xff694c00)
        : scheme.onSurface;
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        key: Key('entry-${entry.entryId}'),
        color: background,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ExpansionTile(
            key: Key('activity-details-${entry.entryId}'),
            tilePadding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            iconColor: foreground,
            collapsedIconColor: foreground,
            shape: const Border(),
            collapsedShape: const Border(),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(_activityIcon(entry), size: 18, color: foreground),
                    Text(
                      _activityLabel(entry),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    _ActivityBadge(
                      label: _displayName(entry.status.name),
                      foreground: foreground,
                    ),
                    if (entry.truncated)
                      _ActivityBadge(
                        key: Key('activity-truncated-${entry.entryId}'),
                        label: 'Truncated',
                        foreground: foreground,
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  entry.content,
                  key: Key('activity-summary-${entry.entryId}'),
                  style: TextStyle(color: foreground, height: 1.35),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Text(
                      _timestamp(entry.createdAt),
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: foreground),
                    ),
                    Text(
                      '• ${_displayName(entry.source.name)}',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: foreground),
                    ),
                  ],
                ),
              ],
            ),
            children: [
              Divider(color: foreground.withValues(alpha: 0.25)),
              _TechnicalDetail(
                label: 'Event',
                value:
                    'v${entry.eventVersion} · ${_displayName(entry.family.name)}',
              ),
              _TechnicalDetail(label: 'Sequence', value: '${entry.sequence}'),
              if (entry.runId case final runId?)
                _TechnicalDetail(label: 'Run', value: runId),
              _TechnicalDetail(
                label: 'Correlation',
                value: entry.correlationId,
              ),
              if (entry.toolCallId case final toolCallId?)
                _TechnicalDetail(label: 'Tool call', value: toolCallId),
            ],
          ),
        ),
      ),
    );
  }

  String _activityLabel(ChatEntry entry) => switch (entry.kind) {
    ChatEntryKind.assistantDelta => 'Model output',
    ChatEntryKind.toolCall => '${_toolLabel(entry.toolName)} started',
    ChatEntryKind.toolOutput => '${_toolLabel(entry.toolName)} output',
    ChatEntryKind.toolResult => '${_toolLabel(entry.toolName)} result',
    ChatEntryKind.error => 'Agent error',
    ChatEntryKind.lifecycle => switch (entry.status) {
      ChatEntryStatus.queued => 'Queued',
      ChatEntryStatus.running => 'Agent activity',
      ChatEntryStatus.completed => 'Run completed',
      ChatEntryStatus.failed => 'Run failed',
      ChatEntryStatus.cancelled => 'Run cancelled',
      _ => 'Run update',
    },
    _ => _displayName(entry.kind.name),
  };

  String _toolLabel(String? toolName) => toolName == null
      ? 'Tool'
      : _displayName(toolName.replaceAll(RegExp(r'[._-]+'), ' '));

  String _timestamp(DateTime value) {
    final utc = value.toUtc();
    String two(int part) => part.toString().padLeft(2, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)} '
        '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)} UTC';
  }

  String _displayName(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

  IconData _activityIcon(ChatEntry entry) => switch (entry.kind) {
    ChatEntryKind.assistantDelta => Icons.notes_outlined,
    ChatEntryKind.toolCall => Icons.build_outlined,
    ChatEntryKind.toolOutput => Icons.terminal_outlined,
    ChatEntryKind.toolResult =>
      entry.status == ChatEntryStatus.failed
          ? Icons.error_outline
          : Icons.check_circle_outline,
    ChatEntryKind.error => Icons.error_outline,
    _ => switch (entry.status) {
      ChatEntryStatus.queued => Icons.schedule,
      ChatEntryStatus.running => Icons.sync,
      ChatEntryStatus.completed => Icons.check_circle_outline,
      ChatEntryStatus.failed => Icons.error_outline,
      ChatEntryStatus.cancelled => Icons.cancel_outlined,
      _ => Icons.info_outline,
    },
  };
}

class _ActivityBadge extends StatelessWidget {
  const _ActivityBadge({
    required this.label,
    required this.foreground,
    super.key,
  });

  final String label;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      border: Border.all(color: foreground.withValues(alpha: 0.35)),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: foreground),
    ),
  );
}

class _TechnicalDetail extends StatelessWidget {
  const _TechnicalDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(label, style: Theme.of(context).textTheme.labelSmall),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.messageController,
    required this.enabled,
    required this.canSend,
    required this.submitting,
    required this.cancelling,
    required this.working,
    required this.onSend,
    required this.onCancel,
  });

  final TextEditingController messageController;
  final bool enabled;
  final bool canSend;
  final bool submitting;
  final bool cancelling;
  final bool working;
  final Future<void> Function() onSend;
  final Future<void> Function() onCancel;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 1,
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const Key('chat-message'),
                controller: messageController,
                enabled: enabled,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: working ? 'Dextero is working…' : 'Message Dextero',
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (working)
              IconButton.filledTonal(
                key: const Key('cancel-run'),
                tooltip: 'Cancel run',
                onPressed: cancelling ? null : onCancel,
                icon: cancelling
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.stop_rounded),
              )
            else
              IconButton.filled(
                key: const Key('send-message'),
                tooltip: 'Send message',
                onPressed: canSend ? onSend : null,
                icon: submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_upward_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('error-banner'),
    color: Theme.of(context).colorScheme.errorContainer,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}
