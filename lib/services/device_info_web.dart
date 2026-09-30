/// Web device info — no RAM detection, use generous defaults.
Future<Map<String, dynamic>> getDeviceInfo() async {
  return {
    'totalRamGB': 8.0,
    'availableRamGB': 4.0,
    'isTensorSoC': 0.0,
    'socFamily': 8, // unknown
    'socHardware': '',
  };
}

/// Web has no memory to report, so there is no `/proc/meminfo` to hand over.
///
/// Null rather than a zeroed string: `readMeminfo('')` is already "nothing to
/// read", and a fabricated total would show a bar that means nothing.
Future<String?> getMeminfo() async => null;
