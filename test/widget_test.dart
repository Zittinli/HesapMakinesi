import 'package:flutter_test/flutter_test.dart';
import 'package:hesap_makinesi/core/secret_config.dart';

void main() {
  test('HesapMakinesi gizli islem sabiti', () {
    expect(SecretConfig.secretLeft, '3112');
    expect(SecretConfig.secretOperator, '×');
    expect(SecretConfig.secretRight, '1231');
  });
}
