# Origin

This directory was a standalone repository, `dollarbr/mobileLM-rs`, and was folded
into `mobileLM-app` on 2026-09-27. That repo has been deleted; this file is the
only remaining trace of its commit-by-commit history, so the *why* behind the
current state is not lost with it.

The fold was a squash. Rewriting thirteen commits into one is right here — every one
of them is a fix to a file that no longer exists at that path (the standalone
`.github/workflows/ci.yml` is now the job in this repo's own workflow), and a
linear history of "fix(ci): install the NDK with sdkmanager" sitting in a
Flutter app's log is worse than a summary. The reasoning those commits
accumulated is in [BENCH.md](BENCH.md) and [ARTIFACT.md](ARTIFACT.md), which is
where it belongs.

## What the standalone repo was for

The question it answered: *is a Rust engine core worth anything here, or is the
rewrite a fantasy?* The engine is C++ and stays C++, so a rewrite buys no speed
— 1B Q4_0 does 21.2 tok/s prefill on CPU against Vulkan's 3.4. What it buys is
reach: LiteRT-LM's **C API** is plain C, and Kotlin cannot `dlopen` it, so
today the only route from Dart to that engine is a hand-written Kotlin plugin.
Rust can call it directly. That is the whole argument, and it is now answered
empirically: the engine generates on the Edge 60.

## The commits, in order

| SHA | What it fixed |
|---|---|
| `3f7c786` | feat: bootstrap mobileLM-rs — Rust rewrite, milestone 0 (device probe) |
| `06a65f6` | fix(ci): give setup-ndk the versionSpec it requires |
| `755762e` | fix(ci): the setup-ndk input is `ndk-version`, not `versionSpec` |
| `57e2265` | fix(ci): install the NDK with sdkmanager, not nttld/setup-ndk |
| `f22b45d` | fix(ci): use the runner image's own NDK instead of installing one |
| `0e60d42` | fix(ci): find the cross-compiled binary instead of guessing its path |
| `d443711` | docs: record the CI traps that cost four runs |
| `c114fe5` | feat(scripts): one command for the milestone-0 device run |
| `69cc760` | fix(probe): report real CPU topology, and stop mangling /proc and JSON |
| `2348c71` | docs(bench): record the milestone-0 device run |
| `f633b2b` | feat(litert): drive LiteRT-LM from Rust through its C API, and bench it |
| `1fd253a` | fix(litert): the stream delivered JSON, not text -- found by running it |
| `3c3f219` | fix(ci): check DT_NEEDED with readelf, not ldd |

The four NDK commits and the two later CI commits are six red runs in a row, all
in the first hour. They are worth keeping in mind before writing any CI here:
`nttld/setup-ndk` 404s on the image, `sdkmanager` is not on `PATH`, the image
ships two NDKs, and `file` exits 0 on a missing path.

## Versions

`3f7c786` was the last commit tagged or released anywhere; there was never a
release from this repo. Its 0.4.0 framing was deliberately *not* used, because
`mobileLM-app` is public and the core adds no user-visible feature — which is
also why landing it here, as a library the app does not yet call, is the safe
half of the plan.
