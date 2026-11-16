import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class AndroidRelease {
  const AndroidRelease(this.versionCode, this.versionName, this.url);

  final int versionCode;
  final String versionName;
  final Uri url;

  static AndroidRelease? forInstalled(Object? manifest, int installedCode) {
    if (manifest is! Map<String, dynamic>) {
      throw const FormatException('Invalid update manifest');
    }
    if (manifest['active'] == false) return null;

    final code = manifest['versionCode'];
    final name = manifest['versionName'];
    final url = manifest['downloadUrl'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (manifest['active'] != true ||
        manifest['applicationId'] != 'com.katyuflow.katyuflow' ||
        code is! int ||
        code <= 0 ||
        code > 2100000000 ||
        name is! String ||
        name.length > 32 ||
        !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(name) ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'appdistribution.firebase.google.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Invalid Android release');
    }
    return code > installedCode ? AndroidRelease(code, name, uri) : null;
  }
}

class AndroidUpdateCheck {
  const AndroidUpdateCheck();

  static const _application = MethodChannel('com.katyuflow.katyuflow/release');
  static final _manifest = Uri.https(
    'katyuflow.web.app',
    '/android-release.json',
  );
  static const _maxBytes = 4096;

  Future<AndroidRelease?> latest() async {
    final installedCode = await _application.invokeMethod<int>('versionCode');
    if (installedCode == null || installedCode <= 0) {
      throw const FormatException('Missing installed versionCode');
    }
    final client = http.Client();
    try {
      return await _read(
        client,
        installedCode,
      ).timeout(const Duration(seconds: 8));
    } finally {
      client.close();
    }
  }

  Future<AndroidRelease?> _read(http.Client client, int installedCode) async {
    final request = http.Request('GET', _manifest)
      ..followRedirects = false
      ..headers['Accept'] = 'application/json';
    final response = await client.send(request);
    final type = response.headers['content-type']?.split(';').first.trim();
    if (response.statusCode != 200 ||
        type != 'application/json' ||
        (response.contentLength ?? 0) > _maxBytes) {
      throw const FormatException('Invalid update response');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > _maxBytes) {
        throw const FormatException('Update response too large');
      }
      bytes.addAll(chunk);
    }
    return AndroidRelease.forInstalled(
      jsonDecode(utf8.decode(bytes)),
      installedCode,
    );
  }
}
