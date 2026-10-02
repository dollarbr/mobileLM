import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/services/workspace_paths.dart';

/// The two workspace path rules, as pure functions.
///
/// Both were live bugs, and both failed by producing a *plausible* wrong value
/// rather than an exception, which is why neither showed up as a crash:
///
/// - **the unbounded path**: `openFolder` composed `childRelPath(name)` out of
///   a listing that carries only a name, so tapping the same folder repeatedly
///   gave `TESTES/TESTES/TESTES` with no limit. It read as the app forgetting
///   where it was, because the path was one the app had built itself;
/// - **the cold start**: nothing remembered the chosen project, `loadSessions()`
///   opens no conversation, so the first new conversation after a restart asked
///   again — while the Settings tile said the choice was remembered.
void main() {
  group('navigateInto cannot build an unbounded path', () {
    test('a normal descent joins the path', () {
      expect(navigateInto('', 'TESTES'), 'TESTES');
      expect(navigateInto('TESTES', 'logs'), 'TESTES/logs');
      expect(navigateInto('TESTES/logs', 'raw'), 'TESTES/logs/raw');
    });

    test('entering a folder that repeats the current one does not move', () {
      // The reported symptom. `TESTES` is the current folder and a subfolder
      // also called `TESTES` is tapped.
      expect(navigateInto('TESTES', 'TESTES'), 'TESTES',
          reason: 'and it returns the current path rather than throwing, so the '
              'caller can treat it as "already here"');
    });

    test('and because it did not move, the next tap cannot either', () {
      // This is the property that makes the growth impossible rather than
      // merely unlikely: the first refusal leaves the parent unchanged, and the
      // parent still ends in the same name, so every later tap is refused too.
      var path = 'TESTES';
      for (var i = 0; i < 20; i++) {
        path = navigateInto(path, 'TESTES');
      }
      expect(path, 'TESTES');
      expect(path.split('/').where((s) => s == 'TESTES').length, 1);
    });

    test('a repeated name deeper in the tree is still legal', () {
      // The rule is about the immediate parent, not about the name appearing
      // twice. `A/A/B/A` is four real folders and must stay reachable, or the
      // guard would be a prison rather than a rule.
      expect(navigateInto('A', 'A'), 'A',
          reason: 'immediate re-entry is the thing being refused');
      expect(navigateInto('A', 'B'), 'A/B');
      expect(navigateInto('A/B', 'A'), 'A/B/A',
          reason: 'and here the parent is B, so descending into A is fine');
      expect(navigateInto('A/B/A', 'C'), 'A/B/A/C');
    });

    test('an empty or separator-bearing name does not move', () {
      expect(navigateInto('TESTES', ''), 'TESTES');
      expect(navigateInto('TESTES', '   '), 'TESTES');
      expect(navigateInto('TESTES', 'a/b'), 'TESTES',
          reason: 'a name with a separator is not reachable from a SAF listing; '
              'treating it as one segment would silently open another folder');
    });

    test('the name is trimmed, so a trailing space cannot dodge the guard', () {
      // The listing and the picker both hand over raw names. If the guard
      // compared untrimmed, "TESTES " would sail past it and produce
      // "TESTES/TESTES " — the same path to the same folder, one level deeper,
      // and the repetition would be back with a different spelling.
      expect(navigateInto('TESTES', 'TESTES '), 'TESTES');
      expect(navigateInto('TESTES', ' TESTES'), 'TESTES');
    });
  });

  group('resolveRememberedProject survives the folder disappearing', () {
    const existing = ['TESTES', 'notes'];

    test('a project that still exists is remembered', () {
      expect(resolveRememberedProject('TESTES', existing), 'TESTES');
    });

    test('one that was deleted outside the app is dropped', () {
      // The folder can vanish in a file manager, and a remembered name that no
      // longer exists would bind every new conversation to somewhere the file
      // tools cannot reach — silently, and every time.
      expect(resolveRememberedProject('GONE', existing), isNull);
    });

    test('and the drop is reported, so the app can say so', () {
      // Silently asking again is what made the original feel like amnesia: the
      // user set a default, the default quietly stopped existing, and the only
      // evidence was a dialog they did not expect.
      final gone = <String>[];
      resolveRememberedProject('GONE', existing, onDropped: gone.add);
      expect(gone, ['GONE']);
    });

    test('nothing remembered is null and reports nothing dropped', () {
      // Null means "fresh install" to `_createNewChat`, and that is the one
      // case where asking the user is the right thing to do.
      final gone = <String>[];
      expect(resolveRememberedProject(null, existing, onDropped: gone.add),
          isNull);
      expect(gone, isEmpty);
    });

    test('an empty remembered value is treated as nothing remembered', () {
      expect(resolveRememberedProject('', existing), isNull,
          reason: 'a blank string in the box must not become a project called ""');
    });

    test('an empty workspace cannot remember anything', () {
      expect(resolveRememberedProject('TESTES', const []), isNull);
    });
  });
}
