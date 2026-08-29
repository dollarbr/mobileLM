import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/workspace_service.dart';

/// Fullscreen first-launch gate: the user picks the workspace folder once.
/// Shown by [HomeView] whenever [WorkspaceService.needsSetup] is true and the
/// platform supports SAF workspaces.
class WorkspaceSetupView extends StatefulWidget {
  const WorkspaceSetupView({super.key});

  @override
  State<WorkspaceSetupView> createState() => _WorkspaceSetupViewState();
}

class _WorkspaceSetupViewState extends State<WorkspaceSetupView> {
  bool _busy = false;

  Future<void> _choose() async {
    if (_busy) return;
    setState(() => _busy = true);
    final workspace = Get.find<WorkspaceService>();
    final uri = await workspace.pickWorkspace();
    if (uri == null && mounted) {
      // Cancelled — keep the gate visible.
      setState(() => _busy = false);
      Get.snackbar('Workspace', 'No folder chosen yet. Pick one to continue.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFFB9F53E);    return Scaffold(
      backgroundColor:
          Theme.of(context).brightness == Brightness.dark
              ? Colors.black
              : Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.workspaces_outline, size: 72, color: Color(0xFF8B7CFF)),
                const SizedBox(height: 16),
                Text(
                  'Set up your workspace',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'MobileLM organizes your work into projects. Pick a folder '
                  'on this device — each project you start later becomes a '
                  'subfolder inside it, where the app can read, create, edit '
                  'and delete files.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'You can change this folder later in Settings.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).hintColor,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _busy ? null : _choose,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                  ),
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.create_new_folder_outlined),
                  label: Text(_busy ? 'Opening picker…' : 'Choose workspace folder'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
