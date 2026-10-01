// The mapping from a `.tflite` signature to the classify contract.
//
// The rule that needed pinning is which input carries the features. It started as
// "the first input" and the A72 killed it in the most ordinary way possible:
// Laya's act head stores `feats [1,4]` *before* `pooled_cls [1,1024]`, so
// "first" picks the 4-element auxiliary and the endpoint then correctly reports
// "the head wants 4 features and got 1024" — a right answer to a wrong question.
//
// The replacement is the largest input, with `features_input` as the override.
// That is a heuristic, and a heuristic with no test is a comment.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/services/litert_model.dart';
import 'package:mobilelm/services/litert_service.dart';

void main() {
  LitertSignature sig(List<LitertTensor> inputs, List<LitertTensor> outputs,
          {int subgraph = 0}) =>
      LitertSignature(
        key: 'serving_default',
        inputs: inputs,
        outputs: outputs,
        subgraphIndex: subgraph,
      );

  const logits = LitertTensor(
      name: 'logits', type: TensorType.float32, shape: [1, 3]);

  group('the feature vector is the LARGEST input, not the first', () {
    test('the act head is the case that broke "first", so it is the test', () {
      // In the file's stored order feats comes first. If this test ever starts
      // picking `feats`, the rule regressed to the thing that did not work.
      final s = sig(const [
        LitertTensor(name: 'feats', type: TensorType.float32, shape: [1, 4]),
        LitertTensor(
            name: 'pooled_cls', type: TensorType.float32, shape: [1, 1024]),
      ], [logits]);
      final h = tfliteHeadShape(s)!;
      expect(h.features.name, 'pooled_cls');
      expect(h.featureCount, 1024);
      expect([for (final t in h.auxiliary) t.name], ['feats']);
    });

    test('a single-input head is unaffected', () {
      final s = sig(const [
        LitertTensor(name: 'x', type: TensorType.float32, shape: [1, 768]),
      ], [logits]);
      final h = tfliteHeadShape(s)!;
      expect(h.features.name, 'x');
      expect(h.auxiliary, isEmpty);
      expect(h.classCount, 3);
    });

    test('a tie on size takes the first of them, so the choice is stable', () {
      // Determinism matters more than which one: a rule that alternates between
      // runs would make a number unreproducible for no stated reason.
      final a = sig(const [
        LitertTensor(name: 'a', type: TensorType.float32, shape: [1, 8]),
        LitertTensor(name: 'b', type: TensorType.float32, shape: [1, 8]),
      ], [logits]);
      final b = sig(const [
        LitertTensor(name: 'b', type: TensorType.float32, shape: [1, 8]),
        LitertTensor(name: 'a', type: TensorType.float32, shape: [1, 8]),
      ], [logits]);
      expect(tfliteHeadShape(a)!.features.name, 'a');
      expect(tfliteHeadShape(b)!.features.name, 'b');
    });

    test('a non-float input is not eligible even when it is the largest', () {
      // A uint8 image is 602112 values and beats a 1024 feature vector on size.
      // Choosing it would push bytes through a float bridge, which reinterprets
      // them rather than converting them.
      final s = sig(const [
        LitertTensor(
            name: 'image', type: TensorType.uint8, shape: [1, 224, 224, 3]),
        LitertTensor(name: 'feats', type: TensorType.float32, shape: [1, 16]),
      ], [logits]);
      final h = tfliteHeadShape(s)!;
      expect(h.features.name, 'feats');
      // The uint8 one is dropped rather than offered as an auxiliary: a caller
      // cannot fill it through a Float32List.
      expect([for (final t in h.auxiliary) t.name], isEmpty);
    });

    test('a dynamic-dimension input is not eligible, and is not offered', () {
      final s = sig(const [
        LitertTensor(
            name: 'dyn', type: TensorType.float32, shape: [1, -1, 1024]),
        LitertTensor(name: 'ok', type: TensorType.float32, shape: [1, 32]),
      ], [logits]);
      final h = tfliteHeadShape(s)!;
      expect(h.features.name, 'ok');
      expect([for (final t in h.auxiliary) t.name], isEmpty);
    });
  });

  group('features_input overrides the guess, and a wrong name is a refusal', () {
    final s = sig(const [
      LitertTensor(name: 'feats', type: TensorType.float32, shape: [1, 4]),
      LitertTensor(
          name: 'pooled_cls', type: TensorType.float32, shape: [1, 1024]),
    ], [logits]);

    test('naming the small input picks the small input', () {
      final h = tfliteHeadShape(s, featuresInput: 'feats')!;
      expect(h.features.name, 'feats');
      expect(h.featureCount, 4);
      expect([for (final t in h.auxiliary) t.name], ['pooled_cls']);
    });

    test('naming the large input is the same as the default', () {
      expect(tfliteHeadShape(s, featuresInput: 'pooled_cls')!.features.name,
          tfliteHeadShape(s)!.features.name);
    });

    test('an unknown name returns null rather than falling back', () {
      // A caller that named a tensor and got a different one back has no way to
      // notice except that the numbers are subtly wrong.
      expect(tfliteHeadShape(s, featuresInput: 'nao_existe'), isNull);
    });

    test('naming a tensor that exists but is not float returns null', () {
      final u = sig(const [
        LitertTensor(
            name: 'image', type: TensorType.uint8, shape: [1, 224, 224, 3]),
      ], [logits]);
      expect(tfliteHeadShape(u, featuresInput: 'image'), isNull);
    });
  });

  group('what is not a head, and the reason names it', () {
    test('no inputs at all', () {
      final s = sig(const [], [logits]);
      expect(tfliteHeadShape(s), isNull);
      expect(notAHeadReason(s), contains('no inputs'));
    });

    test('no outputs at all', () {
      final s = sig(const [
        LitertTensor(name: 'x', type: TensorType.float32, shape: [1, 4]),
      ], const []);
      expect(tfliteHeadShape(s), isNull);
      expect(notAHeadReason(s), contains('no outputs'));
    });

    test('two outputs is a refusal, and says one logit per class', () {
      final s = sig(const [
        LitertTensor(name: 'x', type: TensorType.float32, shape: [1, 4]),
      ], const [
        logits,
        LitertTensor(name: 'other', type: TensorType.float32, shape: [1, 2]),
      ]);
      expect(tfliteHeadShape(s), isNull);
      expect(notAHeadReason(s), contains('one logit per class'));
    });

    test('an image model says so, with the type and the shape', () {
      final s = sig(const [
        LitertTensor(
            name: 'image', type: TensorType.uint8, shape: [1, 224, 224, 3]),
      ], [logits]);
      expect(tfliteHeadShape(s), isNull);
      final why = notAHeadReason(s);
      expect(why, contains('UINT8'));
      expect(why, contains('[1, 224, 224, 3]'));
    });

    test('a dynamic feature width says the buffer size is unknown', () {
      final s = sig(const [
        LitertTensor(
            name: 'x', type: TensorType.float32, shape: [1, -1, 1024]),
      ], [logits]);
      expect(tfliteHeadShape(s), isNull);
      expect(notAHeadReason(s), contains('dynamic dimension'));
    });
  });

  group('the real act head, screened and mapped', () {
    final path = _findActHead();
    final skip = path == null
        ? 'act head not in the LiteRT cache; run on the device that has it'
        : null;

    test('it maps to a head with pooled_cls as features and feats auxiliary', () {
      final s = parseLitertModel(File(path!).readAsBytesSync())
          .defaultSignature!;
      final h = tfliteHeadShape(s)!;
      expect(h.features.name, 'pooled_cls');
      expect(h.featureCount, 1024);
      expect([for (final t in h.auxiliary) t.name], ['feats']);
      expect(h.classCount, 2);
      expect(h.allInputs.keys.toSet(), {'pooled_cls', 'feats'});
    }, skip: skip);

    test('and swapping the override moves the boundary the other way', () {
      final s = parseLitertModel(File(path!).readAsBytesSync())
          .defaultSignature!;
      final flipped = tfliteHeadShape(s, featuresInput: 'feats')!;
      expect(flipped.featureCount, 4);
      expect([for (final t in flipped.auxiliary) t.name], ['pooled_cls']);
    }, skip: skip);
  });
}

String? _findActHead() {
  final roots = [
    if (Platform.environment['MOBILELM_MODEL_DIR'] != null)
      Platform.environment['MOBILELM_MODEL_DIR']!,
    '/tmp/opencode/litert-cache',
    '${Platform.environment['HOME']}/.cache/mobilelm-litert',
  ];
  for (final root in roots) {
    final f = File('$root/laya_en_act_head_fp32.tflite');
    if (f.existsSync()) return f.path;
  }
  return null;
}
