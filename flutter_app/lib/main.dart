import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'features/auth/services/firebase_auth_service.dart';
import 'features/projects/services/firebase_project_workspace.dart';

const _demoProjectId = String.fromEnvironment(
  'KATYUFLOW_EMULATOR_PROJECT',
  defaultValue: 'demo-katyuflow',
);
const _defaultAppName = '[DEFAULT]';
const _mode = String.fromEnvironment(
  'KATYUFLOW_MODE',
  defaultValue: 'emulator',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_mode == 'demo' && !kReleaseMode) {
    runApp(const KatyuFlowApp());
    return;
  }
  try {
    if (_mode != 'emulator' || kReleaseMode) {
      throw StateError('Mode KatyuFlow tidak didukung.');
    }

    if (!_demoProjectId.startsWith('demo-')) {
      throw StateError('Mode emulator memerlukan ID proyek demo-.');
    }
    final app = await Firebase.initializeApp(demoProjectId: _demoProjectId);
    // Firestore creates its platform delegate from the default Firebase app.
    // Use the named demo app for every emulator operation, even on a configured build.
    if (Firebase.apps.every((app) => app.name != _defaultAppName)) {
      await Firebase.initializeApp(
        name: _defaultAppName,
        demoProjectId: _demoProjectId,
      );
    }

    final auth = FirebaseAuth.instanceFor(app: app);
    final db = FirebaseFirestore.instanceFor(app: app);
    db.settings = const Settings(persistenceEnabled: false);
    const configuredHost = String.fromEnvironment('KATYUFLOW_EMULATOR_HOST');
    final host = configuredHost.isNotEmpty
        ? configuredHost
        : !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : '127.0.0.1';
    const authPort = int.fromEnvironment(
      'KATYUFLOW_AUTH_PORT',
      defaultValue: 29099,
    );
    const firestorePort = int.fromEnvironment(
      'KATYUFLOW_FIRESTORE_PORT',
      defaultValue: 28080,
    );
    await auth.useAuthEmulator(host, authPort, automaticHostMapping: false);
    db.useFirestoreEmulator(host, firestorePort, automaticHostMapping: false);

    runApp(
      KatyuFlowApp.firebase(
        auth: FirebaseAuthService(auth, db),
        modeLabel: 'Firebase Emulator',
        openWorkspace: (account) => FirebaseProjectWorkspace(db, account),
      ),
    );
  } catch (error) {
    if (kDebugMode) {
      debugPrint('KatyuFlow gagal menginisialisasi Firebase: $error');
    }
    runApp(
      MaterialApp(
        title: 'KatyuFlow',
        home: Scaffold(
          appBar: AppBar(title: const Text('KatyuFlow')),
          body: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Firebase gagal dimulai. Periksa konfigurasi dan buka ulang KatyuFlow.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
