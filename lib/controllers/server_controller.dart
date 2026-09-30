import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';

import '../core/constants.dart';
import '../services/app_log_service.dart';
import '../services/hive_service.dart';
import '../services/inference_service.dart';
import '../services/openai_server_service.dart';
import '../utils/server_auth.dart';

class ServerController extends GetxController {
  final HiveService _hive = Get.find<HiveService>();
  final InferenceService inference = Get.find<InferenceService>();
  final OpenAiServerService _server = OpenAiServerService();

  final isRunning = false.obs;
  final isStarting = false.obs;
  final localUrl = RxnString();
  final serverStatus = 'Server stopped'.obs;
  final lastError = RxnString();

  final useApiKey = false.obs;
  final apiKey = ''.obs;

  /// What the loaded model actually is, as far as the API is concerned.
  ///
  /// Null means "not asked yet", which the view renders as no examples rather
  /// than as chat examples: showing a `curl` for `/v1/chat/completions` to
  /// someone who has a BERT loaded is how a user finds out that the endpoint
  /// exists by getting a refusal.
  ///
  /// Refreshed by the `ever` on `loadedModelName` below, so it follows a model
  /// swap without the model controller knowing this controller exists.
  final encoder = Rxn<EncoderInfo>();

  /// A short label for the loaded model, for the examples: "embedding",
  /// "reranker", "classifier", or null for a generation model.
  String? get modelRole {
    final info = encoder.value;
    if (info == null || !info.isEncoder) return null;
    if (info.isClassifier) return 'classifier';
    if (info.isReranker) return 'reranker';
    if (info.isEmbedding) return 'embedding';
    return 'encoder';
  }

  /// The port the server is on. Whatever the user chose, or
  /// [AppConstants.defaultServerPort] if they never chose one.
  final serverPort = RxInt(AppConstants.defaultServerPort);

  late final TextEditingController portCtrl;
  late final TextEditingController apiKeyCtrl;

  /// Read from [AppConstants] rather than written out here.
  ///
  /// These were two copies of the same number — `defaultServerPort` in
  /// `AppConstants` and `_defaultPort` here — and the one that actually decides
  /// what a fresh install listens on is this one, so editing the other looked
  /// like it worked and did nothing. That is the same failure as the version
  /// number this repo once kept in three places in prose, and it is fixed the
  /// same way: one place, referenced.
  static const int _defaultPort = AppConstants.defaultServerPort;
  static const int _maxPortProbe = 9000;

  @override
  void onInit() {
    super.onInit();
    _applyAuthDecision();
    serverPort.value =
        _hive.getSetting<int>(AppConstants.keyServerPort) ?? _defaultPort;

    portCtrl =
        TextEditingController(text: serverPort.value.toString());
    apiKeyCtrl = TextEditingController(text: apiKey.value);

    // Ask what the model is now, and again on every swap. `LlamaEncoder.info()`
    // goes over the JNI, so it is one round trip per model load rather than one
    // per frame — the alternative, reading it in the view's `Obx`, would ask
    // again on every rebuild of the examples list.
    ever(inference.loadedModelName, (_) => refreshEncoder());
    refreshEncoder();
  }

  /// Decide the auth state from storage, and write it back if a key was made.
  ///
  /// The rule itself lives in `utils/server_auth.dart` and is pure, because it
  /// is a migration: get it backwards and the server comes up on every
  /// interface with no key and nothing reports it. A test can pin the three
  /// cases; a test cannot pin this method, which is why the decision was moved
  /// out and only the storage is left here.
  ///
  /// Persisting the generated key before the server can start is the load-
  /// bearing part. A key that exists in memory but not in Hive is a key that
  /// silently changes on the next cold start, and a client with the old one
  /// starts getting 401s for no stated reason.
  void _applyAuthDecision() {
    final decision = decideServerAuth(
      storedKey: _hive.getSetting<String>(AppConstants.keyServerApiKey),
      storedUseKey: _hive.getSetting<bool>(AppConstants.keyServerUseApiKey),
    );
    apiKey.value = decision.apiKey;
    useApiKey.value = decision.requireKey;
    if (decision.generated) {
      unawaited(saveSettings());
      // Logged once, at boot, and deliberately without the key itself. A
      // support log is the first place someone looks when a client gets 401s,
      // and a credential in there is a credential on disk somewhere else.
      Get.find<AppLogService>().info('Server API key generated; the local API '
          'now requires it. Find it in Settings, or send it as: '
          '-H "Authorization: Bearer <key>"');
    }
  }

  /// Re-reads the encoder surface of the loaded model.
  ///
  /// A failure here is not a failure to report: a generation model, a LiteRT
  /// runtime, and a model that is not loaded at all all make this throw, and all
  /// three mean the same thing to the view — there is no encoder, so show the
  /// chat examples. The endpoint's own refusal carries the detail when someone
  /// actually calls it.
  Future<void> refreshEncoder() async {
    if (!inference.isModelLoaded.value) {
      encoder.value = null;
      return;
    }
    try {
      encoder.value = await LlamaEncoder.info();
    } on Object {
      encoder.value = null;
    }
  }

  bool get hasLocalModel => inference.isModelLoaded.value;

  String get modelName => inference.loadedModelName.value.isEmpty
      ? 'No model loaded'
      : inference.loadedModelName.value;

  Future<void> toggleServer(bool enabled) async {
    if (enabled) {
      await startServer();
    } else {
      await stopServer();
    }
  }

  /// Returns true when [port] is free to bind on all interfaces.
  static Future<bool> isPortFree(int port) async {
    try {
      final socket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Start from [base] and walk up until an open port is found, or
  /// [_maxPortProbe] is reached. Returns the first available port.
  static Future<int> findAvailablePort(int base) async {
    for (int p = base; p <= _maxPortProbe; p++) {
      if (await isPortFree(p)) return p;
    }
    return base; // caller should show an error
  }

  Future<void> startServer() async {
    if (isRunning.value || isStarting.value) return;
    lastError.value = null;
    // No model gate, deliberately.
    //
    // It used to refuse here: "Load a local GGUF or LiteRT-LM model first." That
    // is circular now and was always awkward — the server is how you load a
    // model over the network, so requiring one to start it means the feature
    // cannot bootstrap itself and a client that wanted to swap models had to go
    // and touch the phone. The endpoints that need a model already refuse
    // cleanly with no model: `_localModelError` for generation,
    // `_encoderUnavailable` for embeddings/rerank/classify. A server that is up,
    // reports `loaded: null`, and answers 400 with a sentence is a better
    // answer than a port that is not listening at all.

    // Make sure any previously-stale server is fully cleaned up before
    // trying a new bind.  stopServer sets _server to null and force-closes
    // the old HttpServer, but the platform socket can linger in TIME_WAIT.
    // We close it here explicitly so the new bind has the best chance.
    await _server.stop();

    // Persist whatever port the user typed before probing.
    await saveSettings();

    // Probe the user's chosen port. If it is busy, walk forward until we
    // find one that is free — and tell the user what happened.
    final configured = serverPort.value;
    if (!await isPortFree(configured)) {
      final chosen = await findAvailablePort(configured + 1);
      serverPort.value = chosen;
      Get.snackbar(
        'Port occupied',
        'Port $configured is already in use. Server will run on $chosen.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }

    isStarting.value = true;
    serverStatus.value = 'Starting server...';

    try {
      await _server.start(
        port: serverPort.value,
        apiKey: useApiKey.value ? apiKey.value : null,
        onLog: (message) => serverStatus.value = message,
      );
      localUrl.value = _server.localUrl;
      isRunning.value = true;
      serverStatus.value = 'Server running';
      // Persist the actual port used (might differ from user setting).
      await _hive.setSetting(
          AppConstants.keyServerPort, serverPort.value);
    } catch (e) {
      lastError.value = '$e';
      serverStatus.value = 'Server failed';
      Get.find<AppLogService>().error('API server failed', details: e);
      Get.snackbar('Server failed', '$e');
    } finally {
      isStarting.value = false;
    }
  }

  Future<void> stopServer() async {
    isStarting.value = false;
    await _server.stop();
    isRunning.value = false;
    localUrl.value = null;
    serverStatus.value = 'Server stopped';
  }

  Future<void> saveSettings() async {
    await _hive.setSetting(AppConstants.keyServerUseApiKey, useApiKey.value);
    await _hive.setSetting(AppConstants.keyServerApiKey, apiKey.value.trim());
    // Save the port the user configured (may differ from what we actually bind).
    final port = int.tryParse(portCtrl.text.trim());
    if (port != null && port > 0 && port < 65536) {
      serverPort.value = port;
    }
    await _hive.setSetting(AppConstants.keyServerPort, serverPort.value);
  }

  Future<void> generateApiKey() async {
    // The same generator the boot path uses, so a key made by tapping the
    // wand and a key made by the migration are indistinguishable in length,
    // alphabet and entropy. Two key formats in one app is one more thing to
    // be wrong about later.
    apiKey.value = generateServerApiKey();
    useApiKey.value = true;
    await saveSettings();
  }

  /// Roll a new key, invalidating the old one.
  ///
  /// Separate from [generateApiKey] only in intent, not in behaviour: this one
  /// is what a person reaches for after the key has been in a shell history, a
  /// screenshot, or a chat, and it must turn the requirement back on even if
  /// they had turned it off.
  Future<void> regenerateApiKey() async {
    await generateApiKey();
    Get.find<AppLogService>()
        .info('Server API key regenerated; the previous key no longer works.');
  }

  Future<void> copyText(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    Get.snackbar('Copied', '$label copied.');
  }

  String get baseUrl =>
      localUrl.value ?? 'http://localhost:${serverPort.value}';

  String get openAiBaseUrl => '$baseUrl/v1';

  @override
  void onClose() {
    portCtrl.dispose();
    apiKeyCtrl.dispose();
    unawaited(stopServer());
    super.onClose();
  }
}
