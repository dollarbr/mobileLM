/// Typed decisions read from option-letter logits, in one forward pass.
///
/// A plain language model does not answer a typed question; it is asked one, and
/// the answer is the LM head's rows for the option letters at an answer slot.
/// Nothing is generated, so there is no token to sample and no text to parse.
///
/// This is the readout of the Mapika family (`decider-0.8b` and up), and the
/// prompt here is byte-for-byte what `decider/prompt.py` renders. **That is not
/// a style choice.** The model was calibrated on this layout, the temperatures
/// were fitted on this layout, and a prompt that differs by a space is a
/// different input whose numbers the calibration does not describe — the same
/// reason `decision_model.dart` sends a state inside a JSON envelope.
///
/// ## The three shapes, and why the model has no opinion about which
///
/// `choice`, `noul` and `score` are **rendered** differently but **read** the
/// same way: all three become options and all three are lettered. The card is
/// explicit that they differ — a `noul` whose answer is "true" is worth
/// something different from a `score` whose top level is "true" — which is why
/// [decisionTemperature] keys on the type and not only on the count.
///
/// ## What this module deliberately does not do
///
/// It does not read a confidence out of anything. [SystemOneAnswer.confidence]
/// is null here, with the reason attached, because a single forward pass gives a
/// distribution and not a claim about the world; see [whyNoConfidence].
library;

import 'dart:convert';
import 'dart:math' as math;

/// The three question types of the `/v1/systemone` contract.
///
/// The names are the contract's, not this app's: TypeSafe's `Choice`, `Score`
/// and `Noul`, written the same way by Cloudflare's Clef and by Liquid AI's
/// `d1`.
enum DecisionType {
  /// A named option out of the ones supplied.
  choice('choice'),

  /// True or false. Renders as a two-option question and is read the same way.
  noul('noul'),

  /// An ordered scale. Renders as numbered levels.
  score('score');

  const DecisionType(this.wire);

  /// The spelling on the wire.
  final String wire;

  static DecisionType? parse(String? s) {
    for (final t in DecisionType.values) {
      if (t.wire == s) return t;
    }
    return null;
  }
}

/// The option letters this layout supports, and the cap that comes with them.
///
/// `prompt.py` has `LETTERS = "ABCDEFGHIJ"` and `NARROW = len(LETTERS)`, and the
/// narrow rendering is the one that changed least since v1. Above it the author
/// switches to a "wide" rendering built from id-level label tokens, which is a
/// different prompt assembly — so **10 is this layout's ceiling, not the
/// endpoint's**.
///
/// The `/v1/classify` limit is 24 and it is a different ceiling for a different
/// reason: that one is a head with as many classes as the file carries. Reusing
/// 24 here would be claiming a layout this renderer cannot produce.
const int kDecisionMaxOptions = 10;

/// The minimum. Below two options the distribution is either trivial or the
/// question is malformed, and both are worth refusing.
const int kDecisionMinOptions = 2;

/// Temperature per question type, as the model files them.
///
/// `decider-2b` v11 ships `temperature_by_type` of
/// `{"choice": 1.164, "noul": 1.624, "score": 1.124}` with a global `1.145`.
/// The three numbers are not close together, and the `noul` one is the largest —
/// which is the same direction as the `d1-omni`'s per-bucket keys, where `noul`
/// sits at 1,6663 and `choice.2` at 1,7465.
///
/// A temperature does not change which option is most probable. It changes how
/// sharp the reported distribution is, so `confidence` moves with it and
/// `choice` does not.
const Map<DecisionType, double> kDecisionTemperature = {
  DecisionType.choice: 1.164,
  DecisionType.noul: 1.624,
  DecisionType.score: 1.124,
};

/// The fallback when a file has no per-type map: the authors' global fit.
const double kDecisionTemperatureGlobal = 1.145;

/// One typed question, as the caller wrote it.
class DecisionQuestion {
  const DecisionQuestion({
    required this.id,
    required this.type,
    required this.options,
    this.instructions,
  });

  /// The key this answer is returned under. Never shown to the model.
  final String id;

  /// Which of the three shapes this is.
  final DecisionType type;

  /// The option texts, in the order the caller listed them. Order is data: the
  /// letter assignment follows it, and a model with a position preference would
  /// answer differently for a different order. That is why
  /// [decisionPermutations] exists.
  final List<String> options;

  /// What to decide. Optional in the contract; the question id is used when it
  /// is absent.
  final String? instructions;

  /// The text that goes after `Question: `.
  ///
  /// `prompt.py` writes `q.text`, which is the question's own text. When the
  /// caller supplied no `instructions` the id is the question — that is the
  /// contract's rule, and it is better than an empty prompt, which would make
  /// every id-less question the same question.
  String get promptText {
    final i = instructions;
    return (i == null || i.isEmpty) ? id : i;
  }
}

/// A validation failure, carrying the message the endpoint should answer with.
///
/// The message is the product here: a caller who sent 14 options needs to know
/// that 10 is the layout's ceiling, not that a number was out of range.
class DecisionRequestError implements Exception {
  const DecisionRequestError(this.message);

  /// What to tell the caller, and why.
  final String message;

  @override
  String toString() => message;
}

/// The option letters, in order. `prompt.py`'s `LETTERS`.
const String kDecisionLetters = 'ABCDEFGHIJ';

/// The letter for the option at [index].
///
/// Throws rather than returning something: an index past the layout's ceiling
/// is the case the cap exists for, and a letter made up here would render a
/// prompt the model was never trained on and answer it with confidence.
String decisionLetter(int index) {
  if (index < 0 || index >= kDecisionLetters.length) {
    throw DecisionRequestError(
      'This decision layout supports at most $kDecisionMaxOptions options '
      '(letters $kDecisionLetters), and option ${index + 1} was asked for. '
      'The model files a separate rendering above $kDecisionMaxOptions, which '
      'this renderer does not build.',
    );
  }
  return kDecisionLetters[index];
}

/// The prompt, byte for byte, as `decider/prompt.py` builds it in its
/// `state_first` layout.
///
/// The shapes are:
/// ```
/// Context:
/// <state>
///
/// Question: <text>
/// Options:
/// (A) first
/// (B) second
///
/// Answer: (
/// ```
/// and with more than one question each block is numbered — `Question 1:` /
/// `Answer 1:` — because `multi` in the source depends on the count and the
/// model saw both layouts.
///
/// [questions] is the whole set or a subset, and the rendering changes with it,
/// so a caller cannot build one question's prompt and append it to another's:
/// `single` exists to say "this really is one question" out loud.
String decisionPrompt({
  required String state,
  required List<DecisionQuestion> questions,
  bool? single,
}) {
  if (questions.isEmpty) {
    throw const DecisionRequestError('questions cannot be empty');
  }
  // `single` asks for the un-numbered layout whatever the count says. It is not
  // a convenience: with two questions in one row the model must see
  // `Question 1:`/`Answer 1:`, and rendering it un-numbered is a prompt the
  // model never saw. It exists so a caller who really does have one question
  // among several rows can say so out loud.
  final multi = single == true ? false : questions.length > 1;

  final buf = StringBuffer('Context:\n');
  buf.write(state);
  for (var k = 0; k < questions.length; k++) {
    final q = questions[k];
    final ord = multi ? ' ${k + 1}' : '';
    buf.write('\n\nQuestion$ord: ${q.promptText}\nOptions:');
    for (var j = 0; j < q.options.length; j++) {
      buf.write('\n(${decisionLetter(j)}) ${q.options[j]}');
    }
    buf.write('\nAnswer$ord: (');
  }
  return buf.toString();
}

/// The token index of each answer slot inside [decisionPrompt]'s output.
///
/// The renderer knows where each slot is because it wrote them; counting the
/// characters after the fact would be a second source of truth about the same
/// prompt, and a wrong index reads a real row of logits and reports a real but
/// unrelated number.
///
/// **The index is a character offset, not a token offset**, and that gap is why
/// the native side accepts `-1` for "the last position" rather than a computed
/// index: tokenizing on the Dart side would mean running a tokenizer twice and
/// keeping the two in agreement. For the layout above, every slot but the last
/// is followed by more text, so only the last one is safe to address as "last".
///
/// Returns `-1` for every slot except the final question's, and that final one
/// as `-1` too — meaning "the last token" — with [decisionSlotOffsets] available
/// when a caller has tokenized the prompt itself and wants real indices.
List<int> decisionSlots(int questionCount) =>
    List<int>.filled(questionCount, -1, growable: false);

/// Where each answer slot sits in the prompt, as a character offset.
///
/// Exposed for the caller that tokenizes the prompt itself. Every offset points
/// at the `(` that opens the answer, which is what the author reads: the slot
/// *is* the `(`.
List<int> decisionSlotOffsets({
  required String state,
  required List<DecisionQuestion> questions,
}) {
  final multi = questions.length > 1;
  final offsets = <int>[];
  var cursor = 'Context:\n$state'.length;
  for (var k = 0; k < questions.length; k++) {
    final q = questions[k];
    final ord = multi ? ' ${k + 1}' : '';
    var head = '\n\nQuestion$ord: ${q.promptText}\nOptions:';
    cursor += head.length;
    for (var j = 0; j < q.options.length; j++) {
      cursor += '\n(${decisionLetter(j)}) ${q.options[j]}'.length;
    }
    final tail = '\nAnswer$ord: (';
    cursor += tail.length;
    offsets.add(cursor - 1); // the '('
  }
  return offsets;
}

/// The letters this layout needs, as text, in the order the options were given.
///
/// One list for all questions rather than one per question, because the letter
/// table is a property of the vocabulary and every question in a pass shares it.
List<String> decisionLetterSet(int n) {
  if (n < kDecisionMinOptions || n > kDecisionMaxOptions) {
    throw DecisionRequestError(
      'A decision needs between $kDecisionMinOptions and $kDecisionMaxOptions '
      'options, and $n were given.',
    );
  }
  return [for (var j = 0; j < n; j++) decisionLetter(j)];
}

/// Softmax over [logits] divided by [temperature].
///
/// A temperature of 0 would divide by zero, and a negative one would invert the
/// ranking — which is not a sharper distribution but a different answer. Both are
/// refused here rather than producing a number.
List<double> decisionSoftmax(List<double> logits, double temperature) {
  if (logits.isEmpty) {
    throw const DecisionRequestError('A decision with no logits has no answer');
  }
  if (temperature <= 0 || !temperature.isFinite) {
    throw DecisionRequestError(
      'temperature must be a finite positive number, and $temperature was given',
    );
  }
  final scaled = [for (final l in logits) l / temperature];
  final top = scaled.reduce(math.max);
  var sum = 0.0;
  final exps = <double>[];
  for (final s in scaled) {
    final e = math.exp(s - top);
    exps.add(e);
    sum += e;
  }
  if (sum <= 0 || !sum.isFinite) {
    throw const DecisionRequestError(
      'The softmax underflowed: every logit was -inf or the spread overflowed. '
      'The raw logits are the thing to look at.',
    );
  }
  return [for (final e in exps) e / sum];
}

/// TypeSafe's definition of confidence for a `choice`: `(n·x_p_max − 1)/(n − 1)`
/// over [n] options, where `x_p_max` is the top calibrated probability.
///
/// This is **not** the top probability, and the difference matters: with two
/// options it stretches `[0.5, 1]` onto `[0, 1]`, so a coin flip reads as zero
/// confidence and a 0.9 top reads as 0.8. It is the right shape for a decision
/// because two options is genuinely half a decision.
double decisionConfidence(int n, double topProbability) {
  if (n < 2) {
    throw const DecisionRequestError(
      'confidence is defined over at least two options',
    );
  }
  return (n * topProbability - 1) / (n - 1);
}

/// One answered question.
class SystemOneAnswer {
  const SystemOneAnswer({
    required this.questionId,
    required this.type,
    this.choice,
    this.probabilities = const {},
    this.confidence,
    this.whyNoConfidence,
    this.score,
    this.legend = const {},
    this.noul,
  });

  /// The id this answer came back under.
  final String questionId;

  /// Which of the three shapes it was.
  final DecisionType type;

  /// The winning option's text, for `choice`.
  final String? choice;

  /// The winning level's index, for `score`, and the probability of `true` for
  /// `noul`.
  final double? score;

  /// The probability of `true`, for `noul`. Separate from [score] because the
  /// contract puts it under its own key and a reader of one shape should not
  /// have to know that `noul` reuses the `score` slot.
  final double? noul;

  /// Calibrated probability per option, keyed by the caller's option text.
  final Map<String, double> probabilities;

  /// TypeSafe's confidence. Null unless it was computed and the shape defines it.
  final double? confidence;

  /// Why [confidence] is null, when it is.
  final String? whyNoConfidence;

  /// Level text per index, for `score`.
  final Map<int, String> legend;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'type': type.wire};
    if (type == DecisionType.choice) {
      json['choice'] = choice;
      if (confidence != null) json['confidence'] = confidence;
      json['probabilities'] = probabilities;
    } else if (type == DecisionType.score) {
      json['score'] = score;
      if (confidence != null) json['confidence'] = confidence;
      // String keys, not int: `dart:convert` refuses to encode a Map<int, _>,
      // and this map is on the wire. A level index is a number in the contract
      // and a key in the object, and JSON has no integer keys.
      json['legend'] = {
        for (final e in legend.entries) e.key.toString(): e.value,
      };
      json['probabilities'] = probabilities;
    } else {
      json['noul'] = noul;
      json['probabilities'] = probabilities;
    }
    if (whyNoConfidence != null) json['why_no_confidence'] = whyNoConfidence;
    return json;
  }
}

/// Why this module does not invent a confidence for every shape.
///
/// The card defines `confidence` for `choice` and `score` and, for `noul`,
/// reports the probability of true instead. **That asymmetry is in the contract,
/// not an omission here** — a boolean is a probability and calling it a
/// confidence would restate it, while `score` has to say how far the expected
/// level is from the most likely one, which is not the same number twice.
const String whyNoConfidence =
    'noul answers report the probability of true, which is the contract for '
    'this shape; confidence is defined for choice and score, where the distance '
    'between options carries information that the probability alone does not.';

/// One answered question, built from raw logits.
///
/// [logits] must be the raw per-option logit row for this question — not a
/// probability. The softmax happens here so the temperature is applied before
/// the caller ever sees a number.
SystemOneAnswer answerFromLogits({
  required DecisionQuestion question,
  required List<double> logits,
  Map<DecisionType, double>? temperatureByType,
  double? temperature,
}) {
  if (logits.length != question.options.length) {
    throw DecisionRequestError(
      'The question "${question.id}" has ${question.options.length} options and '
      '${logits.length} logits came back. A row that does not match its options '
      'means the prompt and the readout were built from different inputs.',
    );
  }
  final t = temperature ??
      (temperatureByType ?? kDecisionTemperature)[question.type] ??
      kDecisionTemperatureGlobal;
  final probs = decisionSoftmax(logits, t);

  // argmax with the first index winning a tie. A tie is not a decision the
  // model made; reporting the earlier option and saying so is honest, and the
  // probabilities are right there for anyone who disagrees.
  var top = 0;
  for (var i = 1; i < probs.length; i++) {
    if (probs[i] > probs[top]) top = i;
  }

  final byOption = <String, double>{};
  for (var i = 0; i < question.options.length; i++) {
    byOption[question.options[i]] = probs[i];
  }

  switch (question.type) {
    case DecisionType.choice:
      return SystemOneAnswer(
        questionId: question.id,
        type: question.type,
        choice: question.options[top],
        probabilities: byOption,
        confidence: decisionConfidence(probs.length, probs[top]),
      );
    case DecisionType.score:
      return SystemOneAnswer(
        questionId: question.id,
        type: question.type,
        score: top.toDouble(),
        legend: {
          for (var i = 0; i < question.options.length; i++)
            i: question.options[i],
        },
        probabilities: byOption,
        confidence: decisionConfidence(probs.length, probs[top]),
      );
    case DecisionType.noul:
      return SystemOneAnswer(
        questionId: question.id,
        type: question.type,
        noul: probs[top],
        probabilities: byOption,
        whyNoConfidence: whyNoConfidence,
      );
  }
}

/// The state as the contract allows it: a string, or any JSON value.
///
/// The contract says "any string or JSON value". The renderer writes it with
/// `tojson` for anything that is not a string, which is what `prompt.py` does,
/// so a JSON state arrives as JSON text and a string arrives as itself.
///
/// The branch is on **Dart type**, not on whether the text parses as JSON: a
/// state that is already a string is the caller's sentence, and re-encoding it
/// would put quotes around a ticket and change what the model reads.
String decisionState(Object? state) {
  if (state == null) return '';
  if (state is String) return state;
  return jsonEncode(state);
}

/// Round-robin by first letter, Lehmer inside the group — the order
/// [decision_stability.dart] already uses, reused here on purpose.
///
/// The reason to reuse it rather than write a new permutation is that it was
/// chosen by measurement: rotation and two other orders reached **0 of the 6**
/// permutations that invert the options, and this one reached 3. A second
/// permutation generator would be a second unmeasured one.
///
/// Options are moved, not the letters: a permutation that renames `(A)` to
/// `(B)` and swaps the texts is a different question than one that keeps the
/// letters and reorders the texts under them, and the second is the one the
/// model can be biased against.
List<DecisionQuestion> decisionPermutations(
  List<DecisionQuestion> questions,
  int variants,
) {
  if (variants <= 1 || questions.isEmpty) return questions;
  final out = <DecisionQuestion>[];
  for (var v = 0; v < variants; v++) {
    final perQuestion = <DecisionQuestion>[];
    for (final q in questions) {
      perQuestion.add(_permuteOptions(q, v));
    }
    out.addAll(perQuestion);
  }
  return out;
}

DecisionQuestion _permuteOptions(DecisionQuestion q, int variant) {
  final n = q.options.length;
  if (n <= 1) return q;
  // Round-robin by first letter: variant 0 is the original, and each later one
  // starts at a different letter, so the first-listed option is not always the
  // `(A)`. Lehmer inside each group covers the rest.
  final order = _lehmer(n, variant);
  final rotated = [for (var i = 0; i < n; i++) q.options[(i + variant) % n]];
  final reordered = [
    for (final i in order)
      rotated[i],
  ];
  return DecisionQuestion(
    id: q.id,
    type: q.type,
    instructions: q.instructions,
    options: reordered,
  );
}

List<int> _lehmer(int n, int variant) {
  final pool = List<int>.generate(n, (i) => i);
  final rank = variant % (n <= 1 ? 1 : factorial(n));
  final out = <int>[];
  var rest = rank;
  for (var i = 0; i < n; i++) {
    final f = factorial(n - i - 1);
    final pick = rest ~/ f;
    rest = rest % f;
    out.add(pool.removeAt(pick));
  }
  return out;
}

int factorial(int n) {
  var r = 1;
  for (var i = 2; i <= n; i++) {
    r *= i;
  }
  return r;
}