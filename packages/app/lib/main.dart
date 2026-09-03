import 'package:dextero_server/dextero_client.dart';
import 'package:flutter/material.dart' show SelectableText, ThemeMode;
import 'package:flutter/services.dart' show LogicalKeyboardKey, TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:shad/shad.dart';

import 'src/dextero_controller.dart';
import 'src/dextero_design.dart';

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
    return ShadApp(
      debugShowCheckedModeBanner: false,
      title: 'Dextero',
      theme: DexteroDesign.lightTheme,
      darkTheme: DexteroDesign.darkTheme,
      themeMode: ThemeMode.system,
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

  Future<void> _approve() => widget.controller.approvePendingWork();

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = ShadTheme.of(context);
    final canSend =
        controller.hostStatus != null &&
        !controller.busy &&
        _messageController.text.trim().isNotEmpty;

    return ColoredBox(
      color: theme.colorScheme.background,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: DexteroDesign.contentMaxWidth,
              ),
              child: Padding(
                padding: DexteroDesign.pagePadding(constraints.maxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(controller: controller),
                    const SizedBox(height: 20),
                    if (controller.error case final error?) ...[
                      _ErrorBanner(message: error),
                      const SizedBox(height: 12),
                    ],
                    Expanded(
                      child: _ConversationPanel(
                        state: controller.loadState,
                        entries: controller.entries,
                        scrollController: _scrollController,
                      ),
                    ),
                    if (controller.pendingApproval case final approval?) ...[
                      const SizedBox(height: 12),
                      _ApprovalPrompt(
                        approval: approval,
                        approving: controller.approving,
                        onApprove: _approve,
                      ),
                    ],
                    const SizedBox(height: 12),
                    _Composer(
                      messageController: _messageController,
                      enabled:
                          controller.hostStatus != null && !controller.busy,
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
        _StatusBadge(
          key: const Key('model-provider'),
          icon: LucideIcons.bot,
          label: '${_displayName(status.modelProvider)} · ${status.modelName}',
        ),
      if (status != null)
        ShadTooltip(
          builder: (context) => Text(status.retentionNotice),
          child: const _StatusBadge(
            icon: LucideIcons.database,
            label: 'Until restart',
          ),
        ),
      _StatusBadge(
        icon: status == null ? LucideIcons.cloudOff : LucideIcons.circle,
        iconColor: status == null
            ? null
            : DexteroDesign.success(ShadTheme.of(context).brightness),
        label: status == null
            ? 'Disconnected'
            : '${status.name} ${status.version}',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < DexteroDesign.compactBreakpoint) {
          return Column(
            key: const Key('compact-header'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Brand(),
              const SizedBox(height: 14),
              Wrap(spacing: 6, runSpacing: 6, children: badges),
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
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.foreground,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            LucideIcons.sparkles,
            size: 19,
            color: theme.colorScheme.background,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dextero',
                style: theme.textTheme.h3.copyWith(
                  color: theme.colorScheme.foreground,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'Local agent workspace',
                style: theme.textTheme.small.copyWith(
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.icon,
    required this.label,
    this.iconColor,
    super.key,
  });

  final IconData icon;
  final String label;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadBadge.outline(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: iconColor ?? theme.colorScheme.mutedForeground,
          ),
          const SizedBox(width: 6),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _ConversationPanel extends StatelessWidget {
  const _ConversationPanel({
    required this.state,
    required this.entries,
    required this.scrollController,
  });

  final ChatLoadState state;
  final List<ChatEntry> entries;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        border: Border.all(color: theme.colorScheme.border),
        borderRadius: theme.radius,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  LucideIcons.messagesSquare,
                  size: 16,
                  color: theme.colorScheme.mutedForeground,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Conversation',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.small.copyWith(
                      color: theme.colorScheme.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  entries.isEmpty
                      ? 'No messages'
                      : '${entries.length} ${entries.length == 1 ? 'event' : 'events'}',
                  style: theme.textTheme.small.copyWith(
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: theme.colorScheme.border),
          Expanded(
            child: _ConversationView(
              state: state,
              entries: entries,
              scrollController: scrollController,
            ),
          ),
        ],
      ),
    );
  }
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
            ShadSpinner(
              key: Key('history-loading'),
              size: 22,
              semanticLabel: 'Loading conversation',
            ),
            SizedBox(height: 12),
            Text('Loading conversation…'),
          ],
        ),
      );
    }
    if (state == ChatLoadState.empty || entries.isEmpty) {
      return const ShadEmpty(
        icon: Icon(LucideIcons.messageSquare),
        title: Text(
          'Start a conversation with Dextero.',
          key: Key('empty-history'),
        ),
        description: Text(
          'Messages and safe activity summaries will appear here.',
        ),
      );
    }
    return ListView.separated(
      key: const Key('chat-history'),
      controller: scrollController,
      padding: const EdgeInsets.all(16),
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
      ChatEntryKind.approval => _ActivityRow(entry: entry),
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
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: DexteroDesign.messageMaxWidth,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: user ? scheme.primary : scheme.background,
            border: user ? null : Border.all(color: scheme.border),
            borderRadius: user
                ? const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    topRight: Radius.circular(4),
                    bottomLeft: Radius.circular(14),
                    bottomRight: Radius.circular(14),
                  )
                : const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                    bottomRight: Radius.circular(14),
                  ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user ? 'You' : 'Dextero',
                  style: theme.textTheme.small.copyWith(
                    color: user
                        ? scheme.primaryForeground.withValues(alpha: 0.76)
                        : scheme.mutedForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  entry.content,
                  key: Key('entry-${entry.entryId}'),
                  style: theme.textTheme.p.copyWith(
                    color: user ? scheme.primaryForeground : scheme.foreground,
                    height: 1.45,
                  ),
                ),
                if (entry.truncated) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Summary truncated',
                    style: theme.textTheme.small.copyWith(
                      color: user
                          ? scheme.primaryForeground.withValues(alpha: 0.7)
                          : scheme.mutedForeground,
                    ),
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
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final isError =
        entry.kind == ChatEntryKind.error ||
        entry.status == ChatEntryStatus.failed;
    final isWarning = entry.status == ChatEntryStatus.warning;
    final background = isError
        ? scheme.destructive.withValues(alpha: 0.08)
        : isWarning
        ? DexteroDesign.warning(
            theme.brightness,
          ).withValues(alpha: theme.brightness == Brightness.dark ? 0.12 : 0.08)
        : scheme.muted.withValues(alpha: 0.58);
    final foreground = isError
        ? scheme.destructive
        : isWarning
        ? DexteroDesign.warning(theme.brightness)
        : scheme.foreground;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: Key('entry-${entry.entryId}'),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(
            color: isError || isWarning
                ? foreground.withValues(alpha: 0.24)
                : scheme.border,
          ),
          borderRadius: theme.radius,
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: DexteroDesign.messageMaxWidth,
          ),
          child: ShadCollapsible(
            trigger: (context, open, toggle) => FocusableActionDetector(
              key: Key('activity-details-${entry.entryId}'),
              mouseCursor: SystemMouseCursors.click,
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
              },
              actions: {
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    toggle();
                    return null;
                  },
                ),
              },
              child: Semantics(
                button: true,
                expanded: open,
                onTap: toggle,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: toggle,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(13, 11, 11, 11),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            _activityIcon(entry),
                            size: 16,
                            color: foreground,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 7,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    _activityLabel(entry),
                                    style: theme.textTheme.small.copyWith(
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
                                      key: Key(
                                        'activity-truncated-${entry.entryId}',
                                      ),
                                      label: 'Truncated',
                                      foreground: foreground,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                entry.content,
                                key: Key('activity-summary-${entry.entryId}'),
                                style: theme.textTheme.small.copyWith(
                                  color: scheme.foreground,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    _timestamp(entry.createdAt),
                                    style: theme.textTheme.small.copyWith(
                                      color: scheme.mutedForeground,
                                    ),
                                  ),
                                  Text(
                                    '• ${_displayName(entry.source.name)}',
                                    style: theme.textTheme.small.copyWith(
                                      color: scheme.mutedForeground,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        AnimatedRotation(
                          turns: open ? 0.5 : 0,
                          duration: const Duration(milliseconds: 160),
                          child: Icon(
                            LucideIcons.chevronDown,
                            size: 16,
                            color: scheme.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(39, 0, 13, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: scheme.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  _TechnicalDetail(
                    label: 'Event',
                    value:
                        'v${entry.eventVersion} · ${_displayName(entry.family.name)}',
                  ),
                  _TechnicalDetail(
                    label: 'Sequence',
                    value: '${entry.sequence}',
                  ),
                  if (entry.runId case final runId?)
                    _TechnicalDetail(label: 'Run ID', value: runId),
                  _TechnicalDetail(
                    label: 'Correlation ID',
                    value: entry.correlationId,
                  ),
                  if (entry.toolCallId case final toolCallId?)
                    _TechnicalDetail(label: 'Tool call', value: toolCallId),
                  if (entry.approvalId case final approvalId?)
                    _TechnicalDetail(label: 'Approval ID', value: approvalId),
                ],
              ),
            ),
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
    ChatEntryKind.approval => switch (entry.status) {
      ChatEntryStatus.pending => 'Approval required',
      ChatEntryStatus.approved => 'Action approved',
      ChatEntryStatus.cancelled => 'Approval cancelled',
      _ => 'Approval update',
    },
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
    ChatEntryKind.assistantDelta => LucideIcons.fileText,
    ChatEntryKind.toolCall => LucideIcons.wrench,
    ChatEntryKind.toolOutput => LucideIcons.terminal,
    ChatEntryKind.toolResult =>
      entry.status == ChatEntryStatus.failed
          ? LucideIcons.circleAlert
          : LucideIcons.checkCircle2,
    ChatEntryKind.approval =>
      entry.status == ChatEntryStatus.pending
          ? LucideIcons.shieldAlert
          : LucideIcons.shieldCheck,
    ChatEntryKind.error => LucideIcons.circleAlert,
    _ => switch (entry.status) {
      ChatEntryStatus.queued => LucideIcons.clock3,
      ChatEntryStatus.running => LucideIcons.loaderCircle,
      ChatEntryStatus.completed => LucideIcons.checkCircle2,
      ChatEntryStatus.failed => LucideIcons.circleAlert,
      ChatEntryStatus.cancelled => LucideIcons.circleStop,
      _ => LucideIcons.info,
    },
  };
}

class _ApprovalPrompt extends StatelessWidget {
  const _ApprovalPrompt({
    required this.approval,
    required this.approving,
    required this.onApprove,
  });

  final ChatEntry approval;
  final bool approving;
  final Future<void> Function() onApprove;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final warning = DexteroDesign.warning(theme.brightness);
    return Container(
      key: const Key('approval-prompt'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: warning.withValues(alpha: 0.08),
        border: Border.all(color: warning.withValues(alpha: 0.28)),
        borderRadius: theme.radius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(LucideIcons.shieldAlert, size: 18, color: warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Approval required',
                  style: theme.textTheme.small.copyWith(
                    color: theme.colorScheme.foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  approval.content,
                  style: theme.textTheme.small.copyWith(
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ShadButton(
            key: const Key('approve-work'),
            enabled: !approving,
            onPressed: approving ? null : onApprove,
            child: approving
                ? const ShadSpinner(size: 14)
                : const Text('Approve'),
          ),
        ],
      ),
    );
  }
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
  Widget build(BuildContext context) => ShadBadge.outline(
    foregroundColor: foreground,
    backgroundColor: const Color(0x00000000),
    child: Text(label),
  );
}

class _TechnicalDetail extends StatelessWidget {
  const _TechnicalDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.mutedForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.small.copyWith(
                color: theme.colorScheme.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
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
    final theme = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        border: Border.all(color: theme.colorScheme.border),
        borderRadius: theme.radius,
        boxShadow: [
          BoxShadow(
            color: const Color(0xff000000).withValues(
              alpha: theme.brightness == Brightness.dark ? 0.18 : 0.05,
            ),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: ShadInput(
              key: const Key('chat-message'),
              controller: messageController,
              enabled: enabled,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              placeholder: Text(
                working ? 'Dextero is working…' : 'Message Dextero',
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (working)
            ShadTooltip(
              builder: (context) => const Text('Cancel run'),
              child: ShadGestureDetector(
                child: ShadIconButton.destructive(
                  key: const Key('cancel-run'),
                  semanticLabel: 'Cancel run',
                  enabled: !cancelling,
                  onPressed: cancelling ? null : onCancel,
                  icon: cancelling
                      ? const ShadSpinner(size: 16)
                      : const Icon(LucideIcons.square),
                ),
              ),
            )
          else
            ShadTooltip(
              builder: (context) => const Text('Send message'),
              child: ShadGestureDetector(
                child: ShadIconButton(
                  key: const Key('send-message'),
                  semanticLabel: 'Send message',
                  enabled: canSend,
                  onPressed: canSend ? onSend : null,
                  icon: submitting
                      ? const ShadSpinner(size: 16)
                      : const Icon(LucideIcons.arrowUp),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => ShadAlert.destructive(
    key: const Key('error-banner'),
    icon: const Icon(LucideIcons.circleAlert),
    title: const Text('Connection problem'),
    description: Text(message),
  );
}
