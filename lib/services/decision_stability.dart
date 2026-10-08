/// Whether a decision model **means** its answer, measured by asking it the same
/// question with the options shuffled.
///
/// Pure, for the same reason `decision_model.dart`, `acceleration.dart` and
/// `memory_readout.dart` are: the thing that can be wrong silently here is a
/// judgement about trust, and a judgement about trust is exactly the thing that
/// must not need a phone to check.
///
/// ## Why this instead of a percentage
///
/// The obvious way to answer "how sure is it?" is to read a probability per
/// option and normalise. That does not work for a generative decision model,
/// and the reason is not philosophical — it is measured:
///
/// - A decision model emits **one** distribution over the whole vocabulary, and
///   the only thing anyone reads from it is the logit of the letter tokens. Those
///   logits are not calibrated. Applying softmax to them always produces numbers
///   that sum to 1, **including when the model has no idea**, so the display
///   cannot distinguish "I am sure" from "I am guessing" — it renders both.
/// - Measured on `d1-omni-600M` with the canonical llama.cpp endpoint, a total
///   outage scored `confidence: 0.0` over a flat `0.34 / 0.25 / 0.28 / 0.14`.
///   Normalised, that reads "34% low severity" — a mild preference, when the
///   truth is that the model does not know and picked wrong.
/// - The Liquid `d1` family ships its own calibration in the GGUF
///   (`lfm2.decision.temperature.*`, per question type and per option-count
///   bucket), precisely because the raw logits are not probabilities. Ignoring
///   them discards what the author shipped; that is a separate, legitimate
///   reading, and it is not this file's job to invent one when the key is absent.
///
/// **Permutation stability is measurable without inventing a number.** Ask the
/// same question with the options in different orders. If the answer follows the
/// *content* it is stable under reordering. If it follows the *position* — the
/// first option, the second — the answer is an artefact of the prompt and the
/// model had no opinion to permute.
///
/// Measured on `d1-3B`, 4 options, all 24 permutations:
///
/// | case | stability | canonical confidence |
/// |---|---|---|
/// | invoice / renegotiation | **24/24 → Financeiro** | 0.80–0.94 |
/// | "where is my second invoice copy" | **13/24 → Support, 11/24 → Financeiro** | 0.32–0.63 |
///
/// The case the model is confident about is permutation-stable. The one it gets
/// wrong **does not have an opinion at all**, and no normalised number separates
/// them. llama.cpp does the same thing upstream: `n_variants` returns 2 for a LEV
/// choice question, *"to cancel the preference for the first label"*.
///
/// ## What this is not
///
/// It is not a confidence score and it does not produce one. A model can be
/// perfectly stable and consistently wrong, and a model can answer 4/4 on a
/// question it has no business answering. This measures **reproducibility under
/// a change that should not matter**, which is the property an automated decision
/// actually depends on and the one a percentage invents away.

library;

/// One answer to one variant of the question.
///
/// [letter] and [label] are **optional**, and that is not laziness: a run where
/// the model failed the contract has no letter, and a constructor that required
/// one would make "the model refused" unrepresentable — which is the case this
/// whole file is about. A probe without them is a real, counted result.
class DecisionProbe {
  const DecisionProbe({
    required this.order,
    this.letter,
    this.label,
    this.raw,
  });

  /// The letters in the order they were shown to the model, mapped to their
  /// labels. This is the only thing that differs between probes of one question.
  final Map<String, String> order;

  /// What came back. Null when the model failed the contract on this run, which
  /// is a result and not a gap — a refused variant is an unstable decision.
  final String? letter;

  final String? label;

  /// What the model actually wrote, with the thinking block already stripped.
  ///
  /// Kept **per probe**, not just on the first run, and that is the whole reason
  /// it exists. On a single-variant call the refusal payload carries it and the
  /// user sees why. On a 12-variant call, "2 of 12 produced no answer" says a
  /// count and nothing else: a model that answered six times with prose and six
  /// times with a letter counts identically to one that refused both ways. The
  /// words are what tell them apart.
  ///
  /// Optional and not clipped here — clipping is the endpoint's job, since only
  /// the endpoint knows the response is going out over the wire.
  final String? raw;

  /// Whether this run produced a usable answer at all.
  bool get answered => letter != null;

  /// The **content** the model chose, independent of which letter carried it.
  ///
  /// Comparing labels rather than letters is the whole point: `A→Financeiro` and
  /// `B→Financeiro` are the same decision written twice, and a run that scored
  /// them as different would be measuring the relabelling instead of the model.
  String? get choice => label;
}

/// The verdict over every variant of one question.
class DecisionStability {
  const DecisionStability({
    required this.probes,
    required this.distinct,
    required this.failed,
  });

  final List<DecisionProbe> probes;

  /// How many **different** decisions came back, by label.
  final int distinct;

  /// How many runs produced no answer at all.
  final int failed;

  int get runs => probes.length;

  /// The label that won the most runs. Null when nothing answered.
  String? get leading => _tally.entries.isEmpty
      ? null
      : _tally.entries.first.key;

  /// How many runs agreed with [leading].
  int get leadingRuns => _tally.values.isEmpty ? 0 : _tally.values.first;

  Map<String, int> get _tally {
    final out = <String, int>{};
    for (final p in probes) {
      final c = p.choice;
      if (c == null) continue;
      out[c] = (out[c] ?? 0) + 1;
    }
    // Sort by count desc, then label, so `leading` is deterministic: two labels
    // tied on count would otherwise depend on probe order, and a stability report
    // that changes between two identical runs is a report nobody trusts.
    final entries = out.entries.toList()
      ..sort((a, b) => b.value != a.value
          ? b.value.compareTo(a.value)
          : a.key.compareTo(b.key));
    return Map.fromEntries(entries);
  }

  /// Whether every run that answered picked the same thing.
  ///
  /// False when [failed] is non-zero even if the answers agreed: three votes for
  /// one label out of four attempts is not four out of four, and a run where the
  /// model refused is not a vote for what the others said.
  bool get isStable => failed == 0 && distinct <= 1;

  /// `leadingRuns/runs`, or null when nothing answered.
  ///
  /// Named [agreement] and not `confidence`: it is the share of runs that agreed,
  /// and reading it as a probability is the mistake this file exists to prevent.
  double? get agreement => runs == 0 ? null : leadingRuns / runs;

  /// A one-line verdict for a screen. Pure text, no formatting, no `.tr` — the
  /// caller translates, because a formatted string here would freeze at the boot
  /// locale the way `static const` translations do.
  String describe() {
    if (runs == 0) return 'no runs';
    if (failed == runs) return 'no run produced an answer';
    if (failed > 0) return 'unstable: $failed of $runs produced no answer';
    if (distinct <= 1) return 'stable: $leadingRuns of $runs agreed on $leading';
    return 'unstable: $distinct different answers across $runs runs';
  }
}

/// Summarise the runs of one question.
///
/// Probes are counted by their **content**, not their letter, so a caller may
/// shuffle the options freely between runs. Probes with no answer are counted as
/// failed rather than dropped: dropping them would let a model that answers once
/// and refuses the other three times report perfect stability.
DecisionStability summariseDecisionStability(List<DecisionProbe> probes) {
  final choices = <String>{};
  var failed = 0;
  for (final p in probes) {
    if (p.answered) {
      final c = p.choice;
      if (c != null) choices.add(c);
    } else {
      failed++;
    }
  }
  return DecisionStability(
    probes: List.unmodifiable(probes),
    distinct: choices.length,
    failed: failed,
  );
}

/// How many variants to ask for a set of options.
///
/// The default is the ceiling, and that is a measured decision rather than a
/// cautious one.
///
/// **Rotation was tried first and it is structurally blind to the case that
/// matters.** Rotating `[A B C D]` by one covers **4 of the 24** permutations —
/// `abcd`, `bcda`, `cdab`, `dabc` — and all four live in the same cyclic group.
/// Measured on `d1-3B` with the "where is my second invoice copy" case: the full
/// set splits 18/6, and **none of the 4 rotations was among the 6 that flipped**.
/// Three variants reported `3/3 stable` for a question that is only 75% stable.
///
/// A screen that cannot see the failure it was built to catch is not a cheap
/// version of the test — it is a different test, and it reports the wrong answer
/// with the same confidence. So the default is the whole set up to the ceiling.
const int kDefaultDecisionVariants = kMaxDecisionVariants;

/// The hard ceiling, and what it costs.
///
/// 12 of 24 permutations reaches three of the six that actually flipped, and
/// still fits one question on a phone. The cost is real and measured: a `d1-3B`
/// decision takes **6,6–23,8 s** on the Galaxy A72, so a 12-variant run of a
/// single question is **1,5–4,5 minutos**. That is why this is a test a caller
/// chooses to run, never a default on an interactive path.
const int kMaxDecisionVariants = 12;

/// Permutations of the letters in [letters], capped at [limit].
///
/// **Lehmer order, not rotation** — and that is the whole reason this function
/// changed shape. Lehmer order enumerates permutations by their rank in the
/// factorial number system, so the first N spread across the entire space
/// instead of being drawn from one cyclic subgroup. For four options, limit 12
/// reaches `bacd`, `bcad` and `bdca` — three of the six that flipped — where
/// rotation reaches none of them at any small limit.
///
/// Deterministic: the same question produces the same variants on every run and
/// on every device, so two reports can be compared. And balanced whenever the
/// limit is the full count: each letter visits each position exactly once.
List<Map<String, String>> decisionPermutations(
  Map<String, String> letters, {
  int limit = kDefaultDecisionVariants,
}) {
  if (letters.length < 2) return [Map.of(letters)];
  final keys = letters.keys.toList(growable: false);
  final n = keys.length;
  final total = _fact(n);
  final max = limit > total ? total : limit;

  // **Walk Lehmer ranks with a stride**, not 0,1,2…. Consecutive Lehmer ranks
  // keep the same prefix for a long run — ranks 0-5 all start with `A` — so a
  // plain prefix of that order is a *worse* screen than rotation: it spends the
  // whole budget on one first letter and never varies the thing under test.
  //
  // The stride is the smallest one coprime with n! and at least n, which visits
  // every rank exactly once over a full sweep and spreads the first `limit`
  // evenly. For n=4 the stride is 9 over 24 ranks, and the first 12 land 3 on
  // each starting letter — including `bacd`, `bcad` and `bdca`, three of the six
  // that actually flipped. Measured: the naive order reached **zero** of them.
  final out = <Map<String, String>>[];

  // **Round-robin over first letters, then Lehmer within each.** This is the
  // order the measurement demands, and the measurement is specific.
  //
  // On `d1-3B`, all 6 permutations that flipped had the first letter in **{B,
  // C}** and none had `A` first — and every rotation, which does put each letter
  // first exactly once, drew its first three from that set and still missed them.
  // So spreading on the first letter is necessary and **not sufficient**, but it
  // is the axis the flip set actually separates on: no variant starting with `A`
  // ever flipped. Grouping by first letter and walking Lehmer inside each group
  // guarantees the budget is spent on distinct first letters before it is spent
  // on rearranging the tail.
  //
  // Ranks are laid out so that rank `r` decodes with the first letter cycling
  // through the keys: `rank = group * (n-1)! + tailRank` for group `g`, which is
  // exactly Lehmer's own decomposition — the leading factor counts the first
  // element. So no re-ordering of the enumeration is needed: iterating `group`
  // and `tailRank` in that nesting **is** the balanced walk.
  final perGroup = _fact(n - 1);
  for (var g = 0; g < n && out.length < max; g++) {
    final pool = List<String>.of(keys);
    final head = pool.removeAt(g);
    for (var t = 0; t < perGroup && out.length < max; t++) {
      var r = t;
      final tail = List<String>.of(pool);
      final ordered = <String>[head];
      for (var place = n - 2; place >= 1; place--) {
        final block = _fact(place);
        ordered.add(tail.removeAt(r ~/ block));
        r %= block;
      }
      ordered.add(tail.first);
      out.add({for (final k in ordered) k: letters[k]!});
    }
  }
  return out;
}

// (A `_gcd` and a stride-based walk were both tried here and both removed: the
// stride visited distinct *ranks* but 0 of the 6 permutations that actually flip,
// because it does not control the first letter. The measurement is in the
// doc comment on `decisionPermutations`.)

int _fact(int n) {
  var v = 1;
  for (var i = 2; i <= n; i++) {
    v *= i;
  }
  return v;
}