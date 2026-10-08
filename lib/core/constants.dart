import 'package:flutter/widgets.dart';

class AppConstants {
  AppConstants._();

  // Hive Box Names
  static const String chatSessionsBox = 'chat_sessions';
  static const String chatMessagesBox = 'chat_messages';
  static const String tasksBox = 'tasks';
  static const String settingsBox = 'settings';

  // Settings Keys
  static const String keyInferenceMode = 'inference_mode'; // 'local' or 'cloud'
  static const String keyCloudProvider =
      'cloud_provider'; // 'openai', 'anthropic', 'google', 'kimi'
  static const String keyOpenaiKey = 'openai_api_key';
  static const String keyAnthropicKey = 'anthropic_api_key';
  static const String keyGoogleKey = 'google_api_key';
  static const String keyKimiKey = 'kimi_api_key';
  static const String keyStabilityKey = 'stability_api_key';
  static const String keyNvidiaKey = 'nvidia_api_key';
  static const String keyOpenRouterKey = 'openrouter_api_key';
  static const String keyDeepSeekKey = 'deepseek_api_key';
  static const String keyCustomCloudName = 'custom_cloud_name';
  static const String keyCustomCloudBaseUrl = 'custom_cloud_base_url';
  static const String keyCustomCloudKey = 'custom_cloud_api_key';
  static const String keyCustomCloudProfiles = 'custom_cloud_profiles';
  static const String keyCustomCloudProfileIndex = 'custom_cloud_profile_index';
  static const String keyOpenaiModel = 'openai_model';
  static const String keyAnthropicModel = 'anthropic_model';
  static const String keyGoogleModel = 'google_model';
  static const String keyKimiModel = 'kimi_model';
  static const String keyStabilityModel = 'stability_model';
  static const String keyNvidiaModel = 'nvidia_model';
  static const String keyOpenRouterModel = 'openrouter_model';
  static const String keyDeepSeekModel = 'deepseek_model';
  static const String keyCustomCloudModel = 'custom_cloud_model';
  static const String keyGlobalSystemPrompt = 'global_system_prompt';
  static const String keyLocalModelPath = 'local_model_path';
  static const String keyLocalModelName = 'local_model_name';
  static const String keyLocalModelRuntime = 'local_model_runtime';
  static const String keyLocalModelBackend = 'local_model_backend';
  static const String keyLiteRtPerformanceMode = 'litert_performance_mode';

  /// Whether the Models tab still offers to run the CPU self-test. False once
  /// the user dismisses the card. Separate from the result, which is a
  /// measurement and not a preference.
  static const String keyCpuSelfTestOffer = 'cpu_self_test_offer';

  /// When true, the Models tab shows only what is already on the device plus
  /// the online tab, and the whole download catalogue goes away. For someone who
  /// chats with a cloud model and never wants to manage local files: the list
  /// is 40 entries they will not download any of.
  static const String keyLocalCatalogueHidden = 'local_catalogue_hidden';

  /// Overrides the benchmark's advice. Off by default.
  ///
  /// The benchmark says "this phone is under 5 tok/s, cloud models will feel
  /// better" and offers to hide the local list. Hiding 40 models is a big
  /// change to make on the strength of one 24-token run, so the offer is
  /// declined by default and this flag is the permanent version of declining it
  /// — the user says once, in Settings, and the benchmark stops offering again
  /// for good.
  ///
  /// The advice is still shown. Suppressing the number because the user does not
  /// want the consequence would be the wrong trade: the measurement is the
  /// useful part, and the list is the part they get to decide about.
  static const String keyIgnoreBenchmarkAdvice =
      'show_models_ignore_benchmarks';
  static const String keyThinkingMode = 'thinking_mode';
  static const String keyToolsEnabled = 'tools_enabled';
  static const String keyEnabledTools = 'enabled_tools';
  static const String keyCustomSearchUrl = 'custom_search_url';
  static const String keyCustomSearchToken = 'custom_search_token';
  static const String keyLiteRtGpuWarningAccepted =
      'litert_gpu_warning_accepted';
  static const String keyLiteRtGpuLoadPending = 'litert_gpu_load_pending';
  static const String keyLiteRtGpuCrashDetected = 'litert_gpu_crash_detected';

  /// Routes `.litertlm` models through the Rust core (`libmobilelm_core.so`)
  /// instead of the Kotlin plugin.
  ///
  /// **Defaults to off, and that is a decision, not an omission.** The Rust path is
  /// the claim 0.4.0 makes, and the claim is not earned until it has been run
  /// beside the plugin on the same phone, same model, same prompt. Until then the
  /// default is the path that has been generating for months, and this switch is
  /// how the comparison gets made. It flips to on in the same commit that deletes
  /// the plugin — after the numbers are in `docs/BENCH.md`, not before.
  ///
  /// Off is also the safe state on a device whose runtime the core cannot use: the
  /// Rust attempt fails at load and the load falls through to the plugin, so a bad
  /// runtime costs a few seconds of load time rather than an unusable model.
  /// Per-model Auto Fast benchmark verdicts. Key = prefix + 'name:bytes',
  /// value = 'cpu' | 'gpu'. Measured once, reused on every later load.
  static const String autoFastBenchKeyPrefix = 'auto_fast_bench_';

  /// Set once, for the whole device, when a GPU that registered and reported a
  /// layer count then refused the model at `llama_model_load` with
  /// "Unsupported device". Per device and not per model on purpose: a backend
  /// that cannot host one GGUF is not going to host the next one, and the probe
  /// that discovers it is itself what puts the driver in the process. Measured
  /// on a Galaxy A72 — see the Auto Fast fallback in `inference_android.dart`.
  static const String gpuLoadFailedKey = 'gpu_load_failed';
  /// Same scheme for the vision projector backend ('cpu' | 'gpu').
  static const String visionBenchKeyPrefix = 'vision_bench_';
  static const String keyImageModelPath = 'image_model_path';
  static const String keyImageModelName = 'image_model_name';
  static const String keyTemperature = 'temperature';
  static const String keyMaxTokens = 'max_tokens';
  static const String keyContextSize = 'context_size';

  // Per-role encoder parameters. Each is nullable and a null means "ask the
  // model" — see `EncoderSettingsService` for why these are not defaults.
  static const String keyEmbedQueryPrefix = 'embed_query_prefix';
  static const String keyEmbedPassagePrefix = 'embed_passage_prefix';
  static const String keyEmbedNormalize = 'embed_normalize';
  static const String keyRerankTopN = 'rerank_top_n';
  static const String keyRerankReturnDocuments = 'rerank_return_documents';
  static const String keyRerankSigmoid = 'rerank_sigmoid';
  static const String keyRerankDocumentSeparator = 'rerank_document_separator';
  static const String keyEncoderMaxInputTokens = 'encoder_max_input_tokens';
  static const String keyScheduledTaskNotifications = 'scheduled_task_notifications';
  static const String keyServerApiKey = 'server_api_key';
  static const String keyServerUseApiKey = 'server_use_api_key';
  static const String keyServerPort = 'server_port';
  /// The port the local API server listens on when the user has not chosen one.
  ///
  /// 8091, not the 8080 that every OpenAI-compatible server in the world uses —
  /// which is exactly why it is a bad default on a phone. 8080 is the first port
  /// anybody reaches for, so it is the one already taken: by a Syncthing on one
  /// device, by a Bifrost gateway on the development host, and by whatever else
  /// the person running this has on their machine. A default that collides is a
  /// default that costs every user a port-collision dance, and the collision
  /// handler here is a silent walk up to the next free port, so the cost is not
  /// even visible as an error.
  ///
  /// This is only the *default*. A port the user set is stored in Hive under
  /// [keyServerPort] and always wins, so nobody who already chose one sees this
  /// change. The single source of truth for the number lives here;
  /// `ServerController` reads it rather than keeping a second copy.
  static const int defaultServerPort = 8091;
  static const String keyImageSteps = 'image_steps';
  static const String keyImageGenForceCpu = 'image_gen_force_cpu';
  /// CPU threads for llama.cpp. 0 means "half the cores".
  static const String keyCpuThreads = 'cpu_threads';
  static const String keyMmprojForceCpu = 'mmproj_force_cpu';
  static const String keyImageGenBackend = 'image_gen_backend';
  static const String keyImageGenGpuGuardMb = 'image_gen_gpu_guard_mb';
  static const String keyImageGenSize = 'image_gen_size';
  static const String keyImageGenQuantization = 'image_gen_quantization';
  /// Idioma da interface: `auto` | `en` | `pt_BR`.
  ///
  /// O default **não** é `auto`. Ver `LanguagePreference.padrao` e o porquê no
  /// `AGENTS.md` — a versão curta é que um idioma deduzido é o que produziu
  /// 62 descrições em inglês numa tela que se dizia portuguesa.
  static const String keyLanguage = 'language';
  static const String keyFontScale = 'font_scale';
  static const String keyTopP = 'top_p';
  static const String keyTopK = 'top_k';
  static const String keyMinP = 'min_p';
  static const String keyRepeatPenalty = 'repeat_penalty';
  /// Per-model parameter overrides captured from GGUF metadata.
  static const String modelParamsKeyPrefix = 'model_params_';
  /// Persisted SAF tree URI for the models backup destination.
  static const String keyBackupTreeUri = 'backup_tree_uri';

  /// Persisted SAF tree URI for the workspace root, chosen once during first
  /// launch and relocateable later from Settings.
  static const String keyWorkspaceTreeUri = 'workspace_tree_uri';

  /// The last project the user chose through the picker, so a new conversation
  /// starts there after a cold start.
  ///
  /// Without it the workspace was only in memory: `loadSessions()` loads the
  /// list and opens nothing, so `ChatController.currentProjectPath` was null
  /// until a conversation was opened, and the first new conversation after a
  /// restart asked which project to use. The tile said the choice was
  /// remembered — the inheritance was real, it just did not survive a restart.
  static const String keyLastProjectName = 'last_project_name';

  // Default Model Config
  static const double defaultTemperature = 0.20;
  static const int defaultMaxTokens = 1024;
  static const int defaultContextSize = 4096;
  static const String defaultLiteRtPerformanceMode = 'auto_fast';

  /// Hard context ceiling for LiteRT models: the GPU driver OOMs above it.
  /// inference_service clamps the dialog value to this; the model card
  /// states it, because .litertlm headers carry no context field of their own.
  static const int liteRtContextCap = 4096;

  /// A sentinela de "o tamanho não se resolve", e **o valor é uma string em
  /// inglês de propósito**.
  ///
  /// Ela viaja por três caminhos que são comparação, não pintura:
  /// `detectUrlSize` a devolve, quem chama compara com `==`, e `AiModel.size`
  /// a guarda no Hive. Traduzir a string faria a comparação parar de casar, e o
  /// sintoma não seria um texto errado na tela — seria um `Unknown size` do
  /// runtime caindo na frase de erro genérica.
  ///
  /// **O valor continua sendo pintado em um lugar só**, e é por isso que a
  /// sentinela é nomeada em vez de o texto ser traduzido: `Text(model.size)`
  /// precisa dizer alguma coisa quando o campo é este, e o campo **é** o valor.
  /// Um literal solto não separa "comparei com isto" de "isto vai para a tela",
  /// e é essa separação que a varredura de texto de tela não conseguia fazer.
  /// Ver `mv_size_unknown` no mapa de tradução, que é o único ponto de pintura.
  static const String kUnknownSize = 'Unknown size';

  /// 'auto' leaves the model to its own habits; 'on'/'off' send the soft switch.
  static const String defaultThinkingMode = 'auto';

  /// On by default with the offline trio plus the two web tools pre-ticked.
  static const bool defaultToolsEnabled = true;

  /// Which tools are ticked when the user first turns tools on. The offline
  /// three only — a local-first app does not reach the network by default.
  /// Only the network pair ships enabled: they are the tools a chat model
  /// actually needs, and each one is individually reviewable. Everything else
  /// waits for an explicit opt-in in Settings.
  static const List<String> defaultEnabledTools = [
    'web_search',
    'read_url',
    'list_files',
    'read_file',
    'create_file',
    'write_file',
    'delete_file',
    'rename_file',
  ];

  static const String keyAgentMaxHops = 'agent_max_hops';

  /// Tool round-trips per message. 1 = the classic single hop (a small model
  /// handed its own tool output loops forever); the agent toggle raises it.
  static const int defaultAgentMaxHops = 1;
  static const int maxAgentHopsCap = 8;

  /// Where `agentMaxHops == 0` actually stops.
  ///
  /// **Zero cannot mean "no limit", and pretending it does is a hang.** The
  /// setting is documented as infinite, the UI shows `∞`, and the loop was
  /// `while (hop < maxHops)` — so picking 0 gave the user **zero** tool calls and
  /// a Settings tile that said otherwise. The label was not the bug; the loop
  /// was, and this is the number it needed.
  ///
  /// 50 is chosen from what a hop costs, not from taste. Each one is a full
  /// generation: on the A72's 5 tok/s models a hop runs tens of seconds, so 50
  /// is minutes of visible work and not a silent stall; against a tool that
  /// loops (a model re-reading its own output and calling again) it is the
  /// difference between a message that ends and one that never does. It is
  /// above the 20 cloud models are held to, because cloud's 20 is about credits
  /// and this is about a spinner.
  ///
  /// A number here is still a ceiling, so the UI's `∞` is the *user's* intent and
  /// this is the app's. When it is this one that stops the loop, the message says
  /// so — see `agent_hops.dart`.
  static const int agentHopBackstop = 50;
  static const int defaultImageSteps = 8;
  static const bool defaultImageGenForceCpu = true;
  /// 0 = half the cores. See the thread-tuning note in inference_android.dart.
  static const int defaultCpuThreads = 0;
  /// Default true: measured on a Mali-G615, encoding one image took 197s with
  /// the projector on the GPU against 84s on four CPU threads. ggml-vulkan
  /// falls back per-op for the ViT, so the "GPU" path spends its time copying
  /// tensors. Switchable in Settings, because this is a per-driver fact.
  static const bool defaultMmprojForceCpu = true;
  static const int defaultImageGenGpuGuardMb = 2048; // 2 GB — no warning at this value
  static const int defaultImageGenSize = 0; // 0 = Auto recommended
  static const double defaultFontScale =
      1.10; // first slider stop labelled "Large" — the new out-of-box size

  // System Prompt (compact for small context models) — same default as OGAM.
  static const String systemPrompt =
      '''You are a helpful AI assistant running locally on the user's device. Your responses should be:
- Accurate and factual - never make up information
- Concise but complete - answer the question fully without unnecessary elaboration
- Helpful and friendly - focus on solving the user's actual need
- Honest about limitations - if you don't know something, say so

If asked about yourself, you can mention you're a local AI assistant that prioritizes user privacy.''';

  static const String systemPromptPT =
      '''Você é um assistente de IA útil que roda localmente no dispositivo do usuário. Suas respostas devem ser:
- Precisas e factuais - nunca invente informações
- Concisas mas completas - responda a pergunta totalmente sem elaboração desnecessária
- Úteis e simpáticas - foque em resolver a necessidade real do usuário
- Honestas sobre limitações - se não souber algo, diga

Se perguntado sobre você mesmo, pode mencionar que é um assistente de IA local que prioriza a privacidade do usuário.''';

  /// Returns system prompt in the appropriate language based on device locale.
  static String get localizedSystemPrompt {
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    if (locale != null && (locale.languageCode == 'pt' || locale.countryCode == 'BR')) {
      return systemPromptPT;
    }
    return systemPrompt;
  }
  // System Prompt for Uncensored Models
  static const String uncensoredSystemPrompt =
      '''You are mobileLM running with an uncensored local model. Be direct, mature, and conversational. Avoid moralizing or unnecessary disclaimers, but keep answers accurate and do not help with real-world harm, abuse, or illegal activity.''';

  static bool isUncensoredModelName(String value) {
    final lower = value.toLowerCase();
    return lower.contains('uncensored') ||
        lower.contains('abliterated') ||
        lower.contains('unrestricted') ||
        lower.contains('dolphin');
  }

  // Available Models for Download
  //
  // ── Encoders ────────────────────────────────────────────────────────────────
  // Every entry below was screened with `tool/gguf-screen.py` before it was
  // written here, which reads the GGUF header over a range request and answers
  // what the app will answer after a 450 MB download. That is not a nicety: a
  // model can load, occupy the screen and produce nothing, and there is no other
  // symptom. `jina-reranker-v1-tiny-en` is 36 MB, half a second to load, and has
  // no output at all — its conversion put the head at `cls.weight` where
  // llama.cpp looks for `cls.output`, and dropped the `pooler.dense` the head was
  // trained against. Its own `general.tags` still say `reranker`.
  //
  // The screen checks two things, and the second is not optional:
  //   1. `cls.output.weight` is present — without it there is no logit, and
  //      llama.cpp hands back one float of a pooled hidden state instead, which
  //      is a number in (-1, 1) that ranks plausibly and means nothing.
  //   2. `general.architecture` is one the vendored llama.cpp knows. This is what
  //      rejects `laya_english_q8_0` (architecture `ggmlc`) and
  //      `gte-multilingual-reranker-base` (`new`) — the second of which carries a
  //      perfect `[768]` head and still does not load, which is the case a
  //      head-only check would wave through.
  //
  // Sizes are the `content-length` of the URL as checked on 2026-09-28, not the
  // hub's rounded display size.
  //
  // `role` is declared here, on purpose. The app already has a role for every
  // model — `LlamaEncoder` reports one from the loaded file's own tensors — and
  // the temptation is to sort the menu off the filename. That is how
  // `bge-small-en-v1.5` became a "classifier" once: the name does not carry the
  // architecture, and the app's own rule (`pooling == 'rank'` and `nClsOut > 1`)
  // is the only one that does. A curated list is a place to assert what is known
  // at curation time from the screened file, which is a different and stronger
  // claim than what can be guessed from a name.
  static const List<Map<String, String>> encoderModels = [
    // ── rerankers: a query scored against documents ──────────────────────────
    {
      'role': 'rerank',
      'name': 'GTE Reranker ModernBERT Base (Q4_K_M)',
      'filename': 'gte-reranker-modernbert-base-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/jolleyboy/gte-reranker-modernbert-base-GGUF/resolve/main/gte-reranker-modernbert-base-Q4_K_M.gguf',
      'size': '101.4 MB',
      'descriptionEn':
          
          'Cross-encoder reranker, ModernBERT, Portuguese and English. '
          'Measured on an Edge 60 at 111 ms per query with a real logit '
          'spread of 2,07. The one to start with.',
          'descriptionPt':
'Reranker cross-encoder, ModernBERT, português e inglês. Medido num '
          'Edge 60 a 111 ms por consulta, com um spread de logit real de '
          '2,07. É o ponto de partida.',
      'template': 'modern-bert',
      'runtime': 'llama',
    },
    {
      'role': 'rerank',
      'name': 'GTE Reranker ModernBERT Base (Q8_0)',
      'filename': 'gte-reranker-modernbert-base-Q8_0.gguf',
      'url':
          'https://huggingface.co/keisuke-miyako/gte-reranker-modernbert-base-gguf-q8_0/resolve/main/gte-reranker-modernbert-base-Q8_0.gguf',
      'size': '153.4 MB',
      'descriptionEn':
          
          'The same reranker in Q8_0, for when the last 0,2 of the NDCG is '
          'worth 54 MB. Verified end to end on an Edge 60.',
          'descriptionPt':
'O mesmo reranker em Q8_0, para quando os últimos 0,2 de NDCG '
          'valham os 54 MB. Verificado de ponta a ponta num Edge 60.',
      'template': 'modern-bert',
      'runtime': 'llama',
    },
    {
      'role': 'rerank',
      'name': 'BGE Reranker Base (Q8_0)',
      'filename': 'bge-reranker-base-Q8_0.gguf',
      'url':
          'https://huggingface.co/xinming0111/bge-reranker-base-Q8_0-GGUF/resolve/main/bge-reranker-base-q8_0.gguf',
      'size': '289.7 MB',
      'descriptionEn':
          
          'Cross-encoder reranker, BERT architecture, English. The head and '
          'the pooler projection are both in the file, which is the check '
          'that matters.',
          'descriptionPt':
'Reranker cross-encoder, arquitetura BERT, inglês. A cabeça e a '
          'projeção do pooler estão ambas no arquivo — é essa a verificação '
          'que importa.',
      'template': 'bert',
      'runtime': 'llama',
    },
    {
      'role': 'rerank',
      'name': 'BCE Reranker Base v1 (Q4_K_M)',
      'filename': 'bce-reranker-base_v1-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/jfiekdjdk/bce-reranker-base_v1-Q4_K_M-GGUF/resolve/main/bce-reranker-base_v1-q4_k_m.gguf',
      'size': '208.9 MB',
      'descriptionEn':
          
          'Cross-encoder reranker, BERT, English and Chinese. Well formed: '
          'cls.output.weight [768] with the 768x768 pooler beside it.',
          'descriptionPt':
'Reranker cross-encoder, BERT, inglês e chinês. Bem formado: '
          'cls.output.weight [768] com o pooler 768x768 ao lado.',
      'template': 'bert',
      'runtime': 'llama',
    },
    // ── embeddings: text to one vector ──────────────────────────────────────
    {
      'role': 'embed',
      'name': 'Multilingual E5 Small (Q8_0)',
      'filename': 'multilingual-e5-small-Q8_0.gguf',
      'url':
          'https://huggingface.co/keisuke-miyako/multilingual-e5-small-gguf-q8_0/resolve/main/multilingual-e5-small-Q8_0.gguf',
      'size': '125.8 MB',
      'descriptionEn':
          
          'Embeds in 100 languages including Portuguese, mean-pooled. The one '
          'to reach for on a pt_BR device — a purely English embedder makes '
          'Portuguese search quietly bad.',
          'descriptionPt':
'Embeda em 100 idiomas, incluindo português, com mean-pooling. O '
          'primeiro a escolher num aparelho pt_BR — um embedder só em inglês '
          'degrada a busca em português sem fazer barulho.',
      'template': 'bert',
      'runtime': 'llama',
    },
    {
      'role': 'embed',
      'name': 'BGE Small EN v1.5 (F16)',
      'filename': 'bge-small-en-v1.5-f16.gguf',
      'url':
          'https://huggingface.co/unsloth/bge-small-en-v1.5-GGUF/resolve/main/bge-small-en-v1.5-f16.gguf',
      'size': '64.5 MB',
      'descriptionEn':
          
          'Smallest usable embedder: 33M parameters, 384 dimensions, CLS '
          'pooling. Verified on an Edge 60.',
          'descriptionPt':
'O menor embedder utilizável: 33M de parâmetros, 384 dimensões, '
          'pooling CLS. Verificado num Edge 60.',
      'template': 'bert',
      'runtime': 'llama',
    },
    {
      'role': 'embed',
      'name': 'BGE Small EN v1.5 (Q8_0)',
      'filename': 'bge-small-en-v1.5-Q8_0.gguf',
      'url':
          'https://huggingface.co/ggml-org/bge-small-en-v1.5-Q8_0-GGUF/resolve/main/bge-small-en-v1.5-q8_0.gguf',
      'size': '35.0 MB',
      'descriptionEn':
          
          'The same 33M embedder in Q8_0 — half the bytes of F16 for a '
          '384-float vector, where the quantisation is nearly free.',
          'descriptionPt':
'O mesmo embedder de 33M em Q8_0 — metade dos bytes do F16 para um '
          'vetor de 384 floats, onde a quantização é quase de graça.',
      'template': 'bert',
      'runtime': 'llama',
    },
    {
      'role': 'embed',
      'name': 'E5 Small v2 (Q8_0)',
      'filename': 'e5-small-v2-Q8_0.gguf',
      'url':
          'https://huggingface.co/ggml-org/e5-small-v2-Q8_0-GGUF/resolve/main/e5-small-v2-q8_0.gguf',
      'size': '35.0 MB',
      'descriptionEn':
          
          'Small mean-pooled embedder, English, 384 dimensions. Needs "query: '
          '" and "passage: " prefixes on the two sides, as every E5 does.',
          'descriptionPt':
'Embedder pequeno com mean-pooling, inglês, 384 dimensões. Precisa '
          'dos prefixos "query: " e "passage: " nos dois lados, como todo E5.',
      'template': 'bert',
      'runtime': 'llama',
    },
    {
      'role': 'embed',
      'name': 'Nomic Embed Text v1.5 (Q4_K_M)',
      'filename': 'nomic-embed-text-v1.5-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q4_K_M.gguf',
      'size': '80.2 MB',
      'descriptionEn':
          
          'Long-context embedder, 8k, mean-pooled, 768 dimensions. The only '
          'screened option that embeds a whole document in one pass.',
          'descriptionPt':
'Embedder de contexto longo, 8k, com mean-pooling, 768 dimensões. A '
          'única opção testada que embeda um documento inteiro numa passada.',
      'template': 'nomic-bert',
      'runtime': 'llama',
    },
    {
      'role': 'embed',
      'name': 'ModernBERT Embed Base (Q8_0)',
      'filename': 'modernbert-embed-base-Q8_0.gguf',
      'url':
          'https://huggingface.co/keisuke-miyako/modernbert-embed-base-gguf-q8_0/resolve/main/modernbert-embed-base-Q8_0.gguf',
      'size': '152.8 MB',
      'descriptionEn':
          
          'ModernBERT embedder, mean-pooled, 768 dimensions. The same '
          'architecture as the reranker above, so it is worth having both to '
          'see the difference a scoring head makes.',
          'descriptionPt':
'Embedder ModernBERT, com mean-pooling, 768 dimensões. A mesma '
          'arquitetura do reranker acima, então vale ter os dois para ver a '
          'diferença que uma cabeça de pontuação faz.',
      'template': 'modern-bert',
      'runtime': 'llama',
    },
    // ── the second wave, screened 2026-09-28 ──────────────────────────────
    // Every entry here needed no code change to work, which is a much
    // stronger claim than "was found", and it is the reason these six are in
    // the catalogue while `Qwen3-Reranker-0.6B` and the two mxbai rerankers
    // are not. Those three are the same models minus their `cls.output.weight`,
    // and a reranker with no head loads, occupies the screen, and then
    // returns nothing at all.
    {
      'role': 'rerank',
      'name': 'BGE Reranker v2 M3 (Q4_K_M)',
      'filename': 'bge-reranker-v2-m3-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/gpustack/bge-reranker-v2-m3-GGUF/resolve/main/bge-reranker-v2-m3-Q4_K_M.gguf',
      'size': '418.1 MB',
      'descriptionEn':
          
          '568M, multilingual, arch bert. Carries both cls.output.weight and '
          'pooler, and that pair is what decides whether a score is a score — '
          'the jina v1 file above has the head without the pooler and returns '
          'a number in (-1,1) that ranks plausibly. Twice the size of the BGE '
          'Reranker Base and multilingual, which on a pt_BR phone is the part '
          'that matters.',
          'descriptionPt':
'568M, multilíngue, arch bert. Tem cls.output.weight e pooler, e é '
          'esse par que decide se uma pontuação é uma pontuação — o arquivo '
          'jina v1 acima tem a cabeça sem o pooler e devolve um número em '
          '(-1,1) que ordena de forma plausível. O dobro do tamanho do BGE '
          'Reranker Base, e multilíngue, que num aparelho pt_BR é a parte que '
          'importa.',
      'template': 'bert',
      'runtime': 'llama',
    },
    {
      'role': 'rerank',
      'name': 'BGE Reranker v2 M3 (Q2_K)',
      'filename': 'bge-reranker-v2-m3-Q2_K.gguf',
      'url':
          'https://huggingface.co/gpustack/bge-reranker-v2-m3-GGUF/resolve/main/bge-reranker-v2-m3-Q2_K.gguf',
      'size': '349.5 MB',
      'descriptionEn':
          
          'The same reranker in Q2_K: 69 MB cheaper for a quantisation that '
          'costs a little ordering rather than the shape of the answer.',
          'descriptionPt':
'O mesmo reranker em Q2_K: 69 MB a menos por uma quantização que '
          'custa um pouco de ordenação, e não a forma da resposta.',
      'template': 'bert',
      'runtime': 'llama',
    },
    {
      'role': 'rerank',
      'name': 'Jina Reranker v2 Base Multilingual (Q4_K_M)',
      'filename': 'jina-reranker-v2-base-multilingual-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/gpustack/jina-reranker-v2-base-multilingual-GGUF/resolve/main/jina-reranker-v2-base-multilingual-Q4_K_M.gguf',
      'size': '212.1 MB',
      'descriptionEn':
          
          '278M, arch bert, head and pooler both present. The smallest '
          'reranker here that returns a real logit — and it is the v2 of a '
          'family whose v1 is in this catalogue and does not work, so the '
          'version in the name is the entire difference.',
          'descriptionPt':
'278M, arch bert, cabeça e pooler presentes. O menor reranker aqui '
          'que devolve um logit de verdade — e é o v2 de uma família cujo v1 '
          'está neste catálogo e não funciona, então a versão no nome é toda '
          'a diferença.',
      'template': 'bert',
      'runtime': 'llama',
    },
    {
      'role': 'rerank',
      'name': 'Qwen3 Reranker 4B (Q4_K_M)',
      'filename': 'Qwen3-Reranker-4B-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/Voodisss/Qwen3-Reranker-4B-GGUF-llama_cpp/resolve/main/Qwen3-Reranker-4B-Q4_K_M.gguf',
      'size': '2.4 GB',
      'descriptionEn':
          
          'The strongest reranker screened, and the first qwen3 the app '
          'treats as an encoder. It declares its own pooling_type=rank and '
          'carries cls.output.weight [2560, 2] with yes/no labels — the head '
          'llama.cpp loads for LLM_ARCH_QWEN3. Unmeasured: every number this '
          'catalogue quotes is the ModernBERT above, and a qwen3 has never '
          'run here.',
          'descriptionPt':
'O reranker mais forte que passou na triagem, e o primeiro qwen3 '
          'que o app trata como encoder. Declara o próprio pooling_type=rank '
          'e traz cls.output.weight [2560, 2] com rótulos sim/não — a cabeça '
          'que o llama.cpp carrega para LLM_ARCH_QWEN3. Sem medir: todos os '
          'números que este catálogo cita são do ModernBERT acima, e um qwen3 '
          'nunca rodou aqui.',
      'template': 'qwen3',
      'runtime': 'llama',
    },
    {
      'role': 'rerank',
      'name': 'Qwen3 Reranker 4B (Q2_K)',
      'filename': 'Qwen3-Reranker-4B-Q2_K.gguf',
      'url':
          'https://huggingface.co/Voodisss/Qwen3-Reranker-4B-GGUF-llama_cpp/resolve/main/Qwen3-Reranker-4B-Q2_K.gguf',
      'size': '1.7 GB',
      'descriptionEn':
          
          'The same 4B reranker in Q2_K: 2,4 GB becomes 1,7 GB. The size is '
          'what decides this one, and 4B is already the top of the range this '
          'app is aimed at.',
          'descriptionPt':
'O mesmo reranker de 4B em Q2_K: 2,4 GB viram 1,7 GB. O tamanho é o '
          'que decide este, e 4B já é o topo da faixa que este app atende.',
      'template': 'qwen3',
      'runtime': 'llama',
    },
    {
      'role': 'embed',
      'name': 'Qwen3 Embedding 0.6B (Q8_0)',
      'filename': 'Qwen3-Embedding-0.6B-Q8_0.gguf',
      'url':
          'https://huggingface.co/Qwen/Qwen3-Embedding-0.6B-GGUF/resolve/main/Qwen3-Embedding-0.6B-Q8_0.gguf',
      'size': '609.5 MB',
      'descriptionEn':
          
          'Published by Qwen itself. Arch qwen3, declares pooling_type=last, '
          '1024 dimensions. The only embedder here that is a decoder rather '
          'than a BERT, and the one that reads a whole document in a single '
          'pass — which is the actual argument for it over the 80 MB Nomic '
          'above.',
          'descriptionPt':
'Publicado pelo próprio Qwen. Arch qwen3, declara '
          'pooling_type=last, 1024 dimensões. O único embedder aqui que é um '
          'decoder em vez de um BERT, e o que lê um documento inteiro numa '
          'única passada — que é o argumento real a favor dele contra o Nomic '
          'de 80 MB acima.',
      'template': 'qwen3',
      'runtime': 'llama',
    },
  ];

  static const List<Map<String, String>> availableModels = [
    {
      'name': 'Qwen 3 0.6B (LiteRT-LM)',
      'filename': 'Qwen3-0.6B.litertlm',
      'url':
          'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
      'size': '586 MB',
      'descriptionEn':
          
          'Smallest LiteRT-LM general-purpose chat model for low-RAM phones',
          'descriptionPt':
'O menor modelo de chat LiteRT-LM de uso geral, para aparelhos com '
          'pouca RAM',
      'template': 'litert',
      'runtime': 'litert',
    },
    {
      'name': 'Qwen 2.5 1.5B Instruct (LiteRT-LM)',
      'filename': 'Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
      'url':
          'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
      'size': '1.49 GB',
      'descriptionEn':
           'Balanced LiteRT-LM chat model with int8 quantization',
          'descriptionPt':
'Modelo de chat LiteRT-LM equilibrado, com quantização int8',
      'template': 'litert',
      'runtime': 'litert',
    },
    {
      'name': 'DeepSeek R1 Distill Qwen 1.5B (LiteRT-LM)',
      'filename':
          'DeepSeek-R1-Distill-Qwen-1.5B_multi-prefill-seq_q8_ekv4096.litertlm',
      'url':
          'https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B_multi-prefill-seq_q8_ekv4096.litertlm',
      'size': '1.71 GB',
      'descriptionEn':
           'Reasoning-focused LiteRT-LM model with int8 quantization',
          'descriptionPt':
'Modelo LiteRT-LM voltado a raciocínio, com quantização int8',
      'template': 'litert',
      'runtime': 'litert',
    },
    // These four were "Quantisation-aware": the weights were trained knowing
    // they would end up 4-bit, and vendors name the recipe differently — Google
    // says QAT, Liquid says QAD. The idea is sound and the files are smaller
    // than a post-training quant of the same size.
    //
    // They do not work here. Measured on a Galaxy A72 (SM-A725M, Snapdragon
    // 720G, /e/OS 4.3 A15): the LFM2.5-230M in its official QAD-Q4_0 file loads,
    // prefills at 263 tok/s, and then emits 24 consecutive token id 0 — which
    // that GGUF declares as tokenizer.ggml.padding_token_id, not as its EOS
    // (7). It answers nothing, and the answer looks like a slow phone.
    //
    // It is the file, not the build and not the device. Same model, same repo,
    // 128 bytes apart in metadata, as a plain Q4_0: real text. As Q4_K_M: real
    // text, 3.9 tok/s. Built with GGML_CPU_ALL_VARIANTS OFF to take the Q4_0
    // out of the ARM dot-product repack entirely, on the same ordinary kernels
    // Q4_K already used: still 24 pads. The repack was innocent — the weights
    // are wrong whichever kernel path reads them. This is the same shape as the
    // "ARM-optimized" GGUFs already noted for this vendored llama.cpp: it fails
    // on every device, and a 404 is not the only way a URL can be wrong.
    //
    // So: plain Q4_0, which is the layout llama.cpp does repack for ARM
    // dot-product, and therefore the fastest 4-bit path on a phone. Do not put
    // another QAT/QAD entry in without running it first and reading the sampled
    // token ids out of app.log — a model that answers nothing still reports a
    // plausible tok/s, because the sampler is working fine on garbage weights.
    {
      'name': 'LFM2.5 230M (Q4_0)',
      'filename': 'LFM2.5-230M-Q4_0.gguf',
      'url':
          'https://huggingface.co/LiquidAI/LFM2.5-230M-GGUF/resolve/main/LFM2.5-230M-Q4_0.gguf',
      'size': '0.14 GB',
      'descriptionEn':
          
          'Smallest model here — runs on anything. The benchmark model, so it '
          'has to be one that answers: see the QAT/QAD note above',
          'descriptionPt':
'O menor modelo da lista — roda em qualquer aparelho. É o modelo do '
          'benchmark, então precisa ser um que responda: ver a nota de '
          'QAT/QAD acima',
      'template': 'chatml',
      'runtime': 'llama',
      'benchmark': 'true',
    },
    {
      // The floor of the catalogue, and the reason the benchmark works. 135M
      // parameters, 105 MB, and on a Galaxy A72 (two A76) the prefill is a
      // rounding error rather than a budget problem. Kept even though it is
      // worse at conversation than the 230M: a self-test has to be cheap enough
      // to always pass, or it stops being a self-test and starts being a second
      // way to fail.
      'name': 'SmolLM2 135M (Q4_K_M)',
      'filename': 'SmolLM2-135M-Instruct-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/bartowski/SmolLM2-135M-Instruct-GGUF/resolve/main/SmolLM2-135M-Instruct-Q4_K_M.gguf',
      'size': '0.10 GB',
      'descriptionEn':
          
          'The smallest thing here that still speaks, and the next candidate '
          'for the CPU benchmark — lighter than the 230M, but not the '
          'benchmark yet because the pass/fail thresholds are calibrated '
          'against the 230M on a Galaxy A72, and those need re-measuring '
          'before they describe this model',
          'descriptionPt':
'O menor que ainda responde, e o candidato mais leve para o '
          'benchmark de CPU — mais leve que o 230M, mas ainda não é o '
          'benchmark porque os limiares de aprovação foram calibrados contra '
          'o 230M num Galaxy A72, e precisam ser remedidos antes de valer '
          'para este modelo',
      'template': 'chatml',
      'runtime': 'llama',
    },
    {
      'name': 'LFM2.5 350M (Q4_0)',
      'filename': 'LFM2.5-350M-Q4_0.gguf',
      'url':
          'https://huggingface.co/LiquidAI/LFM2.5-350M-GGUF/resolve/main/LFM2.5-350M-Q4_0.gguf',
      'size': '0.20 GB',
      'descriptionEn':
           '4-bit, tuned for edge devices',
          'descriptionPt':
'4 bits, ajustado para aparelhos de borda',
      'template': 'chatml',
      'runtime': 'llama',
    },
    {
      'name': 'LFM2.5 1.2B Instruct (Q4_0)',
      'filename': 'LFM2.5-1.2B-Instruct-Q4_0.gguf',
      'url':
          'https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_0.gguf',
      'size': '0.65 GB',
      'descriptionEn':
          
          '4-bit. Multilingual, and the sweet spot for most phones',
          'descriptionPt':
'4 bits. Multilíngue, e o ponto ideal para a maioria dos aparelhos',
      'template': 'chatml',
      'runtime': 'llama',
    },
    {
      'name': 'LFM2.5 2.6B (Q4_0)',
      'filename': 'LFM2.5-2.6B-Q4_0.gguf',
      'url':
          'https://huggingface.co/LiquidAI/LFM2.5-2.6B-GGUF/resolve/main/LFM2.5-2.6B-Q4_0.gguf',
      'size': '1.48 GB',
      'descriptionEn':
           '4-bit, the largest LFM2.5 that still fits comfortably',
          'descriptionPt':
'4 bits, o maior LFM2.5 que ainda cabe com folga',
      'template': 'chatml',
      'runtime': 'llama',
    },
    // LFM2.5-VL — the vision-language half of the same family. Liquid AI ships
    // the projector only as Q8_0 (or worse), so the vision floor is set by the
    // projector, not the weights: 450M costs 98 MB of projector, 1.6B and 3B
    // both cost 556 MB of the same one.
    //
    // Every URL and size below was read from the Hugging Face API on 2026-09-27,
    // not copied from a model card. Re-check with
    //   curl -sI "https://huggingface.co/<repo>/resolve/main/<file>" | grep -i content-length
    // before trusting one: a renamed or removed file is a 404 at download time
    // with no other symptom, and the catalogue is the only place it shows up.
    // ── Liquid AI `d1` ────────────────────────────────────────────────────────
    //
    // **Every URL in this entry was confirmed with a HEAD request, and the
    // `Content-Length` matches the file on disk byte for byte.** That is the rule
    // the catalogue already has — *"discovering the arch is unsupported after
    // 774 MB is defeat"* — and it earned its keep: the Hub API answered
    // `Invalid username or password`, the GGUF does not carry its own repo URL
    // (only `general.base_model.0.repo_url`, which is the **base model**), and
    // `LiquidAI/LFM2-d1-3B-GGUF` returns **401**. The name of the model *looks*
    // like LFM2 because it is one, and that is not the repository.
    //
    // **`Q4_K_M` is the smallest quantisation published**: BF16 5.03 GB, F16
    // 5.03, Q8_0 2.68. There is no smaller one to fall back on, so **this card
    // does not appear on a 5.6 GB phone** — 1.56 GB against a
    // `maxModelBytes` of 1.40 GB. That is the filter working, not a defect, and
    // the same mechanism that hides the five image models.
    {
      'name': 'd1-3B (Q4_K_M + vision)',
      'filename': 'd1-3B-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/LiquidAI/d1-3B-GGUF/resolve/main/d1-3B-Q4_K_M.gguf',
      'size': '1.56 GB',
      'descriptionEn':
          'Liquid AI decision model: text or image in, one letter out. Measured '
          'on an A72 — answers a billing question correctly and it survives '
          'reordering the options. 1.56 GB of weights plus a 0.54 GB projector',
      'descriptionPt':
          'Modelo de decisão da Liquid AI: texto ou imagem entra, uma letra sai. '
          'Medido no A72 — acerta uma pergunta de fatura e a resposta sobrevive '
          'à reordenação das opções. 1,56 GB de pesos mais um projector de '
          '0,54 GB',
      'template': 'chatml',
      'runtime': 'llama',
      'vision': 'true',
      'mmprojUrl':
          'https://huggingface.co/LiquidAI/d1-3B-GGUF/resolve/main/mmproj-d1-3B-Q8_0.gguf',
      'mmprojFilename': 'mmproj-d1-3B-Q8_0.gguf',
      'role': 'decision',
    },
    {
      'name': 'LFM2.5-VL 450M (Q4_0 + vision)',
      'filename': 'LFM2.5-VL-450M-Q4_0.gguf',
      'url':
          'https://huggingface.co/LiquidAI/LFM2.5-VL-450M-GGUF/resolve/main/LFM2.5-VL-450M-Q4_0.gguf',
      'size': '209 MB',
      'descriptionEn':
          
          'Smallest vision-language model here. 209 MB of weights plus a 98 '
          'MB projector',
          'descriptionPt':
'O menor modelo de visão-linguagem da lista. 209 MB de pesos mais '
          'um projector de 98 MB',
      'template': 'chatml',
      'runtime': 'llama',
      'vision': 'true',
      'mmprojUrl':
          'https://huggingface.co/LiquidAI/LFM2.5-VL-450M-GGUF/resolve/main/mmproj-LFM2.5-VL-450m-Q8_0.gguf',
      'mmprojFilename': 'mmproj-LFM2.5-VL-450m-Q8_0.gguf',
    },
    {
      'name': 'LFM2.5-VL 1.6B (Q4_0 + vision)',
      'filename': 'LFM2.5-VL-1.6B-Q4_0.gguf',
      'url':
          'https://huggingface.co/LiquidAI/LFM2.5-VL-1.6B-GGUF/resolve/main/LFM2.5-VL-1.6B-Q4_0.gguf',
      'size': '664 MB',
      'descriptionEn':
          
          'The sweet spot of the VL line. The projector is 556 MB, so vision '
          'costs more than the weights',
          'descriptionPt':
'O ponto ideal da linha VL. O projector tem 556 MB, então a visão '
          'custa mais que os pesos',
      'template': 'chatml',
      'runtime': 'llama',
      'vision': 'true',
      'mmprojUrl':
          'https://huggingface.co/LiquidAI/LFM2.5-VL-1.6B-GGUF/resolve/main/mmproj-LFM2.5-VL-1.6b-Q8_0.gguf',
      'mmprojFilename': 'mmproj-LFM2.5-VL-1.6b-Q8_0.gguf',
    },
    {
      'name': 'LFM2.5-VL 3B (Q4_0 + vision)',
      'filename': 'LFM2.5-VL-3B-Q4_0.gguf',
      'url':
          'https://huggingface.co/LiquidAI/LFM2.5-VL-3B-GGUF/resolve/main/LFM2.5-VL-3B-Q4_0.gguf',
      'size': '1.52 GB',
      'descriptionEn':
          
          'Largest LFM2.5-VL. Same 556 MB projector as the 1.6B, so the step '
          'up buys text quality only',
          'descriptionPt':
'O maior LFM2.5-VL. O mesmo projector de 556 MB do 1.6B, então '
          'subir de tamanho só melhora o texto',
      'template': 'chatml',
      'runtime': 'llama',
      'vision': 'true',
      'mmprojUrl':
          'https://huggingface.co/LiquidAI/LFM2.5-VL-3B-GGUF/resolve/main/mmproj-LFM2.5-VL-3B-Q8_0.gguf',
      'mmprojFilename': 'mmproj-LFM2.5-VL-3B-Q8_0.gguf',
    },
    // Spark X2.5 — a distinct architecture, not a Qwen or Llama derivative in
    // disguise. It arrived in llama.cpp as LLM_ARCH_SPARK2_5 (PR #27868) in the
    // 2026-09-23 vendor sync, so it needs an engine from that sync or newer; on
    // an older build the GGUF fails to load with an unknown-architecture error.
    // The 1.7B filename is the same one already used in the field, so the app
    // recognises a copy the user downloaded by hand instead of re-fetching it.
    {
      'name': 'Spark X2.5 1.7B (Q4_K_M)',
      'filename': 'Spark-X2.5-1.7B-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/XHToken/Spark-X2.5-1.7B-GGUF/resolve/main/Spark-X2.5-1.7B-Q4_K_M.gguf',
      'size': '1.03 GB',
      'descriptionEn':
          
          'New architecture (LLM_ARCH_SPARK2_5), text only. Needs the engine '
          'from the 2026-09-23 sync',
          'descriptionPt':
'Arquitetura nova (LLM_ARCH_SPARK2_5), só texto. Precisa do motor '
          'da sincronização de 2026-09-23',
      'template': 'chatml',
      'runtime': 'llama',
    },
    {
      'name': 'Spark X2.5 4B (Q4_K_M)',
      'filename': 'Spark-X2.5-4B-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/XHToken/Spark-X2.5-4B-GGUF/resolve/main/Spark-X2.5-4B-Q4_K_M.gguf',
      'size': '2.42 GB',
      'descriptionEn':
          
          'Largest Spark. Same architecture requirement as the 1.7B; needs a '
          'roomy phone',
          'descriptionPt':
'O maior Spark. A mesma exigência de arquitetura do 1.7B; precisa '
          'de um aparelho espaçoso',
      'template': 'chatml',
      'runtime': 'llama',
    },
    // Qwen3.5 — the current Qwen generation, and all three sizes under 4B are
    // multimodal. The catalogue still had Qwen2.5-3B and a LiteRT-only Qwen3 0.6B,
    // so this whole line was missing. The projector is the smaller file here,
    // roughly a quarter of the weights, which is unusual and worth knowing before
    // budgeting RAM for a vision turn.
    {
      'name': 'Qwen3.5 0.8B (Q4_K_M + vision)',
      'filename': 'Qwen3.5-0.8B-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf',
      'size': '508 MB',
      'descriptionEn':
           'Multimodal at 0.8B. 195 MB projector, so about 700 MB with vision',
          'descriptionPt':
'Multimodal em 0.8B. Projector de 195 MB, então cerca de 700 MB com '
          'visão',
      'template': 'chatml',
      'runtime': 'llama',
      'vision': 'true',
      'mmprojUrl':
          'https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/mmproj-F16.gguf',
      'mmprojFilename': 'mmproj-Qwen3.5-0.8B-F16.gguf',
    },
    {
      'name': 'Qwen3.5 2B (Q4_K_M + vision)',
      'filename': 'Qwen3.5-2B-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf',
      'size': '1.19 GB',
      'descriptionEn':
           'The balanced Qwen3.5. 637 MB projector on top of the weights',
          'descriptionPt':
'O Qwen3.5 equilibrado. 637 MB de projector somados aos pesos',
      'template': 'chatml',
      'runtime': 'llama',
      'vision': 'true',
      'mmprojUrl':
          'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/mmproj-F16.gguf',
      'mmprojFilename': 'mmproj-Qwen3.5-2B-F16.gguf',
    },
    {
      'name': 'Qwen3.5 4B (Q4_K_M + vision)',
      'filename': 'Qwen3.5-4B-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf',
      'size': '2.55 GB',
      'descriptionEn':
          
          'Best quality under 4B here, and multimodal. 641 MB projector; a '
          'vision turn needs ~3.2 GB',
          'descriptionPt':
'A melhor qualidade abaixo de 4B na lista, e multimodal. Projector '
          'de 641 MB; um turno com visão precisa de cerca de 3,2 GB',
      'template': 'chatml',
      'runtime': 'llama',
      'vision': 'true',
      'mmprojUrl':
          'https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/mmproj-F16.gguf',
      'mmprojFilename': 'mmproj-Qwen3.5-4B-F16.gguf',
    },
    // The rest of what is worth having under 4B. Each one is here for a reason a
    // size alone would not give you: a different licence, a different trade, or a
    // capability nothing else in this list covers.
    {
      'name': 'Ministral 3 3B Instruct (Q4_K_M + vision)',
      'filename': 'Ministral-3-3B-Instruct-2512-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/mistralai/Ministral-3-3B-Instruct-2512-GGUF/resolve/main/Ministral-3-3B-Instruct-2512-Q4_K_M.gguf',
      'size': '2.00 GB',
      'descriptionEn':
          
          'Mistral\'s own weights, ungated. Vision needs the 803 MB BF16 '
          'projector — the heaviest one here',
          'descriptionPt':
'Os pesos próprios da Mistral, sem censura. A visão precisa do '
          'projector BF16 de 803 MB — o maior da lista',
      'template': 'chatml',
      'runtime': 'llama',
      'vision': 'true',
      'mmprojUrl':
          'https://huggingface.co/mistralai/Ministral-3-3B-Instruct-2512-GGUF/resolve/main/Ministral-3-3B-Instruct-2512-BF16-mmproj.gguf',
      'mmprojFilename': 'Ministral-3-3B-Instruct-2512-BF16-mmproj.gguf',
    },
    {
      'name': 'Phi-4-mini Instruct 3.8B (Q4_K_M)',
      'filename': 'microsoft_Phi-4-mini-instruct-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/bartowski/microsoft_Phi-4-mini-instruct-GGUF/resolve/main/microsoft_Phi-4-mini-instruct-Q4_K_M.gguf',
      'size': '2.32 GB',
      'descriptionEn':
           'Microsoft, MIT licence. Strong at reasoning for its size, text '
          'only',
          'descriptionPt':
'Microsoft, licença MIT. Forte em raciocínio para o tamanho, só '
          'texto',
      'template': 'chatml',
      'runtime': 'llama',
    },
    {
      'name': 'SmolLM3 3B (Q4_K_M)',
      'filename': 'SmolLM3-Q4_K_M.gguf',
      'url': 'https://huggingface.co/ggml-org/SmolLM3-3B-GGUF/resolve/main/SmolLM3-Q4_K_M.gguf',
      'size': '1.78 GB',
      'descriptionEn':
          
          'HuggingFace\'s own 3B, in the llama.cpp org\'s repo. Text only; '
          'reasoning variant exists upstream',
          'descriptionPt':
'O 3B da própria HuggingFace, no repositório da organização '
          'llama.cpp. Só texto; existe uma variante de raciocínio a montante',
      'template': 'chatml',
      'runtime': 'llama',
    },
    {
      'name': 'SmolVLM2 2.2B Instruct (Q4_K_M + vision)',
      'filename': 'SmolVLM2-2.2B-Instruct-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/ggml-org/SmolVLM2-2.2B-Instruct-GGUF/resolve/main/SmolVLM2-2.2B-Instruct-Q4_K_M.gguf',
      'size': '1.04 GB',
      'descriptionEn':
          
          'The larger sibling of the 500M already listed. 565 MB projector; '
          'good at screenshots and UI',
          'descriptionPt':
'O irmão maior do 500M já listado. Projector de 565 MB; bom em '
          'capturas de tela e interfaces',
      'template': 'chatml',
      'runtime': 'llama',
      'vision': 'true',
      'mmprojUrl':
          'https://huggingface.co/ggml-org/SmolVLM2-2.2B-Instruct-GGUF/resolve/main/mmproj-SmolVLM2-2.2B-Instruct-Q8_0.gguf',
      'mmprojFilename': 'mmproj-SmolVLM2-2.2B-Instruct-Q8_0.gguf',
    },
    {
      'name': 'Gemma 3 270M Instruct (QAT Q4_0)',
      'filename': 'gemma-3-270m-qat-Q4_0.gguf',
      'url':
          'https://huggingface.co/ggml-org/gemma-3-270m-qat-GGUF/resolve/main/gemma-3-270m-qat-Q4_0.gguf',
      'size': '230 MB',
      'descriptionEn':
          
          'The smallest useful text model here. For testing the pipeline, not '
          'for answers',
          'descriptionPt':
'O menor modelo de texto realmente útil da lista. Serve para testar '
          'o pipeline, não para responder',
      'template': 'gemma',
      'runtime': 'llama',
    },
    {
      'name': 'Gemma 3 1B Instruct (QAT Q4_0)',
      'filename': 'gemma-3-1B-it-QAT-Q4_0.gguf',
      'url':
          'https://huggingface.co/lmstudio-community/gemma-3-1B-it-qat-GGUF/resolve/main/gemma-3-1B-it-QAT-Q4_0.gguf',
      'size': '0.72 GB',
      'descriptionEn':
          
          'Quantisation-aware 4-bit. Google\'s own QAT weights, mirrored '
          'ungated',
          'descriptionPt':
'4 bits ciente de quantização. Os pesos QAT da própria Google, '
          'espelhados sem censura',
      'template': 'gemma',
      'runtime': 'llama',
    },
    {
      'name': 'Gemma 3 4B Instruct (QAT Q4_0)',
      'filename': 'google_gemma-3-4b-it-qat-Q4_0.gguf',
      'url':
          'https://huggingface.co/bartowski/google_gemma-3-4b-it-qat-GGUF/resolve/main/google_gemma-3-4b-it-qat-Q4_0.gguf',
      'size': '2.37 GB',
      'descriptionEn':
          
          'Quantisation-aware 4-bit with vision. Needs a 0.85 GB projector',
          'descriptionPt':
'4 bits ciente de quantização, com visão. Precisa de um projector '
          'de 0,85 GB',
      'template': 'gemma',
      'runtime': 'llama',
      'vision': 'true',
      'mmprojUrl':
          'https://huggingface.co/bartowski/google_gemma-3-4b-it-qat-GGUF/resolve/main/mmproj-google_gemma-3-4b-it-qat-f16.gguf',
      'mmprojFilename': 'mmproj-google_gemma-3-4b-it-qat-f16.gguf',
    },
    {
      'name': 'Gemma 4 E2B Instruct (QAT Q4_0)',
      'filename': 'gemma-4-E2B_q4_0-it.gguf',
      'url':
          'https://huggingface.co/google/gemma-4-E2B-it-qat-q4_0-gguf/resolve/main/gemma-4-E2B_q4_0-it.gguf',
      'size': '3.35 GB',
      'descriptionEn':
          
          'Quantisation-aware 4-bit — text, images and audio. Needs a 0.99 GB '
          'projector',
          'descriptionPt':
'4 bits ciente de quantização — texto, imagens e áudio. Precisa de '
          'um projector de 0,99 GB',
      'template': 'gemma',
      'runtime': 'llama',
      'vision': 'true',
      'mmprojUrl':
          'https://huggingface.co/google/gemma-4-E2B-it-qat-q4_0-gguf/resolve/main/gemma-4-E2B-it-mmproj.gguf',
      'mmprojFilename': 'gemma-4-E2B-it-mmproj.gguf',
    },
    {
      'name': 'Gemma 4 E4B Instruct (QAT Q4_0)',
      'filename': 'gemma-4-E4B_q4_0-it.gguf',
      'url':
          'https://huggingface.co/google/gemma-4-E4B-it-qat-q4_0-gguf/resolve/main/gemma-4-E4B_q4_0-it.gguf',
      'size': '5.15 GB',
      'descriptionEn':
          
          'Quantisation-aware 4-bit — text, images and audio. Needs a 0.99 GB '
          'projector and a roomy phone',
          'descriptionPt':
'4 bits ciente de quantização — texto, imagens e áudio. Precisa de '
          'um projector de 0,99 GB e de um aparelho espaçoso',
      'template': 'gemma',
      'runtime': 'llama',
      'vision': 'true',
      'mmprojUrl':
          'https://huggingface.co/google/gemma-4-E4B-it-qat-q4_0-gguf/resolve/main/gemma-4-E4B-it-mmproj.gguf',
      'mmprojFilename': 'gemma-4-E4B-it-mmproj.gguf',
    },
    {
      'name': 'Gemma 4 E2B Instruct (GGUF)',
      'filename': 'gemma-4-E2B-it-Q4_0.gguf',
      'url':
          'https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_0.gguf',
      'size': '2.65 GB',
      'descriptionEn':
          
          'Multimodal — text, images and audio, with GPU offload. Needs a '
          '0.52 GB projector',
          'descriptionPt':
'Multimodal — texto, imagens e áudio, com offload para a GPU. '
          'Precisa de um projector de 0,52 GB',
      'template': 'gemma',
      'runtime': 'llama',
      'vision': 'true',
      'mmprojUrl':
          'https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/main/mmproj-gemma-4-E2B-it-Q8_0.gguf',
      'mmprojFilename': 'mmproj-gemma-4-E2B-it-Q8_0.gguf',
    },
    {
      'name': 'Qwen2.5-Omni 3B (GGUF)',
      'filename': 'Qwen2.5-Omni-3B-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/ggml-org/Qwen2.5-Omni-3B-GGUF/resolve/main/Qwen2.5-Omni-3B-Q4_K_M.gguf',
      'size': '1.96 GB',
      'descriptionEn':
          
          'Omni — images and audio in, text out. Needs a 1.43 GB projector',
          'descriptionPt':
'Omni — imagens e áudio de entrada, texto de saída. Precisa de um '
          'projector de 1,43 GB',
      'template': 'chatml',
      'runtime': 'llama',
      'vision': 'true',
      'mmprojUrl':
          'https://huggingface.co/ggml-org/Qwen2.5-Omni-3B-GGUF/resolve/main/mmproj-Qwen2.5-Omni-3B-Q8_0.gguf',
      'mmprojFilename': 'mmproj-Qwen2.5-Omni-3B-Q8_0.gguf',
    },
    {
      'name': 'Qwen2.5-VL 3B Instruct (GGUF)',
      'filename': 'Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/ggml-org/Qwen2.5-VL-3B-Instruct-GGUF/resolve/main/Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf',
      'size': '1.80 GB',
      'descriptionEn':
          
          'Vision — strong at reading text in images. Needs a 0.79 GB '
          'projector',
          'descriptionPt':
'Com visão — forte em ler texto dentro de imagens. Precisa de um '
          'projector de 0,79 GB',
      'template': 'chatml',
      'runtime': 'llama',
      'vision': 'true',
      'mmprojUrl':
          'https://huggingface.co/ggml-org/Qwen2.5-VL-3B-Instruct-GGUF/resolve/main/mmproj-Qwen2.5-VL-3B-Instruct-Q8_0.gguf',
      'mmprojFilename': 'mmproj-Qwen2.5-VL-3B-Instruct-Q8_0.gguf',
    },
    {
      'name': 'SmolVLM2 500M Video (GGUF)',
      'filename': 'SmolVLM2-500M-Video-Instruct-Q8_0.gguf',
      'url':
          'https://huggingface.co/ggml-org/SmolVLM2-500M-Video-Instruct-GGUF/resolve/main/SmolVLM2-500M-Video-Instruct-Q8_0.gguf',
      'size': '0.41 GB',
      'descriptionEn':
          
          'Vision — tiny and quick, for trying image input cheaply. 0.10 GB '
          'projector',
          'descriptionPt':
'Com visão — minúsculo e rápido, para testar entrada de imagem '
          'barato. Projector de 0,10 GB',
      'template': 'chatml',
      'runtime': 'llama',
      'vision': 'true',
      'mmprojUrl':
          'https://huggingface.co/ggml-org/SmolVLM2-500M-Video-Instruct-GGUF/resolve/main/mmproj-SmolVLM2-500M-Video-Instruct-Q8_0.gguf',
      'mmprojFilename': 'mmproj-SmolVLM2-500M-Video-Instruct-Q8_0.gguf',
    },
    {
      'name': 'Gemma 4 E2B Instruct (LiteRT-LM)',
      'filename': 'gemma-4-E2B-it.litertlm',
      'url':
          'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
      'size': '2.46 GB',
      'descriptionEn':
          
          'Multimodal — reads text, images and audio. Best size/quality '
          'balance',
          'descriptionPt':
'Multimodal — lê texto, imagens e áudio. Melhor equilíbrio entre '
          'tamanho e qualidade',
      'template': 'litert',
      'runtime': 'litert',
      'vision': 'true',
    },
    {
      'name': 'Gemma 4 E4B Instruct (LiteRT-LM)',
      'filename': 'gemma-4-E4B-it.litertlm',
      'url':
          'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm',
      'size': '3.40 GB',
      'descriptionEn':
          
          'Multimodal — text, images and audio. Highest quality; needs ~5 GB '
          'RAM',
          'descriptionPt':
'Multimodal — texto, imagens e áudio. A maior qualidade; precisa de '
          'cerca de 5 GB de RAM',
      'template': 'litert',
      'runtime': 'litert',
      'vision': 'true',
    },
    {
      'name': 'Kimi Moonlight 16B-A3B (Q3_K_S)',
      'filename': 'moonlight-16b-a3b-instruct-q3_k_s.gguf',
      'url':
          'https://huggingface.co/mmnga/Moonlight-16B-A3B-Instruct-gguf/resolve/main/Moonlight-16B-A3B-Instruct-Q3_K_S.gguf',
      'size': '7.1 GB',
      'descriptionEn':
           'Moonshot AI (Kimi) — 3B active MoE, high quality',
          'descriptionPt':
'Moonshot AI (Kimi) — MoE com 3B ativos, alta qualidade',
      'template': 'chatml',
    },
    {
      'name': 'Qwen2.5-3B Instruct (Q4_K_M)',
      'filename': 'qwen2.5-3b-instruct-q4_k_m.gguf',
      'url':
          'https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf',
      'size': '2.1 GB',
      'descriptionEn':
           'Best balance of speed and quality for mobile',
          'descriptionPt':
'O melhor equilíbrio de velocidade e qualidade para celular',
      'template': 'chatml',
    },
    {
      'name': 'Qwen2-VL-2B Instruct (Q4_K_M)',
      'filename': 'qwen2-vl-2b-instruct-q4_k_m.gguf',
      'url':
          'https://huggingface.co/bartowski/Qwen2-VL-2B-Instruct-GGUF/resolve/main/Qwen2-VL-2B-Instruct-Q4_K_M.gguf',
      'size': '1.5 GB',
      'descriptionEn':
          
          'Vision-capable model, but images run on LiteRT-LM only — here it '
          'is text',
          'descriptionPt':
'O modelo tem visão, mas as imagens só rodam no LiteRT-LM — aqui '
          'ele é só texto',
      'template': 'chatml',
      'vision': 'true',
    },
    {
      'name': 'Phi-3.5 Mini Instruct (Q4_K_M)',
      'filename': 'phi-3.5-mini-instruct-q4_k_m.gguf',
      'url':
          'https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf',
      'size': '2.2 GB',
      'descriptionEn':
           'Microsoft\'s compact reasoning model',
          'descriptionPt':
'Modelo compacto de raciocínio da Microsoft',
      'template': 'phi',
    },
    {
      'name': 'Gemma 2 2B Instruct (Q4_K_M)',
      'filename': 'gemma-2-2b-it-q4_k_m.gguf',
      'url':
          'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
      'size': '1.71 GB',
      'descriptionEn':
          
          'Google\'s lightweight general chat model — fast and smart',
          'descriptionPt':
'Modelo de chat leve e rápido da Google',
      'template': 'gemma',
    },
    {
      'name': 'Gemma-2-2B-Abliterated (Q4_K_M)',
      'filename': 'gemma-2-2b-it-abliterated-q4_k_m.gguf',
      'url':
          'https://huggingface.co/bartowski/gemma-2-2b-it-abliterated-GGUF/resolve/main/gemma-2-2b-it-abliterated-Q4_K_M.gguf',
      'size': '1.6 GB',
      'descriptionEn':
           '🔓 Abliterated — Permanently uncensored, very smart',
          'descriptionPt':
'🔓 Abliterated — permanentemente sem censura, e esperto',
      'template': 'gemma',
    },
    {
      'name': 'SmolLM2-1.7B-Uncensored (Q4_K_M)',
      'filename': 'smollm2-1.7b-instruct-uncensored-q4_k_m.gguf',
      'url':
          'https://huggingface.co/mradermacher/SmolLM2-1.7B-Instruct-Uncensored-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Uncensored.Q4_K_M.gguf',
      'size': '1.1 GB',
      'descriptionEn':
           'Ultra-compact and unrestricted assistant',
          'descriptionPt':
'Assistente ultracompacto e sem restrições',
      'template': 'chatml',
    },
    {
      'name': 'Dolphin-3.0-Qwen2.5-1.5B (Q4_K_M)',
      'filename': 'dolphin-3.0-qwen2.5-1.5b-q4_k_m.gguf',
      'url':
          'https://huggingface.co/bartowski/Dolphin3.0-Qwen2.5-1.5B-GGUF/resolve/main/Dolphin3.0-Qwen2.5-1.5B-Q4_K_M.gguf',
      'size': '1.1 GB',
      'descriptionEn':
           'Uncensored Dolphin 3.0 — Fast and unrestricted',
          'descriptionPt':
'Dolphin 3.0 sem censura — rápido e sem restrições',
      'template': 'chatml',
    },
    {
      'name': 'Llama-3.2-3B Uncensored (Q4_K_M)',
      'filename': 'llama-3.2-3b-instruct-uncensored-q4_k_m.gguf',
      'url':
          'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-uncensored-GGUF/resolve/main/Llama-3.2-3B-Instruct-uncensored-Q4_K_M.gguf',
      'size': '2.1 GB',
      'descriptionEn':
           'Uncensored Llama 3.2 3B — Smarter and unrestricted',
          'descriptionPt':
'Llama 3.2 3B sem censura — mais esperto e sem restrições',
      'template': 'llama3',
    },
    {
      'name': 'Llama-3.2-1B Instruct (Q4_K_M)',
      'filename': 'llama-3.2-1b-instruct-q4_k_m.gguf',
      'url':
          'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      'size': '0.8 GB',
      'descriptionEn':
           'Ultra-lightweight text model',
          'descriptionPt':
'Modelo de texto ultraleve',
      'template': 'llama3',
    },
    {
      'name': 'DreamShaper 8 LCM (SD 1.5)',
      'filename': 'DreamShaper8_LCM.safetensors',
      'url':
          'https://huggingface.co/Lykon/dreamshaper-8-lcm/resolve/main/DreamShaper8_LCM.safetensors',
      'size': '2.0 GB',
      'descriptionEn':
           'Extremely fast 4-step local image generation',
          'descriptionPt':
'Geração de imagem local em 4 passos, extremamente rápida',
      'template': 'sd',
    },
    {
      'name': 'CyberRealistic V8 FP16 (SD 1.5)',
      'filename': 'CyberRealistic_V8_FP16.safetensors',
      'url':
          'https://huggingface.co/cyberdelia/CyberRealistic/resolve/main/CyberRealistic_V8_FP16.safetensors',
      'size': '2.0 GB',
      'descriptionEn':
          
          'Photorealistic, uncensored local image generation — FP16 for '
          'mobile',
          'descriptionPt':
'Geração de imagem local fotorrealista e sem censura — FP16 para '
          'celular',
      'template': 'sd',
    },
    {
      'name': 'Realistic Vision V5.1 fp16 (SD 1.5)',
      'filename': 'Realistic_Vision_V5.1_fp16-no-ema.safetensors',
      'url':
          'https://huggingface.co/SG161222/Realistic_Vision_V5.1_noVAE/resolve/main/Realistic_Vision_V5.1_fp16-no-ema.safetensors',
      'size': '2.0 GB',
      'descriptionEn':
           'Highly popular photorealistic portrait and scene model',
          'descriptionPt':
'Modelo muito popular de retratos e cenas fotorrealistas',
      'template': 'sd',
    },
    {
      'name': 'AbsoluteReality 1.8.1 pruned (SD 1.5)',
      'filename': 'AbsoluteReality_1.8.1_pruned.safetensors',
      'url':
          'https://huggingface.co/Lykon/AbsoluteReality/resolve/main/AbsoluteReality_1.8.1_pruned.safetensors',
      'size': '2.0 GB',
      'descriptionEn':
           'Photorealistic general-purpose image generation',
          'descriptionPt':
'Geração de imagem fotorrealista de uso geral',
      'template': 'sd',
    },
    {
      'name': 'AnyLoRA (SD 1.5)',
      'filename': 'AnyLoRA_noVae_fp16-pruned.safetensors',
      'url':
          'https://huggingface.co/Lykon/AnyLoRA/resolve/main/AnyLoRA_noVae_fp16-pruned.safetensors',
      'size': '2.0 GB',
      'descriptionEn':
           'Highly versatile Anime / Stylized image generator',
          'descriptionPt':
'Gerador de imagem anime e estilizado, muito versátil',
      'template': 'sd',
    },
  ];

  // Cloud API Endpoints
  static const String openaiEndpoint =
      'https://api.openai.com/v1/chat/completions';
  static const String anthropicEndpoint =
      'https://api.anthropic.com/v1/messages';
  static const String googleEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models';
  static const String kimiEndpoint =
      'https://api.moonshot.ai/v1/chat/completions';
  static const String stabilityEndpoint =
      'https://api.stability.ai/v2beta/stable-image/generate/sd3';
  static const String nvidiaEndpoint = 'https://integrate.api.nvidia.com/v1';
  static const String openRouterEndpoint = 'https://openrouter.ai/api/v1';
  static const String deepSeekEndpoint = 'https://api.deepseek.com';
}
