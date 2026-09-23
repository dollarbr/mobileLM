# mobileLM — Agent Guide

Objetivo do repo: mix do **PrivateLM** (motor local Flutter) com **PocketStrike-AI**
(camada de agente). Fonte da verdade do roadmap: [`docs/PLAN.md`](docs/PLAN.md) — leia antes de qualquer tarefa.

## Estado atual

M1 ✅ · M2 ✅ · M3 ✅ · M4 ✅ · M5 ✅ — releases publicadas em
<https://github.com/dollarbr/mobileLM/releases>. Versão atual: **0.3.2+1**.
Engine local (GGUF + LiteRT-LM 0.17.1) + agente multi-passo + tools nativas
(18 built-in, 8 privilegiadas via Shizuku) + tarefas agendadas + image gen +
servidor OpenAI compatível + cloud models com auto-detect de contexto/capabilidades.

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
- **Flutter analyze não compila Kotlin.** Se remover imports de `MainActivity.kt`, o bug só aparece no `flutter build`. Verifique o Kotlin manualmente após qualquer alteração nos `.kt`.
- **Modelos custom adicionados via URL/search só são removidos da lista se o predicado
  `isStaleImport` em `refreshDownloaded()` olhar `isCustom` também.** O bug antigo
  deletava o arquivo do disco mas mantinha o entry no Hive, fazendo o modelo
  reaparecer depois de qualquer refresh. Corrigido em `0.2.4`: a condição agora é
  `(m.isImported || m.isCustom) && !files.contains(m.filename)`.

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

## Tools privilegiadas (Shizuku)

Oito tools de leitura e settings que só existem quando há Shizuku. **O app nunca
chama `su` nem exige root** — decisão de produto. Detalhes, os quatro estados, a
regra de argv-nunca-string-de-shell e o teto de saída em
[`docs/SHIZUKU.md`](docs/SHIZUKU.md) — leia antes de mexer em
`privileged_commands.dart` ou no `ShizukuShell`.

## Identidade

Spec completa em `docs/brand/palette.md`. Ícone: `docs/brand/logo.svg`.
Dark-first, accent Volt `#B9F53E`, Pulse `#8B7CFF` com parcimônia.

## Comandos

```bash
cd mobileLM-app
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings   # ~40 infos/warnings pre-existentes
flutter test                                           # único arquivo: flutter test test/x_test.dart
flutter run --debug
flutter build apk --debug --target-platform android-arm64
flutter build apk --release --split-per-abi --target-platform android-arm64
```

## Branch e commit

Branch **`dev`** é onde se testa; merge na `main` só depois de análise e testes
(com `--no-ff`). Ambos publicados em `origin`.

Todo commit em mobileLM-app deve ser **documentado** (pedido explícito do usuário) —
diferente do resto do workspace, onde commit só ocorre se pedido.

## CI e release

Três workflows ativos: `ci.yml` (analyze + test, ~2 min), `debug-apk.yml` (APK debug
arm64 por push, ~22 min) e `release.yml` (dispara na tag).

Release é por tag, e a tag tem que bater com a versão do `pubspec` **sem** o
`+build`: `0.3.2+1` → tag `0.3.2`. O workflow falha de propósito se divergirem.
Tags com prefixo `v` (ex: `v0.3.0`) também são aceitas. As notas saem agrupadas por
prefixo de Conventional Commit; o que não casa com nenhum prefixo cai em "Other",
então nada some.

Release tags publicadas: `0.2.3` (M4), `0.3.0` (cloud + métricas), `0.3.1` (exportar, chips, sumarização), `0.3.2` (PDF→markdown, clamp cloud correto, tools de arquivo removidas quando documento anexado).

**Todo workflow que compila precisa liberar disco antes.** Os nativos vendorizados
— llama.cpp com backend Vulkan e seus ~300 objetos de shader, LiteRT, Stable
Diffusion — enchem os ~14 GB livres do runner com intermediários, e o release ainda
soma R8. O `release.yml` ficou a vida toda sem esse passo (nunca havia rodado) e
morreria em `No space left on device` na primeira tag; corrigido em `ea9a828`.

**Assinatura de release é bloqueada por padrão fora do CI.** O `build.gradle.kts`
lança exceção se `isReleaseBuild` for true e `GITHUB_ACTIONS`/`CI` não estiverem
presentes. Para build local de release sem keystore, use `flutter build apk
--release` (release *não-assinado*) — o build.gradle permite quando `signingConfig`
é debug. Para build assinado local, defina `MOBILELM_ALLOW_DEBUG_RELEASE_SIGNING=true`.

Sem keystore no CI: `MOBILELM_ALLOW_DEBUG_RELEASE_SIGNING=true`.

## Notas de build

- Máquina: 12 hybrid cores (10 e-core + 2 p-core). `org.gradle.workers.max=2` no
  `gradle.properties` — nunca sature todos os núcleos.
- Threads: 4 é o ótimo no Edge 60 (4×A78+4×A55); 8 regressa porque A55 trava A78.
- R8 está desligado (`isMinifyEnabled = false`). Não adicione regras ProGuard por
  precaução — elas não fazem efeito e podem mascarar problemas reais.
- **Plugins locais com `dependency_overrides` podem não ser detectados pelo Flutter plugin discovery.** Se `dart_plugin_registrant.dart` não inclui, registrar manualmente no `MainActivity`.
- Modelo pequeno (<2B) prefere CPU no prefill: GPU (Vulkan) tem overhead de shader
  que domina até ~2B parâmetros. `n_gpu_layers==0` deve zerar a lista de dispositivos,
  não apenas pular offload — senão ggml sched offloads ops pro Vulkan (`op_offload`).

## Cloud features (0.3.0)
## Tradução (PT-BR)

- **Cobertura:** ~394 `.tr` calls no código, 278+ keys em `app_translation.dart`
- **Arquivos:** `lib/l10n/app_translation.dart` (GetX), `lib/l10n/app_en.arb`, `lib/l10n/app_pt_BR.arb`
- **Templates traduzidos:**
  - Sugestões de chat (16 prompts em PT-BR)
  - Views: chat, model, settings, log, task, workspace, HF search
  - Controllers: model, chat, settings
  - Widgets: image_viewer
- **Regra:** strings UI nunca em `const` — `.tr` é método runtime
- **Device locale:** `pt_BR` (confirmado via `adb shell getprop persist.sys.locale`)


- **Round-trip ceiling:** cloud = 20 hops fixo; local = `agentMaxHops` (setting).
  Setting "Tool round-trips" inclui `∞` (valor 0 = infinito) e entrada manual
  (toque no valor → dialog com TextField, valida 0–8).
- **Context window auto-detect:** `_parseContextWindows()` em
  `cloud_model_controller.dart` — OpenRouter, DeepSeek, NVIDIA, Google, OpenAI.
  Safe maxTokens = 25% do contexto, min 256 (`effectiveMaxTokens()`).
- **Capability auto-detect:** vision/tools tags por provider na lista de modelos.
- **Métricas persistentes:** `ChatMessage` armazena `ttftMillis`, `totalTokens`,
  `totalMs`. Exibidas permanentemente após geração no `ChatBubble`. Cores:
  Volt `#B9F53E` (escuro) / verde escuro `#1B5E20` (claro).
- **Cloud TPS:** `cloudTokensPerSecond` observable no chat controller.

## Sugestões de próximas features

Ver [`docs/suggestions.md`](docs/suggestions.md) para lista completa organizada
por esforço/impacto. Top 3: exportar conversa, chips de sugestão rápida,
sumarização automática de contexto.

## Cloud features (0.3.0)
## Tradução (PT-BR)

- **Cobertura:** ~394 `.tr` calls no código, 278+ keys em `app_translation.dart`
- **Arquivos:** `lib/l10n/app_translation.dart` (GetX), `lib/l10n/app_en.arb`, `lib/l10n/app_pt_BR.arb`
- **Templates traduzidos:**
  - Sugestões de chat (16 prompts em PT-BR)
  - Views: chat, model, settings, log, task, workspace, HF search
  - Controllers: model, chat, settings
  - Widgets: image_viewer
- **Regra:** strings UI nunca em `const` — `.tr` é método runtime
- **Device locale:** `pt_BR` (confirmado via `adb shell getprop persist.sys.locale`)


- **Round-trip ceiling:** cloud = 20 hops fixo; local = `agentMaxHops` (setting).
  Setting "Tool round-trips" inclui `∞` (valor 0 = infinito) e entrada manual
  (toque no valor → dialog com TextField, valida 0–8).
- **Context window auto-detect:** `_parseContextWindows()` em
  `cloud_model_controller.dart` — OpenRouter, DeepSeek, NVIDIA, Google, OpenAI.
  Safe maxTokens = 25% do contexto, min 256 (`effectiveMaxTokens()`).
- **Capability auto-detect:** vision/tools tags por provider na lista de modelos.
- **Métricas persistentes:** `ChatMessage` armazena `ttftMillis`, `totalTokens`,
  `totalMs`. Exibidas permanentemente após geração no `ChatBubble`. Cores:
  Volt `#B9F53E` (escuro) / verde escuro `#1B5E20` (claro).
- **Cloud TPS:** `cloudTokensPerSecond` observable no chat controller.
