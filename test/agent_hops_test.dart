import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/core/constants.dart';
import 'package:mobilelm/services/agent_hops.dart';

/// The tool-hop ceiling, and — the part that was actually broken — what it says
/// when it stops.
///
/// ## The bug
///
/// Three places described `agentMaxHops == 0` and none of them was the loop:
///
/// - this docstring's own comment: *"0 = infinite (no ceiling)"*;
/// - the Settings tile: `∞`, subtitle *"Unlimited agent mode"*;
/// - `chat_controller.dart`: `while (hop < maxHops)`, which for 0 is **zero**
///   iterations.
///
/// So the user who chose "unlimited" got an agent that could not call one tool,
/// and the screen said the opposite. Nothing threw, nothing warned, and the
/// feature looked like it was on.
///
/// The second half was the ending message: `'Tool limit reached ($maxHops
/// hop(s)).'` would have said *limit reached (0 hops)* — quoting back the number
/// that was supposed to mean "none".
void main() {
  group('0 is not zero hops', () {
    test('the setting at 0 still lets the agent work', () {
      final hops = AgentHops.resolve(0, isLocal: true);
      expect(hops.ceiling, greaterThan(0),
          reason: 'a ceiling of zero is not "unlimited", it is "do nothing", '
              'and that is exactly what `while (hop < 0)` did');
      expect(hops.ceiling, AppConstants.agentHopBackstop);
      expect(hops.unlimited, isTrue,
          reason: 'and the ending has to know the difference, because the '
              'sentence it writes depends on it');
    });

    test('and the message says the backstop is the app\'s, not the user\'s', () {
      // The user asked for no limit. Telling them "tool limit reached" would
      // describe a limit they deliberately did not set.
      final msg = AgentHops.resolve(0, isLocal: true).limitReachedMessage();
      expect(msg, contains('${AppConstants.agentHopBackstop}'));
      expect(msg.toLowerCase(), contains("you set it to unlimited"));
      expect(msg.toLowerCase(), isNot(contains('tool limit reached')),
          reason: 'a limit the user did not choose is not a limit they reached');
    });
  });

  group('a chosen number stays a chosen number', () {
    test('each value from 1 to the cap is taken verbatim', () {
      for (var n = 1; n <= AppConstants.maxAgentHopsCap; n++) {
        final hops = AgentHops.resolve(n, isLocal: true);
        expect(hops.ceiling, n);
        expect(hops.unlimited, isFalse);
      }
    });

    test('the message quotes the number back as theirs, singular and plural',
        () {
      expect(AgentHops.resolve(1, isLocal: true).limitReachedMessage(),
          contains('(1 hop)'));
      expect(AgentHops.resolve(3, isLocal: true).limitReachedMessage(),
          contains('(3 hops)'),
          reason: '"1 hops" is the kind of thing that ships because nobody '
              'looked at the singular');
    });
  });

  group('cloud has a ceiling the setting cannot move', () {
    test('the setting is ignored entirely', () {
      // Not "clamped to 20": ignored. It is a local setting, and cloud's 20 is
      // about credits — a person should not be able to raise it by accident
      // from a tile about the local agent.
      for (final n in [0, 1, 5, 8]) {
        expect(AgentHops.resolve(n, isLocal: false).ceiling, 20,
            reason: 'setting $n must not reach the cloud loop');
      }
    });

    test('and cloud never claims to be unlimited', () {
      expect(AgentHops.resolve(0, isLocal: false).unlimited, isFalse,
          reason: 'otherwise the ending would tell a cloud user their 0 reached '
              'the app backstop, which is not what stopped them');
    });
  });

  group('a negative setting is not a way to get zero hops back', () {
    // `setAgentMaxHops` clamps to 0..8, so a stored negative should be
    // impossible. Resolving one to 0 here anyway means a corrupted Hive value
    // gets the same treatment as "unlimited" rather than a silent zero.
    test('it resolves like the unlimited case', () {
      final hops = AgentHops.resolve(-3, isLocal: true);
      expect(hops.ceiling, AppConstants.agentHopBackstop);
      expect(hops.unlimited, isTrue);
    });
  });

  test('the backstop is a real number and not a placeholder', () {
    // Every argument in the constant's comment is about cost per hop. If someone
    // "fixes" a hang by setting this to 0, the whole class of bug returns and
    // this is the assertion that says so.
    expect(AppConstants.agentHopBackstop, greaterThan(0));
    expect(AppConstants.agentHopBackstop, greaterThan(20),
        reason: 'cloud is held to 20 because of credits; this one exists because '
            'a spinner that never ends is worse, so it is above');
  });
}
