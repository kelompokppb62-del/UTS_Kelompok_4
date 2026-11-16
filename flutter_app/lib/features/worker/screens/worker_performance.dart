import 'package:flutter/material.dart';

import '../../../core/widgets/page_list.dart';
import '../../auth/models/account.dart';
import '../../projects/models/work_project.dart';
import '../../projects/screens/project_details.dart';
import '../../projects/services/project_workspace.dart';
import '../../projects/widgets/project_deadline.dart';

class WorkerProfile extends StatefulWidget {
  const WorkerProfile({
    super.key,
    required this.workspace,
    required this.worker,
    required this.viewer,
  });

  final ProjectWorkspace workspace;
  final Account worker;
  final Account viewer;

  @override
  State<WorkerProfile> createState() => _WorkerProfileState();
}

class _WorkerProfileState extends State<WorkerProfile> {
  late final _profile = widget.workspace.watchProfile(widget.worker);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Profil Worker')),
    body: StreamBuilder(
      stream: _profile,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Profil gagal dimuat.'));
        }
        final profile = snapshot.data;
        if (profile == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListenableBuilder(
          listenable: widget.workspace,
          builder: (context, _) {
            if (widget.workspace.error case final error?) {
              return PageList(children: [Text(error)]);
            }
            if (widget.workspace.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            final projects = widget.workspace.assignedTo(widget.worker).toList()
              ..sort((a, b) => b.deadline.compareTo(a.deadline));
            final completed = projects
                .where((p) => p.status == ProjectStatus.completed)
                .toList();
            final measured = completed
                .where((p) => p.submittedOnTime != null)
                .length;
            final onTime = completed
                .where((p) => p.submittedOnTime == true)
                .length;
            final completion = projects.isEmpty
                ? '—'
                : '${(100 * completed.length / projects.length).round()}%';
            return PageList(
              children: [
                Text(
                  profile.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (profile.email case final email?) Text(email),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Total project diklaim  ${projects.length}'),
                        Text(
                          'Project aktif  ${projects.length - completed.length}',
                        ),
                        Text('Project selesai  ${completed.length}'),
                        Text('Total poin  ${profile.points}'),
                        Text('Persentase penyelesaian  $completion'),
                        Text('Tepat waktu  $onTime dari $measured terukur'),
                        if (measured < completed.length)
                          Text(
                            '${completed.length - measured} tanpa data waktu',
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Riwayat pekerjaan',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (projects.isEmpty)
                  const Text('Belum ada project yang diklaim.'),
                for (final project in projects)
                  Card(
                    child: ListTile(
                      title: Text(project.title),
                      subtitle: Text(
                        '${statusText(project.status)} • ${wibDateTime(project.effectiveDeadline)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => ProjectDetails(
                            board: widget.workspace,
                            account: widget.viewer,
                            projectId: project.id,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    ),
  );
}

class WorkerLeaderboard extends StatefulWidget {
  const WorkerLeaderboard({super.key, required this.workspace});

  final ProjectWorkspace workspace;

  @override
  State<WorkerLeaderboard> createState() => _WorkerLeaderboardState();
}

class _WorkerLeaderboardState extends State<WorkerLeaderboard> {
  late final _scores = widget.workspace.watchScores();

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: _scores,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(child: Text('Leaderboard gagal dimuat.'));
      }
      final scores = snapshot.data?.toList();
      if (scores == null) {
        return const Center(child: CircularProgressIndicator());
      }
      scores.sort((a, b) {
        final points = b.points.compareTo(a.points);
        if (points != 0) return points;
        final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return name != 0 ? name : a.id.compareTo(b.id);
      });
      return PageList(
        children: [
          Text('Leaderboard', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          if (scores.isEmpty) const Text('Belum ada Worker di leaderboard.'),
          for (final (index, score) in scores.indexed)
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Text('${index + 1}')),
                title: Text(score.name),
                subtitle: Text(
                  '${score.completed} selesai • ${score.onTime} tepat waktu',
                ),
                trailing: Text('${score.points} poin'),
              ),
            ),
        ],
      );
    },
  );
}
