/// A loaded `.tflite` model, screened and ready to run.
///
/// ## Why there is a screen step at all
///
/// The LiteRT Java API binds tensors by name and cannot list them, so a host has
/// to read the names out of the FlatBuffer before it can run anything. That read
/// ([parseLitertModel]) is the screen. It happens on load, once, and its result
/// is what the caller uses to decide whether the model is a classifier at all.
///
/// ## What counts as a classifier here, and why it is not "exactly one input"
///
/// The first rule I wrote was "exactly one float input, one float output", on the
/// reasoning that a head is a feature vector in and logits out. Checking that
/// against the published `.tflite` classifiers said something different:
///
/// - **Laya's act head** takes `pooled_cls` **[1,1024] and `feats` [1,4]** — two
///   inputs, and its output `act_logits` [1,2] is exactly what a head should
///   produce.
/// - **MobileNet** takes one input, but it is `uint8 [1,224,224,3]`: a rank-4
///   image, not a feature vector.
/// - **BERT classifiers** take `input_ids`, `attention_mask` and
///   `token_type_ids`.
///
/// So "one input" is not what distinguishes a head, and insisting on it refused
/// every real model while accepting none. The rule that survives is about the
/// **first** input being the features and the output being logits, with any
/// further inputs **left for the caller to supply** — which is precisely what
/// Laya's `feats` is, and which a host computes rather than guesses.
///
/// The alternative, inventing the auxiliary inputs as zeros, is worse than
/// refusing: a logit computed on invented features is a number with no meaning
/// and it comes back wearing a confident label.
///
/// The shape lives in [TfliteHeadShape], a pure value, because "can this app
/// serve this model" is decidable on a laptop and it is what decides what the UI
/// offers.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:litert_flutter/litert_flutter.dart';

import 'litert_model.dart';

export 'package:litert_flutter/litert_flutter.dart'
    show LitertException, LitertAccelerators, LitertRun, LitertLoadResult;

/// How a `.tflite` signature maps onto the classify contract, or why it does not.
class TfliteHeadShape {
  const TfliteHeadShape({
    required this.features,
    required this.auxiliary,
    required this.logits,
  });

  /// The input a request's `features` fill.
  ///
  /// **Not the first one, and the device is why.** The rule this started with was
  /// "the first input", and Laya's act head breaks it in the most ordinary way
  /// possible: it stores `feats [1,4]` *before* `pooled_cls [1,1024]`, so
  /// "first" picks the 4-element auxiliary and the endpoint then says "the head
  /// wants 4 features and got 1024" — a correct error, from a wrong decision.
  ///
  /// What is true across the heads is the *size*: the feature vector is the big
  /// one, and auxiliary inputs are small derived quantities. So the default is the
  /// largest input, and a caller that knows better says so with
  /// `features_input`. The response always names which input was used, so being
  /// wrong costs one request and not a debug session.
  final LitertTensor features;

  /// The other inputs. The caller supplies these; the host never invents them.
  final List<LitertTensor> auxiliary;

  /// The single output, read as one logit per class.
  final LitertTensor logits;

  int get featureCount => features.elementCount;
  int get classCount => logits.elementCount;

  /// Every input by name, for an error message that says what *is* available.
  Map<String, LitertTensor> get allInputs => {
        for (final t in [features, ...auxiliary]) t.name: t,
      };
}

/// Recognise a classification head, or refuse with a reason.
///
/// Three refusals, and what each costs if it is not refused:
///
/// - **No input, or more than one output.** Nothing to fill, or nothing
///   unambiguous to read.
/// - **The first input is not float.** A `uint8 [1,224,224,3]` image is a
///   different contract, and pushing it through a float bridge reinterprets the
///   bytes instead of converting them.
/// - **A dynamic dimension** on the features or the logits. The element count is
///   unknown, so the buffer size would be a guess.
TfliteHeadShape? tfliteHeadShape(LitertSignature s, {String? featuresInput}) {
  if (s.inputs.isEmpty) return null;
  if (s.outputs.length != 1) return null;
  final usable = s.inputs
      .where((t) =>
          t.type == TensorType.float32 &&
          !t.hasDynamicDimension &&
          t.elementCount > 0)
      .toList();
  if (usable.isEmpty) return null;
  final o = s.outputs.single;
  if (o.type != TensorType.float32) return null;
  if (o.hasDynamicDimension || o.elementCount == 0) return null;

  // An explicit name wins, and an unknown name is a refusal rather than a
  // silent fallback: a caller that named a tensor and got a different one has no
  // way to notice except that the numbers are wrong.
  final named = featuresInput == null
      ? null
      : usable.where((t) => t.name == featuresInput).firstOrNull;
  if (featuresInput != null && named == null) return null;

  // Largest, and the first of the largest on a tie — the stored order decides,
  // so the choice is at least deterministic.
  final features = named ??
      usable.reduce((a, b) => b.elementCount > a.elementCount ? b : a);
  return TfliteHeadShape(
    features: features,
    auxiliary: usable.where((t) => t.name != features.name).toList(),
    logits: o,
  );
}

/// Why a signature is not a head, in one line for an error message.
///
/// Names the auxiliary inputs when there are any, because "this model is not a
/// classifier" is a dead end for the caller and "supply `feats`" is not.
String notAHeadReason(LitertSignature s) {
  if (s.inputs.isEmpty) return 'it declares no inputs.';
  if (s.outputs.isEmpty) return 'it declares no outputs.';
  if (s.outputs.length != 1) {
    return 'it has ${s.outputs.length} outputs; a head has one logit per class.';
  }
  final f = s.inputs.first;
  if (f.type != TensorType.float32) {
    return 'its first input is ${f.type.label} ${f.shapeLabel}, and this '
        'endpoint fills a float feature vector.';
  }
  if (f.hasDynamicDimension) {
    return 'its first input has a dynamic dimension, so the buffer size is '
        'unknown.';
  }
  if (s.outputs.single.hasDynamicDimension) {
    return 'its output has a dynamic dimension.';
  }
  return 'unknown';
}

/// One loaded model.
class LitertModel {
  LitertModel._({
    required this.path,
    required this.info,
    required this.signature,
    required this.load,
    required this.runCount,
  });

  final String path;

  /// Everything read from the FlatBuffer, before the runtime touched it.
  final LitertModelInfo info;

  /// The signature this model is served through.
  final LitertSignature signature;

  /// What the compile reported — including which accelerator it would not tell us.
  final LitertLoadResult load;

  final int runCount;

  /// Whether [LitertModel] can serve `/v1/classify`.
  TfliteHeadShape? get head => tfliteHeadShape(signature);

  /// The same, with the caller naming which input carries the features.
  TfliteHeadShape? headWith(String? featuresInput) =>
      tfliteHeadShape(signature, featuresInput: featuresInput);

  bool get isClassifier => head != null;

  /// The feature width, e.g. 1024.
  int get inputSize => signature.inputs.first.elementCount;

  /// How many classes, e.g. 2.
  int get outputSize => signature.outputs.first.elementCount;

  Map<String, dynamic> toJson() => {
        'path': path,
        'signature': signature.key,
        'inputs': [for (final t in signature.inputs) t.toJson()],
        'outputs': [for (final t in signature.outputs) t.toJson()],
        'is_classifier': isClassifier,
        if (isClassifier == false) 'not_a_head_reason': notAHeadReason(signature),
        if (head != null)
          'head': {
            'features': head!.features.toJson(),
            'logits': head!.logits.toJson(),
            'auxiliary': [for (final t in head!.auxiliary) t.toJson()],
          },
        'compile_ms': load.compileMillis,
        'requested': load.requested,
        'available': load.available,
        if (load.requestedButUnavailable.isNotEmpty)
          'requested_but_unavailable': load.requestedButUnavailable,
        // null, on purpose, and see the note on the field.
        'executed_accelerator': load.executedAccelerator,
        'executed_accelerator_note': load.executedAcceleratorNote,
      };

  @override
  String toString() => 'LitertModel(${path.split('/').last}, '
      '${signature.inputs.length}in/${signature.outputs.length}out, '
      'classifier=$isClassifier)';
}

/// Owns the one loaded `.tflite`, and is the only thing that talks to the
/// plugin.
///
/// Single-model on purpose, and for the same reason the server is: a
/// `TensorBuffer` belongs to exactly one inference, so two concurrent runs on one
/// model is a native crash rather than an exception. The plugin refuses a
/// second call with `busy`; this refuses it before that with a message that says
/// what to do instead.
class LitertService extends GetxService {
  LitertModel? _loaded;
  int _runs = 0;
  bool _running = false;

  LitertModel? get loaded => _loaded;

  @visibleForTesting
  set loadedForTest(LitertModel? m) => _loaded = m;

  /// What the device can do. Safe to call with nothing loaded.
  Future<LitertAccelerators> accelerators() => LiteRt.availableAccelerators();

  /// Screen a `.tflite` without loading it.
  ///
  /// Separate from [load] because screening is what a catalogue scan wants and
  /// compiling is not: a 705 MB graph takes seconds of native time and the
  /// question "what does this file expect?" does not need it answered.
  Future<LitertModelInfo> screen(String path) async {
    final f = File(path);
    if (!f.existsSync()) {
      throw LitertException('not_found', 'No file at $path');
    }
    return parseLitertModel(f.readAsBytesSync());
  }

  /// Compile and keep the model, screening it first.
  ///
  /// The screen is not optional. A model that gets compiled and then found to
  /// have two inputs has already cost seconds of native time and a screenful of
  /// the user's, and the reason would be one line of log.
  Future<LitertModel> load(
    String path, {
    List<String> accelerators = const ['CPU'],
    int numThreads = 0,
  }) async {
    if (_running) {
      throw LitertException(
        'busy',
        'A .tflite inference is running. One model, one inference at a time.',
      );
    }
    final info = await screen(path);
    final signature = info.defaultSignature;
    if (signature == null) {
      throw LitertException(
        'no_signature',
        '${path.split('/').last} declares no signature. A model with no '
            'signature_defs cannot be bound by name, which is the only way the '
            'LiteRT API takes inputs.',
      );
    }
    if (!signature.bindable) {
      throw LitertException(
        'not_bindable',
        'Signature ${signature.key} cannot be driven: '
        '${signature.unusableReason}.',
      );
    }

    final res = await LiteRt.load(path,
        accelerators: accelerators, numThreads: numThreads);
    _runs = 0;
    _loaded = LitertModel._(
      path: path,
      info: info,
      signature: signature,
      load: res,
      runCount: 0,
    );
    return _loaded!;
  }

  /// Run the loaded model's signature, by tensor name.
  Future<LitertRun> run(
    Map<String, Float32List> inputs,
    List<String> outputNames, {
    String signature = 'serving_default',
  }) async {
    final m = _loaded;
    if (m == null) {
      throw LitertException('no_model', 'No .tflite loaded');
    }
    _running = true;
    try {
      final r = await LiteRt.run(
        inputs: inputs,
        outputNames: outputNames,
        signature: signature,
      );
      _runs++;
      return r;
    } finally {
      _running = false;
    }
  }

  /// Run a head: one feature vector in, one logit per class out.
  ///
  /// [auxiliary] fills any input beyond the first, by name. It is not optional
  /// in spirit: a head with auxiliary inputs cannot be run without them, and
  /// this fills them with **nothing** rather than with zeros, because a logit
  /// computed on invented features is a number with no meaning wearing a
  /// confident label. Laya's act head needs `feats` here, and the caller
  /// computes it from the marker logits it already has.
  ///
  /// Returns the raw logits. Not a probability, not a label, not a score. What
  /// they mean — which class is which, and whether a softmax over them is even
  /// the right reading — is the caller's, because only the caller knows the label
  /// set and the calibration.
  Future<Float32List> classify(
    Float32List features, {
    Map<String, Float32List> auxiliary = const {},
    String? featuresInput,
  }) async {
    final m = _loaded;
    if (m == null) {
      throw LitertException('no_model', 'No .tflite loaded');
    }
    final head = m.headWith(featuresInput);
    if (head == null) {
      throw LitertException(
        'not_a_head',
        '${m.path.split('/').last} is not a classification head: '
        '${notAHeadReason(m.signature)}',
      );
    }
    if (features.length != head.featureCount) {
      // Checked here rather than left to the runtime, because a native shape
      // error does not say what it expected.
      throw LitertException(
        'wrong_size',
        'The head wants ${head.featureCount} features '
        '(${head.features.shapeLabel}) and got ${features.length}.',
      );
    }

    final missing = <String>[];
    final wrongSize = <String, String>{};
    for (final t in head.auxiliary) {
      final v = auxiliary[t.name];
      if (v == null) {
        missing.add('${t.name} ${t.type.label} ${t.shapeLabel}');
      } else if (v.length != t.elementCount) {
        wrongSize[t.name] = '${t.elementCount}, got ${v.length}';
      }
    }
    if (missing.isNotEmpty || wrongSize.isNotEmpty) {
      // Both halves named, because both are the caller's to fix and one message
      // that says "wrong request" sends them looking in the wrong place.
      final parts = <String>[
        if (missing.isNotEmpty)
          'missing input(s): ${missing.join(', ')}',
        if (wrongSize.isNotEmpty)
          'wrong size for: ${wrongSize.entries.map((e) => '${e.key} wants ${e.value}').join(', ')}',
      ];
      throw LitertException(
        'missing_auxiliary',
        'This head takes ${head.auxiliary.length} input(s) beyond the feature '
        'vector. Supply them in "auxiliary_inputs", by the names the model '
        'declares — ${parts.join('; ')}. They are not filled with zeros on '
        'purpose: a logit computed on invented features is a number with no '
        'meaning.',
      );
    }

    final inName = head.features.name;
    final outName = head.logits.name;
    final inputs = <String, Float32List>{inName: features, ...auxiliary};
    final r = await run(inputs, [outName]);
    final out = r.outputs[outName];
    if (out == null || out.isEmpty) {
      throw LitertException(
        'empty_output',
        'The head returned no values for $outName. The runtime ran and produced '
        'nothing, which is a different thing from not running.',
      );
    }
    return out;
  }

  /// Release the compiled model and the memory it holds.
  ///
  /// Returns whether anything was loaded, because the caller has to be able to
  /// tell "I freed something" from "there was nothing there" — and because the
  /// difference is the difference between a number coming back and a lie.
  ///
  /// **Refuses while a run is in flight, and the check belongs here and not in
  /// the route.** `load` guards the same flag with the same reasoning, and the
  /// invariant is "one model, one inference at a time" — a property of the
  /// runtime, not of any HTTP surface. Unloading under a running inference frees
  /// the graph that inference is reading, and the crash would land inside native
  /// code with no Dart frame to point at.
  ///
  /// The same word the load path uses, so a client that already handles `busy`
  /// from a load handles it from an unload.
  Future<bool> unload() async {
    if (_running) {
      throw LitertException(
        'busy',
        'A .tflite inference is running. Unloading now would free the graph it '
        'is reading.',
      );
    }
    final was = _loaded != null;
    final path = _loaded?.path;
    _loaded = null;
    _runs = 0;
    await LiteRt.unload();
    return was;
  }
}
