import 'package:cloud_functions/cloud_functions.dart';

class EmailCheckException implements Exception {
  const EmailCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Kayit oncesi e-posta adresinin gercekten teslim edilebilir olup olmadigini
/// sunucu tarafinda kontrol eder: bicim, tek kullanimlik alan adi listesi ve
/// alan adinin MX kaydi.
class EmailCheckService {
  EmailCheckService({FirebaseFunctions? functions})
      : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  final FirebaseFunctions _functions;

  Future<void> ensureDeliverable(String email) async {
    final HttpsCallableResult<dynamic> response;
    try {
      response = await _functions.httpsCallable('validateEmailAddress').call({
        'email': email.trim().toLowerCase(),
      });
    } on FirebaseFunctionsException catch (_) {
      throw const EmailCheckException(
        'E-posta dogrulanamadi. Baglantini kontrol edip tekrar dene.',
      );
    }

    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['valid'] == true) return;

    throw EmailCheckException(_messageFor(data['reason'] as String? ?? ''));
  }

  String _messageFor(String reason) {
    switch (reason) {
      case 'format':
        return 'E-posta adresi gecerli bir bicimde degil.';
      case 'disposable':
        return 'Tek kullanimlik e-posta adresleriyle kayit olunamaz.';
      case 'no_mx':
        return 'Bu e-posta alan adi mesaj kabul etmiyor. Gercek bir adres gir.';
      default:
        return 'E-posta adresi dogrulanamadi.';
    }
  }
}
