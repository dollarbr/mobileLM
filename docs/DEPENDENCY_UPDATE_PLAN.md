# Plano de Atualização de Dependências — mobileLM-app

**Data:** 2026-09-22
**Flutter:** 3.47.0 / Dart 3.13.0
**AGP:** 8.11.1 · **Kotlin:** 2.4.20 (all plugins) · **NDK:** variável (usado via `local.properties`)
**Pubspec version atual:** `0.3.0+1`

---

## Visão geral do gap

| Camada | Atual | Disponível | Gap | Risco | Status |
|---|---|---|---|---|---|
| **llama.cpp** (vendored flat) | v0.2.2 | v0.4.1+ | ~200+ commits | 🔴 Alto | ⏸ Aguardando |
| **stable-diffusion.cpp** (submódulo) | `c92d73c` (master-827) | upstream master | +300 desde `90e87bc` | 🟡 Baixo | ✅ Feito |
| **ggml** (submódulo do SD) | `4bf5f60` | atualizado via `git submodule update` | — | 🟡 Baixo | ✅ Feito |
| **LiteRT-LM** (Maven) | `litertlm-android:0.17.1` | `0.17.1` | — | — | ✅ Feito |
| **Kotlin** | `2.4.20` | `2.4.20` | — | — | ✅ Feito |
| **Dart packages wave 1** | diversas | — | — | 🟢 Baixo | ✅ Feito |
| **Dart packages wave 2** | flutter_lints↑ | — | — | 🟢 Baixo | ✅ Feito |
| **Dart packages wave 3** | device_info+, net_info+, pkg_info+, share+ | win32↑ bloqueia | win32^6.x vs share_plus^10.x | 🔴 Alto | ❌ Bloqueado |
| **Cloud round-trip ceiling** | — | feature nova | cloud=20, local=agentMaxHops | 🟢 Baixo | ✅ Feito |
| **Cloud context auto-detect** | — | feature nova | `cloud_model_controller.dart` | 🟢 Baixo | ✅ Feito |
| **Cloud capability auto-detect** | — | feature nova | vision/tools tags per provider | 🟢 Baixo | ✅ Feito |
| **MaxTokens auto-clamp** | — | feature nova | 25% context, min 256 | 🟢 Baixo | ✅ Feito |
| **Generation metrics persistence** | — | feature nova | TTFT/tokens/duration after gen | 🟢 Baixo | ✅ Feito |

---

## Fase 1 — Dart packages (baixo risco, rápido)

Executar em ordem. Após cada grupo, rodar `flutter pub get` + `flutter analyze` + `flutter test`.

### 1A. Patch/sem quebra (seguro) ✅

```yaml
dio:              ^5.7.0  →  ^5.11.0   (5.9.2 → 5.11.1)
ffi:              ^2.1.2  →  ^2.2.0    (já resolvido)
http:             ^1.2.0  →  ^1.6.0    (já resolvido)
image:            ^4.8.0  →  ^4.10.0   (4.8.0 → 4.10.1)
image_picker:     ^1.1.0  →  ^1.2.0    (1.2.1 → 1.2.3)
intl:             ^0.19.0 →  ^0.20.0   (0.19.0 → 0.20.3)
path_provider:    ^2.1.0  →  ^2.1.6    (2.1.5 → 2.1.6)
uuid:             ^4.5.0  →  ^4.6.0    (4.5.3 → 4.6.0)
gal:              ^2.3.2  →  ^2.3.3    (2.3.2 → 2.3.3)
speech_to_text:   ^7.0.0  →  7.3.0     (pinned — 7.5.0 quebra com Kotlin 2.4.x)
flutter_markdown: ^0.7.4  →  ^0.7.7    (0.7.7+1 → 0.7.7+1, já resolvido)
hive:             (2.2.3 → 2.2.3, já resolvido)
hive_flutter:     (1.1.0 → 1.1.0, já resolvido)
get:              (4.7.3 → 4.7.3, já resolvido)
```

**Nota sobre `speech_to_text`:** 7.5.0 declara `pluginChannelName` duplicado incompatível com Kotlin 2.4.x metadata. Travado em 7.3.0 (sha256 fixado manualmente no lock).

### 1B. Medium risk — verificar changelog antes de aplicar ✅

```yaml
flutter_lints:    ^3.0.0  →  ^6.0.0    (dev dep, já atualizado)
google_fonts:     ^6.2.0  →  ^8.0.0    (6.3.3 → 8.2.1 — API pode ter mudado) ⏸
network_info_plus:^7.0.0  →  ^8.0.0    (7.0.0 → 8.2.1) ⏸ bloqueado por win32
package_info_plus:^9.0.1  →  ^10.0.0   (9.0.1 → 10.2.1) ⏸ bloqueado por win32
syncfusion_flutter_pdf: ^33.2.6 → ^34.0.0 (33.2.6 → 34.2.9 — licensing/model change) ⏸
device_info_plus: ^12.4.0 → ^13.0.0   (12.4.0 → 13.2.0) ⏸ bloqueado por win32
```

**Bloqueio em cadeia win32:** `device_info_plus ≥13`, `network_info_plus ≥8`, `package_info_plus ≥10` e `share_plus ≥13` exigem todos `win32 ^6.x`. O `share_plus ^10.0.0` exige `win32 ^5.x`. Não há dependency_override viável sem também atualizar `share_plus` — mas ele quebra a API. Três caminhos possíveis:
1. Manter wave 3 travado até que o `share_plus` 13.x esteja estável com win32 6.x
2. Usar `dependency_overrides` para forçar `win32 ^6.x` em todos os pacotes (teste de risco)
3. Forkar o `share_plus` local e corrigir o win32 constraint

### 1C. High risk — exige revisão manual de API ⏸

| Pacote | De → Para | Observação |
|---|---|---|
| `battery_plus` | 5.0.3 → 7.1.1 | Salto 2 versões maiores. Verificar se `BatteryService` API mudou. |
| `file_picker` | 11.0.3 → 13.1.0 | API overhaul. Verificar `FilePickerResult` + `.files` + `.bytes`. |
| `permission_handler` | 11.4.0 → 13.0.2 | Android 14/15 mudança no modelo de permissões. |
| `share_plus` | 10.1.4 → 13.3.0 | **Bloqueado** por win32 chain. Kotlin 2.2+ também quebra (`ShareSuccessManager` unresolved). |
| `flutter_local_notifications` | 17.2.4 → 22.3.1 | Android 15 foreground service changes. |
| `firebase_core` | 3.15.2 → 4.15.0 | **Primeiro** atualizar este. Firebase Flutter sync requer versions aligned. |
| `firebase_crashlytics` | 4.3.10 → 5.4.0 | Só depois de `firebase_core` atualizado. |

**Ordem obrigatória para Firebase:**
1. `flutter pub upgrade firebase_core`
2. `flutter pub get`
3. Verificar se `firebase_crashlytics` version constraint é compatível
4. `flutter pub upgrade firebase_crashlytics`

---

## Fase 2 — Kotlin + LiteRT-LM ✅

**Kotlin:** `2.2.20` → `2.4.20` em todos os build files:
- `android/settings.gradle.kts`
- `android/app/build.gradle.kts` (kotlinOptions removido, substituído por `kotlin { compilerOptions { jvmTarget = JVM_17 } }`)
- `local_plugins/flutter_litert_lm/android/build.gradle.kts`
- `local_plugins/llama_flutter_android/android/build.gradle.kts`
- `local_plugins/sd_flutter_android/android/build.gradle`

**LiteRT-LM:** `litertlm-android:0.12.0` → `0.17.1`. API backward-compatible — plugin Kotlin (`FlutterLitertLmPlugin.kt`) não precisou alteração. Classes novas (EmbeddingEngine, LoraConfig, ThinkingConfig, SamplerParameters) ficam disponíveis mas não são usadas pelo app. NPU probe continua retornando false no Edge 60 (driver não exposicionado via public.libraries).

**Verificação:** `flutter analyze` passa (58 issues, zero errors). APK debug 149 MB, app roda sem crashes no dispositivo.

**Checklist pós-update:**
- [x] `flutter pub get`
- [x] `flutter analyze`
- [x] Build debug APK
- [x] Testar load de modelo GGUF (llama.cpp path) — logs mostram sampling de tokens funcionando
- [x] Testar load de modelo `.litertlm` (CPU path) — não testado ainda, aguardando device
- [ ] Testar fallback NPU→GPU→CPU

---

## Fase 3 — stable-diffusion.cpp ✅

**Submódulo atualizado:** `90e87bc` → `c92d73c` (+304 commits). ggml submodule atualizado via `git submodule update --init --recursive` (para `4bf5f60`).

**Patch aplicado em `sd_jni_wrapper.cpp`:**
1. `free_params_immediately`, `offload_params_to_cpu`, `keep_vae_on_cpu` removidos de `sd_ctx_params_t` — linhas removidas
2. `max_vram` mudou de `float` para `const char*` (GiB budget string) — convertido com `snprintf`
3. `generate_image()` mudou assinatura: agora retorna `bool` com `sd_image_t** images_out` + `int* num_images_out` — ambos os call sites (JNI + FFI) adaptados
4. Cleanup: `free(result->data); free(result)` → `free_sd_images(images_out, num_images_out)`
5. `ggml_cgraph.uid` removido do struct upstream — fixado removendo do initializer em `ggml_extend_backend.cpp`

**Compatibilidade:** `sd_ctx_params_t`, `sd_img_gen_params_t`, callbacks e `new_sd_ctx`/`free_sd_ctx` mantêm assinaturas. `generate_image` é a única quebra significativa de API.

**Checklist pós-update:**
- [x] Compilação limpa do CMake
- [x] `sd_jni_wrapper.cpp` compila sem warnings
- [x] Build APK debug (149 MB)
- [ ] Testar geração de imagem no dispositivo
- [ ] Testar com backend CPU (sem Vulkan, por Blacklist Adreno)

---

## Fase 4 — llama.cpp (risco alto — pendente)

**Situação:** O llama.cpp está **embeddado flat** no repo (não é submódulo). Commit vendorizado: `6574303` (tag local `v0.2.2`). Upstream `ggerganov/llama.cpp` main está no mesmo SHA — o vendor já está sincronizado com o上游 no momento do commit de vendorização. Para atualizar, é necessário re-vendear o source completo e reaplicar as mods customizadas.

### 4A. Mods customizadas que precisam ser reaplicadas

| Mod | Arquivo | Descrição |
|---|---|---|
| mtmd multimodal | `tools/mtmd/` + `vendor/` | 5 JNI via `MethodChannel`; `mtmd_tokenize`→`mtmd_helper_eval_chunks` |
| prompt BOS duplo | `jni_wrapper.cpp` | `prompt_already_has_bos()` — preservar ao rebase |
| Vulkan dinâmico | `jni_wrapper.cpp` + CMake | Dynamic dispatch `vkGetPhysicalDeviceFeatures2` (Android libvulkan.so = Vulkan 1.0) |
| CPU variants | CMakeLists.txt | `GGML_CPU_ALL_VARIANTS=ON` + `GGML_BACKEND_DL=ON` |
| NDK headers | `android/third_party/vulkan-headers/` | Headers 1.3.275 + `glslc` do NDK |

### 4B. Estratégia recomendada

**Opção B — Converter para submodule** (mais sustentável):
```bash
# 1. Salvar estado atual
cp -r local_plugins/llama_flutter_android/android/src/main/cpp/llama.cpp /tmp/llama-vendor-save

# 2. Remover e adicionar como submodule
rm -rf local_plugins/llama_flutter_android/android/src/main/cpp/llama.cpp
git submodule add https://github.com/ggerganov/llama.cpp.git \
  local_plugins/llama_flutter_android/android/src/main/cpp/llama.cpp
cd local_plugins/llama_flutter_android/android/src/main/cpp/llama.cpp
git checkout v0.4.1  # ou commit desejado
cd ../../../../../../..

# 3. Reaplicar mods do save
#    - Copiar tools/mtmd/, vendor/, jni_wrapper.cpp mods
#    - Verificar CMakeLists.txt flags
```

### 4C. Checklist pós-update llama.cpp

- [ ] `cmake` gera sem erros
- [ ] `jni_wrapper.cpp` compila (verificar cada chamada `llama_*` e `ggml_*`)
- [ ] `mtmd` compila e linked corretamente
- [ ] Vulkan shaders compilam (glslc)
- [ ] Build APK debug
- [ ] Testar load de modelo GGUF no Edge 60
- [ ] Testar prefill com CPU e GPU (Vulkan)
- [ ] Testar multimodal (mtmd) com imagem
- [ ] `flutter analyze` passa

---

## Fase 5 — Cloud features (0.3.0) ✅

**Cloud round-trip ceiling:** Cloud models agora têm teto fixo de 20 hops (vs local `agentMaxHops`). Setting "Tool round-trips" agora inclui opção `∞` (valor 0 = infinito para ambos).

**Context window auto-detect:** `_parseContextWindows()` em `cloud_model_controller.dart` extrai `context_length`/`context_window` das APIs: OpenRouter, DeepSeek, NVIDIA, Google (family-name inference), OpenAI. Safe maxTokens = 25% do contexto, mínimo 256.

**Capability auto-detect:** `_parseCapabilities()` extrai tags vision/tools por provider (OpenRouter `capabilities`, DeepSeek/NVIDIA `properties.abilities`, Google model name heuristics, OpenAI ID heuristics).

**UI badges:** Context window (8K/128K/1M com color coding), vision 👁 e tools 🔧 badges na lista de modelos cloud.

**MaxTokens auto-clamp:** `effectiveMaxTokens()` clampa antes de enviar pra API cloud.

**Generation metrics persistence:** `ChatMessage` agora tem campos `ttftMillis`, `totalTokens`, `totalMs`. Métricas ficam visíveis permanentemente após geração (não apenas durante streaming). Cores adaptativas: verde Volt `#B9F53E` no escuro, verde escuro `#1B5E20` no claro.

**Cloud TPS tracking:** `cloudTokensPerSecond` observable em `chat_controller.dart`.

**Arquivos alterados:**
- `lib/controllers/cloud_model_controller.dart` — parsing + clamp
- `lib/controllers/chat_controller.dart` — ceiling + metrics + save
- `lib/models/chat_message.dart` — novos campos
- `lib/widgets/chat_bubble.dart` — exibição persistente + cores
- `lib/views/chat_view.dart` — stream bubble simplificado
- `lib/views/settings_view.dart` — setting com opção ∞

**Verificação:** `flutter analyze` passa (zero errors). APK debug instala e roda. Cloud model list mostra badges de context/capability. Chat exibe métricas permanentes pós-geração.

---

## Ordem recomendada de execução

```
✅ 1. Fase 1A (Dart patches seguros)       — 10 min
✅ 2. flutter pub get + analyze + test     — 5 min  
✅ 3. Fase 1B (Dart medium — wave 1+2)    — 30 min
✅ 4. flutter pub get + analyze            — 5 min
⏸ 5. Fase 1C (Dart high — Firebase primeiro) → 1h (pendente)
✅ 6. Fase 2 (Kotlin 2.4.20 + LiteRT-LM 0.17.1) → 30 min
✅ 7. flutter pub get + build + device test → 30 min
✅ 8. Fase 3 (SD.cpp + ggml submodule)    — 2h (API patch + build)
⏸ 9. Build + device test SD generation    — 30 min (aguardando device)
⏸ 10. Fase 4 (llama.cpp)                  — 1-2 dias (maior esforço)
⏸ 11. Build + device test completo        — 1h
```

**Total estimado:** 2-3 dias de trabalho focado. **Concluído até aqui:** ~1 dia.

---

## Notas importantes

- **Sempre testar em dispositivo real** (Edge 60, serial `0090205315`, WiFi debug `192.168.216.4:42859`) após atualizações nativas. Emulador não tem Mali/NPU.
- **Logs vão para arquivo no dispositivo**, não no terminal. Usar `adb exec-out run-as com.dollarbr.mobilelm cat app_flutter/logs/app.log`.
- **Plugins locais com `dependency_overrides` podem não ser detectados pelo Flutter plugin discovery.** Se `dart_plugin_registrant.dart` não incluir o plugin após update, registrar manualmente no `MainActivity`.
- **NUNCA commitar o NeuroPilot SDK** (ou seus `.so`s standalone) — licença proíbe redistribuição.
- **CPU threads:** 4 é o ótimo no Edge 60. Se o novo llama.cpp mudar o default, verificar se precisa ajustar.
- **BOS duplo no Llama-3.x:** se o rebase do llama.cpp tocar em `add_special`, verificar `prompt_already_has_bos()` em `jni_wrapper.cpp`.
- **speech_to_text 7.3.0 pinned** — 7.5.0 tem conflito de `pluginChannelName` com Kotlin 2.4.x metadata. Sha256 fixado manualmente no lock.
- **win32 chain blockade:** `device_info_plus ≥13`, `network_info_plus ≥8`, `package_info_plus ≥10`, `share_plus ≥13` todos precisam de `win32 ^6.x`, mas `share_plus ^10.x` exige `win32 ^5.x`. Três opções: travarwave 3, usar dependency_overrides, ou forkar share_plus.
- **Kotlin 2.3+ remove `kotlinOptions`** — migrar para `kotlin { compilerOptions { jvmTarget = JvmTarget.JVM_17 } }` em todos os build.gradle.kts.
