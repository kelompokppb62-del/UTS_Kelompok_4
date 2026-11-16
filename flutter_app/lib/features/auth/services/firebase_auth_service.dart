import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/account.dart';
import 'auth_service.dart';

enum _AuthStep { login, restore, claims, profile }

class FirebaseAuthService implements SessionAuthService {
  FirebaseAuthService(FirebaseAuth auth, FirebaseFirestore db)
    : this.withProfileReader(auth, (path) async {
        final snapshot = await db
            .doc(path)
            .get(const GetOptions(source: Source.server));
        return snapshot.data();
      });

  @visibleForTesting
  const FirebaseAuthService.withProfileReader(this._auth, this._readProfile);

  final FirebaseAuth _auth;
  final Future<Map<String, dynamic>?> Function(String path) _readProfile;
  static const _verificationTimeout = Duration(seconds: 20);
  static const _invalidSession =
      'Sesi Firebase tidak valid. Silakan masuk lagi.';

  @override
  Future<Account?> signIn({
    required UserRole role,
    required String email,
    required String password,
  }) async {
    final result = await _request(
      _AuthStep.login,
      () => _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      ),
    );
    final user = result.user;
    if (user == null) throw const AuthAccessException(_invalidSession);
    return _verify(user, expectedRole: role);
  }

  @override
  Future<Account?> restoreSession({UserRole? expectedRole}) async {
    final user = await _request(
      _AuthStep.restore,
      () => _auth.authStateChanges().first.timeout(_verificationTimeout),
    );
    if (user == null) {
      if (expectedRole != null) {
        throw const AuthAccessException(_invalidSession);
      }
      return null;
    }
    return _verify(user, expectedRole: expectedRole);
  }

  Future<Account> _verify(User user, {UserRole? expectedRole}) async {
    try {
      final token = await _request(
        _AuthStep.claims,
        () => user.getIdTokenResult(true).timeout(_verificationTimeout),
      );
      final role = switch (token.claims?['role']) {
        'owner' => UserRole.owner,
        'worker' => UserRole.worker,
        _ => throw const _SessionDenied(
          'missing-role',
          'Peran akun belum ditetapkan. Hubungi Owner.',
        ),
      };
      if (expectedRole != null && role != expectedRole) {
        throw const _SessionDenied(
          'wrong-role',
          'Peran akun tidak sesuai dengan halaman login ini.',
        );
      }

      final data = await _request(
        _AuthStep.profile,
        () => _readProfile('users/${user.uid}').timeout(_verificationTimeout),
      );
      if (data == null) {
        throw const _SessionDenied(
          'missing-profile',
          'Profil akun belum tersedia. Hubungi Owner.',
        );
      }
      if (data['status'] != 'active') {
        throw const _SessionDenied(
          'inactive-profile',
          'Akun belum aktif. Hubungi Owner.',
        );
      }
      if (data['role'] != role.name) {
        throw const _SessionDenied(
          'profile-role-mismatch',
          'Akses tidak diizinkan. Peran akun dan profil tidak cocok.',
        );
      }
      if (_auth.currentUser?.uid != user.uid) {
        throw const _SessionDenied('session-changed', _invalidSession);
      }
      _log('dashboard authorized');
      return Account(id: user.uid, role: role);
    } on _SessionDenied catch (denial) {
      _log('authorization denied ${denial.reason}');
      if (_auth.currentUser?.uid == user.uid) {
        try {
          await _signOut(denial.reason);
        } catch (_) {
          // A failed sign-out must still leave the dashboard locked.
        }
      }
      rethrow;
    }
  }

  Future<T> _request<T>(_AuthStep step, Future<T> Function() request) async {
    _log('${step.name} started');
    try {
      final result = await request();
      _log('${step.name} succeeded');
      return result;
    } on TimeoutException {
      throw _retry(
        step,
        'timeout',
        'Waktu verifikasi habis. Periksa koneksi dan coba lagi.',
      );
    } on FirebaseException catch (error) {
      throw _failure(step, error.code);
    } catch (_) {
      throw _retry(step, 'unexpected', 'Verifikasi Firebase gagal. Coba lagi.');
    }
  }

  AuthAccessException _failure(_AuthStep step, String code) {
    final timeout = code == 'deadline-exceeded' || code == 'timeout';
    if (timeout) {
      return _retry(
        step,
        'timeout',
        'Waktu permintaan habis. Periksa koneksi dan coba lagi.',
      );
    }

    if (step == _AuthStep.login) {
      final (reason, message) = switch (code) {
        'invalid-credential' ||
        'wrong-password' ||
        'user-not-found' ||
        'invalid-email' => (
          'invalid-credentials',
          'Email atau password tidak cocok.',
        ),
        'too-many-requests' => (
          'rate-limited',
          'Terlalu banyak percobaan. Coba lagi nanti.',
        ),
        'network-request-failed' ||
        'unavailable' => ('network', 'Koneksi Firebase Auth gagal. Coba lagi.'),
        'user-disabled' => (
          'disabled-user',
          'Akun belum aktif. Hubungi Owner.',
        ),
        'operation-not-allowed' ||
        'app-not-authorized' ||
        'permission-denied' => (
          'access-denied',
          'Akses login tidak diizinkan. Hubungi Owner.',
        ),
        _ => ('unexpected', 'Login Firebase gagal. Coba lagi.'),
      };
      return _retry(step, reason, message);
    }

    if (const {
      'user-disabled',
      'user-not-found',
      'user-token-expired',
      'invalid-user-token',
      'invalid-credential',
      'unauthenticated',
    }.contains(code)) {
      _log('${step.name} failed invalid-session');
      return _SessionDenied(
        'invalid-session',
        code == 'user-disabled'
            ? 'Akun telah dinonaktifkan. Hubungi Owner.'
            : _invalidSession,
      );
    }
    if (code == 'permission-denied') {
      _log('${step.name} failed access-denied');
      return _SessionDenied(
        'access-denied',
        step == _AuthStep.profile
            ? 'Akses profil ditolak. Hubungi Owner untuk memeriksa akun.'
            : 'Akses sesi Firebase ditolak. Hubungi Owner.',
      );
    }
    if (code == 'unavailable' || code == 'network-request-failed') {
      return _retry(
        step,
        'network',
        step == _AuthStep.profile
            ? 'Koneksi Firestore terputus. Coba lagi untuk memverifikasi profil.'
            : 'Koneksi Firebase Auth gagal. Coba lagi untuk memverifikasi sesi.',
      );
    }
    return _retry(
      step,
      'unexpected',
      step == _AuthStep.profile
          ? 'Profil Firestore gagal diverifikasi. Coba lagi.'
          : 'Sesi Firebase gagal diverifikasi. Coba lagi.',
    );
  }

  AuthAccessException _retry(_AuthStep step, String reason, String message) {
    _log('${step.name} failed $reason');
    return AuthAccessException(message, retrySession: step != _AuthStep.login);
  }

  @override
  Future<void> signOut() => _signOut('manual');

  Future<void> _signOut(String reason) async {
    _log('signOut started $reason');
    try {
      await _auth.signOut();
      _log('signOut succeeded $reason');
    } catch (_) {
      _log('signOut failed $reason');
      rethrow;
    }
  }

  // Only static stage/reason labels. No Firebase exception payloads or user data.
  static void _log(String event) => debugPrint('KatyuFlow auth: $event');
}

class _SessionDenied extends AuthAccessException {
  const _SessionDenied(this.reason, super.message);
  final String reason;
}
