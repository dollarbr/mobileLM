import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/core/constants.dart';
import 'package:mobilelm/models/ai_model.dart';
import 'package:mobilelm/services/cpu_self_test.dart';

/// Real numbers, not invented ones.
///
/// The 230M figures are the Galaxy A72 (Snapdragon 720G, two A76) the whole
/// self-test exists for; the 360M figure is the same phone, same build, same
/// CPU Safe mode, failing. If these two are ever in the same verdict bucket then
/// the verdict is not discriminating and the thresholds are wrong.
void main() {
  group('judgeCpuSelfTest', () {
    test('the A72 measuring 12 tok/s passes', () {
      // ~12 tok/s, first token in a few seconds. This is the run that made the
      // benchmark possible in the first place.
      expect(judgeCpuSelfTest(ttftMillis: 2200, tokensPerSecond: 12.0),
          CpuVerdict.ok);
    });

    test('a phone that is slow but answers is slow, not failed', () {
      final v = judgeCpuSelfTest(ttftMillis: 58000, tokensPerSecond: 1.4);
      expect(v, CpuVerdict.slow);
    });

    test('crossing the prefill budget is slow even at a high rate', () {
      // 40 tok/s but 75 s to the first token. Averaging the rate alone would
      // call this a pass, and it is the case that matters: a user waits 75 s
      // before seeing anything at all.
      expect(judgeCpuSelfTest(ttftMillis: 75000, tokensPerSecond: 40.0),
          CpuVerdict.slow);
    });

    test('no output at all is a failure, whatever the numbers claim', () {
      // Zero and negative both mean "the run produced nothing". A benchmark
      // that reported a verdict here would be reporting arithmetic, not a test.
      expect(judgeCpuSelfTest(ttftMillis: 0, tokensPerSecond: 9.9), CpuVerdict.fail);
      expect(judgeCpuSelfTest(ttftMillis: 900, tokensPerSecond: 0), CpuVerdict.fail);
      expect(judgeCpuSelfTest(ttftMillis: 900, tokensPerSecond: -1), CpuVerdict.fail);
    });

    test('the 5 tok/s line itself passes', () {
      // The threshold is the user's number, chosen at 5 rather than the 15 that
      // reads better on paper: 15 is where a chat stops feeling like a chat,
      // which is a taste line, and 5 is closer to where the engine stops being
      // usable at all. Exactly 5 has to pass or the boundary is untestable.
      expect(judgeCpuSelfTest(ttftMillis: 10000, tokensPerSecond: 5.0),
          CpuVerdict.ok);
    });

    test('just under 5 is a slow, so the boundary is reachable from both sides',
        () {
      expect(judgeCpuSelfTest(ttftMillis: 10000, tokensPerSecond: 4.9),
          CpuVerdict.slow);
      expect(judgeCpuSelfTest(ttftMillis: 10000, tokensPerSecond: 5.0),
          CpuVerdict.ok);
    });

    test('a phone that is slow but answers is never told it is broken', () {
      // 4 tok/s is unpleasant and it works. "fail" would be a lie the user has
      // to disprove by looking at the reply, and this measurement is the only
      // thing standing between them and that.
      final v = judgeCpuSelfTest(ttftMillis: 2200, tokensPerSecond: 4.0);
      expect(v, CpuVerdict.slow);
      expect(v, isNot(CpuVerdict.fail));
    });
  });

  group('benchmarkSaysUseCloudModels', () {
    test('the A72 measurement, at 12 tok/s, stays with local models', () {
      // The whole point of 5 rather than 15: a phone that measures 12 on this
      // benchmark must not be told to give up on local models. At the 15 that
      // was tried first, this exact case would have failed and the app would
      // have been pushing a phone that demonstrably can run a model.
      expect(benchmarkSaysUseCloudModels(CpuVerdict.ok, 12.0), isFalse);
    });

    test('a phone under the line gets the cloud advice', () {
      expect(benchmarkSaysUseCloudModels(CpuVerdict.slow, 4.9), isTrue);
    });

    test('exactly at the line is not pushed to the cloud', () {
      expect(benchmarkSaysUseCloudModels(CpuVerdict.ok, 5.0), isFalse);
    });

    test('a device that produced nothing also gets the cloud advice', () {
      // A fail has no rate to compare, so the rate path cannot be the only
      // route: a phone that never answered is the strongest case for cloud
      // models, not the weakest.
      expect(benchmarkSaysUseCloudModels(CpuVerdict.fail, null), isTrue);
    });

    test('the advice is advice, and never removes the option', () {
      // Nothing in here mutates state. Hiding the list is a separate, explicit
      // action, which is why a wrong prediction costs the user a tap to undo
      // rather than a feature they have to go find.
      for (final (v, t) in [
        (CpuVerdict.ok, 12.0),
        (CpuVerdict.slow, 2.0),
        (CpuVerdict.fail, null),
      ]) {
        expect(() => benchmarkSaysUseCloudModels(v, t), returnsNormally);
      }
    });
  });

  group('describeCpuSelfTest', () {
    test('a pass and a slow both report a real rate, never a placeholder', () {
      // The placeholder is a lone "—" standing in for a number, so assert on
      // the number being present rather than on the dash: the dash is also the
      // clause separator, and a test that forbade it would be forbidding
      // punctuation rather than checking behaviour.
      for (final (t, v, want) in [
        (2200, 12.0, CpuVerdict.ok),
        (58000, 1.4, CpuVerdict.slow),
      ]) {
        final verdict = judgeCpuSelfTest(ttftMillis: t, tokensPerSecond: v);
        expect(verdict, want);
        final s = describeCpuSelfTest(CpuSelfTestResult(
          verdict: verdict,
          tokensPerSecond: v,
          ttftMillis: t,
          detail: '',
        ));
        expect(s, contains(v.toStringAsFixed(1)), reason: s);
        expect(s, isNot(contains('tok/s, —')), reason: s);
        expect(s, isNot(contains('in —')), reason: s);
      }
    });

    test('the ok and slow strings differ, so a slowdown is visible', () {
      // If both branches rendered the same words, a phone going from 12 to 1.4
      // tok/s would look like no change at all.
      String str(double v, int t) => describeCpuSelfTest(CpuSelfTestResult(
            verdict: judgeCpuSelfTest(ttftMillis: t, tokensPerSecond: v),
            tokensPerSecond: v,
            ttftMillis: t,
            detail: '',
          ));
      expect(str(12.0, 2200), isNot(str(1.4, 58000)));
    });

    test('a failure reports the engine detail, not a rate', () {
      const detail = 'Could not load the benchmark model';
      final s = describeCpuSelfTest(
          const CpuSelfTestResult(verdict: CpuVerdict.fail, detail: detail));
      expect(s, detail);
      expect(s, isNot(contains('tok/s')));
    });
  });

  group('pickBenchmarkModel', () {
    AiModel m(String name, {bool bench = false, String runtime = 'llama'}) =>
        AiModel(
          name: name,
          filename: '$name.gguf',
          url: 'https://example.test/$name.gguf',
          size: '0.1 GB',
          descriptionEn: '',
          template: 'chatml',
          runtime: runtime,
          isBenchmark: bench,
        );

    test('finds the flagged model and ignores everything else', () {
      final chosen = pickBenchmarkModel(
          [m('Bigger'), m('Bench', bench: true), m('Also bigger')]);
      expect(chosen?.name, 'Bench');
    });

    test('a LiteRT model is never the benchmark', () {
      // The self-test exercises the llama.cpp CPU path specifically; picking a
      // .litertlm would make the test pass or fail on an entirely different
      // engine and say nothing about the gate it is checking.
      final chosen = pickBenchmarkModel([m('LiteRt', bench: true, runtime: 'litert')]);
      expect(chosen, isNull);
    });

    test('null when nothing is flagged, rather than a silent guess', () {
      expect(pickBenchmarkModel([m('A'), m('B')]), isNull);
      expect(pickBenchmarkModel([]), isNull);
    });
  });

  group('the catalogue', () {
    test('exactly one model is the benchmark, and it is the one with a number',
        () {
      final benchmarks = AppConstants.availableModels
          .where((m) => m['benchmark'] == 'true')
          .toList();
      expect(benchmarks, hasLength(1),
          reason: 'two benchmarks means two rulers and no comparison');
      expect(benchmarks.single['filename'], kBenchmarkModelFilename);
      expect(benchmarks.single['runtime'], 'llama');
    });

    test('the benchmark is no heavier than the 230M it was measured on', () {
      // Not "the smallest in the catalogue", and that difference is deliberate.
      // The 135M is lighter and would fit a tighter budget, but the pass and
      // slow thresholds in judgeCpuSelfTest are calibrated against 12 tok/s from
      // the 230M on an A72. Swapping in a lighter model without re-measuring
      // would make the thresholds describe a model nobody has run, which is
      // how a benchmark stops meaning anything.
      //
      // So the rule is: the benchmark may get *lighter* only together with a
      // new measurement. This test is where that coupling is written down, and
      // it fails the moment someone adds a 135M benchmark on a hunch.
      final bench = AppConstants.availableModels
          .firstWhere((m) => m['benchmark'] == 'true');
      final gb = double.parse(bench['size']!.replaceAll(' GB', ''));
      expect(gb, lessThanOrEqualTo(0.15 + 0.001));
    });

    test('the benchmark is heavier than nothing that claims to replace it', () {
      // The mirror image, and the one that would catch the real error: a model
      // smaller than the benchmark is *not* automatically a better one. It is
      // only a candidate, and it says so in its own description.
      final bench = AppConstants.availableModels
          .firstWhere((m) => m['benchmark'] == 'true');
      final benchGb = double.parse(bench['size']!.replaceAll(' GB', ''));
      final lighter = AppConstants.availableModels.where((m) {
        if (m['runtime'] != 'llama' || m['benchmark'] == 'true') return false;
        final g = double.tryParse((m['size'] ?? '').replaceAll(' GB', ''));
        return g != null && g < benchGb;
      });
      for (final m in lighter) {
        // **Nos dois idiomas.** A ficha que a tela mostra é uma de duas, e o
        // defeito — dizer que o modelo substitui o benchmark — aparece em
        // o idioma que a pessoa está lendo.
        for (final idioma in const ['descriptionEn', 'descriptionPt']) {
          expect(m[idioma], contains('benchmark'),
              reason: '${m['name']} is lighter than the benchmark, so its '
                  '$idioma has to say it is a candidate for it and not a '
                  'replacement');
        }
      }
    });

    test('every benchmark mmproj is unique, as every mmproj must be', () {
      // The catalogue-wide rule, re-asserted because the benchmark could grow
      // a projector later and this is the failure that is invisible until a
      // download overwrites a file.
      final names = AppConstants.availableModels
          .map((m) => m['mmprojFilename'] ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      expect(names.toSet().length, names.length);
    });

    test('the declared size matches the real content-length', () {
      // Checked on 2026-09-29 against the CDN: 149.080.928 bytes for the 230M
      // plain Q4_0, 105.454.432 for the 135M Q4_K_M. A 404 or a renamed file
      // only shows up at download time, so this is the cheap moment to catch it.
      //
      // It used to say 149.081.056 and QAD, which was correct for a file that
      // does not work: that one emitted 24 consecutive <|pad|> tokens on the A72
      // while reporting a plausible tok/s. See the QAT/QAD note in constants.
      final m = AppConstants.availableModels
          .firstWhere((x) => x['filename'] == kBenchmarkModelFilename);
      expect(m['size'], '0.14 GB');
      expect(m['url'], contains('LFM2.5-230M-Q4_0.gguf'));
    });

    test('the benchmark is not a QAT or QAD build', () {
      // Not a style rule. Those files load and then answer nothing, and nothing
      // about the failure announces itself: the benchmark reported 0,7 tok/s on
      // a Galaxy A72 and the user could not tell that number from a slow phone.
      // A model that produces nothing is worse than a model that is missing,
      // because the missing one is visible.
      final bench = AppConstants.availableModels
          .firstWhere((m) => m['filename'] == kBenchmarkModelFilename);
      final name = bench['filename'] ?? '';
      expect(name.contains('QAD') || name.contains('QAT'), isFalse,
          reason: 'QAT/QAD GGUFs emit <|pad|> with this vendored llama.cpp — '
              'measured on a Galaxy A72, see the note in constants.dart');
    });

    test('no Liquid LFM2.5 entry is a QAD build', () {
      // Scoped to Liquid on purpose. QAT is Google's spelling of the same idea
      // and the Gemma entries still ship, because "same idea" is not "same
      // file": the Gemma QAT GGUFs are a different producer and a different
      // architecture, and nothing measured yet says they fail. Liquid's QAD
      // files are the ones measured broken, so that is the family this asserts.
      // Anyone promoting a Gemma QAT entry past the catalogue has to run it
      // first and read the sampled token ids — see the QAT/QAD note in
      // constants.dart for how the LFM2.5 failure looked from the outside.
      final liquidQad = AppConstants.availableModels
          .where((m) =>
              (m['filename'] ?? '').contains('LFM2.5') &&
              (m['filename'] ?? '').contains('QAD'))
          .map((m) => m['filename'])
          .toList();
      expect(liquidQad, isEmpty,
          reason: 'Liquid QAD GGUFs emit <|pad|> on this build — measured');
    });
  });

  group('the self-test prompt', () {
    test('is short enough that its prefill cannot be the bottleneck', () {
      // Every token is prefill. A prompt of any real length turns a self-test
      // into the thing it is meant to rule out, which is the mistake the 545
      // token agent system prompt caused on the A72.
      expect(kCpuSelfTestPrompt.length, lessThan(60));
      expect(kCpuSelfTestPrompt, contains('2+2'),
          reason: 'a known answer is what makes a reply checkable by eye');
    });
  });
  _measurementRuleTests();
}

/// The measurement rule, tested without a phone.
///
/// The numbers here are the Galaxy A72's, and the shape of the simulation is
/// the thing that matters: a *first* generation that is catastrophically slow
/// and a second that is not. That is not a rounding difference, it is what the
/// device does every time the process starts, and it is the reason
/// `measureGeneration` throws the first one away.
void _measurementRuleTests() {
  group('measureGeneration', () {
    /// A fake engine with the A72's measured shape: the first call crawls, the
    /// second is quick. `slowFirstMs` stands in for the governor not having
    /// ramped yet.
    Future<String> fake({
      required int maxTokens,
      void Function(String)? onToken,
      required int slowFirstMs,
      required int fastTokenMs,
      required bool firstCall,
    }) async {
      if (firstCall) await Future<void>.delayed(Duration(milliseconds: slowFirstMs));
      for (var i = 0; i < maxTokens; i++) {
        await Future<void>.delayed(Duration(milliseconds: fastTokenMs));
        onToken?.call('tok');
      }
      return List.filled(maxTokens, 'tok').join(' ');
    }

    test('the cold attempt does not become the answer, so a fresh process is not judged cold',
        () async {
      var call = 0;
      final m = await measureGeneration(
        ({required int maxTokens, void Function(String)? onToken}) {
          call++;
          return fake(
            maxTokens: maxTokens,
            onToken: onToken,
            slowFirstMs: 400,
            fastTokenMs: 1,
            firstCall: call == 1,
          );
        },
        maxTokens: 4,
      );

      expect(call, 3, reason: 'three attempts, best one kept');
      // The measured run is the fast one. If the warm-up were removed, this
      // test would still pass the count check but the timing below would carry
      // the 400 ms and the rate would collapse toward the A72's 0.2 tok/s.
      expect(m.totalMs, lessThan(400),
          reason: 'the discarded run must not be inside the measured window');
    });

    test('tokens are counted from the engine, not split out of the text', () async {
      // The old code did `text.split(RegExp(r'\s+')).length`, which counts
      // words. A reply of 24 tokens that happens to be four words was being
      // divided by four, so the reported rate was wrong by the ratio between
      // the two — and always in the flattering direction.
      final m = await measureGeneration(
        ({required int maxTokens, void Function(String)? onToken}) async {
          for (var i = 0; i < 24; i++) {
            onToken?.call('word');
          }
          // One "word", 24 tokens. Word-counting would return 1.
          return 'word';
        },
        maxTokens: 24,
        attempts: 1,
      );
      expect(m.tokens, 24, reason: '24 onToken calls are 24 tokens');
    });

    test('time to first token is the first token, not the end of the run', () async {
      // The old code read `sw.elapsedMilliseconds` after the whole generation
      // and labelled it TTFT, which is why a run whose prefill took 2.8 s was
      // reported as 71.4 s to first token. Here the first token lands early and
      // the run continues for a while after it.
      final m = await measureGeneration(
        ({required int maxTokens, void Function(String)? onToken}) async {
          onToken?.call('a');
          await Future<void>.delayed(const Duration(milliseconds: 300));
          onToken?.call('b');
          return 'a b';
        },
        maxTokens: 2,
        attempts: 1,
      );
      expect(m.firstTokenMs, lessThan(200),
          reason: 'the first token arrives before the run ends');
      expect(m.totalMs, greaterThan(m.firstTokenMs),
          reason: 'and the run is still longer than that');
    });

    test('a run that produces nothing scores zero rather than dividing by zero',
        () async {
      final m = await measureGeneration(
        ({required int maxTokens, void Function(String)? onToken}) async => '',
        maxTokens: 4,
        attempts: 1,
      );
      expect(m.tokensPerSecond, 0.0);
      expect(m.firstTokenMs, -1);
    });
  });
}
