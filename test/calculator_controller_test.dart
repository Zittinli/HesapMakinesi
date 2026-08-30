import 'package:flutter_test/flutter_test.dart';
import 'package:hesap_makinesi/core/secret_config.dart';
import 'package:hesap_makinesi/features/calculator/calculator_controller.dart';

void main() {
  test('3112 × 1231 islemi gizli arayuzu acar', () {
    expect(
      SecretConfig.shouldUnlockOperation(
        left: '3112',
        operator: '×',
        right: '1231',
      ),
      isTrue,
    );
    expect(
      SecretConfig.shouldUnlockOperation(
        left: '3112',
        operator: '×',
        right: '1230',
      ),
      isFalse,
    );
  });

  test('degistirilen giris kodunu tanir', () {
    final controller = CalculatorController();

    for (final digit in '12'.split('')) {
      controller.onButtonPressed(digit);
    }
    controller.onButtonPressed('+');
    for (final digit in '34'.split('')) {
      controller.onButtonPressed(digit);
    }

    expect(
      controller.onEqualsPressed(
        expectedLeft: '12',
        expectedOperator: '+',
        expectedRight: '34',
      ),
      isTrue,
    );
    expect(controller.display, '0');
  });

  test('hesap makinesi gizli islemi algilar', () {
    final controller = CalculatorController();

    for (final digit in '3112'.split('')) {
      controller.onButtonPressed(digit);
    }
    controller.onButtonPressed('×');
    for (final digit in '1231'.split('')) {
      controller.onButtonPressed(digit);
    }

    expect(controller.onEqualsPressed(), isTrue);
    expect(controller.display, '0');
  });

  test('hesap makinesi temel islemleri yapar', () {
    final controller = CalculatorController();

    controller.onButtonPressed('7');
    controller.onButtonPressed('+');
    expect(controller.expressionDisplay, '7 +');
    controller.onButtonPressed('3');
    expect(controller.expressionDisplay, '7 + 3');
    expect(controller.onEqualsPressed(), isFalse);
    expect(controller.display, '10');

    controller.onButtonPressed('C');
    expect(controller.display, '0');
  });

  test('sifira bolme hataya dusurur', () {
    final controller = CalculatorController();

    controller.onButtonPressed('8');
    controller.onButtonPressed('÷');
    controller.onButtonPressed('0');
    controller.onEqualsPressed();

    expect(controller.display, 'Hata');
  });
}
