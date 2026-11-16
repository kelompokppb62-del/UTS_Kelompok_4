import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/page_list.dart';
import '../models/account.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.role,
    required this.auth,
    required this.onLogin,
  });

  final UserRole role;
  final AuthService auth;
  final ValueChanged<Account> onLogin;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _hidden = true;
  bool _loading = false;
  bool _retrySession = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.auth is DemoAuthService) {
      _email.text = DemoAuthService.emailFor(widget.role);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || (!_retrySession && !_form.currentState!.validate())) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    Account? user;
    var retrySession = _retrySession;
    var error = widget.auth is DemoAuthService
        ? 'Email atau password demo tidak cocok.'
        : 'Email atau password tidak cocok.';
    try {
      user = _retrySession
          ? await (widget.auth as SessionAuthService).restoreSession(
              expectedRole: widget.role,
            )
          : await widget.auth.signIn(
              role: widget.role,
              email: _email.text,
              password: _password.text,
            );
      retrySession = false;
    } on AuthAccessException catch (failure) {
      error = failure.message;
      retrySession = failure.retrySession && widget.auth is SessionAuthService;
    } catch (_) {
      error = 'Login gagal. Coba lagi.';
    }
    if (!mounted) return;
    if (user != null && user.role == widget.role) {
      _password.clear();
      widget.onLogin(user);
    } else {
      if (retrySession) _password.clear();
      setState(() {
        _loading = false;
        _retrySession = retrySession;
        _error = error;
      });
    }
  }

  Future<void> _changeAccount() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await (widget.auth as SessionAuthService).signOut();
      if (!mounted) return;
      _email.clear();
      _password.clear();
      setState(() {
        _retrySession = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Keluar gagal. Coba lagi.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = widget.role == UserRole.owner;
    final accent = owner ? AppColors.navy : AppColors.darkTeal;
    final title = owner ? 'Owner' : 'Worker';
    final demo = widget.auth is DemoAuthService;
    return PopScope(
      canPop: !_loading && !_retrySession,
      child: Scaffold(
        appBar: AppBar(title: const Text('KatyuFlow')),
        body: SafeArea(
          top: false,
          child: PageList(
            maxWidth: 520,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: owner ? AppColors.navy : const Color(0xFFD9F7F3),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      owner ? Icons.shield_outlined : Icons.bolt_rounded,
                      size: 34,
                      color: owner ? Colors.white : accent,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Login $title',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: owner ? Colors.white : AppColors.navy,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      owner
                          ? 'Kelola pesanan dan tinjau pekerjaan tim.'
                          : 'Temukan project berikutnya dan kumpulkan poin.',
                      style: TextStyle(
                        color: owner ? Colors.white : AppColors.navy,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_retrySession) ...[
                      TextFormField(
                        controller: _email,
                        enabled: !_loading,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: (value) =>
                            RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                .hasMatch((value ?? '').trim())
                            ? null
                            : 'Masukkan email yang valid.',
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _password,
                        enabled: !_loading,
                        obscureText: _hidden,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          suffixIcon: IconButton(
                            tooltip: _hidden
                                ? 'Tampilkan password'
                                : 'Sembunyikan password',
                            onPressed: _loading
                                ? null
                                : () => setState(() => _hidden = !_hidden),
                            icon: Icon(
                              _hidden
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) =>
                            (value ?? '').isEmpty ? 'Masukkan password.' : null,
                      ),
                    ],
                    if (demo) ...[
                      const SizedBox(height: 12),
                      const Text('Akun demo lokal · Password: 123456'),
                    ],
                    if (_error case final error?) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 52),
                      ),
                      child: _loading
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                semanticsLabel: 'Sedang masuk',
                              ),
                            )
                          : Text(
                              _retrySession
                                  ? 'Coba lagi verifikasi'
                                  : 'Masuk ke Dashboard',
                            ),
                    ),
                    if (_retrySession)
                      TextButton(
                        onPressed: _loading ? null : _changeAccount,
                        child: const Text('Ganti akun'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
