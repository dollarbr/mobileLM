import 'package:flutter/services.dart';

/// Read access to the loaded model's GGUF metadata.
///
/// Rides its own tiny channel rather than the Pigeon API for the same reason
/// as the mtmd surface: the generated schema is not in the repository, and
/// key/value lookup is self-contained.
class LlamaModelMeta {
  static const _channel = MethodChannel('llama_flutter_android/model_meta');

  /// Value of [key], or null when the model does not carry it.
  static Future<String?> get(String key) async {
    try {
      final v = await _channel.invokeMethod<String>('getMeta', {'key': key});
      return (v == null || v.isEmpty) ? null : v;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Header facts of an on-disk GGUF, read without loading the model:
  /// `arch`, `context_length`, `size_label` (whichever the file carries).
  /// Empty map when the file is missing or is not a readable GGUF.
  static Future<Map<String, String>> probeFile(String path) async {
    try {
      final raw =
          await _channel.invokeMethod<String>('probeFile', {'path': path});
      if (raw == null || raw.isEmpty) return const {};
      return {
        for (final line in raw.split('\n'))
          if (line.contains('='))
            line.substring(0, line.indexOf('=')):
                line.substring(line.indexOf('=') + 1),
      };
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      return const {};
    }
  }
}
