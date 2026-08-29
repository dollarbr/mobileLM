import 'package:get/get.dart';

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

  late final HiveService _hive;

  @override
  void onInit() {
    super.onInit();
    _hive = Get.find<HiveService>();
  }

  bool get isReady => treeUri.value != null && treeUri.value!.isNotEmpty;
  bool get isRoot => currentRelPath.value.isEmpty;
  bool get supported => ws.workspaceSupported;

  /// Load the persisted URI on startup and refresh the root listing.
  Future<void> initialize() async {
    final saved = _hive.getSetting<String>(AppConstants.keyWorkspaceTreeUri);
    if (saved != null && saved.isNotEmpty) {
      treeUri.value = saved;
      await refresh();
    } else {
      needsSetup.value = true;
    }
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
  Future<void> openFolder(String name) async {
    currentRelPath.value = childRelPath(name);
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
