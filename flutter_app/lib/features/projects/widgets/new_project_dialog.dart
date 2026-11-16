import 'package:flutter/material.dart';

import 'package:katyuflow/features/projects/models/work_project.dart';

import 'project_deadline.dart';

class NewProjectDialog extends StatefulWidget {
  const NewProjectDialog({super.key, this.serverNow});

  final DateTime? serverNow;

  @override
  State<NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<NewProjectDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _client = TextEditingController();
  final _brief = TextEditingController();
  String _packageName = 'Basic';
  DateTime? _deadline;

  @override
  void dispose() {
    _title.dispose();
    _client.dispose();
    _brief.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.of(context).pop(
      NewProjectDraft(
        title: _title.text.trim(),
        client: _client.text.trim(),
        packageName: _packageName,
        brief: _brief.text.trim(),
        deadline: _deadline,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tambah Project'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _title,
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Nama project wajib diisi.'
                    : null,
                decoration: const InputDecoration(labelText: 'Nama project'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _client,
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Nama client wajib diisi.'
                    : null,
                decoration: const InputDecoration(labelText: 'Nama client'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _packageName,
                decoration: const InputDecoration(labelText: 'Paket layanan'),
                items: const ['Basic', 'Full Setup', 'Premium']
                    .map(
                      (name) =>
                          DropdownMenuItem(value: name, child: Text(name)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _packageName = value);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _brief,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Brief project'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: widget.serverNow == null
                    ? null
                    : () async {
                        final picked = await selectDeadline(
                          context,
                          widget.serverNow!,
                        );
                        if (mounted && picked != null) {
                          setState(() => _deadline = picked);
                        }
                      },
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  _deadline == null
                      ? 'Deadline default 2 hari'
                      : wibDateTime(_deadline!),
                ),
              ),
              if (_deadline != null)
                TextButton(
                  onPressed: () => setState(() => _deadline = null),
                  child: const Text('Gunakan deadline default'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Publikasikan')),
      ],
    );
  }
}
