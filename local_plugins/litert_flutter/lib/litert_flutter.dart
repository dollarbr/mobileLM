/// LiteRT 2.2.0 for `.tflite` models, over a method channel.
///
/// Thin on purpose. The decisions that needed care — which accelerator to ask
/// for, what to report about the one that actually ran, how to name a tensor —
/// are made in `LiteRtPlugin.kt` and in `services/litert_model.dart`, and they
/// are testable there. This file is the transport.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart';

/// A tensor buffer on its way in or out.
///
/// Floats only, because that is the whole of what this app's `.tflite` models
/// use and because the alternative is a `List<double>` crossing the channel,
/// which `StandardMessageCodec` encodes element by element. For Laya's main
/// graph that is `[1, 512, 1024]` — 524 288 doubles boxed one at a time, on
/// every request.
class LitertBuffer {
  const LitertBuffer(this.data);

  /// A `Float32List` travels as a Java `float[]`; a `List<double>` does not
  /// travel as one.
  final Float32List data;

  int get length => data.length;
}

/// What a device can do, and what the runtime will not tell us.
class LitertAccelerators {
  const LitertAccelerators({
    required this.available,
    required this.hasGpu,
    required this.hasCpu,
  });

  final List<String> available;
  final bool hasGpu;
  final bool hasCpu;

  @override
  String toString() => 'available=$available';
}

/// The result of a successful `run`.
class LitertRun {
  const LitertRun({
    required this.outputs,
    required this.runMillis,
    required this.signature,
    required this.inputBytes,
  });

  /// Output name to values, in the order the caller asked for them.
  final Map<String, Float32List> outputs;

  final int runMillis;
  final String signature;
  final int inputBytes;
}

/// Thrown for anything the plugin refused.
///
/// The message is the plugin's, verbatim. It names the file, the signature and
/// the tensor, because a LiteRT failure that does not is a failure you end up
/// bisecting through the runtime.
class LitertException implements Exception {
  LitertException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'LitertException($code): $message';
}

class LiteRt {
  LiteRt._();

  static const MethodChannel _channel =
      MethodChannel('com.dollarbr.mobilelm/litert');

  /// What this device can actually do.
  ///
  /// This is the only accelerator fact in the plugin that is not a request:
  /// `Environment.getAvailableAccelerators()` is already filtered by what LiteRT
  /// could load, so a phone with no usable OpenCL simply does not list GPU.
  static Future<LitertAccelerators> availableAccelerators() async {
    final r = await _invoke<Map<Object?, Object?>>('availableAccelerators');
    return LitertAccelerators(
      available: (r!['available'] as List).cast<String>(),
      hasGpu: r['hasGpu'] as bool? ?? false,
      hasCpu: r['hasCpu'] as bool? ?? false,
    );
  }

  /// Compile a `.tflite` and keep it loaded.
  ///
  /// [accelerators] is what to *ask* for. Read
  /// [LitertLoadResult.requestedButUnavailable] to find out whether the device
  /// had it — and note that even when it did, LiteRT 2.2.0 does not expose the
  /// accelerator that actually ran, so `executedAccelerator` is null and
  /// `executedAcceleratorNote` says so.
  ///
  /// [numThreads] of 0 leaves the choice to the runtime.
  static Future<LitertLoadResult> load(
    String path, {
    List<String> accelerators = const ['CPU'],
    int numThreads = 0,
  }) async {
    final r = await _invoke<Map<Object?, Object?>>('loadModel', () => {
          'path': path,
          'accelerators': accelerators,
          'numThreads': numThreads,
        });
    return LitertLoadResult(
      path: r!['path'] as String,
      compileMillis: (r['compileMillis'] as num?)?.toInt() ?? 0,
      requested: (r['requested'] as List).cast<String>(),
      available: (r['available'] as List).cast<String>(),
      requestedButUnavailable:
          (r['requestedButUnavailable'] as List?)?.cast<String>() ??
              const [],
      executedAccelerator: r['executedAccelerator'] as String?,
      executedAcceleratorNote: r['executedAcceleratorNote'] as String?,
    );
  }

  /// Run one signature, binding tensors **by name**.
  ///
  /// Names, not positions, and not as an option: the Java API binds by name and
  /// the stored order is not what a document about the model tends to list.
  /// Laya's act head is the proof — its FlatBuffer stores `feats` before
  /// `pooled_cls` while `HOST_CONTRACT.md` lists them the other way round.
  static Future<LitertRun> run({
    required Map<String, Float32List> inputs,
    required List<String> outputNames,
    String signature = 'serving_default',
  }) async {
    final r = await _invoke<Map<Object?, Object?>>('run', () => {
          'signature': signature,
          'inputs': inputs,
          'outputNames': outputNames,
        });
    final raw = r!['outputs'] as Map;
    return LitertRun(
      outputs: raw.map((k, v) => MapEntry(k as String, v as Float32List)),
      runMillis: (r['runMillis'] as num?)?.toInt() ?? 0,
      signature: r['signature'] as String? ?? signature,
      inputBytes: (r['inputBytes'] as num?)?.toInt() ?? 0,
    );
  }

  /// Drop the loaded model and free the native handle.
  static Future<bool> unload() async {
    final r = await _invoke<Map<Object?, Object?>>('unload');
    return r?['unloaded'] as bool? ?? false;
  }

  /// Turn a platform error into a [LitertException] with the plugin's code and
  /// message intact, rather than a bare `PlatformException` whose text is the
  /// class name.
  static Future<T> _invoke<T>(String method, [Map<String, Object?>? Function()? a]) async {
    try {
      final r = await _channel.invokeMethod<T>(method, a?.call());
      if (r == null) {
        throw LitertException(
            'null_result', '$method returned nothing. The plugin answered on '
                'the wrong thread, or did not answer.');
      }
      return r;
    } on PlatformException catch (e) {
      throw LitertException(e.code, e.message ?? '(no message)');
    } on MissingPluginException {
      // **NotImplemented, not necessarily an unregistered plugin.** A registered
      // plugin whose `onMethodCall` has no branch for this name answers
      // `notImplemented()`, and Flutter surfaces *that* as MissingPluginException.
      //
      // This cost a whole diagnosis cycle pointing the wrong way: the class was
      // in the dex, the generated registrant referenced it, and the message here
      // said registration, so the only thing left to check was the method name —
      // which was the actual cause (`load` in Kotlin, `loadModel` in Dart).
      throw LitertException(
        'no_handler',
        "LiteRT answered notImplemented() for '$method', which means the "
            'plugin is registered but has no handler with that exact name. '
            'Either the plugin is not registered, or the method names on the two '
            'sides differ — the second is far more common and looks like the '
            'first from here.',
      );
    }
  }
}

/// What a `load` actually got.
class LitertLoadResult {
  const LitertLoadResult({
    required this.path,
    required this.compileMillis,
    required this.requested,
    required this.available,
    required this.requestedButUnavailable,
    required this.executedAccelerator,
    required this.executedAcceleratorNote,
  });

  final String path;
  final int compileMillis;

  /// What was asked for.
  final List<String> requested;

  /// What the device reports it can do.
  final List<String> available;

  /// Requested and not available — the substitutions LiteRT will make silently.
  final List<String> requestedButUnavailable;

  /// **Always null in LiteRT 2.2.0.** `CompiledModel` has no getter for the
  /// accelerator it used. Kept as a field so a caller has to acknowledge it
  /// rather than discover later that "gpu" was only ever a request.
  final String? executedAccelerator;

  final String? executedAcceleratorNote;

  @override
  String toString() => 'compiled ${compileMillis}ms, requested $requested, '
      'available $available, executed=$executedAccelerator';
}
