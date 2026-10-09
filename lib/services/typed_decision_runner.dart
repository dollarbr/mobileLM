import 'package:llama_flutter_android/llama_flutter_android.dart';

import 'typed_decision.dart';

/// Runs typed decisions against the loaded model, and turns logits into the
/// `/v1/systemone` answer shape.
///
/// ## One pass per question, and why that is not a shortcut
///
/// `decider/prompt.py` can pack every question into one row and read all the
/// slots, and that is roughly half the latency. It is not what this does, for a
/// reason that is not laziness: **the slot index is a token position, and this
/// module never tokenizes the prompt.** The renderer knows where each `(` is in
/// *characters*; turning that into a token index means running the model's
/// tokenizer over the prompt, and then two things have to stay in agreement
/// about the same string. The single-question layout ends at its own answer
/// slot, so `-1` — "the last token" — is exact, and the ambiguity disappears.
///
/// The cost is one forward pass per question instead of one per request. On the
/// A72 that is the difference between a prompt that answers in a few hundred
/// milliseconds and one that answers in as many, which is a real regression. The
/// fix is not to guess a token index: it is to have [LlamaDecision.tokenIdsFor]
/// also able to report the token count of a prefix, and then the packed row
/// becomes provable. That is the honest shape of the remaining work.
///
/// ## The order of operations, and why it is that order
///
/// 1. **Validate the options against the letters.** Before the model is touched,
///    because a letter past the layout's ceiling is a fact about the request.
/// 2. **Resolve the letter ids.** Before the prompt is built, because a letter
///    that is not one token means no valid prompt exists — building it anyway
///    would send the model a prompt whose answer slot cannot be read.
/// 3. **Build the prompt, decode, read logits.**
/// 4. **Calibrate in Dart.** Temperature and softmax happen after the logits
///    cross the boundary, never in C++.
class TypedDecisionRunner {
  const TypedDecisionRunner();

  /// The letter ids for [letters], or the reason there are not any.
  ///
  /// Cached per call rather than per runner: the letter table is a property of
  /// the loaded vocabulary, and the runner does not know which file is loaded.
  /// Ten tokenization calls are microseconds; a cache keyed on nothing is a
  /// cache that survives a model swap and answers for the wrong file.
  Future<List<int>> _letterIds(List<String> letters) async {
    final ids = <int>[];
    for (final letter in letters) {
      final one = await LlamaDecision.tokenIdsFor(letter);
      if (one == null || !one.isSingle) {
        final count = one?.tokenCount ?? 0;
        throw DecisionUnavailable(
          'The letter "$letter" is $count token${count == 1 ? '' : 's'} in '
          "this model's vocabulary, not one. A decision is read by restricting "
          'the LM head to single-letter tokens, so a letter that splits has no '
          'logit to read and the prompt cannot be built. This is a property of '
          'the loaded file, not of the request.',
        );
      }
      ids.add(one.id);
    }
    return ids;
  }

  /// Every distinct letter across every question, in first-seen order.
  ///
  /// Two questions with three options each ask for six letters but there are
  /// only three distinct ones, and `tokenizeSingle` is cheap but not free. The
  /// order matters: it is the index into the pass's flat row, so it has to be
  /// the same order on every call.
  List<String> _distinctLetters(List<List<String>> perQuestion) {
    final distinct = <String>[];
    final seen = <String>{};
    for (final letters in perQuestion) {
      for (final l in letters) {
        if (seen.add(l)) distinct.add(l);
      }
    }
    return distinct;
  }

  /// Answer [questions] about [state].
  ///
  /// [state] is the contract's "any string or JSON value"; [decisionState] does
  /// the rendering.
  ///
  /// Each question is scored in its own forward pass, so the rows come back one
  /// per question in the order given. [temperatureByType] overrides the module's
  /// per-type fit, and a file that carries no calibration at all falls to
  /// [kDecisionTemperatureGlobal] — which is what [answerFromLogits] already
  /// does, and why this does not carry a table of its own.
  Future<TypedDecisionResult> run({
    required Object? state,
    required List<DecisionQuestion> questions,
    Map<DecisionType, double>? temperatureByType,
    double? temperature,
  }) async {
    if (questions.isEmpty) {
      throw const DecisionRequestError('questions cannot be empty');
    }

    // Validate first, so the caller hears about a ceiling it cannot fix before
    // the model is touched. `decisionPrompt` would also throw, but only after
    // the letter ids were resolved, and the ids are the part that talks to the
    // device.
    final lettersPerQuestion = <List<String>>[];
    for (final q in questions) {
      lettersPerQuestion.add(decisionLetterSet(q.options.length));
    }

    final distinct = _distinctLetters(lettersPerQuestion);
    final allIds = await _letterIds(distinct);
    final stateText = decisionState(state);

    final answers = <SystemOneAnswer>[];
    var totalMs = 0;
    for (var k = 0; k < questions.length; k++) {
      final q = questions[k];
      // One question per pass, so the layout is the un-numbered one and the
      // slot is the last token. See the class comment for why this is not a
      // shortcut.
      final prompt = decisionPrompt(
        state: stateText,
        questions: [q],
        single: true,
      );
      final pass = await LlamaDecision.decisionScores(
        prompt: prompt,
        slotIndices: decisionSlots(1),
        tokenIds: allIds,
      );
      totalMs += pass.elapsedMs;

      // The pass reads every distinct letter, because one `llama_decode` cannot
      // know which ones this question wants. Slicing by the letter's position in
      // `distinct` is what keeps the row in **this question's option order**,
      // which is the order the letters were assigned in — reading the pass
      // straight into `answerFromLogits` would score option B's probability
      // against option A's text whenever two questions shared a letter.
      final row = <double>[];
      for (final l in decisionLetterSet(q.options.length)) {
        final pos = distinct.indexOf(l);
        if (pos < 0 || pos >= allIds.length) {
          throw DecisionUnavailable(
            'The letter "$l" for question "${q.id}" has no logit in the pass. '
            'The candidate list and the question were built from different '
            'inputs.',
          );
        }
        row.add(pass.scores[pos]);
      }

      answers.add(answerFromLogits(
        question: q,
        logits: row,
        temperatureByType: temperatureByType,
        temperature: temperature,
      ));
    }

    return TypedDecisionResult(answers: answers, elapsedMs: totalMs);
  }
}

/// The answers to a set of typed questions, and what the passes cost.
class TypedDecisionResult {
  const TypedDecisionResult({required this.answers, required this.elapsedMs});

  /// One answer per question, in the order they were asked.
  final List<SystemOneAnswer> answers;

  /// Total wall-clock across every forward pass.
  final int elapsedMs;

  /// The contract's `answers` object, keyed by question id.
  ///
  /// A duplicate id would silently drop an answer, because a JSON object cannot
  /// hold two values under one key. The runner keeps order, so the first wins
  /// here and the count mismatch is visible in [answers] — but a caller sending
  /// duplicate ids is sending a request whose response cannot say everything it
  /// asked, and that is worth a name rather than a silent drop.
  Map<String, dynamic> toJson() {
    final seen = <String>{};
    final out = <String, dynamic>{};
    for (final a in answers) {
      if (seen.contains(a.questionId)) continue;
      seen.add(a.questionId);
      out[a.questionId] = a.toJson();
    }
    return out;
  }

  /// Ids that appeared more than once, in first-seen order.
  List<String> get duplicateIds {
    final counts = <String, int>{};
    for (final a in answers) {
      counts[a.questionId] = (counts[a.questionId] ?? 0) + 1;
    }
    return counts.entries
        .where((e) => e.value > 1)
        .map((e) => e.key)
        .toList();
  }
}