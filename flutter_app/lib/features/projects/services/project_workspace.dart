import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../auth/models/account.dart';
import '../../auth/models/worker_summary.dart';
import '../../auth/models/worker_score.dart';
import '../models/project_collaboration.dart';
import '../models/work_project.dart';

enum ProjectResult {
  submitted('Hasil dikirim untuk review Owner.'),
  invalidDetails('Periksa isi formulir dan deadline.'),
  scoreOutOfSync('Riwayat poin perlu disinkronkan sebelum approval.'),
  updated('Status project diperbarui.'),
  claimed('Project masuk ke Project Saya.'),
  approved('Project disetujui. Poin worker ditambahkan.'),
  revision('Project dikembalikan untuk revisi.'),
  unavailable('Project ini sudah tidak tersedia.'),
  quota('Batas 3 klaim project hari ini sudah tercapai.'),
  forbidden('Akun ini tidak dapat memperbarui project tersebut.'),
  failed('Perubahan gagal. Periksa koneksi dan muat ulang status project.'),
  invalidStatus('Status project tidak memungkinkan tindakan ini.');

  const ProjectResult(this.message);
  final String message;
}

class ProjectRequestException implements Exception {
  const ProjectRequestException(this.message);

  final String message;
}

abstract class ProjectWorkspace extends ChangeNotifier {
  bool get isLoading => false;
  String? get error => null;

  DateTime? get serverNow;
  List<WorkProject> get projects;
  Stream<WorkerSummary> watchProfile(Account account);
  Stream<List<WorkerScore>> watchScores();
  Stream<List<ProjectActivity>> watchActivity(String id);
  Future<List<Uint8List>> loadRevisionImages(String id);
  Stream<List<ChecklistItem>> watchChecklist(String id);
  Future<void> editChecklist(
    Account account,
    String id, {
    String? itemId,
    String? title,
  });
  Future<void> finishChecklist(Account account, String id, ChecklistItem item);
  Stream<List<ProjectMessage>> watchDiscussion(String id, {int limit = 30});
  Future<void> sendMessage(Account account, String id, String text);
  FutureOr<ProjectResult> submitWork(
    Account account,
    String id,
    WorkSubmission submission, {
    String? expectedActivityId,
  });
  FutureOr<ProjectResult> requestRevision(
    Account account,
    String id,
    RevisionRequest revision, {
    String? expectedActivityId,
  });
  Stream<List<WorkerSummary>> watchWorkers();

  WorkProject? projectById(String id) {
    for (final project in projects) {
      if (project.id == id) return project;
    }
    return null;
  }

  Iterable<WorkProject> assignedTo(Account account);
  int claimsToday(Account account);
  int earnedPoints(Account account);

  Future<void> publishDraft(Account account, NewProjectDraft draft);
  FutureOr<ProjectResult> claim(Account account, String id);
  FutureOr<ProjectResult> advance(
    Account account,
    String id, {
    ProjectStatus? expectedStatus,
  });
  FutureOr<ProjectResult> review(
    Account account,
    String id, {
    required bool approved,
    String? expectedActivityId,
  });
}
