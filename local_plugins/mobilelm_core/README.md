# mobilelm_core

The Rust engine core for **mobileLM**. A local-first AI assistant on your phone:
the engine is C++ and stays C++, and this is the layer around it.

> **Not used by any APK yet.** The cdylib and the Dart bindings exist and build in
> CI, but `inference_android.dart` is untouched: the app still reaches LiteRT-LM
> through the Kotlin plugin and behaves exactly as it did before this crate
> existed. What remains is the device run that compares the two paths, and then
> deleting the plugin. [`docs/APK.md`](docs/APK.md) has the plan and what is done
> in it; [`AGENTS.md`](AGENTS.md) for what "not shipped" means precisely.

It was a standalone repository (`dollarbr/mobileLM-rs`) until 2026-09-27.
[`docs/ORIGIN.md`](docs/ORIGIN.md) has why, and the commit trail the fold
replaced.

## What is honest about "100% Rust"

The **engine is C++ and stays C++**. llama.cpp and stable-diffusion.cpp are
vendored, patched and tuned; rewriting them would throw away the Android Vulkan
dispatcher fix, the per-ISA CPU variant dispatch, the empty-device-list fix, and
the multimodal `mtmd` pipeline — all paid for in device measurements. What would
be Rust is *our* code: the core, the agent loop, the tools, the persistence, the
probe.

What Rust buys today is not speed. It is **reach**: LiteRT-LM's C API
(`litert_lm_*`, 144 exported symbols) is plain C, and Kotlin cannot `dlopen` it,
so the only route from Dart to that engine is a hand-written Kotlin plugin. Rust
calls it directly, and the run in [`docs/BENCH.md`](docs/BENCH.md) shows it
generating on the target hardware.

## Where it stands

| | |
|---|---|
| Device probe | working — CPU topology, RAM, dlopen of the C API, NPU library visibility |
| LiteRT-LM C API | **generating** — Qwen3-0.6B on an Edge 60, load 2.45 s, TTFT 2.72 s, 3.54 tok/s, backend `cpu` |
| Prefill timing | available and now switched on — `BENCH.md` said the C API could not report it, which was wrong |
| Vision and audio | the encoder backends are bound; **not yet run on a device** |
| NPU | unreachable on this device, from any language. LiteRT's own registry reaches the same verdict at runtime |
| `libmobilelm_core.so` | builds for arm64 in CI (~1m11s), 15 entry points, `dlopen`s the engine |
| Dart bindings | written, 12 tests, no device needed |
| Used by the app | **not yet** — `inference_android.dart` is untouched |

3.54 tok/s is a first number, not a result: a 0.6B float model on CPU with no
thread count and no accelerator hint. Read it as headroom, not as a verdict.

## Layout

| Path | What |
|---|---|
| `crates/mobilelm-core/` | `Backend`, the `Engine` trait, `LoadReport`, `dynlib`, `json`, and the device probe. No dependencies, on purpose. |
| `crates/mobilelm-litert/` | The LiteRT-LM C API, hand-written against the official headers. |
| `crates/mobilelm-ffi/` | The cdylib: `extern "C"` over the two crates above, for `dart:ffi`. Thin on purpose — everything testable lives below it. |
| `crates/mobilelm-bench/` | Headless CLI: `--probe` for the device, `--bench` for a generation. |
| `docs/BENCH.md` | The measurement matrix, the numbers, and the traps each one cost. |
| `docs/APK.md` | The plan for putting this in the app, and what blocks it. |
| `docs/ARTIFACT.md` | How to run the arm64 binary, and why CI cannot. |
| `scripts/` | Fetches the prebuilts. Nothing binary is committed. |

## Quick start

```sh
# everything a host can check, in about a second
cargo test
cargo clippy --all-targets

# the library the APK ships, for the host
cargo build -p mobilelm-ffi

# device prerequisites, no phone needed
scripts/run-on-device.sh --check

# with the phone connected: probe, then generate
scripts/run-on-device.sh
scripts/run-on-device.sh --bench
```

## Building for Android

Two things this machine does not have, both checked in CI rather than fought with
locally:

1. `rustup target add aarch64-linux-android` — the std for the target. Arch's
   `rust` package ships host std only.
2. An NDK whose **host tools are x86_64**. `/opt/android-sdk/ndk/28.2.13676358`
   is on disk, but its `clang` and `glslc` are x86-64 ELF binaries and this is an
   aarch64 host, so they cannot execute. Google publishes no `linux-aarch64` NDK
   host at all.

Type-checking for Android works locally once (1) is done; producing the binary
needs CI.

## License

MIT, matching mobileLM. Vendored C++ keeps its own upstream licenses.
