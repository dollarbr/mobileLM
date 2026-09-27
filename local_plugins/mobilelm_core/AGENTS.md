# mobilelm_core — Agent Guide

The Rust engine core. Read [`../../AGENTS.md`](../../AGENTS.md) first: it holds
the device knowledge, the engine traps and the MediaTek NPU ground truth this
inherits. This file only covers what is different here.

It was a standalone repository (`dollarbr/mobileLM-rs`) until 2026-09-27 and was
folded in. [`docs/ORIGIN.md`](docs/ORIGIN.md) has the reasoning for the fold and
the commit trail it replaced; the workspace guide has the short version.

## What it is, and what it is not

**Not in any APK.** Nothing in `lib/` imports this, Gradle does not build it, and
the app's behaviour is identical with or without it. It is a library plus a
headless harness, gated in CI, and the wiring is separate work. Do not describe
it as shipped.

**Not faster.** The engine is C++ and stays C++. A 1B Q4_0 does 21.2 tok/s
prefill on CPU against Vulkan's 3.4 on this phone, and no amount of Rust in the
core changes that. What Rust buys is *reach*: LiteRT-LM's C API is plain C, and
Kotlin cannot `dlopen` it, so today the only route from Dart to that engine is a
hand-written Kotlin plugin. Rust calls it directly. That is the whole argument,
and `docs/BENCH.md` has the run that proves it generates.

- **C++ stays.** llama.cpp and stable-diffusion.cpp are vendored and linked.
  "100% Rust" means our code, not the inference engine — rewriting it would
  discard the Android Vulkan dispatcher fix, the HWCAP CPU variant dispatch, the
  `devices={nullptr}` fix and the `mtmd` pipeline.
- **LiteRT-LM goes through its C API**, not the AAR's JNI. The AAR ships
  `liblitertlm_jni.so` with JNI exports only; the C API prebuilt
  (`litert_lm_c_api-0.1.0.zip`, LiteRT-LM v0.16+) ships
  `lib/android_arm64/liblitert-lm.so` with 144 `litert_lm_*` exports including
  `litert_lm_engine_settings_set_litert_dispatch_lib_dir`. Fetch it with
  `scripts/fetch-litert-capi.sh`; never commit a binary.
- **No binary in git.** Models, `.so` prebuilts and build trees are gitignored.
- **Zero dependencies**, not even `serde_json`. A build-time dependency is one
  more thing that can break on a bare `adb shell`.

## Commands

All from this directory, or with `--manifest-path local_plugins/mobilelm_core/Cargo.toml`.

```sh
cargo test                              # 41 tests, no network, no toolchain beyond host
cargo clippy --all-targets              # must be silent
cargo fmt --check
cargo run -p mobilelm-bench -- --probe  # works on the host today

scripts/run-on-device.sh --check         # device prerequisites, no phone needed
scripts/run-on-device.sh                # push + probe, needs a connected device
```

Android target: `rustup target add aarch64-linux-android`, then
`cargo ndk -t arm64-v8a build --release -p mobilelm-bench` — **in CI only**. This
host is aarch64 and the NDK's own `clang`/`glslc` are x86-64 ELF binaries, so they
cannot run here; Google ships no `linux-aarch64` NDK host. Do not try to make it
work locally, and do not add a Docker/qemu workaround to the docs as if it were
the plan. The same is true of the Flutter build, which is why every APK comes
from CI.

`--probe` deliberately exits non-zero when a library it was told to check failed
to load: a caller scripting it wants a signal, and a probe that always exits 0 is
a probe nobody reads.

**Device runs go through `scripts/run-on-device.sh`**, never through adb commands
typed by hand. It is the only place that knows the binary comes from a CI
artifact, that the push target is `/data/local/tmp/mobilelm-rs`, and what the two
possible `loaded:false` reasons mean.

### CI (`rust-core` and `rust-core-android`, in the root `ci.yml`)

Two jobs, split because they are different toolchains: a Dart lint failure and a
missing aarch64 std have nothing to do with each other, and lumping them in hides
which is broken. The arm64 job cross-compiles and asserts the engine stayed a
runtime dependency. It does **not** run the engine — qemu-user cannot execute an
Android binary at all, and the reasoning is in
[`docs/ARTIFACT.md`](docs/ARTIFACT.md).

Six traps, each of which cost a red run. The workflow comments carry the detail:

- **The runner image ships two NDKs** (27.x and 29.x) and exports
  `ANDROID_NDK_ROOT` for one. Globbing picks the other and cargo-ndk warns that
  the variables disagree. Trust the exported root; write both names from it.
- **Do not install an NDK.** `nttld/setup-ndk@v1` builds the download URL from
  the numeric version, but Google names the archive by letter revision
  (`28.2.13676358` ships as `android-ndk-r28c-linux.zip`) → 404 on a perfectly
  valid version. `sdkmanager` resolves that mapping but is not on PATH on this
  image. Use the NDK that is already there.
- **`file` on a missing path exits 0** on this image. A hardcoded artifact path
  therefore turns a wrong guess into a green step and a missing upload. The step
  finds the binary with `find` and asserts it exists.
- **`qemu-aarch64-static` cannot run an Android binary.** It emulates the CPU,
  not libc, and the binary hardcodes `/system/bin/linker64` as its interpreter.
  Making it work needs an extracted Android rootfs — a ~1 GB download to re-measure
  what `adb shell` answers exactly. Do not spend a day rediscovering this.
- **`ldd` is useless on a foreign-architecture binary.** It executes the target's
  interpreter, so on the x86-64 runner it runs the x86-64 loader against an
  aarch64 binary: exit 1, no output, indistinguishable from a real finding. Use
  `readelf -d` and read `DT_NEEDED`, which is a table read.
- **A heredoc cannot live inside a YAML block scalar.** The body has to be
  unindented, which is not YAML. Keep that prose in `docs/` and `cat` it.
- cargo-ndk's output layout is `target/<triple>/release/`, with no per-ABI
  directory. Do not reintroduce a path by hand.

The NDK version is the image's, not the `28.2.13676358` that Flutter pins. That
is fine while nothing is linked and stops being fine the first time an engine is
in this build — pin it then.

## Rules the code enforces

- **Report the backend that ran, never the one requested.** `Engine::backend()`
  and `LoadReport::actual` exist for this; a fallback carries a
  `fallback_reason`. There is no constructor that lets them disagree silently.
- **The engine is `dlopen`ed, never linked.** Linking `liblitert-lm.so` (39 MB,
  aarch64) would mean `cargo test` cannot run on a laptop, and an app would die at
  startup on a device without the runtime instead of reporting that it is
  missing. CI asserts it with `readelf -d`.
- **`Backend`'s `Ord` is hand-written** so `Npu < GpuVulkan < Gpu < Cpu`. A
  derived `Ord` orders by declaration and silently reverses the fallback chain —
  this exact bug was introduced once and caught by
  `ladder_starts_at_npu_and_ends_at_cpu`. Do not "simplify" it back.
- **Accelerator decisions live in `mobilelm-core::probe`**, never in the UI. No
  SoC-name inference, no brand allowlist; memory decides.
- **Engine is `Send`, not `Sync`.** No engine here is safe for concurrent calls,
  and the LiteRT-LM C API in particular will corrupt state if you pretend
  otherwise.
- **`/proc` values are right-aligned under a tab.** Parse through
  `parse_kib_after_prefix`, which trims first. Skipping the trim yields `None`,
  which is indistinguishable from "this device reports nothing".
- **The probe never `dlclose`s.** Unloading a 39 MB runtime while a model handle
  is alive is a use-after-free.
- **A stream chunk is not a token.** `litert_lm_stream_chunk_get_text` is
  documented as returning the chunk's text; 0.17.1 returns the *serialised
  message*, one JSON envelope per token. `mobilelm_core::json::extract_content_text`
  is what unwraps it, and its test fixtures are literal device output. A mock
  built from the header's promise tests the promise — 34 host tests passed while
  the phone printed JSON at the user.

## Testing

`cargo test` is host-only and dependency-free on purpose: it has to stay fast
enough to run on every save. Device behaviour is verified by `--probe` and
`--bench`. A change that cannot be tested on the host needs a test that at least
pins the pure logic (parsing, ranking, formatting) and leaves the device part to
the harness.

When a device run produces a number worth keeping, put it in
[`docs/BENCH.md`](docs/BENCH.md) with the model, the quant, the context and the
backend that actually ran. A throughput figure without those four is not a
measurement. Never overwrite a number — append.
