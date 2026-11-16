import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../auth/models/account.dart';
import '../models/project_collaboration.dart';
import '../models/work_project.dart';
import 'firestore_server_clock.dart';
import 'project_workspace.dart';

class FirestoreProjectMutations {
  FirestoreProjectMutations(this._db, this._clock);

  final FirebaseFirestore _db;
  final FirestoreServerClock _clock;

  static const _dailyLimit = 3;
  static const _pointsPerProject = 100;
  static const _packages = ['Basic', 'Full Setup', 'Premium'];

  DocumentReference<Map<String, dynamic>> _project(String id) =>
      _db.doc('projects/$id');

  Future<void> publish(Account account, NewProjectDraft draft) async {
    if (account.role != UserRole.owner) {
      throw ProjectRequestException(ProjectResult.forbidden.message);
    }
    final title = draft.title.trim();
    final client = draft.client.trim();
    final brief = draft.brief.trim();
    if (title.isEmpty ||
        title.length > 160 ||
        client.isEmpty ||
        client.length > 160 ||
        brief.length > 4000 ||
        !_packages.contains(draft.packageName)) {
      throw const ProjectRequestException(
        'Periksa judul, nama client, paket, dan panjang brief.',
      );
    }
    try {
      final now = await _clock.sync();
      final deadline = draft.deadline ?? now.add(const Duration(days: 2));
      if (!deadline.isAfter(now) ||
          deadline.difference(now) > const Duration(days: 365)) {
        throw const ProjectRequestException(
          'Deadline harus setelah waktu sekarang dan maksimal 365 hari.',
        );
      }
      final project = _db.collection('projects').doc();
      final activity = _db.collection('projectActivities').doc();
      final listing = <String, Object>{
        'projectId': project.id,
        'title': title,
        'packageType': draft.packageName,
        'status': 'available',
        'points': _pointsPerProject,
        'deadline': Timestamp.fromDate(deadline),
        'createdAt': FieldValue.serverTimestamp(),
      };
      final batch = _db.batch()
        ..set(project, {
          ...listing,
          'createdBy': account.id,
          'clientName': client,
          'brief': brief.isEmpty ? 'Belum ada brief tambahan.' : brief,
          'assignedWorkerId': null,
          'updatedAt': FieldValue.serverTimestamp(),
          'activityId': activity.id,
        })
        ..set(_db.doc('projectListings/${project.id}'), listing)
        ..set(activity, _activity(account, project.id, 'published'));
      await batch.commit().timeout(const Duration(seconds: 20));
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw ProjectRequestException(ProjectResult.forbidden.message);
      }
      throw const ProjectRequestException(
        'Publikasi belum dikonfirmasi. Periksa daftar project sebelum mencoba lagi.',
      );
    } on TimeoutException {
      throw const ProjectRequestException(
        'Publikasi belum dikonfirmasi. Periksa daftar project sebelum mencoba lagi.',
      );
    }
  }

  Future<ProjectResult> claim(Account account, String id) async {
    if (account.role != UserRole.worker) return ProjectResult.forbidden;
    final listing = _db.doc('projectListings/$id');
    final counter = _db.doc('claimCounters/${account.id}');
    final user = _db.doc('users/${account.id}');
    final activity = _db.collection('projectActivities').doc();

    return _run(() async {
      for (var attempt = 0; ; attempt++) {
        await _clock.sync();
        try {
          return await _db.runTransaction((transaction) async {
            // The private project cannot be read before assignment. The listing
            // is the concurrency guard, and Rules validate both documents.
            if (!(await transaction.get(listing)).exists) {
              return ProjectResult.unavailable;
            }
            final quota = (await transaction.get(counter)).data();
            final updatedAt = quota?['updatedAt'] as Timestamp?;
            final now = _clock.now!;
            final count =
                updatedAt != null &&
                    FirestoreServerClock.sameJakartaDay(updatedAt.toDate(), now)
                ? quota!['claimCount'] as int
                : 0;
            if (count >= _dailyLimit) return ProjectResult.quota;
            final profile = (await transaction.get(user)).data()!;
            transaction
              ..update(_project(id), {
                'status': 'claimed',
                'assignedWorkerId': account.id,
                'assignedWorkerName': profile['name'],
                'claimedAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
                'activityId': activity.id,
              })
              ..delete(listing)
              ..set(counter, {
                'workerId': account.id,
                'lastProjectId': id,
                'claimCount': count + 1,
                'updatedAt': FieldValue.serverTimestamp(),
              })
              ..set(activity, _activity(account, id, 'claimed'));
            return ProjectResult.claimed;
          });
        } on FirebaseException catch (error) {
          // A transaction can cross midnight after reading the clock sample.
          if (attempt != 0 || error.code != 'permission-denied') rethrow;
        }
      }
    });
  }

  Future<ProjectResult> advance(
    Account account,
    String id,
    ProjectStatus? expected,
  ) {
    if (account.role != UserRole.worker) {
      return Future.value(ProjectResult.forbidden);
    }
    final project = _project(id);
    return _run(
      () => _db.runTransaction((transaction) async {
        final data = (await transaction.get(project)).data();
        if (data == null || data['assignedWorkerId'] != account.id) {
          return ProjectResult.forbidden;
        }
        if (ProjectStatus.fromStored(data['status'] as String) != expected) {
          return ProjectResult.invalidStatus;
        }
        final next = switch (expected) {
          ProjectStatus.claimed ||
          ProjectStatus.revision => ProjectStatus.working,
          ProjectStatus.working => ProjectStatus.almostDone,
          _ => null,
        };
        if (next == null) return ProjectResult.invalidStatus;
        _transition(transaction, account, project, next.name);
        return ProjectResult.updated;
      }),
    );
  }

  Future<ProjectResult> review(
    Account account,
    String id,
    bool approved, {
    String? expectedActivityId,
  }) {
    if (account.role != UserRole.owner) {
      return Future.value(ProjectResult.forbidden);
    }
    final project = _project(id);
    final reward = _db.doc('pointTransactions/$id');
    Future<ProjectResult> transact() => _db.runTransaction((transaction) async {
      final data = (await transaction.get(project)).data();
      final recorded = (await transaction.get(reward)).exists;
      if (approved && data?['status'] == 'completed' && recorded) {
        return ProjectResult.approved;
      }
      if (data == null ||
          ProjectStatus.fromStored(data['status'] as String) !=
              ProjectStatus.waitingReview ||
          recorded ||
          (expectedActivityId != null &&
              data['activityId'] != expectedActivityId)) {
        return ProjectResult.invalidStatus;
      }
      if (!approved) return ProjectResult.invalidStatus;
      final assignee = data['assignedWorkerId'] as String?;
      if (assignee == null || assignee.isEmpty) {
        return ProjectResult.invalidStatus;
      }
      final worker = _db.doc('users/$assignee');
      final workerData = (await transaction.get(worker)).data();
      final scoreboard = _db.doc('workerScores/$assignee');
      final score = (await transaction.get(scoreboard)).data();
      final previous = workerData?['points'];
      final points = data['points'];
      if (previous is! int || points is! int || points <= 0) {
        return ProjectResult.invalidStatus;
      }
      final beforePoints = (score?['points'] as int?) ?? 0;
      if (beforePoints != previous) return ProjectResult.scoreOutOfSync;
      final deadline =
          (data['revisionDeadline'] ?? data['deadline']) as Timestamp;
      final submitted = (data['submittedAt'] ?? data['updatedAt']) as Timestamp;
      final onTime = !submitted.toDate().isAfter(deadline.toDate());
      _transition(
        transaction,
        account,
        project,
        'completed',
        patch: {'submittedAt': submitted},
      );
      transaction
        ..update(worker, {
          'points': previous + points,
          'lastRewardProjectId': id,
        })
        ..set(scoreboard, {
          'name': workerData!['name'],
          'points': previous + points,
          'completed': ((score?['completed'] as int?) ?? 0) + 1,
          'onTime': ((score?['onTime'] as int?) ?? 0) + (onTime ? 1 : 0),
          'updatedAt': FieldValue.serverTimestamp(),
        })
        ..set(reward, {
          'projectId': id,
          'workerId': assignee,
          'points': points,
          'reason': 'project_approved',
          'createdAt': FieldValue.serverTimestamp(),
        });
      return ProjectResult.approved;
    });

    return _run(() async {
      try {
        return await transact();
      } on FirebaseException catch (error) {
        // A simultaneous approval may change the ledger before Rules evaluate
        // this attempt. Read it again to recognize an already-completed review.
        if (!approved || error.code != 'permission-denied') rethrow;
        return transact();
      }
    });
  }

  Future<ProjectResult> submit(
    Account account,
    String id,
    WorkSubmission work, {
    String? expectedActivityId,
  }) {
    if (account.role != UserRole.worker) {
      return Future.value(ProjectResult.forbidden);
    }
    if (work.notes.trim().isEmpty ||
        work.notes.length > 4000 ||
        !WorkSubmission.validDiscord(work.discordUrl) ||
        (work.proofUrl != null && !WorkSubmission.validHttps(work.proofUrl!))) {
      return Future.value(ProjectResult.invalidDetails);
    }
    return _run(
      () => _db.runTransaction((transaction) async {
        final project = _project(id);
        final data = (await transaction.get(project)).data();
        if (data == null || data['assignedWorkerId'] != account.id) {
          return ProjectResult.forbidden;
        }
        final status = ProjectStatus.fromStored(data['status'] as String);
        if ((status != ProjectStatus.almostDone &&
                status != ProjectStatus.revision) ||
            (expectedActivityId != null &&
                data['activityId'] != expectedActivityId)) {
          return ProjectResult.invalidStatus;
        }
        _transition(
          transaction,
          account,
          project,
          ProjectStatus.waitingReview.storedName,
          patch: {'submittedAt': FieldValue.serverTimestamp()},
          detail: {
            'notes': work.notes.trim(),
            'discordUrl': work.discordUrl,
            'proofUrl': work.proofUrl,
          },
        );
        return ProjectResult.submitted;
      }),
    );
  }

  Future<ProjectResult> revise(
    Account account,
    String id,
    RevisionRequest revision, {
    String? expectedActivityId,
  }) {
    if (account.role != UserRole.owner) {
      return Future.value(ProjectResult.forbidden);
    }
    if (revision.title.trim().isEmpty ||
        revision.title.length > 160 ||
        revision.description.trim().isEmpty ||
        revision.description.length > 4000 ||
        revision.images.length > 2 ||
        revision.images.any(
          (image) => image.length > RevisionRequest.maxImageBytes,
        )) {
      return Future.value(ProjectResult.invalidDetails);
    }
    return _run(() async {
      final deadline = revision.deadline;
      if (deadline != null) {
        final now = await _clock.sync();
        if (!deadline.isAfter(now) ||
            deadline.difference(now) > const Duration(days: 365)) {
          return ProjectResult.invalidDetails;
        }
      }
      return _db.runTransaction((transaction) async {
        final project = _project(id);
        final data = (await transaction.get(project)).data();
        if (data == null ||
            ProjectStatus.fromStored(data['status'] as String) !=
                ProjectStatus.waitingReview ||
            (expectedActivityId != null &&
                data['activityId'] != expectedActivityId)) {
          return ProjectResult.invalidStatus;
        }
        final due = deadline == null ? null : Timestamp.fromDate(deadline);
        final activity = _transition(
          transaction,
          account,
          project,
          ProjectStatus.revision.storedName,
          patch: {'revisionDeadline': due},
          detail: {
            'title': revision.title.trim(),
            'description': revision.description.trim(),
            'deadline': due,
            'imageCount': revision.images.length,
          },
        );
        if (revision.images.isNotEmpty) {
          transaction.set(_db.doc('revisionImages/$activity'), {
            'encoding': 'image/jpeg',
            'images': revision.images.map(Blob.new).toList(),
          });
        }
        return ProjectResult.revision;
      });
    });
  }

  String _transition(
    Transaction transaction,
    Account account,
    DocumentReference<Map<String, dynamic>> project,
    String status, {
    Map<String, Object?> patch = const {},
    Map<String, Object?>? detail,
  }) {
    final activity = _db.collection('projectActivities').doc();
    transaction
      ..update(project, {
        ...patch,
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
        'activityId': activity.id,
      })
      ..set(activity, {
        ..._activity(account, project.id, status),
        'detail': ?detail,
      });
    return activity.id;
  }

  Map<String, Object> _activity(Account account, String id, String action) => {
    'projectId': id,
    'actorId': account.id,
    'action': action,
    'timestamp': FieldValue.serverTimestamp(),
  };

  Future<ProjectResult> _run(Future<ProjectResult> Function() command) async {
    try {
      return await command();
    } on FirebaseException catch (error) {
      return switch (error.code) {
        'permission-denied' || 'unauthenticated' => ProjectResult.forbidden,
        'not-found' => ProjectResult.unavailable,
        _ => ProjectResult.failed,
      };
    } on TimeoutException {
      return ProjectResult.failed;
    }
  }
}
