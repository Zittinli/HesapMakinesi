import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesap_makinesi/features/calculator/calculator_screen.dart';

void main() {
  testWidgets('tuşlara basinca ekranda sayi gorunur', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CalculatorScreen(onSecretUnlock: () {}),
      ),
    );

    expect(find.text('0'), findsWidgets);

    await tester.tap(find.text('7'));
    await tester.pump();
    expect(find.text('7'), findsWidgets);

    await tester.tap(find.text('+'));
    await tester.pump();
    expect(find.text('7 +'), findsOneWidget);

    await tester.tap(find.text('3'));
    await tester.pump();
    expect(find.text('3'), findsWidgets);
    expect(find.text('7 + 3'), findsOneWidget);

    await tester.tap(find.text('='));
    await tester.pump();
    expect(find.text('10'), findsOneWidget);
  });
}
