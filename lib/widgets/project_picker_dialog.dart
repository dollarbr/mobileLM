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
      title: Text('workspace_project'.tr),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'ppd_choose_folder'.tr,
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
              if (projects.isEmpty)
                Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('no_projects_yet___create_one_to_get_star'.tr),
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
                decoration: InputDecoration(
                  labelText: 'pp_new_project_name'.tr,
                  hintText: 'pp_name_hint'.tr,
                  prefixIcon: const Icon(Icons.create_new_folder),
                ),
                onSubmitted: (_) => _createProject(context),
              ),
              const SizedBox(height: 8),
              // **A `Wrap`, and this is the fourth time this repo pays for it.**
              // A `Row` with `spaceBetween` and two text buttons has no width of
              // its own: each button carries horizontal padding, the labels are
              // sentences in Portuguese, and nothing limits the sum. Measured on
              // the Galaxy A72 at the app's **default** font scale of 1.10 it
              // overflowed by 24 px.
              //
              // `Wrap` keeps the current look whenever the two fit — with
              // `spaceBetween` they still sit at opposite ends — and stacks them
              // when they do not, which is the behaviour the `Row` does not have.
              // And the two are *alternatives*: one binds a project, the other
              // explicitly refuses to, and stacking them says that in a way two
              // buttons lying down do not.
              //
              // `test/project_picker_layout_test.dart` fixes the width and the
              // text scale, and its first test asserts the `Row` **does**
              // overflow, so the harness cannot quietly stop being hostile.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop(kNoProjectSentinel),
                    child: Text('no_project'.tr),
                  ),
                  FilledButton(
                    onPressed: () => _createProject(context),
                    child: Text('create_project'.tr),
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
