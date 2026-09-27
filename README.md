# mobileLM

<p align="center">
  <img src="docs/brand/logo.svg" width="96" alt="mobileLM logo"/>
</p>

**A local-first AI agent that lives on your phone.** PrivateLM's on-device
engine with an agent body on top: native tools, multi-step tool chains, and daily
scheduled tasks that keep running with the app closed.

<p align="center">
  <img src="docs/screenshots/chat.png" width="250" alt="Chat"/>
  <img src="docs/screenshots/models.png" width="250" alt="Models"/>
  <img src="docs/screenshots/settings.png" width="250" alt="Settings"/>
</p>

## What it does

- **Local inference, no cloud required** — GGUF models on llama.cpp and
  `.litertlm` models on LiteRT-LM. The accelerator ladder (NPU → GPU → CPU)
  lives in the native layer and reports the backend that *actually ran*, not the
  one that was asked for. CPU variants are compiled per ARM feature set and
  picked at load time, so an old SoC gets a baseline build and a new one gets
  i8mm/SME without anyone picking a model.
- **Multimodal in the chat** — images, PDFs, office documents, audio (speech to
  text) and video (frames sampled into a contact sheet), through llama.cpp's
  `libmtmd` plus per-model projectors (`mmproj`).
- **24 built-in agent tools** — clock, calculator, device state, clipboard,
  haptics, share sheet, file management scoped to the active project
  (`list_files`, `read_file`, `create_file`, `write_file`, `delete_file`,
  `rename_file`), web tools (`web_search`, `read_url`) and task management
  (`schedule_task`, `list_scheduled_tasks`, `cancel_scheduled_task`).
  Anything that writes, sends or deletes stops and waits for a human tap.
  Tool chains are capped so a small model cannot spin forever.
  Eight more read-only system tools exist only when
  [Shizuku](https://shizuku.dev) is installed — no root, ever. See
  [docs/SHIZUKU.md](docs/SHIZUKU.md).
- **Workspace projects** — point the app at one folder on the device; every
  project is a subfolder inside it, and a chat binds to one project so the file
  tools cannot wander. New chats stay in the project you are already in, and the
  chip in the chat header is how you change or drop that binding. See
  [docs/WORKSPACE.md](docs/WORKSPACE.md).
- **Scheduled tasks** — a prompt bound to a model snapshot and a daily fire time.
  It runs in a foreground service with its own engine and an empty history, then
  posts the result as a notification and into the chat.
- **Image generation** — Stable Diffusion in a background isolate, CPU or GPU,
  with the quantisation selectable.
- **A local OpenAI-compatible server** on port 8080, so other apps on the same
  network can talk to the model running on your phone.
- **Thinking toggle** — `<think>` blocks parsed and rendered separately, with
  auto/on/off.
- **45 models in the catalogue**, 150 MB to 2.4 GB, 18 of them multimodal. Every
  entry is a direct link to a file whose size was checked before it was listed;
  nothing is proxied through a server of ours.
- **Cloud when you want it** — OpenRouter, DeepSeek, NVIDIA, Google, OpenAI,
  with context window and capabilities detected per model rather than configured
  by hand.

## Install

Download from [Releases](https://github.com/dollarbr/mobileLM/releases). One
file: `mobileLM-<version>-arm64-v8a.apk`.

**arm64-v8a only, and that is not going to change.** llama.cpp, LiteRT-LM and
Stable Diffusion are all vendored as arm64, and the native plugins pin
`abiFilters 'arm64-v8a'`. Every Android device shipped since 2017 is arm64, so a
32-bit APK would buy nobody anything and cost a second native build of the entire
engine. On a 32-bit device the app will not run — and the web build is not a
fallback: it has no local engine at all, only cloud providers.

Every push also produces a debug APK, available from the
[debug workflow's artifacts](https://github.com/dollarbr/mobileLM/actions/workflows/debug-apk.yml)
(signed in, so you must sign in to GitHub to download it).

### Before you install an update

Releases up to and including **0.3.3** were signed with the Android **debug
key**, which is public — anyone could produce an APK that updates over yours.
From **0.3.4** on, releases are signed with the project's own key.

That means 0.3.4 is the first release you *cannot* update over an earlier one.
Android refuses to replace an app with a differently-signed build, so you will
have to uninstall first — and that deletes your downloaded models, chat history
and workspace bindings. Export anything you care about from the app before you
do. After 0.3.4, updates are normal again.

Debug APKs from CI are still debug-signed. That is correct and intended: they
are not distributed, and they must be able to install over any build.

## Build from source

```sh
flutter pub get
flutter build apk --release --split-per-abi --target-platform android-arm64
```

`--target-platform android-arm64` is what makes the split produce exactly one
APK. Without it you get a single fat `app-release.apk`; with it and
`--split-per-abi` you get one file per ABI — which is one file.

Requirements: Flutter (stable), the Android SDK and NDK. Nothing else. The native
engines are vendored under `local_plugins/` and compiled by Gradle and CMake on
first build. Expect the first build to be slow and hungry: llama.cpp with its
Vulkan shader set, LiteRT and Stable Diffusion together will fill a 14 GB runner
and take the better part of half an hour on a machine that is not saturating its
cores.

**Release builds only work in CI, and that is deliberate.** `build.gradle.kts`
refuses a release build outside CI, and refuses one without a keystore — a
release APK is never debug-signed, not even by accident. To look at a local
artifact, build debug. See [Signing](#signing).

## Signing

| Build | Signed with |
|---|---|
| Release (CI) | the project's release key, from GitHub secrets |
| Release (local) | refused — the build fails, it does not downgrade |
| Debug | the Android debug key, as always |

The release keystore is never in the repository. `release.yml` materialises it
from the `RELEASE_KEYSTORE_BASE64`, `RELEASE_STORE_PASSWORD` and
`RELEASE_KEY_PASSWORD` secrets into `android/keystore.jks`, writes the
`android/key.properties` that Gradle reads, and the key alias is discovered from
the keystore itself rather than stored in a fourth secret that could drift out of
sync. Both paths are gitignored, and the workflow asserts that they are.

After the build, the workflow reads the APK's certificate and **fails if it is
`CN=Android Debug`**, or if there is not exactly one signer. That check is the
reason this cannot silently regress again.

The first version of this setup had the secrets configured and the workflow
never reading them, while the build fell back to the debug key — so every APK
through 0.3.3 shipped forgeable. Nothing about the keystore was wrong; nobody
was using it. If you want to check a given release for yourself:

```sh
apksigner verify --print-certs mobilelm-<version>-arm64-v8a.apk
```

## Credits

- **[PrivateLM](https://github.com/orailnoor/cross-platform-llm-client)** — this
  repository is a fork of its Flutter codebase: engine, chat, attachments,
  acceleration ladder. MIT.
- **[OGAM](https://github.com/off-grid-ai/OGAM)** — the default system prompt is
  taken from OGAM. MIT.
- **[PocketStrike-AI](https://github.com/AbuZar-Ansarii/PocketStrike-AI)** — the
  agent layer's design: tolerant tool-call parsing and the tool-registry
  approach. MIT.
- **[llama.cpp](https://github.com/ggml-org/llama.cpp)** and
  **[LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM)** — the inference
  engines, vendored and patched.

## License

MIT — see [LICENSE](LICENSE). Vendored C++ keeps its own upstream licenses.
