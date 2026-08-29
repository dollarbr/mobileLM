import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Non-project sentinel: when [_pick] returns this, the user explicitly chose
/// to open a general chat with no project bound.
const String kNoProjectSentinel = '\uE000';

/// Asks whether a new chat should bind to an existing project folder, create a
/// new one, or stay project-less. Returns a project name, [kNoProjectSentinel]
/// for "no project", or null if dismissed.
Future<String?> showProjectPicker(List<String> projects) async {
  return Get.dialog<String>(
    _ProjectPickerDialog(projects: projects),
    barrierDismissible: true,
  );
}

class _ProjectPickerDialog extends StatefulWidget {
  final List<String> projects;
  const _ProjectPickerDialog({required this.projects});

  @override
  State<_ProjectPickerDialog> createState() => _ProjectPickerDialogState();
}

class _ProjectPickerDialogState extends State<_ProjectPickerDialog> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projects = widget.projects;
    return AlertDialog(
      title: const Text('Workspace project'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'This chat works inside a project folder. Choose where its '
                  'files live, or keep it as a general chat.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
              if (projects.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('No projects yet — create one to get started.'),
                )
              else
                ...projects.map((name) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.folder),
                      title: Text(name),
                      onTap: () => Navigator.of(context).pop(name),
                    )),
              const Divider(),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'New project name',
                  hintText: 'e.g. my-website',
                  prefixIcon: Icon(Icons.create_new_folder),
                ),
                onSubmitted: (_) => _createProject(context),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop(kNoProjectSentinel),
                    child: const Text('No project'),
                  ),
                  FilledButton(
                    onPressed: () => _createProject(context),
                    child: const Text('Create project'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _createProject(BuildContext context) {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }
}
