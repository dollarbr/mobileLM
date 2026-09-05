# mobileLM — Agent Guide

Objetivo do repo: mix do **PrivateLM** (motor local Flutter) com **PocketStrike-AI**
(camada de agente). Fonte da verdade do roadmap: [`docs/PLAN.md`](docs/PLAN.md) — leia antes de qualquer tarefa.

## Estado atual

M1 concluído no código: base PrivateLM importada e rebrandada (applicationId `com.dollarbr.mobilelm`, pacote Dart `mobilelm`, ícone adaptativo bolha+raio, tema Ink/Volt). Validação final = CI verde.

## Regras herdadas (aprendidas nas sessões anteriores)

- Base M1 = PrivateLM, já importada neste repo. Não recriar engine, plugins nativos
  (`local_plugins/*`) nem escada de aceleração do zero.
- O fork local `../privateLM` **não existe mais** (apagado, junto com o repo no GitHub).
  A referência é o upstream <https://github.com/orailnoor/cross-platform-llm-client>, e
  o que havia de trabalho só naquela pasta está registrado em
  [`docs/PRIVATELM_REFERENCE.md`](./docs/PRIVATELM_REFERENCE.md) — inclusive o bug de BOS
  duplicado no Llama-3.x, que provavelmente também vale aqui.
- De PocketStrike portar **padrões e catálogo**, não código Kotlin inteiro:
  `[TOOL_CALL]`, lazy registry, parser tolerante. A base já tem parser tolerante em
  `lib/services/tools/` — estender, não duplicar.
- Tool que escreve/envia/apaga exige **confirmação humana** na UI. Leitura pura pode ser auto.
- Agente multi-passo só atrás de toggle, com teto de iterações (modelos pequenos loopam).
- Nativo arm64-only; licenças MIT dos upstreams devem ser citadas (README/LICENSE já cobrem).

## Workspace

Pasta raiz via SAF + projetos como subpastas; conversa liga-se a um projeto por
`ChatSession.projectPath`. Detalhes, ciclo de vida e as armadilhas já pagas em
[`docs/WORKSPACE.md`](docs/WORKSPACE.md) — leia antes de mexer no picker, no
`WorkspaceService` ou em `createNewChat`.

## Alternativas de stack já avaliadas

**Llamatik** ([ferranpons/Llamatik](https://github.com/ferranpons/Llamatik), MIT,
`com.llamatik:library:1.10.1` no Maven Central) é uma biblioteca Kotlin Multiplatform que
embrulha llama.cpp + whisper.cpp + stable-diffusion.cpp numa API só, com multimodal por
`mmproj` e Multi-Token Prediction. Trocaria os três plugins vendorizados de
`local_plugins/` por uma dependência.

**Está parado, e a razão é concreta: Llamatik não fala LiteRT-LM.** Sem isso caem os
modelos `.litertlm` (5 dos 24 do catálogo, incluindo gemma-4 E2B/E4B) e toda a escada
NPU → GPU → CPU. Também não tem o dispatch por variante ARM
(`GGML_CPU_ALL_VARIANTS`) que evita SIGILL em aparelhos pré-2017. Manter um plugin
LiteRT à parte anularia o ganho de consolidar.

Estudo completo (em português) na raiz do workspace: `docs/KMP_MIGRATION_ANALYSIS.md`
(começa por um fact-check datado), `docs/KMP_MIGRATION_PLAN.md`,
`docs/KMP_BUILD_LIMITATIONS.md`. **Reabrir só se o Llamatik ganhar LiteRT** ou se o
caminho NPU for abandonado de vez.

## Identidade

Spec completa em `docs/brand/palette.md`. Ícone: `docs/brand/logo.svg`.
Dark-first, accent Volt `#B9F53E`, Pulse `#8B7CFF` com parcimônia.

## Comandos (valem a partir do M1)

Flutter padrão: `flutter pub get`, `flutter analyze --no-fatal-infos --no-fatal-warnings`,
`flutter test`, tag `<x.y.z>` dispara release de APKs split-per-abi.
