import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/utils/token_rate.dart';

void main() {
  // The number on the bubble. Two call sites had this wrong in the same shape, and
  // these are the cases that decide whether it ever is again.
  group('endToEndTokensPerSecond', () {
    test('measures from the request, not from the first token', () {
      // 139 tokens in 55.9 s is the Kotlin plugin's real turn on the Edge 60.
      final start = DateTime(2026, 9, 28, 10);
      final rate = endToEndTokensPerSecond(
        tokens: 139,
        start: start,
        now: start.add(const Duration(milliseconds: 55900)),
      );
      expect(rate, closeTo(2.49, 0.01));
    });

    test('a burst at the end cannot report thousands of tokens per second', () {
      // The measurement that motivated the function: 106 tokens all landing in
      // the 21 ms after a blocking call returned. The old denominator started at
      // the first token, so this turned into 5047.6 tok/s on a device whose
      // fastest local model does 3.1.
      final start = DateTime(2026, 9, 28, 10);
      final rate = endToEndTokensPerSecond(
        tokens: 106,
        start: start,
        now: start.add(const Duration(milliseconds: 61980)),
      );
      expect(rate, closeTo(1.71, 0.01));
    });

    test('holds still when the whole turn took no measurable time', () {
      final start = DateTime(2026, 9, 28, 10);
      final rate = endToEndTokensPerSecond(
        tokens: 106,
        start: start,
        now: start,
      );
      expect(rate, 0.0);
    });

    test('is zero for an empty turn rather than NaN or infinity', () {
      final start = DateTime(2026, 9, 28, 10);
      expect(
        endToEndTokensPerSecond(
          tokens: 0,
          start: start,
          now: start.add(const Duration(seconds: 10)),
        ),
        0.0,
      );
    });

    test('goes down as the turn gets longer, not up', () {
      // The old formula had the property that a longer response could report a
      // higher rate, because the window it divided by was the part after the
      // first token and that shrinks to nothing at the end of a burst. This is
      // the property that makes the number worth reading.
      final start = DateTime(2026, 9, 28, 10);
      final short = endToEndTokensPerSecond(
        tokens: 100,
        start: start,
        now: start.add(const Duration(seconds: 10)),
      );
      final long = endToEndTokensPerSecond(
        tokens: 1000,
        start: start,
        now: start.add(const Duration(seconds: 100)),
      );
      expect(short, closeTo(10.0, 0.01));
      expect(long, closeTo(10.0, 0.01));
    });
  });
}
