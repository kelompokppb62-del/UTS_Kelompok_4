enum ProjectStatus {
  available,
  claimed,
  working,
  almostDone,
  waitingReview,
  revision,
  completed;

  String get storedName => switch (this) {
    waitingReview => 'waiting_review',
    revision => 'revision_required',
    _ => name,
  };

  static ProjectStatus fromStored(String value) => switch (value) {
    'waiting_review' => waitingReview,
    'revision_required' => revision,
    _ => values.byName(value),
  };
}

class WorkProject {
  const WorkProject({
    required this.id,
    required this.title,
    required this.client,
    required this.packageName,
    required this.brief,
    required this.deadline,
    this.points = 100,
    this.status = ProjectStatus.available,
    this.claimedBy,
    this.assignedWorkerName,
    this.isListing = false,
    this.claimedAt,
    this.revisionDeadline,
    this.submittedAt,
    this.completedAt,
    this.activityId,
  });

  final String id;
  final String title;
  final String client;
  final String packageName;
  final String brief;
  final DateTime deadline;
  final int points;
  final ProjectStatus status;
  final String? claimedBy;
  final String? assignedWorkerName;
  final bool isListing;
  final DateTime? claimedAt;
  final DateTime? revisionDeadline;
  final DateTime? submittedAt;
  final DateTime? completedAt;
  final String? activityId;

  DateTime get effectiveDeadline => revisionDeadline ?? deadline;
  bool? get submittedOnTime {
    final finished = submittedAt ?? completedAt;
    return finished == null ? null : !finished.isAfter(effectiveDeadline);
  }

  bool needsDeadlineAttention(DateTime? now) =>
      now != null &&
      status != ProjectStatus.completed &&
      status != ProjectStatus.waitingReview &&
      effectiveDeadline.difference(now) <= const Duration(hours: 24);

  WorkProject withStatus(
    ProjectStatus next, {
    String? workerId,
    DateTime? when,
    DateTime? revisionDue,
    DateTime? submitted,
    DateTime? completed,
  }) => WorkProject(
    id: id,
    title: title,
    client: client,
    packageName: packageName,
    brief: brief,
    deadline: deadline,
    points: points,
    status: next,
    claimedBy: workerId ?? claimedBy,
    assignedWorkerName: assignedWorkerName,
    isListing: isListing,
    claimedAt: when ?? claimedAt,
    revisionDeadline: next == ProjectStatus.revision
        ? revisionDue
        : revisionDeadline,
    submittedAt: submitted ?? submittedAt,
    completedAt: completed ?? completedAt,
    activityId: activityId,
  );
}

String statusText(ProjectStatus status) {
  switch (status) {
    case ProjectStatus.available:
      return 'Tersedia';
    case ProjectStatus.claimed:
      return 'Sudah diklaim';
    case ProjectStatus.working:
      return 'Sedang dibuat';
    case ProjectStatus.almostDone:
      return 'Hampir selesai';
    case ProjectStatus.waitingReview:
      return 'Menunggu review';
    case ProjectStatus.revision:
      return 'Perlu revisi';
    case ProjectStatus.completed:
      return 'Selesai';
  }
}

class NewProjectDraft {
  const NewProjectDraft({
    required this.title,
    required this.client,
    required this.packageName,
    required this.brief,
    this.deadline,
  });

  final String title;
  final String client;
  final String packageName;
  final String brief;
  final DateTime? deadline;
}
