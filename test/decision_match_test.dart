import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/services/decision_model.dart';

/// The match kind is the feature; these fix all three paths and the two ways the
/// old parser reported them identically.
void main() {
  const choices = {'A': 'bug', 'B': 'billing', 'C': 'account'};

  group('DecisionMatch', () {
    test('a lone letter is the contract', () {
      final a = parseDecisionAnswer('B', choices)!;
      expect(a.letter, 'B');
      expect(a.label, 'billing');
      expect(a.match, DecisionMatch.letter);
      expect(a.followedContract, isTrue);
    });

    test('a dressed-up letter is still a letter, but not the contract', () {
      for (final raw in ['B.', '(B)', '**B**', 'B -', 'B)']) {
        final a = parseDecisionAnswer(raw, choices)!;
        expect(a.match, DecisionMatch.decoratedLetter, reason: raw);
        expect(a.letter, 'B', reason: raw);
        // The point of the enum: `followedContract` is false, which is invisible
        // to a caller reading only `letter`.
        expect(a.followedContract, isFalse, reason: raw);
      }
    });

    test('a written label is its own kind, and is not the contract', () {
      final a = parseDecisionAnswer('billing', choices)!;
      expect(a.letter, 'B');
      expect(a.label, 'billing');
      expect(a.match, DecisionMatch.label);
      expect(a.followedContract, isFalse);
    });

    /// The regression this enum exists for: before it, all three returned the
    /// same `letter`/`label` pair and the caller had no way to tell them.
    test('the three kinds are indistinguishable by letter and label alone', () {
      final a = parseDecisionAnswer('B', choices)!;
      final b = parseDecisionAnswer('B.', choices)!;
      final c = parseDecisionAnswer('billing', choices)!;
      for (final other in [b, c]) {
        expect(other.letter, a.letter);
        expect(other.label, a.label);
      }
      expect({a.match, b.match, c.match}.length, 3);
    });
  });

  group('parseDecisionAnswer — the refusals must not move', () {
    test('no letter at all is still null', () {
      expect(parseDecisionAnswer('', choices), isNull);
      expect(parseDecisionAnswer('   \n ', choices), isNull);
      expect(parseDecisionAnswer('I cannot help with that.', choices), isNull);
    });

    test('an unterminated think block is still refused', () {
      expect(parseDecisionAnswer('<think>B seems likely', choices), isNull);
      expect(
        parseDecisionAnswer('<think>\n\n</think>\n\nB', choices)!.match,
        DecisionMatch.letter,
      );
    });

    test('a letter that is not an offered option is still refused', () {
      expect(parseDecisionAnswer('Z', choices), isNull);
    });

    test('a label must match the whole answer, not a substring', () {
      // `debugging tools` contains `bug`; accepting a substring here would be the
      // first-letter bug wearing a different hat.
      expect(
        parseDecisionAnswer('debugging tools', {'A': 'bug', 'B': 'other'}),
        isNull,
      );
    });
  });
}