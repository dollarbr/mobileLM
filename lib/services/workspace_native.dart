import 'package:flutter/services.dart';

const _channel = MethodChannel('com.aichat.ai_chat/workspace');

/// A single entry in a workspace directory listing.
class WorkspaceEntry {
  final String name;
  final bool isDir;
  final int size;
  WorkspaceEntry({
    required this.name,
    required this.isDir,
    this.size = 0,
  });

  factory WorkspaceEntry.fromMap(Map<dynamic, dynamic> map) => WorkspaceEntry(
        name: map['name'] as String? ?? '',
        isDir: map['isDir'] as bool? ?? false,
        size: (map['size'] as num?)?.toInt() ?? 0,
      );
}

/// Opens the native folder picker and returns the granted workspace tree URI
/// (persisted across sessions), or null on cancel.
Future<String?> pickWorkspaceTree() async {
  try {
    return await _channel.invokeMethod<String>('wsPickWorkspace');
  } catch (_) {
    return null;
  }
}

/// Lists the directory at [relPath] under the workspace [treeUri], returning
/// per-entry metadata (name, isDir, size).
Future<List<WorkspaceEntry>> listWorkspaceDir({
  required String treeUri,
  required String relPath,
}) async {
  try {
    final result = await _channel.invokeListMethod<dynamic>(
      'wsListDir',
      {'treeUri': treeUri, 'relPath': relPath},
    );
    final entries = <WorkspaceEntry>[];
    for (final item in result ?? <dynamic>[]) {
      final map = Map<dynamic, dynamic>.from(item as Map);
      entries.add(WorkspaceEntry.fromMap(map));
    }
    return entries;
  } catch (_) {
    return <WorkspaceEntry>[];
  }
}

/// Lists the names of directories directly under the workspace root (projects).
Future<List<String>> listWorkspaceProjects(String treeUri) async {
  final entries = await listWorkspaceDir(treeUri: treeUri, relPath: '');
  return entries.where((e) => e.isDir).map((e) => e.name).toList();
}

/// Creates a folder at [relPath] (parents are created on demand).
Future<bool> mkdir({
  required String treeUri,
  required String relPath,
}) async {
  try {
    await _channel.invokeMethod<String>(
      'wsMkdir',
      {'treeUri': treeUri, 'relPath': relPath},
    );
    return true;
  } catch (_) {
    return false;
  }
}

Future<String?> readFile({
  required String treeUri,
  required String relPath,
}) async {
  try {
    return await _channel.invokeMethod<String>(
      'wsReadFile',
      {'treeUri': treeUri, 'relPath': relPath},
    );
  } catch (_) {
    return null;
  }
}

Future<bool> writeFile({
  required String treeUri,
  required String relPath,
  required String content,
}) async {
  try {
    await _channel.invokeMethod<bool>(
      'wsWriteFile',
      {'treeUri': treeUri, 'relPath': relPath, 'content': content},
    );
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> deleteItem({
  required String treeUri,
  required String relPath,
}) async {
  try {
    final ok = await _channel.invokeMethod<bool>(
      'wsDelete',
      {'treeUri': treeUri, 'relPath': relPath},
    );
    return ok ?? false;
  } catch (_) {
    return false;
  }
}

Future<bool> renameItem({
  required String treeUri,
  required String relPath,
  required String newName,
}) async {
  try {
    await _channel.invokeMethod<String>(
      'wsRename',
      {'treeUri': treeUri, 'relPath': relPath, 'newName': newName},
    );
    return true;
  } catch (_) {
    return false;
  }
}

/// Copies everything under [oldTreeUri] into [newTreeUri]. Returns the number
/// of files moved, or -1 on failure.
Future<int> moveWorkspace({
  required String oldTreeUri,
  required String newTreeUri,
}) async {
  try {
    final moved = await _channel.invokeMethod<int>(
      'wsMoveWorkspace',
      {'oldTreeUri': oldTreeUri, 'newTreeUri': newTreeUri},
    );
    return moved ?? -1;
  } catch (_) {
    return -1;
  }
}

bool get workspaceSupported => true;
