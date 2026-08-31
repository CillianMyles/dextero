import 'package:dextero_app/main.dart';
import 'package:dextero_app/src/dextero_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('explains how to configure a disconnected app', (tester) async {
    final controller = DexteroController(
      token: null,
      serverUrl: 'http://localhost:8080/',
    );

    await tester.pumpWidget(DexteroApp(controller: controller));
    await tester.pump();

    expect(find.text('Dextero'), findsOneWidget);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.textContaining('make app-web'), findsOneWidget);
    expect(tester.widget(find.byKey(const Key('run-task'))), isNotNull);
  });
}
