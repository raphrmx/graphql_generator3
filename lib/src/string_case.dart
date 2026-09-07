/// Word-splitting and case conversions used to name the generated symbols.
///
/// Replaces `package:recase`, of which the generator only ever used
/// `camelCase` and `snakeCase`. The splitting rules are kept identical so
/// previously generated names stay unchanged:
/// - `_`, `-`, `.`, `/`, `\` and spaces separate words and are dropped;
/// - an upper-case letter starts a new word, unless the whole input is
///   upper-case (`ABC` is one word, not three);
/// - inside a word only the first letter is kept upper-case.
List<String> _splitWords(String text) {
  final words = <String>[];
  final buffer = StringBuffer();
  final isAllCaps = text.toUpperCase() == text;

  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (_separators.contains(char)) continue;

    buffer.write(char);

    final next = i + 1 == text.length ? null : text[i + 1];
    final isEndOfWord =
        next == null ||
        (!isAllCaps && _upperAlpha.hasMatch(next)) ||
        _separators.contains(next);

    if (isEndOfWord) {
      words.add(buffer.toString());
      buffer.clear();
    }
  }

  return words;
}

const _separators = {' ', '.', '/', '_', r'\', '-'};

final _upperAlpha = RegExp(r'[A-Z]');

String _capitalize(String word) =>
    '${word.substring(0, 1).toUpperCase()}${word.substring(1).toLowerCase()}';

/// Converts [text] to `camelCase`, eg `BmcBddEmployee` -> `bmcBddEmployee`.
String camelCase(String text) {
  final words = _splitWords(text).map(_capitalize).toList();
  if (words.isNotEmpty) {
    words[0] = words[0].toLowerCase();
  }
  return words.join();
}

/// Converts [text] to `snake_case`, eg `BmcDeviceData` -> `bmc_device_data`.
String snakeCase(String text) =>
    _splitWords(text).map((w) => w.toLowerCase()).join('_');
