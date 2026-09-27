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

> [!WARNING]
> **0.3.4 is the first release that is genuinely signed. Take it, not an older one.**
>
> Every release up to 0.3.3 was signed with the **Android debug key** — and not
> the same one twice. Each CI run generated a throwaway `debug.keystore` on an
> ephemeral runner, so all seven older releases carry seven different
> certificates. That makes them two things at once: **not verifiable** (anyone can
> produce a debug-signed APK that claims to be mobileLM, because the debug key is
> public), and **not updatable** (no two of them can install over each other, and
> the keys are gone, so that will not change).
>
> 0.3.4 and every version after it are signed with **one fixed key**, held in
> repository secrets — the same secrets every time. Check it:
>
> ```sh
> apksigner verify --print-certs mobilelm-<version>-arm64-v8a.apk
> ```
>
> ```
> CN=dollarbr, OU=mobileLM, O=mobileLM, C=BR
> SHA-256: 1cd43cb7daddcec2a70c35926939a00247c66df5b1bd0a08db4293fc556cfb6d
> ```
>
> Anything reporting `CN=Android Debug` is not from a release you should be
> installing. The release workflow fails the build if the certificate is not this
> one, so it cannot be published by accident. More detail in
> [Signing](#signing).

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

**0.3.4 is the first release you cannot install over an earlier one.** Android
refuses to replace an app with a differently-signed build, so uninstall first —
that deletes your downloaded models, chat history and workspace bindings.
Export anything you care out of the app before you do.

You have almost certainly had to do this at every previous version too, and the
README used to imply otherwise. It did not. Every release through 0.3.3 was
signed with a *different* Android debug key:

| Release | Signing certificate SHA-256 (first 12) | versionCode |
|---|---|---|
| 0.1.0 | `150430ee483f` | 2002 |
| 0.2.0 | `af4642b184f1` | 2003 |
| 0.2.1 | `0f407a555bb3` | 2001 |
| 0.3.0 | `bc1a801ffd19` | 2001 |
| 0.3.1 | `ef9321cf0798` | 2001 |
| 0.3.2 | `4e8436507d35` | 2001 |
| 0.3.3 | `0c508b931263` | 2001 |

Seven releases, seven keys. Each CI run generated a throwaway `debug.keystore`
on an ephemeral runner, so no two of them could install over each other. The
keys are gone; nobody kept them. There was no upgrade path to lose — every
version bump was already an uninstall and a reinstall.

From 0.3.4 the key is fixed and stored as a repository secret, so from here on
updates are ordinary installs. Check any release yourself:

```sh
gh release download 0.3.3 --repo dollarbr/mobileLM
apksigner verify --print-certs mobilelm-0.3.3-arm64-v8a.apk   # CN=Android Debug
apksigner verify --print-certs mobilelm-0.3.4-arm64-v8a.apk   # CN=dollarbr
```

Debug APKs from CI are still debug-signed. That is correct and intended: they
are not distributed, they must be able to install over any build, and a stable
debug key would defeat the point of the assertion in [Signing](#signing).

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
| Release (CI) | the project's release key, from the `release` environment |
| Release (local) | refused — the build fails, it does not downgrade |
| Debug | the Android debug key, as always |

The release keystore is never in the repository. `release.yml` materialises it
from the `RELEASE_KEYSTORE_BASE64`, `RELEASE_STORE_PASSWORD` and
`RELEASE_KEY_PASSWORD` secrets into `android/keystore.jks`, writes the
`android/key.properties` that Gradle reads, and the key alias is discovered from
the keystore itself rather than stored in a fourth secret that could drift out of
sync. Both paths are gitignored, and the workflow asserts that they are.

Those three secrets live in a GitHub **environment** named `release`, not at
repository level, and the build job declares `environment: release`. Two things
follow, and both matter:

- Only a job that declares that environment can read them. At repository level
  they were visible to every workflow in the repo, including the debug APK build
  that runs on every push.
- The environment allows **tags only**. A workflow run from a branch cannot
  deploy to it, so pushing code — or opening a branch — gets nobody near the
  signing key. Verified: a branch-triggered run is rejected in about two seconds
  with `Branch "..." is not allowed to deploy to release due to environment
  protection rules`, before a single step executes.

To confirm the setup is intact, `gh secret list --repo dollarbr/mobileLM` should
come back **empty**; the secrets should only be visible with
`gh secret list --env release`. If something shows up at repository level, the
environment is not protecting anything.

Secret scanning and secret scanning push protection are both enabled. They are
free on a public repository, and they are the net against a secret being
force-added to a commit one day.

One control is not available here: environment *required reviewers* is an
organization feature, and this repository is on a personal account, so the API
rejects it with `App not installed on organization`. The tag restriction covers
the concrete scenario — someone pushes code — but there is no human approval gate
in front of a release. Moving the repository to an organization would allow one.

After the build, the workflow reads the APK's certificate and checks three
things: the SHA-256 must be `1cd43cb7…`, it must not be `CN=Android Debug`, and
there must be exactly one signer.

The fingerprint is the one that matters. The other two pass happily for a
*brand-new* release key — which is the exact shape of the original bug, a
release that builds, signs, goes green, and is signed by the wrong key. The
fingerprint is the only thing that tells "our key" apart from "some other
non-debug key".

The first version of this setup had the secrets configured and the workflow
never reading them, while the build fell back to the debug key — so every APK
through 0.3.3 shipped forgeable, each with a *different* debug key. Nothing
about the keystore was wrong; nobody was using it.

The release key is `CN=dollarbr, OU=mobileLM, O=mobileLM, C=BR`, SHA-256
`1cd43cb7daddcec2a70c35926939a00247c66df5b1bd0a08db4293fc556cfb6d`. The
keystore lives outside every repository, with its password beside it, and is
valid until 2054. **If you ever need to verify a build is really ours, that
fingerprint is the thing to compare** — not the file name, not the tag, and
definitely not the version string, all of which are forgeable.

An earlier `mobilelm_release.jks` (2780 bytes, 2026-09-16) is kept as
`mobilelm_release.jks.orphaned`. Its password was never recorded, so it can
never sign anything. Nothing was ever signed with it, so there is nothing to
recover; it is there only in case you want to look at its certificate.

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
