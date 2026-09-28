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

### The prefill column was wrong, and the fix is a switch

The Milestone 1 table above records prefill as "not measured — the C API reports
no prompt timing". **It does report it.** The claim was wrong in the easiest way
possible: nobody looked, and a field that was never filled in got an explanation.

The C API has a benchmark family:

- `litert_lm_engine_settings_enable_benchmark` — the switch, on the engine
  settings, and it is **off by default**
- `litert_lm_conversation_get_benchmark_info` — per conversation, and it works on
  the conversation path this app uses, not only on the session path
- `litert_lm_benchmark_info_get_time_to_first_token`
- `litert_lm_benchmark_info_get_prefill_token_count_at` / `_decode_token_count_at`
- `litert_lm_benchmark_info_get_prefill_tokens_per_sec_at` /
  `_decode_tokens_per_sec_at`

All six are bound in `ApiExt` and `LiteRt::load_with` now turns the switch on, so
`LiteRt::benchmark()` returns a populated `Bench`. The prefill number the matrix
has been asking for is obtainable.

Two things about the number when it lands:

- **It is the engine's, not the harness's.** The 3.54 tok/s above and the 2,716 ms
  TTFT came from `Instant` around a channel that also carries the JSON unwrap.
  The benchmark family reports what the engine did. Both are worth having; they
  are not the same measurement and should not be put in the same column.
- **Index 0 means the first turn of the conversation.** A per-turn read needs an
  index, and the harness runs one turn, so 0 is the turn. A multi-turn
  conversation needs this indexed properly before its numbers mean anything.

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
| prefill | not measured — see the correction below |
| peak RSS | 1,857,948 KiB (1.77 GiB) |
| resolved backend | `cpu` (requested `cpu`) |
| runtime | `liblitert-lm.so` **v0.16.0** (the only release shipping `litert_lm_c_api-0.1.0.zip`), dlopen, 9/9 C API symbols |

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
chunk". On the runtime we ship it returns the **serialised message**:

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

## In the app, on the device: Kotlin baseline vs Rust core

Appended 2026-09-27. The run above is the `mobilelm-bench` CLI; this is the app
loading the same model through the two paths, in one APK, switch in Settings →
text generation → **Rust engine core**.

**Device** Motorola Edge 60, Dimensity 7300. **Model** Qwen3-0.6B.litertlm,
614,236,160 bytes, no quantisation column because `.litertlm` is a compiled
bundle rather than a GGUF. **Context** 4096. **Mode** `cpu_safe`, which resolved
to `cpu` on both sides. **Prompt** `Explain in one sentence what is a token.` —
ASCII, identical on both runs, so the same bytes reach the chat template.

| | Kotlin plugin (baseline) | Rust core |
|---|---|---|
| transport | `MethodChannel` → `LiteLmEngine` (JNI) | `dart:ffi` → `libmobilelm_core.so` → LiteRT-LM C API |
| load | `loaded with CPU backend, ctx=4096` | `Rust load report: actual: cpu, fallbackReason: null` |
| fell back to the other path | n/a | **no** |
| TTFT | 11.05 s | not yet measured |
| decode | 3.1 tok/s | not yet measured |
| tokens | 139 | not yet measured |
| total | 55.9 s | not yet measured |
| peak RSS, model loaded, idle | not captured | 1,836,835 KB (1.75 GiB) |

The baseline's own log lines, so the app's numbers can be checked against the
log rather than trusted: `sendMessage` 18:01:37.523, `FIRST TOKEN` 18:01:50.051,
`stream done - 139 chunks` 18:02:34.914. The app's 11.05 s TTFT is measured from
slightly later than `sendMessage`; 139 tokens over the 44.86 s between first token
and last chunk is the 3.1 tok/s, so the app excludes TTFT from the rate exactly as
the Rust `GenOutcome::decode_tps` does — the two columns are comparable.

**1.75 GiB for the Rust path matches the CLI's 1.77 GiB** for the same model,
which is the useful cross-check: the app's engine, the harness's engine and the
runtime underneath are the same weights, and the FFI boundary is not holding a
second copy of anything. The transitional APK does carry *both* runtimes
(`liblitertlm_jni.so` 21,802,952 B and `liblitert-lm.so` 38,969,320 B — the same
library, two ABIs), but only one engine is ever instantiated, so the RAM
concern that motivated measuring it does not materialise. Native heap 1,207,596 KB
of the 1,836,835 KB total.

`loadMs: 0` in the load report is the engine's own figure and it is zero because
`litert_lm_engine_settings_enable_benchmark` covers per-turn timing, not engine
construction. Wall clock for the load was 2.38 s (18:41:32.465 → 18:41:34.845).
The report's `capabilities: 0` is correct for this model: text-only, no vision or
audio bit set.

### Two device bugs, and why the additive wiring is what made them findable

Both cost a 22-minute CI build to fix, and both had the same shape: the Rust path
did its work correctly and never told the rest of the app.

1. **`load` was never dispatched.** The isolate creates the engine inside its
   `case 'load':`, and nothing ever sent that command — the boot map sat holding
   the parameters for a call that was not made. Every later call then failed on a
   null handle, three calls from the cause. The device said
   `engine handle is null (in mobilelm_engine_load_report)`.
2. **`_isLiteRt` was never set.** The load returned a success `LoadResult`, the
   header showed the model, RSS was the model's weights — and the first message
   threw `Exception: No model loaded`, because `generate` routes on that flag,
   fell past the LiteRT branch, and hit the llama branch's guard on `_controller`,
   which is null here *by design*. The message named a symptom three
   indirections from its cause.

The fallback is why these were bugs and not outages: on both, the Kotlin plugin
took over and generated normally (139 and 254 chunks). Had this been a
replacement rather than an addition, the first one would have been an app with no
LiteRT-LM at all, found on a phone rather than in a log.

### Not yet proven, and the one that decides whether the plugin can go

The Rust load has **no retry ladder**. The Kotlin load has three attempts —
full, then without the audio encoder, then text-only on a vision signature
mismatch — and a specific message for a text-only file loaded as vision. The Rust
path attempts once, and on any error it *declines*, so the plugin loads the model.

So the Rust path serves text-only LiteRT-LM today. A multimodal model is a
decline, not a failure — which is safe, and means the gemma-4 E2B run will show
the fallback working rather than Rust working. Deleting the plugin before that
retry ladder exists would delete gemma-4 E2B and E4B from the catalogue. See
Gap 6 in [APK.md](APK.md).

## A sampler type is a capability, not a preference

The fifth device run got further than the four before it, because the
instrumentation from the fourth finally answered its question, and the answer was
not the one the log was shaped around:

```
[LiteRt] sendStream fn=Pointer: address=0x6be6b00090 maxTokens=2048 jsonBytes=91
[LiteRt] sendStream rc=-1
[Inference] Rust turn failed: mobilelm_core: runtime:
    UNIMPLEMENTED: Sampler type: 1 not implemented yet. (in mobilelm_send_stream)
```

`fn=` is a real address, so the callback pointer was never the problem and the
`nullptr` theory was wrong. What failed is one line of policy: the code asked for
`kLiteRtLmSamplerTypeTopK` and the v0.16.0 runtime does not implement it.

**TopK is the type the app's own plugin requests** — `topK: 64, topP: 0.95,
temperature from the slider` — and it was being passed as a constant. A runtime
that does not implement a sampler type answers `UNIMPLEMENTED` **on the first
turn of the conversation, after the model has been built**, not at load. So the
turn died with a runtime error about a setting, having produced no token.

| | |
|---|---|
| where it surfaced | the turn, ~3 s in, after prefill and decode were built |
| what it cost | five device runs, four of them chasing a null function pointer |
| what was actually wrong | a hardcoded enum value treated as universal |

Two things worth writing down because both were believed and neither was true:
the callback pointer arrives fine, and `-999` never meant anything beyond
"`nativeStatus` was not assigned".

### The fix, and the part that is not a fix

`sampler_params` now probes — requested type first, then the others, and takes
the first the runtime accepts — and **no outcome of the probe can fail a turn**.
A runtime that implements none of the three gets the engine's own default, which
is a working sampler, and the substitution is reported by a fifteenth ABI entry
point, `mobilelm_sampler_report`, rather than absorbed.

Greedy is the one request that does not fall back, and the reason is the point:
substituting top-k for greedy would not honour the request more precisely, it
would change it. A non-greedy request does fall back, TopK → TopP → Greedy,
because all three are constrained sampling and the default is narrower than any.

### The gap this opens between the two paths

Not fixed, and it decides something: **on the Rust path the temperature slider may
be inert, and the app has no way to know which it is.** The Kotlin plugin's
`samplerConfig` goes through the AAR's own JNI, which is a different route to the
same engine and evidently reaches a sampler. The C API route is the one that
just learned it may not get one at all.

So the comparison is not only speed. It is that the Kotlin path can be shown to
honour the setting and the Rust path has to be asked. `mobilelm_sampler_report`
is that answer, and `APK.md` Gap 9 tracks closing it before the plugin goes.
