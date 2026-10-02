import 'package:get/get.dart';

import 'workspace_paths.dart';
import '../core/constants.dart';
import '../services/hive_service.dart';
import 'workspace_native.dart'
    if (dart.library.html) 'workspace_stub.dart' as ws;

/// Holds the workspace root (a persisted SAF tree URI) plus the folder the UI
/// is currently showing relative to that root, and a snapshot of its contents.
///
/// All file operations go through the native channel so the app can reach
/// folders outside its own sandbox (materialized through scoped storage). A
/// project is simply a folder directly under the workspace root, referenced by
/// its clean name in [ChatSession.projectPath].
class WorkspaceService extends GetxService {
  /// Persisted SAF tree URI for the workspace root.
  final treeUri = Rxn<String>();

  /// Folder being displayed, relative to [treeUri.parent]. Empty = the root.
  final currentRelPath = ''.obs;

  /// Contents of [currentRelPath] (folders and files interleaved).
  final entries = <ws.WorkspaceEntry>[].obs;

  final isLoading = false.obs;

  /// True before the user has picked a workspace folder (first launch).
  final needsSetup = false.obs;

  /// The last project the user **chose**, kept across a cold start.
  ///
  /// **Separate from [currentRelPath] on purpose.** The tab's position and
  /// "where this user works" are different questions: opening an old chat moves
  /// the tab to whatever that chat was bound to, and browsing into a subfolder
  /// moves it deeper, and neither is a decision about the default. Only the
  /// project picker is.
  ///
  /// Null means *nothing remembered yet* — a fresh install, which is the one
  /// case where asking is right. Choosing "No project" deliberately does **not**
  /// clear it: that choice was about one conversation, and the next one still
  /// lands in the workspace the user works in. The app bar chip changes it.
  final rememberedProject = Rxn<String>();

  /// A remembered project that was dropped because its folder disappeared.
  /// Read by the UI to say so, rather than silently asking again.
  final droppedProject = Rxn<String>();

  late final HiveService _hive;

  @override
  void onInit() {
    super.onInit();
    _hive = Get.find<HiveService>();
  }

  bool get isReady => treeUri.value != null && treeUri.value!.isNotEmpty;
  bool get isRoot => currentRelPath.value.isEmpty;
  bool get supported => ws.workspaceSupported;

  /// Load the persisted URI on startup, refresh the root listing, and bring
  /// back the last chosen project.
  ///
  /// The restore is inside here because it needs the root listing to validate
  /// against, and this is the one place that already has it at boot.
  Future<void> initialize() async {
    final saved = _hive.getSetting<String>(AppConstants.keyWorkspaceTreeUri);
    if (saved == null || saved.isEmpty) {
      needsSetup.value = true;
      return;
    }
    treeUri.value = saved;
    await refresh();
    await restoreRememberedProject();
  }

  /// Bring back the last chosen project, if it still exists.
  ///
  /// **Validated against the live listing, because the folder can be deleted
  /// outside the app** — in a file manager, by the user, by anything holding the
  /// SAF grant. A remembered name that no longer exists would bind every new
  /// chat to a folder whose file tools cannot reach, and it would do it silently
  /// and repeatedly.
  Future<void> restoreRememberedProject() async {
    final gone = <String>[];
    final resolved = resolveRememberedProject(
      _hive.getSetting<String>(AppConstants.keyLastProjectName),
      await listProjects(),
      onDropped: gone.add,
    );
    rememberedProject.value = resolved;
    droppedProject.value = gone.isEmpty ? null : gone.first;
    if (resolved != null) await openProject(resolved);
  }

  /// Remember [name] as the project new conversations start in.
  ///
  /// Called from the project picker only, and **not** from `openChat`: opening a
  /// conversation is not choosing a workspace, and letting it overwrite the
  /// default would mean reviewing an old chat quietly moves the default.
  Future<void> rememberProject(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    rememberedProject.value = trimmed;
    await _hive.setSetting(AppConstants.keyLastProjectName, trimmed);
  }

  /// The absolute-ish path of the currently displayed folder, for display only.
  String get displayPath => currentRelPath.value.isEmpty
      ? '/'
      : '/${currentRelPath.value}';

  /// Joins a child name onto the current relative path.
  String childRelPath(String name) => currentRelPath.value.isEmpty
      ? name
      : '${currentRelPath.value}/$name';

  Future<void> refresh() async {
    if (!isReady) return;
    isLoading.value = true;
    entries.value = await ws.listWorkspaceDir(
      treeUri: treeUri.value!,
      relPath: currentRelPath.value,
    );
    isLoading.value = false;
  }

  /// Open a folder (its name relative to the current folder).
  ///
  /// **Refuses to descend into a folder that repeats the current one's name.**
  /// The path used to be composed by [childRelPath] out of a listing that
  /// carries only a name, so tapping the same folder repeatedly produced
  /// `TESTES/TESTES/TESTES` with no limit and no complaint. See
  /// `workspace_paths.dart` for why the guard is here rather than a change to
  /// the native listing. `A/A/B/A` is still reachable; only the immediate
  /// re-entry is refused, and refusing it means *not moving*, not an error.
  Future<void> openFolder(String name) async {
    final next = navigateInto(currentRelPath.value, name);
    if (next == currentRelPath.value) {
      // Already here. Re-listing is still worth it — the tap may have followed
      // a rename elsewhere — and it is what makes the refusal invisible.
      await refresh();
      return;
    }
    currentRelPath.value = next;
    await refresh();
  }

  Future<void> navigateUp() async {
    final parts = currentRelPath.value.split('/')
      ..removeWhere((s) => s.isEmpty);
    if (parts.isEmpty) return;
    parts.removeLast();
    currentRelPath.value = parts.join('/');
    await refresh();
  }

  /// Return to the workspace root (the projects list).
  Future<void> goRoot() async {
    if (currentRelPath.value.isEmpty) return;
    currentRelPath.value = '';
    await refresh();
  }

  /// Jump to a project folder (by name) — its path relative to the root.
  Future<void> openProject(String name) async {
    currentRelPath.value = name;
    await refresh();
  }

  /// List an arbitrary folder (path relative to the workspace root) without
  /// moving the UI's current folder. Used by the agent file tools.
  Future<List<ws.WorkspaceEntry>> listDir(String relPath) async {
    if (!isReady) return [];
    return ws.listWorkspaceDir(
      treeUri: treeUri.value!,
      relPath: relPath,
    );
  }

  Future<List<String>> listProjects() async {
    if (!isReady) return [];
    return ws.listWorkspaceProjects(treeUri.value!);
  }

  Future<bool> createFolder(String name) async {
    if (name.trim().isEmpty) return false;
    final ok = await ws.mkdir(
      treeUri: treeUri.value!,
      relPath: childRelPath(name.trim()),
    );
    if (ok) await refresh();
    return ok;
  }

  /// Create a project folder directly under the workspace root, regardless of
  /// where the Workspace UI currently is. Returns false when it already exists.
  Future<bool> createProject(String name) async {
    if (name.trim().isEmpty) return false;
    return ws.mkdir(
      treeUri: treeUri.value!,
      relPath: name.trim(),
    );
  }

  Future<bool> createFile(String name, {String content = ''}) async {
    if (name.trim().isEmpty) return false;
    final err = await ws.writeFile(
      treeUri: treeUri.value!,
      relPath: childRelPath(name.trim()),
      content: content,
    );
    if (err == null) await refresh();
    return err == null;
  }

  Future<String?> readFile(String relPath) =>
      ws.readFile(treeUri: treeUri.value!, relPath: relPath);

  Future<String?> writeFile(String relPath, String content) =>
      ws.writeFile(treeUri: treeUri.value!, relPath: relPath, content: content);

  Future<bool> deleteItem(String relPath) async {
    final ok = await ws.deleteItem(treeUri: treeUri.value!, relPath: relPath);
    if (ok) await refresh();
    return ok;
  }

  Future<bool> renameItem(String relPath, String newName) async {
    final ok = await ws.renameItem(
      treeUri: treeUri.value!,
      relPath: relPath,
      newName: newName,
    );
    if (ok) await refresh();
    return ok;
  }

  /// Pick a workspace folder (native SAF). Returns the URI or null on cancel.
  Future<String?> pickWorkspace() async {
    if (!ws.workspaceSupported) return null;
    final uri = await ws.pickWorkspaceTree();
    if (uri != null) {
      await _save(uri);
    }
    return uri;
  }

  /// Relocate the whole workspace: copy everything under the old root into the
  /// new one, then switch the persisted URI. Returns true on success.
  Future<bool> relocateWorkspace() async {
    final oldUri = treeUri.value;
    if (oldUri == null) return false;
    final newUri = await ws.pickWorkspaceTree();
    if (newUri == null || newUri == oldUri) return false;
    final moved = await ws.moveWorkspace(
      oldTreeUri: oldUri,
      newTreeUri: newUri,
    );
    if (moved < 0) return false;
    await _save(newUri);
    return true;
  }

  Future<void> _save(String uri) async {
    treeUri.value = uri;
    needsSetup.value = false;
    currentRelPath.value = '';
    await _hive.setSetting(AppConstants.keyWorkspaceTreeUri, uri);
    await refresh();
  }
}
