import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/services/decision_stability.dart';
import 'package:mobilelm/services/system_one.dart';

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
  _wireFormatTests();
}

/// The two producers that used to be private to the server class, and the two
/// mutations that **passed 607 of 607** while they were.
///
/// Measured, before this file grew these groups: renaming the payload key
/// `distinct_answers` → `distinctCount`, and removing the clamp from `variants`
/// entirely. Both left the whole suite green, because the tests carried
/// **hand-written copies** of a format nobody could drift away from — a copy is
/// not a contract. The endpoint and the tests now call the same functions.
void _wireFormatTests() {
  group('parseVariants — the clamp, which nothing tested', () {
    test('an absent or non-integer field is one decision', () {
      expect(parseVariants(null), 1);
      expect(parseVariants('12'), 1, reason: 'a string is not a count');
      expect(parseVariants(3.5), 1, reason: 'a double is not a count');
      expect(parseVariants(true), 1);
      expect(parseVariants(<int>[4]), 1);
    });

    test('one and below are one, never zero or negative', () {
      // Zero permutations would mean **no answer at all**, and a negative one is
      // worse. The floor is 1 because the endpoint's contract has always been
      // "one question, one decision".
      for (final bad in [0, -1, -400]) {
        expect(parseVariants(bad), 1, reason: '$bad');
      }
    });

    test('above the ceiling clamps to the ceiling, never past it', () {
      // 400 permutations of a 3B decision at 6,6–23,8 s each is about two hours
      // on the A72. Clamping is what makes a mistyped number a bad number
      // instead of a hung request.
      expect(parseVariants(400), kMaxDecisionVariants);
      expect(parseVariants(kMaxDecisionVariants + 1), kMaxDecisionVariants);
      expect(parseVariants(1 << 40), kMaxDecisionVariants);
    });

    test('inside the range passes through untouched', () {
      for (final n in [1, 2, 4, 11, kMaxDecisionVariants]) {
        expect(parseVariants(n), n, reason: '$n');
      }
    });

    test('a cap below one is raised to one, not obeyed', () {
      // A test helper passing `cap: 0` would otherwise get `0`, and `parseVariants`
      // would hand the caller a request that cannot produce an answer.
      expect(parseVariants(9, cap: 0), 1);
      expect(parseVariants(9, cap: 1), 1);
      expect(parseVariants(9, cap: 4), 4);
    });
  });

  group('clipDecisionText', () {
    test('short text is trimmed and returned whole', () {
      expect(clipDecisionText('  B  '), 'B');
      expect(clipDecisionText(''), '');
    });

    test('long text is cut and marked as cut', () {
      final cut = clipDecisionText('x' * 300);
      expect(cut.length, 201, reason: '200 characters plus the ellipsis');
      expect(cut.endsWith('\u2026'), isTrue,
          reason: 'a real ellipsis, so a response that was cut looks cut');
    });

    test('the boundary is inclusive', () {
      expect(clipDecisionText('x' * 200).length, 200);
      expect(clipDecisionText('x' * 201).length, 201);
    });
  });

  group('stabilityPayload — one producer, read back by the client', () {
    final probes = [
      const DecisionProbe(
        order: {'A': 'x', 'B': 'y'},
        letter: 'B',
        label: 'Financeiro',
        raw: 'B',
      ),
      const DecisionProbe(
        order: {'B': 'y', 'A': 'x'},
        letter: 'A',
        label: 'Financeiro',
        raw: 'A',
      ),
      const DecisionProbe(
        order: {'B': 'y', 'A': 'x'},
        raw: 'I cannot determine which department handles this request.',
      ),
    ];
    final s = summariseDecisionStability(probes);
    final payload = stabilityPayload(s, probes);

    test('the verdict and the probes both travel', () {
      // **Three** probes, not two: two answered, one refused. `runs` counts
      // attempts, which is the whole reason a refusal is instability rather than
      // a dropped run — an assertion written from memory said 2 here and was
      // wrong about the field the test is about.
      expect(payload['runs'], 3);
      expect(payload['stable'], isFalse, reason: 'one run refused');
      expect(payload['failed_runs'], 1);
      expect(payload['leading'], 'Financeiro');
      expect(payload['leading_runs'], 2);
      expect((payload['probes']! as List).length, 3);
    });

    test('a refused run keeps its raw text, clipped', () {
      final list = payload['probes']! as List;
      final refused = list[2] as Map<String, Object?>;
      expect(refused['letter'], isNull);
      expect(refused['label'], isNull);
      expect((refused['raw']! as String).length, lessThanOrEqualTo(81),
          reason: '80 characters plus the ellipsis');
    });

    test('the order travels as letters, not as a map', () {
      // A `Map` serialises to a JSON **object** whose key order is not guaranteed,
      // and the whole point of the field is the order.
      final list = payload['probes']! as List;
      expect((list[0] as Map)['order'], ['A', 'B']);
      expect((list[1] as Map)['order'], ['B', 'A']);
    });

    /// **The round trip that did not exist.** The endpoint builds this map and
    /// `SystemOneResult.fromClassify` reads it; nothing connected the two, which
    /// is why renaming a key was invisible.
    test('the client reads back exactly what this produces', () {
      final read = const SystemOneResult().fromClassify({
        'model': 'd1-3B-Q4_K_M.gguf',
        'choice': 'B',
        'label': 'Financeiro',
        'match': 'letter',
        'stability': payload,
      });
      final back = read.stability!;
      expect(back.runs, 3);
      expect(back.failed, 1);
      expect(back.distinct, 1);
      expect(back.leading, 'Financeiro');
      // Two of the three agreed — and the third is a refusal, not a vote.
      expect(back.leadingRuns, 2);
      expect(back.isStable, isFalse,
          reason: 'two votes out of three attempts is not unanimity');

      // **The order survives, and this is the assertion that was missing.**
      //
      // Every other assertion in this test is about counts, and counts survive a
      // reader that throws the order away — which is what the bug was: the
      // console prints `order.keys.join(' ')`, so all twelve permutation lines
      // rendered as an empty string while every number stayed correct. Removing
      // the `List` branch from `_probeOrder` again left this file green until
      // this line existed.
      expect(back.probes.length, 3);
      expect(back.probes[0].order.keys.toList(), ['A', 'B']);
      expect(back.probes[1].order.keys.toList(), ['B', 'A'],
          reason: 'the second probe really was shown in the other order');
      // A refused run keeps its slot in the list rather than being compacted out.
      expect(back.probes[2].letter, isNull);
      expect(back.probes[2].order.keys.toList(), ['B', 'A']);
    });

    test('and the client agrees with the server about the verdict', () {
      // Both sides run the same `summariseDecisionStability` on the same probes,
      // so a disagreement means one of them is not reading its own output.
      final read = const SystemOneResult().fromClassify({
        'model': 'x',
        'choice': 'B',
        'label': 'Financeiro',
        'stability': payload,
      });
      expect(read.stability!.isStable, payload['stable']);
      expect(read.stability!.runs, payload['runs']);
      expect(read.stability!.leading, payload['leading']);
    });

    test('an unstable verdict survives the trip too', () {
      final split = [
        const DecisionProbe(
            order: {'A': 'x'}, letter: 'A', label: 'Suporte'),
        const DecisionProbe(
            order: {'A': 'x'}, letter: 'B', label: 'Financeiro'),
      ];
      final v = summariseDecisionStability(split);
      final p = stabilityPayload(v, split);
      final read = const SystemOneResult().fromClassify({
        'model': 'x',
        'choice': 'A',
        'label': 'Suporte',
        'stability': p,
      });
      expect(p['stable'], isFalse);
      expect(read.stability!.isStable, isFalse);
      expect(read.stability!.distinct, 2);
      // One vote each: the tie breaks on the **label** rather than on probe
      // order, and both sides have to break it the same way — `Financeiro`
      // sorts before `Suporte`.
      expect(read.stability!.leading, 'Financeiro',
          reason: 'ties break on the label, and both sides must agree');
    });

    test('every run agreeing reads stable on both sides', () {
      final agree = [
        const DecisionProbe(order: {'A': 'x'}, letter: 'A', label: 'bug'),
        const DecisionProbe(order: {'B': 'y'}, letter: 'B', label: 'bug'),
      ];
      final p = stabilityPayload(summariseDecisionStability(agree), agree);
      expect(p['stable'], isTrue);
      expect(p['agreement'], 1.0);
      final read = const SystemOneResult().fromClassify({
        'model': 'x',
        'choice': 'A',
        'label': 'bug',
        'stability': p,
      });
      expect(read.stability!.isStable, isTrue);
      expect(read.stability!.agreement, 1.0);
    });
  });
}
