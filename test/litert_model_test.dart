// Reading a .tflite header without the runtime.
//
// The one test that matters most is the last group: it parses the real
// `laya_en_act_head_fp32.tflite`, published by litert-community, whose SHA256 is
// in the repo's SHA256SUMS. That file is 1.0 MB and lives in the LiteRT cache,
// so the test is skipped when it is not there — but on the machine that matters
// it is a real model, not a fixture I wrote to match my own parser.
//
// The bug this parser has to survive: the Java API binds tensors by name and
// offers no way to list them. So a host that guesses "input 0 is the features"
// runs Laya's act head wrong — it has TWO inputs, `pooled_cls` and `feats`, and
// its output is `act_logits`. Guessing the arity would not run it at all.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/services/litert_model.dart';
import 'package:mobilelm/services/litert_service.dart';

void main() {
  group('a file that is not a TFLite model says so, and says what it is', () {
    test('the identifier is checked before any offset is followed', () {
      // This is the whole reason for the check: without it these bytes decode
      // into whatever the offsets happen to point at, and the error arrives from
      // inside the FlatBuffer reader with no mention of the file type.
      final wrong = Uint8List(64);
      wrong[4] = 0x47; // 'G'
      wrong[5] = 0x47; // 'G'
      wrong[6] = 0x55; // 'U'
      wrong[7] = 0x46; // 'F'
      wrong[0] = 0x20; // a plausible-looking root offset
      expect(
        () => parseLitertModel(wrong),
        throwsA(isA<LitertFormatException>()
            .having((e) => e.message, 'message', contains('"GGUF"'))
            .having((e) => e.message, 'message', contains('not a TFLite model'))),
      );
    });

    test('a truncated file is named as truncated, not as corrupt schema', () {
      expect(
        () => parseLitertModel(Uint8List.fromList([0, 0, 0, 0, 0x54, 0x46, 0x4c])),
        throwsA(isA<LitertFormatException>()
            .having((e) => e.message, 'message', contains('truncated'))),
      );
    });

    test('an HTML error page is reported as the wrong type, with the bytes', () {
      // A 404 from a model host saved as a .tflite. The name says so, and the
      // message quotes it back, which is the difference between a two-second
      // diagnosis and a bisect through the download path.
      // A 404 from a model host saved as a .tflite. The identifier a .tflite
      // carries is at bytes 4..8, which in an HTML page is the middle of
      // `<!DOCTYPE` — not the first two characters, which is what I asserted
      // first. What matters is that the message quotes back what it found.
      final html = Uint8List.fromList('<!DOCTYPE html><html>404</html>'.codeUnits);
      expect(
        () => parseLitertModel(html),
        throwsA(isA<LitertFormatException>()
            .having((e) => e.message, 'message', contains('"CTYP"'))
            .having((e) => e.message, 'message', contains('not a TFLite model'))),
      );
    });
  });

  group('the type table, which the file stores as a byte and not a name', () {
    test('the codes the TFLite schema fixes are the ones we use', () {
      // If the schema renumbered these the parser would read the wrong type and
      // nothing would say so — a float32 buffer written as int32 is a plausible
      // wrong answer. Pinning the numbers is the test.
      expect(TensorType.float32.code, 0);
      expect(TensorType.float16.code, 1);
      expect(TensorType.int32.code, 2);
      expect(TensorType.uint8.code, 3);
      expect(TensorType.int64.code, 4);
      expect(TensorType.string.code, 5);
      expect(TensorType.boolean.code, 6);
      expect(TensorType.int16.code, 7);
      expect(TensorType.int8.code, 9);
    });

    test('an unknown code is refused, with the code in the message', () {
      // A model from a newer converter. The number in the message is what tells
      // you the reader is behind the file, rather than the file being broken.
      expect(
        () => TensorType.fromCode(99),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('99'))
            .having((e) => e.message, 'message', contains('newer converter'))),
      );
    });

    test('float16 is refused as an input even though it is a real type', () {
      // The trap. fp16 is ordinary in the schema and appears constantly in
      // weights, so it feels safe. But a graph taking fp16 *activations* needs a
      // different buffer path, and writing float32 into it produces numbers from
      // an unwritten buffer rather than an error.
      expect(TensorType.float16.supportedAsInput, isFalse,
          reason: 'writing float32 into an fp16 tensor is silently wrong');
      expect(TensorType.float32.supportedAsInput, isTrue);
      expect(TensorType.int32.supportedAsInput, isTrue);
      expect(TensorType.string.supportedAsInput, isFalse);
      expect(TensorType.resource.supportedAsInput, isFalse);
    });
  });

  group('shape arithmetic refuses to guess a dynamic dimension', () {
    test('a fully static shape multiplies out', () {
      const t = LitertTensor(
          name: 'x', type: TensorType.float32, shape: [1, 1024]);
      expect(t.elementCount, 1024);
      expect(t.hasDynamicDimension, isFalse);
      expect(t.shapeLabel, '[1, 1024]');
    });

    test('a -1 dimension is flagged, and the count is 0 rather than negative', () {
      const t = LitertTensor(
          name: 'x', type: TensorType.float32, shape: [1, -1, 1024]);
      expect(t.hasDynamicDimension, isTrue);
      // Not -1024: a negative buffer size is a different failure from a
      // flagged one, and only one of them is diagnosable.
      expect(t.elementCount, 0);
    });

    test('the shape is written the way the contract writes it', () {
      const t =
          LitertTensor(name: 'x', type: TensorType.float32, shape: [1, 2, 3]);
      expect(t.shapeLabel, '[1, 2, 3]');
    });
  });

  group('an unnamed tensor is refused, because the API binds by name', () {
    test('a signature with an unnamed input is not bindable, and says why', () {
      const s = LitertSignature(
        key: 'serving_default',
        inputs: [
          LitertTensor(name: '', type: TensorType.float32, shape: [1, 4]),
        ],
        outputs: [
          LitertTensor(name: 'out', type: TensorType.float32, shape: [1, 2]),
        ],
        subgraphIndex: 0,
      );
      expect(s.bindable, isFalse);
      expect(s.unusableReason, contains('binds by name'));
    });

    test('an unsupported input type is refused with the type named', () {
      // Needs a real output, or the "no outputs" check fires first and the
      // message names the wrong thing — which is what happened the first time.
      const s = LitertSignature(
        key: 'serving_default',
        inputs: [
          LitertTensor(name: 'x', type: TensorType.string, shape: [1, 4]),
        ],
        outputs: [
          LitertTensor(name: 'y', type: TensorType.float32, shape: [1, 2]),
        ],
        subgraphIndex: 0,
      );
      expect(s.bindable, isFalse);
      expect(s.unusableReason, contains('STRING'));
    });

    test('a signature with no inputs is not bindable, and it is not vacuously true', () {
      // The bug: `every` over an empty list is true, so a signature with no
      // inputs at all used to pass — and then be picked as the default, with
      // nothing to fill in.
      const s = LitertSignature(
        key: 'serving_default',
        inputs: [],
        outputs: [
          LitertTensor(name: 'y', type: TensorType.float32, shape: [1, 2]),
        ],
        subgraphIndex: 0,
      );
      expect(s.bindable, isFalse);
      expect(s.unusableReason, contains('no inputs'));
    });

    test('a signature with no outputs is not bindable either', () {
      const s = LitertSignature(
        key: 'serving_default',
        inputs: [
          LitertTensor(name: 'x', type: TensorType.float32, shape: [1, 2]),
        ],
        outputs: [],
        subgraphIndex: 0,
      );
      expect(s.bindable, isFalse);
      expect(s.unusableReason, contains('no outputs'));
    });

    test('a good signature is bindable and has no complaint', () {
      const s = LitertSignature(
        key: 'serving_default',
        inputs: [
          LitertTensor(name: 'feats', type: TensorType.float32, shape: [1, 4]),
        ],
        outputs: [
          LitertTensor(name: 'logits', type: TensorType.float32, shape: [1, 2]),
        ],
        subgraphIndex: 0,
      );
      expect(s.bindable, isTrue);
      expect(s.unusableReason, 'unknown');
    });
  });

  group('serving_default wins as the default, and the fallbacks are sane', () {
    LitertSignature sig(String key) => LitertSignature(
          key: key,
          inputs: const [
            LitertTensor(name: 'x', type: TensorType.float32, shape: [1, 2]),
          ],
          outputs: const [
            LitertTensor(name: 'y', type: TensorType.float32, shape: [1, 2]),
          ],
          subgraphIndex: 0,
        );

    test('serving_default is preferred over a model with several signatures', () {
      final info = LitertModelInfo(
        version: 3,
        description: '',
        signatures: [sig('other'), sig('serving_default'), sig('third')],
      );
      expect(info.defaultSignature!.key, 'serving_default');
    });

    test('without it, a bindable signature is used rather than the first', () {
      // Picking signatures.first here would hand the host something it cannot
      // run, and the failure would arrive as a native error with no mention of
      // the choice.
      final info = LitertModelInfo(
        version: 3,
        description: '',
        signatures: [
          const LitertSignature(
              key: 'bad', inputs: [], outputs: [], subgraphIndex: 0),
          sig('only_good'),
        ],
      );
      expect(info.defaultSignature!.key, 'only_good');
    });

    test('with none bindable, it still reports a signature rather than nothing', () {
      final info = LitertModelInfo(
        version: 3,
        description: '',
        signatures: [
          const LitertSignature(
              key: 'bad', inputs: [], outputs: [], subgraphIndex: 0),
        ],
      );
      expect(info.defaultSignature!.key, 'bad');
    });

    test('a model with no signature at all reports null, not a guess', () {
      final info =
          LitertModelInfo(version: 3, description: '', signatures: const []);
      expect(info.defaultSignature, isNull);
    });
  });

  group('JSON round-trip, because the screen runs over HTTP', () {
    // The console does not read the FlatBuffer itself — it asks the server to,
    // and gets JSON. So the value has to survive the trip, and the thing that
    // proves it is a round trip against the real file rather than a fixture: the
    // parser's output goes out as JSON, comes back, and has to be the same graph.
    test('a signature survives toJson and back', () {
      const original = LitertSignature(
        key: 'serving_default',
        inputs: [
          LitertTensor(name: 'feats', type: TensorType.float32, shape: [1, 4]),
          LitertTensor(
              name: 'pooled_cls', type: TensorType.float32, shape: [1, 1024]),
        ],
        outputs: [
          LitertTensor(name: 'act_logits', type: TensorType.float32, shape: [1, 2]),
        ],
        subgraphIndex: 0,
      );
      final back = LitertSignature.fromJson(original.toJson());
      expect(back.key, original.key);
      expect(back.subgraphIndex, original.subgraphIndex);
      expect([for (final t in back.inputs) t.name], ['feats', 'pooled_cls']);
      expect(back.inputs[0].shape, [1, 4]);
      expect(back.inputs[1].elementCount, 1024);
      expect(back.outputs.first.name, 'act_logits');
      // And the judgement survives, which is the part that matters: a signature
      // that came back not-bindable would make the console refuse a model it had
      // just described as fine.
      expect(back.bindable, original.bindable);
    });

    test('a dynamic dimension survives, and is still flagged', () {
      const original = LitertTensor(
          name: 'x', type: TensorType.float32, shape: [1, -1, 1024]);
      final back = LitertTensor.fromJson(original.toJson());
      expect(back.hasDynamicDimension, isTrue);
      expect(back.elementCount, 0);
    });

    test('an int shape from JSON becomes an int shape, not a double', () {
      // `jsonDecode` gives `1` as int and `1.0` as double, and both are `num`.
      // A shape of doubles would still print as `[1, 1024]` and would compare
      // unequal to the same shape parsed from the file — so the failure is a test
      // that passes on the label and fails on the value.
      final back = LitertTensor.fromJson({
        'name': 'x',
        'type': 'FLOAT32',
        'shape': [1, 1024]
      });
      expect(back.shape, [1, 1024]);
      expect(back.shape.every((d) => d is int), isTrue);
      expect(back.elementCount, 1024);
    });

    test('an unknown type label is refused, not read as float', () {
      // The trap. Defaulting here would turn "a schema I cannot describe" into
      // "a model that computes something", and the console would happily fill a
      // buffer with float32 where the file says something else.
      expect(
        () => LitertTensor.fromJson({'name': 'x', 'type': 'FLOAT8E5M3', 'shape': [1]}),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('FLOAT8E5M3'))
            .having((e) => e.message, 'message', contains('newer converter'))),
      );
    });

    test('the whole model round-trips, default signature included', () {
      const info = LitertModelInfo(
        version: 3,
        description: 'MLIR Converted.',
        signatures: [
          LitertSignature(
            key: 'serving_default',
            inputs: [
              LitertTensor(name: 'x', type: TensorType.float32, shape: [1, 8]),
            ],
            outputs: [
              LitertTensor(name: 'y', type: TensorType.int32, shape: [1, 3]),
            ],
            subgraphIndex: 0,
          ),
        ],
      );
      final back = LitertModelInfo.fromJson(info.toJson());
      expect(back.version, 3);
      expect(back.description, 'MLIR Converted.');
      expect(back.defaultSignature!.key, 'serving_default');
      // A non-float output is preserved as itself rather than coerced, because
      // the refusal that follows from it depends on the type being real.
      expect(back.defaultSignature!.outputs.first.type, TensorType.int32);
    });
  });

  group('the real published act head, parsed without the runtime', () {
    // litert-community/Laya-English-LiteRT, laya_en_act_head_fp32.tflite,
    // 1.0 MB. SHA256 c6f8de9b66e36581ce03cca7047d0a6b… in the repo's
    // SHA256SUMS. HOST_CONTRACT.md declares the signature: main graph aside, the
    // act graph takes pooled_cls [1,1024] and feats [1,4] and returns
    // act_logits [1,2].
    final path = _findActHead();
    final skip = path == null
        ? 'act head not in the LiteRT cache; run on the device that has it'
        : null;

    // Every lookup below goes **by name**, not by index, because that is the
    // only thing the Java API accepts — and this file is the proof that index
    // order is not something to assume. HOST_CONTRACT.md's table lists the act
    // graph's inputs as `pooled_cls` then `feats`; the FlatBuffer stores them
    // the other way round. A host that read the contract and bound position 0
    // would hand a 4-element feats tensor to the 1024-wide pooled_cls and get a
    // shape error, or worse, on a model where the two widths happen to match.
    LitertTensor inputByName(LitertSignature sig, String name) =>
        sig.inputs.firstWhere((t) => t.name == name);

    test('two inputs and one output, and the names are the real ones', () {
      final s = parseLitertModel(File(path!).readAsBytesSync())
          .defaultSignature!;
      expect(s.key, 'serving_default',
          reason: 'the contract binds by this name');
      expect(s.inputs.map((t) => t.name).toSet(), {'pooled_cls', 'feats'});
      expect(s.outputs.map((t) => t.name), ['act_logits']);
    }, skip: skip);

    test('the stored order is feats then pooled_cls, NOT the contract\'s prose', () {
      // Asserted as its own test so that if a future converter changes the
      // order, the failure says "the order changed" instead of "the names are
      // wrong", and the comment above explains why it must not be hardcoded.
      final s = parseLitertModel(File(path!).readAsBytesSync())
          .defaultSignature!;
      expect([for (final t in s.inputs) t.name], ['feats', 'pooled_cls']);
    }, skip: skip);

    test('the shapes and types are what the contract says', () {
      final s = parseLitertModel(File(path!).readAsBytesSync())
          .defaultSignature!;
      final pooled = inputByName(s, 'pooled_cls');
      final feats = inputByName(s, 'feats');
      expect(pooled.type, TensorType.float32);
      expect(pooled.shape, [1, 1024]);
      expect(feats.shape, [1, 4]);
      expect(s.outputs.first.shape, [1, 2]);
      expect(pooled.elementCount, 1024);
      expect(feats.elementCount, 4);
      expect(s.outputs.first.elementCount, 2);
    }, skip: skip);

    test('it is bindable, so the host can drive it', () {
      final info = parseLitertModel(File(path!).readAsBytesSync());
      expect(info.defaultSignature!.bindable, isTrue);
    }, skip: skip);

    test('the real file round-trips through JSON unchanged', () {
      // The pair that matters for the console: parse the published file, put it
      // through the wire format the server returns, read it back, and check the
      // head is still a head with the same boundary. A fixture would pass even if
      // the wire format disagreed with the parser about something the file
      // happens not to exercise.
      final parsed = parseLitertModel(File(path!).readAsBytesSync());
      final back = LitertModelInfo.fromJson(parsed.toJson());
      expect(back.version, parsed.version);
      expect(back.description, parsed.description);
      final a = parsed.defaultSignature!;
      final b = back.defaultSignature!;
      expect(b.key, a.key);
      expect([for (final t in b.inputs) t.name],
          [for (final t in a.inputs) t.name]);
      expect([for (final t in b.outputs) t.name],
          [for (final t in a.outputs) t.name]);
      expect(b.inputs.map((t) => t.elementCount).toList(),
          a.inputs.map((t) => t.elementCount).toList());
      // The boundary the console depends on: features is the 1024 one, and
      // `feats` is the auxiliary. If the round trip reordered them, the console
      // would fill the wrong tensor.
      expect(tfliteHeadShape(b)!.features.name, 'pooled_cls');
      expect([for (final t in tfliteHeadShape(b)!.auxiliary) t.name], ['feats']);
    }, skip: skip);

    test('the file announces itself as an MLIR conversion, with one signature', () {
      // Small, but it is the field that tells you a model came from the
      // converter rather than from a hand-written flatbuffer, and it is in the
      // header the same read already made.
      final info = parseLitertModel(File(path!).readAsBytesSync());
      expect(info.description.toLowerCase(), contains('mlir'));
      expect(info.signatures, hasLength(1));
    }, skip: skip);
  });
}

/// Where the act head is, if it has been downloaded.
///
/// Two places, because the model controller and a manual `adb push` both end up
/// somewhere sensible and a test that only knows one of them is a test that
/// skips when it could have run.
String? _findActHead() {
  const names = ['laya_en_act_head_fp32.tflite'];
  final roots = [
    if (Platform.environment['MOBILELM_MODEL_DIR'] != null)
      Platform.environment['MOBILELM_MODEL_DIR']!,
    '/tmp/opencode/litert-cache',
    '${Platform.environment['HOME']}/.cache/mobilelm-litert',
  ];
  for (final root in roots) {
    for (final n in names) {
      final f = File('$root/$n');
      if (f.existsSync()) return f.path;
    }
  }
  return null;
}
