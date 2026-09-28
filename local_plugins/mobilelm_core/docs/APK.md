# Getting the core into the APK

The plan for 0.4.0, written from the code rather than from the intention. Every
claim below was read out of a file, a header or an API response; the ones that
cost something to establish say how.

Read [`BENCH.md`](BENCH.md) first: it has the device numbers, and this document
assumes them.

## Where this stands

Steps 1–4 of the plan below are done, on `core/rust-hybrid`, and step 5 has
started — the device is the only place it can be done.

| step | state | where |
|---|---|---|
| 1. Pin the runtime version in writing | done | `fetch-litert-capi.sh`, and the wrong `0.17.1` line in `BENCH.md` is corrected |
| 2. `mobilelm-ffi` crate | done | `crates/mobilelm-ffi/`, 14 entry points, `readelf` assertion in CI |
| 3. CI plumbing | done | `.github/workflows/rust-core.yml`, called by all three; `native` job passes in ~1m11s |
| 4. Dart bindings | done | `lib/ffi/mobilelm_core_bindings.dart`, `lib/ffi/litert_engine.dart`; 12 tests that need no device |
| 5. Device run, both paths, same prompt | **load proven, turn not yet measured** | the load runs on the device with no fallback; generation is pending the third build |
| 6. Delete the Kotlin plugin | **blocked, newly** | gated on step 5 *and* on Gap 6 below — not the same gate it was |
| 7. 0.4.0 | not started | |

So the core is in a debug APK and the app **can** use it, behind a switch that
defaults off. What has not happened yet is a measured turn on the Rust path, and
deleting the plugin is now blocked for a reason that was not on the list when this
table was written.

**The Kotlin baseline is measured.** Qwen3-0.6B.litertlm, `cpu_safe` → `cpu`,
ctx 4096, the same prompt on both sides: 11.05 s TTFT, 3.1 tok/s decode, 139
tokens, 55.9 s. The numbers are in `BENCH.md`; they are what the Rust turn is
compared against.

Three findings landed while doing it, two corrections and one blocker:

- **`litert_lm_conversation_get_benchmark_info` exists.** The matrix's prefill
  column said the C API reports no prompt timing. It does, behind
  `litert_lm_engine_settings_enable_benchmark`, which nothing was calling. See
  the correction in `BENCH.md`.
- **`mobilelm-ffi` cannot also be an rlib.** It would emit
  `libmobilelm_core.rlib` into the same `target/` as the `mobilelm-core`
  package's library and the two would overwrite each other depending on build
  order — surfacing as an unrelated crate failing to link.
- **Two device bugs, one shape.** The load worked and generation still failed,
  twice, for reasons that were both "the new path did its job and never said so":
  an undispatched `load` command, and a missing `_isLiteRt`. Each cost a
  22-minute build. The pattern is the finding — an additive path has to establish
  the same shared state the path beside it establishes, or it is invisible until
  it is asked to do the work.

## What 0.4.0 has to be

A minor bump is a promise that the user receives something that did not exist
before. For 0.4.0 that is one sentence: **the LiteRT-LM engine is reached from
Dart through `dart:ffi` and a Rust cdylib, instead of through a hand-written
Kotlin plugin.** Reach, not speed. The engine stays C++ and the throughput does
not change.

Two things follow, and they are the whole shape of the work:

- The Kotlin plugin `local_plugins/flutter_litert_lm` becomes deletable, along
  with its AAR dependency. That is what makes the claim true rather than
  cosmetic — otherwise the Rust path is a second engine, not a replacement.
- The runtime the Rust path loads is a **different binary** from the one the AAR
  ships. That is not a detail, it is the first section below.

## Blocker 1 — the C API prebuilt is v0.16.0, and the only fix in 0.17.1 does not apply to this app

`scripts/fetch-litert-capi.sh` fetches
`litert_lm_c_api-0.1.0.zip` from tag `v0.16.0`. That is the **only** release of
`google-ai-edge/LiteRT-LM` that carries it:

```
v0.17.1  (no c_api asset)
v0.17.0  (no c_api asset)
v0.16.1  (no c_api asset)
v0.16.0  litert_lm_c_api-0.1.0.zip   154.1 MB   sha256:f0f3ae7b...
```

The AAR in the app is `com.google.ai.edge.litertlm:litertlm-android:0.17.1`, so
the Rust path is a runtime **downgrade** unless the C API is rebuilt from source.
Before treating that as fatal, read what 0.17.1 actually fixed — its release note
is one line, and the commit behind it is narrower than it sounds:

```
f300c4fdc28b  fix(tool_use): keep integers as integers in tool call arguments
  runtime/components/tool_use/**            (the native FC parser)
  runtime/components/constrained_decoding/llg_fc_tool_calls.cc
  runtime/components/constrained_decoding/llg_python_tool_calls.cc
```

Every file is the engine's **native function-calling / constrained-decoding**
path — the thing that runs when a model emits tool calls the way Gemma and
Qwen natively do, with the grammar constraining generation.

**This app does not use it.** Tool calls arrive as text and are parsed by regex
in `lib/services/tools/tool_call_parser.dart` — `[TOOL_CALL: name(arg="v")]`, a
fenced JSON block, a bare object, `<tool_call>`. `inference_android.dart` and
`inference_service.dart` contain no occurrence of tools, function declarations
or constrained decoding being handed to LiteRT-LM. The fix touches a code path
this app does not enter.

So the downgrade is real but, as of today, cosmetic. Three consequences worth
writing down rather than rediscovering:

- **It is safe to ship the vendored C API, on this evidence.** The expensive
  alternative — vendoring a CMake build of `litert_lm` at v0.17.1 with its whole
  LiteRT/XNNPACK/TFLite closure — buys a fix for a feature this app does not
  enable.
- **It stops being safe the day native function calling is turned on.** The
  plugin's Dart API has `LiteLmTool` (`lib/src/tool.dart`), so the capability is
  one call away. If native FC is ever adopted, this decision has to be revisited,
  and the cheap fix is then to build the C API at 0.17.1 from source — the tree
  has a root `CMakeLists.txt` and `c/CMakeLists.txt`, so it is an NDK build like
  any other vendored engine.
- **The decision should be written down where the next person looks, not only
  here.** It is a version pin with a reason attached, and the reason is three
  directories away from the code that depends on it.

**`docs/BENCH.md` is wrong on this and should be corrected:** it records the
runtime as "`liblitert-lm.so` 0.17.1". The file on disk came from the v0.16.0
C API package. Whatever v0.16.0 is, that line overstates it.

## Blocker 2 — the APK grows by about 17 MB

Measured, not estimated. From a real `unzip -l` of a debug APK built with the
natives in place:

| | bytes | note |
|---|---|---|
| `liblitertlm_jni.so` (AAR, arm64) | 21,802,952 | removed with the plugin |
| `liblitert-lm.so` (C API, arm64) | 38,969,320 | the same runtime, a different ABI |
| `libmobilelm_core.so` (new cdylib) | **435,568** | |
| net | **+17.6 MB** | before compression |

The cdylib is 436 KB, not the 2–4 MB this section guessed when it was written. It
is a thin ABI over code that was already there, and `opt-level = 3` with
`strip = "symbols"` leaves very little. That correction moves the number by a few
megabytes and changes nothing about the decision, but the number should be the
measured one.

Deleting the AAR pays for a third of the growth, not all of it. The two binaries
are the same runtime with different ABIs, so the C API one is simply larger.

This is a product decision, not an engineering one, and it belongs in the release
notes and the README where the download size is stated. It is also the honest
answer to "is the Kotlin plugin worth keeping": ~18 MB is the price of the Rust
path, and the alternative to paying it is not "no Rust".

**For scale, and not as a proposal:** the same listing shows
`libsd_jni_vulkan.so` at 55.0 MB, `libsd_jni_opencl.so` at 25.2 MB and
`libsd_jni.so` at 24.2 MB — 104 MB of stable-diffusion engines, two and a half
times the LiteRT question and three times its whole budget. If APK size is worth
attacking, that is where it is. It is out of scope here and nothing in this plan
touches it.

Note the C API zip is 154 MB but only 39 MB of it is needed — the fetch script
already unpacks selectively (`include/*` and `lib/android_arm64/*`), so CI pays
for a 154 MB download to place 39 MB in the APK. Caching the download is worth
more than it looks once this runs on every debug build.

## Blocker 3 — resolved: a tag push now builds the cdylib

The three workflows trigger on different things, and that mattered:

| workflow | trigger |
|---|---|
| `ci.yml` | `push: branches: [main]` |
| `debug-apk.yml` | `push` (any branch) + `workflow_dispatch` |
| `release.yml` | `push: tags` |

The cross-compile lived in `ci.yml`, so a tag push built nothing and `release.yml`
had no Rust artifact to download. The gap was invisible: the job was green in
ci.yml, and nobody runs ci.yml when they cut a tag.

`.github/workflows/rust-core.yml` is now a `workflow_call` workflow all three call,
and the six traps the old job had paid for moved into it. The `native` job passes
in 1m11s. Two details worth keeping: a called workflow's jobs get their own
runners, so the **artifact** is the only channel between them — the `cdylib` and
`runtime` outputs are for the log, not for the files; and the `native` job does
**not** declare `environment: release`, because it compiles a cdylib and needs no
signing secret.

## Gap 4 — resolved: all six bindings the app was calling past

`Engine` in `mobilelm-core` is a good shape and the right rules, but the app's
LiteRT path did more than the trait described. Each row below is a thing
`inference_android.dart` did that the Rust core could not. All six are bound now;
the table is kept because the "why" is the part that is easy to lose.

| what the app does | where | what the C API offers | now |
|---|---|---|---|
| set a vision backend | `_createLiteRtEngine` → `LiteLmEngineConfig.visionBackend` | `litert_lm_engine_settings_create(model, backend, vision_backend_str, audio_backend_str)` — `engine.h:491` | `EngineExtras::vision_backend` |
| set an audio backend | same, `audioBackend` | same signature | `EngineExtras::audio_backend` |
| per-turn temperature | `_ensureLiteRtConversation` | `litert_lm_sampler_params_*` — `engine.h:155–180`, reached through a **session** config hung off the conversation | `Sampler` + `reopen_conversation` |
| send an image | `LiteLmContent.imageFile` → `Content.ImageFile` | `message_json` with `content: [{"type":"image",…}]` — `multimodal_processor_helper.cc:64` | `json::parts_message` |
| send audio | `LiteLmContent.audioFile` | same, `{"type":"audio",…}` — same file, line 66 | same |
| count tokens | `countTokens` on the plugin channel | `litert_lm_engine_tokenize` + `…_get_num_tokens` | `LiteRt::count_tokens` |

**The audio backend is not a nicety, it is a crash.** The comment on
`inference_android.dart:516` says leaving `audioBackend` null and then sending
audio segfaults the engine thread — the encoder is never built and the first
frame dereferences it. A Rust path that passes `null` reproduces that segfault,
on a thread where it is much harder to attribute.

The multimodal request side is also the mirror of a bug already paid for.
`json::extract_content_text` unwraps the *response*; there is no Rust code that
*builds* a multimodal message, and the C++ side reads `message["content"]` as an
array of typed items (`multimodal_processor_helper.cc:54-69`). Writing that
builder, and testing it against the literal JSON the device emitted, is the same
discipline that caught the response-side bug.

## Gap 5 — resolved: the ladder has one owner, and it is a pure function

`lib/services/acceleration.dart` held `planLiteRtTier` and
`mobilelm_core::probe` held the Rust answer. Two implementations of one rule is
two answers waiting to disagree, usually on the device nobody tests on.

The rule is now `mobilelm_core::plan::plan_litert_tier`, reached over FFI as
`mobilelm_plan`, and it is a pure function — so the app's accelerator choice is
covered by `cargo test` instead of by trying a model on a phone. The test that
matters is `a_cpu_safe_request_is_never_upgraded`: a plan that quietly upgrades a
CPU-safe request to GPU makes the phone hot and the setting useless, and neither
shows up in a log.

`planLiteRtTier` keeps its old body as the fallback for a build without the
native library — a debug build predating the wiring, a web target, a laptop test.
That body is the *only* other implementation, and it exists for exactly that case.

`settings_view.dart` still calls `NpuStatus.probe()` from the Kotlin plugin, which
is a third answer to the same question. It goes with the plugin in step 6.

One honest limit to carry into the UI: `LoadReport.actual` is set to
`cfg.backend` with a comment saying LiteRT-LM does not report which backend it
settled on. The device run contradicts that being knowable — LiteRT's own
registry logged `RegisterAccelerator: name=CpuAccelerator` after failing the
NPU, while CPU was requested, so in that run they agreed; nothing guarantees
they always will. Whatever the FFI returns, the app must not display `actual` as
an observation.

## Gap 6 — open: the Rust load has no retry ladder, so it cannot serve a multimodal model

Found by reading the two load paths against each other while waiting on a build,
after the device proved the text-only path works.

The Kotlin load is not one load. It is up to three attempts, and each fallback
turns a hard failure into a working model:

| attempt | trigger | what it gives up |
|---|---|---|
| 1 | — | nothing |
| 2 | any failure while `enableVision` | the **audio** encoder |
| 3 | `exactly one signature but got` | **vision**, text-only |

Plus a specific message for `TF_LITE_VISION_ENCODER` — a text-only file loaded as
a vision model — which is the one case that is a user error rather than a missing
capability, and gets a different sentence.

`_loadLiteRtViaRust` has none of the three. It calls `LiteRtEngine.load` once, and
on any error it sets `_rustLoadFailure`, prints, and returns `null` — which the
caller reads as *declined*, so the Kotlin plugin loads the model instead.

That is a safe failure and it is the right default, but it means:

- **the Rust path serves text-only LiteRT-LM, today.** Nothing else.
- **deleting the plugin in step 6 would delete two catalogue models.** gemma-4
  E2B and E4B are LiteRT-LM and multimodal, and neither loads without attempts 2
  and 3.

So step 6's gate is no longer only "the two paths agree on a text-only turn". It
is also "the Rust load can fall back the way the Kotlin load does", and that work
has not been done. Writing it is mechanical — the C API takes both encoder
backends in the same `litert_lm_engine_settings_create` call, and
`EngineExtras::vision_backend`/`audio_backend` are already bound, so a retry is
`LiteRtEngine.load` again with one of them `null` — but it has to be written and
then measured on a real multimodal model, which is what the gemma-4 run is for.

**Until then, keep the plugin.** Deleting it on the strength of a text-only
comparison is how a catalogue quietly loses two models.

## Gap 7 — open: the ABI version is read and never enforced

`mobilelm_abi_version()` returns `0.4.0-ffi.1` and `core_self_check.dart` reads
it, but nothing compares it against the value this Dart was built for. The string
was designed as the guard against a Dart/native signature mismatch — the failure
mode with no symptom — and it is currently decorative.

What it is worth is narrower than it first looks. Android replaces the `.so` on
install, so a stale native library is not a realistic case; the realistic one is a
*source* mismatch, where a signature changed on one side and not the other. That
one does not need a version string — it crashes on the first call, loudly, on the
device. So this is a cheap assertion to add later (compare, refuse, decline to
the plugin) rather than a load-bearing one, and it is deliberately **not** in the
way of 0.4.0. Putting an untested refusal in front of a working fallback in the
same change that first ships the path is the wrong order.

## The shape on the Dart side

There is a working precedent in this repo, and it should be copied rather than
reinvented: `local_plugins/sd_flutter_android` builds `libsd_jni.so` with
Gradle+CMake, places it in `jniLibs/arm64-v8a/`, and `lib/ffi/sd_ffi_bindings.dart`
opens it with `DynamicLibrary.open('libsd_jni.so')` from a spawned isolate,
hopping C-callbacks to Dart through a `SendPort` and a `static` Dart callback
registered with `Pointer.fromFunction` (`sd_ffi_bindings.dart:383-388`).

The LiteRT stream callback arrives on a LiteRT-owned thread, so the same shape
applies and the same hazard comes with it: a `static` callback that outlives the
isolate, or a `NativeCallable` bound to the wrong isolate, is a use-after-free
that shows up as a random crash. `SdIsolateProcessor`'s lifecycle is the
reference for getting the teardown order right.

The engine handle is `Send` and deliberately not `Sync` (`lib.rs:181`), so the
Dart object must own it from exactly one isolate — the same constraint the
plugin's `engineId` string handles today, just enforced by the type system
instead of by convention.

## Order of work

Each step has a gate that is a fact, not an opinion.

**1. Pin the runtime version, in writing.** Record that the vendored C API is
v0.16.0 and why, next to the version in `fetch-litert-capi.sh`, and fix the wrong
`0.17.1` line in `BENCH.md`. *Gate: a written decision, because it is what makes
step 6 defensible.* If native function calling is ever adopted, this comes back
as a source build.

**2. `mobilelm-ffi` crate.** `crate-type = ["cdylib"]`, a `#[no_mangle] extern
"C"` surface, and the six bindings from gap 4. `cargo test` covers the message
builder against device JSON fixtures and the argument marshalling; nothing here
needs a phone. *Gate: `cargo test` and `clippy` green, and a `readelf -d` on the
cdylib that shows no `liblitert` in `DT_NEEDED` — the same assertion the
existing arm64 job makes, now on the artifact that ships.*

**3. CI plumbing.** The reusable workflow, the `jniLibs` injection, the fetch
step in all three workflows. *Gate: a debug APK that contains both
`libmobilelm_core.so` and `liblitert-lm.so`, asserted from the artifact, not
assumed.*

**4. Dart bindings.** `lib/ffi/mobilelm_core_bindings.dart` and an engine object
that satisfies the same shape `_generateLiteRt` uses today — same streaming, same
`_cleanLiteRtChunk` treatment, same idle and hard timeouts, same
`Status Code: 13` retry. Reuse `_cleanLiteRtChunk`; the JSON envelope the Kotlin
path produced is the same one Rust produces, so the cleaner is already correct.
*Gate: a `.litertlm` generating through the Rust path in a debug build, text
only.*

**5. Device run, both paths, same prompt.** The comparison goes in `BENCH.md`
with model, quant, context and resolved backend, and **appends** — the 0.17.1
Kotlin numbers stay where they are. Vision and audio in the same run, because
that is where the null-backend segfault would appear. *Gate: the Rust path is not
slower, and vision and audio both work.*

**6. Delete the plugin.** Remove `local_plugins/flutter_litert_lm`, the AAR
dependency, the `NpuStatus` import in `settings_view.dart`, and
`planLiteRtTier` in `acceleration.dart` if step 5 says Rust owns the ladder.
*Gate: a release APK with `liblitertlm_jni.so` absent, checked with `unzip -l`.*

**7. 0.4.0.** `+build` such that `build + 2000` clears 4004.

## What must not move

- **The engine is `dlopen`ed, never linked.** This is why `cargo test` runs on a
  laptop and why an app can report a missing runtime instead of dying at
  startup. A `#[link]` in the new crate would take that away while every host
  test still passed, so the `readelf` assertion has to move with the artifact.
- **Report the backend that ran.** Carried from `Engine` into the FFI surface;
  the C ABI has no way to make the two agree, so the Dart side has to be told
  which is which.
- **`cargo test` stays host-only and dependency-free.** The FFI crate's tests
  are the reason the message builder is trustworthy before it reaches a phone.
- **Version numbers are `build + 2000`**, per the app guide. A cdylib does not
  change that.
- **Do not move the keystore, the models or the build trees.** `.gitignore`
  already covers `vendor/prebuilt/`, `target/` and `*.litertlm`; the cdylib is
  CI output and must not be committed.

## Gap 8 — open: the stop button cannot stop a Rust turn

Found on the device, when a hung turn was asked to be interrupted and could not
be.

`InferenceEngine.stop()` short-circuits on `_isLiteRt`:

```dart
if (_isLiteRt) {
  _liteConversationHasMessages = true;
  return;
}
await _controller?.stop()   // the Kotlin path, the only one that interrupts
```

That branch exists because the plugin's conversation is the thing a stop has to
tell. With the Rust path it is the wrong branch for a different reason: the call
in flight is `mobilelm_send_stream`, a **blocking FFI call**, and the ABI this
crate exposes has no cancellation hook — the C API's send is non-blocking and
returns a handle, and the whole `send_stream` design here blocks precisely so
nothing outlives the call. There is no point in the call where Dart can observe a
request to stop.

What the user gets is worse than no button at all. `stop()` still calls `_onStop`,
so the UI leaves its thinking state and the turn looks abandoned — while the
native call keeps running and the text arrives anyway. A control that appears to
work and does not is a worse lie than a missing one.

The 20-minute backstop in `litert_engine.dart` is the only thing bounding it
today, and it is a blunt instrument: it reports, it does not stop.

**This is a real cost of the transport, and it belongs in the 0.4.0 decision
rather than after it.** "The engine is reached from Dart instead of through a
Kotlin plugin" is a reach argument, and it is true; "and a turn can no longer be
cancelled" is the other side of it, and the Kotlin path can. Three things would
each close it, in ascending order of work:

1. **`_onStop` stops reporting success.** Cheap, honest, and makes the UI's state
   match reality — the turn really is still running.
2. **Drop the generation isolate and let the process restart the engine.** The
   blocked call dies with the isolate; `_rustLoadFailure` already exists to send
   the next load to the plugin. Coarse, but a stop that works.
3. **A real cancellation hook in the C API path** — the session-based
   `litert_lm_session_*` entry points, if they offer one, reached through a
   handle rather than a blocking wrapper. The `reopen_conversation` binding is
   already there, so the session object is within reach; this is the only option
   that does not involve giving something up.

Do (1) before 0.4.0 regardless of which of the others gets done. A shipped
control that lies is a bug the moment anyone presses it.
