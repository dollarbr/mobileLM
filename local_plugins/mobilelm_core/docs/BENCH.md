# Benchmark matrix

Every number in this file must carry: **model + quant + context + the backend that
actually ran**. A tok/s figure without those four is an anecdote.

## The bar: numbers the rewrite has to reproduce or beat

Measured on the target device (Motorola Edge 60, Dimensity 7300 / MT6878, Mali-G615
MC2, 8 GB) and recorded in `../mobileLM/AGENTS.md` and
`../mobileLM/.claude/memory.md`. The point of listing them here is that a Rust
rewrite which is *slower* than the Dart app has failed, regardless of how clean
the code is.

| Arm | What it is | Baseline to beat |
|---|---|---|
| **A** | llama.cpp, vendored+patched, CPU variant picked by HWCAP | 1B Q4_0: **21.2 tok/s** prefill-equivalent, 1B Q4_0 decode on 4 threads. Threads: **4 optimal, 8 regresses** (A55 contention starves the A78s). |
| **B** | llama.cpp, Vulkan | 1B Q4_0: **3.4 tok/s** — roughly **6x worse than CPU** for small models; shader/dispatch overhead dominates ≤2B. Only wins on large models. |
| **C** | LiteRT-LM C API, CPU | ctx clamped to **4096** by its own driver regardless of what is asked. |
| **D** | LiteRT-LM C API, GPU (OpenCL/GLES) | — (no C-API measurement exists yet; the JNI path was never benchmarked either) |
| **E** | LiteRT-LM C API, NPU via dispatch dir | **Expected to fail on this phone.** Verified: the dispatch dlopens a bare `libneuron_adapter.so` (absent) and `libneuron_adapter_mgvi.so` (present in `/vendor/lib64` but in no `public.libraries*.txt`, so the linker namespace blocks it). Record the failure, do not spend a week on it. |
| **F** | **candle**, pure-Rust GGUF, CPU | No baseline. This arm exists to answer "what does giving up C++ actually cost?", so it needs a number. Expect it to lose to A; the number is the deliverable, not the win. |

Two traps that make these numbers lie if you are careless:

- **Vulkan `llama_decode` returns at submit.** Without `llama_synchronize` the
  cost stays hidden until the first `llama_sampler_sample`, and a "GPU is faster"
  result appears out of nowhere. Sync before you time.
- **Prefill and decode must be reported separately.** They behave differently
  enough on a phone that averaging them hides which one regressed.
  `GenOutcome::prefill_tps` / `decode_tps` do this, and `decode_tps` deliberately
  excludes TTFT.

Also log **peak RSS** (`VmHWM`, already in the probe). A faster engine that eats
twice the RAM is not a win on an 8 GB phone with a 2.5 GB interactive-class
budget, and tok/s alone cannot tell the two apart.

## Milestone 0 — the probe, before any engine

Two unknowns decide whether this rewrite is viable, and neither needs a model, an
APK or a UI:

1. **Does `liblitert-lm.so` (android_arm64) load on Bionic and do its 144
   `litert_lm_*` symbols resolve?** The AAR's JNI wrapper proves nothing about the
   C API. `mobilelm-bench --probe --litertlm <path>` answers it, and reports the
   loader's own error text — which is the only thing that separates "file not
   found" from "found, but the linker namespace forbids it".
2. **What does the CPU report, and which NPU libraries are visible?**
   `/proc/cpuinfo` `Features` and the `libLiteRtDispatch*` / `libneuron*` scan.

```sh
scripts/fetch-litert-capi.sh     # C API -> vendor/prebuilt/ (gitignored)
scripts/run-on-device.sh         # push + probe, needs a connected device
```

`run-on-device.sh` does the whole thing: it fetches the arm64 probe binary from
the CI artifact, verifies both binaries are aarch64, pushes them, and prints the
device baseline followed by the C API load test. `--check` runs every check that
does not need the phone, so a broken prerequisite is discovered before you go
looking for the cable.

## Milestone 1 — one real generation per arm

Per arm: model load wall time, TTFT, prefill tok/s, decode tok/s, peak RSS,
`.so` size, and the resolved backend. Then the two comparisons that matter:

- **A vs B** (does the ladder's CPU-over-GPU conclusion hold for the Rust build?)
- **A vs F** (what does pure Rust cost?)

## What gets carried over from the Flutter app, verbatim

Not "reimplemented later" — these are known-correct behaviours with a reason
attached, listed in `../mobileLM/AGENTS.md`:

- `n_gpu_layers == 0` must set an **empty device list**, not just skip offload
  (ggml sched otherwise sends ops to Vulkan when batch > 32; prefill 12.1 s → 3.6 s).
- The prompt must not get a **second BOS** when it already opens with one.
- ggml log strings must be **sanitized before `NewStringUTF`**, or CheckJNI aborts
  a debuggable build on a truncated multibyte tail.
- **4 threads**, not 8, on this SoC.
- A **16 KB page-size** linker flag is required for Android 15.
- Accelerator choice is a **service decision**, never a UI one.

## Results

### Milestone 0 — device probe, Edge 60 (2026-09-27)

Run via `scripts/run-on-device.sh` over wireless adb. Device: MT6878, Android,
12 GB class.

```
cpu      : implementer 0x41, part 0xd05, 8 cores -> "4x Cortex-A55 + 4x Cortex-A78"
features : fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp
           cpuid asimdrdm lrcpc dcpop asimddp
mem      : 11_694_264 KiB total
peak RSS : 4_192 KiB baseline -> 48_928 KiB with the 39 MB C API mapped
C API    : loaded=true, 9/9 symbols resolved
```

Two things this settles:

- **The LiteRT-LM C API works on the device.** `lib/android_arm64/liblitert-lm.so`
  (38.9 MB) dlopens on Bionic and every symbol we need resolves. Bindgen is
  unblocked, the `.litertlm` catalogue is reachable, and so is
  `litert_lm_engine_settings_set_litert_dispatch_lib_dir`. No Kotlin, no JNI, no
  Bazel build of the runtime.
- **The CPU variant choice is confirmed independently.** `atomics` + `fphp` +
  `asimdhp` + `asimddp` and **no `i8mm`, no `sme`** — the same feature set that
  makes the Flutter app's ladder pick the dotprod+fp16 variant on this SoC, and
  the same reason 8 threads regress. The decode of 0xd05/0xd41 to A55/A78 is
  pinned by a unit test, because getting it backwards produces a plausible-looking
  thread count that is wrong.

### Arm E — the NPU, on this device

`libneuron*` in `/vendor/lib64` (found by the probe with `--npu-dir /vendor/lib64`):

| Library | On disk | In `public.libraries*.txt` (what an app may link) |
|---|---|---|
| `libneuron_graph_delegate.mtk.so` | present, **not readable** even by `adb shell` | **yes** |
| `libneuron_runtime.so` | 1.65 MB, resolves | no |
| `libneuron_runtime.7.so` | 1.58 MB, resolves | no |
| `libneuron_platform.so` | 194 KB, resolves | no |
| `libneuron_adapter_mgvi.so` | symlink, target unresolvable | no |
| `libneuron_wrapper.so` | symlink, target unresolvable | no |

The NPU runtime is in the firmware. The set of sonames an app may actually load
is **empty**: the only exposed library does not resolve, and the ones that resolve
are not exposed. So `litert_lm_engine_settings_set_litert_dispatch_lib_dir` is a
dead end here, for the same reason it is dead from Kotlin — the blocker is the
OEM's linker namespace, not the language. Record the failure, do not spend a week
on it.

Caveat that matters: these are `adb shell` observations, and the shell user is not
an app. "The shell can read it" does not mean an app can load it. The exposed set
in `public.libraries*.txt` is the ceiling for an app, which is why the table
crosses the two rather than trusting either alone.

### Arms A–D, F — pending

Nothing measured yet. `docs/BENCH.md` keeps the targets at the top; append here
when they land, newest last, and never overwrite a number.

### Milestone 1 — LiteRT-LM, CPU, Edge 60 (2026-09-27)

Qwen3-0.6B (`.litertlm`, 614,236,160 bytes), one turn of 48 tokens, Portuguese
prompt, `mobilelm-bench --bench --backend cpu`.

| | |
|---|---|
| load | 2,453 ms |
| TTFT | 2,716 ms |
| total | 63,499 ms |
| chunks | 215 |
| decode | **3.54 tok/s** |
| prefill | not measured — the C API reports no prompt timing, so the field stays 0 rather than being guessed |
| peak RSS | 1,857,948 KiB (1.77 GiB) |
| resolved backend | `cpu` (requested `cpu`) |
| runtime | `liblitert-lm.so` 0.17.1, dlopen, 9/9 C API symbols |

The model answered, in Portuguese, in one sentence as asked: *"Um token é uma
parte de um texto ou conjunto de dados separada por espaços, palavras ou outros
elementos como em uma frase ou um conjunto de dados."* 215 chunks for 48
requested tokens — the engine streams by graph step, not by token, so `chunks`
and `decode_tokens` are the same number and neither is the model's token count.

The NPU line in the load log is worth reading rather than skipping:

```
WARNING: [npu_registry.cc:34] NPU accelerator could not be loaded and registered
INFO: RegisterAccelerator: name=LiteRT GPU
INFO: RegisterAccelerator: name=CpuAccelerator
```

LiteRT's own registry tries the NPU first, fails, and lands on CPU. That is the
same verdict `Arm E` reached from the outside by reading
`public.libraries*.txt` — reached here by the engine's own attempt, which is the
stronger form of the evidence.

XNNPACK partitions the model into 57 (prefill) and 58 (decode) graphs. Peak RSS
of 1.77 GiB for a 0.6B model is the weight file mapped plus XNNPACK's arena; the
`.litertlm` is float, not quantised, which is most of the difference.

**3.54 tok/s is not a result to keep.** It is a 0.6B float model on CPU with no
thread count, no accelerator hint and no quantisation. It is recorded because it
is the first real number, and because the honest reading is that LiteRT-LM on this
phone has a lot of headroom — not that it is fast. Compare against arm A (llama.cpp
Q4_0, 21.2 tok/s prefill on CPU) only once both are measured the same way.

### The bug the phone found that 34 tests did not

`litert_lm_stream_chunk_get_text` is documented as "Gets the text content of the
chunk". On 0.17.1 it returns the **serialised message**:

```json
{"role":"assistant","content":[{"type":"text","text":"<think>"}]}
```

One envelope per token. The first device run produced correct output wrapped in
215 JSON objects, which is why the tests could not have caught it: nothing in a
host test ever had a real chunk to hand.

The Flutter app's own Kotlin path is the reference for what to do about it —
`messageToMap` filters the message's contents for `Content.Text` and joins them.
There is no `Content.Text` in Rust, so `mobilelm_core::json::extract_content_text`
does that job, and its test fixtures are the literal strings the Edge 60 emitted.

Two CLI bugs surfaced in the same run, both from the same cause (the harness's
usage text and its parser were maintained by hand and had already drifted):
`--stream` was implemented but missing from the accepted-flag list, and the usage
line advertised `--bench <model>`, a positional the parser rejects. A test now
compares the two lists in both directions, and it immediately caught a third
thing — `--mmproj` was accepted and undocumented.

### Why CI cannot run this

`qemu-aarch64-static` fails with `Could not open '/system/bin/linker64'`. qemu
emulates the CPU, not the C library, and an Android binary hardcodes the Android
linker as its interpreter. Extracting an Android rootfs to work around it is
about a gigabyte of download to re-measure, under emulation, what `adb shell`
answers exactly. CI therefore gates the build; the device gates the engine. The
full reasoning is in [ARTIFACT.md](ARTIFACT.md).
