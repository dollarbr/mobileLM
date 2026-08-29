import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_litert_lm/flutter_litert_lm.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';

import '../controllers/settings_controller.dart';
import '../core/constants.dart';
import 'acceleration.dart';
import 'hive_service.dart';

/// Whether the current platform supports local inference.
bool get supportsLocalInference => Platform.isAndroid || Platform.isIOS;

/// Result from model loading.
class LoadResult {
  final bool success;
  final String message;
  final String gpuName;
  final int gpuLayers;
  final String runtime;
  final String backend;
  LoadResult({
    required this.success,
    required this.message,
    this.gpuName = '',
    this.gpuLayers = 0,
    this.runtime = '',
    this.backend = '',
  });
}

/// Android & iOS inference engine — wraps llama_flutter_android.
class InferenceEngine {
  LlamaController? _controller;
  LiteLmEngine? _liteEngine;
  LiteLmConversation? _liteConversation;
  StreamSubscription? _subscription;
  StreamSubscription? _loadProgressSub;
  Timer? _idleTimer;
  void Function()? _onStop;
  bool _isLiteRt = false;
  bool _disposed = false;
  bool _hasLoadedModel = false;
  String? _liteConversationSystemPrompt;
  double? _liteConversationTemperature;
  bool _liteConversationHasMessages = false;

  /// What the loaded GGUF projector supports, or null when there is none.
  MultimodalSupport? _mmprojSupport;
  /// Sampler values this session generates with: user globals overlaid by
  /// per-model saves, then by whatever the GGUF itself declares.
  final Map<String, double> _effectiveParams = {};
  String _mediaMarker = '<__media__>';

  MultimodalSupport? get multimodalSupport => _mmprojSupport;
  String get mediaMarker => _mediaMarker;

  Future<LoadResult> loadModel({
    required String modelPath,
    String? mmprojPath,
    String? modelRuntime,
    required int contextSize,
    required String deviceTier,
    bool isTensorSoC = false,
    /// llama.cpp CPU threads, or 0 for half the cores.
    int cpuThreads = 0,
    /// Keep the vision encoder off the GPU even when the layers are on it.
    bool mmprojForceCpu = false,
    String liteRtPerformanceMode = 'auto_fast',
    bool forceLiteRtCpu = false,
    bool clearLiteRtCache = false,
    bool enableLiteRtVision = false,
    void Function(double)? onProgress,
  }) async {
    _disposed = false;
    final runtime = _runtimeFor(modelPath, modelRuntime);
    if (runtime == 'litert') {
      return _loadLiteRtModel(
        modelPath,
        contextSize: contextSize,
        performanceMode: liteRtPerformanceMode,
        forceCpu: forceLiteRtCpu,
        clearCache: clearLiteRtCache,
        enableVision: enableLiteRtVision,
        onProgress: onProgress,
      );
    }

    _isLiteRt = false;
    _controller = LlamaController();

    // ── Accelerator ladder (GGUF path: NPU is LiteRT-only, so GPU -> CPU here) ──
    int gpuLayers = 0;
    String gpuNameStr = '';

    try {
      final gpu = await _controller!.detectGpu();
      gpuNameStr = gpu.gpuName;

      print('[Inference] GPU: ${gpu.gpuName}');
      print('[Inference]   Vulkan: ${gpu.vulkanSupported}');
      print('[Inference]   Free RAM: ${gpu.freeRamBytes ~/ 1024 ~/ 1024}MB');
      print('[Inference]   Recommended layers: ${gpu.recommendedGpuLayers}');

      final plan = planAcceleration(
        mode: liteRtPerformanceMode,
        vulkanSupported: gpu.vulkanSupported,
        recommendedGpuLayers: gpu.recommendedGpuLayers.toInt(),
      );
      gpuLayers = plan.gpuLayers;
      print('[Inference] ${plan.reason}');
    } catch (e) {
      print('[Inference] GPU detection failed: $e — CPU fallback');
    }

    // ── Thread Tuning ──
    // Default is half the cores, not a number per tier. The tier string
    // describes RAM, not the CPU, so the old table handed every GPU device 4
    // threads and every 'high' device 5 whether the chip had 4 cores or 12.
    //
    // Half is not politeness towards the system: ggml syncs every thread at
    // the end of each op, so on a big.LITTLE phone the little cores set the
    // pace for the big ones and more threads can measure slower. The setting
    // exists because that is worth testing per device, not assuming.
    final cores = Platform.numberOfProcessors;
    int threads = cpuThreads > 0 ? cpuThreads : (cores ~/ 2).clamp(2, 6);
    threads = threads.clamp(1, cores < 1 ? 1 : cores);
    print('[Inference] Threads: $threads of $cores cores'
        '${cpuThreads > 0 ? ' (user set)' : ' (auto, half)'}');

    // Google Tensor SoC (Pixel 6/7/8) has known Q4_K_M dequant bugs
    // that corrupt logits at >1 thread on Gemma models. Force single-threaded
    // to eliminate KV cache races in the quantization dot-product path.
    final modelName = modelPath.toLowerCase();
    if (isTensorSoC && modelName.contains('gemma')) {
      threads = 1;
      print(
          '[Inference] Tensor SoC + Gemma detected — forcing single-threaded inference');
    }

    // ── Load Progress ──
    // Re-created on every backend switch below: the subscription dies with the
    // old LlamaController when dispose() closes its stream.
    Future<void> subscribeProgress() async {
      await _loadProgressSub?.cancel();
      _loadProgressSub = null;
      try {
        _loadProgressSub = _controller!.loadProgress.listen((progress) {
          onProgress?.call(_normalizeProgress(progress));
        });
      } catch (_) {}
    }
    await subscribeProgress();

    // ── Load ──
    Future<void> loadWith(int layers) async {
      await _controller!.loadModel(
        modelPath: modelPath,
        threads: threads,
        contextSize: contextSize,
        gpuLayers: layers,
      );
    }
    await loadWith(gpuLayers);
    _hasLoadedModel = true;

    // ── Auto Fast micro-benchmark ──
    // Vulkan present says a GPU *can* take the layers; it does not say the GPU
    // is fast. On small models the Mali here prefilled 6x slower than the CPU
    // (3.4 vs 21.2 tok/s) because shader dispatch dominates. So when the user
    // asked for Auto Fast and we loaded onto the GPU, measure both backends on
    // one short prefill and keep the winner before the first real prompt.
    //
    // The verdict is cached per model file in Hive, so a model benchmarks once
    // ever — later loads go straight to the winning backend. The key includes
    // the byte size so a re-quantized file under the same name re-benchmarks.
    String benchKey() => '${AppConstants.autoFastBenchKeyPrefix}'
        '${modelPath.split('/').last}:${File(modelPath).lengthSync()}';
    String? cachedVerdict;
    try {
      final hive = Get.find<HiveService>();
      cachedVerdict = hive.getSetting<String>(benchKey());
    } catch (_) {}

    bool benchOnCpu = false;
    if (liteRtPerformanceMode == 'auto_fast' && gpuLayers > 0) {
      if (cachedVerdict == 'cpu') {
        print('[Inference] Auto Fast: cached CPU win for this model'
            ' — loading straight to CPU');
        await _controller!.dispose();
        _controller = LlamaController();
        await subscribeProgress();
        await loadWith(0);
        gpuLayers = 0;
        benchOnCpu = true;
      } else {
        if (cachedVerdict == 'gpu') {
          print('[Inference] Auto Fast: cached GPU win for this model'
              ' — skipping benchmark');
        } else {
          try {
            print('[Inference] Auto Fast: benchmarking GPU prefill…');
            final gpuMs = await _benchPrefillMs(_controller!);

            print('[Inference] Auto Fast: reloading on CPU for comparison…');
            await _controller!.dispose();
            _controller = LlamaController();
            await subscribeProgress();
            await loadWith(0);
            benchOnCpu = true;
            final cpuMs = await _benchPrefillMs(_controller!);

            final winner = gpuMs <= cpuMs ? 'gpu' : 'cpu';
            try {
              Get.find<HiveService>().setSetting(benchKey(), winner);
            } catch (_) {}
            print('[Inference] Auto Fast: $winner wins '
                '(${gpuMs <= cpuMs ? gpuMs : cpuMs} ms vs '
                '${gpuMs <= cpuMs ? cpuMs : gpuMs} ms)${cachedVerdict == null ? ' — saved' : ''}');

            if (winner == 'gpu') {
              print('[Inference] Auto Fast: reloading on GPU');
              await _controller!.dispose();
              _controller = LlamaController();
              await subscribeProgress();
              await loadWith(gpuLayers);
              benchOnCpu = false;
            } else {
              gpuLayers = 0;
            }
          } catch (e) {
            // Whatever failed, the model that is currently loaded still works:
            // report honestly which one that is instead of throwing away the load.
            gpuLayers = benchOnCpu ? 0 : gpuLayers;
            print('[Inference] Auto Fast benchmark failed: $e — '
                'keeping ${benchOnCpu ? 'CPU' : 'GPU'} load');
          }
        }
      }
    }

    // ── Multimodal projector ──
    // A GGUF vision or audio model is two files: the weights, loaded above,
    // and the projector that encodes the media. Offloading the encoder to the
    // GPU follows the same decision as the model itself -- when there was not
    // enough memory for a single layer there is none for a ViT either.
    _mmprojSupport = null;
    if (mmprojPath != null && mmprojPath.isNotEmpty) {
      // Separately switchable from the model's own offload: a single 31 KB
      // image measured 183 s to encode with useGpu on this Mali, one thread
      // pegged and no system time -- the signature of a per-op Vulkan
      // fallback shuttling tensors rather than a ViT running on the GPU.
      // Which way is faster is a per-device fact, so like Auto Fast it gets
      // measured once and cached — unless the user pinned CPU explicitly.
      String visionKey() => '${AppConstants.visionBenchKeyPrefix}'
          '${mmprojPath.split('/').last}:${File(mmprojPath).lengthSync()}';

      bool useGpuForProjector = gpuLayers > 0 && !mmprojForceCpu;
      String? visionVerdict;
      if (useGpuForProjector) {
        try {
          visionVerdict =
              Get.find<HiveService>().getSetting<String>(visionKey());
        } catch (_) {}
        if (visionVerdict == 'cpu') {
          useGpuForProjector = false;
          print('[Inference] Vision: cached CPU win — encoder on CPU');
        } else if (visionVerdict == 'gpu') {
          print('[Inference] Vision: cached GPU win — skipping benchmark');
        }
      }

      Future<MultimodalSupport?> loadProjector(bool gpu) {
        return LlamaMultimodal.loadProjector(
          mmprojPath,
          useGpu: gpu,
          nThreads: threads,
        );
      }

      MultimodalSupport? support;
      try {
        if (useGpuForProjector && visionVerdict == null) {
          print('[Inference] Vision: benchmarking GPU encoder…');
          support = await loadProjector(true);
          final gpuMs = await _benchEncodeMs(_controller!);

          print('[Inference] Vision: reloading encoder on CPU…');
          await LlamaMultimodal.freeProjector();
          support = await loadProjector(false);
          final cpuMs = await _benchEncodeMs(_controller!);

          final winner = gpuMs <= cpuMs ? 'gpu' : 'cpu';
          try {
            Get.find<HiveService>().setSetting(visionKey(), winner);
          } catch (_) {}
          print('[Inference] Vision: $winner wins '
              '(${gpuMs <= cpuMs ? gpuMs : cpuMs} ms vs '
              '${gpuMs <= cpuMs ? cpuMs : gpuMs} ms)');

          if (winner == 'gpu') {
            print('[Inference] Vision: reloading encoder on GPU');
            await LlamaMultimodal.freeProjector();
            support = await loadProjector(true);
          } else {
            useGpuForProjector = false;
          }
        } else {
          support = await loadProjector(useGpuForProjector);
        }
      } catch (e) {
        print('[Inference] Vision benchmark failed: $e');
        try {
          await LlamaMultimodal.freeProjector();
        } catch (_) {}
        support = await loadProjector(false);
        useGpuForProjector = false;
      }

      if (support == null) {
        // Not fatal: the model still answers text. Saying so beats a silent
        // downgrade the user only notices when an image is ignored.
        print('[Inference] ⚠ Projector rejected: $mmprojPath');
      } else {
        _mmprojSupport = support;
        _mediaMarker = await LlamaMultimodal.mediaMarker();
        print('[Inference] ✓ Projector loaded: $support '
            '(${useGpuForProjector ? "GPU" : "CPU"})');
      }
    }

    await _applyEffectiveParams(modelPath);

    final accel = gpuLayers > 0
        ? 'GPU ($gpuLayers layers, $gpuNameStr)'
        : 'CPU ($threads threads)';
    print('[Inference] ✓ Model loaded: $accel, ctx=$contextSize');

    return LoadResult(
      success: true,
      message: 'Model loaded ($accel).',
      gpuName: gpuNameStr,
      gpuLayers: gpuLayers,
      runtime: 'llama',
      backend: gpuLayers > 0 ? 'gpu' : 'cpu',
    );
  }

  Future<LoadResult> _loadLiteRtModel(
    String modelPath, {
    required int contextSize,
    required String performanceMode,
    required bool forceCpu,
    required bool clearCache,
    required bool enableVision,
    void Function(double)? onProgress,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
          'LiteRT-LM is enabled for Android only in this app.');
    }

    _isLiteRt = true;
    _controller = null;

    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory('${tempDir.path}/litert_cache');
    // Full ladder here: NPU -> GPU -> CPU. Asking for NPU without a vendor
    // dispatch driver bundled costs a failed engine init before LiteRT's own
    // fallback kicks in, so probe for the driver instead of assuming the SoC
    // can be reached.
    final npu = forceCpu ? const NpuStatus(available: false) : await NpuStatus.probe();
    if (!forceCpu) print('[Inference] $npu');
    final tier = planLiteRtTier(
      mode: forceCpu ? 'cpu_safe' : performanceMode,
      npuAvailable: npu.available,
    );
    final backend = switch (tier) {
      AccelTier.npu => LiteLmBackend.npu,
      AccelTier.gpu => LiteLmBackend.gpu,
      AccelTier.cpu => LiteLmBackend.cpu,
    };
    final backendLabel = tier.name.toUpperCase();

    try {
      onProgress?.call(0.05);
      if (clearCache && await cacheDir.exists()) {
        try {
          await cacheDir.delete(recursive: true);
        } catch (_) {}
      }
      await cacheDir.create(recursive: true);
      onProgress?.call(0.18);

      // Audio rides along with vision. The multimodal .litertlm files this app
      // loads (gemma-3n, gemma-4) carry both encoders in one file, and there is
      // no separate flag to key off; a file with only a vision encoder is
      // caught by the retry below.
      _liteEngine = await _createLiteRtEngine(
        modelPath: modelPath,
        contextSize: contextSize,
        cacheDir: cacheDir.path,
        backend: backend,
        enableVision: enableVision,
        enableAudio: enableVision,
      );
      _hasLoadedModel = true;
      onProgress?.call(0.92);
      print(
          '[Inference] LiteRT-LM loaded with $backendLabel backend, ctx=$contextSize');
      return LoadResult(
        success: true,
        message: 'LiteRT-LM model loaded ($backendLabel backend).',
        gpuName: tier == AccelTier.cpu ? '' : 'LiteRT $backendLabel',
        gpuLayers: tier == AccelTier.cpu ? 0 : 1,
        runtime: 'litert',
        backend: backend.name,
      );
    } catch (error) {
      print('[Inference] LiteRT-LM load failed: $error');
      final errorStr = error.toString();
      if (errorStr.contains('TF_LITE_VISION_ENCODER')) {
        return LoadResult(
          success: false,
          message:
              'This LiteRT-LM file is text-only, but it was loaded as a vision model. Turn off Vision for this model or re-import it as a normal chat model.',
        );
      }
      // Asking for an audio encoder the file does not have fails the whole
      // load, so drop audio and keep the model rather than losing it.
      if (enableVision) {
        print('[Inference] Retrying without the audio encoder.');
        try {
          _liteEngine = await _createLiteRtEngine(
            modelPath: modelPath,
            contextSize: contextSize,
            cacheDir: cacheDir.path,
            backend: backend,
            enableVision: true,
            enableAudio: false,
          );
          _hasLoadedModel = true;
          onProgress?.call(0.92);
          return LoadResult(
            success: true,
            message: 'LiteRT-LM model loaded ($backendLabel backend, no audio).',
            gpuName: tier == AccelTier.cpu ? '' : 'LiteRT $backendLabel',
            gpuLayers: tier == AccelTier.cpu ? 0 : 1,
            runtime: 'litert',
            backend: backend.name,
          );
        } catch (audioFallbackError) {
          print('[Inference] Without-audio retry failed too: $audioFallbackError');
        }
      }
      if (enableVision && errorStr.contains('exactly one signature but got')) {
        print(
            '[Inference] Vision encoder signature mismatch. Falling back to text-only mode.');
        try {
          _liteEngine = await _createLiteRtEngine(
            modelPath: modelPath,
            contextSize: contextSize,
            cacheDir: cacheDir.path,
            backend: backend,
            enableVision: false,
            enableAudio: false,
          );
          _hasLoadedModel = true;
          onProgress?.call(0.92);
          return LoadResult(
            success: true,
            message:
                'Model loaded in text-only mode. Its vision features are incompatible with the LiteRT engine (expected 1 signature, found multiple).',
            gpuName: tier == AccelTier.cpu ? '' : 'LiteRT $backendLabel',
            gpuLayers: tier == AccelTier.cpu ? 0 : 1,
            runtime: 'litert',
            backend: backend.name,
          );
        } catch (fallbackError) {
          print('[Inference] LiteRT-LM fallback load failed: $fallbackError');
          return LoadResult(
            success: false,
            message: 'LiteRT load failed: $fallbackError',
          );
        }
      }
      if (errorStr.contains('exactly one signature but got')) {
        return LoadResult(
          success: false,
          message:
              'This vision model is incompatible with the LiteRT engine (expected 1 signature, found multiple). Please try a standard GGUF model or a text-only LiteRT model instead.',
        );
      }
      rethrow;
    }
  }

  Future<LiteLmEngine> _createLiteRtEngine({
    required String modelPath,
    required int contextSize,
    required String cacheDir,
    required LiteLmBackend backend,
    required bool enableVision,
    required bool enableAudio,
  }) {
    return LiteLmEngine.create(
      LiteLmEngineConfig(
        modelPath: modelPath,
        backend: backend,
        cacheDir: cacheDir,
        visionBackend: enableVision ? LiteLmBackend.cpu : null,
        // Leaving this null and then sending audio is what segfaults the
        // engine thread: the encoder is never built, and the first audio frame
        // dereferences it. Null means "this model has no audio", never
        // "decide later".
        audioBackend: enableAudio ? LiteLmBackend.cpu : null,
        maxNumTokens: contextSize,
      ),
    );
  }

  double _normalizeProgress(double progress) {
    if (progress.isNaN || progress.isInfinite) return 0.0;
    final normalized = progress > 1 ? progress / 100 : progress;
    return normalized.clamp(0.0, 1.0).toDouble();
  }

  Future<String> generate({
    required String prompt,
    List<Map<String, String>>? conversationHistory,
    required String systemPrompt,
    required String modelName,
    required int maxTokens,
    required double temperature,
    String? imagePath,
    String? audioPath,
    void Function(String token)? onToken,
  }) async {
    if (_isLiteRt) {
      return _generateLiteRt(
        prompt: prompt,
        conversationHistory: conversationHistory,
        systemPrompt: systemPrompt,
        maxTokens: maxTokens,
        temperature: temperature,
        imagePath: imagePath,
        audioPath: audioPath,
        onToken: onToken,
      );
    }

    if (_controller == null) throw Exception('No model loaded');

    // ── Attachments (libmtmd) ──
    // The projector decides what this model can actually read: refusing an
    // image because no projector is loaded is a different answer from
    // refusing it because the projector only does audio.
    final support = _mmprojSupport;
    final hasImage = imagePath != null && imagePath.isNotEmpty;
    final hasAudio = audioPath != null && audioPath.isNotEmpty;

    if (hasImage && support?.vision != true) {
      return support == null
          ? 'This model has no multimodal projector loaded, so it cannot see '
              'images. Pick a model that ships an mmproj file, or use a LiteRT '
              'multimodal model.'
          : 'This projector handles audio only — it cannot read images.';
    }
    if (hasAudio && support?.audio != true) {
      return support == null
          ? 'This model has no multimodal projector loaded, so it cannot hear '
              'audio. Pick a model that ships an mmproj file, or use a LiteRT '
              'multimodal model.'
          : 'This projector handles images only — it cannot read audio.';
    }

    var userPrompt = prompt;
    if (hasImage || hasAudio) {
      // Order matters: the markers are matched to the queued files positionally.
      final media = <String>[
        if (hasImage) imagePath,
        if (hasAudio) audioPath,
      ];
      await LlamaMultimodal.setMedia(media);
      userPrompt = '${List.filled(media.length, _mediaMarker).join('\n')}\n$prompt';
      print('[Inference] Queued ${media.length} attachment(s) for mtmd');
    }

    // The encoder runs before a single token exists, and it is slow enough to
    // dwarf a text prefill: one image measured 84s on CPU and 197s on this
    // Mali's Vulkan fallback. A flat 60s budget declared those runs dead while
    // they were still working, and the answer then arrived after the app had
    // already given up on it.
    final mediaCount = (hasImage ? 1 : 0) + (hasAudio ? 1 : 0);
    final prefillBudget = Duration(seconds: 60 + 240 * mediaCount);
    final hardBudget = Duration(seconds: 180 + 240 * mediaCount);

    final completer = Completer<String>();
    final buffer = StringBuffer();
    bool completed = false;

    void finish(String result) {
      if (!completed && !_disposed) {
        completed = true;
        _idleTimer?.cancel();
        _subscription?.cancel();
        _onStop = null;
        // Cancelling the Dart subscription does not stop nativeGenerate: it
        // keeps decoding on its worker thread, holding the context. Timing
        // out here without saying so left it running, and the next prompt
        // then queued behind it for the rest of the abandoned generation.
        unawaited(_controller?.stop() ?? Future.value());
        if (!completer.isCompleted) completer.complete(result);
      }
    }

    _onStop = () {
      finish(buffer.toString());
    };

    // ── Use generateChat() for native template handling ──
    Stream<String>? stream;
    try {
      final messages = _buildChatMessages(
          userPrompt, conversationHistory, systemPrompt,
          imagePath: imagePath, historyPrompt: prompt);
      stream = _controller!.generateChat(
        messages: messages,
        template: null,
        maxTokens: maxTokens,
        temperature: temperature,
        topP: _effectiveParams['topP'] ?? 0.9,
        topK: (_effectiveParams['topK'] ?? 40).toInt(),
        minP: _effectiveParams['minP'] ?? 0.05,
        repeatPenalty: _effectiveParams['repeatPenalty'] ?? 1.1,
        repeatLastN: 64,
      );
      print('[Inference] generateChat() started (${messages.length} messages)');
    } catch (e) {
      print('[Inference] generateChat() failed: $e — fallback to generate()');
      try {
        await _controller!.stop();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 100));
      final fullPrompt = _buildPrompt(
          userPrompt, conversationHistory, systemPrompt, modelName);
      stream = _controller!.generate(
        prompt: fullPrompt,
        maxTokens: maxTokens,
        temperature: temperature,
        topP: _effectiveParams['topP'] ?? 0.9,
        topK: (_effectiveParams['topK'] ?? 40).toInt(),
        minP: _effectiveParams['minP'] ?? 0.05,
        repeatPenalty: _effectiveParams['repeatPenalty'] ?? 1.1,
        repeatLastN: 64,
      );
    }

    int tokenCount = 0;
    _subscription = stream.listen(
      (token) {
        if (tokenCount == 0) {
          print('[Inference] ✓ FIRST TOKEN received! Prefill done.');
        }
        final clean = _sanitizeGemmaGarbage(token);
        if (clean.isEmpty) return;
        buffer.write(clean);
        tokenCount++;
        onToken?.call(clean);
        _idleTimer?.cancel();
        _idleTimer = Timer(const Duration(seconds: 5), () {
          print('[Inference] Idle timeout — $tokenCount tokens');
          finish(buffer.toString());
        });
      },
      onDone: () {
        print('[Inference] Stream onDone — $tokenCount tokens total');
        finish(buffer.toString());
      },
      onError: (error) {
        print('[Inference] Stream error: $error');
        finish('ERROR: Generation failed — $error');
      },
    );

    // Prefill timeout
    _idleTimer = Timer(prefillBudget, () {
      if (tokenCount == 0) {
        finish(mediaCount > 0
            ? 'ERROR: The encoder did not finish within '
                '${prefillBudget.inSeconds}s. Try a smaller image, or switch '
                'the vision encoder backend in Settings.'
            : 'ERROR: Model did not respond. Try a smaller model or shorter conversation.');
      }
    });

    // Hard timeout
    Future.delayed(hardBudget, () {
      if (!completed) {
        final partial = buffer.toString();
        finish(partial.isEmpty ? 'ERROR: Generation timed out.' : partial);
      }
    });

    return await completer.future;
  }

  Future<String> _generateLiteRt({
    required String prompt,
    List<Map<String, String>>? conversationHistory,
    required String systemPrompt,
    required int maxTokens,
    required double temperature,
    String? imagePath,
    String? audioPath,
    void Function(String token)? onToken,
  }) async {
    if (_liteEngine == null) throw Exception('No LiteRT-LM model loaded');

    await _subscription?.cancel();
    await _ensureLiteRtConversation(
      prompt: prompt,
      conversationHistory: conversationHistory,
      systemPrompt: systemPrompt,
      temperature: temperature,
    );

    // Retry up to 2 times on Status Code: 13 (INTERNAL_ERROR)
    const maxRetries = 2;
    String lastError = '';
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      if (attempt > 0) {
        print('[Inference] Retrying LiteRT-LM generation (attempt ${attempt + 1})');
        await Future.delayed(Duration(seconds: attempt));
      }
      try {
        return await _doGenerateLiteRt(
          prompt: prompt,
          conversationHistory: conversationHistory,
          systemPrompt: systemPrompt,
          maxTokens: maxTokens,
          temperature: temperature,
          imagePath: imagePath,
          audioPath: audioPath,
          onToken: onToken,
        );
      } catch (e) {
        lastError = e.toString();
        if (!lastError.contains('Status Code: 13') || attempt == maxRetries) break;
      }
    }
    return 'ERROR: LiteRT-LM generation failed after $maxRetries retries. Try a smaller model or shorter prompt. Error: $lastError';
  }

  Future<String> _doGenerateLiteRt({
    required String prompt,
    List<Map<String, String>>? conversationHistory,
    required String systemPrompt,
    required int maxTokens,
    required double temperature,
    String? imagePath,
    String? audioPath,
    void Function(String token)? onToken,
  }) async {

    final completer = Completer<String>();
    final buffer = StringBuffer();
    bool completed = false;
    bool hasVisibleOutput = false;
    var tokenCount = 0;

    void finish(String result) {
      if (!completed && !_disposed) {
        completed = true;
        _idleTimer?.cancel();
        _subscription?.cancel();
        _onStop = null;
        if (!completer.isCompleted) completer.complete(result);
      }
    }

    _onStop = () => finish(buffer.toString());

    if ((imagePath != null && imagePath.isNotEmpty) ||
        (audioPath != null && audioPath.isNotEmpty)) {
      final contents = <LiteLmContent>[
        LiteLmContent.text(prompt),
        if (imagePath != null && imagePath.isNotEmpty)
          LiteLmContent.imageFile(imagePath),
        if (audioPath != null && audioPath.isNotEmpty)
          LiteLmContent.audioFile(audioPath),
      ];

      _subscription =
          _liteConversation!.sendMultimodalMessageStream(contents).listen(
        (delta) {
          var text = _cleanLiteRtChunk(delta.text);
          if (text.isEmpty) return;

          if (!hasVisibleOutput) {
            if (!_hasPrintableText(text)) return;
            text = text.trimLeft();
            hasVisibleOutput = true;
          }

          if (tokenCount == 0) {
            print('[Inference] LiteRT-LM multimodal FIRST TOKEN received');
          }
          _liteConversationHasMessages = true;
          tokenCount++;
          buffer.write(text);
          onToken?.call(text);
          _idleTimer?.cancel();
          _idleTimer = Timer(const Duration(seconds: 8), () {
            print(
                '[Inference] LiteRT-LM multimodal idle timeout - $tokenCount chunks');
            finish(buffer.toString());
          });
        },
        onDone: () {
          _liteConversationHasMessages = true;
          print(
              '[Inference] LiteRT-LM multimodal stream done - $tokenCount chunks');
          finish(buffer.toString());
        },
        onError: (error) {
          print('[Inference] LiteRT-LM multimodal stream error: $error');
          finish('ERROR: LiteRT-LM multimodal generation failed - $error');
        },
      );

      _idleTimer = Timer(const Duration(seconds: 90), () {
        if (tokenCount == 0) {
          finish('ERROR: LiteRT-LM multimodal model did not respond.');
        }
      });

      Future.delayed(const Duration(seconds: 240), () {
        if (!completed) {
          final partial = buffer.toString();
          finish(partial.isEmpty
              ? 'ERROR: LiteRT-LM multimodal generation timed out.'
              : partial);
        }
      });

      return completer.future;
    }

    _subscription = _liteConversation!.sendMessageStream(prompt).listen(
      (delta) {
        var text = _cleanLiteRtChunk(delta.text);
        if (text.isEmpty) return;

        if (!hasVisibleOutput) {
          if (!_hasPrintableText(text)) return;
          text = text.trimLeft();
          hasVisibleOutput = true;
        }

        if (tokenCount == 0) {
          print('[Inference] LiteRT-LM FIRST TOKEN received');
        }
        _liteConversationHasMessages = true;
        tokenCount++;
        buffer.write(text);
        onToken?.call(text);
        _idleTimer?.cancel();
        _idleTimer = Timer(const Duration(seconds: 5), () {
          print('[Inference] LiteRT-LM idle timeout - $tokenCount chunks');
          finish(buffer.toString());
        });
      },
      onDone: () {
        _liteConversationHasMessages = true;
        print('[Inference] LiteRT-LM stream done - $tokenCount chunks');
        finish(buffer.toString());
      },
      onError: (error) {
        print('[Inference] LiteRT-LM stream error: $error');
        finish('ERROR: LiteRT-LM generation failed - $error');
      },
    );

    _idleTimer = Timer(const Duration(seconds: 60), () {
      if (tokenCount == 0) {
        finish('ERROR: LiteRT-LM model did not respond. Try a smaller model.');
      }
    });

    Future.delayed(const Duration(seconds: 180), () {
      if (!completed) {
        final partial = buffer.toString();
        finish(partial.isEmpty
            ? 'ERROR: LiteRT-LM generation timed out.'
            : partial);
      }
    });

    return completer.future;
  }

  Future<void> _ensureLiteRtConversation({
    required String prompt,
    required List<Map<String, String>>? conversationHistory,
    required String systemPrompt,
    required double temperature,
  }) async {
    final hasIncomingHistory = conversationHistory != null &&
        conversationHistory.any((msg) => (msg['content'] ?? '').isNotEmpty);
    final shouldReset = _liteConversation == null ||
        _liteConversationSystemPrompt != systemPrompt ||
        _liteConversationTemperature != temperature ||
        (_liteConversationHasMessages && !hasIncomingHistory);

    if (!shouldReset) return;

    try {
      await _liteConversation?.dispose();
    } catch (_) {}

    _liteConversation = await _liteEngine!.createConversation(
      LiteLmConversationConfig(
        systemInstruction: systemPrompt,
        initialMessages:
            _buildLiteRtInitialMessages(prompt, conversationHistory),
        samplerConfig: LiteLmSamplerConfig(
          temperature: temperature,
          topK: 64,
          topP: 0.95,
        ),
      ),
    );
    _liteConversationSystemPrompt = systemPrompt;
    _liteConversationTemperature = temperature;
    _liteConversationHasMessages = hasIncomingHistory;
  }

  Future<void> stop() async {
    if (_disposed) return;
    _idleTimer?.cancel();
    final stopCallback = _onStop;
    _onStop = null;
    stopCallback?.call();
    unawaited(_subscription?.cancel() ?? Future<void>.value());
    if (_isLiteRt) {
      _liteConversationHasMessages = true;
      return;
    }
    try {
      await _controller?.stop().timeout(const Duration(milliseconds: 800));
    } catch (_) {}
  }

  /// Reset any persistent conversation state so the next generation
  /// starts with a clean context. Essential when switching chat sessions.
  Future<void> resetConversation() async {
    if (_isLiteRt) {
      try {
        await _liteConversation?.dispose();
      } catch (_) {}
      _liteConversation = null;
      _liteConversationSystemPrompt = null;
      _liteConversationTemperature = null;
      _liteConversationHasMessages = false;
    }
    // llama.cpp (GGUF) is stateless per-generation — no native
    // conversation object to reset.
  }

  Future<ContextInfo?> getContextInfo() async {
    if (_isLiteRt) return null;
    try {
      return await _controller?.getContextInfo();
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    if (_hasLoadedModel) {
      try {
        await _controller?.dispose();
      } catch (_) {}
    }
    try {
      await _liteConversation?.dispose();
    } catch (_) {}
    try {
      await _liteEngine?.dispose();
    } catch (_) {}
    unawaited(_loadProgressSub?.cancel() ?? Future<void>.value());
    _loadProgressSub = null;
    _controller = null;
    _liteConversation = null;
    _liteEngine = null;
    _isLiteRt = false;
    _hasLoadedModel = false;
    _liteConversationSystemPrompt = null;
    _liteConversationTemperature = null;
    _liteConversationHasMessages = false;
  }

  // ── Helpers ──

  String _runtimeFor(String modelPath, String? modelRuntime) {
    final runtime = modelRuntime?.toLowerCase();
    if (runtime == 'litert' || runtime == 'llama') return runtime!;
    final lower = modelPath.toLowerCase();
    if (lower.endsWith('.litertlm')) return 'litert';
    return 'llama';
  }

  List<LiteLmMessage> _buildLiteRtInitialMessages(
    String prompt,
    List<Map<String, String>>? history,
  ) {
    if (history == null || history.isEmpty) return const [];

    var recent = history.length > 16
        ? history.sublist(history.length - 16)
        : List<Map<String, String>>.from(history);
    if (recent.isNotEmpty &&
        recent.last['role'] == 'user' &&
        recent.last['content'] == prompt) {
      recent = recent.sublist(0, recent.length - 1);
    }

    return recent
        .where((msg) => (msg['content'] ?? '').trim().isNotEmpty)
        .map((msg) {
      final content = msg['content'] ?? '';
      return msg['role'] == 'assistant'
          ? LiteLmMessage.model(content)
          : LiteLmMessage.user(content);
    }).toList();
  }

  String _cleanLiteRtChunk(String text) {
    return _sanitizeGemmaGarbage(
      text
          .replaceAll(
              RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]'),
              '')
          .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
          .replaceAll('\uFFFD', '')
          .replaceAll('<|endoftext|>', '')
          .replaceAll('<|im_end|>', '')
          .replaceAll('<|end|>', ''),
    );
  }

  /// Strip Gemma garbage tokens that leak when Q4_K_M dequant is corrupt
  /// on Google Tensor SoC. Harmless on devices that don't produce them.
  /// NOTE: Do NOT trim() — SentencePiece tokens rely on leading spaces.
  String _sanitizeGemmaGarbage(String text) {
    return text
        .replaceAll(RegExp(r'<unused\d+>'), '')
        .replaceAll(RegExp(r'\[@BOS@\]'), '')
        .replaceAll('<bos>', '')
        .replaceAll('<mask>', '')
        .replaceAll('<pad>', '')
        .replaceAll('<unk>', '')
        .replaceAll('<s>', '')
        .replaceAll('</s>', '');
  }

  bool _hasPrintableText(String text) {
    for (final rune in text.runes) {
      if (rune > 32 &&
          rune != 0x7F &&
          rune != 0x200B &&
          rune != 0x200C &&
          rune != 0x200D &&
          rune != 0xFEFF &&
          rune != 0xFFFD) {
        return true;
      }
    }
    return false;
  }

  List<ChatMessage> _buildChatMessages(
    String prompt,
    List<Map<String, String>>? history,
    String systemPrompt, {
    String? imagePath,
    // What the caller's message looks like in the history. With attachments
    // [prompt] carries media markers the history entry does not have, and
    // comparing the decorated text would miss the match and send the turn
    // twice.
    String? historyPrompt,
  }) {
    final messages = <ChatMessage>[];
    messages.add(ChatMessage(role: 'system', content: systemPrompt));

    if (history != null && history.isNotEmpty) {
      var recent = history.length > 16
          ? history.sublist(history.length - 16)
          : List.of(history);
      if (recent.isNotEmpty &&
          recent.last['role'] == 'user' &&
          recent.last['content'] == (historyPrompt ?? prompt)) {
        recent = recent.sublist(0, recent.length - 1);
      }
      for (final msg in recent) {
        final content = msg['content'] ?? '';
        messages
            .add(ChatMessage(role: msg['role'] ?? 'user', content: content));
      }
    }

    messages
        .add(ChatMessage(role: 'user', content: prompt, imagePath: imagePath));
    return messages;
  }

  /// One raw-completion pass, timed to the first token.
  ///
  /// maxTokens=1 keeps it pure prefill — the quantity that actually differs
  /// between CPU and GPU on small models. Callers pass the same string to both
  /// backends, so only relative time matters; absolute tok/s is for the log.
  Future<int> _timeToFirstToken(LlamaController controller, String prompt,
      {Duration budget = const Duration(seconds: 15)}) async {
    final sw = Stopwatch()..start();
    final done = Completer<void>();
    late final StreamSubscription<String> sub;
    sub = controller.generate(
      prompt: prompt,
      maxTokens: 1,
      temperature: 0.0,
      topP: 1.0,
      topK: 1,
      minP: 0.05,
      typicalP: 1.0,
      repeatPenalty: 1.0,
      frequencyPenalty: 0.0,
      presencePenalty: 0.0,
      repeatLastN: 1,
    ).listen(
      (_) {
        if (!done.isCompleted) done.complete();
      },
      onError: (Object _) {
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future.timeout(budget, onTimeout: () {});
    sw.stop();
    await sub.cancel();
    try {
      await controller.stop();
    } catch (_) {}
    return sw.elapsedMilliseconds;
  }

  /// Resolves the sampler values for this model, in precedence order:
  /// GGUF-embedded metadata > per-model saved overrides > user globals.
  /// Whatever the GGUF declares is cached under the model's key so later
  /// loads skip the queries.
  Future<void> _applyEffectiveParams(String modelPath) async {
    final sc = Get.find<SettingsController>();
    final params = <String, double>{
      'temperature': sc.temperature.value,
      'topP': sc.topP.value,
      'topK': sc.topK.value.toDouble(),
      'minP': sc.minP.value,
      'repeatPenalty': sc.repeatPenalty.value,
    };

    String cacheKey() => '${AppConstants.modelParamsKeyPrefix}'
        '${modelPath.split('/').last}:${File(modelPath).lengthSync()}';
    try {
      final raw = Get.find<HiveService>().getSetting<String>(cacheKey());
      if (raw != null) {
        final saved = jsonDecode(raw) as Map<String, dynamic>;
        saved.forEach((k, v) => params[k] = (v as num).toDouble());
      }
    } catch (_) {}

    const candidates = <String, List<String>>{
      'temperature': ['temperature', 'sampling.temperature', 'gen.temperature'],
      'topP': ['top_p', 'sampling.top_p', 'gen.top_p'],
      'topK': ['top_k', 'sampling.top_k', 'gen.top_k'],
      'minP': ['min_p', 'sampling.min_p', 'gen.min_p'],
      'repeatPenalty': [
        'repeat_penalty',
        'sampling.repeat_penalty',
        'gen.repeat_penalty'
      ],
    };
    var fromModel = false;
    for (final entry in candidates.entries) {
      for (final key in entry.value) {
        final v = double.tryParse(await LlamaModelMeta.get(key) ?? '');
        if (v != null) {
          if (params[entry.key] != v) fromModel = true;
          params[entry.key] = v;
          break;
        }
      }
    }
    if (fromModel) {
      try {
        Get.find<HiveService>()
            .setSetting(cacheKey(), jsonEncode(params));
      } catch (_) {}
    }
    _effectiveParams
      ..clear()
      ..addAll(params);
    print('[Inference] Sampler: '
        '${params.entries.map((e) => "${e.key}=${e.value}").join(", ")}');
  }

  /// Text-prefill benchmark: fixed ~24-token string, long enough that per-call
  /// overhead does not dominate, short enough that a slow GPU stays in budget.
  Future<int> _benchPrefillMs(LlamaController controller) {
    return _timeToFirstToken(controller, 'The quick brown fox jumps over '
        'the lazy dog. Pack my box with five dozen liquor jugs.');
  }

  /// Vision-encoder benchmark over a tiny generated PNG.
  ///
  /// Encoder cost scales with patch count, so 64×64 keeps both passes inside
  /// seconds while still exercising the same op mix that made full photos
  /// take 183 s on this Mali's Vulkan fallback. The queued media is cleared
  /// afterwards either way — a leftover bench image would otherwise ride
  /// along with the user's first real attachment.
  Future<int> _benchEncodeMs(LlamaController controller) async {
    final dir = await getTemporaryDirectory();
    final bench = File('${dir.path}/vision_bench_64.png');
    if (!bench.existsSync()) {
      final image = img.Image(width: 64, height: 64);
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          image.setPixelRgba(x, y, x * 4 % 256, y * 4 % 256, (x + y) * 2 % 256, 255);
        }
      }
      await bench.writeAsBytes(img.encodePng(image));
    }
    await LlamaMultimodal.setMedia([bench.path]);
    final marker = _mediaMarker.isNotEmpty
        ? _mediaMarker
        : await LlamaMultimodal.mediaMarker();
    try {
      return await _timeToFirstToken(
          controller, '$marker\nDescribe this image.');
    } finally {
      try {
        await LlamaMultimodal.setMedia(const []);
      } catch (_) {}
    }
  }

  String _buildPrompt(
    String userMessage,
    List<Map<String, String>>? history,
    String systemPrompt,
    String modelName,
  ) {
    // Auto-detect template from model name
    final name = modelName.toLowerCase();
    if (name.contains('gemma')) {
      return _buildGemma(userMessage, history, systemPrompt);
    }
    if (name.contains('llama-3') || name.contains('llama3')) {
      return _buildLlama3(userMessage, history, systemPrompt);
    }
    return _buildChatML(userMessage, history, systemPrompt);
  }

  String _buildChatML(
      String msg, List<Map<String, String>>? history, String sys) {
    final buf = StringBuffer();
    buf.write('<|im_start|>system\n$sys<|im_end|>\n');
    if (history != null) {
      final recent =
          history.length > 8 ? history.sublist(history.length - 8) : history;
      for (final m in recent) {
        final content = m['content'] ?? '';
        final trunc =
            content.length > 300 ? '${content.substring(0, 300)}...' : content;
        buf.write('<|im_start|>${m['role'] ?? 'user'}\n$trunc<|im_end|>\n');
      }
    }
    buf.write('<|im_start|>user\n$msg<|im_end|>\n<|im_start|>assistant\n');
    return buf.toString();
  }

  String _buildGemma(
      String msg, List<Map<String, String>>? history, String sys) {
    final buf = StringBuffer();
    buf.write(
        '<start_of_turn>user\n$sys<end_of_turn>\n<start_of_turn>model\nUnderstood.<end_of_turn>\n');
    if (history != null) {
      final recent =
          history.length > 4 ? history.sublist(history.length - 4) : history;
      for (final m in recent) {
        final role = m['role'] == 'assistant' ? 'model' : 'user';
        final content = m['content'] ?? '';
        final trunc =
            content.length > 300 ? '${content.substring(0, 300)}...' : content;
        buf.write('<start_of_turn>$role\n$trunc<end_of_turn>\n');
      }
    }
    buf.write('<start_of_turn>user\n$msg<end_of_turn>\n<start_of_turn>model\n');
    return buf.toString();
  }

  String _buildLlama3(
      String msg, List<Map<String, String>>? history, String sys) {
    final buf = StringBuffer();
    buf.write(
        '<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n$sys<|eot_id|>');
    if (history != null) {
      final recent =
          history.length > 4 ? history.sublist(history.length - 4) : history;
      for (final m in recent) {
        final content = m['content'] ?? '';
        final trunc =
            content.length > 300 ? '${content.substring(0, 300)}...' : content;
        buf.write(
            '<|start_header_id|>${m['role'] ?? 'user'}<|end_header_id|>\n\n$trunc<|eot_id|>');
      }
    }
    buf.write(
        '<|start_header_id|>user<|end_header_id|>\n\n$msg<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n');
    return buf.toString();
  }
}
