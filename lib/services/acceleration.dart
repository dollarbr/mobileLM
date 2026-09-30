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

/// Below this, a GGUF is faster on the CPU than on the phone's GPU.
///
/// Everything under it is measured; everything over it is not, and the
/// behaviour above it is unchanged. Both facts matter, so neither is buried:
///
/// | model | CPU | GPU | on |
/// |---|---|---|---|
/// | LFM2.5 230M Q4_0 (149 MB) | **57 tok/s** | 10–14 tok/s | Edge 60, 0.5.0 |
/// | 1B Q4_0 (~700 MB) | **21,2 tok/s** | 3,4 tok/s | Edge 60 |
///
/// 4x to 6x, twice, on the same phone, and the gap is not a tuning difference —
/// it is shader and dispatch overhead that does not amortise over a model this
/// small. The 25 s to first token in the same run is the same effect seen from
/// the other end.
///
/// The threshold is in bytes because that is the only size signal the catalogue
/// has (`AiModel.size` is a human string, and the native probe does not report a
/// parameter count). It conflates quantisation with parameter count — a 0.5B at
/// Q8 is bigger on disk than a 1B at Q4 — which biases it towards the CPU. That
/// is the right direction to be biased in, given the numbers above.
const int kSmallGgufCpuWinsBytes = 1280 * 1024 * 1024;

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
///
/// [modelBytes] is the size of the GGUF about to be loaded, or 0 when it is not
/// known. It is what stops `auto_fast` from putting a 230M model on the GPU, and
/// it is the parameter this function was missing: for its whole life it received
/// only capability answers — *can* this device use Vulkan, *how many* layers fit
/// — and never *what* it was being asked to run. Capability is not suitability.
/// A Mali-G615 with memory to spare says yes to a 230M model, and the answer is
/// 4x slower than the CPU it just declined to use.
AccelerationPlan planAcceleration({
  required String mode,
  required bool vulkanSupported,
  required int recommendedGpuLayers,
  bool npuAvailable = false,
  int modelBytes = 0,
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
    // A model this small is slower on the GPU, and it fits in memory by
    // definition — it is small — so the layer count the probe recommended is
    // advice that is right about memory and wrong about speed. Checked before
    // the GPU branch so that a big model, which genuinely needs the offload to
    // load at all, is unaffected.
    if (modelBytes > 0 && modelBytes <= kSmallGgufCpuWinsBytes) {
      return AccelerationPlan(
        AccelTier.cpu,
        0,
        'CPU — ${_mb(modelBytes)} MB model, and the GPU is slower than the CPU '
        'at this size (measured twice on the Edge 60: 57 vs 10-14 tok/s at 230M, '
        '21,2 vs 3,4 at 1B)',
      );
    }
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

String _mb(int bytes) => (bytes / (1024 * 1024)).round().toString();

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
