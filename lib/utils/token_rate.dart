/// Tokens per second, measured end to end.
///
/// Extracted from two call sites that had the same bug in the same shape, and a
/// number this wrong is worth naming once rather than fixing twice.
///
/// ## The bug this exists to prevent
///
/// The obvious denominator is "time since the first token", on the reasoning that
/// the first token is when generation starts. It is not: it is when generation
/// *ends*, minus the prefill. And because the numerator counts tokens that have
/// already arrived, the ratio is measured over a window that shrinks to nothing
/// as the response completes. A stream that finishes is a stream whose window is
/// shortest, so the number goes **up** as the answer gets shorter.
///
/// Measured on a real turn of the LiteRT-LM path, all 106 tokens landed in the
/// 21 ms after a blocking call returned:
///
/// ```text
/// 106 tokens / 0.021 s = 5047.6 tok/s   ← what the bubble said
/// 106 tokens / 61.98 s = 1.71 tok/s     ← what the phone was doing
/// ```
///
/// The device's fastest local model does 3.1 tok/s. The bubble was reporting a
/// number 1600× faster than anything the engine can produce, and it was
/// *pre-existing* — it affects the llama.cpp path, the Kotlin plugin and the cloud
/// path identically, which is why it went unnoticed for this long: every route
/// has a burst at the end somewhere, and no single one made it look like a
/// rounding error.
///
/// ## The rule
///
/// [start] is when the **request** was made. Prefill, time-to-first-token and
/// generation are all part of what the user waited for, so all of them belong in
/// the denominator. This is the number to compare between two phones or two
/// models, because it is the number that describes the wait.
///
/// The cost is that it is not the engine's steady-state decode rate, and that is
/// correct: steady-state rate is not what anyone experiences. Time to first token
/// is already recorded and displayed separately, so nothing is lost by folding
/// it in here.
///
/// Returns 0.0 rather than infinity when [now] has not advanced past [start] —
/// two `DateTime.now()` calls inside the same microsecond are a real thing on a
/// fast phone, and a bubble that says "∞ tok/s" is worse than one that says 0.
double endToEndTokensPerSecond({
  required int tokens,
  required DateTime start,
  required DateTime now,
}) {
  if (tokens <= 0) return 0.0;
  final seconds = now.difference(start).inMicroseconds / 1000000.0;
  if (seconds <= 0) return 0.0;
  return tokens / seconds;
}
