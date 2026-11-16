import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'android_update.dart';

bool get showAndroidUpdates =>
    kReleaseMode && !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class AndroidUpdateButton extends StatefulWidget {
  const AndroidUpdateButton({
    super.key,
    this.compact = false,
    this.check,
    this.open,
  });

  final bool compact;
  final Future<AndroidRelease?> Function()? check;
  final Future<bool> Function(Uri)? open;

  @override
  State<AndroidUpdateButton> createState() => _AndroidUpdateButtonState();
}

class _AndroidUpdateButtonState extends State<AndroidUpdateButton> {
  bool _checking = false;

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _openRelease(Uri uri) async {
    try {
      final ok =
          await (widget.open?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
      if (ok || !mounted) return;
    } catch (_) {
      if (!mounted) return;
    }
    _notice('Tautan APK resmi tidak dapat dibuka.');
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    AndroidRelease? release;
    try {
      release = await (widget.check ?? const AndroidUpdateCheck().latest)();
    } catch (_) {
      if (mounted) _notice('Belum dapat memeriksa pembaruan. Coba lagi nanti.');
      return;
    } finally {
      if (mounted) setState(() => _checking = false);
    }
    if (!mounted) return;
    if (release == null) {
      _notice('Belum ada pembaruan Android yang tersedia.');
      return;
    }
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('KatyuFlow ${release!.versionName} tersedia'),
        content: const Text(
          'Buka halaman distribusi resmi untuk mengunduh dan memasang APK secara manual.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Nanti'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Buka tautan APK resmi'),
          ),
        ],
      ),
    );
    if (mounted && shouldOpen == true) await _openRelease(release.url);
  }

  @override
  Widget build(BuildContext context) {
    const label = 'Periksa pembaruan Android';
    final action = _checking ? null : _check;
    return widget.compact
        ? IconButton(
            tooltip: _checking ? 'Memeriksa pembaruan' : label,
            onPressed: action,
            icon: const Icon(Icons.system_update_outlined),
          )
        : TextButton(
            onPressed: action,
            child: Text(_checking ? 'Memeriksa pembaruan…' : label),
          );
  }
}
