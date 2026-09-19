import 'package:url_launcher/url_launcher.dart';

class RegistrationTerms {
  static const privacyPolicyUrl =
      'https://sites.google.com/view/hesap-makinesi-privacy-policy/home';

  static final Uri privacyPolicyUri = Uri.parse(privacyPolicyUrl);

  static Future<bool> openPrivacyPolicy() {
    return launchUrl(privacyPolicyUri, mode: LaunchMode.externalApplication);
  }

  static const checkboxLabel = 'Okudum, anladım.';

  static const summary =
      'Kayıt olarak e-posta adresinin, görünen adının, mesajlarının, '
      'çevrimiçi durumunun ve bildirim kayıtlarının HesapMakinesi '
      'tarafından işlenmesini kabul edersin. Bu kutu işaretlenmeden '
      'kayıt olunamaz.';

  static const fullText =
      'Aydınlatma metni\n\n'
      'HesapMakinesi, gizli mesajlaşma özelliği için şu verileri işler:\n'
      '- E-posta ve görünen ad (hesap oluşturma)\n'
      '- Gönderdiğin mesajlar ve sohbet geçmişi\n'
      '- Çevrimiçi / son görülme bilgisi (ayarlardan kapatılabilir)\n'
      '- Yazıyor ve görüldü bilgisi (ayarlardan kapatılabilir)\n'
      '- Uygunsuz içerik bildirimleri (moderasyon)\n\n'
      'Veriler Firebase (Google) altyapısında saklanır. Hesabını '
      'Ayarlar > Hesabı sil ile kalıcı silebilirsin.\n\n'
      'Gizlilik politikası: $privacyPolicyUrl\n\n'
      'Kayıt olmak için bu metni okuduğunu onaylaman ve e-postana '
      'gelen 6 haneli kodu girmen gerekir.';
}
