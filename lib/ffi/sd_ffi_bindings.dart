import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

// ---------------------------------------------------------------------------
// Enums (must match stable-diffusion.h)
// ---------------------------------------------------------------------------

enum QuantizationType {
  f32, // 0  - full precision float32
  f16, // 1  - half precision (default)
  q4_0, // 2  - 4-bit, fastest, smallest
  q4_1, // 3  - 4-bit, slightly better quality
  q5_0, // 6  - 5-bit
  q5_1, // 7  - 5-bit, better quality
  q8_0, // 8  - 8-bit, good balance of speed/quality
  q8_1, // 9  - 8-bit
  q2_k, // 10 - 2-bit K-quant, smallest
  q3_k, // 11 - 3-bit K-quant
  q4_k, // 12 - 4-bit K-quant, recommended for quality
  q5_k, // 13 - 5-bit K-quant
  q6_k, // 14 - 6-bit K-quant, near-lossless
  q8_k, // 15 - 8-bit K-quant
}

extension QuantizationTypeExtension on QuantizationType {
  String get displayName {
    switch (this) {
      case QuantizationType.f32:
        return 'FP32';
      case QuantizationType.f16:
        return 'FP16';
      case QuantizationType.q4_0:
        return 'Q4_0 (fastest)';
      case QuantizationType.q4_1:
        return 'Q4_1';
      case QuantizationType.q5_0:
        return 'Q5_0';
      case QuantizationType.q5_1:
        return 'Q5_1';
      case QuantizationType.q8_0:
        return 'Q8_0 (balanced)';
      case QuantizationType.q8_1:
        return 'Q8_1';
      case QuantizationType.q2_k:
        return 'Q2_K (smallest)';
      case QuantizationType.q3_k:
        return 'Q3_K';
      case QuantizationType.q4_k:
        return 'Q4_K (recommended)';
      case QuantizationType.q5_k:
        return 'Q5_K';
      case QuantizationType.q6_k:
        return 'Q6_K (near-lossless)';
      case QuantizationType.q8_k:
        return 'Q8_K';
    }
  }

  int get nativeValue {
    switch (this) {
      case QuantizationType.f32:
        return 0;
      case QuantizationType.f16:
        return 1;
      case QuantizationType.q4_0:
        return 2;
      case QuantizationType.q4_1:
        return 3;
      case QuantizationType.q5_0:
        return 6;
      case QuantizationType.q5_1:
        return 7;
      case QuantizationType.q8_0:
        return 8;
      case QuantizationType.q8_1:
        return 9;
      case QuantizationType.q2_k:
        return 10;
      case QuantizationType.q3_k:
        return 11;
      case QuantizationType.q4_k:
        return 12;
      case QuantizationType.q5_k:
        return 13;
      case QuantizationType.q6_k:
        return 14;
      case QuantizationType.q8_k:
        return 15;
    }
  }
}

enum Backend {
  cpu,
  vulkan,
  opencl,
}

extension BackendExtension on Backend {
  String get displayName {
    switch (this) {
      case Backend.cpu:
        return 'CPU';
      case Backend.vulkan:
        return 'Vulkan (GPU)';
      case Backend.opencl:
        return 'OpenCL (GPU)';
    }
  }

  String get libraryName {
    switch (this) {
      case Backend.cpu:
        return 'libsd_jni.so';
      case Backend.vulkan:
        return 'libsd_jni_vulkan.so';
      case Backend.opencl:
        return 'libsd_jni_opencl.so';
    }
  }

  /// Checks if the backend's native library file is present in the APK.
  /// This does a lightweight existence check without fully loading the library.
  bool get isAvailable {
    if (this == Backend.cpu) return true;
    if (!Platform.isAndroid) return false;
    try {
      // Try to open the library — if it fails, the .so isn't bundled
      DynamicLibrary.open(libraryName);
      // Don't keep it open here; just verify it exists
      // (DynamicLibrary doesn't have a close() method in Dart FFI)
      return true;
    } catch (e) {
      return false;
    }
  }
}

enum SampleMethod {
  euler,
  eulerA,
  heun,
  dpm2,
  dpmpp2sA,
  dpmpp2m,
  dpmpp2mv2,
  ipndm,
  ipndmV,
  lcm,
  ddimTrailing,
  tcd,
  resMultistep,
  res2s,
  erSde,
}

enum Schedule {
  discrete,
  karras,
  exponential,
  ays,
  gits,
  sgmUniform,
  simple,
  smoothstep,
  klOptimal,
  lcm,
  bongTangent,
}

// ---------------------------------------------------------------------------
// Native typedefs
// ---------------------------------------------------------------------------

// The two callbacks take a trailing `Pointer<Void>` and return `void`, which is
// exactly what `NativeCallable.listener` requires — the analyzer enforces the
// return type, and the C trampolines in `sd_jni_wrapper.cpp` declare the same
// shape. The reason is in that file: the ggml workers that call these are
// process threads belonging to no isolate, and a `Pointer.fromFunction` can only
// ever be invoked from the isolate that made it. Getting this wrong aborts the
// process with SIGABRT, not an exception.
typedef ProgressCallbackNative = Void Function(
    Int32 step, Int32 steps, Float time, Pointer<Void> userData);
typedef LogCallbackNative = Void Function(
    Int32 level, Pointer<Utf8> text, Pointer<Void> userData);

typedef SdFfiSetProgressCallbackNative = Void Function(
    Pointer<NativeFunction<ProgressCallbackNative>> cb);
typedef SdFfiSetProgressCallback = void Function(
    Pointer<NativeFunction<ProgressCallbackNative>> cb);

typedef SdFfiSetLogCallbackNative = Void Function(
    Pointer<NativeFunction<LogCallbackNative>> cb);
typedef SdFfiSetLogCallback = void Function(
    Pointer<NativeFunction<LogCallbackNative>> cb);

typedef SdFfiInitNative = Pointer<Void> Function(
  Pointer<Utf8> modelPath,
  Int32 nThreads,
  Bool flashAttn,
  Bool vaeTiling,
  Pointer<Utf8> taesdPath,
  Int32 wtype,
  Int32 backend,
);
typedef SdFfiInit = Pointer<Void> Function(
  Pointer<Utf8> modelPath,
  int nThreads,
  bool flashAttn,
  bool vaeTiling,
  Pointer<Utf8> taesdPath,
  int wtype,
  int backend,
);

// Extended init exposing full sd_ctx_params_t fields
typedef SdFfiInitExNative = Pointer<Void> Function(
  Pointer<Utf8> modelPath,
  Int32 nThreads,
  Bool flashAttn,
  Bool vaeTiling,
  Pointer<Utf8> taesdPath,
  Pointer<Utf8> vaePath,
  Pointer<Utf8> clipLPath,
  Int32 wtype,
  Int32 backend,
  Bool offloadParamsToCpu,
  Bool enableMmap,
  Bool keepVaeOnCpu,
  Float maxVram,
);
typedef SdFfiInitEx = Pointer<Void> Function(
  Pointer<Utf8> modelPath,
  int nThreads,
  bool flashAttn,
  bool vaeTiling,
  Pointer<Utf8> taesdPath,
  Pointer<Utf8> vaePath,
  Pointer<Utf8> clipLPath,
  int wtype,
  int backend,
  bool offloadParamsToCpu,
  bool enableMmap,
  bool keepVaeOnCpu,
  double maxVram,
);

typedef SdFfiFreeNative = Void Function(Pointer<Void> ctx);
typedef SdFfiFree = void Function(Pointer<Void> ctx);

typedef SdFfiGenerateNative = Pointer<Uint8> Function(
  Pointer<Void> ctx,
  Pointer<Utf8> prompt,
  Pointer<Utf8> negativePrompt,
  Int32 width,
  Int32 height,
  Int32 steps,
  Int64 seed,
  Float cfgScale,
  Int32 sampleMethod,
  Int32 schedule,
  Bool vaeTiling,
  Pointer<IntPtr> outSize,
);
typedef SdFfiGenerate = Pointer<Uint8> Function(
  Pointer<Void> ctx,
  Pointer<Utf8> prompt,
  Pointer<Utf8> negativePrompt,
  int width,
  int height,
  int steps,
  int seed,
  double cfgScale,
  int sampleMethod,
  int schedule,
  bool vaeTiling,
  Pointer<IntPtr> outSize,
);

typedef SdFfiGetCoresNative = Int32 Function();
typedef SdFfiGetCores = int Function();

// ---------------------------------------------------------------------------
// Global isolate communication
// ---------------------------------------------------------------------------

SendPort? _globalSendPort;

// `user_data` is unused on this side and that is deliberate: it is the VM's
// handle for the callable, not payload, and reading it as anything would be a
// reinterpretation of memory the Dart side does not own.
//
// The send is guarded on a null port rather than assumed: the native side can
// outlive the isolate that registered it during teardown, and a `!` here would
// throw on a worker thread, where an unhandled Dart error has nowhere to go.
void _staticProgressCallback(
    int step, int steps, double time, Pointer<Void> userData) {
  _globalSendPort?.send({
    'type': 'progress',
    'step': step,
    'steps': steps,
    'time': time,
  });
}

void _staticLogCallback(
    int level, Pointer<Utf8> text, Pointer<Void> userData) {
  _globalSendPort?.send({
    'type': 'log',
    'level': level,
    'message': text.toDartString(),
  });
}

// ---------------------------------------------------------------------------
// FFI Bindings singleton
// ---------------------------------------------------------------------------

class SdFfiBindings {
  static DynamicLibrary? _lib;
  static String _currentBackendLib = '';

  /// Returns the backend whose library is currently loaded,
  /// or [Backend.cpu] if nothing is loaded yet.
  static Backend get loadedBackend {
    if (_currentBackendLib.isEmpty) return Backend.cpu;
    return Backend.values.firstWhere(
      (b) => b.libraryName == _currentBackendLib,
      orElse: () => Backend.cpu,
    );
  }

  static late SdFfiSetProgressCallback setProgressCallback;
  static late SdFfiSetLogCallback setLogCallback;
  static late SdFfiInit init;
  static late SdFfiInitEx initEx;
  static late SdFfiFree freeCtx;
  static late SdFfiGenerate generate;
  static late SdFfiGetCores getCores;

  // The callables are held in fields rather than being built and dropped, for
  // two reasons that both cost a crash or a leak: `NativeCallable.listener`
  // registers a trampoline in the VM that is only released by `close()`, and
  // the native side holds a bare function pointer that would outlive the Dart
  // object it points into.
  static NativeCallable<ProgressCallbackNative>? _progressCallable;
  static NativeCallable<LogCallbackNative>? _logCallable;

  /// Initialize FFI bindings for a specific backend.
  /// Call this before using any other functions.
  static void initialize([Backend backend = Backend.cpu]) {
    if (Platform.isAndroid) {
      final libName = backend.libraryName;
      if (_lib != null && _currentBackendLib == libName) return;

      print('[SdFfiBindings] Loading backend library: $libName');
      try {
        _lib = DynamicLibrary.open(libName);
        _currentBackendLib = libName;
        print('[SdFfiBindings] Loaded: $libName');
      } catch (e) {
        print('[SdFfiBindings] Failed to load $libName: $e');
        rethrow;
      }
    } else {
      throw UnsupportedError('SdFfiBindings only supports Android');
    }

    _lookupFunctions();
  }

  static void _lookupFunctions() {
    if (_lib == null)
      throw StateError('FFI library not loaded. Call initialize() first.');

    setProgressCallback = _lib!.lookupFunction<SdFfiSetProgressCallbackNative,
        SdFfiSetProgressCallback>('sd_ffi_set_progress_callback');

    setLogCallback = _lib!
        .lookupFunction<SdFfiSetLogCallbackNative, SdFfiSetLogCallback>(
            'sd_ffi_set_log_callback');

    init = _lib!.lookupFunction<SdFfiInitNative, SdFfiInit>('sd_ffi_init');
    initEx =
        _lib!.lookupFunction<SdFfiInitExNative, SdFfiInitEx>('sd_ffi_init_ex');
    // Ensure the backend library is actually available; if not, mark it unavailable
    if (_currentBackendLib != Backend.cpu.libraryName) {
      final backend =
          Backend.values.firstWhere((b) => b.libraryName == _currentBackendLib);
      print('[SdFfiBindings] Backend ${backend.displayName} loaded');
    }

    freeCtx = _lib!.lookupFunction<SdFfiFreeNative, SdFfiFree>('sd_ffi_free');

    generate = _lib!
        .lookupFunction<SdFfiGenerateNative, SdFfiGenerate>('sd_ffi_generate');

    getCores = _lib!
        .lookupFunction<SdFfiGetCoresNative, SdFfiGetCores>('sd_ffi_get_cores');
  }

  /// Registers the native callbacks with this isolate's message port.
  ///
  /// `NativeCallable.listener`, not `Pointer.fromFunction`: the ggml workers
  /// that drive these callbacks are process threads with no isolate attached,
  /// and the VM aborts the whole process with SIGABRT if one of them reaches a
  /// `Pointer.fromFunction` — `Cannot invoke native callback outside an
  /// isolate`. A listener keeps the isolate as the owner while letting the VM
  /// marshal the call in from anywhere.
  static void setupCallbacks(SendPort sendPort) {
    _globalSendPort = sendPort;

    // Rebuild on every registration. `clearCallbacks` closes the previous
    // pair, so `??=` here would hand the native side a pointer to a callable
    // the VM had already torn down — the crash this replaces, in a quieter
    // costume.
    _progressCallable?.close();
    _logCallable?.close();

    _progressCallable = NativeCallable<ProgressCallbackNative>.listener(
      _staticProgressCallback,
    );
    _logCallable =
        NativeCallable<LogCallbackNative>.listener(_staticLogCallback);

    setProgressCallback(_progressCallable!.nativeFunction);
    setLogCallback(_logCallable!.nativeFunction);
  }

  /// Detaches the native side and releases the VM's trampolines.
  ///
  /// The order matters and is not symmetric: the native pointers are cleared
  /// **before** `close()`, so no worker can land on a closed callable in
  /// between. Doing it the other way round leaves a window where the library
  /// holds a pointer into a trampoline that no longer exists.
  static void clearCallbacks() {
    setProgressCallback(Pointer.fromAddress(0));
    setLogCallback(Pointer.fromAddress(0));
    _globalSendPort = null;
    _progressCallable?.close();
    _logCallable?.close();
    _progressCallable = null;
    _logCallable = null;
  }
}
