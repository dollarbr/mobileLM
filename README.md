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
- **Agent tools** — 18 built-in tools, including clock, calculator, device info,
  clipboard, haptics, share, file management scoped to the active project
  (`list_files`, `read_file`, `create_file`, `write_file`, `delete_file`,
  `rename_file`), web tools (`web_search`, `read_url`), and task management
  (`schedule_task`, `list_scheduled_tasks`, `cancel_scheduled_task`).
  Write-class tools pause for a human tap before they run. Tool chains are
  capped (default single hop, up to 8) so small models can't spin forever.
- **Scheduled tasks** — a named prompt bound to a model snapshot and a daily
  fire time. Runs in a foreground service with its own engine and empty
  history, posts the result as a notification and into the chat.
- **Image generation** — Stable Diffusion in a background isolate
  (CPU/GPU, quant selectable).
- **OpenAI-compatible local server** on port 8080 for other apps on the
  same network.
- **Thinking toggle** (`<think>` parsing) with auto/on/off.

## Install

Grab a split APK from
[Releases](https://github.com/dollarbr/mobileLM/releases):

| APK | Contents |
|---|---|
| `arm64-v8a` | Everything: native inference, vision, image gen |
| `armeabi-v7a` | Cloud chat + image gen only (native engines are arm64) |

Every push also produces a debug APK in the
[Debug workflow artifacts](https://github.com/dollarbr/mobileLM/actions/workflows/debug-apk.yml).

## Build from source

```sh
flutter pub get
flutter build apk --release --split-per-abi --target-platform android-arm64
```

The native engines are vendored under `local_plugins/` and compiled by
Gradle/CMake on first build — no extra setup beyond Flutter + Android SDK/NDK.

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
