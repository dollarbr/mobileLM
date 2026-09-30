import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/utils/logistic.dart';

/// The logistic function behind `relevance_score_probability`.
///
/// It shipped as a 24-term Taylor series inside the rerank handler and returned
/// **1,2470** and **−0,00098** for real logits of −10,645 and −7,561, measured on
/// a Galaxy A72 running `bge-reranker-v2-m3`, from a model that was ranking
/// correctly the whole time. The logit next to it was right, so nothing looked
/// broken — which is the reason the range below is the range of a *confidently
/// wrong* document rather than of an interesting one.
///
/// A reranker fed a plausible query and a plausible document produces a logit
/// near zero, which is the one region where the old series was accurate. It only
/// breaks when the model is sure, i.e. on documents that are obviously wrong, and
/// the ordering is already right in that case, so nobody looks twice. Any test
/// with a reasonable query and a reasonable document passes against the broken
/// version; that is why these cases are the recorded device values rather than
/// invented boundaries.
void main() {
  // What the Galaxy A72 run actually returned: (logit, probability). The last two
  // are the bug — a probability above 1 and one below 0.
  const fromA72 = <(double, double)>[
    (0.7458935976028442, 0.6782832770754093),
    (-4.5768585205078125, 0.010182404827798947),
    (-7.560942649841309, -0.000985221394697156),
    (-10.645021438598633, 1.2469757958344225),
  ];

  group('sigmoid', () {
    test('stays inside [0, 1] for the values the device produced', () {
      for (final (logit, _) in fromA72) {
        final p = sigmoid(logit);
        expect(p, greaterThanOrEqualTo(0.0), reason: 'sigmoid($logit) = $p');
        expect(p, lessThanOrEqualTo(1.0), reason: 'sigmoid($logit) = $p');
      }
    });

    test('reproduces the two correct values the device should have got', () {
      // These are the two that were nonsense. The correct answers are what the
      // ranking in that same run implies: the cake recipe was far below the
      // winning document, and "bateria" sat between them.
      expect(sigmoid(-10.645021438598633), closeTo(2.4e-5, 1e-5));
      expect(sigmoid(-7.560942649841309), closeTo(4.9e-4, 1e-4));
    });

    test('agrees with the two correct values the device did get', () {
      // 1e-7, not 1e-9, and the reason is worth having in the file: the *expected*
      // values here are what the broken series produced, and the series was
      // already carrying about 9,5e-9 of error at x = −4,58 — its ninth digit,
      // before it turns catastrophic. Holding the new function to the old one's
      // full precision would be holding it to the old one's error.
      for (final (logit, expected) in fromA72.take(2)) {
        expect(sigmoid(logit), closeTo(expected, 1e-7),
            reason: 'sigmoid($logit)');
      }
    });

    test('is monotone, so sorting by it agrees with sorting by the logit', () {
      var previous = -1.0;
      for (var x = -60.0; x <= 60.0; x += 0.5) {
        final p = sigmoid(x);
        expect(p, greaterThanOrEqualTo(previous), reason: 'not monotone at $x');
        previous = p;
      }
    });

    test('is never NaN, including for a NaN input', () {
      expect(sigmoid(double.nan), 0.5);
      for (var x = -700.0; x <= 700.0; x += 7.0) {
        expect(sigmoid(x).isNaN, isFalse, reason: 'NaN at $x');
      }
    });

    test('saturates onto the clamp rather than overflowing at the ends', () {
      // 1 − 1e-12, not 1.0, and not 0.0. The floor is deliberate: a probability of
      // exactly 0 makes a client that takes its logarithm produce −infinity, and
      // one of exactly 1 makes `1 − p` do the same. Asserted rather than assumed,
      // because "the clamp exists" is exactly the sort of claim that decays.
      expect(sigmoid(700), closeTo(1 - 1e-12, 1e-15));
      expect(sigmoid(-700), closeTo(1e-12, 1e-15));
      expect(sigmoid(0), closeTo(0.5, 1e-12));
      expect(sigmoid(double.infinity), closeTo(1 - 1e-12, 1e-15));
      expect(sigmoid(double.negativeInfinity), closeTo(1e-12, 1e-15));
    });

    test('agrees with an independent formulation where both are exact', () {
      // `(eˣ − 1) / (eˣ + 1)` is `tanh(x/2)`, and `½(1 + tanh(x/2))` is the
      // logistic. It is the same function assembled the other way round: one `exp`
      // of the raw argument, no reciprocal, no branch. So agreeing with it is a
      // check on the branch structure and the reciprocal rather than a tautology,
      // and it is exact for the range below — at |x| ≤ 18, `eˣ` is at most 6,6e7,
      // so the subtraction in the numerator cancels three digits at worst.
      //
      // The obvious reference, another power series, is the mistake this file
      // exists to record: 40 terms at x = −40 peak around 1,2e17 cancelling down
      // to a true 4,2e−18, and return 0,9999999999. Same failure, better
      // coefficients, same wrong answer. Past |x| ≈ 20 this formulation loses to
      // cancellation too, and the true value is under the clamp anyway, so the
      // tails are asserted against the clamp by name instead.
      for (var x = -18.0; x <= 18.0; x += 0.31) {
        expect(sigmoid(x), closeTo(_independent(x), 1e-12), reason: 'at $x');
      }
    });
  });
}

/// `½(1 + tanh(x/2))` with `tanh(z)` written as `(e^{2z} − 1)/(e^{2z} + 1)`.
double _independent(double x) {
  final double e = math.exp(x);
  return 0.5 * (1 + (e - 1) / (e + 1));
}
