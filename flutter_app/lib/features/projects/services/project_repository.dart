import '../models/work_project.dart';

abstract interface class ProjectRepository {
  List<WorkProject> get projects;
  void save(WorkProject project);
}

class InMemoryProjectRepository implements ProjectRepository {
  InMemoryProjectRepository(Iterable<WorkProject> seed)
    : _projects = {for (final project in seed) project.id: project};

  final Map<String, WorkProject> _projects;

  @override
  List<WorkProject> get projects =>
      List.unmodifiable(_projects.values.toList().reversed);

  @override
  void save(WorkProject project) => _projects[project.id] = project;
}
