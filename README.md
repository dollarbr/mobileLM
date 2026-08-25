# mobileLM

**On-device AI assistant with an agentic spine.**

mobileLM mixes the two halves of a pocket AI:

- from **PrivateLM** — the local inference stack: GGUF via llama.cpp (Vulkan/CPU ladder), LiteRT-LM, multimodal attachments, image generation, model browser;
- from **PocketStrike-AI** — the agent layer: native Android tools, `[TOOL_CALL]` convention, lazy tool registry, task automation.

Everything runs on-device by default. Cloud is opt-in.

> Status: **bootstrap** — no app code yet. See [`docs/PLAN.md`](docs/PLAN.md) for the roadmap and [`docs/brand/`](docs/brand/) for the identity.

## Brand

| | |
|---|---|
| Icon | chat bubble + bolt: "a local model that acts" |
| Base | Ink `#0B1018` · Surface `#131B27` |
| Accent | Volt `#B9F53E` · Pulse `#8B7CFF` (sparingly) |
| Type | Space Grotesk (display) / Inter (UI) / JetBrains Mono (code) |

Full spec: [`docs/brand/palette.md`](docs/brand/palette.md).

## License

MIT. Derives from [orailnoor/cross-platform-llm-client](https://github.com/orailnoor/cross-platform-llm-client) (PrivateLM) and [AbuZar-Ansarii/PocketStrike-AI](https://github.com/AbuZar-Ansarii/PocketStrike-AI), both MIT.
