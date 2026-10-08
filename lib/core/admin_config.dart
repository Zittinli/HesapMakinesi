class AdminConfig {
  static const founderEmail = 'zttnlnkc@gmail.com';
  static const founderUid = 'RUwHPHB6HRdy3l6jBsIexmDHYAB3';

  static const emails = <String>[founderEmail];

  static bool isAdminEmail(String? email) {
    if (email == null || email.isEmpty) return false;
    return emails.contains(email.trim().toLowerCase());
  }

  static bool isFounder({String? email, String? userId}) {
    if (isAdminEmail(email)) return true;
    return userId != null && userId == founderUid;
  }
}
