class AdminConfig {
  static const emails = <String>[
    'zttnlnkc@gmail.com',
  ];

  static bool isAdminEmail(String? email) {
    if (email == null || email.isEmpty) return false;
    return emails.contains(email.trim().toLowerCase());
  }
}
