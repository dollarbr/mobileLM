# Getting the core into the APK

The plan for 0.4.0, written from the code rather than from the intention. Every
claim below was read out of a file, a header or an API response; the ones that
cost something to establish say how.

Read [`BENCH.md`](BENCH.md) first: it has the device numbers, and this document
assumes them.

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

## Blocker 2 — the APK grows by about 20 MB

| | now | after |
|---|---|---|
| `liblitertlm_jni.so` (AAR, arm64) | 21.8 MB | — removed with the plugin |
| `liblitert-lm.so` (C API, arm64) | — | 38.9 MB |
| `libmobilelm_core.so` (new cdylib) | — | ~2–4 MB |
| published APK | 78 MB | **~98 MB** |

Deleting the AAR pays for a third of the growth, not all of it. The two binaries
are the same runtime with different ABIs, so the C API one is simply larger.

This is a product decision, not an engineering one, and it belongs in the release
notes and the README where the download size is stated. It is also the honest
answer to "is the Kotlin plugin worth keeping": 20 MB is the price of the Rust
path, and the alternative to paying it is not "no Rust".

Note the C API zip is 154 MB but only 39 MB of it is needed — the fetch script
already unpacks selectively (`include/*` and `lib/android_arm64/*`), so CI pays
for a 154 MB download to place 39 MB in the APK. Caching the download is worth
more than it looks once this runs on every debug build.

## Blocker 3 — a tag push never builds the cdylib

The three workflows trigger on different things, and that matters more than it
looks:

| workflow | trigger |
|---|---|
| `ci.yml` | `push: branches: [main]` |
| `debug-apk.yml` | `push` (any branch) + `workflow_dispatch` |
| `release.yml` | `push: tags` |

The `rust-core-android` job that cross-compiles the core lives in `ci.yml`. A tag
push **does not run `ci.yml`**, so at the moment `release.yml` starts there is no
Rust artifact to download. Building the cdylib inside the Flutter Gradle build is
worse: it puts a `rustup` and `cargo-ndk` install into a job that is already the
slowest in the repo, and it makes the APK depend on a toolchain the Flutter build
has no other reason to need.

The answer is a **reusable workflow** (`on: workflow_call`) that builds the
cdylib and uploads it, called by all three. One definition, one cache, one place
that knows the toolchain. The existing `rust-core-android` job becomes a call to
it, and its six hard-won traps (two NDKs in the image, `file` exiting 0 on a
missing path, `ldd` being useless, the `readelf` assertion) move with it.

## Gap 4 — the core is missing six things the app already calls

`Engine` in `mobilelm-core` is a good shape and the right rules, but the app's
LiteRT path does more than the trait describes. Each row below is a thing
`inference_android.dart` does today that the Rust core cannot yet do.

| what the app does | where | what the C API offers | state in the core |
|---|---|---|---|
| set a vision backend | `_createLiteRtEngine` → `LiteLmEngineConfig.visionBackend` | `litert_lm_engine_settings_create(model, backend, vision_backend_str, audio_backend_str)` — `engine.h:491` | `load()` passes `null, null` (`mobilelm-litert/src/lib.rs:87`) |
| set an audio backend | same, `audioBackend` | same signature | `null` |
| per-turn temperature | `_ensureLiteRtConversation` | `litert_lm_sampler_params_create` / `_set_top_k` / `_set_top_p` / `_set_temperature` — `engine.h:155–180` | not bound |
| send an image | `LiteLmContent.imageFile` → `Content.ImageFile` | `message_json` with `content: [{"type":"image",…}]` — confirmed in `runtime/conversation/model_data_processor/multimodal_processor_helper.cc:64` | not bound; `send_once(&str)` only |
| send audio | `LiteLmContent.audioFile` | same, `{"type":"audio",…}` — same file, line 66 | not bound |
| count tokens | `countTokens` on the plugin channel | `litert_lm_session_get_*` family | not bound |

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

## Gap 5 — the ladder would exist in two places

`lib/services/acceleration.dart:79` holds `planLiteRtTier`, and
`mobilelm_core::probe` holds the Rust answer. They will disagree the first time
one changes. The core's own rule is explicit — *"Accelerator decisions live in
`mobilelm-core::probe`, never in the UI"* — and the moment there is a Rust
engine, the Dart copy is the one that has to go, or it becomes the one that is
consulted. `settings_view.dart` also calls `NpuStatus.probe()` from the plugin,
which is a third answer to the same question.

Decide this before the FFI layer, because the answer changes what the FFI
exposes: a `probe()` that returns the resolved tier, or a `plan()` that takes the
user's mode and returns one. The second is what the app needs; the first is what
the core has.

One honest limit to carry into the UI: `LoadReport.actual` is set to
`cfg.backend` with a comment saying LiteRT-LM does not report which backend it
settled on. The device run contradicts that being knowable — LiteRT's own
registry logged `RegisterAccelerator: name=CpuAccelerator` after failing the
NPU, while CPU was requested, so in that run they agreed; nothing guarantees
they always will. Whatever the FFI returns, the app must not display `actual` as
an observation.

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
