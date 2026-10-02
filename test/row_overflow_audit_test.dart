import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The audit for **`Text` that cannot wrap inside a `Row`**.
///
/// ## What actually overflows
///
/// The fourth time this repository paid for an unconstrained `Row`, the audit was
/// rebuilt instead of hunting by eye — and the *first* version of it was wrong in
/// the way this repository keeps producing wrong things: **an error that presents
/// itself as another one**.
///
/// The first scanner flagged **24** places, and it was measuring the wrong string.
/// The trap is that a `Text` inside a `Row` is measured by the widget tree in
/// two different regimes:
///
/// - `Expanded` / `Flexible` / `Spacer` → the child gets a **bounded** width and
///   wraps. Any length is fine.
/// - neither → the child gets an **unbounded** width, does not wrap, and overflows
///   as soon as its intrinsic width exceeds what the row has left.
///
/// So the first scan's "24 candidates" was really 24 places where the code *looks*
/// unwrapped, and most of them were `'${(pct * 100).toStringAsFixed(0)}%'` — four
/// characters that cannot overflow anything. **24 was a count of shapes, not of
/// bugs.**
///
/// ## The thing that makes it a real audit: `.tr` is resolved
///
/// The second half of the trap is that the string in the source is often **not the
/// string on screen**. `'listening_tap_mic_to_stop'.tr` is 25 characters in the
/// file and **39 in pt_BR** — *"Ouvindo — toque no microfone para parar"*. At 12 dp
/// and a text scale of 2 that is ~515 dp of intrinsic width in a row that has
/// ~312 dp to work with, and the source literal alone would never have flagged it.
///
/// So this audit resolves every `.tr` key against `lib/l10n/app_translation.dart`
/// before measuring, strips interpolations down to a single character, and only
/// then asks "is the text that will actually be painted at least this long".
/// **24 candidates become 3, and the 3 are the ones that can really overflow.**
///
/// That is the whole reason this file exists rather than a list in a document: the
/// count that is wrong in the cheap direction is 24, the count in the expensive
/// direction is "every `Text` in the app", and the real answer is in between and
/// changes whenever someone adds a translation.
///
/// ## What it does and does not claim
///
/// It claims: *this text, at this length, is a direct child of a `Row` with no
/// `Expanded`, `Flexible` or `Spacer` in it.* That is a **shape**, and a shape is
/// a necessary condition, not a sufficient one — a 3-character string in that
/// position is harmless, and a 40-character one may still fit.
///
/// It does **not** claim a layout failure, because these `Row`s are inside
/// `Obx` bodies in views that cannot be mounted without a Hive box and a
/// `ModelController`. Proving the overflow needs a widget test per site, and that
/// is a second file, not this one.
///
/// The allowlist below is therefore a list of **shapes examined by hand and
/// justified in the comment next to each entry** — not a list of bugs suppressed to
/// make the suite green.
void main() {
  // A row with an unbounded child only overflows past this much painted text.
  // 20 characters is not a derived constant: it is the point where the shortest
  // translation that overflows in this app stops being a hypothetical. See the
  // three entries below for the ones that actually do.
  const minChars = 20;

  final map = _translationMap();
  final views = _viewFiles();

  test('the translation map is not empty, or every key reads as a miss',
      () {
    expect(map, isNotEmpty,
        reason: 'the whole point is resolving `.tr`; an empty map makes every '
            'unresolved key fall back to its own name, which is 12-25 characters '
            'and looks exactly like a real long string');
  });

  test('the scan found view files, or it is looking at nothing',
      () {
    expect(views.length, greaterThan(5),
        reason: 'if the walk stops matching, the audit reports zero overflows '
            'and passes — the failure mode of a scan that cannot fail');
  });

  test('no Text that can overflow is a direct child of an unconstrained Row',
      () {
    final offenders = <String>[];

    for (final file in views) {
      final source = file.readAsStringSync();
      for (final row in _rows(source)) {
        final line = _lineOf(source, row.start);
        for (final child in _directChildren(row.body)) {
          if (_isFlexible(child)) continue;
          if (!_isText(child)) continue;
          final painted = _paintedText(child, map);
          if (painted.length < minChars) continue;
          offenders.add('${_rel(file)}:$line  '
              '${painted.length} chars  ${painted.length > 46 ? '${painted.substring(0, 46)}…' : painted}');
        }
      }
    }

    expect(
      offenders,
      _allowlisted,
      reason: 'A `Text` that is a direct child of a `Row` with no `Expanded`, '
          '`Flexible` or `Spacer` is measured at its full intrinsic width and '
          'cannot wrap, so it overflows the row as soon as the row runs out of '
          'space. Wrap it, or put a `Spacer` after it.\n\n'
          'Each entry below was looked at by hand. If you are adding one, the '
          'comment on it must say why the text fits where it stands — "it is '
          'short" is checked by the length threshold, not by the comment.\n\n'
          '${offenders.isEmpty ? '' : offenders.join('\n')}',
    );
  });

  test('the scanner still finds a row it should find (a sibling proves it)',
      () {
    // The audit above passes vacuously if the parenthesis matcher, the
    // child-splitter or the `.tr` resolver stops working: every site would
    // simply stop being reported. This builds the exact shape the audit looks
    // for and asserts it is found, in isolation from the repository.
    const fonte = '''
      Row(children: [
        const SizedBox(width: 8),
        Text('a_key_that_does_not_exist_anywhere'.tr,
            style: TextStyle(fontSize: 12)),
        const Spacer(),
      ]),
''';
    final achados = <String>[];
    for (final row in _rows(fonte)) {
      for (final child in _directChildren(row.body)) {
        if (_isFlexible(child)) continue;
        if (!_isText(child)) continue;
        achados.add(_paintedText(child, map));
      }
    }
    expect(achados, hasLength(1));
    // Unresolved keys must read as their **own name**, never as an empty string.
    // An empty string is short enough to pass the threshold, so a resolver that
    // quietly returns `''` turns this audit into a no-op.
    expect(achados.single, isNotEmpty);
  });

  test('a Text that is short enough is not reported, even in the same Row',
      () {
    // The other half of the vacuity: the audit must not flag everything, or
    // people will learn to ignore it and the three real ones stop mattering.
    const fonte = '''
      Row(children: [
        Text('ok', style: TextStyle(fontSize: 12)),
        const SizedBox(width: 4),
      ]),
''';
    final achados = <String>[];
    for (final row in _rows(fonte)) {
      for (final child in _directChildren(row.body)) {
        if (_isFlexible(child)) continue;
        if (!_isText(child)) continue;
        final painted = _paintedText(child, map);
        if (painted.length >= minChars) achados.add(painted);
      }
    }
    expect(achados, isEmpty);
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// The allowlist. Every entry says why the text fits where it stands.
// ─────────────────────────────────────────────────────────────────────────────

/// Empty, and that is the point.
///
/// The first run of this audit reported three sites and each was fixed rather
/// than allowlisted: a `Flexible` around the STT pill, and `Expanded` plus
/// ellipsis on the two that sit inside cards. **An allowlist here would have
/// been the cheaper commit and the worse repository** — it makes the audit's
/// green indistinguishable from the bugs being fixed, and the next person adds
/// their entry to it instead of reading their own `Row`.
///
/// So the list stays empty, and if it ever grows, the entry has to carry the
/// reason the text fits where it stands. A bare entry is a suppressed bug.
const _allowlisted = <String>[];

// ─────────────────────────────────────────────────────────────────────────────
// The scanner. Deliberately small, deliberately readable, and deliberately not
// clever: every step of it is a claim someone could check by eye.
// ─────────────────────────────────────────────────────────────────────────────

class _Row {
  _Row(this.start, this.body);
  final int start;
  final String body;
}

List<File> _viewFiles() {
  final root = Directory('lib/views');
  if (!root.existsSync()) return const [];
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// Every `Row(` in the source, with its parenthesised body matched properly.
///
/// Matching parentheses by counting is what makes this able to tell a `Row` from a
/// `Row` inside another widget's argument list, which a regex cannot.
List<_Row> _rows(String source) {
  final out = <_Row>[];
  final re = RegExp(r'\bRow\s*\(');
  for (final m in re.allMatches(source)) {
    final body = _balanced(source, m.end - 1);
    if (body == null) continue;
    out.add(_Row(m.start, body));
  }
  return out;
}

/// The text between the brackets at [open], or `null` if they do not close.
String? _balanced(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    final c = s[i];
    if (c == '(' || c == '[' || c == '{') {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      depth--;
      if (depth == 0) return s.substring(open + 1, i);
    }
  }
  return null;
}

/// The elements of a `children: [...]` list, split at commas that are at the top
/// level of the list — commas inside a nested call or collection do not split.
List<String> _directChildren(String rowBody) {
  final m = RegExp(r'children\s*:\s*\[').firstMatch(rowBody);
  if (m == null) return const [];
  final list = _balanced(rowBody, m.end - 1);
  if (list == null) return const [];

  final out = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < list.length; i++) {
    final c = list[i];
    if (c == '(' || c == '[' || c == '{') {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      depth--;
    } else if (c == ',' && depth == 0) {
      out.add(list.substring(start, i));
      start = i + 1;
    }
  }
  if (start < list.length) out.add(list.substring(start));
  return out;
}

/// A child that gives its subtree a bounded width. `Spacer` is an `Expanded`, and
/// `SizedBox.expand` too — both are the fix, not the disease.
bool _isFlexible(String child) =>
    RegExp(r'\b(Expanded|Flexible|Spacer)\s*\(').hasMatch(child) ||
    RegExp(r'SizedBox\s*\.\s*expand').hasMatch(child);

/// Whether the child starts a `Text(`. A `Text.rich` counts too; an `Icon` does
/// not, because an icon has a fixed size and cannot be the thing that overflows.
bool _isText(String child) =>
    RegExp(r'^\s*(Text|Text\.rich)\s*\(').hasMatch(child);

/// The string that will actually be painted, with `.tr` resolved.
///
/// This is the method the audit exists for. Two rules, both learned the hard way:
///
/// - a `.tr` key resolves against the map, and an **unresolved key reads as its own
///   name** — never as `''`, because an empty string is short enough to slip under
///   the threshold and turn the audit into a no-op;
/// - an interpolation becomes **one character**, because `'${(pct * 100).toStringAsFixed(0)}%'`
///   is four characters on screen and its source form is forty.
String _paintedText(String child, Map<String, String> map) {
  final body = child.substring(child.indexOf('('));

  final tr = RegExp(r"'([A-Za-z0-9_]+)'\s*\.\s*tr").firstMatch(body);
  if (tr != null) return map[tr.group(1)!] ?? tr.group(1)!;

  // No `.tr`: take the first string literal and collapse every interpolation in it.
  // Not a raw string — `r"...\"..."` does not escape the quote, it *ends* the
  // string on it, which is a compile error pointing at the wrong place.
  final lit = RegExp("'([^']*)'|\"([^\"]*)\"").firstMatch(body);
  if (lit == null) return '';
  final raw = lit.group(1) ?? lit.group(2) ?? '';
  return raw
      .replaceAll(RegExp(r'\$\{[^}]*\}'), 'x')
      .replaceAll(RegExp(r'\$[A-Za-z_][A-Za-z0-9_.]*'), 'x')
      .trim();
}

/// `'key': 'value'` out of the GetX map. Written by hand rather than with
/// `Get` because this runs without a Flutter binding, and because the map is a
/// plain Dart literal — importing it would drag the whole view layer in.
Map<String, String> _translationMap() {
  final file = File('lib/l10n/app_translation.dart');
  if (!file.existsSync()) return {};
  final source = file.readAsStringSync();
  return {
    for (final m in RegExp(
            r"^\s*'([A-Za-z0-9_]+)'\s*:\s*'((?:[^'\\]|\\.)*)'",
            multiLine: true)
        .allMatches(source))
      m.group(1)!: m.group(2)!,
  };
}

int _lineOf(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;

String _rel(File f) => f.path.replaceAll(r'\', '/');