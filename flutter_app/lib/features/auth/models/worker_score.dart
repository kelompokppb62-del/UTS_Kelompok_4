class WorkerScore {
  const WorkerScore(
    this.id,
    this.name,
    this.points,
    this.completed,
    this.onTime,
  );

  final String id;
  final String name;
  final int points;
  final int completed;
  final int onTime;
}
