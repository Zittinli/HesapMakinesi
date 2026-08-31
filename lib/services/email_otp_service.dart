import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'auth_log_service.dart';

class EmailOtpException implements Exception {
  const EmailOtpException(this.message);
  final String message;

  @override
  String toString() => message;
}

class EmailOtpService {
  EmailOtpService({
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    AuthLogService? authLog,
  })  : _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'europe-west1'),
        _auth = auth ?? FirebaseAuth.instance,
        _authLog = authLog ?? AuthLogService();

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final AuthLogService _authLog;

  Future<void> sendCode() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const EmailOtpException('Oturum bulunamadi.');
    }
    try {
      await _functions.httpsCallable('sendEmailOtp').call();
      await _authLog.log(
        type: 'otp_sent',
        email: user.email ?? '',
      );
    } on FirebaseFunctionsException catch (error) {
      await _authLog.log(
        type: 'otp_failed',
        email: user.email ?? '',
        success: false,
        errorCode: error.code,
      );
      throw EmailOtpException(_mapError(error));
    }
  }

  Future<void> verifyCode(String code) async {
    final email = _auth.currentUser?.email ?? '';
    try {
      await _functions.httpsCallable('verifyEmailOtp').call({
        'code': code.trim(),
      });
      await _auth.currentUser?.reload();
      await _authLog.log(type: 'otp_verified', email: email);
    } on FirebaseFunctionsException catch (error) {
      await _authLog.log(
        type: 'otp_failed',
        email: email,
        success: false,
        errorCode: error.code,
      );
      throw EmailOtpException(_mapError(error));
    }
  }

  String _mapError(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'resource-exhausted':
        return 'Biraz bekleyip tekrar dene.';
      case 'not-found':
        return 'Once e-posta kodu iste.';
      case 'deadline-exceeded':
        return 'Kodun suresi doldu. Yeni kod iste.';
      case 'invalid-argument':
        return 'Kod 6 haneli olmali.';
      case 'permission-denied':
        return error.message?.contains('deneme') == true
            ? 'Cok fazla yanlis deneme.'
            : 'Kod yanlis.';
      default:
        return 'Kod gonderilemedi veya dogrulanamadi.';
    }
  }
}
