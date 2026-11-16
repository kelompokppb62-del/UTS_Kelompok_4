import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as images;
import 'package:image_picker/image_picker.dart';

import '../../../core/widgets/notice.dart';
import '../../../core/widgets/page_list.dart';
import '../../auth/models/account.dart';
import '../models/project_collaboration.dart';
import '../models/work_project.dart';
import '../services/project_workspace.dart';
import '../widgets/project_deadline.dart';

Uint8List? compressRevisionImage(Uint8List bytes) {
  final decoder = images.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null || info.width * info.height > 24000000) return null;
  var image = decoder!.decodeFrame(0);
  if (image == null) return null;
  image = images.bakeOrientation(image);
  if (image.width > 1200 || image.height > 1200) {
    image = images.copyResize(
      image,
      width: image.width >= image.height ? 1200 : null,
      height: image.height > image.width ? 1200 : null,
    );
  }
  image.exif = images.ExifData();
  for (final quality in [82, 66, 50, 35, 22]) {
    final jpeg = images.encodeJpg(image, quality: quality);
    if (jpeg.length <= RevisionRequest.maxImageBytes) return jpeg;
  }
  return null;
}

bool isDisplayableRevisionImage(Uint8List bytes) {
  if (bytes.length < 16 || bytes.length > RevisionRequest.maxImageBytes) {
    return false;
  }
  try {
    final info = images.JpegDecoder().startDecode(bytes);
    return info != null &&
        info.width >= 1 &&
        info.width <= 1200 &&
        info.height >= 1 &&
        info.height <= 1200;
  } catch (_) {
    return false;
  }
}

class ProjectReviewForm extends StatefulWidget {
  const ProjectReviewForm({
    super.key,
    required this.account,
    required this.board,
    required this.project,
    required this.isRevision,
  });

  final Account account;
  final ProjectWorkspace board;
  final WorkProject project;
  final bool isRevision;

  @override
  State<ProjectReviewForm> createState() => _ProjectReviewFormState();
}

class _ProjectReviewFormState extends State<ProjectReviewForm> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _notes = TextEditingController();
  final _discord = TextEditingController();
  final _proof = TextEditingController();
  final _photos = <Uint8List>[];
  DateTime? _deadline;
  bool _saving = false;
  bool _picking = false;
  late final _checklist = widget.board.watchChecklist(widget.project.id);

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _discord.dispose();
    _proof.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_picking || _photos.length >= 2) return;
    setState(() => _picking = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (file == null || !mounted) return;
      if (await file.length() > 12000000) {
        if (mounted) {
          showNotice(
            context,
            'File sumber terlalu besar. Pilih gambar yang lebih kecil.',
          );
        }
        return;
      }
      final jpeg = await compute(
        compressRevisionImage,
        await file.readAsBytes(),
      );
      if (!mounted) return;
      if (jpeg == null) {
        showNotice(
          context,
          'Gambar tidak bisa dikompresi. Coba screenshot JPEG atau PNG lain.',
        );
      } else {
        setState(() => _photos.add(jpeg));
      }
    } catch (_) {
      if (mounted) {
        showNotice(context, 'Gambar gagal dibuka. Coba pilih gambar kembali.');
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _picking || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final board = widget.board;
    final project = widget.project;
    final proof = _proof.text.trim();
    ProjectResult result;
    try {
      result = widget.isRevision
          ? await board.requestRevision(
              widget.account,
              project.id,
              RevisionRequest(
                _title.text.trim(),
                _notes.text.trim(),
                _deadline,
                List.of(_photos),
              ),
              expectedActivityId: project.activityId,
            )
          : await board.submitWork(
              widget.account,
              project.id,
              WorkSubmission(
                _notes.text.trim(),
                _discord.text.trim(),
                proof.isEmpty ? null : proof,
              ),
              expectedActivityId: project.activityId,
            );
    } catch (_) {
      result = ProjectResult.failed;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (result == ProjectResult.submitted || result == ProjectResult.revision) {
      Navigator.of(context).pop(result);
    } else {
      showNotice(context, result.message);
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Wajib diisi.' : null;

  @override
  Widget build(BuildContext context) {
    final revision = widget.isRevision;
    final busy = _saving || _picking;
    final now = widget.board.serverNow;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(revision ? 'Request Revision' : 'Submit Work'),
        ),
        body: Form(
          key: _form,
          child: PageList(
            children: [
              Text(
                widget.project.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              if (revision)
                TextFormField(
                  controller: _title,
                  enabled: !busy,
                  maxLength: 160,
                  validator: _required,
                  decoration: const InputDecoration(labelText: 'Judul revisi'),
                ),
              TextFormField(
                controller: _notes,
                enabled: !busy,
                maxLength: 4000,
                minLines: 4,
                maxLines: 8,
                validator: _required,
                decoration: InputDecoration(
                  labelText: revision ? 'Deskripsi revisi' : 'Laporan hasil',
                ),
              ),
              if (revision) ...[
                OutlinedButton.icon(
                  onPressed: busy || _photos.length == 2 ? null : _pickImage,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text('Pilih screenshot (${_photos.length}/2)'),
                ),
                for (var index = 0; index < _photos.length; index++)
                  ListTile(
                    leading: Image.memory(
                      _photos[index],
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                    ),
                    title: Text('Screenshot ${index + 1}'),
                    onTap: () => showRevisionImage(context, _photos[index]),
                    trailing: IconButton(
                      tooltip: 'Hapus screenshot',
                      onPressed: busy
                          ? null
                          : () => setState(() => _photos.removeAt(index)),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: busy || now == null
                      ? null
                      : () async {
                          final picked = await selectDeadline(context, now);
                          if (mounted && picked != null) {
                            setState(() => _deadline = picked);
                          }
                        },
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    _deadline == null
                        ? 'Deadline revisi (opsional)'
                        : wibDateTime(_deadline!),
                  ),
                ),
                if (_deadline != null)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() => _deadline = null),
                    child: const Text('Hapus deadline revisi'),
                  ),
              ] else ...[
                TextFormField(
                  controller: _discord,
                  enabled: !busy,
                  maxLength: 300,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Link server Discord',
                    hintText: 'https://discord.gg/contohserver',
                  ),
                  validator: (value) =>
                      WorkSubmission.validDiscord(value?.trim() ?? '')
                      ? null
                      : 'Gunakan tautan undangan Discord HTTPS.',
                ),
                TextFormField(
                  controller: _proof,
                  enabled: !busy,
                  maxLength: 1000,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Link bukti tambahan (opsional)',
                  ),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ||
                          WorkSubmission.validHttps(value!.trim())
                      ? null
                      : 'Gunakan tautan HTTPS yang valid.',
                ),
                const SizedBox(height: 8),
                Text(
                  'Ringkasan checklist',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                StreamBuilder(
                  stream: _checklist,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Text('Checklist gagal dimuat.');
                    }
                    final items = snapshot.data;
                    if (items == null) return const LinearProgressIndicator();
                    if (items.isEmpty) {
                      return const Text('Belum ada checklist.');
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final item in items)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              item.done
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                            ),
                            title: Text(item.title),
                          ),
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: busy ? null : _save,
                child: Text(
                  _saving
                      ? 'Mengirim…'
                      : revision
                      ? 'Kirim revisi'
                      : 'Kirim untuk review',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void showRevisionImage(BuildContext context, Uint8List bytes) {
  showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: Stack(
        alignment: Alignment.topRight,
        children: [
          InteractiveViewer(
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Padding(
                padding: EdgeInsets.all(32),
                child: Text('Gambar tidak dapat dibuka.'),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Tutup',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    ),
  );
}
