# Sugestões de Funcionalidades — mobileLM-app

**Data:** 2026-09-22  
**Versão atual:** 0.3.0+1  
**Engine:** GGUF + LiteRT-LM 0.17.1 · Cloud + Agente multi-passo

---

## ✅ Features completadas na versão 0.3.0

| Feature | Status | Arquivo principal |
|---|---|---|
| Cloud round-trip ceiling | ✅ Feito | `chat_controller.dart` — cloud = 20 hops fixo, local = `agentMaxHops` |
| Context window auto-detect | ✅ Feito | `cloud_model_controller.dart` — OpenRouter, DeepSeek, NVIDIA, Google, OpenAI |
| Capability auto-detect (vision/tools) | ✅ Feito | `cloud_model_controller.dart` — parsed per provider |
| MaxTokens auto-clamp | ✅ Feito | `effectiveMaxTokens()` — 25% do contexto, mínimo 256 |
| Métricas de geração persistentes | ✅ Feito | `chat_bubble.dart` — TTFT, tokens, duração após conclusão |
| Cores adaptativas de métricas | ✅ Feito | Verde Volt `#B9F53E` no escuro, verde escuro `#1B5E20` no claro |
| Setting "Tool round-trips" com ∞ | ✅ Feito | `settings_view.dart` — valor 0 = infinito |
| Cloud TPS tracking | ✅ Feito | `chat_controller.dart` — `cloudTokensPerSecond` observable |
| Kotlin 2.4.20 upgrade | ✅ Feito | Todos os build files |
| LiteRT-LM 0.17.1 | ✅ Feito | Maven `litertlm-android:0.17.1` |
| Dart packages wave 1 | ✅ Feito | dio, ffi, http, image, image_picker, intl, path_provider, uuid, gal, speech_to_text |
| SD.cpp submodule update | ✅ Feito | `c92d73c` + ggml `4bf5f60` |
| Patch sd_jni_wrapper.cpp | ✅ Feito | 3 API breaks corrigidos |

---

## 🟢 Baixo esforço, alto impacto

### 1. Exportar conversa
Compartilhar como texto, markdown ou PDF. Útil para salvar diagnósticos, respostas longas, ou enviar para outro lugar.
- **Esforço:** ~1h
- **Como:** `share_plus` já está no projeto; usar `DocumentExporter` simples
- **Priority:** Alta

### 2. Botão "copiar resposta" dedicado
Já existe copiar trecho, mas um botão no bubble com "copiar tudo" seria rápido.
- **Esforço:** ~30 min
- **Como:** Adicionar ícone de cópia no `_streamBubble` e no `ChatBubble`
- **Priority:** Média

### 3. Sugestões rápidas (chips) após resposta
Quando o modelo responde, mostrar chips como "explique melhor", "resuma", "traduza", "continue". Envia um prompt pré-definido automaticamente.
- **Esforço:** ~2h
- **Como:** Widgets chips na parte inferior do bubble, lista de prompts mapeada por contexto
- **Priority:** Alta

### 4. Modo economia de bateria para inferência
Desliga Vulkan/GPU, usa CPU-only quando bateria < 20%. Já tem toggle de acelerador, só precisa ligar ao status da bateria.
- **Esforço:** ~1h
- **Como:** Observar `BatteryPlus` e ajustar `acceleration.dart` automaticamente
- **Priority:** Média

---

## 🟡 Médio esforço, alto impacto

### 5. Sumarização automática de contexto
Quando `contextTokensUsed` > 75% do tamanho, resumo automático das mensagens mais antigas. Libera contexto mantendo o resumo como mensagem de sistema.
- **Esforço:** ~4-6h
- **Como:** Orquestrar `InferenceService.generate()` com histórico truncado + resumo injetado
- **Priority:** Alta

### 6. Comandos rápidos na barra inferior
Swipes ou barra fixa: "pesquisar web", "tirar foto", "verificar bateria", "enviar SMS pra X". Reduz fricção pra tools comuns.
- **Esforço:** ~6-8h
- **Como:** Bottom bar no chat, cada botão chama uma tool diretamente
- **Priority:** Média

### 7. Gravar áudio → transcrever → enviar pro modelo
Já tem `speech_to_text` e LiteRT multimodal, mas não está integrado no fluxo de chat. Botão de gravar que transcreve e manda automaticamente.
- **Esforço:** ~3-4h
- **Como:** Integrar `SpeechToText` com o input field, transformar em mensagem de texto antes de enviar
- **Priority:** Média

### 8. Benchmark comparativo de quantizações
Testar Q4_0 vs Q5_0 vs Q8_0 no modelo atual e mostrar tok/s de cada uma. Já tem engine de benchmark, só precisa expor na UI.
- **Esforço:** ~2-3h
- **Como:** Tela dedicada em Settings > Modelos, comparar lado a lado
- **Priority:** Baixa

---

## 🔵 Médio esforço, médio impacto

### 9. Prompts de sistema pré-definidos por persona
"Assistente técnico", "programador", "tradutor", "resumidor". Salva no Hive, seleciona antes de conversar.
- **Esforço:** ~2h
- **Como:** Lista de presets em Settings, injeta no system prompt antes de gerar
- **Priority:** Média

### 10. Diferença lado a lado de modelos
Coloca dois modelos pra responder a mesma pergunta simultaneamente. Compara velocidade, qualidade, tokens usados.
- **Esforço:** ~4h
- **Como:** Nova tela "Model Comparison", duas instâncias de geração paralela
- **Priority:** Baixa

### 11. Histórias / templates de conversa
Salva fluxos comuns: "debug de app", "revisão de código", "planejamento de viagem". Reaplica sistema prompt + contexto em nova sessão.
- **Esforço:** ~3-4h
- **Como:** Estrutura de template em Hive, loader de contexto na criação de sessão
- **Priority:** Baixa

### 12. Notificação push de tarefas agendadas
Já tem WorkManager, mas notificação quando tarefa completa não parece existir.
- **Esforço:** ~2h
- **Como:** Integrar `flutter_local_notifications` com callback do `ScheduledTaskService`
- **Priority:** Média

---

## Top 3 recomendados

| # | Feature | Por quê |
|---|---|---|
| 1 | **Exportar conversa** | Quase todo mundo quer salvar respostas, fácil de implementar |
| 2 | **Sugestões rápidas (chips)** | Melhora UX imediatamente, mostra o app "pensando" no que você quer depois |
| 3 | **Sumarização automática** | Resolve o maior problema real de modelos locais (contexto curto) |

---

## Como priorizar

1. **Sprint curto (1-2h cada):** Exportar, copiar resposta, chips
2. **Sprint médio (2-4h cada):** Economia de bateria, comandos rápidos, áudio
3. **Sprint longo (4-6h cada):** Sumarização, benchmark, comparison
