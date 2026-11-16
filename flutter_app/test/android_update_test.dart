import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katyuflow/features/updates/android_update.dart';
import 'package:katyuflow/features/updates/android_update_button.dart';

void main() {
  const official =
      'https://appdistribution.firebase.google.com/testerapps/example/releases/example';
  final active = <String, Object>{
    'active': true,
    'applicationId': 'com.katyuflow.katyuflow',
    'versionName': '1.2.1',
    'versionCode': 5,
    'downloadUrl': official,
  };

  test('only a numerically newer active version is offered', () {
    expect(AndroidRelease.forInstalled(active, 4)?.versionName, '1.2.1');
    expect(AndroidRelease.forInstalled(active, 5), isNull);
    expect(AndroidRelease.forInstalled(active, 6), isNull);
    expect(AndroidRelease.forInstalled({'active': false}, 1), isNull);
  });

  test('rejects other packages, unsafe links and malformed versions', () {
    for (final patch in <Map<String, Object>>[
      {'versionCode': '5'},
      {'versionName': 'bad'},
      {'applicationId': 'com.example.other'},
      {'downloadUrl': 'http://appdistribution.firebase.google.com/test'},
      {'downloadUrl': 'https://appdistribution.firebase.google.com.evil.test/'},
      {'downloadUrl': 'https://abc@appdistribution.firebase.google.com/'},
      {'downloadUrl': 'https://appdistribution.firebase.google.com:8443/'},
    ]) {
      expect(
        () => AndroidRelease.forInstalled({...active, ...patch}, 4),
        throwsFormatException,
      );
    }
  });

  testWidgets('opens the official link only after an explicit tap', (
    tester,
  ) async {
    final release = AndroidRelease(5, '1.2.1', Uri.parse(official));
    final opened = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AndroidUpdateButton(
            check: () async => release,
            open: (url) async {
              opened.add(url);
              return true;
            },
          ),
        ),
      ),
    );
    final check = find.text('Periksa pembaruan Android');
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(find.text('KatyuFlow 1.2.1 tersedia'), findsOneWidget);
    expect(opened, isEmpty);
    await tester.tap(find.text('Nanti'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    await tester.tap(check);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buka tautan APK resmi'));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse(official)]);
  });

  testWidgets('network errors do not open a browser or block the app', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AndroidUpdateButton(
            check: () async => throw Exception('Unavailable'),
            open: (_) async {
              fail('No URL should be opened');
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Periksa pembaruan Android'));
    await tester.pumpAndSettle();
    expect(
      find.text('Belum dapat memeriksa pembaruan. Coba lagi nanti.'),
      findsOneWidget,
    );
    expect(find.text('Buka tautan APK resmi'), findsNothing);
  });
}
