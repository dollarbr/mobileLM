class WorkspaceEntry {
  final String name;
  final bool isDir;
  final int size;
  WorkspaceEntry({
    required this.name,
    required this.isDir,
    this.size = 0,
  });
}

/// Web/non-native stub: no SAF, so the workspace is unavailable. The UI guards
/// on [workspaceSupported] and hides workspace features rather than crash.
Future<String?> pickWorkspaceTree() async => null;
Future<List<WorkspaceEntry>> listWorkspaceDir({
  required String treeUri,
  required String relPath,
}) async =>
    <WorkspaceEntry>[];
Future<List<String>> listWorkspaceProjects(String treeUri) async => <String>[];
Future<bool> mkdir({required String treeUri, required String relPath}) async =>
    false;
Future<String?> readFile({
  required String treeUri,
  required String relPath,
}) async =>
    null;
Future<bool> writeFile({
  required String treeUri,
  required String relPath,
  required String content,
}) async =>
    false;
Future<bool> deleteItem({
  required String treeUri,
  required String relPath,
}) async =>
    false;
Future<bool> renameItem({
  required String treeUri,
  required String relPath,
  required String newName,
}) async =>
    false;
Future<int> moveWorkspace({
  required String oldTreeUri,
  required String newTreeUri,
}) async =>
    -1;
bool get workspaceSupported => false;
