import 'dart:typed_data';

import '../../auth/models/account.dart';
import '../../auth/models/worker_summary.dart';
import '../../auth/models/worker_score.dart';
import '../models/project_collaboration.dart';
import '../models/work_project.dart';
import 'project_repository.dart';

import 'project_workspace.dart';

export 'project_workspace.dart' show ProjectResult;

class ProjectBoard extends ProjectWorkspace {
  ProjectBoard(this._repository, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const dailyLimit = 3;
  final ProjectRepository _repository;
  final DateTime Function() _now;
  int _nextProjectNumber = 105;

  @override
  List<WorkProject> get projects => _repository.projects;

  @override
  Stream<List<WorkerSummary>> watchWorkers() {
    const workerId = 'worker@katyuflow.app';
    final names = {workerId: 'Worker Demo'};
    for (final project in projects) {
      final id = project.claimedBy;
      if (id != null && !names.containsKey(id)) {
        names[id] = project.assignedWorkerName ?? (id == 'dina' ? 'Dina' : id);
      }
    }
    return Stream.value([
      for (final entry in names.entries)
        WorkerSummary(
          id: entry.key,
          name: entry.value,
          status: 'active',
          points: earnedPoints(Account(id: entry.key, role: UserRole.worker)),
        ),
    ]);
  }

  @override
  Iterable<WorkProject> assignedTo(Account account) =>
      projects.where((project) => project.claimedBy == account.id);

  @override
  int claimsToday(Account account) => _claimsOn(account, _now().toLocal());

  int _claimsOn(Account account, DateTime today) =>
      assignedTo(account).where((project) {
        final day = project.claimedAt?.toLocal();
        return day != null &&
            day.year == today.year &&
            day.month == today.month &&
            day.day == today.day;
      }).length;

  @override
  int earnedPoints(Account account) =>
      assignedTo(account)
          .where((project) => project.status == ProjectStatus.completed)
          .fold(0, (sum, project) => sum + project.points);

  @override
  Future<void> publishDraft(Account account, NewProjectDraft draft) async {
    if (publish(account, draft) == null) {
      throw const ProjectRequestException(
        'Project tidak dapat dipublikasikan.',
      );
    }
  }

  WorkProject? publish(Account account, NewProjectDraft draft) {
    final title = draft.title.trim();
    final client = draft.client.trim();
    if (account.role != UserRole.owner || title.isEmpty || client.isEmpty) {
      return null;
    }
    String id;
    do {
      id = 'KF-${_nextProjectNumber++}';
    } while (projectById(id) != null);
    final project = WorkProject(
      id: id,
      title: title,
      client: client,
      packageName: draft.packageName,
      brief: draft.brief.trim().isEmpty
          ? 'Belum ada brief tambahan.'
          : draft.brief.trim(),
      deadline: draft.deadline ?? _now().add(const Duration(days: 2)),
    );
    _save(project, account);
    return project;
  }

  @override
  ProjectResult claim(Account account, String id) {
    if (account.role != UserRole.worker) return ProjectResult.forbidden;
    final project = projectById(id);
    if (project == null ||
        project.status != ProjectStatus.available ||
        project.claimedBy != null) {
      return ProjectResult.unavailable;
    }
    final now = _now().toLocal();
    if (_claimsOn(account, now) >= dailyLimit) return ProjectResult.quota;
    _save(
      project.withStatus(
        ProjectStatus.claimed,
        workerId: account.id,
        when: now,
      ),
      account,
    );
    return ProjectResult.claimed;
  }

  @override
  ProjectResult advance(
    Account account,
    String id, {
    ProjectStatus? expectedStatus,
  }) {
    final project = projectById(id);
    if (account.role != UserRole.worker ||
        project == null ||
        project.claimedBy != account.id) {
      return ProjectResult.forbidden;
    }
    if (expectedStatus != null && project.status != expectedStatus) {
      return ProjectResult.invalidStatus;
    }
    final next = switch (project.status) {
      ProjectStatus.claimed || ProjectStatus.revision => ProjectStatus.working,
      ProjectStatus.working => ProjectStatus.almostDone,
      ProjectStatus.almostDone => ProjectStatus.waitingReview,
      _ => null,
    };
    if (next == null) return ProjectResult.invalidStatus;
    _save(project.withStatus(next), account);
    return ProjectResult.updated;
  }

  @override
  ProjectResult review(
    Account account,
    String id, {
    required bool approved,
    String? expectedActivityId,
  }) {
    if (account.role != UserRole.owner) return ProjectResult.forbidden;
    final project = projectById(id);
    if (project == null || project.status != ProjectStatus.waitingReview) {
      return ProjectResult.invalidStatus;
    }
    _save(
      project.withStatus(
        approved ? ProjectStatus.completed : ProjectStatus.revision,
        completed: approved ? _now() : null,
      ),
      account,
    );
    return approved ? ProjectResult.approved : ProjectResult.revision;
  }

  final _events = <String, List<ProjectActivity>>{};
  final _images = <String, List<Uint8List>>{};
  final _checklists = <String, Map<String, ChecklistItem>>{};
  final _messages = <String, List<ProjectMessage>>{};
  final _lastMessage = <(String, String), DateTime>{};
  int _sequence = 0;

  @override
  DateTime get serverNow => _now();

  String _name(Account account) => switch (account.id) {
    'worker@katyuflow.app' => 'Worker Demo',
    'owner@katyuflow.app' => 'Owner Demo',
    'dina' => 'Dina',
    _ => account.id,
  };

  Stream<T> _watch<T>(T Function() read) => Stream.multi((sink) {
    void emit() => sink.add(read());
    addListener(emit);
    sink.onCancel = () => removeListener(emit);
    emit();
  });

  @override
  Stream<WorkerSummary> watchProfile(Account account) => _watch(
    () => WorkerSummary(
      id: account.id,
      name: _name(account),
      email: account.id.contains('@') ? account.id : null,
      status: 'active',
      points: earnedPoints(account),
    ),
  );

  @override
  Stream<List<WorkerScore>> watchScores() => _watch(() {
    final ids = {
      'worker@katyuflow.app',
      ...projects.map((p) => p.claimedBy).nonNulls,
    };
    return ids.map((id) {
      final account = Account(id: id, role: UserRole.worker);
      final completed = assignedTo(account)
          .where((p) => p.status == ProjectStatus.completed);
      return WorkerScore(
        id,
        _name(account),
        earnedPoints(account),
        completed.length,
        completed.where((p) => p.submittedOnTime == true).length,
      );
    }).toList();
  });

  @override
  Stream<List<ProjectActivity>> watchActivity(String id) =>
      _watch(() => List.of(_events[id] ?? []));

  @override
  Future<List<Uint8List>> loadRevisionImages(String id) async =>
      _images[id] ?? [];

  @override
  Stream<List<ChecklistItem>> watchChecklist(String id) => _watch(
    () => (_checklists[id]?.values ?? const <ChecklistItem>[]).toList(),
  );

  @override
  Future<void> editChecklist(
    Account account,
    String id, {
    String? itemId,
    String? title,
  }) async {
    final project = projectById(id);
    if (account.role != UserRole.owner ||
        project == null ||
        project.status == ProjectStatus.completed) {
      throw ProjectRequestException(ProjectResult.forbidden.message);
    }
    final list = _checklists.putIfAbsent(id, () => {});
    final existing = list[itemId];
    if (itemId != null && (existing == null || existing.done)) {
      throw ProjectRequestException(ProjectResult.invalidStatus.message);
    }
    if (title == null && itemId != null) {
      list.remove(itemId);
    } else {
      final text = title?.trim() ?? '';
      if (text.isEmpty || text.length > 160) {
        throw ProjectRequestException(ProjectResult.invalidDetails.message);
      }
      final key = itemId ?? '${++_sequence}';
      list[key] = ChecklistItem(key, text, false);
    }
    notifyListeners();
  }

  @override
  Future<void> finishChecklist(
    Account account,
    String id,
    ChecklistItem item,
  ) async {
    final project = projectById(id);
    final list = _checklists[id];
    final current = list?[item.id];
    if (project == null ||
        project.claimedBy != account.id ||
        account.role != UserRole.worker ||
        project.status == ProjectStatus.completed ||
        project.status == ProjectStatus.waitingReview ||
        current == null ||
        current.done ||
        current.title != item.title) {
      throw ProjectRequestException(ProjectResult.forbidden.message);
    }
    list![item.id] = ChecklistItem(item.id, item.title, true);
    _record(id, account, 'checklist_done', itemTitle: item.title);
    notifyListeners();
  }

  @override
  Stream<List<ProjectMessage>> watchDiscussion(String id, {int limit = 30}) =>
      _watch(() {
        final messages = _messages[id] ?? [];
        return messages
            .skip(messages.length > limit ? messages.length - limit : 0)
            .toList();
      });

  @override
  Future<void> sendMessage(Account account, String id, String text) async {
    final project = projectById(id);
    if (project?.claimedBy == null ||
        (account.role != UserRole.owner && project!.claimedBy != account.id)) {
      throw ProjectRequestException(ProjectResult.forbidden.message);
    }
    final clean = text.trim();
    final now = _now();
    final key = (id, account.id);
    final previous = _lastMessage[key];
    if (clean.isEmpty ||
        clean.length > 1000 ||
        (previous != null &&
            now.difference(previous) < const Duration(seconds: 3))) {
      throw const ProjectRequestException('Periksa pesan atau tunggu 3 detik.');
    }
    _lastMessage[key] = now;
    _messages
        .putIfAbsent(id, () => [])
        .add(ProjectMessage(_name(account), clean, now));
    notifyListeners();
  }

  @override
  ProjectResult submitWork(
    Account account,
    String id,
    WorkSubmission submission, {
    String? expectedActivityId,
  }) {
    final project = projectById(id);
    if (project == null ||
        account.role != UserRole.worker ||
        project.claimedBy != account.id) {
      return ProjectResult.forbidden;
    }
    if (project.status != ProjectStatus.almostDone &&
        project.status != ProjectStatus.revision) {
      return ProjectResult.invalidStatus;
    }
    if (submission.notes.trim().isEmpty ||
        submission.notes.length > 4000 ||
        !WorkSubmission.validDiscord(submission.discordUrl) ||
        (submission.proofUrl != null &&
            !WorkSubmission.validHttps(submission.proofUrl!))) {
      return ProjectResult.invalidDetails;
    }
    _save(
      project.withStatus(ProjectStatus.waitingReview, submitted: _now()),
      account,
      submission: submission,
    );
    return ProjectResult.submitted;
  }

  @override
  ProjectResult requestRevision(
    Account account,
    String id,
    RevisionRequest revision, {
    String? expectedActivityId,
  }) {
    final project = projectById(id);
    if (account.role != UserRole.owner) return ProjectResult.forbidden;
    if (project == null || project.status != ProjectStatus.waitingReview) {
      return ProjectResult.invalidStatus;
    }
    if (revision.title.trim().isEmpty ||
        revision.title.length > 160 ||
        revision.description.trim().isEmpty ||
        revision.description.length > 4000 ||
        revision.images.length > 2 ||
        revision.images.any(
          (image) => image.length > RevisionRequest.maxImageBytes,
        ) ||
        (revision.deadline != null && !revision.deadline!.isAfter(_now()))) {
      return ProjectResult.invalidDetails;
    }
    _save(
      project.withStatus(
        ProjectStatus.revision,
        revisionDue: revision.deadline,
      ),
      account,
      revision: revision,
    );
    return ProjectResult.revision;
  }

  void _record(
    String id,
    Account account,
    String action, {
    WorkSubmission? submission,
    RevisionRequest? revision,
    String? itemTitle,
  }) {
    final eventId = '${++_sequence}';
    if (revision != null && revision.images.isNotEmpty) {
      _images[eventId] = revision.images;
    }
    _events
        .putIfAbsent(id, () => [])
        .insert(
          0,
          ProjectActivity(
            id: eventId,
            actor: account.id,
            action: action,
            at: _now(),
            submission: submission,
            revision: revision,
            imageCount: revision?.images.length ?? 0,
            itemTitle: itemTitle,
          ),
        );
  }

  void _save(
    WorkProject project,
    Account account, {
    WorkSubmission? submission,
    RevisionRequest? revision,
  }) {
    _repository.save(project);
    _record(
      project.id,
      account,
      project.status == ProjectStatus.available
          ? 'published'
          : project.status.storedName,
      submission: submission,
      revision: revision,
    );
    notifyListeners();
  }
}
