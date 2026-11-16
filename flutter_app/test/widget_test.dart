import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katyuflow/app/app.dart';
import 'package:katyuflow/features/projects/screens/project_details.dart';

void main() {
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(finder);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  Future<void> login(WidgetTester tester, String role) async {
    await tap(tester, find.text('Login as $role'));
    await tester.enterText(find.byType(TextFormField).at(1), '123456');
    await tap(tester, find.text('Masuk ke Dashboard'));
    expect(find.text('Dashboard $role'), findsOneWidget);
  }

  Future<void> logout(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Keluar / Ganti akun'));
    await tester.pumpAndSettle();
    expect(find.text('Login as Owner'), findsOneWidget);
  }

  Future<void> openPublished(WidgetTester tester) async {
    final card = find.byWidgetPredicate(
      (widget) =>
          widget is BoardProjectCard &&
          widget.project.title == 'Proyek Uji Discord',
    );
    await tester.scrollUntilVisible(
      card,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tap(
      tester,
      find.descendant(of: card, matching: find.text('Lihat detail')),
    );
  }

  testWidgets('Only the Owner dashboard exposes the Worker directory', (
    tester,
  ) async {
    await tester.pumpWidget(const KatyuFlowApp());
    await login(tester, 'Owner');
    await tester.tap(find.text('Worker'));
    await tester.pumpAndSettle();
    expect(find.text('Daftar Worker'), findsOneWidget);
    expect(find.text('Worker Demo'), findsOneWidget);
    await logout(tester);
    await login(tester, 'Worker');
    expect(find.text('Daftar Worker'), findsNothing);
    expect(find.text('Worker'), findsNothing);
  });

  testWidgets(
    'Login validates fields, shows loading and rejects the wrong role',
    (tester) async {
      await tester.pumpWidget(const KatyuFlowApp());
      await tap(tester, find.text('Login as Worker'));
      final email = find.byType(TextFormField).first;
      final password = find.byType(TextFormField).at(1);
      await tester.enterText(email, 'salah');
      await tap(tester, find.text('Masuk ke Dashboard'));
      expect(find.text('Masukkan email yang valid.'), findsOneWidget);
      expect(find.text('Masukkan password.'), findsOneWidget);

      await tester.enterText(email, 'owner@katyuflow.app');
      await tester.enterText(password, '123456');
      await tap(tester, find.byTooltip('Tampilkan password'));
      expect(
        tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
        isFalse,
      );
      final submit = find.text('Masuk ke Dashboard');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
      expect(
        find.text('Email atau password demo tidak cocok.'),
        findsOneWidget,
      );
      expect(find.text('Dashboard Worker'), findsNothing);
    },
  );

  testWidgets(
    'Owner and Worker complete a published project on a phone layout',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const KatyuFlowApp());

      await login(tester, 'Owner');
      expect(find.text('Total project'), findsOneWidget);
      await tap(tester, find.text('Tambah project'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama project'),
        'Proyek Uji Discord',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama client'),
        'Client Uji',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Brief project'),
        'Brief untuk pengujian.',
      );
      await tester.tap(find.text('Publikasikan'));
      await tester.pumpAndSettle();
      await openPublished(tester);
      await tap(tester, find.text('Tambah item checklist'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Judul pekerjaan'),
        'Atur role',
      );
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(find.text('Atur role'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await logout(tester);

      await login(tester, 'Worker');
      await openPublished(tester);
      expect(find.text('Brief untuk pengujian.'), findsOneWidget);
      await tap(tester, find.text('Klaim project'));
      expect(find.text('Pekerjaan saya'), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);
      await openPublished(tester);
      await tap(tester, find.widgetWithText(CheckboxListTile, 'Atur role'));
      expect(find.text('Checklist · 100%'), findsOneWidget);
      await tap(tester, find.text('Diskusi Project'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Pesan'),
        'Mulai pekerjaan.',
      );
      await tester.tap(find.byTooltip('Kirim pesan'));
      await tester.pumpAndSettle();
      expect(find.text('Mulai pekerjaan.'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      for (final action in [
        'Mulai pengerjaan',
        'Tandai hampir selesai',
        'Kirim untuk review',
      ]) {
        await tap(tester, find.text(action));
      }
      expect(find.text('Submit Work'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Laporan hasil'),
        'Roles dan automod selesai.',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Link server Discord'),
        'https://discord.gg/katyuflow',
      );
      await tap(tester, find.text('Kirim untuk review').last);
      expect(find.text('Menunggu review'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      await logout(tester);

      await login(tester, 'Owner');
      await tester.tap(find.text('Project'));
      await tester.pumpAndSettle();
      await openPublished(tester);
      await tap(tester, find.text('Minta revisi'));
      expect(find.text('Request Revision'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Judul revisi'),
        'Roles',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Deskripsi revisi'),
        'Tambahkan role moderator.',
      );
      await tap(tester, find.text('Kirim revisi'));
      await tap(tester, find.text('Tambahkan role moderator.'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await logout(tester);

      await login(tester, 'Worker');
      await tester.tap(find.text('Project Saya'));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Kirim hasil revisi'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Laporan hasil'),
        'Role moderator ditambahkan.',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Link server Discord'),
        'https://discord.gg/katyuflow',
      );
      await tap(tester, find.text('Kirim untuk review').last);
      await logout(tester);

      await login(tester, 'Owner');
      await tester.tap(find.text('Project'));
      await tester.pumpAndSettle();
      await openPublished(tester);
      await tap(tester, find.text('Setujui'));
      await tester.scrollUntilVisible(
        find.text('Selesai'),
        -180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Selesai'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await logout(tester);

      await login(tester, 'Worker');
      await tester.tap(find.text('Riwayat'));
      await tester.pumpAndSettle();
      expect(find.text('Proyek Uji Discord'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      await tester.tap(find.byTooltip('Profil Worker'));
      await tester.pumpAndSettle();
      expect(find.text('Worker Demo'), findsOneWidget);
      expect(find.text('Total poin  100'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leaderboard'));
      await tester.pumpAndSettle();
      expect(find.text('100 poin'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
