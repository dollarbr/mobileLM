import 'dart:async';
import 'package:get/get.dart';

import 'device_info_native.dart' if (dart.library.html) 'device_info_web.dart'
    as platform_info;
import 'memory_readout.dart';

/// Device capability detection — reads RAM to set safe inference limits.
/// Cross-platform: works on Android/iOS natively, defaults on web.
class DeviceInfoService extends GetxService {
  final totalRamGB = 0.0.obs;
  final availableRamGB = 0.0.obs;
  final deviceTier = ''.obs; // 'low', 'mid', 'high', 'ultra'
  final isTensorSoC = false.obs;
  final socFamily = platform_info.SocFamily.unknown.obs;
  final socHardware = ''.obs;

  // Recommended limits based on device RAM
  int get recommendedContextSize => _tierConfig['contextSize']!;
  int get recommendedMaxTokens => _tierConfig['maxTokens']!;
  int get maxSafeContextSize => _tierConfig['maxContextSize']!;
  int get maxSafeTokens => _tierConfig['maxSafeTokens']!;

  /// The largest model file worth offering, in bytes.
  ///
  /// Not total RAM: Android's low-memory killer takes the app long before the
  /// weights are exhausted. Weights budget: 25% of physical RAM. The rest has
  /// to hold KV cache, a projector on multimodal models, the OS and this UI.
  int get maxModelBytes =>
      (totalRamGB.value * 0.25 * 1024 * 1024 * 1024).round();

  Map<String, int> get _tierConfig {
    final ram = totalRamGB.value;
    if (ram <= 4) {
      return {
        'contextSize': 1024,
        'maxTokens': 256,
        'maxContextSize': 2048,
        'maxSafeTokens': 512,
      };
    } else if (ram <= 6) {
      return {
        'contextSize': 2048,
        'maxTokens': 512,
        'maxContextSize': 4096,
        'maxSafeTokens': 1024,
      };
    } else if (ram <= 8) {
      return {
        'contextSize': 4096,
        'maxTokens': 1024,
        'maxContextSize': 8192,
        'maxSafeTokens': 2048,
      };
    } else if (ram <= 12) {
      return {
        'contextSize': 4096,
        'maxTokens': 2048,
        'maxContextSize': 8192,
        'maxSafeTokens': 4096,
      };
    } else {
      return {
        'contextSize': 8192,
        'maxTokens': 4096,
        'maxContextSize': 16384,
        'maxSafeTokens': 4096,
      };
    }
  }

  Future<DeviceInfoService> init() async {
    await refreshMemoryInfo();

    // Classify device tier
    final ram = totalRamGB.value;
    if (ram <= 4) {
      deviceTier.value = 'low';
    } else if (ram <= 6) {
      deviceTier.value = 'mid';
    } else if (ram <= 8) {
      deviceTier.value = 'high';
    } else {
      deviceTier.value = 'ultra';
    }

    print('[DeviceInfo] RAM: ${totalRamGB.value.toStringAsFixed(1)}GB total, '
        '${availableRamGB.value.toStringAsFixed(1)}GB available, '
        'tier: ${deviceTier.value}, tensor: ${isTensorSoC.value}');
    return this;
  }

  /// The live reading. One observable rather than three, so the UI cannot mix a
  /// total from one poll with an available from another and report a phone that
  /// never existed.
  ///
  /// What the reading *means* — readable, tight, what fraction — is decided by
  /// the pure functions in `memory_readout.dart`, which is where those claims are
  /// tested. This side only fetches.
  final memory = const MemoryReadout(
    totalBytes: 0,
    availableBytes: 0,
    usedBytes: 0,
    freeBytes: 0,
    availableIsEstimated: true,
  ).obs;

  /// Kept for the callers that want a raw number. Reads the same snapshot the
  /// card draws, never a separate one.
  int get memoryTotalBytes => memory.value.totalBytes;
  int get memoryAvailableBytes => memory.value.availableBytes;
  int get memoryUsedBytes => memory.value.usedBytes;

  Timer? _memoryTimer;
  bool _memoryWatchOn = false;

  /// Re-read memory, cheaply — `/proc/meminfo` only, no SoC detection.
  ///
  /// The boot-time `refreshMemoryInfo` is not reusable for this: it also re-reads
  /// `/proc/cpuinfo` and re-runs SoC classification, which is right once and
  /// waste on a timer. Split so the frequent thing stays frequent and cheap.
  ///
  /// A failed or zero-total read leaves the last good numbers in place instead
  /// of publishing zeros. A transient read failure would otherwise make a
  /// perfectly healthy phone show an empty bar, which is a claim, not a gap.
  Future<void> refreshMemoryBytes() async {
    try {
      final parsed = readMeminfo(await platform_info.getMeminfo() ?? '');
      if (!memoryIsReadable(parsed)) return;
      memory.value = parsed;
    } catch (_) {
      // A readout is not worth a crash; leave the last good numbers up.
    }
  }

  /// Start or stop the periodic readout. Idempotent, so a rebuild can call it
  /// without leaking a timer.
  ///
  /// Started when something is happening and stopped when it is not, rather than
  /// running forever: this is a readout for watching a model load, not a
  /// dashboard, and a timer that never stops is a battery bug on a phone whose
  /// whole point of measurement is that it is not the user's daily driver.
  void watchMemory({required bool on, Duration every = const Duration(seconds: 2)}) {
    if (on == _memoryWatchOn) return;
    _memoryWatchOn = on;
    if (on) {
      refreshMemoryBytes();
      _memoryTimer = Timer.periodic(every, (_) => refreshMemoryBytes());
    } else {
      _memoryTimer?.cancel();
      _memoryTimer = null;
    }
  }

  @override
  void onClose() {
    _memoryTimer?.cancel();
    super.onClose();
  }

  Future<void> refreshMemoryInfo() async {
    final info = await platform_info.getDeviceInfo();
    totalRamGB.value = (info['totalRamGB'] as num).toDouble();
    availableRamGB.value = (info['availableRamGB'] as num).toDouble();
    await refreshMemoryBytes();
    isTensorSoC.value = (info['isTensorSoC'] as num? ?? 0.0) > 0.5;
    final rawIndex = (info['socFamily'] as num? ?? 8).toInt();
    final clamped = rawIndex < 0 ? 0 : (rawIndex > 8 ? 8 : rawIndex);
    socFamily.value = platform_info.SocFamily.values[clamped];
    socHardware.value = (info['socHardware'] as String?) ?? '';
  }

  String get tierDescription {
    switch (deviceTier.value) {
      case 'low':
        return '⚠️ Low RAM (${totalRamGB.value.toStringAsFixed(1)}GB) — Use small models only';
      case 'mid':
        return '📱 Mid-range (${totalRamGB.value.toStringAsFixed(1)}GB) — Good for 1-3B models';
      case 'high':
        return '💪 High-end (${totalRamGB.value.toStringAsFixed(1)}GB) — Can run 3-7B models';
      case 'ultra':
        return '🚀 Ultra (${totalRamGB.value.toStringAsFixed(1)}GB) — Full performance mode';
      default:
        return '📱 ${totalRamGB.value.toStringAsFixed(1)}GB RAM detected';
    }
  }
}
