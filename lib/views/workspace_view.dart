import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/workspace_service.dart';
import '../services/workspace_native.dart'
    if (dart.library.html) '../services/workspace_stub.dart' as ws;

class WorkspaceView extends GetView<WorkspaceService> {
  const WorkspaceView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workspace'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Back to projects',
            onPressed: () {
              Get.dialog<void>(
                _ProjectListDialog(),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => controller.refresh(),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!controller.isReady) {
          return const Center(
            child: Text('Workspace not configured. Open Settings to pick a folder.'),
          );
        }
        return Column(
          children: [
            _Breadcrumbs(service: controller),
            Expanded(child: _DirList(service: controller)),
          ],
        );
      }),
      floatingActionButton: Obx(() =>
          controller.isReady
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FloatingActionButton.extended(
                      heroTag: 'new-folder',
                      onPressed: () => _createFolder(context),
                      icon: const Icon(Icons.create_new_folder),
                      label: const Text('Folder'),
                      backgroundColor: Colors.blue,
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton.extended(
                      heroTag: 'new-file',
                      onPressed: () => _createFile(context),
                      icon: const Icon(Icons.description),
                      label: const Text('File'),
                      backgroundColor: Colors.green,
                    ),
                  ],
                )
              : const SizedBox.shrink()),
    );
  }

  Future<void> _createFolder(BuildContext context) async {
    final name = await _promptName(context, 'New folder', 'Folder name');
    if (name == null || name.isEmpty) return;
    final ok = await controller.createFolder(name);
    if (!ok) _showError('Could not create folder (name may be taken).');
  }

  Future<void> _createFile(BuildContext context) async {
    final name = await _promptName(context, 'New file', 'File name (e.g. notes.md)');
    if (name == null || name.isEmpty) return;
    final ok = await controller.createFile(name, content: '');
    if (!ok) _showError('Could not create file (name may be taken).');
  }

  static Future<String?> _promptName(
      BuildContext context, String title, String hint) {
    final ctrl = TextEditingController();
    return Get.dialog<String>(
      AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Get.back(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Get.back(result: ctrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    Get.snackbar('Workspace', message, snackPosition: SnackPosition.BOTTOM);
  }
}

class _Breadcrumbs extends StatelessWidget {
  final WorkspaceService service;
  const _Breadcrumbs({required this.service});

  @override
  Widget build(BuildContext context) {
    final rel = service.currentRelPath.value;
    final segments = rel.isEmpty ? <String>[] : rel.split('/');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.home, size: 20),
              tooltip: 'Workspace root',
              onPressed: () => service.goRoot(),
            ),
            Text('/', style: TextStyle(color: Theme.of(context).hintColor)),
            for (final s in segments) ...[
              const Icon(Icons.chevron_right, size: 16),
              Text(s, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }
}

class _DirList extends StatelessWidget {
  final WorkspaceService service;
  const _DirList({required this.service});

  @override
  Widget build(BuildContext context) {
    final entries = service.entries;
    final dirs = entries.where((e) => e.isDir).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final files = entries.where((e) => !e.isDir).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (entries.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('This folder is empty'),
            Text('Use the buttons below to add files or folders.',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        for (final d in dirs)
          _ItemTile(
            entry: d,
            relPath: service.childRelPath(d.name),
            onOpen: () => service.openFolder(d.name),
            onRename: () => _rename(context, d.name),
            onDelete: () => _delete(context, d.name),
          ),
        for (final f in files)
          _ItemTile(
            entry: f,
            relPath: service.childRelPath(f.name),
            onOpen: () => _openFile(context, service, f, service.childRelPath(f.name)),
            onRename: () => _rename(context, f.name),
            onDelete: () => _delete(context, f.name),
          ),
      ],
    );
  }

  Future<void> _rename(BuildContext context, String name) async {
    final newName = await WorkspaceView._promptName(context, 'Rename', 'New name');
    if (newName == null || newName.isEmpty || newName == name) return;
    final ok = await service.renameItem(service.childRelPath(name), newName);
    if (!ok) {
      Get.snackbar('Workspace', 'Rename failed.',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _delete(BuildContext context, String name) async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Confirm delete'),
        content: Text('Delete "$name"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Get.back(result: true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await service.deleteItem(service.childRelPath(name));
    if (!ok) {
      Get.snackbar('Workspace', 'Delete failed.',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _openFile(BuildContext context, WorkspaceService service,
      ws.WorkspaceEntry entry, String relPath) async {
    final content = await service.readFile(relPath);
    if (content == null) {
      Get.snackbar('Workspace', 'Could not read ${entry.name}',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    if (!context.mounted) return;
    await Get.dialog<void>(
      Dialog(
        child: Container(
          width: 720,
          constraints: const BoxConstraints(maxHeight: 620),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(entry.name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                      onPressed: () => Get.back(), icon: const Icon(Icons.close)),
                ],
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(content,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final ws.WorkspaceEntry entry;
  final String relPath;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _ItemTile({
    required this.entry,
    required this.relPath,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        leading: Icon(
          entry.isDir ? Icons.folder : Icons.insert_drive_file,
          color: entry.isDir ? Colors.blue : Colors.grey,
        ),
        title: Text(entry.name,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(entry.isDir
            ? 'Folder'
            : _formatSize(entry.size)),
        onTap: onOpen,
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'rename') onRename();
            if (v == 'delete') onDelete();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }

  String _formatSize(int size) {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _ProjectListDialog extends StatefulWidget {
  @override
  State<_ProjectListDialog> createState() => _ProjectListDialogState();
}

class _ProjectListDialogState extends State<_ProjectListDialog> {
  late Future<List<String>> _future;

  @override
  void initState() {
    super.initState();
    _future = Get.find<WorkspaceService>().listProjects();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Projects'),
      content: SizedBox(
        width: 320,
        child: FutureBuilder<List<String>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                  height: 60,
                  child: Center(child: CircularProgressIndicator()));
            }
            final projects = snap.data ?? [];
            if (projects.isEmpty) {
              return const SizedBox(
                height: 80,
                child: Center(child: Text('No projects yet.')),
              );
            }
            return ListView(
              shrinkWrap: true,
              children: [
                for (final p in projects)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.folder),
                    title: Text(p),
                    onTap: () {
                      Get.find<WorkspaceService>().openFolder(p);
                      Get.back();
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
