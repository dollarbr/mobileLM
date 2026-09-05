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

List<String> logcatArgv({
  int lines = 100,
  String tag = '',
  String priority = '',
}) {
  final n = lines.clamp(1, 500);
  final hasTag = tag.trim().isNotEmpty;
  return [
    'logcat', '-d', '-t', '$n',
    if (hasTag)
      '${_key(tag, "log tag")}:'
          '${priority.trim().isEmpty ? "V" : _key(priority, "priority")}',
    if (hasTag) '*:S',
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
  if (raw.length <= maxBytes) return raw;
  final omittedKb = ((raw.length - maxBytes) / 1024).ceil();
  return '${raw.substring(0, maxBytes)}\n'
      '[... truncated, $omittedKb KB omitted]';
}
