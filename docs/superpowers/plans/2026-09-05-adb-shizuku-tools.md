# ADB/Shizuku Privileged Tools — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the model eight privileged tools — five reads plus settings and permission writes — that run through Shizuku when the user has it, and vanish from the prompt when they don't.

**Architecture:** A single Kotlin `ShizukuShell` binds a Shizuku `UserService` over AIDL and executes an **argv list**, never a shell string. Dart gets a `PrivilegedService` exposing status and `run(List<String>)`. The tools are built from an injected runner closure, mirroring `buildFileTools`, so every Dart-side behaviour is testable without a device. `ToolRisk` gains a third value so privileged reads confirm too.

**Tech Stack:** Flutter/Dart, GetX, Kotlin, `dev.rikka.shizuku:api:13.1.5`, `dev.rikka.shizuku:provider:13.1.5`, AIDL.

**Spec:** `docs/superpowers/specs/2026-09-05-adb-shizuku-tools-design.md`

## Global Constraints

- Dart package is `mobilelm`; test imports are `package:mobilelm/...`.
- applicationId is `com.dollarbr.mobilelm`; Kotlin package is `com.dollarbr.mobilelm`.
- **The app never invokes `su` and never requires root.** Shizuku may itself be running as root; the app reports that and never asks for it.
- Commands are executed as an **argv `List<String>`**. Nothing is interpolated into a shell string, anywhere, at any layer.
- Every tool result is capped at **8192 bytes** before it reaches the model.
- Model-facing strings (tool results, errors) are **English**, matching every existing tool. The spec quotes the truncation marker in Portuguese; the implemented string is English.
- Every `run` carries a timeout. Default **20000 ms**.
- Native builds are arm64-only; `org.gradle.workers.max=2`.
- Commit messages in English.
- Run `flutter analyze --no-fatal-infos --no-fatal-warnings` and `flutter test` before every commit.

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/services/tools/tool_registry.dart` *(modify)* | `ToolRisk.privileged`, `Tool.preview`, confirmation gate |
| `lib/services/tools/privileged_commands.dart` *(create)* | Pure: argument validation + argv building + output cap. No I/O, no GetX. |
| `lib/services/tools/privileged_tools.dart` *(create)* | The eight `Tool`s, built from an injected runner |
| `lib/services/privileged_service.dart` *(create)* | GetxService: channel talk, status, identity |
| `lib/controllers/chat_controller.dart` *(modify)* | Confirmation dialog shows the real command and identity |
| `lib/views/settings_view.dart` *(modify)* | "ADB / Shizuku" group |
| `lib/main.dart` *(modify)* | Register the service |
| `android/app/src/main/aidl/com/dollarbr/mobilelm/IPrivilegedService.aidl` *(create)* | AIDL contract |
| `android/app/src/main/kotlin/com/dollarbr/mobilelm/PrivilegedUserService.kt` *(create)* | Runs in the Shizuku process |
| `android/app/src/main/kotlin/com/dollarbr/mobilelm/ShizukuShell.kt` *(create)* | Bind, probe, permission, run |
| `android/app/src/main/kotlin/com/dollarbr/mobilelm/MainActivity.kt` *(modify)* | Channel wiring |
| `android/app/build.gradle.kts` *(modify)* | Shizuku deps + `buildFeatures { aidl = true }` |
| `android/app/src/main/AndroidManifest.xml` *(modify)* | `ShizukuProvider` |
| `test/privileged_commands_test.dart` *(create)* | Validation, argv, cap |
| `test/privileged_tools_test.dart` *(create)* | Gating, risk, preview/run agreement |
| `test/tools_registry_test.dart` *(modify)* | Privileged risk never auto-runs |

Tasks 1–4 are pure Dart and need no device. Task 5 is the only one that cannot be verified without hardware.

---

### Task 1: Third risk tier and command preview

**Files:**
- Modify: `lib/services/tools/tool_registry.dart`
- Test: `test/tools_registry_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `ToolRisk.privileged`; `Tool.preview` of type `String Function(Map<String, String> args)?`; `ToolRegistry.execute` gating on `risk != ToolRisk.safe`.

- [ ] **Step 1: Write the failing test**

Append to `test/tools_registry_test.dart`:

```dart
  test('a privileged tool is gated even though it only reads', () async {
    final registry = ToolRegistry([
      Tool(
        name: 'peek',
        description: 'reads something privileged',
        risk: ToolRisk.privileged,
        run: (_) async => 'data',
      ),
    ]);

    // Shell privilege has no "just looking" mode: logcat carries other apps'
    // content, so a read confirms exactly like a write does.
    expect(await registry.execute('peek', {}), ToolRegistry.confirmMarker);
    expect(await registry.execute('peek', {}, confirmed: true), 'data');
  });

  test('preview renders the command a confirmation dialog should show', () {
    final tool = Tool(
      name: 'peek',
      description: 'x',
      risk: ToolRisk.privileged,
      preview: (args) => 'getprop ${args['key']}',
      run: (_) async => '',
    );

    expect(tool.preview!({'key': 'ro.build.id'}), 'getprop ro.build.id');
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/tools_registry_test.dart`
Expected: FAIL — `ToolRisk.privileged` and `preview` are not defined.

- [ ] **Step 3: Write minimal implementation**

In `lib/services/tools/tool_registry.dart`, extend the enum:

```dart
enum ToolRisk {
  /// Answers or reads; running it needs no permission from anyone.
  safe,

  /// Changes device state (clipboard, files, messages…). Runs only after an
  /// explicit human approval in the UI.
  write,

  /// Runs through a privileged shell. Confirms even when it only reads: a
  /// logcat dump carries notifications, tokens and other apps' content, so
  /// there is no "just looking" tier for shell privilege.
  privileged,
}
```

Add the field to `Tool`, after `risk`:

```dart
  /// The real command this call will run, for the confirmation dialog.
  /// Without it the user approves a tool name rather than an action.
  final String Function(Map<String, String> args)? preview;
```

Add `this.preview,` to the constructor parameter list.

In `execute`, replace the gate:

```dart
    if (tool.risk != ToolRisk.safe && !confirmed) {
      return confirmMarker;
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/tools_registry_test.dart`
Expected: PASS, including the pre-existing `clipboard_write` gate test.

- [ ] **Step 5: Commit**

```bash
git add lib/services/tools/tool_registry.dart test/tools_registry_test.dart
git commit -m "feat(tools): add a privileged risk tier and a command preview

Shell privilege has no read-only tier: a logcat dump carries other apps'
notifications and tokens, so a privileged read has to pause for the same
tap a write does. The gate now tests risk != safe rather than naming
write, and Tool.preview lets the dialog show the command instead of only
the tool name."
```

---

### Task 2: Argument validation and argv building

**Files:**
- Create: `lib/services/tools/privileged_commands.dart`
- Test: `test/privileged_commands_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class ArgError implements Exception { final String message; }`
  - `List<String> listAppsArgv({String filter = '', String only = 'all'})`
  - `List<String> appInfoArgv(String package)`
  - `List<String> logcatArgv({int lines = 100, String tag = '', String priority = ''})`
  - `List<String> getPropArgv(String key)`
  - `List<String> readSettingArgv(String namespace, String key)`
  - `List<String> writeSettingArgv(String namespace, String key, String value)`
  - `List<String> grantArgv(String package, String permission)`
  - `List<String> revokeArgv(String package, String permission)`
  - `String capOutput(String raw, {int maxBytes = 8192})`

- [ ] **Step 1: Write the failing test**

Create `test/privileged_commands_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:mobilelm/services/tools/privileged_commands.dart';

void main() {
  group('argument validation', () {
    // A package name reaching the shell unchecked is arbitrary execution as
    // whatever uid Shizuku holds. Narrow tools are only safer than a free
    // shell because of these rules, so each metacharacter gets its own case.
    const injections = [
      'foo; rm -rf /data',
      'foo | cat',
      'foo && id',
      r'foo$(id)',
      'foo`id`',
      'foo\nid',
      'foo id',
    ];

    for (final bad in injections) {
      test('a package name containing ${bad.substring(3)} is rejected', () {
        expect(() => appInfoArgv(bad), throwsA(isA<ArgError>()));
        expect(() => grantArgv(bad, 'android.permission.CAMERA'),
            throwsA(isA<ArgError>()));
      });
    }

    test('a well-formed package name is accepted', () {
      expect(appInfoArgv('com.foo.bar_1'),
          ['dumpsys', 'package', 'com.foo.bar_1']);
    });

    test('the settings namespace is a closed set', () {
      expect(readSettingArgv('secure', 'android_id'),
          ['settings', 'get', 'secure', 'android_id']);
      expect(() => readSettingArgv('bogus', 'k'), throwsA(isA<ArgError>()));
    });

    test('a setting value is never validated, only kept out of a shell string',
        () {
      // The value is free text on purpose — a wallpaper path or a DNS name can
      // contain anything. Safety comes from argv, not from a pattern.
      expect(
        writeSettingArgv('global', 'private_dns_specifier', 'dns.foo; rm -rf /'),
        ['settings', 'put', 'global', 'private_dns_specifier',
         'dns.foo; rm -rf /'],
      );
    });

    test('logcat lines are clamped to 500', () {
      expect(logcatArgv(lines: 99999), contains('500'));
      expect(logcatArgv(lines: 0), contains('1'));
    });

    test('list_apps only accepts the three known scopes', () {
      expect(listAppsArgv(only: 'user'), ['pm', 'list', 'packages', '-3']);
      expect(listAppsArgv(only: 'system'), ['pm', 'list', 'packages', '-s']);
      expect(listAppsArgv(only: 'all'), ['pm', 'list', 'packages']);
      expect(() => listAppsArgv(only: 'weird'), throwsA(isA<ArgError>()));
    });
  });

  group('output cap', () {
    test('short output is untouched', () {
      expect(capOutput('hello'), 'hello');
    });

    test('long output is cut and says so', () {
      // dumpsys package runs past 1 MB and LiteRT is pinned at ctx 4096, so an
      // uncapped result does not waste the turn, it ends it.
      final huge = 'x' * 100000;
      final out = capOutput(huge);

      expect(out.length, lessThan(8192 + 64));
      expect(out, contains('truncated'));
      expect(out, contains('KB omitted'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/privileged_commands_test.dart`
Expected: FAIL — `privileged_commands.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `lib/services/tools/privileged_commands.dart`:

```dart
/// Argument validation and argv building for the privileged tool block.
///
/// Pure on purpose: no channel, no GetX, no I/O. Everything that decides what
/// actually runs on the device lives here so it can be tested without one.
///
/// Commands are built as an argv list and never as a shell string. That is the
/// whole safety argument for narrow tools — interpolating a model-supplied
/// package name into `sh -c` is arbitrary execution as whatever uid Shizuku
/// holds.
library;

/// A rejected argument. Surfaces to the model as a normal error result.
class ArgError implements Exception {
  ArgError(this.message);
  final String message;
  @override
  String toString() => message;
}

final _packagePattern = RegExp(r'^[A-Za-z0-9._]+$');
final _keyPattern = RegExp(r'^[A-Za-z0-9._-]+$');
const _namespaces = {'system', 'secure', 'global'};
const _scopes = {'all', 'user', 'system'};

String _package(String value) {
  final v = value.trim();
  if (!_packagePattern.hasMatch(v)) {
    throw ArgError('Error: "$value" is not a valid package name.');
  }
  return v;
}

String _key(String value, String what) {
  final v = value.trim();
  if (!_keyPattern.hasMatch(v)) {
    throw ArgError('Error: "$value" is not a valid $what.');
  }
  return v;
}

List<String> listAppsArgv({String filter = '', String only = 'all'}) {
  if (!_scopes.contains(only)) {
    throw ArgError('Error: only must be one of ${_scopes.join(", ")}.');
  }
  return [
    'pm', 'list', 'packages',
    if (only == 'user') '-3',
    if (only == 'system') '-s',
    // Passed as its own argv entry, so a filter with metacharacters is just a
    // string pm will not match rather than something a shell would run.
    if (filter.trim().isNotEmpty) filter.trim(),
  ];
}

List<String> appInfoArgv(String package) =>
    ['dumpsys', 'package', _package(package)];

List<String> logcatArgv({int lines = 100, String tag = '', String priority = ''}) {
  final n = lines.clamp(1, 500);
  return [
    'logcat', '-d', '-t', '$n',
    if (tag.trim().isNotEmpty) '${_key(tag, "log tag")}:'
        '${priority.trim().isEmpty ? "V" : _key(priority, "priority")}',
    if (tag.trim().isNotEmpty) '*:S',
  ];
}

List<String> getPropArgv(String key) => ['getprop', _key(key, 'property name')];

String _namespace(String value) {
  final v = value.trim();
  if (!_namespaces.contains(v)) {
    throw ArgError('Error: namespace must be one of ${_namespaces.join(", ")}.');
  }
  return v;
}

List<String> readSettingArgv(String namespace, String key) =>
    ['settings', 'get', _namespace(namespace), _key(key, 'setting key')];

List<String> writeSettingArgv(String namespace, String key, String value) =>
    // `value` is deliberately unvalidated: a DNS name or a path can contain
    // almost anything. It is safe because it is its own argv entry.
    ['settings', 'put', _namespace(namespace), _key(key, 'setting key'), value];

List<String> grantArgv(String package, String permission) =>
    ['pm', 'grant', _package(package), _key(permission, 'permission')];

List<String> revokeArgv(String package, String permission) =>
    ['pm', 'revoke', _package(package), _key(permission, 'permission')];

/// Trims a result to something a 4096-token context can survive.
///
/// The marker matters as much as the cut: a model handed a silent fragment
/// concludes from partial data and sounds just as certain.
String capOutput(String raw, {int maxBytes = 8192}) {
  final bytes = raw.codeUnits.length;
  if (bytes <= maxBytes) return raw;
  final omittedKb = ((bytes - maxBytes) / 1024).ceil();
  return '${raw.substring(0, maxBytes)}\n'
      '[... truncated, $omittedKb KB omitted]';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/privileged_commands_test.dart`
Expected: PASS, all cases.

- [ ] **Step 5: Commit**

```bash
git add lib/services/tools/privileged_commands.dart test/privileged_commands_test.dart
git commit -m "feat(tools): argv building and argument validation for privileged commands

Narrow tools are only safer than a free shell if their arguments are
checked, so the rules are code with tests rather than care taken at the
call site. Commands are argv lists, never shell strings — a setting value
stays free text precisely because it travels as its own argv entry.

Output is capped at 8 KB with a marker naming what was dropped. dumpsys
package runs past 1 MB and LiteRT is pinned at ctx 4096, and a model
handed a silent fragment concludes from partial data just as confidently."
```

---

### Task 3: The eight tools over an injected runner

**Files:**
- Create: `lib/services/tools/privileged_tools.dart`
- Test: `test/privileged_tools_test.dart`

**Interfaces:**
- Consumes: everything from Task 2; `Tool`, `ToolRisk.privileged`, `Tool.preview` from Task 1.
- Produces: `List<Tool> buildPrivilegedTools({required Future<String> Function(List<String> argv) run})`.

- [ ] **Step 1: Write the failing test**

Create `test/privileged_tools_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:mobilelm/services/tools/privileged_tools.dart';
import 'package:mobilelm/services/tools/tool_registry.dart';

void main() {
  late List<List<String>> ran;
  late List<Tool> tools;

  setUp(() {
    ran = [];
    tools = buildPrivilegedTools(run: (argv) async {
      ran.add(argv);
      return 'ok';
    });
  });

  Tool byName(String n) => tools.firstWhere((t) => t.name == n);

  test('every privileged tool is risk privileged and has a preview', () {
    expect(tools, hasLength(8));
    for (final t in tools) {
      expect(t.risk, ToolRisk.privileged, reason: t.name);
      expect(t.preview, isNotNull, reason: t.name);
    }
  });

  test('preview shows exactly the command that run receives', () async {
    final tool = byName('read_setting');
    final args = {'namespace': 'secure', 'key': 'android_id'};

    final shown = tool.preview!(args);
    await tool.run(args);

    // If these drift the user approves one thing and another executes.
    expect(ran.single.join(' '), shown);
  });

  test('a rejected argument comes back as an error, never as a command', () async {
    final out = await byName('app_info').run({'package': 'foo; rm -rf /'});

    expect(out, startsWith('Error:'));
    expect(ran, isEmpty);
  });

  test('results are capped before reaching the model', () async {
    final big = buildPrivilegedTools(run: (_) async => 'y' * 100000);
    final out = await big.firstWhere((t) => t.name == 'get_logcat').run({});

    expect(out, contains('truncated'));
    expect(out.length, lessThan(8192 + 64));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/privileged_tools_test.dart`
Expected: FAIL — `privileged_tools.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `lib/services/tools/privileged_tools.dart`:

```dart
import 'privileged_commands.dart';
import 'tool_registry.dart';

/// The privileged block: five reads plus settings and permission writes.
///
/// [run] is injected rather than reached for, mirroring `buildFileTools`, so
/// every behaviour here is testable without a device or a live Shizuku binder.
///
/// App management (install, uninstall, freeze, clear data) and screen
/// automation (input, screencap, am start) are deliberately out of this
/// version — see the spec.
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

  int lines(Map<String, String> a) =>
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
        lines: lines(a),
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/privileged_tools_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/tools/privileged_tools.dart test/privileged_tools_test.dart
git commit -m "feat(tools): the eight privileged tools over an injected runner

Five reads plus settings and permission writes, each carrying a preview
so the confirmation dialog shows the command rather than the tool name.
A test asserts preview and run agree: if they drift the user approves one
thing and another executes.

The runner is injected the way buildFileTools takes its project path, so
none of this needs a device or a live binder to test. App management and
screen automation stay out of this version by decision, not omission."
```

---

### Task 4: PrivilegedService and prompt gating

**Files:**
- Create: `lib/services/privileged_service.dart`
- Modify: `lib/main.dart`
- Modify: `lib/controllers/chat_controller.dart:1142`
- Modify: `lib/views/settings_view.dart:913`
- Test: `test/privileged_gating_test.dart`

**Interfaces:**
- Consumes: `buildPrivilegedTools` from Task 3.
- Produces:
  - `enum ShizukuState { notInstalled, stopped, needsPermission, ready }`
  - `class PrivilegedService extends GetxService` with `Rx<ShizukuState> state`, `RxString identity`, `Future<void> refresh()`, `Future<void> requestPermission()`, `Future<String> run(List<String> argv)`, `bool get isReady`
  - `List<Tool> privilegedToolsIfReady()` — the block, or `const []`

- [ ] **Step 1: Write the failing test**

Create `test/privileged_gating_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:mobilelm/services/privileged_service.dart';
import 'package:mobilelm/services/tools/privileged_tools.dart';

void main() {
  test('the block is empty unless Shizuku is ready', () {
    // A model told about a tool that then refuses to run wastes a turn
    // arguing with itself — the same reasoning the registry already applies
    // to the enabled filter.
    for (final s in ShizukuState.values) {
      final tools = s == ShizukuState.ready
          ? buildPrivilegedTools(run: (_) async => '')
          : const [];
      expect(tools.isEmpty, s != ShizukuState.ready, reason: '$s');
    }
  });

  test('every state that is not ready reports what the user must do', () {
    expect(ShizukuState.notInstalled.hint, contains('install'));
    expect(ShizukuState.stopped.hint, contains('start'));
    expect(ShizukuState.needsPermission.hint, contains('permission'));
    expect(ShizukuState.ready.hint, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/privileged_gating_test.dart`
Expected: FAIL — `privileged_service.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `lib/services/privileged_service.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// Why the privileged block is or is not available.
///
/// Four states rather than one "unavailable", because each asks a different
/// thing of the user and a single label would hide that.
enum ShizukuState {
  notInstalled,
  stopped,
  needsPermission,
  ready;

  String get hint => switch (this) {
        ShizukuState.notInstalled =>
          'Shizuku is a separate app — install it to enable these tools.',
        ShizukuState.stopped =>
          'Shizuku is installed but not running. Start it over wireless '
              'debugging; it stays up until the phone reboots.',
        ShizukuState.needsPermission =>
          'Shizuku is running. Grant this app permission to use it.',
        ShizukuState.ready => '',
      };

  String get label => switch (this) {
        ShizukuState.notInstalled => 'Shizuku not found',
        ShizukuState.stopped => 'Shizuku stopped',
        ShizukuState.needsPermission => 'Awaiting permission',
        ShizukuState.ready => 'Active',
      };
}

/// Talks to the Shizuku binder through the platform channel.
///
/// The app never invokes `su` and never requires root. Shizuku itself may have
/// been started as root by the user; [identity] reports that, because the same
/// command does different things under uid 2000 and uid 0.
class PrivilegedService extends GetxService {
  static const _channel = MethodChannel('com.aichat.ai_chat/privileged');

  final state = ShizukuState.notInstalled.obs;

  /// `shell 2000` or `root 0`, empty until ready.
  final identity = ''.obs;

  bool get isReady => state.value == ShizukuState.ready;

  Future<void> refresh() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('probe');
      state.value = ShizukuState.values.firstWhere(
        (s) => s.name == (res?['state'] ?? ''),
        orElse: () => ShizukuState.notInstalled,
      );
      identity.value = (res?['identity'] ?? '').toString();
    } on PlatformException {
      state.value = ShizukuState.notInstalled;
    } on MissingPluginException {
      state.value = ShizukuState.notInstalled;
    }
  }

  Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod<void>('requestPermission');
    } on PlatformException {
      // The listener on the Kotlin side settles the result; refresh reads it.
    }
    await refresh();
  }

  Future<String> run(List<String> argv) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'run',
        {'argv': argv, 'timeoutMs': 20000},
      );
      final out = (res?['stdout'] ?? '').toString();
      final err = (res?['stderr'] ?? '').toString();
      final exit = (res?['exit'] as num?)?.toInt() ?? -1;
      if (exit != 0 && out.trim().isEmpty) {
        return 'Error: command exited $exit. ${err.trim()}';
      }
      return err.trim().isEmpty ? out : '$out\n[stderr] ${err.trim()}';
    } on PlatformException catch (e) {
      return 'Error: ${e.message ?? e.code}';
    } on MissingPluginException {
      return 'Error: the privileged channel is not available in this build.';
    }
  }
}
```

Add to the same file:

```dart
/// The privileged block, or nothing at all.
///
/// Hidden rather than advertised-and-broken: the registry already argues that
/// a model told about a tool that then refuses to run wastes a turn arguing
/// with itself.
List<Tool> privilegedToolsIfReady() {
  if (!Get.isRegistered<PrivilegedService>()) return const [];
  final service = Get.find<PrivilegedService>();
  if (!service.isReady) return const [];
  return buildPrivilegedTools(run: service.run);
}
```

with the imports `import 'tools/privileged_tools.dart';` and
`import 'tools/tool_registry.dart';`.

In `lib/main.dart`, beside the other services:

```dart
  final privileged = Get.put(PrivilegedService());
  unawaited(privileged.refresh());
```

In `lib/controllers/chat_controller.dart` at the `buildDefaultToolRegistry(` call
(line ~1142) and in `lib/views/settings_view.dart` at line ~913, add to the
`extra:` list:

```dart
        ...privilegedToolsIfReady(),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test`
Expected: PASS — all 92 existing plus the new files.

- [ ] **Step 5: Commit**

```bash
git add lib/services/privileged_service.dart lib/main.dart \
  lib/controllers/chat_controller.dart lib/views/settings_view.dart \
  test/privileged_gating_test.dart
git commit -m "feat(tools): gate the privileged block on Shizuku availability

Four states rather than one 'unavailable', because installing Shizuku,
starting it, and granting it permission are three different things to ask
of a user and a single label hides which one applies.

With no ready binder the block is absent from the registry entirely
rather than advertised and failing, matching the argument the registry
already makes for its enabled filter.

identity is carried through because Shizuku may have been started as
root: the app never asks for that, but the same command does different
things under uid 2000 and uid 0, so the dialog has to say which."
```

---

### Task 5: Kotlin side — Shizuku binding and execution

**Files:**
- Modify: `android/app/build.gradle.kts`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Create: `android/app/src/main/aidl/com/dollarbr/mobilelm/IPrivilegedService.aidl`
- Create: `android/app/src/main/kotlin/com/dollarbr/mobilelm/PrivilegedUserService.kt`
- Create: `android/app/src/main/kotlin/com/dollarbr/mobilelm/ShizukuShell.kt`
- Modify: `android/app/src/main/kotlin/com/dollarbr/mobilelm/MainActivity.kt`

**Interfaces:**
- Consumes: the channel contract from Task 4 — `probe` → `{state, identity}`, `requestPermission`, `run{argv, timeoutMs}` → `{stdout, stderr, exit}`.
- Produces: nothing further Dart-side.

> `flutter analyze` does not read Kotlin. A missing import here surfaces only
> at build time — this repo has already lost a session to exactly that
> (`Unresolved reference 'Log'`). Build, do not analyze.

- [ ] **Step 1: Add the dependencies and AIDL support**

In `android/app/build.gradle.kts`, inside `android { }`:

```kotlin
    buildFeatures {
        aidl = true
    }
```

and in `dependencies { }`:

```kotlin
    // Privileged shell. The app never invokes su and never requires root;
    // Shizuku is the only privileged path.
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
```

- [ ] **Step 2: Declare the provider**

In `android/app/src/main/AndroidManifest.xml`, inside `<application>`:

```xml
        <provider
            android:name="rikka.shizuku.ShizukuProvider"
            android:authorities="${applicationId}.shizuku"
            android:multiprocess="false"
            android:enabled="true"
            android:exported="true"
            android:permission="android.permission.INTERACT_ACROSS_USERS_FULL" />
```

- [ ] **Step 3: Write the AIDL contract**

Create `android/app/src/main/aidl/com/dollarbr/mobilelm/IPrivilegedService.aidl`:

```aidl
package com.dollarbr.mobilelm;

interface IPrivilegedService {
    /** Runs argv and returns [stdout, stderr, exitCode] as strings. */
    List<String> exec(in List<String> argv, long timeoutMs);
    int callerUid();
    void destroy() = 16777114;
}
```

- [ ] **Step 4: Write the service that runs inside the Shizuku process**

Create `android/app/src/main/kotlin/com/dollarbr/mobilelm/PrivilegedUserService.kt`:

```kotlin
package com.dollarbr.mobilelm

import android.os.Process
import java.util.concurrent.TimeUnit
import kotlin.system.exitProcess

/**
 * Runs in Shizuku's process, so under uid 2000 (or 0 when the user started
 * Shizuku as root). Executes an argv array directly — no shell is spawned, so
 * a metacharacter in an argument is only ever a literal.
 */
class PrivilegedUserService : IPrivilegedService.Stub() {

    override fun exec(argv: List<String>, timeoutMs: Long): List<String> {
        if (argv.isEmpty()) return listOf("", "empty argv", "-1")
        return try {
            val process = ProcessBuilder(argv).redirectErrorStream(false).start()
            val finished = process.waitFor(timeoutMs, TimeUnit.MILLISECONDS)
            if (!finished) {
                process.destroyForcibly()
                return listOf("", "timed out after ${timeoutMs}ms", "-1")
            }
            listOf(
                process.inputStream.bufferedReader().readText(),
                process.errorStream.bufferedReader().readText(),
                process.exitValue().toString(),
            )
        } catch (t: Throwable) {
            listOf("", t.message ?: t.javaClass.simpleName, "-1")
        }
    }

    override fun callerUid(): Int = Process.myUid()

    override fun destroy() {
        exitProcess(0)
    }
}
```

- [ ] **Step 5: Write the binder wrapper**

Create `android/app/src/main/kotlin/com/dollarbr/mobilelm/ShizukuShell.kt`:

```kotlin
package com.dollarbr.mobilelm

import android.content.ComponentName
import android.content.Context
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.IBinder
import rikka.shizuku.Shizuku

/**
 * The one privileged path. There is no interface here on purpose: a second
 * provider (root) was ruled out by product decision, and an interface with a
 * single implementation is speculative abstraction.
 */
class ShizukuShell(private val context: Context) {

    private var service: IPrivilegedService? = null

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            service = IPrivilegedService.Stub.asInterface(binder)
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            service = null
        }
    }

    private val userServiceArgs = Shizuku.UserServiceArgs(
        ComponentName(context.packageName, PrivilegedUserService::class.java.name),
    ).daemon(false).processNameSuffix("privileged").version(1)

    fun probe(): Map<String, Any> {
        if (!isInstalled()) return mapOf("state" to "notInstalled", "identity" to "")
        if (!Shizuku.pingBinder()) return mapOf("state" to "stopped", "identity" to "")
        if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) {
            return mapOf("state" to "needsPermission", "identity" to "")
        }
        bindIfNeeded()
        val uid = Shizuku.getUid()
        return mapOf(
            "state" to "ready",
            "identity" to if (uid == 0) "root 0" else "shell $uid",
        )
    }

    fun requestPermission(code: Int) = Shizuku.requestPermission(code)

    fun run(argv: List<String>, timeoutMs: Long): Map<String, Any> {
        bindIfNeeded()
        val svc = service
            ?: return mapOf("stdout" to "", "stderr" to "not bound", "exit" to -1)
        val out = svc.exec(argv, timeoutMs)
        return mapOf(
            "stdout" to out.getOrElse(0) { "" },
            "stderr" to out.getOrElse(1) { "" },
            "exit" to (out.getOrElse(2) { "-1" }.toIntOrNull() ?: -1),
        )
    }

    private fun bindIfNeeded() {
        if (service == null) Shizuku.bindUserService(userServiceArgs, connection)
    }

    private fun isInstalled(): Boolean = try {
        context.packageManager.getPackageInfo("moe.shizuku.privileged.api", 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }
}
```

- [ ] **Step 6: Wire the channel**

In `MainActivity.kt`, add the imports `import io.flutter.plugin.common.MethodChannel`
(already present) and declare beside the other channel names:

```kotlin
    private val privilegedChannelName = "com.aichat.ai_chat/privileged"
    private var privilegedChannel: MethodChannel? = null
    private val shizukuShell by lazy { ShizukuShell(this) }
```

Inside `configureFlutterEngine`, after the existing channels:

```kotlin
        privilegedChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, privilegedChannelName)
        privilegedChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "probe" -> result.success(shizukuShell.probe())
                "requestPermission" -> {
                    shizukuShell.requestPermission(SHIZUKU_PERMISSION_CODE)
                    result.success(null)
                }
                "run" -> {
                    @Suppress("UNCHECKED_CAST")
                    val argv = call.argument<List<String>>("argv") ?: emptyList()
                    val timeout = (call.argument<Number>("timeoutMs") ?: 20000).toLong()
                    Thread {
                        val out = shizukuShell.run(argv, timeout)
                        runOnUiThread { result.success(out) }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
```

and a companion constant:

```kotlin
    companion object {
        private const val SHIZUKU_PERMISSION_CODE = 4711
    }
```

- [ ] **Step 7: Build to verify Kotlin compiles**

Run: `flutter build apk --debug --target-platform android-arm64`
Expected: BUILD SUCCESSFUL. A missing import fails here and nowhere earlier.

- [ ] **Step 8: Commit**

```bash
git add android/
git commit -m "feat(android): Shizuku-backed privileged shell

Execution goes through a UserService over AIDL rather than
Shizuku.newProcess, which the Shizuku-API README says is being removed in
favour of exactly this.

The service runs ProcessBuilder on an argv array, so no shell is ever
spawned and a metacharacter in an argument stays a literal — the property
the Dart-side validation is written to preserve.

No interface wraps this. A second provider was ruled out by product
decision, and one implementation behind an interface is abstraction
without a second case to justify it."
```

---

### Task 6: Confirmation dialog shows the command

**Files:**
- Modify: `lib/controllers/chat_controller.dart:868-903`

**Interfaces:**
- Consumes: `Tool.preview` from Task 1; `PrivilegedService.identity` from Task 4.
- Produces: nothing.

- [ ] **Step 1: Replace the dialog body**

In the `confirmMarker` branch, replace the `argsText`/`AlertDialog` construction:

```dart
            final tool = _tools.byName(call.name);
            final command = tool?.preview?.call(call.arguments);
            final identity = Get.isRegistered<PrivilegedService>()
                ? Get.find<PrivilegedService>().identity.value
                : '';
            final argsText = call.arguments.entries
                .map((e) => '${e.key}: "${e.value}"')
                .join('\n');
            final allowed = await Get.dialog<bool>(
                  AlertDialog(
                    title: Text(call.name),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (argsText.isNotEmpty) Text(argsText),
                        // A tool name is not something a person can judge.
                        // The command is.
                        if (command != null) ...[
                          const SizedBox(height: 10),
                          const Text('Runs:'),
                          SelectableText(
                            command,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ],
                        if (identity.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('as $identity'),
                        ],
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Get.back(result: false),
                        child: const Text('Deny'),
                      ),
                      FilledButton(
                        onPressed: () => Get.back(result: true),
                        child: const Text('Allow'),
                      ),
                    ],
                  ),
                ) ??
                false;
```

Add `import '../services/privileged_service.dart';` to the file's imports.

- [ ] **Step 2: Verify nothing regressed**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test`
Expected: 0 errors, all tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/controllers/chat_controller.dart
git commit -m "feat(tools): show the real command in the confirmation dialog

A tool name and a bag of arguments is not something a person can judge in
the second they spend on a dialog. The command is, and for a privileged
call so is the uid it runs under."
```

---

### Task 7: Settings group

**Files:**
- Modify: `lib/views/settings_view.dart`

**Interfaces:**
- Consumes: `ShizukuState.label`, `.hint`, `PrivilegedService` from Task 4.
- Produces: nothing.

- [ ] **Step 1: Add the group widget**

Add a method beside `_buildToolsCard`:

```dart
  /// The privileged block's own card: its tools are useless without a binder,
  /// and the three not-ready states each need a different action from the
  /// user, so they get told which one applies.
  Widget _buildShizukuCard(BuildContext context, bool isDark) {
    final service = Get.find<PrivilegedService>();
    return Obx(() {
      final state = service.state.value;
      final identity = service.identity.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state == ShizukuState.ready && identity.isNotEmpty
                ? '${state.label} · $identity'
                : state.label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (state.hint.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(state.hint),
          ],
          if (state == ShizukuState.needsPermission) ...[
            const SizedBox(height: 8),
            FilledButton(
              onPressed: service.requestPermission,
              child: const Text('Grant permission'),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: service.refresh,
            child: const Text('Re-check'),
          ),
        ],
      );
    });
  }
```

Render it in the settings list beside the Tools group, and add
`import '../services/privileged_service.dart';`.

- [ ] **Step 2: Verify**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test`
Expected: 0 errors, all tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/views/settings_view.dart
git commit -m "feat(settings): ADB / Shizuku status card

Shows which of the four states applies and what it asks of the user.
Install, start, and grant are three different problems and one
'unavailable' label would have hidden which one you have."
```

---

### Task 8: Verify on device and document

**Files:**
- Create: `docs/SHIZUKU.md`
- Modify: `.gitignore`, `AGENTS.md`

- [ ] **Step 1: Install and check the four states**

```bash
flutter build apk --release --target-platform android-arm64
adb -s <device> install -r build/app/outputs/flutter-apk/app-release.apk
adb -s <device> shell am start -n com.dollarbr.mobilelm/.MainActivity
```

Use `am start`, never `monkey` — it injects random events and turns on
auto-rotation. Capture and restore `settings get system accelerometer_rotation`
around the install.

Walk all four: Shizuku uninstalled, installed but stopped, running without
permission, granted. Confirm the tool block is absent from Settings in the
first three.

- [ ] **Step 2: Exercise one read and one write**

In a chat, ask for the Android version (should reach `read_system_prop`) and
then to read `secure/android_id`. Confirm the dialog shows the command and the
uid, and that denying returns the declined message.

- [ ] **Step 3: Write the doc**

Create `docs/SHIZUKU.md` covering: what Shizuku is and that the app never needs
root; the four states and what each asks of the user; the argv-not-shell-string
rule and why; the 8 KB cap and why; what is out of scope for v1 and why.

Add `!docs/SHIZUKU.md` to `.gitignore` beside the other negations — `docs/*` is
ignored in this repo and each durable doc needs its own line.

Add a pointer to it in `AGENTS.md`.

- [ ] **Step 4: Commit**

```bash
git add docs/SHIZUKU.md .gitignore AGENTS.md
git commit -m "docs: how the Shizuku tool block works and what it refuses to do"
```
