/// Pure path rules for the workspace.
///
/// Separate from `workspace_service.dart` because the two things that can go
/// wrong here are both decisions, and both went wrong silently.
///
/// ## The unbounded path
///
/// `openFolder` used to compose a path out of the current folder and a name
/// taken from a listing that carries **only a name** — `WorkspaceEntry` has
/// `name`, `isDir` and `size`, and no path. So navigating was
/// `childRelPath(name)`: relative, recomposed each time from wherever the UI
/// happened to be. Tapping a folder that shares its parent's name produced
/// `TESTES/TESTES`, and tapping the row again produced `TESTES/TESTES/TESTES`,
/// with no limit and no complaint. It read as the app forgetting where it was,
/// because the path it was showing was one it had built itself.
///
/// The fix is not the architecture that would prevent it — that is the native
/// listing returning each entry's path from the root, which touches
/// `wsListDir`, the web stub and four call sites. The fix here is a rule that
/// makes the growth impossible, because the reported symptom is the growth and
/// a guard is where the invariant belongs: **a folder may never be entered from
/// a parent that already has its name.** `A/A/B/A` is still perfectly legal and
/// reachable; only the immediate re-entry is refused.
///
/// ## What is deliberately not here
///
/// No path sanitising, no `..` handling, no separator escaping. Every name comes
/// from a SAF listing or from `createFolder`, and SAF does not produce a name
/// containing `/` — so there is no way to build a path here that does not
/// correspond to real nested folders. Writing checks for inputs the platform
/// cannot generate is how a service ends up looking defended while nothing is.
library;

/// Descend into [name] from [currentRelPath].
///
/// Returns the new path relative to the workspace root, or **[currentRelPath]
/// unchanged** when the descent would repeat the parent's own name.
///
/// The unchanged return is the whole point: it makes `TESTES` → `TESTES/TESTES`
/// impossible, and because the parent still ends in `TESTES` the next tap is
/// refused too, so the path cannot grow. A refusal is not a silent no-op — it
/// returns the current path, which the caller can compare, and it is the same
/// path it already had, so the listing does not even need to change.
String navigateInto(String currentRelPath, String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return currentRelPath;
  if (trimmed.contains('/')) {
    // Not reachable from a SAF listing, and if it ever were, treating the whole
    // thing as one segment would silently open a different folder than asked.
    return currentRelPath;
  }
  final parent = currentRelPath;
  final parentName = parent.split('/').lastWhere((s) => s.isNotEmpty, orElse: () => '');
  if (parentName == trimmed) return parent;
  return parent.isEmpty ? trimmed : '$parent/$trimmed';
}

/// The project to remember, or `null` when none should be.
///
/// [persisted] is what was written last time and [existing] is what the
/// workspace root actually contains right now. **The folder can be deleted
/// outside the app** — in a file manager, by the user, by anything holding the
/// SAF grant — and a remembered name that no longer exists would bind every new
/// chat to a folder whose file tools cannot reach. So the name is checked
/// against the live listing and dropped if it is gone.
///
/// Dropping it is not a silent lie: [onDropped] reports it, so the app can say
/// the project is gone instead of quietly asking the user to pick again.
String? resolveRememberedProject(
  String? persisted,
  List<String> existing, {
  void Function(String gone)? onDropped,
}) {
  if (persisted == null || persisted.isEmpty) return null;
  if (existing.contains(persisted)) return persisted;
  onDropped?.call(persisted);
  return null;
}
