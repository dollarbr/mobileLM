import 'privileged_commands.dart';
import 'tool_registry.dart';

/// The privileged block: five reads plus settings and permission writes.
///
/// [run] is injected rather than reached for, mirroring `buildFileTools`, so
/// every behaviour here is testable without a device or a live Shizuku binder.
///
/// App management (install, uninstall, freeze, clear data) and screen
/// automation (input, screencap, am start) are deliberately out of this
/// version — see docs/superpowers/specs/2026-09-05-adb-shizuku-tools-design.md.
List<Tool> buildPrivilegedTools({
  required Future<String> Function(List<String> argv) run,
}) {
  /// Builds argv, runs it, caps the result. An [ArgError] becomes a normal
  /// error result: the model can then say what was wrong, which beats the turn
  /// dying — and nothing reaches the shell.
  Future<String> exec(List<String> Function() build) async {
    final List<String> argv;
    try {
      argv = build();
    } on ArgError catch (e) {
      return e.message;
    }
    return capOutput(await run(argv));
  }

  String show(List<String> Function() build) {
    try {
      return build().join(' ');
    } on ArgError catch (e) {
      return e.message;
    }
  }

  Tool privileged({
    required String name,
    required String description,
    Map<String, String> parameters = const {},
    required List<String> Function(Map<String, String> a) argv,
  }) =>
      Tool(
        name: name,
        description: description,
        parameters: parameters,
        risk: ToolRisk.privileged,
        preview: (a) => show(() => argv(a)),
        run: (a) => exec(() => argv(a)),
      );

  int lineCount(Map<String, String> a) =>
      int.tryParse(a['lines']?.trim() ?? '') ?? 100;

  return [
    privileged(
      name: 'list_apps',
      description: 'Packages installed on this device.',
      parameters: {
        'only': 'all, user or system (default all)',
        'filter': 'optional substring to match',
      },
      argv: (a) => listAppsArgv(
        only: (a['only']?.trim().isEmpty ?? true) ? 'all' : a['only']!.trim(),
        filter: a['filter'] ?? '',
      ),
    ),
    privileged(
      name: 'app_info',
      description: 'Version, install dates and permissions of one package.',
      parameters: {'package': 'the package name, e.g. com.foo.bar'},
      argv: (a) => appInfoArgv(a['package'] ?? ''),
    ),
    privileged(
      name: 'get_logcat',
      description: 'Recent system log lines.',
      parameters: {
        'lines': 'how many lines, up to 500 (default 100)',
        'tag': 'optional log tag to filter by',
        'priority': 'optional V, D, I, W, E or F',
      },
      argv: (a) => logcatArgv(
        lines: lineCount(a),
        tag: a['tag'] ?? '',
        priority: a['priority'] ?? '',
      ),
    ),
    privileged(
      name: 'read_system_prop',
      description: 'Value of an Android system property.',
      parameters: {'key': 'the property, e.g. ro.build.version.release'},
      argv: (a) => getPropArgv(a['key'] ?? ''),
    ),
    privileged(
      name: 'read_setting',
      description: 'Value of a protected Android setting.',
      parameters: {
        'namespace': 'system, secure or global',
        'key': 'the setting key',
      },
      argv: (a) => readSettingArgv(a['namespace'] ?? '', a['key'] ?? ''),
    ),
    privileged(
      name: 'set_setting',
      description: 'Change a protected Android setting.',
      parameters: {
        'namespace': 'system, secure or global',
        'key': 'the setting key',
        'value': 'the new value',
      },
      argv: (a) => writeSettingArgv(
          a['namespace'] ?? '', a['key'] ?? '', a['value'] ?? ''),
    ),
    privileged(
      name: 'grant_permission',
      description: 'Grant a runtime permission to an app.',
      parameters: {
        'package': 'the package name',
        'permission': 'e.g. android.permission.CAMERA',
      },
      argv: (a) => grantArgv(a['package'] ?? '', a['permission'] ?? ''),
    ),
    privileged(
      name: 'revoke_permission',
      description: 'Revoke a runtime permission from an app.',
      parameters: {
        'package': 'the package name',
        'permission': 'e.g. android.permission.CAMERA',
      },
      argv: (a) => revokeArgv(a['package'] ?? '', a['permission'] ?? ''),
    ),
  ];
}
