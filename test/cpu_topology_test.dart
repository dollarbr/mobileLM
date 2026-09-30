import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/utils/cpu_topology.dart';

/// The thread default used to be `numberOfProcessors ~/ 2`, which is correct only
/// when the big cores are the first half of the list. On a Galaxy A72 they are
/// not — they are cpu6 and cpu7, the last two — so "half" put all four threads on
/// A55s and a 258 MB model produced zero tokens in 60 s.
///
/// These are the topologies the function has to get right, and the first two are
/// measured rather than invented: the A72's lines are copied from
/// `cpuinfo_max_freq` on the device, and the Edge 60's four big cores are the
/// count behind the guide's "4 threads is optimal" note.
Map<int, int> _topo(List<int> freqs) => {
  for (var i = 0; i < freqs.length; i++) i: freqs[i],
};

void main() {
  group('bigCoreCount', () {
    test('the Galaxy A72: two big cores numbered last', () {
      // cpu0-5 A55 at 1804 MHz, cpu6-7 A76 at 2323 MHz.
      final t = _topo([1804000, 1804000, 1804000, 1804000, 1804000, 1804000,
        2323200, 2323200]);
      expect(bigCoreCount(t, totalCores: 8), 2,
          reason: 'two A76s, and the old answer was 4 — all of them A55');
    });

    test('the Edge 60 shape: four big cores, keeps the measured optimum', () {
      // Four A78 at 2400, four A55 at 1800.
      final t = _topo([2400000, 2400000, 2400000, 2400000,
        1800000, 1800000, 1800000, 1800000]);
      expect(bigCoreCount(t, totalCores: 8), 4,
          reason: 'the guide records 4 threads as optimal here, and the fix '
              'must not regress the device it was already right about');
    });

    test('big cores numbered first: same answer as numbered last', () {
      final last = _topo([1804000, 1804000, 1804000, 1804000, 1804000, 1804000,
        2323200, 2323200]);
      final first = _topo([2323200, 2323200, 1804000, 1804000, 1804000, 1804000,
        1804000, 1804000]);
      expect(bigCoreCount(first, totalCores: 8), bigCoreCount(last, totalCores: 8),
          reason: 'the whole point: the answer may not depend on the numbering, '
              'which is exactly the assumption that was wrong');
    });

    test('a single prime core is never the answer', () {
      // 1 prime + 3 big + 4 little, which is a real shape on current Androids.
      final t = _topo([3000000, 2400000, 2400000, 2400000,
        1800000, 1800000, 1800000, 1800000]);
      expect(bigCoreCount(t, totalCores: 8), 2,
          reason: 'one thread starves the pipeline, and the scheduler will move '
              'the work to a little core anyway');
    });

    test('a homogeneous CPU uses every core', () {
      final t = _topo(List<int>.filled(8, 2000000));
      expect(bigCoreCount(t, totalCores: 8), 8,
          reason: 'there is no little core to drag the sync barrier, so the '
              'reason the old code took half does not apply');
    });

    test('a four-core homogeneous phone still gets four', () {
      expect(bigCoreCount(_topo([1800000, 1800000, 1800000, 1800000]),
          totalCores: 4), 4);
    });

    test('falls back to half when the kernel says nothing useful', () {
      expect(bigCoreCount(const {}, totalCores: 8), 4);
      expect(bigCoreCount(_topo([0, 0, 0, 0]), totalCores: 4), 2,
          reason: 'zeros are unreadable, not zero-frequency');
    });

    test('falls back when too few cores report', () {
      // Two of eight readable: the topology is unknown, not two big cores.
      final t = _topo([1804000, 0, 0, 0, 0, 0, 2323200, 0]);
      expect(bigCoreCount(t, totalCores: 8), 4);
    });

    test('three tiers: the fastest tier is the answer', () {
      // 1 prime, 3 big, 4 little. The prime is one core, so the clamp lifts it.
      final t = _topo([3000000, 2400000, 2400000, 2400000,
        1800000, 1800000, 1800000, 1800000]);
      expect(bigCoreCount(t, totalCores: 8), 2);
    });

    test('never exceeds the core count', () {
      final t = _topo([3000000, 3000000, 3000000, 3000000]);
      expect(bigCoreCount(t, totalCores: 4), lessThanOrEqualTo(4));
    });

    test('handles a degenerate core count without throwing', () {
      expect(bigCoreCount(const {}, totalCores: 0), 1);
      expect(bigCoreCount(_topo([2000000]), totalCores: 1), 1);
    });
  });

  group('bigCoreMask', () {
    test('masks exactly the cores the count names', () {
      final t = _topo([1804000, 1804000, 1804000, 1804000, 1804000, 1804000,
        2323200, 2323200]);
      // 0b1100_0000 = cpu6 and cpu7.
      expect(bigCoreMask(t, totalCores: 8), 0xC0);
      expect(bigCoreMask(t, totalCores: 8).bitLength, 8);
    });

    test('is 0 when the topology is unknown', () {
      expect(bigCoreMask(const {}, totalCores: 8), 0);
      expect(bigCoreMask(_topo([1804000, 0, 0, 0, 0, 0, 2323200, 0]),
          totalCores: 8), 0,
          reason: 'a mask built from a partial reading would pin threads to the '
              'wrong cores, which is worse than not pinning at all');
    });

    test('masks every core on a homogeneous CPU', () {
      final t = _topo([2000000, 2000000, 2000000, 2000000]);
      expect(bigCoreMask(t, totalCores: 4), 0xF);
    });

    // The mask reaches native as one integer and becomes a cpu_set_t, so a
    // count and a mask that disagree means the wrong number of cores are both
    // limited and reserved. The A72 is the case that produced the feature: the
    // count said 2 and the mask said cpu6-7, and the two came from separate
    // functions over the same map.
    test('names at least as many cores as the count claims', () {
      const topologies = <List<int>>[
        [1804000, 1804000, 1804000, 1804000, 1804000, 1804000, 2323200, 2323200],
        [2000000, 2000000, 2000000, 2000000],
        [1800000, 1800000, 1800000, 2010000, 2010000, 2010000, 2010000, 2010000],
      ];
      for (final freqs in topologies) {
        final t = _topo(freqs);
        final mask = bigCoreMask(t, totalCores: freqs.length);
        final count = bigCoreCount(t, totalCores: freqs.length);
        int bits(int m) {
          var n = 0;
          while (m != 0) {
            n += m & 1;
            m >>= 1;
          }
          return n;
        }

        expect(bits(mask), count,
            reason: 'mask 0x${mask.toRadixString(16)} covers ${bits(mask)} '
                'cores but the thread count says $count; for '
                '$freqs. Fewer cores than threads means oversubscribing, and '
                'more means the surplus sits idle on cores the count bought.');
      }
    });

    test('never asks for a core index a phone could not have', () {
      // CPU_SETSIZE is 1024 on every bionic and glibc build, and a mask bit
      // above it silently addresses nothing: the loop in pinNewThreads stops
      // there and the log says the mask "names no cpu". Nothing in this app can
      // reach that today — the scan in readMaxFreqPerCore stops at 16 — but the
      // assertion is what makes that a fact rather than a hope.
      final mask = bigCoreMask(
          _topo([1804000, 1804000, 1804000, 1804000, 1804000, 1804000,
            2323200, 2323200]),
          totalCores: 8);
      expect(mask, lessThan(1 << 16));
    });
  });
}
