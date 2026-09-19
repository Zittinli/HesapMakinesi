import 'package:url_launcher/url_launcher.dart';

class ChatLink {
  const ChatLink({required this.raw, required this.start, required this.end});

  final String raw;
  final int start;
  final int end;

  String get label {
    final host = uri.host.replaceFirst(RegExp(r'^www\.'), '');
    if (host.contains('instagram.com')) return 'Instagram';
    if (host.contains('tiktok.com')) return 'TikTok';
    return host.isEmpty ? 'Bağlantı' : host;
  }

  Uri get uri {
    final value = raw.startsWith('http') ? raw : 'https://$raw';
    return Uri.parse(value);
  }
}

class ChatLinks {
  ChatLinks._();

  static final pattern = RegExp(
    r'(https?:\/\/[^\s]+|(?:www\.)?(?:instagram\.com|tiktok\.com|vm\.tiktok\.com)\/[^\s]+)',
    caseSensitive: false,
  );

  static List<ChatLink> extract(String text) {
    return [
      for (final match in pattern.allMatches(text))
        ChatLink(raw: match.group(0)!, start: match.start, end: match.end),
    ];
  }

  static Future<void> open(String raw) async {
    final link = ChatLink(raw: raw, start: 0, end: raw.length);
    await launchUrl(link.uri, mode: LaunchMode.externalApplication);
  }
}
