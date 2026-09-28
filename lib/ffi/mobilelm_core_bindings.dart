// FFI bindings to the Rust core's cdylib — `libmobilelm_core.so`.
//
// This is the boundary `docs/APK.md` exists for. Today the LiteRT-LM engine is
// reached from Dart only through a hand-written Kotlin plugin, because the AAR
// ships `liblitertlm_jni.so` with JNI exports and Kotlin cannot `dlopen` the C
// API. The C API is plain C, so `dart:ffi` can call it directly and the Kotlin
// layer becomes deletable. That is the whole claim of 0.4.0, and it is about
// *reach* — the engine stays C++ and the throughput does not change.
//
// Three conventions, each with a reason:
//
// **Strings come back owned and are freed with `mobilelm_string_free`.** The
// library has no way to know when Dart is done with a JSON blob, and leaking
// 42 MB of handles over a long chat session is not a thing anyone notices until
// the app is killed by the OS.
//
// **The stream context is an `int`, not a pointer.** The Rust side calls back on
// a LiteRT-owned thread. If the context were a pointer, its lifetime would be
// the caller's problem across a thread it does not own — the exact shape of the
// use-after-free that `sd_ffi_bindings.dart` invites with
// `Pointer.fromFunction` and a `SendPort`. An id looked up in a Dart-side map
// cannot dangle. The id is meaningless to the native side, which only passes it
// back.
//
// **`mobilelm_abi_version` returns a literal, not an owned string.** The native
// pointer is stable across calls and is never freed; the two other string
// returns are not. `abiVersion` returns a Dart string and `lastError` frees, and
// nothing else in this file calls `mobilelm_string_free` on the version's
// pointer.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// ---------------------------------------------------------------------------
// Native typedefs
// ---------------------------------------------------------------------------

/// A stream chunk from the engine: already-unwrapped text, or the end of the
/// stream, or the reason it ended badly.
///
/// `isFinal` is set on the last call of every turn, and the ABI guarantees it is
/// the last call — that is the C API's own contract about `is_final`, restated
/// because a stream that silently loses its tail is the failure this shape exists
/// to prevent. `err` is non-null exactly when `isFinal` is set and the turn
/// failed.
typedef MobilelmStreamCallbackNative = Void Function(
    Int64 ctx, Pointer<Utf8> text, Int32 isFinal, Pointer<Utf8> err);
typedef MobilelmStreamCallback = void Function(
    int ctx, Pointer<Utf8> text, int isFinal, Pointer<Utf8> err);

typedef MobilelmAbiVersionNative = Pointer<Utf8> Function();
typedef MobilelmAbiVersion = Pointer<Utf8> Function();
typedef MobilelmLastErrorNative = Pointer<Utf8> Function();
typedef MobilelmLastError = Pointer<Utf8> Function();
typedef MobilelmStringFreeNative = Void Function(Pointer<Utf8>);
typedef MobilelmStringFree = void Function(Pointer<Utf8>);

typedef MobilelmSymbolsMissingNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef MobilelmSymbolsMissing = Pointer<Utf8> Function(Pointer<Utf8>);

typedef MobilelmProbeNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef MobilelmProbe = Pointer<Utf8> Function(Pointer<Utf8>);

typedef MobilelmPlanNative = Pointer<Utf8> Function(
    Pointer<Utf8> mode, Int32 forceCpu, Int32 npuAvailable);
typedef MobilelmPlan = Pointer<Utf8> Function(
    Pointer<Utf8> mode, int forceCpu, int npuAvailable);

typedef MobilelmEngineCreateNative = Pointer<Void> Function(
  Pointer<Utf8> runtimePath,
  Pointer<Utf8> modelPath,
  Pointer<Utf8> backend,
  Int32 nCtx,
  Int32 nThreads,
  Pointer<Utf8> cacheDir,
  Pointer<Utf8> dispatchDir,
  Pointer<Utf8> visionBackend,
  Pointer<Utf8> audioBackend,
  Pointer<Utf8> systemPrompt,
);
typedef MobilelmEngineCreate = Pointer<Void> Function(
  Pointer<Utf8> runtimePath,
  Pointer<Utf8> modelPath,
  Pointer<Utf8> backend,
  int nCtx,
  int nThreads,
  Pointer<Utf8> cacheDir,
  Pointer<Utf8> dispatchDir,
  Pointer<Utf8> visionBackend,
  Pointer<Utf8> audioBackend,
  Pointer<Utf8> systemPrompt,
);

typedef MobilelmEngineFreeNative = Void Function(Pointer<Void>);
typedef MobilelmEngineFree = void Function(Pointer<Void>);

typedef MobilelmEngineLoadReportNative = Pointer<Utf8> Function(Pointer<Void>);
typedef MobilelmEngineLoadReport = Pointer<Utf8> Function(Pointer<Void>);

/// `mobilelm_sampler_report` — which sampler type the open conversation is
/// actually sampling with, and what the app asked for instead. Null for a null
/// handle or an engine with no sampler (llama.cpp reads its own GGUF settings).
typedef MobilelmSamplerReportNative = Pointer<Utf8> Function(Pointer<Void>);
typedef MobilelmSamplerReport = Pointer<Utf8> Function(Pointer<Void>);

/// What the engine is sampling with.
///
/// [full] is the field that matters: it is false whenever the type in force is
/// not the type requested, and on a `greedy` sampler the temperature is not
/// consulted at all — so "the slider is set to 0.8" and "the reply ignores it"
/// look identical from the chat without this.
class SamplerReport {
  const SamplerReport({
    required this.requested,
    required this.actual,
    required this.full,
    required this.note,
  });

  /// What the app asked for, or `engine default` when it asked for nothing.
  final String requested;

  /// The type in force, or null when the engine's own default applies.
  final String? actual;

  /// True only when every knob the app set is consulted by [actual].
  final bool full;

  /// One line for a log, from the Rust side.
  final String note;

  factory SamplerReport.fromJson(Map<String, dynamic> d) => SamplerReport(
        requested: d['requested'] as String,
        actual: d['actual'] as String?,
        full: d['full'] as bool,
        note: d['note'] as String,
      );

  @override
  String toString() => note;
}

typedef MobilelmConversationOpenNative = Int32 Function(
  Pointer<Void> handle,
  Pointer<Utf8> systemPrompt,
  Pointer<Utf8> historyJson,
  Double temperature,
  Int32 topK,
  Double topP,
  Int32 greedy,
  Int32 maxOutputTokens,
);
typedef MobilelmConversationOpen = int Function(
  Pointer<Void> handle,
  Pointer<Utf8> systemPrompt,
  Pointer<Utf8> historyJson,
  double temperature,
  int topK,
  double topP,
  int greedy,
  int maxOutputTokens,
);

typedef MobilelmSendStreamNative = Int32 Function(
  Pointer<Void> handle,
  Pointer<Utf8> messageJson,
  Int32 maxTokens,
  Pointer<NativeFunction<MobilelmStreamCallbackNative>> cb,
  Int64 ctx,
);
// A function that *takes* a callback keeps the pointer in its Dart signature
// too, not the Dart function type. `lookupFunction<TNative, TDart>` requires
// `TDart` to be a subtype of `TNative`, and a Dart closure type is not a subtype
// of a function pointer. The caller never sees this: `sendStream` takes the
// `NativeCallable` and passes `.nativeFunction` itself, so a mismatch is not
// expressible. This is the same shape as `SdFfiSetProgressCallback`.
typedef MobilelmSendStream = int Function(
  Pointer<Void> handle,
  Pointer<Utf8> messageJson,
  int maxTokens,
  Pointer<NativeFunction<MobilelmStreamCallbackNative>> cb,
  int ctx,
);

typedef MobilelmSendTextNative = Pointer<Utf8> Function(
    Pointer<Void> handle, Pointer<Utf8> prompt);
typedef MobilelmSendText = Pointer<Utf8> Function(
    Pointer<Void> handle, Pointer<Utf8> prompt);

typedef MobilelmCountTokensNative = Int32 Function(
    Pointer<Void> handle, Pointer<Utf8> text);
typedef MobilelmCountTokens = int Function(
    Pointer<Void> handle, Pointer<Utf8> text);

typedef MobilelmBenchmarkNative = Pointer<Utf8> Function(Pointer<Void>);
typedef MobilelmBenchmark = Pointer<Utf8> Function(Pointer<Void>);

/// The library name the APK ships. Asserted in CI: if the cdylib stops
/// exporting one of the entry points below, the build fails there rather than
/// crashing on a phone at first use.
const String kCoreLibraryName = 'libmobilelm_core.so';

/// The LiteRT-LM C API runtime, next to the cdylib in the same `jniLibs`
/// directory. 38.9 MB on arm64 — the cost of this path, and the reason the
/// Kotlin plugin's deletion is part of it rather than optional.
const String kLiteRtRuntimeName = 'liblitert-lm.so';

/// Raised when a native call fails. Carries the native side's own wording,
/// because the wording is the diagnostic: "cannot dlopen" and "found, but the
/// linker namespace forbids it" are different bugs with different fixes, and
/// flattening them into "engine unavailable" loses the only useful part.
class MobilelmException implements Exception {
  MobilelmException(this.message, {this.symbol});

  final String message;

  /// The native function that failed, when it is known.
  final String? symbol;

  @override
  String toString() => symbol == null
      ? 'mobilelm_core: $message'
      : 'mobilelm_core: $message (in $symbol)';
}

/// The loaded core, and every function in it.
///
/// Not a singleton on purpose: the test suite loads the real library and calls
/// the pure functions (`abiVersion`, `plan`, `symbolsMissing`) without a device,
/// and a global would make that a fight with test ordering.
class MobilelmCore {
  MobilelmCore._(this._lib);

  final DynamicLibrary _lib;

  // --- diagnostics ---------------------------------------------------------

  late final MobilelmAbiVersion _abiVersion =
      _lib.lookupFunction<MobilelmAbiVersionNative, MobilelmAbiVersion>(
          'mobilelm_abi_version');
  late final MobilelmLastError _lastError =
      _lib.lookupFunction<MobilelmLastErrorNative, MobilelmLastError>(
          'mobilelm_last_error');
  late final MobilelmStringFree _stringFree =
      _lib.lookupFunction<MobilelmStringFreeNative, MobilelmStringFree>(
          'mobilelm_string_free');

  // --- the probe and the ladder --------------------------------------------

  late final MobilelmSymbolsMissing _symbolsMissing =
      _lib.lookupFunction<MobilelmSymbolsMissingNative, MobilelmSymbolsMissing>(
          'mobilelm_symbols_missing');
  late final MobilelmProbe _probe =
      _lib.lookupFunction<MobilelmProbeNative, MobilelmProbe>('mobilelm_probe');
  late final MobilelmPlan _plan =
      _lib.lookupFunction<MobilelmPlanNative, MobilelmPlan>('mobilelm_plan');

  // --- engine --------------------------------------------------------------

  late final MobilelmEngineCreate _engineCreate =
      _lib.lookupFunction<MobilelmEngineCreateNative, MobilelmEngineCreate>(
          'mobilelm_engine_create');
  late final MobilelmEngineFree _engineFree =
      _lib.lookupFunction<MobilelmEngineFreeNative, MobilelmEngineFree>(
          'mobilelm_engine_free');
  late final MobilelmEngineLoadReport _engineLoadReport =
      _lib
          .lookupFunction<MobilelmEngineLoadReportNative, MobilelmEngineLoadReport>(
              'mobilelm_engine_load_report');
  late final MobilelmSamplerReport _samplerReport =
      _lib.lookupFunction<MobilelmSamplerReportNative, MobilelmSamplerReport>(
          'mobilelm_sampler_report');

  // --- conversation --------------------------------------------------------

  late final MobilelmConversationOpen _conversationOpen =
      _lib.lookupFunction<MobilelmConversationOpenNative, MobilelmConversationOpen>(
          'mobilelm_conversation_open');

  // --- generation ----------------------------------------------------------

  late final MobilelmSendStream _sendStream =
      _lib.lookupFunction<MobilelmSendStreamNative, MobilelmSendStream>(
          'mobilelm_send_stream');
  late final MobilelmSendText _sendText =
      _lib.lookupFunction<MobilelmSendTextNative, MobilelmSendText>(
          'mobilelm_send_text');
  late final MobilelmCountTokens _countTokens =
      _lib.lookupFunction<MobilelmCountTokensNative, MobilelmCountTokens>(
          'mobilelm_count_tokens');
  late final MobilelmBenchmark _benchmark =
      _lib.lookupFunction<MobilelmBenchmarkNative, MobilelmBenchmark>(
          'mobilelm_benchmark');

  static MobilelmCore? _cached;

  /// Load the core, or explain why it could not be loaded.
  ///
  /// Absence is a normal, expected state, not an exception: a debug build
  /// predating this wiring, a web target, or a test on a laptop. Callers that
  /// care ask [isAvailable] first. Absence is *not* expected on a release APK,
  /// which is why CI asserts the two `.so` files are inside it.
  static MobilelmCore? tryLoad() {
    if (_cached != null) return _cached;
    if (!Platform.isAndroid) return null;
    try {
      final lib = DynamicLibrary.open(kCoreLibraryName);
      // Fail here rather than at the first call: a lookup for a symbol that is
      // not there throws deep inside whatever needed it, and the message names
      // the field rather than the ABI.
      final core = MobilelmCore._(lib);
      core.abiVersion;
      _cached = core;
      return core;
    } catch (e) {
      return null;
    }
  }

  /// Whether the core is present. Same contract as
  /// `SdFfiBindings.Backend.isAvailable`.
  static bool get isAvailable => tryLoad() != null;

  // -------------------------------------------------------------------------
  // Calls
  // -------------------------------------------------------------------------

  /// The ABI revision the native side was built at.
  ///
  /// A `c"…"` literal's pointer is stable and is **not** an owned allocation, so
  /// this is the one returned string that must not be freed. It is copied into a
  /// Dart string immediately and the pointer never leaves this class.
  String get abiVersion => _abiVersion().toDartString();

  /// The reason the last native call on this isolate failed, or null.
  String? get lastError {
    final p = _lastError();
    if (p == nullptr) return null;
    final text = p.toDartString();
    _stringFree(p);
    return text;
  }

  /// The optional C API symbols [runtimePath] does not have, as a list of names.
  ///
  /// The answer to "why is temperature doing nothing" on a device whose runtime is
  /// not the one this build was tested against. Empty means the runtime has
  /// everything this build knows how to use.
  List<String> symbolsMissing(String runtimePath) {
    final path = runtimePath.toNativeUtf8();
    try {
      final p = _symbolsMissing(path);
      if (p == nullptr) {
        throw MobilelmException(lastError ?? 'symbols_missing failed',
            symbol: 'mobilelm_symbols_missing');
      }
      final decoded = jsonDecode(p.toDartString());
      _stringFree(p);
      return (decoded as List).cast<String>();
    } finally {
      malloc.free(path);
    }
  }

  /// What `/proc` and the vendor libraries say about this device.
  ///
  /// [npuDir] is `/vendor/lib64` on most phones. What this can and cannot answer
  /// is the point: it lists what is on disk, and the caller decides what an app
  /// may link. On this phone the NPU verdict needs both, and the second half is
  /// the linker namespace — see `docs/BENCH.md`, "Arm E".
  Map<String, dynamic> probe({String npuDir = '/vendor/lib64'}) {
    final dir = npuDir.toNativeUtf8();
    try {
      final p = _probe(dir);
      if (p == nullptr) {
        throw MobilelmException(
            lastError ?? 'probe failed', symbol: 'mobilelm_probe');
      }
      final decoded = jsonDecode(p.toDartString()) as Map<String, dynamic>;
      _stringFree(p);
      return decoded;
    } finally {
      malloc.free(dir);
    }
  }

  /// The accelerator plan for a user's choice.
  ///
  /// This is the one place the ladder is decided. The rule used to be
  /// `planLiteRtTier` in `acceleration.dart` *and* `probe.rs` in Rust, and two
  /// implementations of one rule is two answers waiting to disagree — usually on
  /// the device nobody tests on, in the code that decides whether a model's
  /// NPU is used. It is a pure function now, so `cargo test` covers it.
  ///
  /// [npuAvailable] is a finding, not a guess: read it from [probe] plus whatever
  /// else the platform can tell you. This class does not invent it.
  AccelerationPlan plan(String mode,
      {bool forceCpu = false, bool npuAvailable = false}) {
    final m = mode.toNativeUtf8();
    try {
      final p = _plan(m, forceCpu ? 1 : 0, npuAvailable ? 1 : 0);
      if (p == nullptr) {
        throw MobilelmException(
            lastError ?? 'plan failed', symbol: 'mobilelm_plan');
      }
      final decoded = jsonDecode(p.toDartString()) as Map<String, dynamic>;
      _stringFree(p);
      return AccelerationPlan(
        requested: decoded['requested'] as String,
        chosen: decoded['chosen'] as String,
        reason: decoded['reason'] as String?,
        exact: decoded['exact'] as bool,
      );
    } finally {
      malloc.free(m);
    }
  }

  /// Load a model and open a conversation. Returns an opaque handle.
  ///
  /// Every `char*` is optional except [runtimePath] and [modelPath], and each is
  /// named after the C API call it feeds so a value cannot be paired with the
  /// wrong knob. [visionBackend] and [audioBackend] of null mean "this model has
  /// no such encoder" — never "decide later": the engine is built without the
  /// encoder, and sending it media after that is a crash on a thread nothing is
  /// watching, which is why they are here rather than inferred.
  Pointer<Void> createEngine({
    required String runtimePath,
    required String modelPath,
    required String backend,
    int nCtx = 0,
    int nThreads = 0,
    String? cacheDir,
    String? dispatchDir,
    String? visionBackend,
    String? audioBackend,
    String? systemPrompt,
  }) {
    final alloc = _Alloc();
    try {
      final handle = _engineCreate(
        alloc.str(runtimePath),
        alloc.str(modelPath),
        alloc.str(backend),
        nCtx,
        nThreads,
        alloc.strOrNull(cacheDir),
        alloc.strOrNull(dispatchDir),
        alloc.strOrNull(visionBackend),
        alloc.strOrNull(audioBackend),
        alloc.strOrNull(systemPrompt),
      );
      if (handle == nullptr) {
        throw MobilelmException(
          lastError ?? 'engine_create failed',
          symbol: 'mobilelm_engine_create',
        );
      }
      return handle;
    } finally {
      alloc.free();
    }
  }

  /// Free an engine. Null is a no-op, so a double free from a shutdown path that
  /// races a cancel is harmless.
  void freeEngine(Pointer<Void> handle) => _engineFree(handle);

  /// Which sampler type the open conversation is actually sampling with.
  ///
  /// Nullable because the answer genuinely is "none" in two different cases —
  /// an engine with no sampler at all, and a LiteRT runtime that implements none
  /// of the three types. Both end in the engine's default, and neither is worth
  /// an exception on a path that runs per turn.
  SamplerReport? samplerReport(Pointer<Void> handle) {
    final p = _samplerReport(handle);
    if (p == nullptr) {
      final err = lastError;
      // A runtime that cannot say is not a failure of the turn: the engine's
      // default is in force, which is a working sampler.
      if (err != null) {
        print('[LiteRt] sampler report unavailable: $err');
      }
      return null;
    }
    final decoded = jsonDecode(p.toDartString()) as Map<String, dynamic>;
    _stringFree(p);
    return SamplerReport.fromJson(decoded);
  }

  /// The load report: the tier asked for, the tier that ran, why they differ.
  LoadReport engineLoadReport(Pointer<Void> handle) {
    final p = _engineLoadReport(handle);
    if (p == nullptr) {
      throw MobilelmException(
          lastError ?? 'engine_load_report failed',
          symbol: 'mobilelm_engine_load_report');
    }
    final decoded = jsonDecode(p.toDartString()) as Map<String, dynamic>;
    _stringFree(p);
    return LoadReport(
      runtime: decoded['runtime'] as String,
      requested: decoded['requested'] as String,
      actual: decoded['actual'] as String,
      fallbackReason: decoded['fallback_reason'] as String?,
      loadMs: (decoded['load_ms'] as num).toInt(),
      modelBytes: (decoded['model_bytes'] as num).toInt(),
      capabilities: (decoded['capabilities'] as num).toInt(),
      nCtx: (decoded['n_ctx'] as num).toInt(),
      notes: (decoded['notes'] as List).cast<String>(),
    );
  }

  /// Open or replace the conversation. Any string may be null for "unchanged".
  ///
  /// The sampler is fixed at creation, so a temperature change is a new
  /// conversation — which is what the app already does
  /// (`_ensureLiteRtConversation` compares the temperature), and this is the
  /// call it makes rather than a second rule about when to reload.
  ///
  /// [historyJson] is a JSON **array** of rendered messages. `[]` means no
  /// history; an empty string or a single message object is an error, because
  /// half a history is worse than none — the model would answer as if the earlier
  /// turns never happened.
  void openConversation(
    Pointer<Void> handle, {
    String? systemPrompt,
    String? historyJson,
    double temperature = 0,
    int topK = 0,
    double topP = 0,
    bool greedy = false,
    int maxOutputTokens = 0,
  }) {
    final alloc = _Alloc();
    try {
      final rc = _conversationOpen(
        handle,
        alloc.strOrNull(systemPrompt),
        alloc.strOrNull(historyJson ?? '[]'),
        temperature,
        topK,
        topP,
        greedy ? 1 : 0,
        maxOutputTokens,
      );
      if (rc != 0) {
        throw MobilelmException(
          lastError ?? 'conversation_open failed',
          symbol: 'mobilelm_conversation_open',
        );
      }
    } finally {
      alloc.free();
    }
  }

  /// Stream one turn, blocking until it finishes. Returns 0, or throws.
  ///
  /// **Blocking** on the calling isolate. The C API's send is non-blocking and
  /// the engine keeps calling back on its own thread, so a call that returned
  /// immediately would leave the caller owning the lifetime of its own callback
  /// context. Blocking makes that impossible: the chunks arrive while this call is
  /// still on the stack.
  ///
  /// Which is why [onToken] arrives as a `NativeCallable.listener` rather than a
  /// `Pointer.fromFunction` callback: `listener` may be invoked from any thread,
  /// which is exactly the situation, and `isolateLocal` may not.
  ///
  /// [messageJson] is a rendered message object, not a bare prompt — the C API
  /// wants JSON and a bare string is accepted as an empty turn. The app's
  /// multimodal turn included; `LiteRtMessage` builds it.
  int sendStream(
    Pointer<Void> handle,
    String messageJson,
    int maxTokens,
    NativeCallable<MobilelmStreamCallbackNative> callback,
    int ctx,
  ) {
    final msg = messageJson.toNativeUtf8();
    try {
      // Logged because "did the callback pointer arrive null?" has been the one
      // thing every failed device run had in common, and `-999` cannot tell it
      // apart from any other throw. A pointer prints as an address or `nullptr`,
      // so this settles the question instead of leaving it to be reasoned about.
      final fn = callback.nativeFunction;
      print('[LiteRt] sendStream fn=$fn maxTokens=$maxTokens '
          'jsonBytes=${messageJson.length}');
      final rc = _sendStream(handle, msg, maxTokens, fn, ctx);
      print('[LiteRt] sendStream rc=$rc');
      if (rc != 0) {
        throw MobilelmException(
          lastError ?? 'send_stream failed',
          symbol: 'mobilelm_send_stream',
        );
      }
      return rc;
    } finally {
      malloc.free(msg);
    }
  }

  /// One blocking turn with no streaming. For smoke tests and the harness, not
  /// for the app: the UI streams, and a path only tests use is the path that
  /// rots.
  String sendText(Pointer<Void> handle, String prompt) {
    final alloc = _Alloc();
    try {
      final p = _sendText(handle, alloc.str(prompt));
      if (p == nullptr) {
        throw MobilelmException(
            lastError ?? 'send_text failed',
            symbol: 'mobilelm_send_text');
      }
      final text = p.toDartString();
      _stringFree(p);
      return text;
    } finally {
      alloc.free();
    }
  }

  /// Tokens [text] would occupy, per the engine's own tokenizer. -1 on failure.
  int countTokens(Pointer<Void> handle, String text) {
    final alloc = _Alloc();
    try {
      final n = _countTokens(handle, alloc.str(text));
      if (n < 0) {
        throw MobilelmException(
          lastError ?? 'count_tokens failed — this runtime has no tokenizer API',
          symbol: 'mobilelm_count_tokens',
        );
      }
      return n;
    } finally {
      alloc.free();
    }
  }

  /// The runtime's own timings for this conversation, or null when the runtime
  /// has no benchmark family or no turn has run.
  ///
  /// These are the engine's numbers, not wall time measured here. The difference
  /// matters: a harness's own TTFT includes the JSON unwrap and the channel hop,
  /// and quoting that as the engine's time is measuring the plumbing.
  EngineBenchmark? benchmark(Pointer<Void> handle) {
    final p = _benchmark(handle);
    if (p == nullptr) return null;
    final decoded = jsonDecode(p.toDartString()) as Map<String, dynamic>;
    _stringFree(p);
    return EngineBenchmark(
      ttftMs: (decoded['ttft_ms'] as num).toDouble(),
      prefillTokens: (decoded['prefill_tokens'] as num).toInt(),
      decodeTokens: (decoded['decode_tokens'] as num).toInt(),
      prefillTps: (decoded['prefill_tps'] as num).toDouble(),
      decodeTps: (decoded['decode_tps'] as num).toDouble(),
    );
  }
}

/// Batches the native string allocations for one call, so a call with six string
/// arguments does not need six try/finally pairs.
class _Alloc {
  final List<Pointer<Utf8>> _all = [];

  Pointer<Utf8> str(String s) {
    final p = s.toNativeUtf8();
    _all.add(p);
    return p;
  }

  /// Null for null and for the empty string, because the native side reads both
  /// as "not supplied" and an empty C string is a *different* thing to the C API:
  /// it names a value rather than the absence of one.
  Pointer<Utf8> strOrNull(String? s) =>
      (s == null || s.isEmpty) ? nullptr : str(s);

  void free() {
    for (final p in _all) {
      malloc.free(p);
    }
    _all.clear();
  }
}

/// The accelerator tier the core chose, and whether it is what was asked for.
class AccelerationPlan {
  const AccelerationPlan({
    required this.requested,
    required this.chosen,
    required this.reason,
    required this.exact,
  });

  final String requested;
  final String chosen;

  /// Why [chosen] is not [requested], or null when it did survive — which is the
  /// common case, not the exception.
  final String? reason;

  /// True when the requested tier survived.
  final bool exact;

  /// One line for a log, in the same shape the native side emits — so a line copied
  /// out of a Dart print and one out of a `mobilelm_plan` response are comparable
  /// by eye, which is the point of reading both.
  @override
  String toString() => 'requested=$requested chosen=$chosen exact=$exact'
      '${reason == null ? '' : ' reason="$reason"'}';
}

/// What a load actually produced.
class LoadReport {
  const LoadReport({
    required this.runtime,
    required this.requested,
    required this.actual,
    required this.fallbackReason,
    required this.loadMs,
    required this.modelBytes,
    required this.capabilities,
    required this.nCtx,
    required this.notes,
  });

  /// The `liblitert-lm.so` this came from.
  final String runtime;

  /// The tier that was asked for.
  final String requested;

  /// The tier that is live.
  ///
  /// **LiteRT-LM does not report which accelerator it settled on**, so this is
  /// the requested one. The core's rule is "report the backend that ran, never the
  /// one requested", and the honest way to honour it when the engine will not
  /// answer is to say so rather than to display a guess as an observation. A
  /// device run logged `RegisterAccelerator: name=CpuAccelerator` after failing
  /// the NPU, so the two agreed there; nothing guarantees they always will.
  final String actual;

  final String? fallbackReason;
  final int loadMs;
  final int modelBytes;

  /// 1 = vision, 2 = audio, 0 = text only. Read from a probe after load, never
  /// assumed from the catalogue.
  final int capabilities;
  final int nCtx;

  /// Free-form notes worth a log line: a missing optional symbol, an NPU dispatch
  /// dir that was set, the context ceiling the driver clamped.
  final List<String> notes;
}

/// The engine's own measurements. `null` prefill means the runtime does not
/// report it, which is different from a prefill of zero.
class EngineBenchmark {
  const EngineBenchmark({
    required this.ttftMs,
    required this.prefillTokens,
    required this.decodeTokens,
    required this.prefillTps,
    required this.decodeTps,
  });

  final double ttftMs;
  final int prefillTokens;
  final int decodeTokens;
  final double prefillTps;
  final double decodeTps;

  /// Prefill and decode are reported separately on purpose. On a phone they
  /// behave differently enough that averaging them hides which one regressed,
  /// and decode deliberately excludes TTFT.
  @override
  String toString() => 'ttft=${ttftMs.toStringAsFixed(0)}ms '
      'prefill=${prefillTokens}t/${prefillTps.toStringAsFixed(2)}tok/s '
      'decode=${decodeTokens}t/${decodeTps.toStringAsFixed(2)}tok/s';
}
