import 'package:flutter/material.dart';

import '../core/widgets/notice.dart';
import '../features/auth/models/account.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/welcome_screen.dart';
import '../features/auth/services/auth_service.dart';
import '../features/owner/screens/owner_dashboard.dart';
import '../features/projects/services/demo_projects.dart';
import '../features/projects/services/project_board.dart';
import '../features/projects/services/project_repository.dart';
import '../features/projects/services/project_workspace.dart';
import '../features/worker/screens/worker_dashboard.dart';
import 'theme.dart';

class KatyuFlowApp extends StatefulWidget {
  const KatyuFlowApp({super.key})
    : auth = const DemoAuthService(),
      openWorkspace = null,
      modeLabel = 'Versi demo lokal';

  const KatyuFlowApp.firebase({
    super.key,
    required SessionAuthService this.auth,
    required ProjectWorkspace Function(Account) this.openWorkspace,
    this.modeLabel,
  });

  final AuthService auth;
  final ProjectWorkspace Function(Account)? openWorkspace;
  final String? modeLabel;

  @override
  State<KatyuFlowApp> createState() => _KatyuFlowAppState();
}

class _KatyuFlowAppState extends State<KatyuFlowApp> {
  ProjectBoard? _demoBoard;
  ProjectWorkspace? _workspace;
  Account? _account;
  bool _working = false;
  String? _restoreError;
  bool _canDiscardSession = false;

  @override
  void initState() {
    super.initState();
    if (widget.auth is SessionAuthService) _restoreSession();
  }

  void _open(Account account) {
    final workspace =
        widget.openWorkspace?.call(account) ??
        (_demoBoard ??= ProjectBoard(
          InMemoryProjectRepository(demoProjects(DateTime.now()).reversed),
        ));
    setState(() {
      _account = account;
      _workspace = workspace;
    });
  }

  Future<void> _restoreSession() async {
    final auth = widget.auth as SessionAuthService;
    setState(() {
      _working = true;
      _restoreError = null;
      _canDiscardSession = false;
    });
    try {
      final account = await auth.restoreSession();
      if (mounted && account != null) _open(account);
    } on AuthAccessException catch (error) {
      if (mounted) {
        setState(() {
          _restoreError = error.message;
          _canDiscardSession = error.retrySession;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _restoreError = 'Sesi Firebase gagal dimuat. Periksa koneksi.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _logout(BuildContext context) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final auth = widget.auth;
      if (auth is SessionAuthService) await auth.signOut();
      if (!mounted || !context.mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      _disposeWorkspace();
      setState(() {
        _account = null;
        _workspace = null;
        _restoreError = null;
        _canDiscardSession = false;
      });
    } catch (_) {
      if (context.mounted) showNotice(context, 'Keluar gagal. Coba lagi.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _disposeWorkspace() {
    if (_workspace != _demoBoard) _workspace?.dispose();
  }

  @override
  void dispose() {
    _disposeWorkspace();
    _demoBoard?.dispose();
    super.dispose();
  }

  void _chooseRole(BuildContext context, UserRole role) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => LoginScreen(
          role: role,
          auth: widget.auth,
          onLogin: (account) {
            if (!mounted || !context.mounted) return;
            _open(account);
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Widget _home(BuildContext context) {
    final account = _account;
    if (account != null) {
      final board = _workspace!;
      void logout() {
        _logout(context);
      }

      return account.role == UserRole.owner
          ? Theme(
              data: katyuTheme(useTeal: false),
              child: OwnerDashboard(
                owner: account,
                board: board,
                onLogout: logout,
              ),
            )
          : WorkerDashboard(worker: account, board: board, onLogout: logout);
    }
    if (_working) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(semanticsLabel: 'Memuat sesi'),
        ),
      );
    }
    if (_restoreError case final message?) {
      return Scaffold(
        appBar: AppBar(title: const Text('KatyuFlow')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _restoreSession,
                  child: const Text('Coba lagi'),
                ),
                if (_canDiscardSession)
                  TextButton(
                    onPressed: () => _logout(context),
                    child: const Text('Ganti akun'),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return WelcomeScreen(
      modeLabel: widget.modeLabel,
      onChoose: (role) => _chooseRole(context, role),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'KatyuFlow',
    debugShowCheckedModeBanner: false,
    theme: katyuTheme(useTeal: true),
    home: Builder(builder: _home),
  );
}
