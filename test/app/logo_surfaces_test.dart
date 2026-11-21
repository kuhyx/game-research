// The full-window panels cover the home screen, so each carries the logo.
import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_wrapper.dart';
import 'notes_fixtures.dart';
import 'reader_fixtures.dart';
import 'reader_helpers.dart';

/// The logo is built and lies inside the window.
void expectLogoOnScreen(WidgetTester t) {
  final logo = find.byType(KLogo);
  expect(logo, findsOneWidget);
  final box = t.getRect(logo);
  final window = Offset.zero & t.view.physicalSize / t.view.devicePixelRatio;
  expect(box.width, greaterThan(0));
  expect(
    window.contains(box.topLeft) &&
        window.contains(box.bottomRight - const Offset(1, 1)),
    isTrue,
  );
}

void main() {
  setUpAll(loadInter);
  setUp(() => readerPointer = null);

  testWidgets('the reader toolbar shows the logo', (t) async {
    final w = FakeWrapper()..docs['/t/a.md'] = '# A';
    await openReader(t, w);
    await reveal(t);
    expectLogoOnScreen(t);
  });

  testWidgets('the notes panel shows the logo', (t) async {
    final w = FakeWrapper()..noteParts = twoParts();
    await openNotes(t, w);
    expectLogoOnScreen(t);
    await endNotes(t);
  });
}
