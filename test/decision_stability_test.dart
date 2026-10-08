import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/services/decision_stability.dart';

DecisionProbe ok(String letter, String label, List<String> shown) => DecisionProbe(
      order: {for (final s in shown) s: _lab(s)},
      letter: letter,
      label: label,
    );

String _lab(String letter) => switch (letter) {
      'A' => 'Suporte tecnico',
      'B' => 'Financeiro',
      'C' => 'Recursos humanos',
      _ => 'Juridico',
    };

void main() {
  group('summariseDecisionStability', () {
    test('every run agreeing is stable', () {
      // The measured `d1-3B` invoice case: 24/24.
      final s = summariseDecisionStability([
        ok('A', 'Financeiro', ['A', 'B', 'C', 'D']),
        ok('B', 'Financeiro', ['B', 'C', 'D', 'A']),
        ok('C', 'Financeiro', ['C', 'D', 'A', 'B']),
      ]);
      expect(s.isStable, isTrue);
      expect(s.distinct, 1);
      expect(s.failed, 0);
      expect(s.leading, 'Financeiro');
      expect(s.leadingRuns, 3);
      expect(s.agreement, 1.0);
      expect(s.describe(), 'stable: 3 of 3 agreed on Financeiro');
    });

    test('the measured unstable case: 13/24 split', () {
      // The same question the canonical endpoint answers with 0.58 confidence and
      // 13/24 permutations. Two different labels, no majority to report.
      final probes = <DecisionProbe>[];
      for (var i = 0; i < 24; i++) {
        final wins = i < 13;
        probes.add(ok(
          wins ? 'A' : 'B',
          wins ? 'Suporte tecnico' : 'Financeiro',
          ['A', 'B', 'C', 'D'],
        ));
      }
      final s = summariseDecisionStability(probes);
      expect(s.isStable, isFalse);
      expect(s.distinct, 2);
      expect(s.leading, 'Suporte tecnico');
      expect(s.leadingRuns, 13);
      expect(s.describe(), contains('unstable: 2 different answers'));
    });

    test('compares by content, not by letter', () {
      // The whole point: A->Financeiro and B->Financeiro is one decision twice.
      final s = summariseDecisionStability([
        ok('A', 'Financeiro', ['A', 'B']),
        ok('B', 'Financeiro', ['B', 'A']),
      ]);
      expect(s.isStable, isTrue);
      expect(s.distinct, 1);
    });

    test('a refused run is instability, not a dropped run', () {
      // Dropping the failure would let a model that answers once and refuses
      // three times report perfect stability.
      final s = summariseDecisionStability([
        ok('A', 'Financeiro', ['A', 'B']),
        const DecisionProbe(order: {'A': 'x', 'B': 'y'}),
        const DecisionProbe(order: {'A': 'x', 'B': 'y'}),
      ]);
      expect(s.isStable, isFalse);
      expect(s.failed, 2);
      expect(s.distinct, 1);
      expect(s.describe(), contains('unstable: 2 of 3 produced no answer'));
    });

    test('agreement is the share of runs, and is null with nothing answered', () {
      expect(summariseDecisionStability([]).agreement, isNull);
      expect(summariseDecisionStability([]).describe(), 'no runs');
      final all = summariseDecisionStability([
        const DecisionProbe(order: {'A': 'x'}),
        const DecisionProbe(order: {'A': 'x'}),
      ]);
      expect(all.describe(), 'no run produced an answer');
    });

    test('a tie breaks on the label, not on probe order', () {
      // Two labels, equal count: `leading` must not depend on which ran first,
      // or two identical runs disagree and the report is worthless.
      final a = summariseDecisionStability([
        ok('A', 'Zeta', ['A', 'B']),
        ok('B', 'Alfa', ['B', 'A']),
      ]);
      final b = summariseDecisionStability([
        ok('B', 'Alfa', ['B', 'A']),
        ok('A', 'Zeta', ['A', 'B']),
      ]);
      expect(a.leading, b.leading);
      expect(a.leading, 'Alfa');
    });
  });

  group('decisionPermutations', () {
    final letters = {'A': 'a', 'B': 'b', 'C': 'c', 'D': 'd'};

    /// The regression this ordering change exists for. Measured on `d1-3B`: the
    /// full 24 split 18/6, and **none of the 4 rotations was among the 6 that
    /// flipped**, so a 3-variant rotation reported `3/3 stable` on a question
    /// that is only 75% stable.
    test('reaches the permutations that actually flip, unlike rotation', () {
      // Lower-case, because that is how the desktop run wrote them down; the
      // generator emits upper-case keys, so normalise once instead of two sides
      // of a comparison disagreeing about case (which is what happened first).
      const flips = {'bacd', 'bcad', 'bdca', 'cbad', 'cbda', 'dbca'};
      final reached = decisionPermutations(letters, limit: 12)
          .map((p) => p.keys.join().toLowerCase())
          .toSet();
      expect(
        reached.intersection(flips).length,
        greaterThanOrEqualTo(3),
        reason: 'must reach at least 3 of the 6 that flipped; reached $reached',
      );
      // Rotation covers 4 of 24 and reaches none of them — assert the contrast,
      // so the test fails if someone reinstates it.
      const rotations = {'abcd', 'bcda', 'cdab', 'dabc'};
      expect(
        rotations.intersection(flips),
        isEmpty,
        reason: 'the contrast is only meaningful if rotation really misses all 6',
      );
    });

    test('spreads across the space rather than one cyclic group', () {
      final first8 = decisionPermutations(letters, limit: 8)
          .map((p) => p.keys.join())
          .toList();
      // A cyclic generator gives 4 distinct prefixes ('a','b','c','d'); Lehmer
      // gives 8 distinct first letters out of 4 options because the enumeration
      // is not grouped by first element.
      expect(first8.toSet().length, 8);
      expect(first8.first, 'ABCD');
    });

    test('is exhaustive when the limit allows it', () {
      final all = decisionPermutations(letters, limit: 99)
          .map((p) => p.keys.join())
          .toSet();
      expect(all.length, 24, reason: '4! permutations, no duplicates');
    });

    test('a complete walk still balances positions, but the prefix does not', () {
      // Stated because it is a real asymmetry: the first `limit` variants do NOT
      // visit every position with every letter, and they are not meant to — they
      // are meant to reach distinct first letters, which is the axis the measured
      // flip set separates on. Balance holds only when the whole space is walked.
      final prefix = decisionPermutations(letters, limit: 4);
      expect(prefix.map((p) => p.keys.first).toSet(), {'A'},
          reason: 'the budget is spent on distinct first letters first');

      final all = decisionPermutations(letters, limit: 24);
      for (var pos = 0; pos < 4; pos++) {
        expect(all.map((p) => p.keys.elementAt(pos)).toSet(),
            letters.keys.toSet(), reason: 'position $pos over the full walk');
      }
    });

    test('label travels with its letter', () {
      final perms = decisionPermutations(letters, limit: 4);
      for (final p in perms) {
        for (final e in p.entries) {
          expect(e.value, letters[e.key], reason: '${e.key} kept its label');
        }
      }
    });

    test('respects the limit and defaults to the ceiling', () {
      expect(
        decisionPermutations(letters).length,
        kDefaultDecisionVariants,
      );
      expect(decisionPermutations(letters, limit: 2).length, 2);
    });

    test('is reproducible', () {
      expect(
        decisionPermutations(letters, limit: 6).map((p) => p.keys.toList()).toList(),
        decisionPermutations(letters, limit: 6).map((p) => p.keys.toList()).toList(),
      );
    });

    test('fewer than two options still yields one run', () {
      expect(decisionPermutations({'A': 'x'}).length, 1);
      expect(decisionPermutations({}).length, 1);
    });

    test('an absurd limit yields the whole space, not the option count', () {
      // Rotation's version of this test asserted 4 — the option count. That was
      // the bug it had, not a property worth keeping.
      expect(decisionPermutations(letters, limit: 9999).length, 24);
    });

    test('copes with five options without exploding', () {
      final five = <String, String>{
        for (final c in 'ABCDE'.split('')) c: c.toLowerCase(),
      };
      expect(decisionPermutations(five, limit: 12).length, 12);
      expect(
        decisionPermutations(five, limit: 999).length,
        120,
        reason: '5! permutations',
      );
    });
  });
}