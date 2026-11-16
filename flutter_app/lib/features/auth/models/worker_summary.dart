class WorkerSummary {
  const WorkerSummary({
    required this.id,
    required this.name,
    this.email,
    required this.status,
    required this.points,
  });

  final String id;
  final String name;
  final String? email;
  final String status;
  final int points;
}
