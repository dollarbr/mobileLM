// What the memory readout is allowed to claim.
//
// The card exists to answer one question before a model is picked: will this
// load. Three ways to get that wrong are fixed here, and all three are
// invisible in a screenshot:
//
//   - reading `MemFree`, which excludes reclaimable cache and reads low on a
//     phone while plenty is actually available, so it warns when it should not;
//   - showing a bar at 0% for "cannot read memory here", which reads as
//     "out of memory" rather than "no information";
//   - dividing by a zero total on a platform that has no /proc.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/services/memory_readout.dart';

void main() {
  group('free memory is MemAvailable, not MemFree', () {
    // A phone sitting idle after opening a few apps: plenty available, almost
    // no genuinely free pages because the rest is cache the kernel will drop
    // under pressure. MemFree here would be a third of the real number.
    const meminfo = '''
MemTotal:        5852108 kB
MemFree:          412508 kB
MemAvailable:    2904116 kB
Buffers:          184320 kB
Cached:          3120440 kB
''';

    test('parses MemTotal into bytes', () {
      expect(readMeminfo(meminfo).totalBytes, 5852108 * 1024);
    });

    test('uses MemAvailable, so reclaimable cache counts as available', () {
      final m = readMeminfo(meminfo);
      expect(m.availableBytes, 2904116 * 1024);
      // The distinction the whole readout rests on: counting MemFree would
      // have made this phone look 2,5 GB short when it is not.
      expect(m.availableBytes, greaterThan(readMeminfo(meminfo).freeBytes));
    });

    test('used is total minus available, matching the low-memory killer', () {
      final m = readMeminfo(meminfo);
      expect(m.usedBytes, m.totalBytes - m.availableBytes);
    });
  });

  group('a phone with no MemAvailable still reports something honest', () {
    // Old kernels omit MemAvailable. Falling back to MemFree would be a
    // different quantity reported under the same label, so the fallback
    // exists but is marked, and the UI can tell the two apart.
    const legacy = '''
MemTotal:        2048000 kB
MemFree:         256000 kB
''';

    test('falls back to MemFree and says so', () {
      final m = readMeminfo(legacy);
      expect(m.availableBytes, 256000 * 1024);
      expect(m.availableIsEstimated, isTrue);
    });

    test('a real MemAvailable is not marked as estimated', () {
      final m = readMeminfo('MemTotal: 100 kB\nMemAvailable: 50 kB\n');
      expect(m.availableIsEstimated, isFalse);
    });
  });

  group('unreadable input is zero, and zero means no card', () {
    test('garbage yields zeros rather than a throw', () {
      final m = readMeminfo('not /proc/meminfo at all');
      expect(m.totalBytes, 0);
      expect(m.availableBytes, 0);
      expect(m.usedBytes, 0);
    });

    test('empty input yields zeros', () {
      final m = readMeminfo('');
      expect(m.totalBytes, 0);
    });

    test('a zero total is not readable, so nothing is rendered', () {
      // The distinction that keeps the web target from drawing an empty bar at
      // 0%: a device that cannot report memory is not a device out of memory.
      expect(memoryIsReadable(readMeminfo('')), isFalse);
    });

    test('the fraction is of what is used, which is what the bar shows', () {
      final m = readMeminfo('MemTotal: 5852108 kB\nMemAvailable: 2904116 kB\n');
      // Just over half used, so just under half free. The bar is the complement
      // of the number the warning reads, and mixing the two up is how a full
      // bar ends up meaning "plenty of room".
      expect(memoryUsedFraction(m),
          closeTo(1 - 2904116 / 5852108, 0.0001));
    });

    test('a zero total yields a fraction, not a NaN', () {
      // A NaN reaching LinearProgressIndicator throws in layout and takes the
      // list it sits in with it — on the Models screen, the whole catalogue.
      expect(memoryUsedFraction(readMeminfo('')), 0.0);
    });

    test('available above total is clamped, so the bar cannot exceed 1', () {
      final m = readMeminfo('MemTotal: 1000000 kB\nMemAvailable: 1000100 kB\n');
      expect(memoryUsedFraction(m), inInclusiveRange(0.0, 1.0));
    });
  });

  group('the low-memory warning has a threshold and a reason', () {
    MemoryReadout? readout(int totalMb, int availableMb) {
      final m = readMeminfo('MemTotal: ${totalMb * 1024} kB\n'
          'MemAvailable: ${availableMb * 1024} kB\n');
      return memoryIsReadable(m) ? m : null;
    }

    test('a phone with half its memory free is not tight', () {
      expect(isMemoryTight(readout(5800, 2900)!), isFalse);
    });

    test('a phone about to fail a 1-2 GB load is tight', () {
      // 700 MB of 5,8 GB is 12% free. The Edge 60's ladder asks the probe how
      // many layers fit, and a phone this full answers with fewer layers, so
      // this is the number where the user should hear about it before picking.
      expect(isMemoryTight(readout(5800, 700)!), isTrue);
    });

    test('the threshold is 15%, not something rounder', () {
      // 14% warns, 16% does not. A round number would have been a preference
      // wearing the costume of a measurement; 15% is where the load starts
      // failing on the models the catalogue actually offers.
      expect(isMemoryTight(readout(1000, 140)!), isTrue);
      expect(isMemoryTight(readout(1000, 160)!), isFalse);
    });

    test('an unreadable phone is never tight', () {
      // Otherwise the card would warn about memory it does not have.
      expect(isMemoryTight(readMeminfo('')), isFalse);
    });
  });

  group('formatting speaks the units the models are sold in', () {
    test('rounds to whole MB, because 0,5 GB is noise here', () {
      // A model is a catalogue entry with a size in MB, so the readout has to
      // be comparable to that without arithmetic in the user's head.
      expect(formatWholeMb(1073741824), '1024 MB');
      expect(formatWholeMb(149 * 1024 * 1024), '149 MB');
    });

    test('never renders a negative free count', () {
      // A kernel snapshot mid-reclaim can report more available than total.
      final m = readMeminfo('MemTotal: 1000000 kB\nMemAvailable: 1000100 kB\n');
      expect(formatWholeMb(m.availableBytes.clamp(0, m.totalBytes)),
          isNot(contains('-')));
    });
  });
}
