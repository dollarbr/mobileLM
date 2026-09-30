/// The CPU self-test, and the yardstick every other number is taken against.
///
/// This exists because of one measurement on a Galaxy A72 (Snapdragon 720G, two
/// A76 cores). A 360M model did not return a single token inside the 60 s prefill
/// budget; a 230M one on the same phone, same code, same mode, answered a short
/// turn at about 12 tok/s. Nothing about the gate, the backend or the thread
/// count had changed — only how much arithmetic the prefill owed.
///
/// That gap is the whole reason this file exists. A device that is too slow to
/// answer a useful model is still perfectly measurable, as long as the model
/// used to measure it is small enough that the measurement fits in a budget a
/// human will wait for. And that is the only way to tell a slow phone from a
/// broken one: both look like "no answer" from the outside.
///
/// So: pick the smallest model that can still produce text, ask it something
/// with a known answer, and report what came back. The verdict is deliberately
/// coarse — pass, slow, or fail — because a benchmark that reports a gradient
/// gets read as a regression, and the only thing worth asserting is "the CPU
/// path works and here is how fast".
library;

import 'dart:async';


import '../models/ai_model.dart';

/// How the self-test went.
enum CpuVerdict {
  /// Text came back, comfortably inside the budget.
  ok,

  /// Text came back, but slowly enough that a real model will not.
  slow,

  /// No text. Either the engine is broken or this device is below the floor.
  fail,
}

class CpuSelfTestResult {
  final CpuVerdict verdict;

  /// Null when the model could not be loaded at all.
  final AiModel? model;

  /// Generation rate, tokens per second, end to end. Only meaningful on a pass
  /// or a slow — it is measured across the whole call, so it includes the
  /// prefill, which is the half that actually varies between devices.
  final double? tokensPerSecond;

  /// Time to the first token. On a slow device this is the number that hurts,
  /// and it is the one that explains a slow verdict better than the average.
  final int? ttftMillis;

  /// The answer, trimmed. Present because a self-test that cannot show what it
  /// got is hard to trust when it fails.
  final String? reply;

  /// Why, in a sentence fit for a settings screen.
  final String detail;

  const CpuSelfTestResult({
    required this.verdict,
    this.model,
    this.tokensPerSecond,
    this.ttftMillis,
    this.reply,
    required this.detail,
  });

  bool get passed => verdict != CpuVerdict.fail;
}

/// Which model to test with, given what is actually on disk.
///
/// The catalogue's benchmark wins, because picking it is the point of the flag
/// existing. A benchmark that fell back to "whatever is loaded" would measure
/// the phone with a different ruler every run, and the number would not be
/// comparable to the last one — which is the only reason to keep a benchmark.
/// The model to test with, given the catalogue. Public because the service that
/// runs the test has to resolve it before it can check whether the file exists,
/// and having two resolvers would be two places to keep in sync.
AiModel? pickBenchmarkModel(List<AiModel> available) {
  for (final m in available) {
    if (m.isBenchmark && m.runtime == AiModel.runtimeLlama) return m;
  }
  return null;
}

/// The line below which local models are not worth having on this device.
///
/// 5 tok/s, chosen by the user, and the reasoning is worth writing down because
/// the number looks low and is not. The A72 measures about 12 tok/s on this
/// benchmark, so 5 is roughly where a phone stops being able to keep up with
/// typing-speed reading. The first cut was 15 — about where a chat stops
/// *feeling* like a chat — and that is the version that was wrong: 15 is a taste
/// threshold, and a taste threshold is a bad thing to hide a list of files
/// behind. 5 is closer to a capability boundary, and it still leaves a phone
/// that measures 4 tok/s with its local models intact.
///
/// **It decides what the app suggests, and never what it forbids.** A phone can
/// run a 1B model at 3 tok/s — it will just be unpleasant, and "slow but stays
/// on the device" is the right answer for someone who does not want to send
/// their conversations anywhere. So the suggestion is allowed to be wrong, and
/// the override is one tap in Settings.
const double kCpuUsableTokensPerSecond = 5.0;

/// Below the usable line, the advice is cloud models rather than "slow". Kept
/// separate from the verdict so a device that fails outright is not also told to
/// use the cloud — that is two different problems and one remedy does not fix
/// both.
const int kCpuTtftCeilingMillis = 60000;

/// Pure verdict from the two numbers a run produces. Kept separate from the
/// engine call so it can be tested against real device values, which is how the
/// thresholds above got the numbers they have.
CpuVerdict judgeCpuSelfTest({required int ttftMillis, required double tokensPerSecond}) {
  if (ttftMillis <= 0 || tokensPerSecond <= 0) return CpuVerdict.fail;
  // Both conditions, not either. A device can clear 5 tok/s and still take
  // longer than the prefill budget for the first token, and telling someone
  // their phone is fine when they watched it sit for a minute is the specific
  // thing this measurement exists to avoid.
  if (tokensPerSecond >= kCpuUsableTokensPerSecond &&
      ttftMillis < kCpuTtftCeilingMillis) {
    return CpuVerdict.ok;
  }
  return CpuVerdict.slow;
}

/// Whether a result is good enough to keep the local model list on screen.
///
/// Separate from [judgeCpuSelfTest] on purpose. The verdict describes the CPU;
/// this decides what the app suggests next, and the two are allowed to
/// disagree — a `fail` still routes here so that a device where nothing
/// generated at all also gets the "use the cloud" advice, which is the advice
/// that is actually true for it.
bool benchmarkSaysUseCloudModels(CpuVerdict verdict, double? tokensPerSecond) {
  if (tokensPerSecond == null) return verdict == CpuVerdict.fail;
  return tokensPerSecond < kCpuUsableTokensPerSecond;
}

/// Human-readable summary. Takes the verdict rather than deriving one, so the
/// string and the enum can never disagree.
String describeCpuSelfTest(CpuSelfTestResult r) {
  switch (r.verdict) {
    case CpuVerdict.ok:
      return '${_fmt(r.tokensPerSecond)} tok/s, first token in '
          '${_fmtSec(r.ttftMillis)}';
    case CpuVerdict.slow:
      return '${_fmt(r.tokensPerSecond)} tok/s, first token in '
          '${_fmtSec(r.ttftMillis)}';
    case CpuVerdict.fail:
      return r.detail;
  }
}

String _fmt(double? v) => v == null ? '—' : v.toStringAsFixed(1);
String _fmtSec(int? ms) =>
    ms == null ? '—' : '${(ms / 1000).toStringAsFixed(1)}s';

/// The prompt. Two jobs, and both of them are load-bearing:
///
/// - Short. Every token here is prefill the device pays for before it can
///   answer, and the whole point is to fit inside a budget.
/// - A known answer. "2+2" lets a person see at a glance that the reply is
///   real, and a reply that is a coherent non-answer is distinguishable from
///   garbage, which matters on a 135M model.
///
/// A model this small will not reliably follow instructions, so the pass
/// criterion is "something came back", not "it was right".
const String kCpuSelfTestPrompt = 'Responda em uma palavra: quanto e 2+2?';

/// Runs the self-test against the real engine.
///
/// Everything injectable is a function, so the timing and verdict logic is
/// testable and the llama.cpp call is the only thing that has to be real. That
/// split is deliberate: a mock of a 12 tok/s measurement tests nothing, and the
/// numbers that matter can only come off a device.
class CpuSelfTestRunner {
  /// Resolves a catalogue entry to a file on disk, or null if it is not there.
  /// Injected because this is the part that differs per platform and per
  /// install: the model may be downloaded, absent, or already in use by a chat.
  final Future<String?> Function(AiModel model) resolvePath;

  /// Loads the model. Returns false when it could not be loaded at all.
  final Future<bool> Function(String path, String mode) load;

  /// Generates, reporting each token. Returns the concatenated text.
  final Future<String> Function(String prompt, void Function() onFirstToken)
      generate;

  /// Releases the benchmark model afterwards, so a self-test does not leave the
  /// app holding a 150 MB model the user did not ask for.
  Future<void> Function()? unload;

  CpuSelfTestRunner({
    required this.resolvePath,
    required this.load,
    required this.generate,
    this.unload,
  });

  Future<CpuSelfTestResult> runSelfTest(
    AiModel model, {
    required String mode,
    Stopwatch? clock,
  }) async {
    final sw = clock ?? Stopwatch()..start();
    final path = await resolvePath(model);
    if (path == null || path.isEmpty) {
      return CpuSelfTestResult(
        verdict: CpuVerdict.fail,
        model: model,
        detail: 'The benchmark model is not downloaded yet',
      );
    }

    if (!await load(path, mode)) {
      return CpuSelfTestResult(
        verdict: CpuVerdict.fail,
        model: model,
        detail: 'The engine could not load the benchmark model',
      );
    }
    // Restarted, not continued: the load is the slow half and is not part of
    // what is being measured. A benchmark that included model load would report
    // a number that changes with the SD card, not with the CPU.
    sw
      ..reset()
      ..start();

    var gotFirst = false;
    final text = await generate(kCpuSelfTestPrompt, () => gotFirst = true);
    sw.stop();

    final ttft = gotFirst ? sw.elapsedMilliseconds : -1;
    // Counted by whitespace rather than by a tokenizer: a 135M model can emit
    // odd spacing, and the exact count does not matter next to a 10x
    // difference between devices. What matters is it is a real count and not a
    // constant.
    final tokens = text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
    final tps = ttft > 0 && tokens > 0 ? tokens / (sw.elapsedMilliseconds / 1000) : 0.0;

    final result = CpuSelfTestResult(
      verdict: judgeCpuSelfTest(ttftMillis: ttft, tokensPerSecond: tps),
      model: model,
      tokensPerSecond: tps,
      ttftMillis: ttft > 0 ? ttft : null,
      reply: text.trim().isEmpty ? null : text.trim(),
      detail: '',
    );
    return CpuSelfTestResult(
      verdict: result.verdict,
      model: model,
      tokensPerSecond: result.tokensPerSecond,
      ttftMillis: result.ttftMillis,
      reply: result.reply,
      detail: result.verdict == CpuVerdict.fail
          ? (text.trim().isEmpty
              ? 'The engine ran but produced no text'
              : 'The engine produced something unusable')
          : describeCpuSelfTest(result),
    );
  }
}

/// The catalogue entry every benchmark is measured against. Exposed as a
/// constant so the settings screen and the test agree on the name without
/// either of them reaching into the catalogue list.
///
/// This was the QAD Q4_0 file until 2026-09-29, and the benchmark spent its
/// whole life measuring it. That file loads cleanly, prefills at 263 tok/s, and
/// then emits 24 consecutive token id 0 — the GGUF's own `padding_token_id`,
/// not its EOS — so it answers nothing. A Galaxy A72 reported 0,7 tok/s from it
/// and there was no way to tell that number from a slow phone: the sampler is
/// working perfectly on weights that are wrong. The plain Q4_0 of the same model,
/// 128 bytes away in metadata, answers in the same build on the same device.
const String kBenchmarkModelFilename = 'LFM2.5-230M-Q4_0.gguf';


/// How much text to ask for. Enough to measure a rate over, little enough that
/// a slow phone still finishes: at 12 tok/s this is under two seconds, and at
/// the 1.4 tok/s of a struggling device it is still inside a minute.
const int kCpuSelfTestMaxTokens = 24;

/// Wall-clock ceiling for the whole run — load plus generation. Generous
/// against the prefill budget, because a self-test that gives up early reports
/// "fail" for what is really "slow", and those need different answers.
const Duration kCpuSelfTestTimeout = Duration(minutes: 3);

/// The prompt's system prompt. Empty on purpose.
///
/// This is the A72 lesson applied: the app's real system prompt carries the
/// whole 24-tool catalogue and runs about 500 tokens, and on a 360M model that
/// prefill alone did not fit in 60 s. A self-test that included it would be
/// measuring the agent, not the phone. If the prompt list ever stops being empty
/// the numbers stop meaning what they mean now.
const String kCpuSelfTestSystemPrompt = '';

/// One measured generation.
class CpuSelfTestMeasurement {
  /// Real tokens, as the engine counted them — not words.
  final int tokens;

  /// Milliseconds from the start of the run to the *first* token.
  final int firstTokenMs;

  /// Milliseconds for the whole run, first token included.
  final int totalMs;

  final String text;

  CpuSelfTestMeasurement({
    required this.tokens,
    required this.firstTokenMs,
    required this.totalMs,
    required this.text,
  });

  /// Tokens per second, end to end.
  ///
  /// End to end and not "after the first token", because that is the number the
  /// user experiences: the wait before anything appears is part of how fast the
  /// phone feels, and a rate that starts its clock at the first token flatters
  /// every device by exactly its own prefill time.
  double get tokensPerSecond =>
      (firstTokenMs >= 0 && tokens > 0 && totalMs > 0)
          ? tokens / (totalMs / 1000)
          : 0.0;
}

/// Measure the phone, taking the best of several runs.
///
/// This exists as a free function so the rule can be tested without a phone, a
/// model or an engine — which matters because the rule is the difference
/// between the app keeping its local model list and hiding it.
///
/// Measured on the Galaxy A72, same process, same model, same build, runs
/// seconds apart:
///
///   run 1 (first after the process starts): 0.2 tok/s, 71.4 s to first token
///   run 2 (immediately after):              17.4 tok/s,  0.7 s
///
/// An 87x gap. The cause is the governor, not the engine: `schedutil` raises
/// the big cores on sustained utilisation, and a process that has just been
/// launched is slow to earn it. It is the same wall the compute-thread pinning
/// ran into, seen from the other side.
///
/// A token-counted warm-up does not fix this, and that was measured rather than
/// assumed. Warming with 8 tokens and then measuring gave 0.3 tok/s — 8 tokens
/// at the cold rate is 23 seconds, and the ramp needs longer than that. The
/// ramp is measured in *seconds of load*, so a warm-up sized in tokens does not
/// bound it.
///
/// So the attempts are the warm-up: run it up to [attempts] times and keep the
/// best. On a cold process the first attempt absorbs the ramp and the later ones
/// are warm; on a warm one the first attempt is already the best and the rest
/// are short. Either way the number reported is the phone's real speed.
///
/// Best-of-N is the right direction to be wrong in here. The verdict from a
/// cold run ("0.2 tok/s") is what the app acts on, and its next move is to offer
/// to hide the local catalogue — so under-reporting costs the user their models
/// and over-reporting costs them a slightly wrong idea of their phone.
///
/// `generate` is called [attempts] times. The clock is real wall time, so a test
/// that wants to reproduce the A72 has to actually spend the time.
Future<CpuSelfTestMeasurement> measureGeneration(
  Future<String> Function({
    required int maxTokens,
    void Function(String token)? onToken,
  })
  generate, {
  required int maxTokens,
  int attempts = 3,
}) async {
  CpuSelfTestMeasurement? best;

  for (var i = 0; i < attempts; i++) {
    final sw = Stopwatch()..start();
    var tokens = 0;
    var firstTokenMs = -1;
    final text = await generate(
      maxTokens: maxTokens,
      onToken: (_) {
        if (firstTokenMs < 0) firstTokenMs = sw.elapsedMilliseconds;
        tokens++;
      },
    );
    sw.stop();

    final m = CpuSelfTestMeasurement(
      tokens: tokens,
      firstTokenMs: firstTokenMs,
      totalMs: sw.elapsedMilliseconds,
      text: text,
    );
    if (best == null || m.tokensPerSecond > best.tokensPerSecond) best = m;
  }

  return best!;
}
