import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/notice.dart';
import '../../auth/models/account.dart';
import '../models/project_collaboration.dart';
import '../models/work_project.dart';
import '../services/project_workspace.dart';
import '../widgets/project_deadline.dart';
import 'project_review_forms.dart';

class ProjectHistory extends StatefulWidget {
  const ProjectHistory({super.key, required this.board, required this.project});

  final ProjectWorkspace board;
  final WorkProject project;

  @override
  State<ProjectHistory> createState() => _ProjectHistoryState();
}

class _ProjectHistoryState extends State<ProjectHistory> {
  late final _history = widget.board.watchActivity(widget.project.id);
  final _loadingImages = <String>{};

  Future<void> _openImages(ProjectActivity entry) async {
    if (!_loadingImages.add(entry.id)) return;
    setState(() {});
    try {
      final images = (await widget.board.loadRevisionImages(entry.id))
          .where(isDisplayableRevisionImage)
          .toList();
      if (!mounted) return;
      if (images.isEmpty) {
        showNotice(context, 'Lampiran tidak tersedia.');
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Screenshot revisi'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final bytes in images)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      onTap: () => showRevisionImage(context, bytes),
                      child: Image.memory(
                        bytes,
                        width: 240,
                        height: 112,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Text('Gambar tidak dapat dibuka.'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) showNotice(context, 'Lampiran gagal dimuat.');
    } finally {
      _loadingImages.remove(entry.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _openLink(String value, {bool discord = false}) async {
    final valid = discord
        ? WorkSubmission.validDiscord(value)
        : WorkSubmission.validHttps(value);
    try {
      if (valid &&
          await launchUrl(
            Uri.parse(value),
            mode: LaunchMode.externalApplication,
          )) {
        return;
      }
    } catch (_) {
      // The browser or operating system may block the new window.
    }
    if (mounted) showNotice(context, 'Tautan tidak dapat dibuka.');
  }

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: _history,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Text('Riwayat project gagal dimuat.');
      final entries = snapshot.data;
      if (entries == null) return const LinearProgressIndicator();
      if (entries.isEmpty) return const Text('Belum ada catatan aktivitas.');
      final submissionEvents = entries.where(
        (entry) => ['waitingReview', 'waiting_review'].contains(entry.action),
      );
      final firstSubmission = submissionEvents.isEmpty
          ? null
          : submissionEvents.last.id;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in entries)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _activityTitle(entry, firstSubmission),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      '${_actor(entry)} • ${wibDateTime(entry.at)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (entry.submission case final work?) ...[
                      const SizedBox(height: 8),
                      SelectableText(work.notes),
                      TextButton(
                        onPressed: () =>
                            _openLink(work.discordUrl, discord: true),
                        child: const Text('Buka server Discord'),
                      ),
                      if (work.proofUrl case final url?)
                        TextButton(
                          onPressed: () => _openLink(url),
                          child: const Text('Buka bukti tambahan'),
                        ),
                    ],
                    if (entry.revision case final revision?) ...[
                      const SizedBox(height: 8),
                      Text(
                        revision.title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      SelectableText(revision.description),
                      if (revision.deadline case final deadline?)
                        Text('Deadline revisi ${wibDateTime(deadline)}'),
                      if (entry.imageCount > 0)
                        TextButton.icon(
                          onPressed: _loadingImages.contains(entry.id)
                              ? null
                              : () => _openImages(entry),
                          icon: const Icon(Icons.image_outlined),
                          label: Text('Lihat ${entry.imageCount} screenshot'),
                        ),
                    ],
                    if (entry.action == 'completed')
                      Text('Poin diberikan +${widget.project.points}'),
                    if (entry.itemTitle != null &&
                        entry.action == 'checklist_done')
                      Text(entry.itemTitle!),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );

  String _actor(ProjectActivity entry) => switch (entry.action) {
    'published' || 'revision' || 'revision_required' || 'completed' => 'Owner',
    _ => widget.project.assignedWorkerName ?? 'Worker (${entry.actor})',
  };

  String _activityTitle(ProjectActivity entry, String? firstSubmission) =>
      switch (entry.action) {
        'published' => 'Project dibuat dan dipublikasikan',
        'claimed' => 'Project diklaim',
        'working' => 'Pengerjaan dimulai',
        'almostDone' => 'Project hampir selesai',
        'checklist_done' => 'Item checklist selesai',
        'waiting_review' || 'waitingReview' =>
          entry.id == firstSubmission
              ? 'Hasil dikirim untuk review'
              : 'Hasil revisi dikirim ulang',
        'revision_required' || 'revision' => 'Owner meminta revisi',
        'completed' => 'Owner menyetujui hasil',
        _ => 'Aktivitas project',
      };
}

class ProjectChecklist extends StatefulWidget {
  const ProjectChecklist({
    super.key,
    required this.board,
    required this.account,
    required this.project,
  });

  final ProjectWorkspace board;
  final Account account;
  final WorkProject project;

  @override
  State<ProjectChecklist> createState() => _ProjectChecklistState();
}

class _ProjectChecklistState extends State<ProjectChecklist> {
  late final _items = widget.board.watchChecklist(widget.project.id);
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on ProjectRequestException catch (error) {
      if (mounted) showNotice(context, error.message);
    } catch (_) {
      if (mounted) {
        showNotice(
          context,
          'Checklist gagal diperbarui. Periksa status project.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([ChecklistItem? item]) async {
    var value = item?.title ?? '';
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item == null ? 'Tambah item' : 'Edit item'),
        content: TextFormField(
          initialValue: value,
          onChanged: (text) => value = text,
          autofocus: true,
          maxLength: 160,
          decoration: const InputDecoration(labelText: 'Judul pekerjaan'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, value.trim()),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (!mounted || title == null) return;
    await _run(
      () => widget.board.editChecklist(
        widget.account,
        widget.project.id,
        itemId: item?.id,
        title: title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: _items,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Text('Checklist gagal dimuat.');
      final items = snapshot.data;
      if (items == null) return const LinearProgressIndicator();
      final project = widget.project;
      final owner = widget.account.role == UserRole.owner;
      final edit = owner && project.status != ProjectStatus.completed;
      final tick =
          !owner &&
          project.claimedBy == widget.account.id &&
          project.status != ProjectStatus.completed &&
          project.status != ProjectStatus.waitingReview;
      final done = items.where((item) => item.done).length;
      final progress = items.isEmpty ? 0.0 : done / items.length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Checklist · ${(progress * 100).round()}%',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 6),
          if (items.isEmpty) const Text('Belum ada item checklist.'),
          for (final item in items)
            if (edit && !item.done)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.title),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Edit item',
                      onPressed: _busy ? null : () => _edit(item),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Hapus item',
                      onPressed: _busy
                          ? null
                          : () => _run(
                              () => widget.board.editChecklist(
                                widget.account,
                                project.id,
                                itemId: item.id,
                              ),
                            ),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              )
            else
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.title),
                value: item.done,
                onChanged: tick && !item.done && !_busy
                    ? (_) => _run(
                        () => widget.board.finishChecklist(
                          widget.account,
                          project.id,
                          item,
                        ),
                      )
                    : null,
              ),
          if (edit)
            OutlinedButton.icon(
              onPressed: _busy ? null : _edit,
              icon: const Icon(Icons.add),
              label: const Text('Tambah item checklist'),
            ),
        ],
      );
    },
  );
}

class ProjectDiscussion extends StatefulWidget {
  const ProjectDiscussion({
    super.key,
    required this.board,
    required this.account,
    required this.project,
  });

  final ProjectWorkspace board;
  final Account account;
  final WorkProject project;

  @override
  State<ProjectDiscussion> createState() => _ProjectDiscussionState();
}

class _ProjectDiscussionState extends State<ProjectDiscussion> {
  final _text = TextEditingController();
  late var _messages = widget.board.watchDiscussion(widget.project.id);
  int _limit = 30;
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || _text.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.board.sendMessage(
        widget.account,
        widget.project.id,
        _text.text,
      );
      if (mounted) _text.clear();
    } catch (_) {
      if (mounted) {
        showNotice(
          context,
          'Pesan gagal dikirim. Periksa koneksi atau tunggu 3 detik.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Diskusi Project')),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: StreamBuilder(
              stream: _messages,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Diskusi gagal dimuat.'));
                }
                final messages = snapshot.data;
                if (messages == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (messages.isEmpty) {
                  return const Center(child: Text('Belum ada pesan.'));
                }
                return ListView(
                  reverse: true,
                  padding: const EdgeInsets.all(14),
                  children: [
                    for (final message in messages.reversed)
                      Card(
                        child: ListTile(
                          title: Text(message.author),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(message.text),
                              Text(wibDateTime(message.at)),
                            ],
                          ),
                        ),
                      ),
                    if (messages.length == _limit)
                      TextButton(
                        onPressed: () => setState(() {
                          _limit += 30;
                          _messages = widget.board.watchDiscussion(
                            widget.project.id,
                            limit: _limit,
                          );
                        }),
                        child: const Text('Muat pesan sebelumnya'),
                      ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    enabled: !_sending,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: 1000,
                    decoration: const InputDecoration(labelText: 'Pesan'),
                  ),
                ),
                IconButton.filled(
                  tooltip: 'Kirim pesan',
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send_outlined),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
