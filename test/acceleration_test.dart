import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/services/acceleration.dart';

void main() {
  group('planAcceleration', () {
    test('a Mali GPU with memory to spare goes to the GPU, not to the CPU', () {
      // The regression this whole file exists for: a Mali-G615 (Dimensity 7300)
      // used to be forced onto the CPU by a GPU-name allowlist, twice over —
      // once in Kotlin ("Mali" -> 0 layers) and once in Dart (615 < 650).
      final plan = planAcceleration(
        mode: 'auto_fast',
        vulkanSupported: true,
        recommendedGpuLayers: 99,
      );
      expect(plan.tier, AccelTier.gpu);
      expect(plan.gpuLayers, 99);
    });

    test('NPU wins over GPU when a vendor dispatch driver is present', () {
      final plan = planAcceleration(
        mode: 'auto_fast',
        vulkanSupported: true,
        recommendedGpuLayers: 99,
        npuAvailable: true,
      );
      expect(plan.tier, AccelTier.npu);
    });

    test('no Vulkan means CPU even when the probe suggested layers', () {
      final plan = planAcceleration(
        mode: 'auto_fast',
        vulkanSupported: false,
        recommendedGpuLayers: 99,
      );
      expect(plan.tier, AccelTier.cpu);
      expect(plan.gpuLayers, 0);
    });

    test('the probe deciding no layers fit keeps the load on the CPU', () {
      final plan = planAcceleration(
        mode: 'auto_fast',
        vulkanSupported: true,
        recommendedGpuLayers: 0,
      );
      expect(plan.tier, AccelTier.cpu);
    });

    test('cpu_safe overrides every capability', () {
      final plan = planAcceleration(
        mode: 'cpu_safe',
        vulkanSupported: true,
        recommendedGpuLayers: 99,
        npuAvailable: true,
      );
      expect(plan.tier, AccelTier.cpu);
      expect(plan.gpuLayers, 0);
    });

    test('gpu_fast forces a full offload, but cannot invent Vulkan', () {
      expect(
        planAcceleration(mode: 'gpu_fast', vulkanSupported: true, recommendedGpuLayers: 0).gpuLayers,
        99,
      );
      expect(
        planAcceleration(mode: 'gpu_fast', vulkanSupported: false, recommendedGpuLayers: 99).tier,
        AccelTier.cpu,
      );
    });
  });

  group('the size of the model, which the ladder used to be blind to', () {
    // The measurements, on the same phone, from 0.5.0:
    //   LFM2.5 230M Q4_0 (149 MB): CPU 57 tok/s, GPU 10-14 tok/s, 25 s TTFT
    //   1B Q4_0 (~700 MB):          CPU 21,2 tok/s, GPU 3,4 tok/s
    // 4x to 6x, twice. The capability probe answers "can this device use
    // Vulkan" and it answered yes both times, correctly, and the answer was
    // still the wrong one.

    test('a 230M model on a GPU with memory to spare stays on the CPU', () {
      final plan = planAcceleration(
        mode: 'auto_fast',
        vulkanSupported: true,
        recommendedGpuLayers: 16,
        modelBytes: 149 * 1024 * 1024,
      );
      expect(plan.tier, AccelTier.cpu);
      expect(plan.gpuLayers, 0);
      expect(plan.reason, contains('57 vs 10-14'),
          reason: 'the reason has to name the measurement, or it is just an '
              'assertion in a string');
    });

    test('a 1B model stays on the CPU too, for the same reason', () {
      final plan = planAcceleration(
        mode: 'auto_fast',
        vulkanSupported: true,
        recommendedGpuLayers: 24,
        modelBytes: 700 * 1024 * 1024,
      );
      expect(plan.tier, AccelTier.cpu);
      expect(plan.gpuLayers, 0);
    });

    test('a model above the measured band is offloaded as it always was', () {
      // Nothing in the workspace measures the GPU above ~2B, so nothing here
      // changes above the band. A model this size also needs the offload to
      // load at all, which is a second reason not to touch it.
      final plan = planAcceleration(
        mode: 'auto_fast',
        vulkanSupported: true,
        recommendedGpuLayers: 32,
        modelBytes: 5 * 1024 * 1024 * 1024,
      );
      expect(plan.tier, AccelTier.gpu);
      expect(plan.gpuLayers, 32);
    });

    test('an unknown size keeps the old behaviour rather than guessing', () {
      // 0 is "not read", not "small". A model whose file cannot be measured is
      // about to fail the load, and inventing a size would be a guess dressed
      // as a measurement.
      final plan = planAcceleration(
        mode: 'auto_fast',
        vulkanSupported: true,
        recommendedGpuLayers: 16,
      );
      expect(plan.tier, AccelTier.gpu);
    });

    test('gpu_fast still overrides the size rule, because the user said so', () {
      // The size rule exists to stop `auto_fast` from being wrong on its own.
      // A person who taps "GPU Fast" has asked for the GPU, and the numbers say
      // they will be slower; that is their call to make, and the app's job is
      // to have told them, not to overrule them.
      final plan = planAcceleration(
        mode: 'gpu_fast',
        vulkanSupported: true,
        recommendedGpuLayers: 16,
        modelBytes: 149 * 1024 * 1024,
      );
      expect(plan.tier, AccelTier.gpu);
      expect(plan.gpuLayers, 99);
    });

    test('cpu_safe is unaffected, and so is a device with no Vulkan', () {
      expect(
        planAcceleration(
          mode: 'cpu_safe',
          vulkanSupported: true,
          recommendedGpuLayers: 16,
          modelBytes: 149 * 1024 * 1024,
        ).tier,
        AccelTier.cpu,
      );
      expect(
        planAcceleration(
          mode: 'auto_fast',
          vulkanSupported: false,
          recommendedGpuLayers: 16,
          modelBytes: 149 * 1024 * 1024,
        ).tier,
        AccelTier.cpu,
      );
    });

    test('the NPU still wins over both, because it is not a GPU trade-off', () {
      final plan = planAcceleration(
        mode: 'auto_fast',
        vulkanSupported: true,
        recommendedGpuLayers: 16,
        npuAvailable: true,
        modelBytes: 149 * 1024 * 1024,
      );
      expect(plan.tier, AccelTier.npu);
    });
  });

  group('modeMayOpenGpu', () {
    test('cpu_safe is the only mode that may not open the GPU', () {
      expect(modeMayOpenGpu('cpu_safe'), isFalse);
      expect(modeMayOpenGpu('auto_fast'), isTrue);
      expect(modeMayOpenGpu('gpu_fast'), isTrue);
    });

    test('a closed GPU still plans as CPU, with the same reason', () {
      // The point of the gate is that it costs nothing in behaviour: the probe
      // is skipped, not the decision. Both calls must land on the same plan, or
      // a model would load differently depending on whether we looked first.
      final probed = planAcceleration(
        mode: 'cpu_safe',
        vulkanSupported: true,
        recommendedGpuLayers: 99,
      );
      final unprobed = planAcceleration(
        mode: 'cpu_safe',
        vulkanSupported: false,
        recommendedGpuLayers: 0,
      );
      expect(unprobed.tier, probed.tier);
      expect(unprobed.gpuLayers, probed.gpuLayers);
      expect(unprobed.reason, probed.reason);
      expect(unprobed.gpuLayers, 0);
    });

    test('the gate is a deny, so an unknown mode may still open the GPU', () {
      // A setting read from Hive that is not one of the three should degrade to
      // the ladder rather than silently pinning the user to the CPU.
      expect(modeMayOpenGpu(''), isTrue);
      expect(modeMayOpenGpu('cpu-safe'), isTrue);
    });
  });

  group('planLiteRtTier', () {
    test('NPU only when a dispatch driver is actually bundled', () {
      expect(planLiteRtTier(mode: 'auto_fast', npuAvailable: true), AccelTier.npu);
      expect(planLiteRtTier(mode: 'auto_fast', npuAvailable: false), AccelTier.gpu);
    });

    test('cpu_safe skips the whole ladder', () {
      expect(planLiteRtTier(mode: 'cpu_safe', npuAvailable: true), AccelTier.cpu);
    });
  });
}
