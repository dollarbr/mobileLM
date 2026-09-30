/// How many of this phone's cores are the fast ones.
///
/// The question looks trivial and is not, because the previous answer was
/// `Platform.numberOfProcessors ~/ 2`, and that is wrong on every phone whose
/// big cores are not the first half of the core list.
///
/// Measured on a Galaxy A72 (Snapdragon 720G, `SM_A725M`):
///
/// ```
/// cpu0..cpu5  cpuinfo_max_freq = 1804 MHz   6 × A55
/// cpu6..cpu7  cpuinfo_max_freq = 2323 MHz   2 × A76
/// ```
///
/// Half of eight is four, which on this device is cpu0–cpu3 — **all four of them
/// A55**. The default put every thread on the slowest core. The cost was not
/// subtle: SmolLM2-360M, 258 MB, whose 191-token prefill should take well under a
/// second on a Snapdragon 720G, produced **zero tokens in the 60 s** prefill budget
/// and came back as `Model did not respond. Try a smaller model or shorter
/// conversation.` The model was fine. The default was inverted.
///
/// The fix is to read the topology rather than assume it, because the assumption
/// is not merely approximate on some devices and merely wrong on others — the
/// prime cores are numbered *last* on this Qualcomm part and first on most ARM
/// designs, so the same arithmetic lands on opposite sets of cores depending on
/// who built the SoC.
///
library;

import 'dart:io';

/// The core count to use when the setting is "auto", given each core's maximum
/// frequency in kHz.
///
/// Pure, and separated from the reading of `/sys` so it can be tested against
/// real topologies instead of against the phone it happens to be running on.
///
/// [maxFreqKhz] maps a core index to that core's `cpuinfo_max_freq`. Missing
/// entries are cores that could not be read.
///
/// Returns the number of cores in the fastest tier, with two adjustments that
/// are both about not being pathological:
///
/// * **One is never the answer.** A single prime core with the rest of the chip
///   idle starves the pipeline and, on a big.LITTLE phone, the scheduler will
///   move the work to a little core anyway. A device that reports a single
///   fastest core — which happens where there is one prime core above a cluster
///   of big ones — gets two.
/// * **No usable data falls back** to half the cores, which is what this whole
///   function replaced. It is the right answer on a homogeneous CPU and a merely
///   wrong one on a heterogeneous phone, so it is the right thing to keep as the
///   last resort when the kernel will not tell us anything.
int bigCoreCount(Map<int, int> maxFreqKhz, {required int totalCores}) {
  if (totalCores < 1) return 1;

  final read = <int, int>{
    for (final e in maxFreqKhz.entries)
      if (e.value > 0) e.key: e.value,
  };
  // Half the cores reporting is the line. A phone where a third of the sysfs
  // entries are unreadable is a phone whose topology we do not know, and a wrong
  // topology here is the bug this function exists to remove.
  if (read.length * 2 < totalCores) return (totalCores ~/ 2).clamp(1, totalCores);

  final fastest = read.values.reduce((a, b) => a > b ? a : b);
  final inTopTier = read.values.where((f) => f == fastest).length;

  // The floor of 2 is capped by the core count before it is used, because
  // `int.clamp` throws when the lower bound exceeds the upper, and a one-core
  // phone with one fastest core would otherwise ask for two of one.
  final floor = inTopTier == 1 ? (totalCores < 2 ? 1 : 2) : 1;
  return inTopTier.clamp(floor, totalCores);
}

/// A bitmask of the fastest cores, for [bigCoreCount]'s tier, or 0 when unknown.
///
/// One bit per core, so the A72 topology above is `0xC0` — cpu6 and cpu7.
///
/// 0 is a real answer, not a failure to answer: it means the topology could not
/// be read with enough confidence, and the caller must then leave placement to
/// the scheduler. A guessed mask pins work to the wrong cores, which on a phone
/// means the big ones stay idle, which is the bug this whole file exists to
/// remove — reintroduced one layer down.
///
/// Why this exists when `llama_context_params` has no `cpumask` and the
/// `ggml_thread_apply_affinity` call inside `ggml-cpu.c` is therefore
/// unreachable: that path is closed, and the mask instead goes to the JNI as a
/// plain integer, where the load identifies the threads llama.cpp created and
/// pins them with `sched_setaffinity`. See `nativeSetComputeAffinity` in
/// `jni_wrapper.cpp` for why the identification is done by difference and what
/// was measured on the A72 — 3.9 tok/s unpinned against a stable 2.323 MHz
/// pinned, same APK, same ROM, same model file.
int bigCoreMask(Map<int, int> maxFreqKhz, {required int totalCores}) {
  final read = <int, int>{
    for (final e in maxFreqKhz.entries)
      if (e.value > 0) e.key: e.value,
  };
  if (read.length * 2 < totalCores || read.isEmpty) return 0;
  final fastest = read.values.reduce((a, b) => a > b ? a : b);
  var mask = 0;
  for (final e in read.entries) {
    if (e.value == fastest) mask |= 1 << e.key;
  }
  return mask;
}

Map<int, int>? _cache;

/// The same read, synchronously, for widget builds.
///
/// A `build` cannot await, and the Settings label needs the same number the
/// loader will use — a label computed by a different rule than the code it
/// describes is how the old one ended up lying. This reads the same files the
/// same way; the only difference is that it cannot be the first reader, so on a
/// cold start the first build may see an empty map and render the fallback until
/// the loader has run once. [primeSync] is what that costs.
Map<int, int> readMaxFreqPerCoreSync() {
  if (_cache != null) return _cache!;
  final out = <int, int>{};
  for (var cpu = 0; cpu < 16; cpu++) {
    final f = File(
      '/sys/devices/system/cpu/cpu$cpu/cpufreq/cpuinfo_max_freq',
    );
    try {
      if (!f.existsSync()) {
        if (out.isNotEmpty) break;
        continue;
      }
      out[cpu] = int.parse(f.readAsStringSync().trim());
    } catch (_) {
      // Counted as unreadable; the ratio check decides whether that matters.
    }
  }
  _cache = out;
  return out;
}

Future<Map<int, int>> readMaxFreqPerCore() async {
  if (_cache != null) return _cache!;
  final out = <int, int>{};
  for (var cpu = 0; cpu < 16; cpu++) {
    final f = File(
      '/sys/devices/system/cpu/cpu$cpu/cpufreq/cpuinfo_max_freq',
    );
    try {
      if (!await f.exists()) {
        // Cores are numbered contiguously on every device seen so far, so the
        // first gap ends the scan rather than continuing to a guess.
        if (out.isNotEmpty) break;
        continue;
      }
      out[cpu] = int.parse((await f.readAsString()).trim());
    } catch (_) {
      // A core that will not answer is a core we know nothing about; the ratio
      // check in [bigCoreCount] decides whether that matters.
    }
  }
  _cache = out;
  return out;
}
