import 'package:flutter_test/flutter_test.dart';

import 'package:handtalk/main.dart';

void main() {
  testWidgets('renders HandTalk home landing page and sticky footer navigation', (WidgetTester tester) async {
    await tester.pumpWidget(const HandTalkApp());

    // Verify Landing page hero elements
    expect(find.text('HandTalk'), findsOneWidget);
    expect(find.text('Open Camera'), findsOneWidget);
    expect(find.text('How It Works'), findsOneWidget);

    // Verify Sticky Footer navigation tabs
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Results'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });
}
