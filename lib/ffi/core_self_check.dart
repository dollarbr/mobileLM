// A startup self-check for the Rust core, logged once.
//
// This exists because the core's failure modes are silent in a way that matters.
// `DynamicLibrary.open` returning null, a runtime that will not `dlopen`, and a
// runtime missing optional entry points all produce **no error and no crash** —
// the app simply keeps using the Kotlin plugin, and the user sees an app that
// works exactly as it did before. That is the correct behaviour, and it is also
// indistinguishable from "the core was never wired up".
//
// So it says so, once, in a line. It answers the question that otherwise has no
// answer on a device: *is this APK using the Rust core or not?* The same line
// reports which optional C API symbols the device's runtime lacks, which is the
// only way to find out why temperature is doing nothing on a phone whose runtime
// is not the one the build was tested against.
//
// Kept in the app rather than in CI because the question can only be answered on
// the hardware. CI can prove the library is in the APK — it does, by reading the
// APK — and it cannot prove the loader finds it there.

import 'dart:io';

import 'mobilelm_core_bindings.dart';

class CoreSelfCheck {
  const CoreSelfCheck._();

  static bool _done = false;

  /// Run once per process. Never throws: a diagnostic that can crash the app it
  /// is diagnosing is not a diagnostic.
  static Future<void> run() async {
    if (_done) return;
    _done = true;
    try {
      final core = MobilelmCore.tryLoad();
      if (core == null) {
        _say('absent: $kCoreLibraryName did not open. '
            '${Platform.isAndroid ? 'This build has no Rust core.' : 'Not an Android build.'}');
        return;
      }
      final abi = core.abiVersion;
      String runtime;
      try {
        final missing = core.symbolsMissing(kLiteRtRuntimeName);
        if (missing.isEmpty) {
          runtime =
              'runtime $kLiteRtRuntimeName: all optional C API symbols present';
        } else {
          final head = missing.take(6).join(', ');
          final more =
              missing.length > 6 ? ', and ${missing.length - 6} more' : '';
          runtime = 'runtime $kLiteRtRuntimeName: MISSING ${missing.length} '
              'symbol(s): $head$more';
        }
      } catch (e) {
        // The runtime is missing or unloadable. That is a different failure from
        // the core being absent, and conflating them is how "the core is broken"
        // gets blamed on the core when the 39 MB library is the problem.
        runtime = 'runtime $kLiteRtRuntimeName: could not be inspected — $e';
      }
      _say('present: abi=$abi, $runtime');
    } catch (e) {
      _say('error: $e');
    }
  }

  static void _say(String message) {
    // `print` is what the log poller drains into app_flutter/logs/app.log, which
    // is the only place a user can get at this without a cable.
    print('[CoreSelfCheck] $message');
  }
}
