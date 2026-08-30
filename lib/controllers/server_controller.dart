import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../core/constants.dart';
import '../services/app_log_service.dart';
import '../services/hive_service.dart';
import '../services/inference_service.dart';
import '../services/openai_server_service.dart';

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

  /// User-configured port (default 8080). May be overridden at start time
  /// if the user's choice is already in use.
  final serverPort = RxInt(8080);

  late final TextEditingController portCtrl;
  late final TextEditingController apiKeyCtrl;

  static const int _defaultPort = 8080;
  static const int _maxPortProbe = 9000;

  @override
  void onInit() {
    super.onInit();
    useApiKey.value =
        _hive.getSetting<bool>(AppConstants.keyServerUseApiKey) ?? false;
    apiKey.value = _hive.getSetting<String>(AppConstants.keyServerApiKey) ?? '';
    serverPort.value =
        _hive.getSetting<int>(AppConstants.keyServerPort) ?? _defaultPort;

    portCtrl =
        TextEditingController(text: serverPort.value.toString());
    apiKeyCtrl = TextEditingController(text: apiKey.value);
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
      await ServerSocket.bind(InternetAddress.anyIPv4, port);
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
    if (!hasLocalModel) {
      lastError.value = 'Load a local GGUF or LiteRT-LM model first.';
      Get.snackbar('Server not started', lastError.value!);
      return;
    }

    // Persist whatever port the user typed before probing.
    await saveSettings();

    // If the configured port is busy, find the next free one and inform
    // the user so they know their setting was respected but couldn't be used.
    final configured = serverPort.value;
    if (configured != _defaultPort && !await isPortFree(configured)) {
      final chosen = await findAvailablePort(configured + 1);
      serverPort.value = chosen;
      Get.snackbar(
        'Port occupied',
        'Port $configured is already in use. Server will run on $chosen.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } else if (configured != _defaultPort) {
      // Port is free — just let the user know it was applied.
      Get.snackbar(
        'Server port set',
        'Will listen on port $configured.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
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
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    apiKey.value =
        'aichat_${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    useApiKey.value = true;
    await saveSettings();
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
