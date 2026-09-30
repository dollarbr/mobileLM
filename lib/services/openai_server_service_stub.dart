import 'dart:async';

import '../core/constants.dart';

class OpenAiServerService {
  bool get isRunning => false;
  String? get localUrl => null;

  Future<void> start({
    int port = AppConstants.defaultServerPort,
    String? apiKey,
    void Function(String)? onLog,
  }) async {
    throw UnsupportedError('Local API server is not available on this platform.');
  }

  Future<void> stop() async {}
}
