# mobilelm_core

The Rust engine core for **mobileLM**. A local-first AI assistant on your phone:
the engine is C++ and stays C++, and this is the layer around it.

> **Not in any APK yet.** Nothing in `lib/` imports this, Gradle does not build
> it, and the app behaves identically with or without it. It is a library and a
> headless harness, both gated in CI. The wiring is separate work — see
> [`AGENTS.md`](AGENTS.md) for what "not shipped" means precisely.

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
| NPU | unreachable on this device, from any language. LiteRT's own registry reaches the same verdict at runtime |
| Wired into the app | not yet |

3.54 tok/s is a first number, not a result: a 0.6B float model on CPU with no
thread count and no accelerator hint. Read it as headroom, not as a verdict.

## Layout

| Path | What |
|---|---|
| `crates/mobilelm-core/` | `Backend`, the `Engine` trait, `LoadReport`, `dynlib`, `json`, and the device probe. No dependencies, on purpose. |
| `crates/mobilelm-litert/` | The LiteRT-LM C API, hand-written against the official headers. |
| `crates/mobilelm-bench/` | Headless CLI: `--probe` for the device, `--bench` for a generation. |
| `docs/BENCH.md` | The measurement matrix, the numbers, and the traps each one cost. |
| `docs/ARTIFACT.md` | How to run the arm64 binary, and why CI cannot. |
| `scripts/` | Fetches the prebuilts. Nothing binary is committed. |

## Quick start

```sh
# everything a host can check, in about a second
cargo test
cargo clippy --all-targets

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
