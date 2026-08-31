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
  final _promptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    _promptController.addListener(_refresh);
    widget.controller.initialize();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    widget.controller.dispose();
    _promptController
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final canRun =
        controller.configured &&
        controller.hostStatus != null &&
        !controller.busy &&
        _promptController.text.trim().isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(controller: controller),
                  const SizedBox(height: 28),
                  TextField(
                    key: const Key('task-prompt'),
                    controller: _promptController,
                    enabled: !controller.busy,
                    minLines: 3,
                    maxLines: 7,
                    decoration: const InputDecoration(
                      filled: true,
                      labelText: 'What should Dextero do?',
                      hintText:
                          'Inspect this workspace and summarize its architecture.',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: canRun
                        ? (_) => controller.runTask(_promptController.text)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      key: const Key('run-task'),
                      onPressed: canRun
                          ? () => controller.runTask(_promptController.text)
                          : null,
                      icon: controller.busy
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow_rounded),
                      label: Text(controller.busy ? 'Working…' : 'Run task'),
                    ),
                  ),
                  if (controller.error case final error?) ...[
                    const SizedBox(height: 16),
                    _ErrorBanner(message: error),
                  ],
                  const SizedBox(height: 20),
                  Expanded(child: _EventTimeline(events: controller.events)),
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
    return Row(
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
              Text('Local agent workspace'),
            ],
          ),
        ),
        Chip(
          avatar: Icon(
            status == null ? Icons.cloud_off_outlined : Icons.circle,
            size: 14,
            color: status == null ? null : Colors.green.shade700,
          ),
          label: Text(
            status == null
                ? 'Disconnected'
                : '${status.name} ${status.version}',
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Material(
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

class _EventTimeline extends StatelessWidget {
  const _EventTimeline({required this.events});

  final List<TaskEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Center(
        child: Text('Task progress and results will appear here.'),
      );
    }
    return ListView.separated(
      itemCount: events.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final event = events[index];
        final isOutput = event.kind == TaskEventKind.output;
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_eventIcon(event.kind), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.kind.name.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        event.message,
                        style: isOutput
                            ? const TextStyle(fontSize: 16, height: 1.45)
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _eventIcon(TaskEventKind kind) => switch (kind) {
    TaskEventKind.queued => Icons.schedule,
    TaskEventKind.running => Icons.sync,
    TaskEventKind.output => Icons.notes,
    TaskEventKind.completed => Icons.check_circle_outline,
    TaskEventKind.failed => Icons.error_outline,
  };
}
