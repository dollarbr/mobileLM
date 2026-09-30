/// Memory right now, as a decision rather than as a number.
///
/// Pure functions on purpose, and for the same reason `acceleration.dart` is
/// pure: everything here is a claim about the phone that can be wrong in a way
/// a screenshot cannot show. Putting the arithmetic in a service keeps it
/// testable without a device, which matters because the failure mode being
/// guarded against — showing a phone as out of memory when it is not — is
/// invisible in a screenshot and costs the user a model they could have run.
///
/// The read itself lives in `device_info_native.dart` / `_web.dart` behind the
/// `dart.library.html` split. This file is the part that decides what the
/// reading means.

import 'dart:math' as math;

/// A memory reading, in bytes.
class MemoryReadout {
  const MemoryReadout({
    required this.totalBytes,
    required this.availableBytes,
    required this.usedBytes,
    required this.freeBytes,
    required this.availableIsEstimated,
  });

  /// Physical RAM, 0 when it could not be read at all.
  final int totalBytes;

  /// What the kernel says it can hand out right now, including cache it would
  /// reclaim. This is the number that predicts whether a load succeeds.
  final int availableBytes;

  /// `total - available`. What Android's low-memory killer reasons about, and
  /// what the bar in the UI shows.
  final int usedBytes;

  /// Genuinely untouched pages. Shown nowhere: on a phone this is small almost
  /// always, so displaying it invites the reading "the phone is full" when it is
  /// not.
  final int freeBytes;

  /// True when `availableBytes` was back-filled from `MemFree` because the
  /// kernel did not publish `MemAvailable`. Two different quantities under one
  /// label would be a small lie, so the UI can say which one it is showing.
  final bool availableIsEstimated;
}

/// Parse a `/proc/meminfo` snapshot.
///
/// Every field is optional on purpose. An Android kernel that publishes
/// `MemAvailable` always publishes `MemTotal`, but a truncated read, a vendor
/// `/proc` mount, and every non-Linux platform produce something that does not
/// parse — and the caller needs a value it can check (`totalBytes == 0` means
/// "not readable here"), not an exception.
MemoryReadout readMeminfo(String meminfo) {
  int? kb(String key) {
    final m = RegExp('^$key:\\s+(\\d+)', multiLine: true).firstMatch(meminfo);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  final totalKb = kb('MemTotal');
  if (totalKb == null) {
    return const MemoryReadout(
      totalBytes: 0,
      availableBytes: 0,
      usedBytes: 0,
      freeBytes: 0,
      availableIsEstimated: true,
    );
  }

  final total = totalKb * 1024;
  final free = (kb('MemFree') ?? 0) * 1024;
  final availableKb = kb('MemAvailable');
  final available = (availableKb ?? kb('MemFree') ?? 0) * 1024;

  return MemoryReadout(
    totalBytes: total,
    // A snapshot can catch the kernel mid-reclaim and report slightly more
    // available than total. Clamping keeps the fraction in range and keeps the
    // bar from asking for a value above 1.
    availableBytes: available > total ? total : available,
    usedBytes: math.max(0, total - available),
    freeBytes: free,
    availableIsEstimated: availableKb == null,
  );
}

/// Whether this reading can be shown at all.
///
/// Zero total is what a platform without `/proc` returns — the web target, and
/// iOS where the plugin reports the device-local heap, which is a different
/// quantity from physical RAM and reporting it as "total" would be a lie the
/// readout could not detect later.
bool memoryIsReadable(MemoryReadout m) => m.totalBytes > 0;

/// Share of RAM in use, 0 to 1.
///
/// Returns 0 rather than dividing by zero. A `NaN` reaching a
/// `LinearProgressIndicator` throws in layout and takes the list it is in with
/// it, which on the Models screen means the whole catalogue disappears — the
/// same shape as the `Column`/`ListView` trap, and guarded the same way: the
/// caller checks [memoryIsReadable] first, and this returns something safe if
/// it forgets.
double memoryUsedFraction(MemoryReadout m) {
  if (m.totalBytes <= 0) return 0;
  return (m.usedBytes / m.totalBytes).clamp(0.0, 1.0);
}

/// Whether to warn that a large model will fail to load.
///
/// 15%, and the number is a measurement rather than a round preference: below
/// it, a 1-2 GB model — the middle of the catalogue — does not fit alongside
/// the system and the load fails outright. It fails rather than runs slowly,
/// which is why the warning exists at all: a slow load is discoverable by
/// waiting, a failed one looks like a broken app.
///
/// An unreadable phone is never tight. Warning about memory that was never
/// measured is the worst version of this message, because it is both alarming
/// and unfounded.
bool isMemoryTight(MemoryReadout m) {
  if (!memoryIsReadable(m)) return false;
  return m.availableBytes / m.totalBytes < 0.15;
}

/// Whole megabytes, for comparison against a catalogue entry's `size`.
///
/// Whole MB on purpose. The models are sold in "149 MB" and "1.2 GB", so the
/// readout has to be comparable to that without the user doing arithmetic.
String formatWholeMb(int bytes) {
  if (bytes <= 0) return '0 MB';
  return '${(bytes / (1024 * 1024)).round()} MB';
}
