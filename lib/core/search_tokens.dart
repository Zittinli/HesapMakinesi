class SearchTokens {
  SearchTokens._();

  static final _splitter = RegExp(r'[^\p{L}\p{N}@._]+', unicode: true);

  static List<String> wordsOf(String text) {
    return text
        .toLowerCase()
        .split(_splitter)
        .map((item) => item.trim())
        .where((item) => item.length >= 2)
        .toList();
  }

  static List<String> fromText(String text) {
    final unique = <String>{};
    for (final word in wordsOf(text)) {
      unique.add(word);
      if (unique.length >= 40) break;
    }
    return unique.toList();
  }

  static bool matches(String haystack, String query) {
    final needles = wordsOf(query);
    if (needles.isEmpty) return false;
    final lower = haystack.toLowerCase();
    return needles.every(lower.contains);
  }
}
