import '../core/constants.dart';

/// How many tool round-trips one message may take, and — when the loop stops —
/// what to tell the person who asked for it.
///
/// ## Why this is a separate file
///
/// Because the bug it fixes was a disagreement between three places that each
/// said something different and none of them was the loop:
///
/// - the docstring on `setAgentMaxHops`: *"0 = infinite (no ceiling)"*;
/// - the Settings tile: `∞`, subtitle *"Unlimited agent mode"*;
/// - the loop: `while (hop < maxHops)`, which for 0 is **zero** iterations.
///
/// A user who picked "unlimited" got an agent that could not call a single tool,
/// and the tile said the opposite. Three truths, two of them lies, and nothing
/// threw.
///
/// The fix is here rather than in the loop body because the loop body is where
/// the second half of the bug lives: the message it printed on the way out was
/// `'Tool limit reached ($maxHops hop(s)).'`, so with 0 it said *limit reached
/// (0 hops)* — a message about a limit the user never set, quoting the number
/// that was supposed to mean "none".
///
/// **Cloud is not affected and deliberately so.** The loop reads
/// `inferenceMode != 'local' ? 20 : agentMaxHops`, so cloud has its own ceiling
/// that the user cannot move, and this function only decides the local one.

/// What the loop was allowed to do, and why it stopped.
class AgentHops {
  const AgentHops({
    required this.ceiling,
    required this.unlimited,
    required this.unreachable,
  });

  /// The number of hops the loop will actually permit. Never zero.
  final int ceiling;

  /// Whether that number came from the user's "no limit" (`agentMaxHops == 0`)
  /// rather than from a number they typed. Decides the wording of the ending.
  final bool unlimited;

  /// Whether the ceiling was set but the loop never reached it, which is the
  /// normal case: the model stopped asking for tools. Not a limit being hit.
  final bool unreachable;

  /// Resolve the setting into a number the loop can compare against.
  ///
  /// **`0` maps to [AppConstants.agentHopBackstop], not to 0.** A ceiling of zero
  /// is not "unlimited", it is "do nothing", and that is what the loop used to
  /// do with it.
  factory AgentHops.resolve(int setting, {required bool isLocal}) {
    if (!isLocal) {
      // Cloud's own ceiling, out of reach of the setting on purpose: it is
      // about credits, and a person cannot consent to spend them by accident.
      return const AgentHops(ceiling: 20, unlimited: false, unreachable: true);
    }
    if (setting > 0) {
      return AgentHops(
        ceiling: setting,
        unlimited: false,
        unreachable: false,
      );
    }
    return AgentHops(
      ceiling: AppConstants.agentHopBackstop,
      unlimited: true,
      unreachable: false,
    );
  }

  /// What to show when the loop ran out of hops with a tool call still pending.
  ///
  /// Two wordings because the two ceilings mean different things, and merging
  /// them is what produced the nonsense one:
  ///
  /// - the user asked for no limit, so the honest sentence names the app's
  ///   backstop and says it was the app's choice, not theirs;
  /// - the user typed a number, so the number is quoted back to them as theirs.
  String limitReachedMessage() => unlimited
      ? 'The model kept calling tools, so this stopped at '
          '$ceiling — you set it to unlimited and this is the app\'s backstop, '
          'not a limit you chose.'
      : 'Tool limit reached ($ceiling hop${ceiling == 1 ? '' : 's'}).';
}
