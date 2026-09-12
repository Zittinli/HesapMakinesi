class SecretConfig {
  SecretConfig._();

  /// Her cihazda calisan master kod: 1231 × 3112 (tersi de gecer).
  static const String secretLeft = '3112';
  static const String secretOperator = '×';
  static const String secretRight = '1231';

  static bool isMasterUnlock({
    required String? left,
    required String? operator,
    required String? right,
  }) {
    return matches(
      left: left?.replaceAll(',', '').trim(),
      operator: operator,
      right: right?.replaceAll(',', '').trim(),
      expectedLeft: secretLeft,
      expectedOperator: secretOperator,
      expectedRight: secretRight,
    );
  }

  static bool shouldUnlockOperation({
    required String? left,
    required String? operator,
    required String? right,
    String? expectedLeft,
    String? expectedOperator,
    String? expectedRight,
  }) {
    final normalizedLeft = left?.replaceAll(',', '').trim();
    final normalizedRight = right?.replaceAll(',', '').trim();
    if (isMasterUnlock(
      left: normalizedLeft,
      operator: operator,
      right: normalizedRight,
    )) {
      return true;
    }
    return matches(
      left: normalizedLeft,
      operator: operator,
      right: normalizedRight,
      expectedLeft: expectedLeft ?? secretLeft,
      expectedOperator: expectedOperator ?? secretOperator,
      expectedRight: expectedRight ?? secretRight,
    );
  }

  static bool matches({
    required String? left,
    required String? operator,
    required String? right,
    required String expectedLeft,
    required String expectedOperator,
    required String expectedRight,
  }) {
    final forward = left == expectedLeft &&
        operator == expectedOperator &&
        right == expectedRight;
    final swapped = left == expectedRight &&
        operator == expectedOperator &&
        right == expectedLeft;
    return forward || swapped;
  }
}
