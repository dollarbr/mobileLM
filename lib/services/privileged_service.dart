import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'tools/privileged_tools.dart';
import 'tools/tool_registry.dart';

/// Why the privileged block is or is not available.
///
/// Four states rather than one "unavailable", because each asks a different
/// thing of the user and a single label would hide that.
enum ShizukuState {
  notInstalled,
  stopped,
  needsPermission,
  ready;

  String get hint => switch (this) {
        ShizukuState.notInstalled =>
          'Shizuku is a separate app — install it to enable these tools.',
        ShizukuState.stopped =>
          'Shizuku is installed but not running. Start it over wireless '
              'debugging; it stays up until the phone reboots.',
        ShizukuState.needsPermission =>
          'Shizuku is running. Grant this app permission to use it.',
        ShizukuState.ready => '',
      };

  String get label => switch (this) {
        ShizukuState.notInstalled => 'Shizuku not found',
        ShizukuState.stopped => 'Shizuku stopped',
        ShizukuState.needsPermission => 'Awaiting permission',
        ShizukuState.ready => 'Active',
      };
}

/// Talks to the Shizuku binder through the platform channel.
///
/// The app never invokes `su` and never requires root. Shizuku itself may have
/// been started as root by the user; [identity] reports that, because the same
/// command does different things under uid 2000 and uid 0.
class PrivilegedService extends GetxService {
  static const _channel = MethodChannel('com.aichat.ai_chat/privileged');

  final state = ShizukuState.notInstalled.obs;

  /// `shell 2000` or `root 0`, empty until ready.
  final identity = ''.obs;

  bool get isReady => state.value == ShizukuState.ready;

  Future<void> refresh() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('probe');
      state.value = ShizukuState.values.firstWhere(
        (s) => s.name == (res?['state'] ?? ''),
        orElse: () => ShizukuState.notInstalled,
      );
      identity.value = (res?['identity'] ?? '').toString();
    } on PlatformException {
      state.value = ShizukuState.notInstalled;
    } on MissingPluginException {
      state.value = ShizukuState.notInstalled;
    }
  }

  Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod<void>('requestPermission');
    } on PlatformException {
      // The listener on the Kotlin side settles the result; refresh reads it.
    } on MissingPluginException {
      // Nothing to grant in a build without the channel.
    }
    await refresh();
  }

  Future<String> run(List<String> argv) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'run',
        {'argv': argv, 'timeoutMs': 20000},
      );
      final out = (res?['stdout'] ?? '').toString();
      final err = (res?['stderr'] ?? '').toString();
      final exit = (res?['exit'] as num?)?.toInt() ?? -1;
      if (exit != 0 && out.trim().isEmpty) {
        return 'Error: command exited $exit. ${err.trim()}';
      }
      return err.trim().isEmpty ? out : '$out\n[stderr] ${err.trim()}';
    } on PlatformException catch (e) {
      return 'Error: ${e.message ?? e.code}';
    } on MissingPluginException {
      return 'Error: the privileged channel is not available in this build.';
    }
  }
}

/// The privileged block, or nothing at all.
///
/// Hidden rather than advertised-and-broken: the registry already argues that
/// a model told about a tool that then refuses to run wastes a turn arguing
/// with itself.
List<Tool> privilegedToolsIfReady() {
  if (!Get.isRegistered<PrivilegedService>()) return const [];
  final service = Get.find<PrivilegedService>();
  if (!service.isReady) return const [];
  return buildPrivilegedTools(run: service.run);
}
