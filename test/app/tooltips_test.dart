import 'package:flutter_test/flutter_test.dart';
import 'package:game_research/app/copy_icon.dart';
import 'package:material_ui/material_ui.dart';

Future<void> pumpIcon(WidgetTester t, Future<void> Function()? onCopy) =>
    t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CopyIcon(semantic: 'copy it', size: 40, onCopy: onCopy),
        ),
      ),
    );

void main() {
  testWidgets('the copy icon names itself in one hover word', (t) async {
    await pumpIcon(t, () async {});
    expect(find.byTooltip('Copy'), findsOneWidget);
  });
}
