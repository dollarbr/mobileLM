import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/models/ai_model.dart';

void main() {
  group('AiModel.hasVisionMarker', () {
    test('does not classify text-only Gemma 4 bundles as vision models', () {
      expect(
        AiModel.hasVisionMarker('Gemma-4-E2B-Abliterated.litertlm'),
        isFalse,
      );
    });

    test('recognizes unambiguous vision model markers', () {
      expect(AiModel.hasVisionMarker('Qwen2-VL-Instruct.litertlm'), isTrue);
      expect(AiModel.hasVisionMarker('LLaVA-Next.litertlm'), isTrue);
      expect(AiModel.hasVisionMarker('mobile-vision-model.litertlm'), isTrue);
    });
  });

  // The function every predicate that classifies a model reads. Before the
  // `.tflite` branch it fell through to `runtimeLlama`, and "falls through to
  // llama" is a claim that llama.cpp can open the file: `isLlamaModel` is
  // `runtime == runtimeLlama || filename endsWith .gguf`, so a tensor graph was
  // filed as a GGUF and its card offered "Load" to an engine that rejects the
  // magic bytes.
  group('AiModel.runtimeFromFilename', () {
    test('each runtime is recognised by its own extension', () {
      expect(
        AiModel.runtimeFromFilename('LFM2.5-230M-Q4_0.gguf'),
        AiModel.runtimeLlama,
      );
      expect(
        AiModel.runtimeFromFilename('Qwen3-0.6B.litertlm'),
        AiModel.runtimeLiteRt,
      );
      expect(
        AiModel.runtimeFromFilename('DreamShaper8_LCM.safetensors'),
        AiModel.runtimeSd,
      );
      expect(
        AiModel.runtimeFromFilename('laya_en_act_head_fp32.tflite'),
        AiModel.runtimeTflite,
      );
    });

    test('a .tflite is its own runtime and never a GGUF', () {
      // The assertion is the negative one on purpose. `runtimeLiteRt` would have
      // been the tempting wrong answer — same vendor, same project name — and it
      // is the one that puts a 1 MB classifier in a list of 586 MB generative
      // models behind a button that streams tokens.
      final r = AiModel.runtimeFromFilename('head_fp32.tflite');
      expect(r, isNot(AiModel.runtimeLlama));
      expect(r, isNot(AiModel.runtimeLiteRt));
      expect(r, isNot(AiModel.runtimeSd));
    });

    test('the extension is matched case-insensitively', () {
      // The other runtime branches are case-insensitive because the catalogue is
      // lowercase and nobody noticed; the import path is not the catalogue, and
      // a file picked from a phone's storage can carry any case at all.
      expect(
        AiModel.runtimeFromFilename('HEAD_FP32.TFLITE'),
        AiModel.runtimeTflite,
      );
      expect(
        AiModel.runtimeFromFilename('LFM2.5-230M-Q4_0.GGUF'),
        AiModel.runtimeLlama,
      );
    });

    test('a .tflite is still a .tflite when a template says otherwise', () {
      // The `template` argument exists to let a catalogue entry override the
      // extension for SD checkpoints, which have no extension of their own. It
      // must not be able to talk a `.tflite` out of its own runtime: an
      // auto-registered imported file gets `template: 'chatml'` (see
      // `refreshDownloaded`), and if the template won, every imported head would
      // be registered as SD.
      expect(
        AiModel.runtimeFromFilename(
          'head.tflite',
          template: 'chatml',
        ),
        AiModel.runtimeTflite,
      );
      expect(
        AiModel.runtimeFromFilename(
          'checkpoint.safetensors',
          template: 'sd',
        ),
        AiModel.runtimeSd,
      );
    });

    test('an unknown extension still defaults to llama', () {
      // Kept deliberately. The default is "treat it as a GGUF", which is the
      // pre-existing behaviour and the one that makes an unknown `.gguf` in the
      // models directory work with no code change. It is also why the `.tflite`
      // branch above is a branch and not a comment.
      expect(
        AiModel.runtimeFromFilename('mystery.bin'),
        AiModel.runtimeLlama,
      );
    });
  });
}