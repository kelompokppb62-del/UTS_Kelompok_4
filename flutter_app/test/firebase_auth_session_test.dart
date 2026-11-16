import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katyuflow/app/app.dart';
import 'package:katyuflow/features/auth/models/account.dart';
import 'package:katyuflow/features/auth/services/auth_service.dart';
import 'package:katyuflow/features/auth/services/firebase_auth_service.dart';
import 'package:katyuflow/features/projects/services/project_board.dart';
import 'package:katyuflow/features/projects/services/project_repository.dart';

void main() {
  late _FakeAuth auth;
  late _ProfileReader store;
  late FirebaseAuthService service;

  setUp(() {
    auth = _FakeAuth();
    store = _ProfileReader();
    service = FirebaseAuthService.withProfileReader(auth, store.read);
  });

  Future<Account?> login({UserRole role = UserRole.owner}) => service.signIn(
    role: role,
    email: 'owner@example.test',
    password: 'dummy-password',
  );

  test(
    'login verifies fresh claims and server profile before authorizing',
    () async {
      final user = await login();
      expect(user?.role, UserRole.owner);
      expect(auth.signIns, 1);
      expect(auth.testUser.refreshes, 1);
      expect(store.docPath, 'users/test-fixture');
      expect(auth.signOuts, 0);
    },
  );

  test(
    'transient SDK failures preserve the authenticated user and support retry',
    () async {
      for (final code in ['unavailable', 'internal', 'deadline-exceeded']) {
        store.error = FirebaseException(plugin: 'cloud_firestore', code: code);
        await expectLater(
          login(),
          throwsA(
            isA<AuthAccessException>().having(
              (e) => e.retrySession,
              'can retry',
              true,
            ),
          ),
        );
        expect(auth.currentUser, same(auth.testUser));
        expect(auth.signOuts, 0);
        store.error = null;
        expect(
          (await service.restoreSession(expectedRole: UserRole.owner))?.role,
          UserRole.owner,
        );
      }
      expect(auth.signIns, 3);
    },
  );

  test('temporary claim failures also preserve the session', () async {
    auth.testUser.error = FirebaseAuthException(code: 'network-request-failed');
    await expectLater(
      login(),
      throwsA(
        isA<AuthAccessException>().having(
          (e) => e.retrySession,
          'can retry',
          true,
        ),
      ),
    );
    expect(auth.currentUser, same(auth.testUser));
    expect(auth.signOuts, 0);
    expect(store.docPath, isNull);
  });

  test('restores saved session and manual logout clears it', () async {
    auth.currentUser = auth.testUser;
    expect((await service.restoreSession())?.role, UserRole.owner);
    expect(auth.signIns, 0);
    await service.signOut();
    expect(auth.signOuts, 1);
    expect(await service.restoreSession(), isNull);
  });

  test('wrong login role signs out without reading profile', () async {
    await expectLater(
      login(role: UserRole.worker),
      throwsA(
        isA<AuthAccessException>()
            .having((e) => e.retrySession, 'can retry', false)
            .having((e) => e.message, 'message', contains('tidak sesuai')),
      ),
    );
    expect(auth.signOuts, 1);
    expect(store.docPath, isNull);
  });

  test(
    'inactive or missing profile terminates the session with distinct errors',
    () async {
      store.data = {'status': 'suspended', 'role': 'owner'};
      await expectLater(
        login(),
        throwsA(
          isA<AuthAccessException>().having(
            (e) => e.message,
            'message',
            contains('belum aktif'),
          ),
        ),
      );
      expect(auth.signOuts, 1);
      store.data = null;
      await expectLater(
        login(),
        throwsA(
          isA<AuthAccessException>().having(
            (e) => e.message,
            'message',
            contains('Profil akun belum tersedia'),
          ),
        ),
      );
      expect(auth.signOuts, 2);
    },
  );

  test('confirmed profile denial or invalid token ends the session', () async {
    store.error = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
    await expectLater(
      login(),
      throwsA(
        isA<AuthAccessException>().having(
          (e) => e.retrySession,
          'can retry',
          false,
        ),
      ),
    );
    expect(auth.signOuts, 1);
    auth.testUser.error = FirebaseAuthException(code: 'user-token-expired');
    await expectLater(
      login(),
      throwsA(
        isA<AuthAccessException>().having(
          (e) => e.message,
          'message',
          contains('Sesi Firebase tidak valid'),
        ),
      ),
    );
    expect(auth.signOuts, 2);
  });

  test('wrong password has a specific error and never reads profile', () async {
    auth.error = FirebaseAuthException(code: 'invalid-credential');
    await expectLater(
      login(),
      throwsA(
        isA<AuthAccessException>().having(
          (e) => e.message,
          'message',
          contains('Email atau password tidak cocok'),
        ),
      ),
    );
    expect(store.docPath, isNull);
    expect(auth.signOuts, 0);
  });

  testWidgets(
    'retry stays locked, reuses Firebase Auth, and only opens dashboard after verification',
    (tester) async {
      await tester.pumpWidget(
        KatyuFlowApp.firebase(
          auth: service,
          openWorkspace: (_) => ProjectBoard(InMemoryProjectRepository([])),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Login as Owner'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'owner@example.test',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'dummy-password',
      );
      final pending = Completer<Map<String, dynamic>?>();
      store.pending = pending.future;
      final submit = find.text('Masuk ke Dashboard');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      expect(find.text('Dashboard Owner'), findsNothing);
      final unavailable = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );
      pending.completeError(unavailable);
      await tester.pumpAndSettle();
      expect(find.textContaining('Koneksi Firestore terputus'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Dashboard Owner'), findsNothing);
      expect(auth.signOuts, 0);
      store.pending = null;
      await tester.tap(find.text('Coba lagi verifikasi'));
      await tester.pumpAndSettle();
      expect(auth.signIns, 1);
      expect(find.text('Dashboard Owner'), findsOneWidget);
      await tester.tap(find.byTooltip('Keluar / Ganti akun'));
      await tester.pumpAndSettle();
      expect(auth.signOuts, 1);
      expect(find.text('Login as Owner'), findsOneWidget);
    },
  );

  testWidgets(
    'startup does not open dashboard while restored profile is unavailable',
    (tester) async {
      auth.currentUser = auth.testUser;
      store.error = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );
      await tester.pumpWidget(
        KatyuFlowApp.firebase(
          auth: service,
          openWorkspace: (_) => ProjectBoard(InMemoryProjectRepository([])),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Dashboard Owner'), findsNothing);
      expect(find.textContaining('Koneksi Firestore terputus'), findsOneWidget);
      expect(auth.signOuts, 0);
      store.error = null;
      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(find.text('Dashboard Owner'), findsOneWidget);
      expect(auth.signIns, 0);
    },
  );
}

class _FakeAuth extends Fake implements FirebaseAuth {
  final testUser = _FakeUser();
  @override
  User? currentUser;
  Object? error;
  int signIns = 0;
  int signOuts = 0;

  @override
  Stream<User?> authStateChanges() => Stream.value(currentUser);

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    signIns++;
    if (error case final failure?) throw failure;
    currentUser = testUser;
    return _FakeCredential(testUser);
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    currentUser = null;
  }
}

class _FakeCredential extends Fake implements UserCredential {
  _FakeCredential(this.user);

  @override
  final User user;
}

class _FakeUser extends Fake implements User {
  Object? error;
  int refreshes = 0;

  @override
  String get uid => 'test-fixture';

  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async {
    if (forceRefresh) refreshes++;
    if (error case final failure?) throw failure;
    return _FakeToken();
  }
}

class _FakeToken extends Fake implements IdTokenResult {
  @override
  Map<String, dynamic> get claims => {'role': 'owner'};
}

class _ProfileReader {
  String? docPath;
  Object? error;
  Future<Map<String, dynamic>?>? pending;
  Map<String, dynamic>? data = {'role': 'owner', 'status': 'active'};

  Future<Map<String, dynamic>?> read(String path) async {
    docPath = path;
    if (pending case final result?) return result;
    if (error case final failure?) throw failure;
    return data;
  }
}
