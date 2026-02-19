import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Klok/main.dart'; // Import the main KlokApp

void main() {
  testWidgets('Initial KlokApp loads Clock View and switches to Analog', (WidgetTester tester) async {
    // 1. Build the main application widget (KlokApp).
    await tester.pumpWidget(const KlokApp());
    await tester.pumpAndSettle(); 

    // --- Verify Initial Digital Clock State ---
    
    // Check for the Clock View App Bar Title
    expect(find.text('Klok: Clock'), findsOneWidget);

    // Check for the presence of the large digital clock display (large text style, 88.0)
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.style?.fontSize == 88.0,
      ),
      findsOneWidget,
      reason: 'Should find the large digital time display.',
    );

    // Check for the switch button text
    final switchButtonFinder = find.text('Switch to Analog');
    expect(switchButtonFinder, findsOneWidget);

    // --- Test Switch to Analog Clock ---

    // Tap the switch button
    await tester.tap(switchButtonFinder);
    await tester.pump();
    
    // Verify the button text changed
    expect(find.text('Switch to Digital'), findsOneWidget);
    expect(switchButtonFinder, findsNothing);

    // Verify the digital clock text is no longer present
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.style?.fontSize == 88.0,
      ),
      findsNothing,
      reason: 'Digital time display should be hidden after switching.',
    );
  });
}