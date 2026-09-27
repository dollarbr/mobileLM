# mobileLM

<p align="center">
  <img src="docs/brand/logo.svg" width="96" alt="mobileLM logo"/>
</p>

**A local-first AI agent that lives on your phone.** PrivateLM's on-device
engine, an agent body on top: native tools, multi-step tool chains, and daily
scheduled tasks that run even with the app closed.

<p align="center">
  <img src="docs/screenshots/chat.png" width="250" alt="Chat"/>
  <img src="docs/screenshots/models.png" width="250" alt="Models"/>
  <img src="docs/screenshots/settings.png" width="250" alt="Settings"/>
</p>

## What it does

- **Local inference, no cloud** — GGUF (llama.cpp, Vulkan → CPU ladder) and
  `.litertlm` (LiteRT-LM) models, with a native-side accelerator fallback
  (NPU → GPU → CPU) tuned per device. CPU variants are compiled per ARM
  feature set and picked at runtime, so old SoCs get a baseline build and new
  ones get i8mm/SME automatically.
- **Multimodal in the chat** — images, PDFs, office docs, audio (STT), and
  video (contact-sheet frames) via `libmtmd` + projectors (`mmproj`).
- **Agent tools** — 24 built-in tools, including clock, calculator, device info,
  clipboard, haptics, share, file management scoped to the active project
  (`list_files`, `read_file`, `create_file`, `write_file`, `delete_file`,
  `rename_file`), web tools (`web_search`, `read_url`), and task management
  (`schedule_task`, `list_scheduled_tasks`, `cancel_scheduled_task`).
  Write-class tools pause for a human tap before they run. Tool chains are
  capped (default single hop, up to 8) so small models can't spin forever.
  Eight more exist only with [Shizuku](https://shizuku.dev) installed — read-only
  system inspection that never needs root. See [docs/SHIZUKU.md](docs/SHIZUKU.md).
- **Workspace projects** — pick one folder on the device once; every project
  is a subfolder inside it, and a chat binds to a project so the file tools
  are scoped to it. New chats stay in the project you are already in; the
  project chip in the chat header changes or drops that binding. See
  [docs/WORKSPACE.md](docs/WORKSPACE.md).
- **Scheduled tasks** — a named prompt bound to a model snapshot and a daily
  fire time. Runs in a foreground service with its own engine and empty
  history, posts the result as a notification and into the chat.
- **Image generation** — Stable Diffusion in a background isolate
  (CPU/GPU, quant selectable).
- **OpenAI-compatible local server** on port 8080 for other apps on the
  same network.
- **Thinking toggle** (`<think>` parsing) with auto/on/off.
- **45 models in the catalogue**, from 150 MB to 2.4 GB — 18 of them multimodal.
  Every download is a direct link to a verified file; nothing is proxied through
  a server of ours.

## Install

Grab the APK from
[Releases](https://github.com/dollarbr/mobileLM/releases) — one file,
`mobileLM-<version>-arm64-v8a.apk`.

**arm64-v8a only.** There is no 32-bit build and there is not going to be one:
llama.cpp, LiteRT-LM and Stable Diffusion are all vendored as arm64, and the
plugins pin `abiFilters 'arm64-v8a'`. Every device Android has shipped since
2017 is arm64, so a 32-bit APK would buy nothing and cost a second native build
of the whole engine. On a 32-bit device the app will not run — and note the web
build is not a fallback, it has no local engine at all, only cloud providers.

Every push also produces a debug APK in the
[Debug workflow artifacts](https://github.com/dollarbr/mobileLM/actions/workflows/debug-apk.yml).

## Build from source

```sh
flutter pub get
flutter build apk --release --split-per-abi --target-platform android-arm64
```

`--target-platform android-arm64` is what makes the split produce exactly one APK.
Without it you get a single fat `app-release.apk`; with it and
`--split-per-abi` you get one file per ABI, which is one file.

The native engines are vendored under `local_plugins/` and compiled by
Gradle/CMake on first build — no extra setup beyond Flutter + Android SDK/NDK.
The first build is slow: llama.cpp with its Vulkan shader set, LiteRT and Stable
Diffusion together fill the disk and take the better part of half an hour.

## Credits

- **[PrivateLM](https://github.com/orailnoor/cross-platform-llm-client)** —
  this repository is a fork of its Flutter codebase (engine, chat,
  attachments, acceleration ladder). MIT.
- **[OGAM](https://github.com/off-grid-ai/OGAM)** — the default system prompt
  is copied from OGAM. MIT.
- **[PocketStrike-AI](https://github.com/AbuZar-Ansarii/PocketStrike-AI)** —
  the agent layer's design patterns: tolerant tool-call parsing and the
  tool-registry approach. MIT.
- **[llama.cpp](https://github.com/ggml-org/llama.cpp)** and
  **[LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM)** — the
  inference engines.

## License

MIT — see [LICENSE](LICENSE).

## 🔒 Release Signing Security

Para garantir a segurança da cadeia de suprimentos, **builds de release assinados são permitidos apenas em ambientes de CI verificáveis** (GitHub Actions). Isso impede que chaves de release vazem acidentalmente em ambientes de desenvolvimento.

- **Localmente**: Use `flutter run` (debug) ou `flutter build apk --release` (release build *não-assinado*) para testes. Assinatura de release é bloqueada por padrão.
- **No CI**: O workflow `release.yml` recupera o keystore de release dos GitHub Secrets (`RELEASE_KEYSTORE_BASE64`, `RELEASE_STORE_PASSWORD`, `RELEASE_KEY_PASSWORD`) e realiza o signing de forma segura.
- **Nunca** armazene `android/key.properties` ou arquivos `.jks` no repositório ou em ambientes locais não seguros.

---
