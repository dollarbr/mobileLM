import 'package:flutter/services.dart';

/// Where the next load's compute threads run.
///
/// A thread *count* is not a thread *placement*, and on a heterogeneous phone the
/// difference is not a few percent. Measured on a Galaxy A72 (Snapdragon 720G,
/// cpu0-5 A55 at 1804 MHz, cpu6-7 A76 at 2323 MHz): the same APK, the same ROM,
/// the same model file and the same 2 threads reported 3.9 tok/s on one run and
/// 7.6 on the next, because the threads were spread across all 8 cores, each A76
/// saw so little load that schedutil parked the cluster in its lowest bin
/// (652.800 Hz, 28% of the ceiling), and pulled it down again several times a
/// second. Pinned to cpu6-7, the same generation holds 2.323.200 MHz throughout.
///
/// So the count comes from `cpu_topology.dart` and the placement comes from here.
/// The mask is a core bitmask, one bit per core, the same integer
/// `bigCoreMask` already returns.
class LlamaComputeAffinity {
  static const _channel = MethodChannel('llama_flutter_android/affinity');

  /// Pin the compute threads of the next load to [mask], or 0 to leave placement
  /// to the scheduler.
  ///
  /// Must be called before the load. The threads do not exist until the context
  /// is created, and they are identified by appearing during it, so a mask set
  /// afterwards has nothing to attach to.
  ///
  /// Silently does nothing if the native side is missing, rather than throwing:
  /// this is a performance setting, and a model that runs unpinned is slower but
  /// correct. A failure here must not be the reason a load fails.
  static Future<void> setMask(int mask) async {
    try {
      await _channel.invokeMethod<void>('setComputeAffinity', {'mask': mask});
    } on PlatformException {
      // No native side yet; the load will say so itself.
    } on MissingPluginException {
      // Not Android, or the plugin is not registered.
    }
  }
}
