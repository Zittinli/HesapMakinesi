import 'package:url_launcher/url_launcher.dart';

class RegistrationTerms {
  static const privacyPolicyUrl =
      'https://sites.google.com/view/hesap-makinesi-privacy-policy/home';

  static final Uri privacyPolicyUri = Uri.parse(privacyPolicyUrl);

  static Future<bool> openPrivacyPolicy() {
    return launchUrl(privacyPolicyUri, mode: LaunchMode.externalApplication);
  }

  static const checkboxLabel = 'Okudum, anladim.';

  static const summary =
      'Kayit olarak e-posta adresinin, gorunen adinin, mesajlarinin, '
      'cevrimici durumunun ve bildirim kayitlarinin HesapMakinesi '
      'tarafindan islenmesini kabul edersin. Bu kutu isaretlenmeden '
      'kayit olunamaz.';

  static const fullText =
      'Aydinlatma metni\n\n'
      'HesapMakinesi, gizli mesajlasma ozelligi icin su verileri isler:\n'
      '- E-posta ve gorunen ad (hesap olusturma)\n'
      '- Gonderdigin mesajlar ve sohbet gecmisi\n'
      '- Cevrimici / son gorulme bilgisi (ayarlardan kapatilabilir)\n'
      '- Yaziyor ve goruldu bilgisi (ayarlardan kapatilabilir)\n'
      '- Uygunsuz icerik bildirimleri (moderasyon)\n\n'
      'Veriler Firebase (Google) altyapisinda saklanir. Hesabini '
      'Ayarlar > Hesabi sil ile kalici silebilirsin.\n\n'
      'Gizlilik politikasi: $privacyPolicyUrl\n\n'
      'Kayit olmak icin bu metni okudugunu onaylaman ve e-postana '
      'gelen 6 haneli kodu girmen gerekir.';
}
