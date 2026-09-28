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
  /// Same scheme for the vision projector backend ('cpu' | 'gpu').
  static const String visionBenchKeyPrefix = 'vision_bench_';
  static const String keyImageModelPath = 'image_model_path';
  static const String keyImageModelName = 'image_model_name';
  static const String keyTemperature = 'temperature';
  static const String keyMaxTokens = 'max_tokens';
  static const String keyContextSize = 'context_size';
  static const String keyScheduledTaskNotifications = 'scheduled_task_notifications';
  static const String keyServerApiKey = 'server_api_key';
  static const String keyServerUseApiKey = 'server_use_api_key';
  static const String keyServerPort = 'server_port';
  static const int defaultServerPort = 8080;
  static const String keyImageSteps = 'image_steps';
  static const String keyImageGenForceCpu = 'image_gen_force_cpu';
  /// CPU threads for llama.cpp. 0 means "half the cores".
  static const String keyCpuThreads = 'cpu_threads';
  static const String keyMmprojForceCpu = 'mmproj_force_cpu';
  static const String keyImageGenBackend = 'image_gen_backend';
  static const String keyImageGenGpuGuardMb = 'image_gen_gpu_guard_mb';
  static const String keyImageGenSize = 'image_gen_size';
  static const String keyImageGenQuantization = 'image_gen_quantization';
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

  // Default Model Config
  static const double defaultTemperature = 0.20;
  static const int defaultMaxTokens = 1024;
  static const int defaultContextSize = 4096;
  static const String defaultLiteRtPerformanceMode = 'auto_fast';

  /// Hard context ceiling for LiteRT models: the GPU driver OOMs above it.
  /// inference_service clamps the dialog value to this; the model card
  /// states it, because .litertlm headers carry no context field of their own.
  static const int liteRtContextCap = 4096;

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
  static const List<Map<String, String>> availableModels = [
    {
      'name': 'Qwen 3 0.6B (LiteRT-LM)',
      'filename': 'Qwen3-0.6B.litertlm',
      'url':
          'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
      'size': '586 MB',
      'description':
          'Smallest LiteRT-LM general-purpose chat model for low-RAM phones',
      'template': 'litert',
      'runtime': 'litert',
    },
    {
      'name': 'Qwen 2.5 1.5B Instruct (LiteRT-LM)',
      'filename': 'Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
      'url':
          'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
      'size': '1.49 GB',
      'description': 'Balanced LiteRT-LM chat model with int8 quantization',
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
      'description': 'Reasoning-focused LiteRT-LM model with int8 quantization',
      'template': 'litert',
      'runtime': 'litert',
    },
    // Quantisation-aware models: the weights were trained knowing they would
    // end up 4-bit, so a Q4_0 build holds far closer to the full-precision
    // model than a plain post-training quant of the same size. Q4_0 is also
    // the layout llama.cpp repacks for ARM dot-product and i8mm kernels, so
    // it is the fastest 4-bit path on a phone. Vendors name the recipe
    // differently — Google says QAT, Liquid says QAD — same idea.
    {
      'name': 'LFM2.5 230M (QAD Q4_0)',
      'filename': 'LFM2.5-230M-QAD-Q4_0.gguf',
      'url':
          'https://huggingface.co/LiquidAI/LFM2.5-230M-GGUF/resolve/main/LFM2.5-230M-QAD-Q4_0.gguf',
      'size': '0.15 GB',
      'description':
          'Quantisation-aware 4-bit. Smallest model here — runs on anything',
      'template': 'chatml',
      'runtime': 'llama',
    },
    {
      'name': 'LFM2.5 350M (QAD Q4_0)',
      'filename': 'LFM2.5-350M-QAD-Q4_0.gguf',
      'url':
          'https://huggingface.co/LiquidAI/LFM2.5-350M-GGUF/resolve/main/LFM2.5-350M-QAD-Q4_0.gguf',
      'size': '0.22 GB',
      'description': 'Quantisation-aware 4-bit, tuned for edge devices',
      'template': 'chatml',
      'runtime': 'llama',
    },
    {
      'name': 'LFM2.5 1.2B Instruct (QAD Q4_0)',
      'filename': 'LFM2.5-1.2B-Instruct-QAD-Q4_0.gguf',
      'url':
          'https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-QAD-Q4_0.gguf',
      'size': '0.70 GB',
      'description':
          'Quantisation-aware 4-bit. Multilingual, and the sweet spot for most phones',
      'template': 'chatml',
      'runtime': 'llama',
    },
    {
      'name': 'LFM2.5 2.6B (QAD Q4_0)',
      'filename': 'LFM2.5-2.6B-QAD-Q4_0.gguf',
      'url':
          'https://huggingface.co/LiquidAI/LFM2.5-2.6B-GGUF/resolve/main/LFM2.5-2.6B-QAD-Q4_0.gguf',
      'size': '1.59 GB',
      'description': 'Quantisation-aware 4-bit, the largest LFM2.5 that still fits comfortably',
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
    {
      'name': 'LFM2.5-VL 450M (Q4_0 + vision)',
      'filename': 'LFM2.5-VL-450M-Q4_0.gguf',
      'url':
          'https://huggingface.co/LiquidAI/LFM2.5-VL-450M-GGUF/resolve/main/LFM2.5-VL-450M-Q4_0.gguf',
      'size': '209 MB',
      'description':
          'Smallest vision-language model here. 209 MB of weights plus a 98 MB projector',
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
      'description':
          'The sweet spot of the VL line. The projector is 556 MB, so vision costs more than the weights',
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
      'description':
          'Largest LFM2.5-VL. Same 556 MB projector as the 1.6B, so the step up buys text quality only',
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
      'description':
          'New architecture (LLM_ARCH_SPARK2_5), text only. Needs the engine from the 2026-09-23 sync',
      'template': 'chatml',
      'runtime': 'llama',
    },
    {
      'name': 'Spark X2.5 4B (Q4_K_M)',
      'filename': 'Spark-X2.5-4B-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/XHToken/Spark-X2.5-4B-GGUF/resolve/main/Spark-X2.5-4B-Q4_K_M.gguf',
      'size': '2.42 GB',
      'description':
          'Largest Spark. Same architecture requirement as the 1.7B; needs a roomy phone',
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
      'description': 'Multimodal at 0.8B. 195 MB projector, so about 700 MB with vision',
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
      'description': 'The balanced Qwen3.5. 637 MB projector on top of the weights',
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
      'description':
          'Best quality under 4B here, and multimodal. 641 MB projector; a vision turn needs ~3.2 GB',
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
      'description':
          "Mistral's own weights, ungated. Vision needs the 803 MB BF16 projector — the heaviest one here",
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
      'description': 'Microsoft, MIT licence. Strong at reasoning for its size, text only',
      'template': 'chatml',
      'runtime': 'llama',
    },
    {
      'name': 'SmolLM3 3B (Q4_K_M)',
      'filename': 'SmolLM3-Q4_K_M.gguf',
      'url': 'https://huggingface.co/ggml-org/SmolLM3-3B-GGUF/resolve/main/SmolLM3-Q4_K_M.gguf',
      'size': '1.78 GB',
      'description':
          "HuggingFace's own 3B, in the llama.cpp org's repo. Text only; reasoning variant exists upstream",
      'template': 'chatml',
      'runtime': 'llama',
    },
    {
      'name': 'SmolVLM2 2.2B Instruct (Q4_K_M + vision)',
      'filename': 'SmolVLM2-2.2B-Instruct-Q4_K_M.gguf',
      'url':
          'https://huggingface.co/ggml-org/SmolVLM2-2.2B-Instruct-GGUF/resolve/main/SmolVLM2-2.2B-Instruct-Q4_K_M.gguf',
      'size': '1.04 GB',
      'description':
          'The larger sibling of the 500M already listed. 565 MB projector; good at screenshots and UI',
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
      'description':
          'The smallest useful text model here. For testing the pipeline, not for answers',
      'template': 'gemma',
      'runtime': 'llama',
    },
    {
      'name': 'Gemma 3 1B Instruct (QAT Q4_0)',
      'filename': 'gemma-3-1B-it-QAT-Q4_0.gguf',
      'url':
          'https://huggingface.co/lmstudio-community/gemma-3-1B-it-qat-GGUF/resolve/main/gemma-3-1B-it-QAT-Q4_0.gguf',
      'size': '0.72 GB',
      'description':
          "Quantisation-aware 4-bit. Google's own QAT weights, mirrored ungated",
      'template': 'gemma',
      'runtime': 'llama',
    },
    {
      'name': 'Gemma 3 4B Instruct (QAT Q4_0)',
      'filename': 'google_gemma-3-4b-it-qat-Q4_0.gguf',
      'url':
          'https://huggingface.co/bartowski/google_gemma-3-4b-it-qat-GGUF/resolve/main/google_gemma-3-4b-it-qat-Q4_0.gguf',
      'size': '2.37 GB',
      'description':
          'Quantisation-aware 4-bit with vision. Needs a 0.85 GB projector',
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
      'description':
          'Quantisation-aware 4-bit — text, images and audio. Needs a 0.99 GB projector',
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
      'description':
          'Quantisation-aware 4-bit — text, images and audio. Needs a 0.99 GB projector and a roomy phone',
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
      'description':
          'Multimodal — text, images and audio, with GPU offload. Needs a 0.52 GB projector',
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
      'description':
          'Omni — images and audio in, text out. Needs a 1.43 GB projector',
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
      'description':
          'Vision — strong at reading text in images. Needs a 0.79 GB projector',
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
      'description':
          'Vision — tiny and quick, for trying image input cheaply. 0.10 GB projector',
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
      'description':
          'Multimodal — reads text, images and audio. Best size/quality balance',
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
      'description':
          'Multimodal — text, images and audio. Highest quality; needs ~5 GB RAM',
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
      'description': 'Moonshot AI (Kimi) — 3B active MoE, high quality',
      'template': 'chatml',
    },
    {
      'name': 'Qwen2.5-3B Instruct (Q4_K_M)',
      'filename': 'qwen2.5-3b-instruct-q4_k_m.gguf',
      'url':
          'https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf',
      'size': '2.1 GB',
      'description': 'Best balance of speed and quality for mobile',
      'template': 'chatml',
    },
    {
      'name': 'Qwen2-VL-2B Instruct (Q4_K_M)',
      'filename': 'qwen2-vl-2b-instruct-q4_k_m.gguf',
      'url':
          'https://huggingface.co/bartowski/Qwen2-VL-2B-Instruct-GGUF/resolve/main/Qwen2-VL-2B-Instruct-Q4_K_M.gguf',
      'size': '1.5 GB',
      'description':
          'Vision-capable model, but images run on LiteRT-LM only — here it is text',
      'template': 'chatml',
      'vision': 'true',
    },
    {
      'name': 'Phi-3.5 Mini Instruct (Q4_K_M)',
      'filename': 'phi-3.5-mini-instruct-q4_k_m.gguf',
      'url':
          'https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf',
      'size': '2.2 GB',
      'description': 'Microsoft\'s compact reasoning model',
      'template': 'phi',
    },
    {
      'name': 'Gemma 2 2B Instruct (Q4_K_M)',
      'filename': 'gemma-2-2b-it-q4_k_m.gguf',
      'url':
          'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
      'size': '1.71 GB',
      'description':
          'Google\'s lightweight general chat model — fast and smart',
      'template': 'gemma',
    },
    {
      'name': 'Gemma-2-2B-Abliterated (Q4_K_M)',
      'filename': 'gemma-2-2b-it-abliterated-q4_k_m.gguf',
      'url':
          'https://huggingface.co/bartowski/gemma-2-2b-it-abliterated-GGUF/resolve/main/gemma-2-2b-it-abliterated-Q4_K_M.gguf',
      'size': '1.6 GB',
      'description': '🔓 Abliterated — Permanently uncensored, very smart',
      'template': 'gemma',
    },
    {
      'name': 'SmolLM2-1.7B-Uncensored (Q4_K_M)',
      'filename': 'smollm2-1.7b-instruct-uncensored-q4_k_m.gguf',
      'url':
          'https://huggingface.co/mradermacher/SmolLM2-1.7B-Instruct-Uncensored-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Uncensored.Q4_K_M.gguf',
      'size': '1.1 GB',
      'description': 'Ultra-compact and unrestricted assistant',
      'template': 'chatml',
    },
    {
      'name': 'Dolphin-3.0-Qwen2.5-1.5B (Q4_K_M)',
      'filename': 'dolphin-3.0-qwen2.5-1.5b-q4_k_m.gguf',
      'url':
          'https://huggingface.co/bartowski/Dolphin3.0-Qwen2.5-1.5B-GGUF/resolve/main/Dolphin3.0-Qwen2.5-1.5B-Q4_K_M.gguf',
      'size': '1.1 GB',
      'description': 'Uncensored Dolphin 3.0 — Fast and unrestricted',
      'template': 'chatml',
    },
    {
      'name': 'Llama-3.2-3B Uncensored (Q4_K_M)',
      'filename': 'llama-3.2-3b-instruct-uncensored-q4_k_m.gguf',
      'url':
          'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-uncensored-GGUF/resolve/main/Llama-3.2-3B-Instruct-uncensored-Q4_K_M.gguf',
      'size': '2.1 GB',
      'description': 'Uncensored Llama 3.2 3B — Smarter and unrestricted',
      'template': 'llama3',
    },
    {
      'name': 'Llama-3.2-1B Instruct (Q4_K_M)',
      'filename': 'llama-3.2-1b-instruct-q4_k_m.gguf',
      'url':
          'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      'size': '0.8 GB',
      'description': 'Ultra-lightweight text model',
      'template': 'llama3',
    },
    {
      'name': 'DreamShaper 8 LCM (SD 1.5)',
      'filename': 'DreamShaper8_LCM.safetensors',
      'url':
          'https://huggingface.co/Lykon/dreamshaper-8-lcm/resolve/main/DreamShaper8_LCM.safetensors',
      'size': '2.0 GB',
      'description': 'Extremely fast 4-step local image generation',
      'template': 'sd',
    },
    {
      'name': 'CyberRealistic V8 FP16 (SD 1.5)',
      'filename': 'CyberRealistic_V8_FP16.safetensors',
      'url':
          'https://huggingface.co/cyberdelia/CyberRealistic/resolve/main/CyberRealistic_V8_FP16.safetensors',
      'size': '2.0 GB',
      'description':
          'Photorealistic, uncensored local image generation — FP16 for mobile',
      'template': 'sd',
    },
    {
      'name': 'Realistic Vision V5.1 fp16 (SD 1.5)',
      'filename': 'Realistic_Vision_V5.1_fp16-no-ema.safetensors',
      'url':
          'https://huggingface.co/SG161222/Realistic_Vision_V5.1_noVAE/resolve/main/Realistic_Vision_V5.1_fp16-no-ema.safetensors',
      'size': '2.0 GB',
      'description': 'Highly popular photorealistic portrait and scene model',
      'template': 'sd',
    },
    {
      'name': 'AbsoluteReality 1.8.1 pruned (SD 1.5)',
      'filename': 'AbsoluteReality_1.8.1_pruned.safetensors',
      'url':
          'https://huggingface.co/Lykon/AbsoluteReality/resolve/main/AbsoluteReality_1.8.1_pruned.safetensors',
      'size': '2.0 GB',
      'description': 'Photorealistic general-purpose image generation',
      'template': 'sd',
    },
    {
      'name': 'AnyLoRA (SD 1.5)',
      'filename': 'AnyLoRA_noVae_fp16-pruned.safetensors',
      'url':
          'https://huggingface.co/Lykon/AnyLoRA/resolve/main/AnyLoRA_noVae_fp16-pruned.safetensors',
      'size': '2.0 GB',
      'description': 'Highly versatile Anime / Stylized image generator',
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
