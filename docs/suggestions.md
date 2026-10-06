# Sugestões de Funcionalidades — mobileLM-app

**Data:** 2026-09-30  
**Versão atual:** 0.6.0+2009  
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
caminho generativo, medido com Tev1-0.8B a 5 de 5.

**E a peça que faltava está entregue e verificada.** O interpretador é o LiteRT
2.2.0 (`local_plugins/litert_flutter/`), medido no A72 nos dois backends com
diferença máxima de 2,98e-08 entre eles, e `/v1/classify` serve
`laya_en_act_head_fp32.tflite` — **159 ms** do clique ao logit, com
`features_input "pooled_cls"` e `auxiliary_used ["feats"]` nomeados na resposta.

O que **não** existe é o *host* completo do Laya, e continua fora do escopo
combinado: são 705 MB de grafo, uma tabela de embeddings de 98 MB com SHA256, o
tokenizer ModernBERT e a orquestração de dois grafos.

**Isto já foi escrito aqui como "cabe no Edge 60, não no A72", e está errado.**
São 804 MB de pesos contra um `maxModelBytes` de **1,19 GB** no A72 (25% de
`MemTotal` = 4,78 GB) — 68% do orçamento que o próprio app se dá. **O A72 nunca
foi excluído por memória.** O que seria caro é *cálculo*: um forward pass do
ModernBERT não é decode, o pinning de 4 threads que vale 2,8× para geração não
compensa aqui, e a resposta honesta é "segundos por passagem" — **uma
estimativa, não uma medição.** Argumento completo em
[`HANDOFF.md`](HANDOFF.md) §4.1.

O que separa "fora do escopo" de "não cabe" é que só o primeiro era verdade: o
interpretador já está no APK e já foi provado neste aparelho, então o host é
trabalho de orquestração em Dart, não uma questão de capacidade do telefone.

O console do `.tflite` faz a parte honesta disso — mostra o que o arquivo
diz de si mesmo, deixa você escolher o acelerador, e roda o endpoint — sem
inventar as features que só o host sabe produzir.

E a análise de Laya/OpenJev **não se aplica** a Tev1, o que vale dizer porque
"mesma categoria" costuma significar "mesmo motivo para estar de fora": o que
excluía Laya era `general.architecture = "ggmlc"` e **zero** tensores `cls.*`, e
o Tev1 é um `qwen35` comum que emite uma letra como token seguinte.

---

## ✅ Features completadas na versão 0.5.0 e 0.5.1

⚠️ **Estas duas não tinham seção aqui, e a lacuna é do mesmo tipo da que este
arquivo já cometia**: um documento de "features completadas por versão" que pula
duas versões produz uma lista de sugestões que parece mais do que está pronto. As
duas estão registradas agora, e o detalhe está em `AGENTS.md`.

| Release | Feature | Status | Arquivo principal |
|---|---|---|---|
| `0.5.0` | Pinning automático dos threads de cálculo nos núcleos grandes | ✅ Feito | `lib/utils/cpu_topology.dart` + `jni_wrapper.cpp` (`buildCpuSet`, `ggml_threadpool_new`, `llama_attach_threadpool`). Medido no A72: **6,5 → 18,0 tok/s**, e o ganho é de *utilização*, não de clock — `time_in_state` mostra o cluster quase sempre no piso nos dois casos |
| `0.5.0` | Benchmark de CPU corrigido | ✅ Feito | `measureGeneration` é melhor-de-N. A primeira run depois de abrir o processo deu **0,2 tok/s** e a segunda **17,4** — 87×, e a causa é o governor. `ttftMillis` usava o tempo total e `tokens` contava palavras: os dois bugs |
| `0.5.1` | A escada de aceleração passou a ver o tamanho do modelo | ✅ Feito | `acceleration.dart` — `auto_fast` mantém GGUF abaixo de 1280 MB na CPU. Medido: 1B Q4_0 na CPU 21,2 tok/s contra 3,4 na GPU. `n_gpu_layers==0` zera a lista de dispositivos, senão o ggml sched offloada para o Vulkan |

---

## ✅ Features completadas na versão 0.6.0 — *o idioma é escolhido, e o padrão é inglês*

**Minor porque a frase sai verdadeira: *antes não existia escolha de idioma*.**
Era `locale: Get.deviceLocale` com fallback `pt_BR`, e a consequência **medida**
foram **62 fichas de modelo em inglês numa tela que se dizia portuguesa**. Não é
minor "traduzir o app para inglês" — a 0.5.1 já tinha metade das chaves em
português, e traduzir não cria nada. O que cria é **a escolha**.

| Feature | Status | Arquivo principal |
|---|---|---|
| Seletor de idioma (Auto / English / Português (Brasil)) | ✅ Feito | `lib/services/language_preference.dart` (puro) + painel em Configurações → Aparência. **O padrão é `en`, não `auto`**: o GetX devolve a própria chave para uma tradução que não existe, e um idioma sem mapa inteiro renderiza 905 identificadores |
| Strings do Material nos dois idiomas | ✅ Feito | `flutter_localizations` + três delegates + `supportedLocales`. Sem a lista de locales o conserto **não pega** — foi o segundo `dump` do A72 que disse: `Settings` trocava, o botão `Back` não |
| Descrição do catálogo nos dois idiomas | ✅ Feito | `AiModel.descriptionEn`/`descriptionPt` — dois campos, **não** um que "significa português": com EN como padrão, um campo só publica português num app inglês **sem nenhum aviso** |
| `relevance_score` sem bug de detecção | ✅ Feito | Traduzir `'out of memory'` **fazia a detecção de falta de memória parar de casar**. `TextLanguage.naoTexto` (59 entradas, cada uma com motivo) + o teste que afirma o contrário da varredura |
| **Item 3e: 224 textos de tela traduzidos** | ✅ Feito | 148 literais diretos (`tool/rewrite_broad.dart`), 33 interpolados (`preencher`), 19 rótulos de faceta do hub. Mapa de **674 para 905 chaves**. **Fechado pelo aparelho**, não pelo contador |
| As duas varreduras de inglês em zero | ✅ Feito | `test/inline_english_ratchet_test.dart` com teto **0** em ambas — e o teto da ampla só pode ser zero **depois** do número medido chegar a zero, senão é um teste que passa pelo motivo errado |

**O que a 0.6.0 ensina, e é o que vale para a próxima:** a dívida de texto de tela
era de **duas ordens de grandeza** maior do que o `AGENTS.md` dizia, e a contagem
esteve errada **cinco vezes** — sempre porque a trava media **menos** do que
declarava (uma pasta faltando, um parâmetro faltando, uma letra faltando na
classe de regex). **Um detector que não casa é indistinguível de um detector que
não há**, e a defesa é sempre um teste irmão que prova que ainda vê alguma coisa.
O detalhe completo está em `AGENTS.md`, seção "Os literais de tela".

**Medido no A72, nos dois idiomas:** o seletor troca a tela na hora, sem
reiniciar; `Configurações`/`Settings` e `Aparência`/`Appearance` trocam juntas; e
o filtro do hub mostra `MODALITY`/`MODALIDADE` com `Any`/`Qualquer`,
`Vision`/`Visão`, `Mixture of Experts`/`Mistura de especialistas`,
`Quantisation`/`Quantização` — **e `Omni` é a mesma palavra nos dois idiomas**, o
que é o tipo de coisa que só se descobre conferindo o aparelho.

---

## Onde a fila está hoje

Os itens 1 a 5 desta lista **foram entregues** — 1, 3 e 5 na **0.3.1**, e está
registrado nas seções "✅" acima. Uma lista de sugestões que aponta para o que já
existe não está desatualizada, está **invertida**.

O estado datado, o que está medido e o próximo passo com protocolo estão em
[`HANDOFF.md`](HANDOFF.md). Resumido: a **hipótese da quantização**
(`Q4_K_M` contra `Q4_0` do mesmo modelo), os **4 `litertlm` restantes**, uma
**entrada de catálogo `.tflite`**, e só então a fila antiga de UI abaixo.

---

## 🟢 Baixo esforço, alto impacto

### 1. Exportar conversa ✅ entregue na 0.3.1
Compartilhar como texto, markdown ou PDF. Útil para salvar diagnósticos, respostas longas, ou enviar para outro lugar.
- **Esforço:** ~1h
- **Como:** `share_plus` já está no projeto; usar `DocumentExporter` simples
- **Priority:** Alta

### 2. Botão "copiar resposta" dedicado
❗ **não verificado.** A tabela da 0.3.1 lista três itens e este não é um deles —
já existia "copiar trecho". **Ninguém conferiu**, então treat como pendente até
provar na tela.

Já existe copiar trecho, mas um botão no bubble com "copiar tudo" seria rápido.
- **Esforço:** ~30 min
- **Como:** Adicionar ícone de cópia no `_streamBubble` e no `ChatBubble`
- **Priority:** Média

### 3. Sugestões rápidas (chips) após resposta
✅ **entregue na 0.3.1**

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
✅ **entregue na 0.3.1**

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

### 8. Benchmark comparativo de quantizações ⭐ **é o próximo passo**
Testar `Q4_0` vs `Q4_K_M` vs `Q8_0` **do mesmo modelo** e medir de verdade.

- **Esforço:** ~1h de download e medição. **Não** são 2-3h de tela.
- **Como:** `POST /v1/models/load` + `/v1/chat/completions` com streaming, pedidos
  consecutivos sem pausa, melhor de 3. Está pronto em `~/.cache/mobilelm-tools/`.
- **Prioridade:** **Alta** — este item estava marcado "Baixa" e é o mais
  importante da fila. Motivo: é o único que muda o advice para **36 dos 46**
  modelos do catálogo, e o advice atual está **comprovadamente errado** — o
  `AGENTS.md` diz que o menor modelo é o mais lento, e o menor do catálogo
  (SmolLM2 135M, 5,1 tok/s) é de fato o mais lento dos seis medidos.

**A ordem é medir primeiro, tela depois.** A tela dedicada (Settings > Modelos,
lado a lado) é o item **depois** deste, e só vale a pena se a medição mostrar que
a diferença importa — uma tela que compara três quantizações de um modelo que se
comporta igual é uma tela que ensina a não notar diferença.

**Pré-condição, verificada:** o catálogo **não tem** nenhuma família em duas
quantizações (`Q4_0` 11, `Q4_K_M` 12, `Q8_0` 1, nenhuma família repetida). O par
vem de fora do catálogo, do mesmo autor, para que a única variável seja a
quantização. Protocolo em [`HANDOFF.md`](HANDOFF.md) §5.

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
