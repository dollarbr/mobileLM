# The `mobilelm-bench-arm64` artifact

An arm64 Android binary, plus the LiteRT-LM runtime it loads and the device
script. It exists because that binary cannot be built on an aarch64 Linux
laptop (the NDK ships x86-64 host tools) and cannot be *run* on an x86-64 CI
runner either — see "Why there is no generation job in CI" below.

## Probe

```sh
adb push dist /data/local/tmp/mobilelm-rs
adb shell 'chmod 755 /data/local/tmp/mobilelm-rs/mobilelm-bench'
adb shell 'cd /data/local/tmp/mobilelm-rs && LD_LIBRARY_PATH=$PWD ./mobilelm-bench --probe'
```

Prints the CPU topology and feature letters, total RAM, peak RSS, and whether
`liblitert-lm.so` dlopens with all nine C API symbols resolved. Exit 0 when every
requested library loaded.

## Generation

Needs a `.litertlm` alongside it. The smallest one in the catalogue is 586 MB,
which is why the model is not in the artifact:

```sh
curl -LO https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm
adb push Qwen3-0.6B.litertlm /data/local/tmp/mobilelm-rs/

adb shell 'cd /data/local/tmp/mobilelm-rs && LD_LIBRARY_PATH=$PWD \
  ./mobilelm-bench --bench --model Qwen3-0.6B.litertlm \
  --runtime ./liblitert-lm.so --stream --max-tokens 48 \
  --prompt "Explique em uma frase o que e um token."'
```

One JSON object per line: the device report, then `load`, then one `token` per
chunk, then `done` with TTFT, prefill and decode throughput, and peak RSS.

`scripts/run-on-device.sh` in this archive does all of the above; `--check`
validates the tree without a phone attached.

For the full flag list: `cargo run -p mobilelm-bench -- --help` on a host. It
cannot be captured into this README at build time — the binary is aarch64
Android and the runner is x86-64, so executing it there fails with
`exec format error`.

## Why there is no generation job in CI

The obvious thing to try is `qemu-aarch64-static` on the runner. It does not
work, and the error names nothing useful:

```
qemu-aarch64-static: Could not open '/system/bin/linker64': No such file or directory
```

qemu-user emulates the CPU, not the C library. An Android binary hardcodes
`/system/bin/linker64` as its interpreter, and that file lives in an Android
rootfs, not on the runner. The process dies before `main`.

Making it work means fetching an Android system image and extracting a rootfs
(Google's `android-emulator-container-images` script does this) — roughly a
gigabyte of download to re-answer, under emulation, a question that one
`adb shell` on the target hardware answers exactly. Emulated numbers would also
be actively misleading: XNNPACK picks different kernels per core, and there is no
GPU or NPU driver to fall back to.

So the split is deliberate: **CI proves the arm64 build, the device run proves
the engine.** The recorded results are in [BENCH.md](BENCH.md).

## The one thing CI does assert about the engine

`readelf -d` on the built binary must not list `liblitert` in `DT_NEEDED`. The
engine is `dlopen`ed at runtime, and that is what keeps `cargo test` runnable on
a laptop and lets an app report a missing runtime instead of dying at startup. A
stray `#[link]` would take that away while every test in the workspace still
passed.

`readelf`, not `ldd`: `ldd` executes the binary's interpreter, which on an x86-64
runner is the x86-64 loader pointed at an aarch64 Android binary. It exits 1
with no output — indistinguishable from a real finding, and it failed that way
once already. `DT_NEEDED` is a table read and does not care what the target is.
