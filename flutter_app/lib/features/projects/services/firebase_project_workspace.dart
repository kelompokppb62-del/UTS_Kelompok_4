import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../auth/models/account.dart';
import '../../auth/models/worker_summary.dart';
import '../../auth/models/worker_score.dart';
import '../models/project_collaboration.dart';
import 'firestore_project_collaboration.dart';
import '../models/work_project.dart';
import 'firestore_project_mutations.dart';
import 'firestore_server_clock.dart';
import 'project_workspace.dart';

class FirebaseProjectWorkspace extends ProjectWorkspace {
  FirebaseProjectWorkspace(this._db, this._account) {
    _serverClock = FirestoreServerClock(_db, _account.id);
    _mutations = FirestoreProjectMutations(_db, _serverClock);
    _collaboration = FirestoreProjectCollaboration(_db, _account);
    _initialLoad = Timer(const Duration(seconds: 12), () {
      _initialLoadExpired = true;
      if (isLoading) notifyListeners();
    });
    final projects = _db.collection('projects');
    if (_account.role == UserRole.owner) {
      _watch(
        'projects',
        projects.snapshots(includeMetadataChanges: true),
        (snapshot) => _assigned = _decode(snapshot.docs),
      );
    } else {
      _watch(
        'projects',
        projects
            .where('assignedWorkerId', isEqualTo: _account.id)
            .snapshots(includeMetadataChanges: true),
        (snapshot) => _assigned = _decode(snapshot.docs),
      );
      _watch(
        'listings',
        _db
            .collection('projectListings')
            .snapshots(includeMetadataChanges: true),
        (snapshot) => _listings = _decode(snapshot.docs, listing: true),
      );
      _watch(
        'profile',
        _db.doc('users/${_account.id}').snapshots(includeMetadataChanges: true),
        (snapshot) => _points = (snapshot.data()?['points'] as int?) ?? 0,
      );
      _watch(
        'quota',
        _db
            .doc('claimCounters/${_account.id}')
            .snapshots(includeMetadataChanges: true),
        (snapshot) {
          _lastClaimAt = (snapshot.data()?['updatedAt'] as Timestamp?)
              ?.toDate();
          _count = (snapshot.data()?['claimCount'] as int?) ?? 0;
        },
      );
    }
    unawaited(_syncClock());
    _quotaTicker = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (_serverClock.now == null || timer.tick % 15 == 0) {
        unawaited(_syncClock());
      }
      notifyListeners();
    });
  }

  final FirebaseFirestore _db;
  late final FirestoreServerClock _serverClock;
  late final FirestoreProjectMutations _mutations;
  final Account _account;
  late final FirestoreProjectCollaboration _collaboration;

  @override
  DateTime? get serverNow => _serverClock.now;

  @override
  Stream<List<ProjectActivity>> watchActivity(String id) =>
      _collaboration.watchActivity(id);

  @override
  Future<List<Uint8List>> loadRevisionImages(String id) =>
      _collaboration.loadRevisionImages(id);

  @override
  Stream<List<ChecklistItem>> watchChecklist(String id) =>
      _collaboration.watchChecklist(id);

  @override
  Future<void> editChecklist(
    Account account,
    String id, {
    String? itemId,
    String? title,
  }) => _collaboration.editChecklist(id, itemId: itemId, title: title);

  @override
  Future<void> finishChecklist(
    Account account,
    String id,
    ChecklistItem item,
  ) => _collaboration.finishChecklist(id, item);

  @override
  Stream<List<ProjectMessage>> watchDiscussion(String id, {int limit = 30}) =>
      _collaboration.watchDiscussion(id, limit: limit);

  @override
  Future<void> sendMessage(Account account, String id, String text) =>
      _collaboration.sendMessage(id, text);

  @override
  Future<ProjectResult> submitWork(
    Account account,
    String id,
    WorkSubmission submission, {
    String? expectedActivityId,
  }) => _mutations.submit(
    account,
    id,
    submission,
    expectedActivityId: expectedActivityId,
  );

  @override
  Future<ProjectResult> requestRevision(
    Account account,
    String id,
    RevisionRequest revision, {
    String? expectedActivityId,
  }) => _mutations.revise(
    account,
    id,
    revision,
    expectedActivityId: expectedActivityId,
  );

  @override
  Stream<WorkerSummary> watchProfile(Account account) => _db
      .doc('users/${account.id}')
      .snapshots(includeMetadataChanges: true)
      .where(
        (snapshot) =>
            !snapshot.metadata.isFromCache &&
            !snapshot.metadata.hasPendingWrites,
      )
      .map(_profile);

  @override
  Stream<List<WorkerScore>> watchScores() => _db
      .collection('workerScores')
      .snapshots(includeMetadataChanges: true)
      .confirmed()
      .map((snapshot) {
        return snapshot.docs.map((row) {
          final data = row.data();
          return WorkerScore(
            row.id,
            data['name'] as String,
            data['points'] as int,
            data['completed'] as int,
            data['onTime'] as int,
          );
        }).toList();
      });

  WorkerSummary _profile(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? {};
    return WorkerSummary(
      id: snapshot.id,
      name: data['name'] as String? ?? 'Worker',
      email: data['email'] as String?,
      status: data['status'] as String? ?? '',
      points: data['points'] as int? ?? 0,
    );
  }

  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _ready = <String>{};
  final _cache = <String>{};
  var _assigned = <_ProjectRecord>[];
  var _listings = <_ProjectRecord>[];
  int _points = 0;
  int _count = 0;
  DateTime? _lastClaimAt;
  Timer? _quotaTicker;
  bool _disposed = false;
  late final Timer _initialLoad;
  bool _initialLoadExpired = false;
  String? _error;

  @override
  bool get isLoading =>
      _ready.length < (_account.role == UserRole.owner ? 1 : 4);
  @override
  String? get error =>
      _error ??
      (_cache.isEmpty && !(_initialLoadExpired && isLoading)
          ? null
          : 'Belum tersambung ke Firestore. Periksa koneksi untuk memuat project.');

  @override
  List<WorkProject> get projects {
    final records = [
      ..._assigned,
      ..._listings.where(
        (listing) =>
            !_assigned.any((entry) => entry.project.id == listing.project.id),
      ),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return records.map((record) => record.project).toList();
  }

  @override
  Stream<List<WorkerSummary>> watchWorkers() {
    if (_account.role != UserRole.owner) {
      return Stream.error(
        StateError('Daftar Worker hanya tersedia untuk Owner.'),
      );
    }
    return _db
        .collection('users')
        .where('role', isEqualTo: UserRole.worker.name)
        .snapshots(includeMetadataChanges: true)
        .where(
          (snapshot) =>
              !snapshot.metadata.isFromCache &&
              !snapshot.metadata.hasPendingWrites,
        )
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return _profile(doc);
          }).toList()..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        });
  }

  @override
  Iterable<WorkProject> assignedTo(Account account) => _assigned
      .map((entry) => entry.project)
      .where((p) => p.claimedBy == account.id);

  @override
  int earnedPoints(Account account) => _points;

  @override
  int claimsToday(Account account) {
    final lastClaim = _lastClaimAt;
    final now = _serverClock.now;
    if (lastClaim == null) return 0;
    return now == null || FirestoreServerClock.sameJakartaDay(lastClaim, now)
        ? _count
        : 0;
  }

  Future<void> _syncClock() async {
    try {
      await _serverClock.sync();
      if (!_disposed) notifyListeners();
    } catch (_) {
      // A claim obtains a fresh server sample before starting its transaction.
    }
  }

  void _watch<T extends Object>(
    String key,
    Stream<T> stream,
    void Function(T) consume,
  ) {
    _subscriptions.add(
      stream.listen(
        (snapshot) {
          final metadata = switch (snapshot) {
            QuerySnapshot<Map<String, dynamic>>() => snapshot.metadata,
            DocumentSnapshot<Map<String, dynamic>>() => snapshot.metadata,
            _ => throw StateError('Snapshot Firestore tidak didukung'),
          };
          // Ignore device cache, including values collected under a previous login.
          if (metadata.hasPendingWrites) return;
          if (metadata.isFromCache) {
            if (_ready.contains(key)) _cache.add(key);
          } else {
            _cache.remove(key);
            try {
              consume(snapshot);
              _ready.add(key);
            } catch (_) {
              _error = 'Data project tidak dapat dibaca. Hubungi Owner.';
            }
          }
          notifyListeners();
        },
        onError: (Object error) {
          _assigned = [];
          _listings = [];
          _error =
              error is FirebaseException && error.code == 'permission-denied'
              ? 'Akses project ditolak. Keluar dan masuk kembali.'
              : 'Project gagal dimuat. Periksa koneksi dan masuk kembali.';
          notifyListeners();
        },
      ),
    );
  }

  static List<_ProjectRecord> _decode(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    bool listing = false,
  }) => docs.map((doc) {
    final data = doc.data();
    return _ProjectRecord(
      (data['createdAt'] as Timestamp).toDate(),
      WorkProject(
        id: doc.id,
        title: data['title'] as String,
        client: (data['clientName'] as String?) ?? '',
        packageName: data['packageType'] as String,
        brief: (data['brief'] as String?) ?? '',
        deadline: (data['deadline'] as Timestamp).toDate(),
        status: ProjectStatus.fromStored(data['status'] as String),
        revisionDeadline: (data['revisionDeadline'] as Timestamp?)?.toDate(),
        submittedAt: (data['submittedAt'] as Timestamp?)?.toDate(),
        completedAt: data['status'] == 'completed'
            ? (data['updatedAt'] as Timestamp?)?.toDate()
            : null,
        points: data['points'] as int,
        activityId: data['activityId'] as String?,
        claimedBy: data['assignedWorkerId'] as String?,
        assignedWorkerName: data['assignedWorkerName'] as String?,
        claimedAt: (data['claimedAt'] as Timestamp?)?.toDate(),
        isListing: listing,
      ),
    );
  }).toList();

  @override
  Future<void> publishDraft(Account account, NewProjectDraft draft) =>
      _mutations.publish(account, draft);

  @override
  Future<ProjectResult> claim(Account account, String id) async {
    final result = await _mutations.claim(account, id);
    if (!_disposed) notifyListeners();
    return result;
  }

  @override
  Future<ProjectResult> advance(
    Account account,
    String id, {
    ProjectStatus? expectedStatus,
  }) => _mutations.advance(account, id, expectedStatus);

  @override
  Future<ProjectResult> review(
    Account account,
    String id, {
    required bool approved,
    String? expectedActivityId,
  }) => _mutations.review(
    account,
    id,
    approved,
    expectedActivityId: expectedActivityId,
  );

  @override
  void dispose() {
    _disposed = true;
    _quotaTicker?.cancel();
    _initialLoad.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}

class _ProjectRecord {
  const _ProjectRecord(this.createdAt, this.project);

  final DateTime createdAt;
  final WorkProject project;
}
