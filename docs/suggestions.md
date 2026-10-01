# Sugestões de Funcionalidades — mobileLM-app

**Data:** 2026-09-30  
**Versão atual:** 0.5.1+2008  
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

## ✅ Features completadas na versão 0.3.1

| Feature | Status | Arquivo principal |
|---|---|---|
| Exportar conversa | ✅ Feito | `chat_controller.dart` — `exportChat()` com share_plus |
| Sugestões rápidas (chips) | ✅ Feito | `chat_bubble.dart` — chips abaixo da resposta, delay 500ms |
| Sumarização automática de contexto | ✅ Feito | `chat_controller.dart` — `_maybeSummarizeHistory()`, banner visual no chat |

---

## ✅ Features completadas na versão 0.3.5 — **preparadas, nunca publicadas**

A 0.3.5 chegou a ter commit (`ffd30471b`) e `pubspec` em `0.3.5+2005`, mas a tag
não foi para o remoto e não existe release. **Estes três itens entram na 0.4.0.**

| Feature | Status | Arquivo principal |
|---|---|---|
| Botão de ir para o final acima do de enviar | ✅ Feito | `chat_view.dart` — `Positioned` num `Stack` com a altura da barra medida por `GlobalKey`, em vez do `floatingActionButton` do `Scaffold`, que ancora no fim do corpo |
| Tok/s medido de ponta a ponta | ✅ Feito | `lib/utils/token_rate.dart` + `inference_service.dart` + `chat_controller.dart` — o denominador começava no primeiro token, que é onde a rajada final começa |
| Núcleo híbrido Rust removido do APK | ✅ Feito | −37,2 MB; a decisão, as medições e a rota para retomar estão em [`HYBRID_CORE.md`](HYBRID_CORE.md) |

---

## ✅ Features completadas na versão 0.4.0

| Feature | Status | Arquivo principal |
|---|---|---|
| `/v1/embeddings` no servidor local | ✅ Feito | `openai_server_service_io.dart` — endpoint OpenAI de verdade, com `max_input_tokens` publicado em `capabilities` |
| `/v1/rerank` (formato Cohere/Jina) | ✅ Feito | `openai_server_service_io.dart` — `relevance_score` cru + `relevance_score_probability` ao lado |
| `/v1/classify` | ✅ Feito | `openai_server_service_io.dart` — dois caminhos: cabeça de encoder, e generativo para decision models. Medido no A72 com Tev1-0.8B, **5 de 5** |
| Superfície de decisão (decision models) | ✅ Feito | `decision_model.dart` + `decision_model_test.dart` (28 testes) — despacho por um fato sobre o arquivo (`cls.output.weight` presente ou não), `temperatureOverride`/`maxTokensOverride` em `generate()`, `relevance_score` nulo porque decision model não tem logit |
| Caminho de encoder no JNI | ✅ Feito | `jni_wrapper.cpp` — `nativeEncoderInfo`, `nativeEncode`, `arch_is_encoder`, cabeça de classificação, pooling inferido, `gguf_read_facts` |
| Submenu de encoders em Modelos | ✅ Feito | `model_view.dart` + `model_controller.dart` — 10 encoders, 7 rerankers, papel vindo do catálogo |
| Console de encoder no chat | ✅ Feito | `encoder_console.dart` — 5 templates, barra de relevância relativa, painel `headless`, maximizável |
| Parâmetros por papel em Configurações | ✅ Feito | `encoder_parameters_panel.dart` + `encoder_settings_service.dart` — colunas detectado/override, `auto`/`on`/`off`, teto só pode baixar |
| Triagem de GGUF reproduzível | ✅ Feito | `tool/gguf-screen.py` — range request de 24 MB, sem decodificar arrays, lista de archs lida do llama.cpp vendorizado |
| `config.json` como pre-flight no HF | ✅ Feito | `hf_search_service.dart` (`HfConfig`) + `hf_search_sheet.dart` — veredito de três vias, nunca garante peso |
| Texto e parâmetros de texto em grupos separados | ✅ Feito | `settings_view.dart` — antes era um card colapsável dentro de outro |
| Servidor cai junto com o modelo | ✅ Feito | `model_controller.dart` — `capabilities` não responde mais `running: true` sem modelo |
| Chave de API gerada e exigida | ✅ Feito | `server_auth.dart` — 32 chars de alfabeto sem ambiguidade (160 bits, `Random.secure`), comparação constant-time; ligada por padrão, e um install que **desligou de propósito continua desligado** |
| Gestão de modelos por HTTP | ✅ Feito | `GET /v1/models/local`, `POST /v1/models/{download,load,unload}` — `load` exige `accept_risk`, `unload` é 409, troca de runtime é 409 |
| Servidor sobe sem modelo | ✅ Feito | o portão saiu; os 5 endpoints que precisam de modelo respondem 400 **nomeando o caminho de saída** |
| `stream: true` transmitindo | ✅ Corrigido | `response.bufferOutput = false` nos dois handlers — antes devolvia 1 chunk e `[DONE]` no mesmo instante, 25,86 s depois |
| Watchdog entre tokens | ✅ Corrigido | 5 s → 30 s. 5 s não distingue engine travado de engine lento, e escolher o lado errado corta a resposta do usuário |
| KV cache limpo entre gerações | ✅ Corrigido | `jni_wrapper.cpp` — o clear que o comentário prometia não existia; `g_n_past` crescia ~183 por geração e o prompt seguinte era contaminado pelo anterior |
| Backend do LiteRT medido | ✅ Feito | A/B nos dois backends: **GPU 3,8 tok/s contra CPU 3,0** — GPU ganha por 27%. O default de `planLiteRtTier` está certo por acaso, e o gargalo é o engine ser 6,2× mais lento que o llama.cpp |

Medido no Edge 60 com `gte-reranker-modernbert-base` (Q8_0): **111 ms por par**,
NDCG@10 **0,9981**, logits de −0,1463 a +1,9235 (spread 2,0698), sigmoid
0,4635–0,8725.

**O que a triagem deixou de fora, e por quê.** Isto foi medido e é a parte que
evita a 0.4.1 de repetir o trabalho:

- **Laya** — `general.architecture = "ggmlc"`, que não está nos 152 nomes do
  llama.cpp vendorizado, e zero tensores `cls.*` em 153. A cabeça existe mas está
  em `ggmlc.graph_spec` com 5 inputs e 64 tensores (`act_head.0 [256, 1028]`,
  `act_head.2 [2, 256]`, `scorer.3 [1, 1024]`) — estruturalmente incompatível com
  o `mul_mat` de um vetor que `llama-graph.cpp:3722-3757` faz. Não é um bug de
  conversão, é outro modelo.
- **OpenJev** — Q8_0 tem 28,6 GB. Não é catalogue entry num telefone.
- **`gte-multilingual-reranker-base`** — tem a cabeça `[768]` perfeita e arch `new`,
  que não despacha. Arch válida **e** cabeça é o que carrega, nunca um dos dois.
- **Jina v1-tiny / v1-turbo, `lb-reranker-0.5B` (arch `qwen2`)** — pooling `NONE`
  sem cabeça de ranking; embeddam, não rerankeam.

`litert-community/Laya-English-LiteRT` traz TFLite pronto
(`laya_en_act_head_fp32.tflite`, `HOST_CONTRACT.md`) e era a rota da 0.4.1 — o APK
**não** tem interpretador TFLite hoje, só `liblitertlm_jni.so`, que é LiteRT-LM
generativo.

**A 0.4.1 nunca existiu** — nem tag nem release — e a reserva foi absorvida pela
0.5.0. Mas a feature **não** foi resolvida por isso, e a situação de agora é
melhor do que era: `/v1/classify` passou a servir **decision models** por um
caminho generativo, medido com Tev1-0.8B a 5 de 5. O Laya é um `.tflite` com uma
cabeça de classificação, não um modelo generativo, então ele continua precisando
do interpretador TFLite — é a única peça que falta, e é uma dependência, não uma
feature.

E a análise de Laya/OpenJev **não se aplica** a Tev1, o que vale dizer porque
"mesma categoria" costuma significar "mesmo motivo para estar de fora": o que
excluía Laya era `general.architecture = "ggmlc"` e **zero** tensores `cls.*`, e
o Tev1 é um `qwen35` comum que emite uma letra como token seguinte.

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
- **Status:** ✅ Feito (0.3.2) — guard contra duplicação, resumo incluído no history enviado ao motor, banner visual no chat.

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
