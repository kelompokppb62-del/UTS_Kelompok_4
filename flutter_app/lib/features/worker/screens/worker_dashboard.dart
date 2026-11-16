import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/dashboard_shell.dart';
import '../../../core/widgets/page_list.dart';
import '../../auth/models/account.dart';
import '../../projects/models/work_project.dart';
import '../../projects/screens/project_details.dart';
import '../../projects/services/project_board.dart' show ProjectBoard;
import '../../projects/services/project_workspace.dart';
import 'worker_performance.dart';

class WorkerDashboard extends StatefulWidget {
  const WorkerDashboard({
    super.key,
    required this.worker,
    required this.board,
    required this.onLogout,
  });

  final Account worker;
  final ProjectWorkspace board;
  final VoidCallback onLogout;

  @override
  State<WorkerDashboard> createState() => _WorkerDashboardState();
}

class _WorkerDashboardState extends State<WorkerDashboard> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => DashboardShell(
    title: 'Dashboard Worker',
    tab: _tab,
    onTab: (tab) => setState(() => _tab = tab),
    onLogout: widget.onLogout,
    onProfile: () => Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => WorkerProfile(
          workspace: widget.board,
          worker: widget.worker,
          viewer: widget.worker,
        ),
      ),
    ),
    destinations: const [
      NavigationDestination(
        icon: Icon(Icons.explore_outlined),
        label: 'Tersedia',
      ),
      NavigationDestination(
        icon: Icon(Icons.assignment_ind_outlined),
        label: 'Project Saya',
      ),
      NavigationDestination(
        icon: Icon(Icons.history_rounded),
        label: 'Riwayat',
      ),
      NavigationDestination(
        icon: Icon(Icons.leaderboard_outlined),
        label: 'Leaderboard',
      ),
    ],
    body: _tab == 3
        ? WorkerLeaderboard(workspace: widget.board)
        : ListenableBuilder(
            listenable: widget.board,
            builder: (context, _) {
              final workspace = widget.board;
              if (workspace.error case final message?) {
                return PageList(children: [Text(message)]);
              }
              if (workspace.isLoading) {
                return const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Memuat project',
                  ),
                );
              }
              final board = widget.board;
              final worker = widget.worker;
              final mine = board.assignedTo(worker);
              final visible =
                  (switch (_tab) {
                    0 => board.projects.where(
                      (p) => p.status == ProjectStatus.available,
                    ),
                    1 => mine.where((p) => p.status != ProjectStatus.completed),
                    _ => mine.where((p) => p.status == ProjectStatus.completed),
                  }).toList()..sort(
                    (a, b) =>
                        a.effectiveDeadline.compareTo(b.effectiveDeadline),
                  );
              final urgent = visible
                  .where((p) => p.needsDeadlineAttention(board.serverNow))
                  .length;
              return PageList(
                key: ValueKey(_tab),
                children: [
                  Text(
                    ['Cari Project', 'Pekerjaan saya', 'Project selesai'][_tab],
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      'Pilih project yang masih tersedia.',
                      'Perbarui progres dan kirim hasil untuk review.',
                      'Lihat project yang sudah disetujui Owner.',
                    ][_tab],
                  ),
                  if (urgent > 0)
                    Text('$urgent project mendekati atau lewat deadline.'),
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.navy,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.all(18),
                    child: DefaultTextStyle(
                      style: Theme.of(context).textTheme.bodyMedium!
                          .copyWith(color: Colors.white),
                      child: Wrap(
                        spacing: 32,
                        runSpacing: 12,
                        children: [
                          _WorkerMetric(
                            label: 'Klaim hari ini',
                            value:
                                '${board.claimsToday(worker)} / ${ProjectBoard.dailyLimit}',
                          ),
                          _WorkerMetric(
                            label: 'Total poin',
                            value: '${board.earnedPoints(worker)}',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (visible.isEmpty)
                    Card(
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          [
                            'Belum ada project yang tersedia.',
                            'Project yang diklaim akan muncul di sini.',
                            'Riwayat muncul setelah Owner menyetujui project.',
                          ][_tab],
                        ),
                      ),
                    ),
                  for (final project in visible)
                    BoardProjectCard(
                      key: ValueKey(project.id),
                      project: project,
                      board: board,
                      account: worker,
                      onClaim: () {
                        if (mounted) setState(() => _tab = 1);
                      },
                    ),
                ],
              );
            },
          ),
  );
}

class _WorkerMetric extends StatelessWidget {
  const _WorkerMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      Text(
        value,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
    ],
  );
}
