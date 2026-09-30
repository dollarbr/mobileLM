import 'dart:math' as math;

/// The logistic function, evaluated so that it cannot cancel and cannot leave
/// `[0, 1]`.
///
/// This is here as a pure function because the first version of it lived inside
/// the rerank HTTP handler as a private static, which is the one place a numeric
/// function cannot be reached by a test. That is how it shipped broken.
///
/// **What it was, and what it did.** It was a hand-rolled 24-term Taylor series
/// for `exp`, written to avoid `dart:math` on the grounds that `exp` "overflows to
/// infinity well inside the range a logit can reach" and `Infinity` is not valid
/// JSON. Both halves of that reasoning are wrong, and the field was measurably
/// broken while the model beside it was working perfectly.
///
/// On a Galaxy A72 running `bge-reranker-v2-m3`, real logits of −10,645 and
/// −7,561 came back as `relevance_score_probability` of **1,2470** and
/// **−0,00098** — one above 1, one below 0. The `relevance_score` beside them was
/// correct, which is precisely why nothing looked wrong.
///
/// `Σ xⁱ/i!` is fine for small `|x|`. Its terms grow to roughly `e^|x|` around
/// `i = |x|` before shrinking, so at `x = −10,6` the partial terms reach about
/// 5 000 and then cancel down to a true value of 2,4e−5. In double precision
/// that cancels five orders of magnitude, and the *sign* of the answer does not
/// survive it. The 24-term truncation is not the cause and no term count would
/// fix it, because the cancellation is inherent to summing a series whose terms
/// overshoot the answer by thousands of times over.
///
/// And `dart:math` was never the hazard. The two branches below each hand `exp`
/// an argument that is bounded by construction: `x >= 0` gives it `−x ≤ 0`, so the
/// result is in `(0,5; 1]`; `x < 0` gives it `x < 0`, so the result is in
/// `(0; 0,5)`. Neither branch can be infinite for any finite input, and `exp`
/// itself only reaches infinity past about 709 — well beyond anything a classifier
/// produces, since a saturating one plateaus in the tens.
///
/// The clamp is not load-bearing and is here anyway. A field named
/// `probability` that quietly leaves `[0, 1]` breaks a client's range check
/// without telling anyone, and no client should have to know how this is computed
/// in order to trust it.
double sigmoid(double x) {
  if (x.isNaN) return 0.5;
  // `exp` is only reached with a non-positive argument, so it cannot overflow.
  // The guard is here to make that a property of the code rather than a property
  // of the two branches, in case a caller ever passes a positive value straight
  // in.
  final double e = math.exp(x < 0 ? x : -x);
  final double p = x >= 0 ? 1 / (1 + e) : e / (1 + e);
  return p.clamp(_floor, 1 - _floor).toDouble();
}

/// Far enough from 0 and 1 that a client dividing by it, or taking its logarithm,
/// does not manufacture its own infinity. `1e-12` is the logit of about −27,
/// which a reranker reaches only when it is extremely confident — and there a
/// probability of exactly 0 carries no more information than 1e−12 does.
const double _floor = 1e-12;
