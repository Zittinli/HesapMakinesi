import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesap_makinesi/features/calculator/calculator_screen.dart';

void _setPortrait(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _setLandscape(WidgetTester tester) {
  tester.view.physicalSize = const Size(844, 390);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('tuşlara basinca ekranda sayi gorunur', (tester) async {
    _setPortrait(tester);
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

  testWidgets('geri silme tusu son rakami siler', (tester) async {
    _setPortrait(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: CalculatorScreen(onSecretUnlock: () {}),
      ),
    );

    await tester.tap(find.text('1'));
    await tester.pump();
    await tester.tap(find.text('2'));
    await tester.pump();
    expect(find.text('12'), findsWidgets);

    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    expect(find.text('1'), findsWidgets);
    expect(find.text('12'), findsNothing);
    expect(find.text('±'), findsNothing);
    expect(find.byIcon(Icons.backspace_outlined), findsOneWidget);
  });

  testWidgets('yatayda bilimsel tuslar ve eksi isareti cikar', (tester) async {
    _setLandscape(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: CalculatorScreen(onSecretUnlock: () {}),
      ),
    );

    expect(find.text('sin'), findsOneWidget);
    expect(find.text('cos'), findsOneWidget);
    expect(find.text('√'), findsOneWidget);
    expect(find.text('xʸ'), findsOneWidget);
    expect(find.text('±'), findsOneWidget);

    await tester.tap(find.text('9'));
    await tester.pump();
    await tester.tap(find.text('0'));
    await tester.pump();
    await tester.tap(find.text('sin'));
    await tester.pump();
    expect(find.text('1'), findsWidgets);
  });
}
