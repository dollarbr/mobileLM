/// Which compute tier a model load should aim at.
///
/// The ladder is NPU -> GPU -> CPU. Every tier degrades on its own: LiteRT-LM
/// falls back internally (NPU -> GPU -> CPU) and llama.cpp simply runs the
/// layers it could not offload on the CPU. So a plan is a *preference*, never a
/// promise — always report the backend that actually came back, not this one.
enum AccelTier { npu, gpu, cpu }

/// The decision for one model load.
class AccelerationPlan {
  final AccelTier tier;

  /// llama.cpp `n_gpu_layers`. 0 on the CPU tier, 99 means "all of them"
  /// (llama.cpp clamps it to the model's real layer count).
  final int gpuLayers;

  /// Why this tier — goes straight into the load log, so a device that lands on
  /// CPU says which rung it fell off of.
  final String reason;

  const AccelerationPlan(this.tier, this.gpuLayers, this.reason);

  bool get usesGpu => tier == AccelTier.gpu;
  String get backendName => tier.name;
}

/// Whether this mode is allowed to *open* the GPU at all.
///
/// Separate from [planAcceleration] on purpose, and the reason is a device.
///
/// `planAcceleration` answers "how many layers go on the GPU", and for
/// `cpu_safe` the answer has always been zero. That was not enough: asking the
/// question still calls the native probe, and the probe is what
/// `ggml_backend_load("libggml-vulkan.so")` — so choosing CPU Safe loaded the
/// Vulkan backend and registered the GPU, and the driver was resident for the
/// life of the process.
///
/// Setting `model_params.devices` to a CPU-only list stops the *weights* going
/// across, which is why the Edge 60's numbers improved when that was added
/// (`jni_wrapper.cpp`, the note on "CPU" in Settings). It does not unregister the
/// device. Measured on a Galaxy A72 with an Adreno 618: `cpu_safe` selected,
/// `Device list restricted to the CPU` logged, and then `llama_decode` blocked
/// with every thread asleep and no CPU in use for the full 60 s prefill budget,
/// on a 258 MB model whose 191-token prefill should take seconds. The same
/// comment records the same stall on the Edge 60 costing 5,5 s before the first
/// token. Driver present, CPU idle: the stall is the driver being touched, not
/// arithmetic.
///
/// So the question is no longer "how many layers" but "may we open it", and the
/// honest answer for `cpu_safe` is no. `auto_fast` is allowed to probe, because
/// probing is how the ladder finds out what it has; `gpu_fast` obviously is.
bool modeMayOpenGpu(String mode) => mode != 'cpu_safe';

/// Pick a tier for this load.
///
/// [mode] is the user's setting: `cpu_safe` and `gpu_fast` are explicit
/// overrides and are honoured as far as the hardware allows; `auto_fast` walks
/// the full ladder.
///
/// [recommendedGpuLayers] comes from the native probe, which already weighs
/// free RAM against the device-local heap. It is the number to trust — there is
/// deliberately no GPU-model allowlist here. Binning by the digits in a GPU
/// name ("Mali-G615" -> 615 -> too low, use CPU) is what kept whole vendors off
/// the GPU regardless of how much memory they actually had.
AccelerationPlan planAcceleration({
  required String mode,
  required bool vulkanSupported,
  required int recommendedGpuLayers,
  bool npuAvailable = false,
}) {
  if (mode == 'cpu_safe') {
    return const AccelerationPlan(AccelTier.cpu, 0, 'CPU — user chose CPU Safe');
  }

  if (mode == 'gpu_fast') {
    return vulkanSupported
        ? const AccelerationPlan(AccelTier.gpu, 99, 'GPU — user chose GPU Fast (full offload)')
        : const AccelerationPlan(AccelTier.cpu, 0, 'CPU — GPU Fast asked for, but no Vulkan on this device');
  }

  // auto_fast: the whole ladder.
  if (npuAvailable) {
    return const AccelerationPlan(AccelTier.npu, 0, 'NPU — vendor dispatch driver present');
  }
  if (vulkanSupported && recommendedGpuLayers > 0) {
    return AccelerationPlan(
      AccelTier.gpu,
      recommendedGpuLayers,
      'GPU — Vulkan available, $recommendedGpuLayers layers fit in memory',
    );
  }
  if (vulkanSupported) {
    return const AccelerationPlan(AccelTier.cpu, 0, 'CPU — Vulkan present but not enough free memory to offload');
  }
  return const AccelerationPlan(AccelTier.cpu, 0, 'CPU — no NPU driver and no Vulkan');
}

/// Tier for the LiteRT-LM runtime.
///
/// Kept separate from [planAcceleration] because the two runtimes do not answer
/// to the same probe: LiteRT's GPU tier rides the accelerator bundled inside the
/// litertlm AAR (libLiteRtClGlAccelerator.so — OpenCL/GL, not Vulkan), so our
/// llama.cpp Vulkan capability says nothing about it, and it has no notion of a
/// layer count. What the NPU tier *does* need is a vendor dispatch driver, which
/// is what [npuAvailable] reports.
///
/// This is the one implementation of the rule, and it is a pure function so
/// `test/acceleration_test.dart` covers it. It briefly delegated to
/// `mobilelm_core::plan::plan_litert_tier` in Rust while that core was in the APK;
/// the delegation is gone with it, and this body is what it delegated to, unchanged.
AccelTier planLiteRtTier({required String mode, required bool npuAvailable}) {
  if (mode == 'cpu_safe') return AccelTier.cpu;
  if (npuAvailable) return AccelTier.npu;
  return AccelTier.gpu;
}
