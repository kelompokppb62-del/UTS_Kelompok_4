import 'package:flutter/material.dart';

import '../../../core/widgets/page_list.dart';
import '../../auth/models/worker_summary.dart';
import '../../auth/models/account.dart';
import '../../worker/screens/worker_performance.dart';
import '../../projects/services/project_workspace.dart';

class WorkerDirectory extends StatefulWidget {
  const WorkerDirectory({
    super.key,
    required this.workspace,
    required this.owner,
  });

  final ProjectWorkspace workspace;
  final Account owner;

  @override
  State<WorkerDirectory> createState() => _WorkerDirectoryState();
}

class _WorkerDirectoryState extends State<WorkerDirectory> {
  late final _workers = widget.workspace.watchWorkers();

  @override
  Widget build(BuildContext context) => StreamBuilder<List<WorkerSummary>>(
    stream: _workers,
    builder: (context, snapshot) {
      final workers = snapshot.data;
      return PageList(
        children: [
          Text(
            'Daftar Worker',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          if (snapshot.hasError)
            const Text(
              'Daftar Worker gagal dimuat. Buka tab ini kembali untuk mencoba lagi.',
            )
          else if (workers == null)
            const LinearProgressIndicator(
              semanticsLabel: 'Memuat daftar Worker',
            )
          else if (workers.isEmpty)
            const Text('Belum ada akun Worker.')
          else
            for (final worker in workers)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(worker.name),
                  subtitle: Text(switch (worker.status) {
                    'active' => 'Aktif',
                    'suspended' => 'Dinonaktifkan',
                    'provisioning' => 'Sedang disiapkan',
                    _ => 'Status belum tersedia',
                  }),
                  trailing: Text('${worker.points} poin'),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => WorkerProfile(
                        workspace: widget.workspace,
                        viewer: widget.owner,
                        worker: Account(id: worker.id, role: UserRole.worker),
                      ),
                    ),
                  ),
                ),
              ),
        ],
      );
    },
  );
}
