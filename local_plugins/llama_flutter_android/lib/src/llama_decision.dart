import 'package:flutter/services.dart';

/// Typed decisions, read from option-letter logits in one forward pass.
///
/// A plain language model does not answer a typed question; it is asked one,
/// and the answer is the LM head's rows for the option letters at an answer
/// slot. Nothing is generated, so there is no token to sample and no text to
/// parse.
///
/// This is the same primitive [LlamaEncoder] uses — one token's logit at one
/// position — generalised to N tokens at N positions. The rerank path reads the
/// logit of `yes` and `no`; a decision reads the logits of `A` through `J`.
///
/// ## Why two calls and not one
///
/// [tokenIds] has to exist because a decision readout is defined over **token
/// ids**, and a caller cannot invent them: `A` is one token in one vocabulary and
/// two in another. Folding the tokenization into [decisionScores] would move
/// that check into C++, where the error could only say "something failed";
/// keeping it here means the caller can say *"B is two tokens in this
/// vocabulary"*, which is a fact about the model worth reporting.
///
/// ## What crosses the boundary
///
/// Raw logits, in the order asked, and nothing else. Temperature, bucket
/// selection and the softmax are policy, and policy in C++ cannot be tested
/// without a device — so the calibration lives in `typed_decision.dart`, where
/// there are 46 tests for it.
class LlamaDecision {
  static const _channel = MethodChannel('llama_flutter_android/model_meta');

  /// The one token id for [text], or null when it is not one token.
  ///
  /// [tokenCount] distinguishes "it is two tokens" from "it is zero", which are
  /// different problems with different fixes. A letter that is two tokens is a
  /// vocabulary; an empty string is a caller.
  ///
  /// Synchronous on purpose. It is tokenization, not a forward pass, and the
  /// answer decides whether a valid prompt can be built at all — turning this
  /// into a future the caller awaits N of before sending anything adds a round
  /// trip per option for no gain.
  static Future<SingleToken?> tokenIdsFor(String text) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'tokenizeSingle',
        {'text': text},
      );
      if (res == null) return null;
      final id = (res['id'] as num?)?.toInt() ?? -1;
      final count = (res['tokenCount'] as num?)?.toInt() ?? 0;
      if (id < 0) return SingleToken.notSingle(count);
      return SingleToken(id, count);
    } on PlatformException catch (e) {
      throw DecisionUnavailable(e.message ?? e.toString());
    } on MissingPluginException {
      throw const DecisionUnavailable(
          'The native library is not available on this platform.');
    }
  }

  /// The logit of each id in [tokenIds] at each slot, in one forward pass.
  ///
  /// [slotIndices] are token positions in [prompt]. `-1` means the last one, and
  /// a caller whose prompt ends at its answer slot should send that rather than
  /// counting tokens: the count is a second source of truth about the same
  /// prompt, and a wrong index reads a real row of logits and reports a real but
  /// unrelated number.
  ///
  /// The result is **slot-major** — slot 0's candidates first, then slot 1's —
  /// because that is the order the flagged positions are renumbered into.
  ///
  /// Throws [DecisionUnavailable] when the loaded model is an encoder, which
  /// has no vocab-sized output to read a letter from.
  static Future<DecisionPass> decisionScores({
    required String prompt,
    required List<int> slotIndices,
    required List<int> tokenIds,
  }) async {
    if (slotIndices.isEmpty) {
      throw const DecisionUnavailable(
          'slotIndices is required and cannot be empty: a decision with no '
          'answer slot has nothing to read.');
    }
    if (tokenIds.isEmpty) {
      throw const DecisionUnavailable(
          'tokenIds is required and cannot be empty: a decision with no '
          'candidate tokens has nothing to read.');
    }
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'decisionScores',
        {
          'prompt': prompt,
          'slotIndices': slotIndices,
          'tokenIds': tokenIds,
        },
      );
      if (res == null) {
        throw const DecisionUnavailable('The decision pass returned nothing.');
      }
      final scores = (res['scores'] as List?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const <double>[];
      final slots = (res['slots'] as num?)?.toInt() ?? slotIndices.length;
      final candidates = (res['candidates'] as num?)?.toInt() ?? tokenIds.length;
      final expected = slots * candidates;
      if (scores.length != expected) {
        // A row count that does not match the request means the readout and the
        // prompt came from different places, and a silently truncated list would
        // be scored against the wrong option. Name both numbers.
        throw DecisionUnavailable(
          'The decision pass returned ${scores.length} logits for $expected '
          'asked for ($slots slots x $candidates candidates). The prompt and '
          'the candidate list were built from different inputs.',
        );
      }
      return DecisionPass(
        scores: scores,
        slots: slots,
        candidates: candidates,
        elapsedMs: (res['elapsedMs'] as num?)?.toInt() ?? 0,
      );
    } on PlatformException catch (e) {
      throw DecisionUnavailable(e.message ?? e.toString());
    } on MissingPluginException {
      throw const DecisionUnavailable(
          'The native library is not available on this platform.');
    }
  }
}

/// The token id for a string, or the reason there is not one.
class SingleToken {
  const SingleToken(this.id, this.tokenCount) : isSingle = true;

  /// The string is not one token. [tokenCount] is how many it is.
  const SingleToken.notSingle(this.tokenCount) : id = -1, isSingle = false;

  /// The id, or -1 when [isSingle] is false.
  final int id;

  /// How many tokens the string is.
  final int tokenCount;

  /// Whether [id] is usable as a candidate.
  final bool isSingle;

  @override
  String toString() =>
      isSingle ? 'SingleToken($id)' : 'SingleToken(not single, $tokenCount)';
}

/// One decision pass: raw logits, slot-major.
class DecisionPass {
  const DecisionPass({
    required this.scores,
    required this.slots,
    required this.candidates,
    required this.elapsedMs,
  });

  /// Slot 0's candidates, then slot 1's, then slot 2's. Raw logits: no softmax
  /// has happened and no temperature has been applied.
  final List<double> scores;

  /// How many answer slots were read.
  final int slots;

  /// How many candidates each slot had.
  final int candidates;

  /// Wall-clock for the decode.
  final int elapsedMs;

  /// The logits for one slot.
  List<double> row(int slot) {
    if (slot < 0 || slot >= slots) {
      throw RangeError.range(slot, 0, slots - 1, 'slot',
          'the pass read $slots slots');
    }
    final start = slot * candidates;
    return scores.sublist(start, start + candidates);
  }
}

/// The decision path cannot run: no model, an encoder, a malformed prompt, or a
/// letter the vocabulary does not have.
class DecisionUnavailable implements Exception {
  const DecisionUnavailable(this.message);

  /// What to tell the caller, and why.
  final String message;

  @override
  String toString() => 'DecisionUnavailable: $message';
}