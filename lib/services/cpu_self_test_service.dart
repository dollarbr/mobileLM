/// Wires the CPU self-test to the real engine.
///
/// Kept apart from `cpu_self_test.dart` on purpose. That file is pure: it knows
/// which model to use, what to ask it, and how to turn two numbers into a
/// verdict. This one knows about platform engines and file paths. The split is
/// what makes the thresholds testable against real device values without a
/// device, and it is the same split `scheduled_task_service.dart` uses when it
/// builds its own engine rather than borrowing the chat's.
library;

import 'package:get/get.dart';

import '../core/constants.dart';
import '../models/ai_model.dart';
import 'cpu_self_test.dart';
import 'download_service.dart';
import 'app_log_service.dart';
import 'hive_service.dart';
// The conditional import is the same one scheduled_task_service.dart uses: a
// bare import of the Android engine would not compile for the web target, which
// this project ships. Named `platform` because the stub has to satisfy it.
import 'inference_android.dart'
    if (dart.library.html) 'inference_stub.dart'
    as platform;

/// Observable state for the settings tile.
///
/// The verdict is held rather than recomputed, because a self-test is a
/// measurement: re-deriving it from a stale pair of numbers would quietly
/// relabel a phone that has not been tested since.
class CpuSelfTestState {
  final running = false.obs;

  /// Whether the suggestion card is shown at all. False once the user has
  /// dismissed it, and that is stored — a suggestion that returns on the next
  /// launch is a nag, and nagging is how a useful suggestion gets uninstalled.
  final offer = true.obs;

  /// Set by [CpuSelfTestService.cancel], so the caller can tell a cancelled run
  /// from a failed one. A cancelled test reporting "the CPU returned nothing"
  /// would be a lie the user has to disprove.
  final cancelled = false.obs;

  final summary = ''.obs;
  final verdict = Rxn<CpuVerdict>();
  final tokensPerSecond = RxnDouble();
  final ttftMillis = RxnInt();
  final reply = RxnString();

  void clear() {
    summary.value = '';
    verdict.value = null;
    tokensPerSecond.value = null;
    ttftMillis.value = null;
    reply.value = null;
  }

  void record(CpuSelfTestResult r) {
    verdict.value = r.verdict;
    tokensPerSecond.value = r.tokensPerSecond;
    ttftMillis.value = r.ttftMillis;
    reply.value = r.reply;
    summary.value = describeCpuSelfTest(r);
  }
}

class CpuSelfTestService extends GetxService {
  final state = CpuSelfTestState();
  // `Get.find`, not `AppLogService()`. This was constructing a *second*
  // instance, and the difference is not cosmetic: AppLogService is a
  // GetxService, and GetX only calls `onInit` on the instance that goes through
  // `Get.put` (main.dart:41). The flush timer is started in `onInit`, so a
  // directly-constructed instance appends every line to `_pending` and nothing
  // ever drains it — the benchmark's own log lines, the verdict included, went
  // nowhere at all. Measured on the A72: the run completed, the card showed a
  // verdict, and `grep 'CPU self-test' app.log app.log.1` came back empty on
  // both files.
  //
  // A second instance is also a second `RxList`, so the writes never reach the
  // Obx in the Logs screen — the card is a black box for anything that goes
  // through this field.
  final AppLogService _log;
  CpuSelfTestService({AppLogService? log}) : _log = log ?? Get.find();

  /// The registered instance, not a new one.
  ///
  /// `HiveService()` here would be a second, uninitialised copy: its
  /// `_settingsBox` is a `late` field that only [HiveService.init] fills, and
  /// constructing a fresh one reads it before that happens. The symptom is a
  /// `LateInitializationError` in `main()` before `runApp`, which shows up as an
  /// app frozen on the splash with nothing in logcat beyond that one line — the
  /// cost of a convenience constructor measured in confused debugging.
  HiveService get _hive => Get.find<HiveService>();

  /// The first meaningful line of a native error, capped.
  ///
  /// Both load failures and thrown exceptions arrive as multi-line Java stack
  /// traces. The first line carries the reason; the rest is frames that mean
  /// nothing outside a debugger. Shown raw, the first one measured 40 lines
  /// tall on the Models tab and pushed its own verdict off the screen, so the
  /// card could not report a failure — which is the only thing it exists to do.
  static String _oneLine(String raw) {
    final line = raw
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => raw)
        .replaceAll(RegExp(r'\s+'), ' ');
    return line.length > 120 ? '${line.substring(0, 120)}…' : line;
  }

  /// Restores the dismissal, lazily.
  ///
  /// Not called from `main()`. There is an ordering problem that looks harmless:
  /// `HiveService` is registered before this service, so `Get.find` succeeds —
  /// but its `_settingsBox` is a `late` field that only `HiveService.init`
  /// assigns, and reading it from an early `init()` throws
  /// `LateInitializationError` before `runApp`. The app then sits on the splash
  /// with a single line of logcat that points at this file and nowhere else.
  ///
  /// So the read happens on first use instead, when the box is certainly open.
  /// A dismissed card is not needed during boot, and the cost of being one frame
  /// late on it is nothing.
  bool _offerLoaded = false;

  bool get offerEnabled {
    if (!_offerLoaded) {
      _offerLoaded = true;
      try {
        state.offer.value = _hive.getSetting<bool>(
                AppConstants.keyCpuSelfTestOffer,
                defaultValue: true) ??
            true;
      } catch (_) {
        // A missing box must not take the card down with it. Defaulting to
        // showing the suggestion is the recoverable direction: the user can
        // dismiss it, whereas a card that never appears cannot be dismissed.
        state.offer.value = true;
      }
    }
    return state.offer.value;
  }

  /// Never ask again. Deliberately one-way from the card's point of view:
  /// Settings has the switch to bring it back, and a card that can un-dismiss
  /// itself is a card the user cannot get rid of.
  Future<void> dismissOffer() async {
    state.offer.value = false;
    await _hive.setSetting(AppConstants.keyCpuSelfTestOffer, false);
    _log.info('CPU self-test suggestion dismissed');
  }

  /// Bring it back from Settings.
  Future<void> restoreOffer() async {
    state.offer.value = true;
    await _hive.setSetting(AppConstants.keyCpuSelfTestOffer, true);
  }

  /// Stop the run in progress.
  ///
  /// llama.cpp is mid-`llama_decode` and cannot be interrupted, so this does
  /// not abort the work — it stops the app from waiting on it and reporting a
  /// result. The engine is disposed either way. Reporting "cancelled" straight
  /// away while the native call keeps burning a core is the honest version: the
  /// user got their time back, and the residual work is theirs to know about.
  void cancel() {
    if (!state.running.value) return;
    state.cancelled.value = true;
    state.running.value = false;
    state.summary.value = 'Cancelled';
  }

  Future<CpuSelfTestResult> run({required List<AiModel> availableModels}) async {
    if (state.running.value) {
      return const CpuSelfTestResult(
        verdict: CpuVerdict.fail,
        detail: 'A test is already running',
      );
    }
    state.cancelled.value = false;

    final model = pickBenchmarkModel(availableModels);
    if (model == null) {
      const r = CpuSelfTestResult(
        verdict: CpuVerdict.fail,
        detail: 'No catalogue model is marked as the CPU benchmark',
      );
      state.record(r);
      return r;
    }

    state.running.value = true;
    state.clear();
    final sw = Stopwatch();
    try {
      final downloader = Get.find<DownloadService>();
      final path = await downloader.modelPath(model.filename);
      if (path.isEmpty) {
        final r = CpuSelfTestResult(
          verdict: CpuVerdict.fail,
          model: model,
          detail: 'Download "${model.name}" first — it is the CPU benchmark',
        );
        state.record(r);
        return r;
      }

      // A fresh engine, not the chat's. Two reasons, and the second is the
      // important one: a shared engine would test a context someone else
      // warmed up, and would evict their model. The self-test is a measurement
      // of the CPU path from cold, so it starts cold.
      final engine = platform.InferenceEngine();
      sw.start();
      final load = await engine.loadModel(
        modelPath: path,
        contextSize: AppConstants.defaultContextSize,
        deviceTier: 'medium',
        // Forced, not read from the user's setting, and this is the whole
        // measurement rather than a detail of it.
        //
        // Passing the user's mode is what broke it on the first run: the A72
        // sits on the default `auto_fast`, the probe sees the Adreno and 2,4 GB
        // free, recommends 16 layers, and llama.cpp is handed
        // `n_gpu_layers = 16` for a model whose `lfm2` tensors have no Vulkan
        // implementation. The load dies in 34 ms with "Unsupported device",
        // before any work — and the card reports it as the CPU failing, which
        // is the exact opposite of the truth.
        //
        // A benchmark that measures whatever accelerator happens to be enabled
        // is not a CPU benchmark, and its number is not comparable to the last
        // one. `cpu_safe` also keeps the Vulkan backend out of the process,
        // which is what makes the number attributable to the CPU at all.
        liteRtPerformanceMode: 'cpu_safe',
        onProgress: (_) {},
      );
      if (!load.success) {
        await engine.dispose();
        // Same truncation as the catch below, and for the same reason: a failed
        // load is the most likely thing to carry a full Java stack trace, and
        // it is the one the user is most likely to hit on a phone whose GPU
        // cannot run the model.
        _log.error('CPU self-test load failed', details: load.message);
        final r = CpuSelfTestResult(
          verdict: CpuVerdict.fail,
          model: model,
          detail: _oneLine(load.message),
        );
        state.record(r);
        return r;
      }
      // Restarted, not continued: the load is not what is being measured, and
      // folding it in would make the number depend on the storage rather than
      // on the CPU.
      sw
        ..reset()
        ..start();

      // A warm-up generation, thrown away, then the measured one. The rule and
      // the 87x measurement behind it are documented on `measureGeneration`.
      final m = await measureGeneration(
        ({required int maxTokens, void Function(String)? onToken}) =>
            engine.generate(
          prompt: kCpuSelfTestPrompt,
          systemPrompt: kCpuSelfTestSystemPrompt,
          modelName: model.name,
          maxTokens: maxTokens,
          temperature: 0.0,
          onToken: onToken,
        ),
        maxTokens: kCpuSelfTestMaxTokens,
      );
      await engine.dispose();

      final ttft = m.firstTokenMs;
      final trimmed = m.text.trim();
      final tps = m.tokensPerSecond;
      final verdict =
          judgeCpuSelfTest(ttftMillis: ttft, tokensPerSecond: tps);

      final r = CpuSelfTestResult(
        verdict: verdict,
        model: model,
        tokensPerSecond: tps,
        ttftMillis: ttft > 0 ? ttft : null,
        reply: trimmed.isEmpty ? null : trimmed,
        detail: verdict == CpuVerdict.fail && trimmed.isEmpty
            ? 'The engine ran but produced no text'
            : '',
      );
      _log.info('CPU self-test: ${describeCpuSelfTest(r)}');
      state.record(CpuSelfTestResult(
        verdict: r.verdict,
        model: model,
        tokensPerSecond: r.tokensPerSecond,
        ttftMillis: r.ttftMillis,
        reply: r.reply,
        detail: r.detail,
      ));
      return r;
    } catch (e) {
      // Truncated, always. The engine hands back a full Java stack trace — the
      // one that made this card 40 lines tall and pushed the verdict off the
      // screen entirely. A user cannot act on a stack trace and a settings
      // card is not a log viewer, so the message keeps the first line (which
      // carries the actual reason) and the full text goes to the log, where
      // "Share full log file" can reach it.
      final raw = e.toString();
      _log.error('CPU self-test failed', details: raw);
      final r = CpuSelfTestResult(
        verdict: CpuVerdict.fail,
        model: model,
        detail: _oneLine(raw),
      );
      state.record(r);
      return r;
    } finally {
      // A cancelled run must not overwrite the summary with a verdict nobody
      // waited for.
      if (state.cancelled.value) {
        state.summary.value = 'Cancelled';
      }
      state.running.value = false;
    }
  }
}
