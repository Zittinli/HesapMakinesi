class SecretConfig {
  SecretConfig._();

  /// Gizli arayuzu acan islem: 3112 × 1231 =
  static const String secretLeft = '3112';
  static const String secretOperator = '×';
  static const String secretRight = '1231';

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
