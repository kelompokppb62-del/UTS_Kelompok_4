import '../models/account.dart';

abstract interface class AuthService {
  Future<Account?> signIn({
    required UserRole role,
    required String email,
    required String password,
  });
}

class DemoAuthService implements AuthService {
  const DemoAuthService();

  static String emailFor(UserRole role) => '${role.name}@katyuflow.app';

  @override
  Future<Account?> signIn({
    required UserRole role,
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (email.trim().toLowerCase() != emailFor(role) || password != '123456') {
      return null;
    }
    return Account(id: emailFor(role), role: role);
  }
}

abstract interface class SessionAuthService implements AuthService {
  Future<Account?> restoreSession({UserRole? expectedRole});
  Future<void> signOut();
}

class AuthAccessException implements Exception {
  const AuthAccessException(this.message, {this.retrySession = false});

  final String message;
  final bool retrySession;
}
