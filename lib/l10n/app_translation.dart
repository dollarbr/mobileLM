import 'package:get/get.dart';

/// Os dois idiomas do app.
///
/// **O inglês vem primeiro porque é o padrão, e o padrão é uma escolha
/// declarada — não um deduzido.** O GetX devolve a própria chave para uma
/// tradução que não existe, e foi assim que 38 chaves apareceram como
/// `tool_round_trips` e `mobile_lm` numa tela portuguesa sem nada lançar. Ligar
/// um idioma sem o mapa inteiro dele renderiza os identificadores todos de uma
/// vez, visíveis e inúteis.
///
/// `test/l10n_keys_test.dart` é o que impede isso: ele afirma que os dois
/// mapas têm as mesmas chaves e as mesmas chamadas de `.tr`. Um idioma guardado
/// em metades é metade do defeito de novo.
///
/// **Cada teste desse arquivo tem um irmão que prova que ele ainda vê alguma
/// coisa**, porque uma regex que parou de casar reportaria zero faltando e
/// passaria.
///
/// O prompt de sistema **segue o idioma da tela**, e não é uma escolha
/// estética: o app pedir em português com a interface dizendo que fala inglês é
/// exatamente a inconsistência que o seletor veio tirar. Daí a redação — "a
/// língua que o app está mostrando, e a língua em que você escrever" — em vez
/// do antigo "responda em português brasileiro", que agora seria falso metade
/// das vezes.
///
/// **Os arquivos `.arb` continuam desligados.** `app_pt_BR.arb` e
/// `app_en.arb` têm 113 chaves e não são fonte para nada — nem o GetX os lê,
/// nem o `intl:generate` roda. São um subconjunto do mapa, não uma terceira
/// fonte de verdade; deixá-los é inofensivo e apagá-los é mexer no que não
/// está quebrado.
class AppTranslation extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {
    'en_US': {
      'sc_section_endpoints': 'ENDPOINTS',
      'sc_section_examples': 'USAGE EXAMPLES',
      'sc_title_running': 'API Server Running',
      'sc_title_stopped': 'API Server Stopped',
      'sc_subtitle_stopped': 'Expose your local model as an OpenAI API.',
      'sc_section_security': 'SECURITY',
      'sc_generate_key': 'Generate',
      'sc_copy': 'Copy',
      'set_task_updated': 'Task updated.',
      'set_warning_title': '⚠ Warning',
      'cc_auto_size': 'Auto size',
      'cc_error_bubble': '❌ Error: @e',
      'chat_image_gen_line': 'Image gen · @s @u · @z · @b',
      'chat_image_gen_step': 'step',
      'chat_image_gen_steps': 'steps',
      'cm_built_in_list': 'Built-in list',
      'cm_not_fetched': 'Not fetched yet',
      'cm_updated_now': 'Updated just now',
      'cm_updated_min': 'Updated @n min ago',
      'cm_updated_hour': 'Updated @n h ago',
      'cm_updated_day': 'Updated @n d ago',
      'cm_cloud_active': 'Cloud Model Active',
      'cm_api_key_required': 'API key is required.',
      'cm_model_id_required': 'Model ID is required.',
      'mc_backup': 'Backup',
      'mc_no_folder_selected': 'No folder selected',
      'mc_backup_saved': 'Saved: configs in settings/ + models in Vendor/Family folders',
      'mc_backup_failed': 'Backup failed',
      'mc_restore': 'Restore',
      'mc_restore_applied': 'Configs applied. Restart to fully reload.',
      'mc_restore_applied_count': 'Configs applied (@s value(s)) · @m model file(s) restored',
      'mc_restore_no_files': 'No model files found in the backup folder.',
      'mc_restore_count': '@n model file(s) restored',
      'mc_restore_failed': 'Restore failed',
      'mc_helper_file': 'Helper File',
      'mc_helper_file_detail': '@f is used internally by image generation and cannot be loaded as '
          'a model.',
      'mc_corrupt_file': 'Corrupt Model File',
      'mc_corrupt_detail': '@f did not download correctly. Delete it and download again.',
      'mc_not_valid_litert': '@f is not a valid LiteRT-LM file. Delete it and download again.',
      'mc_image_model': 'Image Model',
      'mc_model_not_loaded': 'Model Not Loaded',
      'mc_model_loaded': 'Model Loaded',
      'mc_check_arch': 'Double check if this LiteRT-LM file matches your architecture.',
      'mc_runtime_local': 'local model',
      'mc_already_loaded': 'This model is already loaded.',
      'mc_already_loaded_named': 'Already loaded: @l',
      'mc_memory_optimized': 'Memory Optimized',
      'mc_memory_freed': 'Unloaded "@l" to free memory for the new model.',
      'mc_api_server_stopped': 'API server stopped',
      'mc_api_server_stopped_detail': 'It serves the model that was just unloaded.',
      'mc_import_failed': 'Import Failed',
      'mc_import_empty': 'The selected file is empty.',
      'mc_local_file': 'Local File',
      'sc_port_occupied': 'Port occupied',
      'sc_port_in_use': 'Port @a is already in use. Server will run on @b.',
      'sc_starting': 'Starting server...',
      'sc_running': 'Server running',
      'sc_failed': 'Server failed',
      'sc_stopped': 'Server stopped',
      'set_search_endpoint_hint': 'Optional. Empty means Brave → Startpage → DuckDuckGo.',
      'set_benchmark_running': 'Running…',
      'set_projector_auto_detail': 'Auto — benchmarked once, faster backend kept',
      'mc_restore_will_overwrite': '@s saved value(s) will overwrite the current ones.',
      'mc_switch_needs_restart': 'You already used @c in this app session. Switching to @t without '
          'restarting can crash the native runtime.\n\nRestart the app, then '
          'load this model.',
      'mc_litert_speed_title': '@m LiteRT speed',
      'mc_model_already_imported': 'A model file named "@f" is already imported in your local app '
          'storage. Want to load the copy that is already there?',
      'mc_restart_recommended': 'Restart recommended',
      'mc_unknown_size': 'Unknown size',
      // ── o que o alargamento da lista de palavras expôs ──
      // A lista de `TextLanguage.englishWords` cresceu 27 palavras medidas, e
      // isso expôs texto que estava em inglês na tela desde sempre **e fora do
      // alcance das duas varreduras**: `show`, `back`, `copy`, `benchmark` e
      // `clear` não estavam na lista, então estes catorze literais não eram
      // contados por nada. Um detector que não conhece a palavra não denuncia
      // o texto — e nenhuma das três travas pode acusar o que elas não veem.
      'log_copy_important': 'Copy important logs',
      'log_clear': 'Clear logs',
      'log_copied': 'Copied',
      'log_copied_detail': 'Important logs copied to clipboard.',
      'ws_back_to_projects': 'Back to projects',
      'ws_refresh': 'Refresh',
      'pp_new_project_name': 'New project name',
      'pp_name_hint': 'e.g. my-website',
      'set_cpu_benchmark': 'CPU benchmark',
      // **A única interpolada das 16, e substituiu um literal com `${…}`** que a
      // trava dos interpolados não via porque `available` não estava na lista.
      //
      // **O espaço em `@ram GB` é o que segura a tela, e o teste novo prova.** O
      // regex de `preencher` lê `@ramGB` como *um* placeholder, a chamada não tem
      // valor para ele, e a `ArgumentError` cai dentro do `build` — o Flutter
      // troca o `Text` por um retângulo vermelho que ocupa a linha toda. Unidade
      // e pontuação vão sempre FORA do placeholder.
      'set_device_budget': 'Available: @ram GB · Context: @ctx · Tokens: @tok',
      'mv_show_it_anyway': 'Show it anyway',
      'mv_cloud_provider_name': 'Provider name',
      'mv_cloud_base_url': 'Base URL',
      'mv_projector': 'Projector',
      'sc_turn_off_anyway': 'Turn off anyway',
      'mc_load_model': 'Load model?',
      'mc_gpu_may_crash': 'GPU can make LiteRT models much faster, closer to Edge Gallery '
          'speed. On some phones GPU/OpenCL can crash the app while loading. '
          'If that happens, Auto Fast will use CPU on the next load.',
      'mv_section_downloaded': 'Downloaded',
      'mv_section_image': 'Image',
      'mv_section_custom_gguf': 'Custom GGUF Models',
      'mv_section_custom_litert': 'Custom LiteRT Models',
      'mv_section_custom_tflite': 'Custom TFLite Models',
      'mv_gpu_layers': '⚡ @w (@n layers)',
      'mv_import_local_or_url': 'Import a local model or add a downloadable URL.',
      'chat_no_project': 'No project',
      'enc_tap_to_fill': 'tap to fill',
      'hf_fits_device': 'Fits my device',
      'log_no_file': 'No Log File',
      'log_none_of_filter': 'No @f messages',
      'mv_no_models_yet': 'No models yet',
      'mv_no_model_selected': 'No model selected',
      'mv_api_key': 'API key',
      'mv_add_key': 'Add Key',
      'mv_no_projector_paired': 'No projector paired',
      'mv_added_custom_url': 'Added custom model via URL',
      'mv_layers_label': '(@n layers)',
      'sv_api_key_off': 'API key off',
      'sv_not_available': 'Not available',
      'sv_health_failed': 'Health failed',
      'set_all_from_model': 'All from the model',
      'set_task_created': 'Task created.',
      'soc_no_feature_vector': 'No feature vector.',
      'soc_ask_for_the_letter': 'ask for the letter',
      'wv_new_folder': 'New folder',
      'wv_new_file': 'New file',
      'ap_text_file': 'Text file',
      'log_nothing_written': 'Nothing has been written to disk yet.',
      'chat_from_gallery': 'From gallery',
      'encp_file_says': 'file says it is',
      'sv_port_label': 'PORT',
      'set_error_label': 'Error',
      'soc_which_shape': 'which shape is this?',
      'soc_server_said': 'The server said:',
      'soc_loaded_name': 'loaded: @l',
      'soc_the_feature_vector': 'the feature vector',
      'soc_run_now': 'running',
      'wv_delete_failed': 'Delete failed.',
      'encp_unknown': 'unknown',
      'hf_search_failed': 'Search failed: @e',
      'set_failed': 'Failed: @e',
      'mv_name_label': 'Name',
      'mv_size_label': 'Size',
      'mv_memory_label': 'Memory',
      'mv_state_loaded': 'loaded',
      'mv_state_ready': 'READY',
      'mv_state_downloaded': 'DOWNLOADED',
      'mv_load_action': 'Load',
      'sv_port_field': 'Port',
      'sv_local_model_ready': 'Local model ready',
      'sv_no_model_loaded': 'No model loaded — chat and encoder endpoints will refuse; model '
          'management still works',
      'set_model_label': 'Model',
      'soc_local_models': 'local models',
      'enc_more_items': '… @n more',
      'lhc_not_bindable': 'not bindable — @r',
      'lhc_never_read_yet': '(not read yet)',
      'lhc_not_loaded_yet': '(not loaded yet)',
      'lhc_unknown': 'unknown',
      'lhc_accelerator_not_exposed': 'LiteRT 2.2.0 does not expose the accelerator it used, so this '
          'console cannot say. On the device, LITERT_CL or CPU in the log is '
          'the answer.',
      'lhc_status_available': 'device reports: @a',
      'lhc_status_requested': 'requested: @q',
      'lhc_status_executed': 'executed: @e — @n',
      'lhc_status_failed': 'status call failed: @e',
      'lhc_top_index_note': 'top_index @t by argmax of @m. That is an argmax and not a '
          'prediction: it is the right reading only for a head trained to '
          'work that way, and there is no label here because only the caller '
          'knows what class 0 is.',
      'mv_paste_provider_key': 'Paste @p key',
      'tv_steps_status': '@n steps · @s',
      'chat_model_origin': '@m · @o',
      'chat_loading_pct': 'Loading model… @p%',
      'encp_load_error': 'Could not read the loaded model: @e',
      'hf_checkpoint_says': 'the checkpoint says: @a',
      'lhc_feature_vector': 'The feature vector fills "@n" (@c values) — the largest input. '
          '@rest',
      'mv_local_models': 'LOCAL MODELS (@n)',
      'mv_download_benchmark_note': '"@n" is @s. It is the smallest model here, and it is what measures '
          'whether this phone can run a model at all. Without it the test '
          'cannot run.',
      'mv_cloud_provider': 'CLOUD · @p',
      'mv_select_provider_model': 'Select @p Model',
      'mv_provider_model_count': '@n models - @f',
      'mv_custom_provider_model': 'Custom @p Model',
      'mv_delete_filename': '@f will be permanently removed from this device.',
      'mv_vision_model': 'Vision · @m',
      'mv_memory_free': '@f free of @t',
      'set_threads_auto': 'Threads: Auto — the big cores (@n)',
      'set_cores_left_out': 'Cores cpu0-@n left out; ggml syncs every thread at the end of each '
          'op and a slow one sets the pace',
      'soc_what_will_send': 'what the window will send: @o',
      'soc_the_model_said': 'the model said: @r',
      'soc_no_confidence': 'no confidence, and here is why: @w',
      'soc_model_label': 'model: @m',
      'lhc_no_auxiliary': 'There are no other inputs.',
      'lhc_auxiliary': 'The other inputs are yours to supply: @t. They are never filled '
          'with zeros.',
    'about': 'About',
    'active_image_model': 'Active image model',
    'active_model': 'Active model',
    'adb_shizuku': 'ADB and Shizuku',
    'add_attachment': 'Add attachment',
    'add_model': 'Add model',
    'add_model_url': 'Add model URL',
    'advanced': 'Advanced',
    'agent_max_hops': 'Max agent hops',
    'all': 'All',
    'all_clear': 'All clear',
    'allow': 'Allow',
    'any': 'Any',
    'api_key_required': 'API key required',
    'app_started': 'App started',
    'app_title': 'mobileLM',
    'appearance': 'Appearance',
    'applies_to_local_and_cloud': 'Applies to local and to cloud',
    'apply': 'Apply',
    'as_identity': 'Running as',
    'assistant': 'Assistant',
    'at_this_minute_past_each_interval': 'At this minute past each interval',
    'at_this_time_every_day': 'At this time every day',
    'attach_file': 'Attach a file',
    'audio': 'Audio',
    'auto_configure_for_device': 'Configure automatically for this device',
    'available_ram': 'Available RAM',
    'backup_configs': 'Back up settings',
    'cancel': 'Cancel',
    'change': 'Change',
    'change_workspace_folder': 'Change the workspace folder?',
    'chat': 'Chat',
    'chat_placeholder': 'Type your message…',
    'chip_continue': 'Continue',
    'chip_continue_prompt': 'Carry on with the previous explanation.',
    'chip_example': 'Example',
    'chip_example_prompt': 'Give a practical example about this topic.',
    'chip_expand': 'Explain further',
    'chip_expand_prompt': 'Explain this again in more detail and clearly.',
    'chip_simplify': 'Simplify',
    'chip_simplify_prompt': 'Explain this more simply, as if for a beginner.',
    'chip_summarise': 'Summarise',
    'chip_summarise_prompt': 'Summarise your previous answer concisely.',
    'chip_translate': 'Translate',
    'chip_translate_prompt': 'Translate your previous answer into English.',
    'close': 'Close',
    'cloud': 'Cloud',
    'cloud_api': 'Cloud API',
    'cloud_models_support_images_and_text_files': 'Cloud models accept images and text files',
    'configs_template_json': 'Settings template (.json)',
    'confirm_delete': 'Confirm delete',
    'confirm_tool_execution': '{tool} wants to change something on this device.',
    'connected': 'Connected',
    'context_size': 'Context size',
    'context_summary': 'Conversation summarised ({{count}} earlier messages condensed)',
    'context_summary_continue': 'Continue the conversation from here.',
    'continue': 'Continue',
    'conversations': 'Conversations',
    'copies_the_file_into_the_models_folder': 'Copies the file into the models folder',
    'could_not_extract': '[Could not extract text from',
    'cpu': 'CPU',
    'crash_report_failed': 'Failed to send crash report',
    'crash_report_sent': 'Crash report sent',
    'crash_reporting': 'Crash reporting',
    'create': 'Create',
    'create_new_project': 'Create new project',
    'create_project': 'Create project',
    'custom_provider': 'Custom provider',
    'daily': 'Daily',
    'daily_prompts_that_run_on_their_own': 'Daily prompts that run on their own',
    'dark': 'Dark',
    'default_size': 'Default size',
    'default_system_prompt': 'Default system prompt',
    'delete': 'Delete',
    'delete_model': 'Delete model?',
    'delete_name': 'Delete \\\$name',
    'deleting': 'Deleting…',
    'deny': 'Deny',
    'describe_image': 'Describe this image.',
    'describe_video': 'Describe what happens in this video.',
    'disconnected': 'Disconnected',
    'document': 'Document',
    'download': 'Download',
    'download_a_gguf_or_litert_model_from_any_url': 'Download a GGUF or LiteRT model from any URL',
    'download_complete': 'Download complete',
    'download_failed': 'Download failed',
    'download_model': 'Download model',
    'download_now': 'Download now',
    'download_the_mmproj_via_the_hf_search_th': 'Download the mmproj via HF search, then link it here',
    'downloading': 'Downloading',
    'downloading_model': 'Downloading model…',
    'edit': 'Edit',
    'edit_model': 'Edit model',
    'edit_task': 'Edit task',
    'elapsed': 'Elapsed',
    'enable_tools': 'Enable tools',
    'enter_value_between': 'Enter a value between \\\$min and \\\$max',
    'error': 'Error',
    'error_saving_image': 'Error saving the image',
    'error_sharing_image': 'Error sharing the image',
    'estimated_time': 'Estimated time',
    'every_2h': 'Every 2h',
    'every_4h': 'Every 4h',
    'every_6h': 'Every 6h',
    'every_8h': 'Every 8h',
    'everything_configs___models': 'Everything (settings + models)',
    'failed_to_save_image': 'Failed to save the image',
    'file': 'File',
    'file_attachment_failed': 'Failed to attach the file',
    'file_not_attached': 'File not attached',
    'file_truncated': '[File truncated to the context size]',
    'filter': 'Filter',
    'filters': 'Filters',
    'firebase_init_failed': '[Firebase] Initialisation failed',
    'fits_my_device': 'Fits my device',
    'folder': 'Folder',
    'font_scale': 'Font scale',
    'font_size': 'Font size',
    'from_hugging_face': 'From Hugging Face',
    'general': 'General',
    'generating_image': 'Generating image…',
    'generation_complete': 'Generation complete',
    'generation_failed': 'Generation failed',
    'get': 'Get',
    'go_to_models': 'Go to models',
    'go_to_root': 'Go to root',
    'gpu': 'GPU',
    'gpu_is_experimental': 'The GPU is experimental: faster on some models and not yet '
'measured on all.',
    'gpu_safety': 'GPU safety',
    'grant_permission': 'Grant permission',
    'hello': 'Hello.',
    'home': 'Home',
    'hourly': 'Hourly',
    'how_can_i_help': 'How can I help?',
    'how_can_i_help_you_today': 'How can I help today?',
    'image': 'Image',
    'image_backend': 'Image backend',
    'image_gen_steps': 'Image generation steps',
    'image_generation': 'Image generation',
    'image_generation_failed': 'Local image generation failed.',
    'image_saved_to_gallery': 'Image saved to the gallery',
    'image_size': 'Image size',
    'import': 'Import',
    'include_model_files': 'Include model files',
    'inference_mode': 'Inference mode',
    'info': 'Information',
    'initialize_speech': 'Initialising speech recognition…',
    'initializing_model': 'Initialising the model',
    'just_once': 'Just once',
    'keep_model_loaded_between_runs': 'Keep the model loaded between runs',
    'language': 'Language',
    'language_auto': 'Automatic',
    'language_auto_detail_en': 'This phone is not set to Portuguese, so the screen is in English.',
    'language_auto_detail_pt': 'This phone is set to Portuguese, so the screen is in Portuguese.',
    'language_changed': 'Language changed',
    'language_english_detail': 'Always English, whatever the phone says',
    'language_portuguese_brazil_detail': 'Always Brazilian Portuguese',
    'large': 'Large',
    'last_model': 'Last model',
    'later': 'Later',
    'light': 'Light',
    'listening': 'Listening…',
    'listening_tap_mic_to_stop': 'Listening — tap the mic to stop',
    'loading': 'Loading…',
    'loading_filename': 'Loading the model',
    'loading_into_memory': 'Loading into memory',
    'loading_model': 'Loading model…',
    'local': 'Local',
    'local_api_server': 'Local API server',
    'local_on_device': 'On device',
    'logs': 'Logs',
    'max_tokens': 'Max tokens',
    'message': 'Message',
    'mobile_br': 'mobileLM',
    'mobile_lm': 'mobileLM',
    'model_already_exists': 'Model already exists',
    'model_files_from_the_backup_folder': 'Model files from the backup folder',
    'model_load_failed': 'Failed to load model',
    'model_loaded': 'Model loaded',
    'model_not_found': 'Model not found',
    'model_placeholder': 'Select a model…',
    'model_size': 'Model size',
    'model_unloaded': 'Model unloaded',
    'model_verification_failed': 'Model verification failed',
    'model_verified': 'Model verified',
    'models': 'Models',
    'multimodal_model': 'Multimodal model',
    'name_placeholder': 'Name…',
    'new_chat': 'New chat',
    'new_daily_task': 'New daily task',
    'new_task': 'New task',
    'no': 'No',
    'no_conversations_yet': 'No conversations yet',
    'no_local_models': 'No local models',
    'no_model_loaded': 'No model loaded',
    'no_models_downloaded_yet': 'No models downloaded yet',
    'no_project': 'No project',
    'no_projects_yet': 'No projects yet.',
    'no_projects_yet___create_one_to_get_star': 'No projects yet — create one to get started.',
    'no_stack': 'No stack trace',
    'no_tasks_yet': 'No tasks yet',
    'no_tasks_yet_a_task_runs_its_prompt_every_day_at_the': 'No tasks yet. A task runs its prompt every day at',
    'no_thought': 'No thinking',
    'none': 'None',
    'off_the_tool_list_is_kept_out_of_the_prompt': 'Off — the tool list is kept out of the prompt',
    'offline': 'Offline',
    'ok': 'OK',
    'online': 'Online',
    'open_project': 'Open project',
    'openai_compatible_endpoint': 'OpenAI-compatible endpoint',
    'overwrites_current_settings': 'Overwrites current settings',
    'pick_from_device_storage': 'Pick from device storage',
    'please_wait': 'Please wait…',
    'privileged_service': 'Privileged service',
    'project_created': 'Project created',
    'project_not_found': 'Project not found',
    'projects': 'Projects',
    'prompt_no_think_tag': '/no_think',
    'prompt_system': 'You are a helpful assistant that replies in the language the app '
'is showing. If the user writes in another language, reply in '
'theirs.',
    'prompt_system_no_think': 'You are a helpful assistant that replies directly without '
'overthinking. Reply in the language the app is showing; if the '
'user writes in another language, reply in theirs.',
    'prompt_system_think': 'You are a helpful assistant that thinks before replying. Reply in '
'the language the app is showing; if the user writes in another '
'language, reply in theirs.',
    'prompt_think_tag': '/think',
    'prompt_to_run': 'Prompt to run',
    'providers': 'Providers',
    'quantisation_aware_only': 'Quantisation-aware only',
    're_check': 'Re-check',
    'recommended': 'Recommended',
    'recommended_max_8': 'Recommended: at most 8 — above that barely changes and takes much '
'longer',
    'refresh': 'Refresh',
    'remove_attachment': 'Remove attachment',
    'removing': 'Removing…',
    'rename': 'Rename',
    'replace_file': 'Replace file',
    'required_before_selecting_live_models': 'Required before selecting live models',
    'reset': 'Reset',
    'restart': 'Restart',
    'restart_app': 'Restart app',
    'restart_now': 'Restart now?',
    'restart_required': 'Restart required',
    'restore': 'Restore',
    'restore_backup': 'Restore backup',
    'review_attachment': 'Review this attachment.',
    'review_file': 'Review this file.',
    'root_access': 'Root access',
    'run_this_single_time_at_the_chosen_hour': 'Run this once at the chosen time',
    'running_tool': 'Running {tool}…',
    'runs': 'Runs',
    'runs_as': 'Runs as',
    'runtime': 'Runtime',
    'sampling_complete': 'Sampling complete',
    'save': 'Save',
    'save_and_select': 'Save and select',
    'saving': 'Saving…',
    'scheduled_task': 'Scheduled task',
    'scheduled_tasks': 'Scheduled tasks',
    'search': 'Search',
    'search_placeholder': 'Search…',
    'seconds': 'seconds',
    'section_about': 'About',
    'section_agent': 'Agent',
    'section_appearance': 'Appearance',
    'section_device_information': 'Device information',
    'section_diagnostics': 'Diagnostics',
    'section_inference_mode': 'Inference mode',
    'section_model_settings': 'Model settings',
    'section_storage': 'Storage',
    'section_workspace': 'Workspace',
    'select': 'Select',
    'select_model': 'Select model',
    'select_project': 'Select project',
    'send': 'Send',
    'sending_crash_report': 'Sending crash report…',
    'server': 'Server',
    'set_up_workspace': 'Set up the workspace',
    'set_up_your_workspace': 'Set up your workspace',
    'settings': 'Settings',
    'shizuku_not_available': 'Shizuku not available',
    'shizuku_required': 'Shizuku required',
    'show_background_notification': 'Show a background notification',
    'skips_files_already_present_and_identica': 'Skips files already present and identical',
    'small': 'Small',
    'some_settings_only_load_at_app_start': 'Some settings only take effect the next time the app starts',
    'sort': 'Sort',
    'speech_not_available': 'Speech recognition not available',
    'speech_to_text': 'Speech to text',
    'start_backup': 'Start backup',
    'steps': 'Steps',
    'stop_generation': 'Stop generation',
    'streaming': 'Streaming…',
    'success': 'Success!',
    'suggestion_1': 'Explain quantum computing in simple terms',
    'suggestion_10': 'Convert 120 km to miles',
    'suggestion_11': 'Write a haiku about the rain',
    'suggestion_12': 'Explain recursion as if I were 5 years old',
    'suggestion_13': 'Suggest a beginner workout plan',
    'suggestion_14': 'Tell me a fun fact about space',
    'suggestion_15': 'Help me write a CV summary',
    'suggestion_16': 'Multiply 128 by 456',
    'suggestion_2': 'Write a short poem about time',
    'suggestion_3': 'Help me debug my code',
    'suggestion_4': 'Summarise a complex topic',
    'suggestion_5': 'What time is it in Tokyo?',
    'suggestion_6': 'Brainstorm names for a coffee shop',
    'suggestion_7': 'Draft a polite complaint email',
    'suggestion_8': 'Translate "good morning" into 5 languages',
    'suggestion_9': 'Plan a 3-day trip to Lisbon',
    'summarize_document': 'Summarise this document.',
    'summarize_pdf': 'Summarise this PDF.',
    'system': 'System',
    'system_prompt_hint': 'Instructions the model follows in every conversation',
    'task_at': 'Task at',
    'task_completed': 'Task completed',
    'task_failed': 'Task failed',
    'tasks': 'Tasks',
    'temperature': 'Temperature',
    'test_local': 'Test local',
    'text_file': 'Text file',
    'text_generation': 'Text generation',
    'theme': 'Theme',
    'theme_dark': 'Dark',
    'theme_light': 'Light',
    'theme_system': 'System default',
    'thinking': 'Thinking…',
    'thinking_auto': 'Automatic',
    'thinking_mode': 'Thinking mode',
    'thinking_off': 'Off',
    'thinking_on': 'On',
    'this_folder_is_empty': 'This folder is empty',
    'this_runs_privileged_command': 'This runs a privileged action.',
    'tool_limit_reached': 'Tool limit reached ({hops} hop(s))',
    'tool_result': 'Tool result',
    'tool_round_trips': 'Tool round trips',
    'tools': 'Tools',
    'transcribe_audio': 'Transcribe or analyse this audio.',
    'troubleshooting_tips': 'Troubleshooting tips',
    'unload': 'Unload',
    'unload_before_loading_another': 'Unload the current model before loading another',
    'unpair': 'Unpair',
    'unsupported_file': 'Unsupported file',
    'untitled_chat': 'Untitled chat',
    'updating': 'Updating…',
    'url': 'URL',
    'use_buttons_to_add_files': 'Use the buttons to add files',
    'use_custom_model_id': 'Use a custom model ID',
    'user': 'User',
    'user_declined': 'The user declined this call.',
    'vae_decode_in_progress': 'VAE decode in progress',
    'validate_last_model': 'Validate last model',
    'verify_model': 'Verify model',
    'video': 'Video',
    'video_not_attached': 'Video not attached',
    'view_errors_warnings': 'View errors and warnings',
    'warning': 'Warning',
    'warning_text_only_model': 'Warning: text-only model',
    'workspace': 'Workspace',
    'workspace_not_configured': 'Workspace not configured',
    'workspace_project': 'Workspace project',
    'workspace_root': 'Workspace root',
    'yes': 'Yes',
    'you_can_change_this_folder_later': 'You can change this folder later',
    'you_need_to_download_a_model': 'You need to download a model',
      // ── Traduzidas por tool/inline_english_scan.dart ─────────────
      // A posição no fonte é o que amarra a tradução ao texto: um texto
      // repetido em dois lugares seria traduzido duas vezes, e a segunda
      // tradução é a que a tela mostra. Use `.tr` e apague o literal.
      'set_hops_hint': '0 = no cap, 1–8 = max hops',
      'mv_one_classification_model': '1 model · classification, not chat',
      'set_512_detail': '512 gives more detail but can be MUCH slower, heat the phone, and '
          'may fail on some devices.',
      'soc_gguf_answers': 'A GGUF answers with a letter or with logits, and which one is only '
          'visible after a load. The server said:',
      'soc_classification_head_console': 'A GGUF classification head carries the labels it was trained with, '
          'so /v1/classify returns them and this window has nothing to ask. '
          'The encoder console drives that one.',
      'mv_wifi_recommended': 'A Wi-Fi connection is highly recommended. Please keep the app open '
          'during the download.',
      'enc_decision_model_explains': 'A decision model answers a structured question with a class, and '
          'it is an ordinary GGUF: Tev1-0.8B loads as qwen35 and carries no '
          'flag saying so. This window shows it options and reports the '
          'letter back — which is the test, and it is also how you find out '
          'whether a model behaves like one at all.',
      'soc_head_not_recognisable': 'A head cannot be recognised by its contents — it has no '
          '`cls.output.weight` — so the caller is the only thing that can say '
          'which head it means. That name comes from the TFLite heads card, '
          'or from whatever `/v1/litert/status` reports as loaded. Neither '
          'answered, so there is nothing to send.',
      'soc_head_no_class_names': 'A head does not carry its own class names. Whoever trained it '
          'knows what class 0 is, and that is you — or whoever you are '
          'standing in for.',
      'tv_planning_steps': 'AI is planning steps…',
      'mv_add_api_key': 'Add API key',
      'set_no_think_label': 'Answer directly, no reasoning (/no_think)',
      'sv_anyone_on_network': 'Anyone on this network will be able to use the app\'s server '
          'without a key. The server listens on all interfaces, not just this '
          'phone.',
      'set_apply_template_detail': 'Apply a config template · bring models back',
      'set_think_label': 'Ask for reasoning before the answer (/think)',
      'sv_authorization_bearer': 'Authorization: Bearer <key>',
      'set_bigger_size_detail': 'Auto recommended. Bigger size = better detail, but much slower and '
          'more memory use.',
      'set_backup_configs': 'Backup configs…',
      'enc_bar_scaled': 'Bar is scaled across this result set, not from zero. A '
          'cross-encoder logit has no absolute scale — the GTE measured here '
          'runs 0,46 to 0,87 on the sigmoid over a set where one document is '
          'the answer and three are not, so a bar from zero would draw all '
          'four nearly full and hide the only thing worth looking at, which '
          'is the gap. The numbers are the absolute ones.',
      'mv_chat_template': 'CHAT TEMPLATE',
      'set_change_folder': 'Change folder…',
      'wsu_choose_folder': 'Choose workspace folder',
      'mv_configure_select': 'Configure and select',
      'set_context_size_a': 'Context Size',
      'tv_create_task_hint': 'Create a task and the AI will plan\nand execute it autonomously',
      'set_custom_search_url': 'Custom search API URL',
      'set_custom_search_token': 'Custom search API token',
      'set_daily_prompts_detail': 'Daily prompts that run on their own',
      'mv_delete_model': 'Delete model',
      'tv_describe_task': 'Describe what you want the AI to do…',
      'set_notification_detail': 'Display a persistent notification while tasks are\nscheduled or '
          'model is kept loaded in the background.',
      'mv_dont_suggest_again': 'Do not suggest this again',
      'iv_download': 'Download',
      'mv_download_any_url': 'Download a GGUF or LiteRT model from any URL',
      'mv_download_benchmark': 'Download the benchmark?',
      'set_all_cores_big_detail': 'Every core is a big one on this device',
      'tv_execute_all_steps': 'Execute All Steps',
      'mv_file_size': 'FILE SIZE',
      'set_faster_more_ram': 'Faster execution, but uses more RAM and battery',
      'mv_hide_api_key': 'Hide API key',
      'hf_hide_too_large': 'Hide GGUFs too large for this phone\'s memory',
      'mv_image_audio_input': 'Image and audio input — LiteRT-LM only',
      'mv_import_storage': 'Import from Storage',
      'mv_inspect_file': 'Inspect the file',
      'mv_keep_models_anyway': 'Keep models anyway',
      'sv_keep_key': 'Keep the key',
      'set_keep_screen_open': 'Keep this screen open',
      'set_keep_models_detail': 'Keeps the local list whatever the benchmark says, and stops it '
          'offering to hide it',
      'soc_load_one_and_probe': 'Load one and tap re-probe, or from a client: POST /v1/models/load '
          'with "filename" and "accept_risk": true. A .tflite is not a GGUF, '
          'so it does not answer here: the window finds one on its own when a '
          'head is loaded, and the TFLite heads card on the Models screen '
          'opens it by name.',
      'mv_low_memory': 'Low memory — a large model will fail to load, not run slowly.',
      'mv_model_info': 'MODEL INFO',
      'mv_model_url': 'MODEL URL',
      'set_max_speed_label': 'Maximum speed, may crash on some devices',
      'wsu_explain_projects': 'MobileLM organizes your work into projects. Pick a folder on this '
          'device — each project you start later becomes a subfolder inside '
          'it, where the app can read, create, edit and delete files.',
      'mv_model_id': 'Model ID',
      'mv_model_weights': 'Model weights',
      'set_gpu_experimental_detail': 'Models at or above this size use CPU. Smaller models can use GPU '
          'Experimental.',
      'set_more_steps_slower': 'More steps = better quality but MUCH slower!',
      'set_more_threads_detail': 'More threads, but the slowest core paces every op',
      'set_change_folder_detail2': 'Moves all existing files into the new folder',
      'encp_no_encoder': 'No encoder loaded. These settings apply to the next one.',
      'mv_no_models_loaded': 'No models loaded. Add an API key to update the live list, or use a '
          'custom model ID.',
      'tv_no_steps': 'No steps generated.',
      'set_no_tasks_detail': 'No tasks yet. A task runs its prompt every day at the chosen time '
          'with the model it was created with — even with the app closed — '
          'and posts the result here in chat.',
      'encp_nothing_overridden': 'Nothing overridden',
      'set_agent_off_detail': 'Off — the tool list is kept out of the prompt',
      'soc_litert_unload': 'POST /v1/litert/unload. The server stays up and a loaded GGUF is '
          'untouched — this frees the LiteRT model and nothing else. It is '
          'the only unload the API can do, because the GGUF one would take '
          'the server down with it.',
      'set_workspace_pick_detail': 'Pick a folder to organize your projects',
      'set_projector_cpu_detail': 'Projector runs on the CPU even when layers are on the GPU',
      'mv_provider_settings': 'Provider settings',
      'hf_qat_explained': 'QAT, QAD, QAFT — trained for 4-bit, so a Q4_0 build holds much '
          'closer to full precision',
      'sv_require_api_key': 'Require API key',
      'sv_required_by_toggle': 'Required by the toggle above',
      'set_restore_backup': 'Restore backup…',
      'set_benchmark_detail': 'Runs the 230M model and measures real speed',
      'mv_save_key_to_verify': 'Save the key to verify it and load live models.',
      'mv_saved_provider': 'Saved provider',
      'mv_search_hf': 'Search Hugging Face',
      'mv_search_models': 'Search models...',
      'mv_search_provider_or_id': 'Search provider models or enter a model ID',
      'hf_search_index': 'Search the GGUF index',
      'mv_select_model': 'Select model',
      'set_send_nothing_default': 'Send nothing — the model\'s own default',
      'mv_set_base_key_id': 'Set base URL, key, and model ID',
      'set_backup_detail': 'Settings template (API keys never leave the device) into a dated '
          'folder of your chosen location.',
      'set_settings_template_files': 'Settings template · optional model files',
      'log_share_full': 'Share full log file',
      'mv_show_api_key': 'Show API key',
      'set_show_models_ignore': 'Show models, ignore benchmarks',
      'mv_showing_local_because': 'Showing local models because you asked to ignore benchmarks.',
      'set_local_only_detail': 'Showing only what is on this device. Encoders still work.',
      'set_stable_mode_label': 'Stable mode with lower speed',
      'soc_system_one_test_b': 'System One test',
      'mv_template': 'Template',
      'set_backup_restore_detail': 'Template first, then the files in the backup folder',
      'mv_test_decision': 'Test a decision',
      'enc_test_as_decision': 'Test it as a decision instead',
      'set_show_models_ignore_detail': 'The benchmark still shows its number, but never offers to hide the '
          'local list again',
      'enc_file_decides_role': 'The file is what decides the role. A tag is an intention, and the '
          'head is a tensor.',
      'encp_loaded_reports': 'The loaded model reports',
      'encp_overrides_apply': 'The overrides below still apply. The auto-detected column is the '
          'part that needs the model.',
      'set_privileged_note': 'The privileged tools are listed under Tools. Every one of them '
          'asks before it runs, reads included.',
      'enc_scores_identical': 'The scores are identical. Nothing in this set discriminates — '
          'either the query is unrelated to every document, or the model is '
          'not scoring. The ranking below is the input order.',
      'lhc_not_zeros': 'These are not filled with zeros by the app. A head that needs them '
          'and does not get them is refused by name — a logit computed on '
          'invented features comes back wearing a confident label.',
      'ppd_choose_folder': 'This chat works inside a project folder. Choose where its files '
          'live, or keep it as a general chat.',
      'set_gpu_first_label': 'Try GPU first, then CPU fallback',
      'sv_turn_off_key': 'Turn off the API key?',
      'sv_turning_back_on': 'Turning it back on generates a new key, and anything using the old '
          'one stops working.',
      'set_hops_one': 'Agent mode: up to @n hop per message',
      'set_hops_many': 'Agent mode: up to @n hops per message',
      'set_unlimited_agent_mode': 'Unlimited agent mode',
      'mv_unload_model': 'Unload model',
      'mv_update_api_key': 'Update API key',
      'mv_openai_endpoint': 'Use any OpenAI-compatible endpoint. Enter the base URL without '
          '/chat/completions.',
      'set_workspace_folder': 'Workspace folder',
      'set_workspace_not_set_up': 'Workspace not set up',
      'set_change_folder_detail': 'Your current projects and files will be copied into the new '
          'folder, then this one will be used from now on.',
      'enc_case_paraphrase': 'a paraphrase and an unrelated pair',
      'encp_above_reported': 'above what the model reported — using the model\'s',
      'lhc_accelerator': 'accelerator — what to ask for',
      'set_auto_size': 'auto size',
      'mv_download_lower': 'download',
      'soc_free_head': 'free the compiled head',
      'enc_hide_console': 'hide the console, show the conversation',
      'enc_case_storage': 'how much storage does the offline map cache use',
      'set_custom_search_url_hint': 'https://searx.example.org/search',
      'set_custom_search_token_hint': 'leave empty for SearXNG',
      'soc_empty_uses_default': 'left empty uses the model card default',
      'soc_no_upper_limit': 'no upper limit here: a head has as many classes as it was trained '
          'with. The 24 is the decision model card\'s number.',
      'lhc_not_screened': 'not screened yet',
      'enc_case_off_domain': 'off domain — scores should flatten',
      'lhc_response_tap': 'response — tap to copy',
      'enc_run_server_off': 'run — server is off',
      'enc_case_self_match': 'self-match — the top of the range',
      'lhc_show_conversation': 'show the conversation',
      'enc_case_obvious': 'the answer is obvious',
      'soc_server_no_answer': 'the server did not answer',
      'enc_what_file_says': 'what the file says about itself',
      'soc_which_area': 'which area does this belong to?',
      // ── Texto de tela da varredura ampla (tool/broad_inline.tsv) ────
      // O casamento é por TEXTO e nunca por `arquivo:linha`: reescrever um
      // literal adjacente apaga as linhas do meio, e uma posição medida
      // antes da primeira reescrita aponta para o lugar errado — e a
      // ferramenta aceitaria, porque ela confia na posição.
      'mc_settings_folder_failed': 'Could not create the settings folder',
      'mc_config_write_failed': 'Could not write mobilelm-config.json',
      'mc_not_a_backup': 'Not a mobileLM config backup.',
      'mc_already_loading': 'Another model is already loading.',
      'mc_model_loading': 'Model Loading',
      'mc_incomplete_file': 'Incomplete Model File',
      'mc_incomplete_tip_delete': 'Delete the model and try redownloading it completely.',
      'mc_incomplete_tip_ram': 'Ensure your device has at least 2-3 GB of free RAM.',
      'mc_hide_technical': 'Hide Technical Details',
      'mc_show_technical': 'Show Technical Details',
      'mc_ram_low': 'Available RAM is lower than recommended. This can crash the app if '
          'Android cannot reserve enough memory.',
      'mc_ram_low_model': 'This can crash the app if Android cannot reserve enough memory for '
          'the model.',
      'mc_ram_more_than_file': 'Loading local models can use more memory than the file size.',
      'mc_runtime_image': 'Image model',
      'mc_import_in_progress': 'Import in Progress',
      'mc_import_wait': 'Wait for the current import to finish.',
      'mc_unsupported': 'Unsupported Model',
      'mc_import_only_formats': 'Only .gguf, .litertlm, .tflite, and .safetensors files can be '
          'imported.',
      'mc_import_unreadable': 'Unable to read the selected file. Try selecting it from local '
          'storage.',
      'mc_select_file': 'Select a model file...',
      'mc_cancel': 'Cancel',
      'mc_download_failed': 'Download Failed',
      'mc_download_unavailable': 'Download Unavailable',
      'mc_no_download_url': 'This model has no download URL.',
      'mc_android_only': 'Android Only',
      'mc_android_only_detail': 'Use the app download button or import a local model on this '
          'platform.',
      'mc_download_starting': 'Starting download...',
      'mc_download_started': 'Download Started',
      'mc_arch_unsupported': 'This GGUF uses a model architecture that is not supported by the '
          'bundled llama.cpp runtime. Update the app runtime or try a GGUF '
          'exported for a supported architecture.',
      'mc_split_missing': 'This appears to be a split GGUF model, but one or more required '
          'model files are missing. Import every split into the same folder '
          'before loading it.',
      'mc_file_corrupt': 'The model file appears to be incomplete or corrupted. This usually '
          'happens when the download is interrupted or the file is invalid.',
      'mc_out_of_memory': 'Your device ran out of memory (RAM) trying to load this model. '
          'Mobile devices have strict memory limits; try using a smaller or '
          'more heavily quantized model (e.g., 1B or 3B parameters, q4_k_m '
          'quantized).',
      'mc_hw_error': 'A hardware or GPU driver error occurred while initializing the '
          'model. Try disabling GPU acceleration or switching to CPU-only '
          'inference in Settings.',
      'mc_native_error': 'The native AI engine encountered an unexpected error while loading '
          'the model. Please check the technical details below for more '
          'information.',
      'mv_no_online_model': 'No online model selected',
      'mv_save_key': 'Save Key',
      'mv_verifying': 'Verifying...',
      'mv_one_download': '1 download in progress · its own bar is on its card',
      'mv_benchmark_running': 'Benchmark running…',
      'mv_benchmark_usability': 'Benchmark usability',
      'mv_bench_cpu_safe': 'CPU Safe mode, one short question. Takes a few seconds to load the '
          'model, then a few to answer.',
      'mv_bench_what_it_does': 'Runs the 230M model in CPU Safe mode and reports your real tok/s, '
          'so you know whether a local model is worth the download.',
      'mv_bench_what_it_does2': 'Downloads the 230M model and runs it in CPU Safe mode, then '
          'reports your real tok/s. Nothing is downloaded or run until you '
          'tap.',
      'mv_bench_fast': 'Fast enough for local models. 1B and under should be comfortable; '
          'larger ones are worth trying before you download them.',
      'mv_bench_cpu_nothing': 'The CPU returned nothing. Cloud models are the reliable choice on '
          'this device.',
      'mv_bench_cpu_path_nothing': 'The CPU path returned nothing, so local models are not going to '
          'work here. Use the cloud models — and if this repeats, the engine '
          'is the problem rather than the model size.',
      'mv_hide_list': 'Hide the local model list',
      'mv_list_hidden': 'Local list hidden',
      'mv_not_now': 'Not now',
      'mv_clear_form': 'Clear form',
      'mv_enter_model_name': 'Enter model name',
      'mv_enter_model_url': 'Enter model URL',
      'mv_enter_description': 'Enter description',
      'mv_url_example': 'https://huggingface.co/…/model.gguf',
      'mv_display_name_hint': 'Display name  (e.g. Qwen3-0.6B)',
      'mv_projector_incomplete': 'Projector download did not complete',
      'mv_no_mmproj': 'No mmproj file found in the models folder yet. Open HF search, '
          'download the projector for this repo, come back here.',
      'mv_loading': 'Loading...',
      'mv_bad_url': 'Invalid URL format. Must start with http:// or https://',
      'mv_size_unresolved': 'Could not resolve file size. Ensure the URL is accessible.',
      'set_scrape_chain': 'Using the scrape chain.',
      'set_gpu_safety_off': 'GPU Safety is off. Large models may crash or freeze on GPU.',
      'set_gpu_safety_high': 'High GPU Safety allows larger models on GPU and may crash, freeze, '
          'or overheat some phones.',
      'set_ctx_may_crash': 'Your phone may crash with this value!',
      'set_ctx_warning': 'Warning: values above 8192 may cause your device to run out of '
          'memory. Continue only if your device has sufficient RAM.',
      'set_ctx_capped': 'Context capped at 4096 to prevent driver memory crash for LiteRT '
          'models.',
      'set_ctx_all_ram': 'Context this large will eat all your RAM!',
      'set_ws_move_failed': 'Could not move the workspace.',
      'set_ws_moved': 'Workspace moved and active.',
      'set_hops_label': 'Set max hops (1–8), or 0 for no cap of your own',
      'set_no_local_files': 'No local model files found.',
      'set_field_name': 'Name',
      'sc_what_is_here': 'What is on this phone',
      'sc_load_downloaded': 'Load a downloaded model',
      'sc_download_catalogue': 'Download one from the catalogue',
      'sc_download_here': 'Download models to this phone',
      'sc_unload': 'Unload or replace the running model',
      'sc_list_here': 'List what is on the phone',
      'sc_use_for_inference': 'Use the phone for inference',
      'sc_network_warning': 'Anyone on this network can use this server.',
      'soc_no_address': 'The API server has no address yet.',
      'soc_no_address_hint': 'the API server has not reported an address yet — open Settings, '
          'API server, and start it',
      'soc_nothing_freed': 'Nothing was loaded, so nothing was freed.',
      'soc_nothing_loaded': 'nothing loaded',
      'soc_is_head': 'this one is a head with a label set of its own',
      'soc_head_labels': 'head with its own labels — the encoder console drives that one',
      'soc_not_decided': 'not decided yet — no GGUF is loaded',
      'soc_state': 'the state — the data being judged',
      'soc_question': 'the question — optional',
      'soc_system': 'the system instruction — optional',
      'soc_default_ok': 'The default already says the three things that matter: treat the '
          'state as data, pick exactly one, return only the letter.',
      'soc_run_head': 'run the head',
      'soc_no_tflite': 'no .tflite to name',
      'soc_left_empty': 'Left empty, this is not sent at all and the endpoint will say '
          'which one it wanted.',
      'soc_left_empty2': 'Left empty, this is not sent at all. Zeros are never substituted: '
          'a logit computed on invented features is a number with no meaning, '
          'and it comes back with a label.',
      'soc_options': 'the options — 2 to 24, the model card\'s number',
      'soc_json_envelope': 'Sent inside a JSON envelope, never as instructions. A ticket with '
          'quotes and braces must not be able to change the shape of the '
          'question.',
      'soc_copy': 'copy',
      'soc_answer': 'the answer',
      'soc_refused': 'the run was refused',
      'soc_reprobe_failed': 'Re-probe failed, so what is shown below is from the file as it was '
          'last read. The run will use the server\'s own answer.',
      'enc_needs_bert': 'This console scores one query against a model, so it needs a '
          'BERT\nor ModernBERT. A GGUF without that shape cannot be tested '
          'here.',
      'enc_no_output': 'This conversion has no output',
      'enc_works_reranker': 'A reranker that works here: gte-reranker-modernbert-base-Q8_0.gguf',
      'enc_works_embed': 'An embedding model that works: bge-small-en-v1.5-f16.gguf',
      'enc_server_off': 'server not running — tap to retry',
      'enc_aux_bad_json': 'auxiliary must be a JSON object of name → numbers',
      'enc_tap_to_copy': 'tap to copy',
      'enc_copied': 'the JSON response is on the clipboard',
      'enc_role_embed': 'Embeddings turn text into one vector each.',
      'enc_role_rerank': 'Rerankers score a query against each document.',
      'enc_reread': 're-read',
      'enc_asym_query': 'Prepended to a plain `input`. The other half of the same asymmetry '
          '— a model trained with both sides marked returns vectors built for '
          'one kind of text if you mark neither.',
      'enc_normalize': 'Auto follows the model. Off returns the raw vector, for a caller '
          'doing its own normalisation.',
      'enc_top_n': 'How many documents come back. A request that sends its own `top_n` '
          'wins over this.',
      'enc_split_newline': 'Used when `documents` arrives as one string. A newline cannot be '
          'told from a paragraph break, so a document sent with blank lines '
          'in it comes back split and ranked, with nothing to indicate it.',
      'enc_prob': 'Adds `relevance_score_probability` next to the raw logit. The '
          'logit is left alone either way — it is the measured contract, and '
          'a cross-encoder\'s sigmoid is not calibrated anyway.',
      'enc_echo': 'Echoes each document back with its score, the way Cohere does. Off '
          'halves the response on a long list.',
      'hf_nothing_loadable': 'Nothing loadable in this repo. Split archives and LiteRT builds '
          'for other vendors\' accelerators are skipped.',
      'hf_mergekit': 'Made with mergekit',
      'hf_format': 'FORMAT',
      'hf_this_device': 'THIS DEVICE',
      'lit_still_compiling': 'LiteRT accepted the file 90 s ago and still has not reported it '
          'compiled. The compile log is in Settings, Log.',
      'lit_screen_first': 'screen a .tflite first — nothing to run',
      'chat_image_failed': '❌ Local image generation failed.',
      'chat_image_here': 'Here is your generated image:',
      'chat_privileged': 'This runs a privileged command.',
      'chat_only_media': 'Only images, video, audio, PDF, DOCX, and text/code files are '
          'supported.',
      'chat_no_frames': 'No frames could be read from this video.',
      'chat_vae_decoding': 'VAE decode in progress…',
      'chat_just_now': 'Just now',
      'chat_show_conversation': 'show conversation',
      'chat_attached_file': 'Attached file:',
      'widget_generated_with': 'Generated with mobileLM',
      'ws_new_name': 'New name',
      'ws_rename_failed': 'Rename failed.',
      'ws_folder_name': 'Folder name',
      'ws_create_folder_failed': 'Could not create folder (name may be taken).',
      'ws_file_name': 'File name (e.g. notes.md)',
      'ws_create_file_failed': 'Could not create file (name may be taken).',
      'ws_setup_none': 'No folder chosen yet. Pick one to continue.',
      'task_no_exec': 'Command execution is not available.',
      'task_cancel': 'Cancel',
      'cloud_nim': 'OpenAI compatible hosted NIM models',
      'cloud_url_required': 'Base URL is required.',
      'cloud_url_invalid': 'Enter a valid OpenAI-compatible base URL.',
      'cloud_free_list': 'Free model list · OpenAI compatible',
      'cloud_native_openai': 'Native OpenAI chat models',
      'cloud_v4': 'OpenAI compatible V4 models',
      'cloud_gemini': 'Gemini native API models',
      'set_unknown_gpu': 'Unknown GPU',
      'enc_doc_example': 'The map cache holds about 340 MB per city.\nThe cache is cleared '
          'from Settings.\nOlive oil is pressed cold.',
    },
    'pt_BR': {
      'sc_section_endpoints': 'ENDPOINTS',
      'sc_section_examples': 'EXEMPLOS DE USO',
      'sc_title_running': 'Servidor de API rodando',
      'sc_title_stopped': 'Servidor de API parado',
      'sc_subtitle_stopped': 'Exponha seu modelo local como uma API da OpenAI.',
      'sc_section_security': 'SEGURANÇA',
      'sc_generate_key': 'Gerar',
      'sc_copy': 'Copiar',
      'set_task_updated': 'Tarefa atualizada.',
      'set_warning_title': '⚠ Aviso',
      'cc_auto_size': 'Tamanho automático',
      'cc_error_bubble': '❌ Erro: @e',
      'chat_image_gen_line': 'Gerar imagem · @s @u · @z · @b',
      'chat_image_gen_step': 'passo',
      'chat_image_gen_steps': 'passos',
      'cm_built_in_list': 'Lista embutida',
      'cm_not_fetched': 'Ainda não buscada',
      'cm_updated_now': 'Atualizada agora',
      'cm_updated_min': 'Atualizada há @n min',
      'cm_updated_hour': 'Atualizada há @n h',
      'cm_updated_day': 'Atualizada há @n d',
      'cm_cloud_active': 'Modelo de nuvem ativo',
      'cm_api_key_required': 'A chave de API é obrigatória.',
      'cm_model_id_required': 'O ID do modelo é obrigatório.',
      'mc_backup': 'Backup',
      'mc_no_folder_selected': 'Nenhuma pasta escolhida',
      'mc_backup_saved': 'Salvo: configurações em settings/ + modelos nas pastas '
          'Vendor/Family',
      'mc_backup_failed': 'Falha no backup',
      'mc_restore': 'Restauração',
      'mc_restore_applied': 'Configurações aplicadas. Reinicie para recarregar tudo.',
      'mc_restore_applied_count': 'Configurações aplicadas (@s valor(es)) · @m arquivo(s) de modelo '
          'restaurado(s)',
      'mc_restore_no_files': 'Nenhum arquivo de modelo encontrado na pasta do backup.',
      'mc_restore_count': '@n arquivo(s) de modelo restaurado(s)',
      'mc_restore_failed': 'Falha na restauração',
      'mc_helper_file': 'Arquivo auxiliar',
      'mc_helper_file_detail': '@f é usado internamente pela geração de imagens e não pode ser '
          'carregado como modelo.',
      'mc_corrupt_file': 'Arquivo de modelo corrompido',
      'mc_corrupt_detail': '@f não baixou corretamente. Apague e baixe de novo.',
      'mc_not_valid_litert': '@f não é um arquivo LiteRT-LM válido. Apague e baixe de novo.',
      'mc_image_model': 'Modelo de imagem',
      'mc_model_not_loaded': 'Modelo não carregado',
      'mc_model_loaded': 'Modelo carregado',
      'mc_check_arch': 'Confira se este arquivo LiteRT-LM bate com sua arquitetura.',
      'mc_runtime_local': 'modelo local',
      'mc_already_loaded': 'Este modelo já está carregado.',
      'mc_already_loaded_named': 'Já carregado: @l',
      'mc_memory_optimized': 'Memória otimizada',
      'mc_memory_freed': '"@l" foi descarregado para liberar memória para o novo modelo.',
      'mc_api_server_stopped': 'Servidor de API parado',
      'mc_api_server_stopped_detail': 'Ele serve o modelo que acabou de ser descarregado.',
      'mc_import_failed': 'Falha na importação',
      'mc_import_empty': 'O arquivo escolhido está vazio.',
      'mc_local_file': 'Arquivo local',
      'sc_port_occupied': 'Porta ocupada',
      'sc_port_in_use': 'A porta @a já está em uso. O servidor vai rodar na @b.',
      'sc_starting': 'Iniciando o servidor...',
      'sc_running': 'Servidor rodando',
      'sc_failed': 'Falha no servidor',
      'sc_stopped': 'Servidor parado',
      'set_search_endpoint_hint': 'Opcional. Vazio significa Brave → Startpage → DuckDuckGo.',
      'set_benchmark_running': 'Rodando…',
      'set_projector_auto_detail': 'Auto — medido uma vez, o backend mais rápido fica',
      'mc_restore_will_overwrite': '@s valor(es) salvo(s) vão sobrescrever os atuais.',
      'mc_switch_needs_restart': 'Você já usou @c nesta sessão do app. Trocar para @t sem reiniciar '
          'pode travar o runtime nativo.\n\nReinicie o app e então carregue '
          'este modelo.',
      'mc_litert_speed_title': '@m no LiteRT',
      'mc_model_already_imported': 'Já existe um arquivo de modelo chamado "@f" importado no '
          'armazenamento local do app. Quer carregar a cópia que já está lá?',
      'mc_restart_recommended': 'Reinício recomendado',
      'mc_unknown_size': 'Tamanho desconhecido',
      'log_copy_important': 'Copiar logs importantes',
      'log_clear': 'Limpar logs',
      'log_copied': 'Copiado',
      'log_copied_detail': 'Logs importantes copiados para a área de transferência.',
      'ws_back_to_projects': 'Voltar aos projetos',
      'ws_refresh': 'Atualizar',
      'pp_new_project_name': 'Nome do novo projeto',
      'pp_name_hint': 'ex.: meu-site',
      'set_cpu_benchmark': 'Benchmark da CPU',
      'set_device_budget':
          'Disponível: @ram GB · Contexto: @ctx · Tokens: @tok',
      'mv_show_it_anyway': 'Mostrar mesmo assim',
      'mv_cloud_provider_name': 'Nome do provedor',
      'mv_cloud_base_url': 'URL base',
      'mv_projector': 'Projetor',
      'sc_turn_off_anyway': 'Desligar mesmo assim',
      'mc_load_model': 'Carregar modelo?',
      'mc_gpu_may_crash': 'A GPU pode deixar os modelos LiteRT bem mais rápidos, perto da '
          'velocidade do Edge Gallery. Em alguns aparelhos a GPU/OpenCL pode '
          'travar o app durante o carregamento. Se acontecer, o Auto Fast vai '
          'usar a CPU no próximo carregamento.',
      'mv_section_downloaded': 'Baixados',
      'mv_section_image': 'Imagem',
      'mv_section_custom_gguf': 'Modelos GGUF personalizados',
      'mv_section_custom_litert': 'Modelos LiteRT personalizados',
      'mv_section_custom_tflite': 'Modelos TFLite personalizados',
      'mv_gpu_layers': '⚡ @w (@n camadas)',
      'mv_import_local_or_url': 'Importe um modelo local ou adicione uma URL para baixar.',
      'chat_no_project': 'Sem projeto',
      'enc_tap_to_fill': 'toque para preencher',
      'hf_fits_device': 'Cabe neste aparelho',
      'log_no_file': 'Sem arquivo de log',
      'log_none_of_filter': 'Nenhuma mensagem de @f',
      'mv_no_models_yet': 'Nenhum modelo ainda',
      'mv_no_model_selected': 'Nenhum modelo selecionado',
      'mv_api_key': 'Chave de API',
      'mv_add_key': 'Adicionar chave',
      'mv_no_projector_paired': 'Nenhum projetor pareado',
      'mv_added_custom_url': 'Modelo personalizado adicionado por URL',
      'mv_layers_label': '(@n camadas)',
      'sv_api_key_off': 'Chave de API desligada',
      'sv_not_available': 'Indisponível',
      'sv_health_failed': 'A verificação falhou',
      'set_all_from_model': 'Tudo do modelo',
      'set_task_created': 'Tarefa criada.',
      'soc_no_feature_vector': 'Sem vetor de features.',
      'soc_ask_for_the_letter': 'peça a letra',
      'wv_new_folder': 'Nova pasta',
      'wv_new_file': 'Novo arquivo',
      'ap_text_file': 'Arquivo de texto',
      'log_nothing_written': 'Nada foi escrito em disco ainda.',
      'chat_from_gallery': 'Da galeria',
      'encp_file_says': 'o arquivo diz que é',
      'sv_port_label': 'PORT',
      'set_error_label': 'Erro',
      'soc_which_shape': 'qual forma é esta?',
      'soc_server_said': 'O servidor disse:',
      'soc_loaded_name': 'carregado: @l',
      'soc_the_feature_vector': 'o vetor de features',
      'wv_delete_failed': 'A exclusão falhou.',
      'soc_run_now': 'executando',
      'encp_unknown': 'desconhecido',
      'hf_search_failed': 'A busca falhou: @e',
      'set_failed': 'Falhou: @e',
      'mv_name_label': 'Nome',
      'mv_size_label': 'Tamanho',
      'mv_memory_label': 'Memória',
      'mv_state_loaded': 'carregado',
      'mv_state_ready': 'PRONTO',
      'mv_state_downloaded': 'BAIXADO',
      'mv_load_action': 'Carregar',
      'sv_port_field': 'Porta',
      'sv_local_model_ready': 'Modelo local pronto',
      'sv_no_model_loaded': 'Nenhum modelo carregado — os endpoints de chat e de encoder vão '
          'recusar; a gestão de modelos continua funcionando',
      'set_model_label': 'Modelo',
      'soc_local_models': 'modelos locais',
      'enc_more_items': '… mais @n',
      'lhc_not_bindable': 'não vinculável — @r',
      'lhc_never_read_yet': '(não lido ainda)',
      'lhc_not_loaded_yet': '(não carregado ainda)',
      'lhc_unknown': 'desconhecido',
      'lhc_accelerator_not_exposed': 'LiteRT 2.2.0 não expõe o acelerador que usou, então este console '
          'não pode dizer. No aparelho, LITERT_CL ou CPU no log é a resposta.',
      'lhc_status_available': 'o aparelho relata: @a',
      'lhc_status_requested': 'pedido: @q',
      'lhc_status_executed': 'executado: @e — @n',
      'lhc_status_failed': 'a chamada de status falhou: @e',
      'lhc_top_index_note': 'top_index @t por argmax de @m. Isso é um argmax e não uma '
          'predição: é a leitura certa só para uma cabeça treinada assim, e '
          'não há rótulo aqui porque só quem chama sabe o que é a classe 0.',
      'mv_paste_provider_key': 'Cole a chave de @p',
      'tv_steps_status': '@n passos · @s',
      'chat_model_origin': '@m · @o',
      'chat_loading_pct': 'Carregando modelo… @p%',
      'encp_load_error': 'Não foi possível ler o modelo carregado: @e',
      'hf_checkpoint_says': 'o checkpoint diz: @a',
      'lhc_feature_vector': 'O vetor de features preenche "@n" (@c valores) — a maior entrada. '
          '@rest',
      'mv_local_models': 'MODELOS LOCAIS (@n)',
      'mv_download_benchmark_note': '"@n" tem @s. É o menor modelo aqui, e é ele que mede se este '
          'aparelho roda um modelo qualquer. Sem ele o teste não roda.',
      'mv_cloud_provider': 'NUVEM · @p',
      'mv_select_provider_model': 'Selecionar modelo de @p',
      'mv_provider_model_count': '@n modelos - @f',
      'mv_custom_provider_model': 'Modelo @p personalizado',
      'mv_delete_filename': '@f será removido permanentemente deste aparelho.',
      'mv_vision_model': 'Visão · @m',
      'mv_memory_free': '@f livres de @t',
      'set_threads_auto': 'Threads: Automático — os núcleos grandes (@n)',
      'set_cores_left_out': 'Núcleos cpu0-@n fora; o ggml sincroniza todas as threads no fim de '
          'cada operação e uma lenta marca o ritmo',
      'soc_what_will_send': 'o que a janela vai enviar: @o',
      'soc_the_model_said': 'o modelo disse: @r',
      'soc_no_confidence': 'sem confiança, e este é o motivo: @w',
      'soc_model_label': 'modelo: @m',
      'lhc_no_auxiliary': 'Não há outras entradas.',
      'lhc_auxiliary': 'As outras entradas são suas: @t. Elas nunca são preenchidas com '
          'zeros.',
      // App basics
      'app_title': 'mobileLM',
      'app_started': 'App iniciado',
      'firebase_init_failed': '[Firebase] Inicialização falhou',
      'no_stack': 'Sem stack trace',
      
      // Common actions
      'settings': 'Configurações',
      'home': 'Início',
      'chat': 'Conversa',
      'workspace': 'Espaço de trabalho',
      'models': 'Modelos',
      'tools': 'Ferramentas',
      'logs': 'Logs',
      
      // Buttons
      'send': 'Enviar',
      'cancel': 'Cancelar',
      'ok': 'OK',
      'yes': 'Sim',
      'no': 'Não',
      'close': 'Fechar',
      'delete': 'Excluir',
      'edit': 'Editar',
      'save': 'Salvar',
      'reset': 'Redefinir',
      'refresh': 'Atualizar',
      'search': 'Pesquisar',
      'filter': 'Filtrar',
      'sort': 'Ordenar',
      
      // Input placeholders
      'chat_placeholder': 'Digite sua mensagem...',
      'search_placeholder': 'Pesquisar...',
      'name_placeholder': 'Nome...',
      'model_placeholder': 'Selecionar modelo...',
      
      // Status messages
      'loading': 'Carregando...',
      'please_wait': 'Por favor, aguarde...',
      'success': 'Sucesso!',
      'error': 'Erro',
      'warning': 'Aviso',
      'info': 'Informação',
      'saving': 'Salvando...',
      'deleting': 'Excluindo...',
      'updating': 'Atualizando...',
      'connected': 'Conectado',
      'disconnected': 'Desconectado',
      'offline': 'Offline',
      'online': 'Online',
      
      // Model-related
      'model_loaded': 'Modelo carregado',
      'model_unloaded': 'Modelo descarregado',
      'loading_model': 'Carregando modelo...',
      'downloading_model': 'Baixando modelo...',
      'model_not_found': 'Modelo não encontrado',
      'context_size': 'Tamanho do contexto',
      'max_tokens': 'Máximo de tokens',
      'temperature': 'Temperatura',
      'inference_mode': 'Modo de inferência',
      'local': 'Local',
      'cloud': 'Nuvem',
      'auto_configure_for_device': 'Configuração automática para dispositivo',
      
      // Settings
      'general': 'Geral',
      'appearance': 'Aparência',
      'advanced': 'Avançado',
      'about': 'Sobre',
      'language': 'Idioma',
      'theme': 'Tema',
      'light': 'Claro',
      'dark': 'Escuro',
      'system': 'Sistema',
      'font_scale': 'Escala da fonte',
      'enable_tools': 'Habilitar ferramentas',
      'agent_max_hops': 'Máximo de saltos do agente',
      'thinking_mode': 'Modo de pensamento',
      'thinking_on': 'Ativado',
      'thinking_off': 'Desativado',
      'thinking_auto': 'Automático',
      
      // Chat-specific
      'new_chat': 'Nova conversa',
      'untitled_chat': 'Conversa sem título',
      'message': 'Mensagem',
      'user': 'Usuário',
      'assistant': 'Assistente',
      'tool_result': 'Resultado da ferramenta',
      'thinking': 'Pensando...',
      'no_thought': 'Sem pensamento',
      'streaming': 'Transmitindo...',
      'generation_complete': 'Geração concluída',
      'generation_failed': 'Falha na geração',
      'stop_generation': 'Parar geração',
      
      // Attachments
      'attach_file': 'Anexar arquivo',
      'remove_attachment': 'Remover anexo',
      'image': 'Imagem',
      'video': 'Vídeo',
      'audio': 'Áudio',
      'document': 'Documento',
      'text_file': 'Arquivo de texto',
      'describe_image': 'Descreva esta imagem.',
      'summarize_pdf': 'Resuma este PDF.',
      'summarize_document': 'Resuma este documento.',
      'context_summary': 'Conversa resumida ({{count}} mensagens antigas condensadas)',
      'context_summary_continue': 'Continue a conversa a partir daqui.',
      'describe_video': 'Descreva o que acontece neste vídeo.',
      'transcribe_audio': 'Transcreva ou analise este áudio.',
      'review_file': 'Revise este arquivo.',
      'review_attachment': 'Revise este anexo.',
      'file_truncated': '[Arquivo truncado para tamanho de contexto]',
      'could_not_extract': '[Não foi possível extrair texto de',
      
      // Tools
      'running_tool': 'Executando {tool}...',
      'tool_limit_reached': 'Limite de ferramentas atingido ({hops} salto(s))',
      'confirm_tool_execution': '{tool} quer alterar algo neste dispositivo.',
      'this_runs_privileged_command': 'Este comando executa uma ação privilegiada.',
      'runs_as': 'Executa como',
      'deny': 'Negar',
      'allow': 'Permitir',
      'user_declined': 'O usuário recusou esta chamada.',
      
      // Image generation
      'image_generation': 'Geração de imagem',
      'generating_image': 'Gerando imagem...',
      'sampling_complete': 'Amostragem concluída',
      'vae_decode_in_progress': 'Decodificação VAE em progresso',
      'image_generation_failed': 'Falha na geração de imagem local.',
      'steps': 'Passos',
      'estimated_time': 'Tempo estimado',
      'seconds': 'segundos',
      
      // Speech-to-text
      'speech_to_text': 'Fala para texto',
      'listening': 'Ouvindo...',
      'speech_not_available': 'Reconhecimento de fala não disponível',
      'initialize_speech': 'Inicializando reconhecimento de fala...',
      
      // Workspace
      'workspace_root': 'Raiz do workspace',
      'no_project': 'Nenhum projeto',
      'select_project': 'Selecionar projeto',
      'create_new_project': 'Criar novo projeto',
      'project_created': 'Projeto criado',
      'project_not_found': 'Projeto não encontrado',
      'open_project': 'Abrir projeto',
      'go_to_root': 'Ir para raiz',
      
      // Model controller
      'downloading': 'Baixando',
      'verify_model': 'Verificar modelo',
      'model_verified': 'Modelo verificado',
      'model_verification_failed': 'Falha na verificação do modelo',
      'last_model': 'Último modelo',
      'validate_last_model': 'Validar último modelo',
      
      // Privileged service (Shizuku)
      'privileged_service': 'Serviço privilegiado',
      'shizuku_required': 'Shizuku necessário',
      'shizuku_not_available': 'Shizuku não disponível',
      'root_access': 'Acesso root',
      
      // Crash reporting
      'crash_reporting': 'Relatório de falhas',
      'sending_crash_report': 'Enviando relatório de falha...',
      'crash_report_sent': 'Relatório de falha enviado',
      'crash_report_failed': 'Falha ao enviar relatório de falha',
      
      // Scheduled tasks
      'scheduled_task': 'Tarefa agendada',
      'task_at': 'Tarefa às',
      'task_completed': 'Tarefa concluída',
      'task_failed': 'Tarefa falhou',
      
      // Download service
      'download': 'Download',
      'download_complete': 'Download concluído',
      'download_failed': 'Download falhou',
      'removing': 'Removendo...',
      
      // Constants
      'mobile_br': 'mobileLM',
      // LLM Prompts (these will be used in inference)
      'prompt_system': 'Você é um assistente prestativo que responde em português brasileiro.',
      'prompt_system_think': 'Você é um assistente prestativo que pensa antes de responder. Responda em português brasileiro.',
      'prompt_system_no_think': 'Você é um assistente prestativo que responde diretamente sem pensar demais. Responda em português brasileiro.',
      'prompt_think_tag': '/think',
      'prompt_no_think_tag': '/no_think',
        'warning_text_only_model': 'Aviso: Modelo apenas de texto',
        'video_not_attached': 'Vídeo não anexado',
        'unsupported_file': 'Arquivo não suportado',
        'file_not_attached': 'Arquivo não anexado',
        'file_attachment_failed': 'Falha ao anexar arquivo',
        
        // Page titles
        'how_can_i_help': 'Como posso ajudar?',
      'unload': 'Descarregar',
      'troubleshooting_tips': 'Dicas de Solução de Problemas',
      'tasks': 'Tarefas',
      'small': 'Pequeno',
      'set_up_your_workspace': 'Configure seu workspace',
      'server': 'Servidor',
      'scheduled_tasks': 'Tarefas Agendadas',
      'restore_backup': 'Restaurar backup',
      'restore': 'Restaurar',
      'restart_required': 'Reinicialização necessária',
      'restart_app': 'Reiniciar app',
      'restart': 'Reiniciar',
      'replace_file': 'Substituir Arquivo',
      'recommended': 'Recomendado',
      'providers': 'Provedores',
      'prompt_to_run': 'Prompt para executar',
      'off_the_tool_list_is_kept_out_of_the_prompt': 'Desligado — a lista de ferramentas é mantida fora do prompt',
      'no_tasks_yet_a_task_runs_its_prompt_every_day_at_the': 'Nenhuma tarefa ainda. Uma tarefa executa seu prompt todo dia às',
      'no_tasks_yet': 'Nenhuma Tarefa Ainda',
      'no_models_downloaded_yet': 'Nenhum modelo baixado ainda',
      'no_local_models': 'Nenhum Modelo Local',
      'no_conversations_yet': 'Nenhuma conversa ainda',
      'multimodal_model': 'Modelo Multimodal',
      'model_load_failed': 'Falha ao Carregar Modelo',
      'model_already_exists': 'Modelo Já Existe',
      'loading_into_memory': 'Carregando na memória',
      'later': 'Depois',
      'large': 'Grande',
      'image_size': 'Tamanho da Imagem',
      'image_gen_steps': 'Passos de Geração de Imagem',
      'image_backend': 'Backend de Imagem',
      'gpu_safety': 'Segurança da GPU',
      'gpu': 'GPU',
      'get': 'Obter',
      'font_size': 'Tamanho da Fonte',
      'filters': 'Filtros',
      'edit_model': 'Editar Modelo',
      'download_now': 'Baixar Agora',
      'download_model': 'Baixar Modelo',
      'download_a_gguf_or_litert_model_from_any_url': 'Baixe um modelo GGUF ou LiteRT de qualquer URL',
      'default_system_prompt': 'Prompt de Sistema Padrão',
      'daily_prompts_that_run_on_their_own': 'Prompts diários que rodam automaticamente',
      'custom_provider': 'Provedor Personalizado',
      'conversations': 'Conversas',
      'backup_configs': 'Backup de configs',
      'api_key_required': 'Chave da API necessária',
      'all_clear': 'Tudo Limpo',
      'add_model_url': 'Adicionar URL do Modelo',
      'add_model': 'Adicionar Modelo',
      'add_attachment': 'Adicionar Anexo',
      'active_model': 'Modelo Ativo',
      'active_image_model': 'Modelo de Imagem Ativo',
      'url': 'URL',
      'test_local': 'Testar local',
      'select_model': 'Selecionar modelo',
      'start_backup': 'Iniciar backup',
      'all': 'Todos',
      'any': 'Qualquer',
      'apply': 'Aplicar',
      'at_this_minute_past_each_interval': 'Neste minuto de cada intervalo',
      'at_this_time_every_day': 'Neste horário todos os dias',
      'cpu': 'CPU',
      'change': 'Alterar',
      'change_workspace_folder': 'Alterar pasta do workspace?',
      'configs_template_json': 'Template de configs (.json)',
      'confirm_delete': 'Confirmar exclusão',
      'continue': 'Continuar',
      'copies_the_file_into_the_models_folder': 'Copia o arquivo para a pasta de modelos',
      'create': 'Criar',
      'create_project': 'Criar projeto',
      'daily': 'Diário',
      'delete_model': 'Excluir modelo?',
      'download_the_mmproj_via_the_hf_search_th': 'Baixe o mmproj pela busca HF, depois vincule aqui',
      'edit_task': 'Editar tarefa',
      'every_2h': 'A cada 2h',
      'every_4h': 'A cada 4h',
      'every_6h': 'A cada 6h',
      'every_8h': 'A cada 8h',
      'everything_configs___models': 'Tudo (configs + modelos)',
      'file': 'Arquivo',
      'fits_my_device': 'Compatível com meu dispositivo',
      'folder': 'Pasta',
      'from_hugging_face': 'Do Hugging Face',
      'go_to_models': 'Ir para Modelos',
      'grant_permission': 'Conceder permissão',
      'hello': 'Olá.',
      'hourly': 'Horário',
      'how_can_i_help_you_today': 'Como posso ajudar hoje?',
      'image_saved_to_gallery': 'Imagem salva na galeria',
      'import': 'Importar',
      'include_model_files': 'Incluir arquivos do modelo',
      'just_once': 'Apenas uma vez',
      'keep_model_loaded_between_runs': 'Manter modelo carregado entre execuções',
      'model_files_from_the_backup_folder': 'Arquivos do modelo da pasta de backup',
      'new_daily_task': 'Nova tarefa diária',
      'new_task': 'Nova tarefa',
      'no_projects_yet___create_one_to_get_star': 'Nenhum projeto ainda — crie um para começar.',
      'no_projects_yet': 'Nenhum projeto ainda.',
      'none': 'Nenhum',
      'overwrites_current_settings': 'Sobrescreve configurações atuais',
      'pick_from_device_storage': 'Escolher do armazenamento do dispositivo',
      'projects': 'Projetos',
      're_check': 'Verificar novamente',
      'rename': 'Renomear',
      'required_before_selecting_live_models': 'Obrigatório antes de selecionar modelos ao vivo',
      'run_this_single_time_at_the_chosen_hour': 'Executar esta única vez na hora escolhida',
      'save_and_select': 'Salvar e Selecionar',
      'select': 'Selecionar',
      'show_background_notification': 'Mostrar notificação em segundo plano',
      'skips_files_already_present_and_identica': 'Ignora arquivos já presentes e idênticos',
      'this_folder_is_empty': 'Esta pasta está vazia',
      'unpair': 'Desvincular',
      'use_custom_model_id': 'Usar ID de modelo personalizado',
      'workspace_project': 'Projeto do workspace',

      // ── As 38 chaves que faltavam ──────────────────────────────────────────
      // Cada uma destas é chamada com `.tr` em pelo menos um lugar do app e
      // **não** existia neste mapa, o que fazia o GetX devolver a própria chave:
      // o usuário lia literalmente `tool_round_trips` num item de Configurações,
      // e `mobile_lm` no Sobre. Uma auditoria de todos os `.tr` contra este
      // mapa achou 38 de uma vez — nenhuma delas é uma chave solta, é um
      // arquivo de traduções que cresceu sem o mapa acompanhando.
      //
      // Estão num bloco só porque chegaram juntas; um passe futuro pode
      // dissolvê-las nos temas acima. `test/l10n_keys_test.dart` falha se voltar
      // a faltar uma, e é ele que impede a próxima leva.
      //
      // As três com placeholder (`$name`, `$min`, `$max`) são as **primeiras**
      // deste mapa a ter um: o consumidor faz `.replaceAll('\$min', ...)`, então
      // o valor precisa conter o texto `$min` literalmente — daí o `\$` aqui, e
      // não o `$` solto, que o Dart tentaria interpolar.
      'adb_shizuku': 'ADB e Shizuku',
      'applies_to_local_and_cloud': 'Vale para o local e para a nuvem',
      'as_identity': 'Executando como',
      'available_ram': 'RAM disponível',
      'cloud_api': 'API na nuvem',
      'cloud_models_support_images_and_text_files':
          'Modelos na nuvem aceitam imagens e arquivos de texto',
      'default_size': 'Tamanho padrão',
      'delete_name': 'Excluir \$name',
      'elapsed': 'Tempo',
      'enter_value_between': 'Digite um valor entre \$min e \$max',
      'error_saving_image': 'Erro ao salvar a imagem',
      'error_sharing_image': 'Erro ao compartilhar a imagem',
      'failed_to_save_image': 'Falha ao salvar a imagem',
      'gpu_is_experimental':
          'A GPU é experimental: mais rápida em alguns modelos e ainda não '
          'medida em todos.',
      'initializing_model': 'Iniciando o modelo',
      'listening_tap_mic_to_stop': 'Ouvindo — toque no microfone para parar',
      'loading_filename': 'Carregando o modelo',
      'local_api_server': 'Servidor de API local',
      'local_on_device': 'No aparelho',
      'mobile_lm': 'mobileLM',
      'model_size': 'Tamanho do modelo',
      'openai_compatible_endpoint': 'Endpoint compatível com OpenAI',
      'quantisation_aware_only': 'Só os compatíveis com quantização',
      'recommended_max_8':
          'Recomendado: no máximo 8 — acima disso quase não muda e demora bem '
          'mais',
      'restart_now': 'Reiniciar agora?',
      'runs': 'Executa',
      'runtime': 'Runtime',
      'set_up_workspace': 'Configurar o espaço de trabalho',
      'some_settings_only_load_at_app_start':
          'Algumas configurações só valem na próxima vez que o app for aberto',
      'system_prompt_hint': 'Instruções que o modelo segue em todas as conversas',
      'text_generation': 'Geração de texto',
      'tool_round_trips': 'Voltas de ferramenta',
      'unload_before_loading_another':
          'Descarregue o modelo atual antes de carregar outro',
      'use_buttons_to_add_files': 'Use os botões para adicionar arquivos',
      'view_errors_warnings': 'Ver erros e avisos',
      'workspace_not_configured': 'Espaço de trabalho não configurado',
      'you_can_change_this_folder_later': 'Você pode trocar esta pasta depois',
      'you_need_to_download_a_model': 'Você precisa baixar um modelo',

      // ── O seletor de idioma ──────────────────────────────────────────────
      // `language_auto` e os dois `language_*_detail` são as chaves novas do
      // seletor; `language` (o título) já existia.
      //
      // **São dois detalhes e não um porque `auto` depende do aparelho.** O
      // aparelho não muda quando a pessoa troca de idioma, então "sigue o
      // telefone" não diz o que vai acontecer — e num aparelho fora do
      // português a única pista de que o modo Automático cai em inglês é a
      // própria tela, depois que já mudou.
      'language_auto': 'Automático',
      'language_auto_detail_pt':
          'Este aparelho está em português, então a tela fica em português.',
      'language_auto_detail_en':
          'Este aparelho não está em português, então a tela fica em inglês.',
      'language_english_detail': 'Sempre em inglês, o que o aparelho diga',
      'language_portuguese_brazil_detail': 'Sempre em português do Brasil',
      'language_changed': 'Idioma alterado',
      // As dezesseis sugestões do estado vazio do chat.
      //
      // **Eram literais em português dentro de `chat_view.dart`**, e é por isso
      // que a build em inglês abria com "Hello." em cima de uma lista de
      // perguntas em português: o título passava por `.tr` e os chips não. É o
      // modo de falha exato que o seletor de idioma veio acabar, então agora
      // são chaves — e `l10n_keys_test.dart` as audita sem ninguém pedir.
      'suggestion_1': 'Explique computação quântica de forma simples',
      'suggestion_2': 'Escreva um poema curto sobre o tempo',
      'suggestion_3': 'Me ajude a depurar meu código',
      'suggestion_4': 'Resuma um tópico complexo',
      'suggestion_5': 'Que horas são em Tóquio?',
      'suggestion_6': 'Brainstorm nomes para uma cafeteria',
      'suggestion_7': 'Rascunhe um e-mail de reclamação educado',
      'suggestion_8': 'Traduza "bom dia" para 5 idiomas',
      'suggestion_9': 'Planeje uma viagem de 3 dias para Lisboa',
      'suggestion_10': 'Converta 120 km para milhas',
      'suggestion_11': 'Escreva um haiku sobre a chuva',
      'suggestion_12': 'Explique recursão como se eu tivesse 5 anos',
      'suggestion_13': 'Sugira um plano de treino para iniciantes',
      'suggestion_14': 'Me conte um fato divertido sobre o espaço',
      'suggestion_15': 'Me ajude a escrever um resumo do currículo',
      'suggestion_16': 'Multiplique 128 por 456',
      // Os seis chips de prompt rápido embaixo de uma resposta do assistente.
      //
      // **Rótulo e prompt são chaves separadas**, porque o prompt vai para o
      // modelo: um chip que parece localizado e manda um prompt em português
      // para um modelo em inglês é pior do que um chip traduzido.
      'chip_expand': 'Explique melhor',
      'chip_expand_prompt':
          'Explique isso de forma mais detalhada e didática.',
      'chip_summarise': 'Resuma',
      'chip_summarise_prompt': 'Resuma a resposta anterior de forma concisa.',
      'chip_translate': 'Traduza',
      'chip_translate_prompt': 'Traduza a resposta anterior para inglês.',
      'chip_continue': 'Continue',
      'chip_continue_prompt': 'Continue a explicação anterior.',
      'chip_example': 'Exemplo',
      'chip_example_prompt': 'Dê um exemplo prático sobre esse assunto.',
      'chip_simplify': 'Simplifique',
      'chip_simplify_prompt':
          'Explique de forma mais simples, como para iniciantes.',
      // Os rótulos de seção e os modos de tema da tela de Configurações.
      //
      // Eram literais em inglês hardcoded, e é a **única** coisa que faltava
      // para a troca de idioma parecer quebrada: o título da tela mudava, os
      // subtítulos mudavam, e no meio da tela aparecia "APPEARANCE" e "Light /
      // Dark / System Default" numa tela portuguesa. A pessoa concluía que o
      // botão não funciona, não que faltou traduzir quatro palavras.
      'section_appearance': 'Aparência',
      'section_inference_mode': 'Modo de inferência',
      'section_model_settings': 'Configurações do modelo',
      'section_device_information': 'Informações do aparelho',
      'section_storage': 'Armazenamento',
      'section_workspace': 'Espaço de trabalho',
      'section_agent': 'Agente',
      'section_diagnostics': 'Diagnóstico',
      'section_about': 'Sobre',
      'theme_light': 'Claro',
      'theme_dark': 'Escuro',
      'theme_system': 'Padrão do sistema',
      'no_model_loaded': 'Nenhum modelo carregado',
      // ── Traduzidas por tool/inline_english_scan.dart ─────────────
      // A posição no fonte é o que amarra a tradução ao texto: um texto
      // repetido em dois lugares seria traduzido duas vezes, e a segunda
      // tradução é a que a tela mostra. Use `.tr` e apague o literal.
      'set_hops_hint': '0 = sem teto, 1–8 = máximo de saltos',
      'mv_one_classification_model': '1 modelo · classificação, não chat',
      'set_512_detail': '512 dá mais detalhe, mas pode ser MUITO mais lento, aquecer o '
          'aparelho e falhar em alguns aparelhos.',
      'soc_gguf_answers': 'Um GGUF responde com uma letra ou com logits, e qual dos dois só '
          'aparece depois de carregar. O servidor disse:',
      'soc_classification_head_console': 'Uma cabeça de classificação GGUF carrega os rótulos com que foi '
          'treinada, então /v1/classify os devolve e esta janela não tem o '
          'que perguntar. O console de encoder dirige aquela.',
      'mv_wifi_recommended': 'Uma conexão Wi-Fi é fortemente recomendada. Mantenha o app aberto '
          'durante o download.',
      'enc_decision_model_explains': 'Um decision model responde a uma pergunta estruturada com uma '
          'classe, e é um GGUF comum: o Tev1-0.8B carrega como qwen35 e não '
          'carrega nenhuma flag que diga isso. Esta janela mostra as opções '
          'dele e devolve a letra — que é o teste, e é também como se '
          'descobre se um modelo se comporta como um.',
      'soc_head_not_recognisable': 'Uma cabeça não é reconhecível pelo conteúdo — não tem '
          '`cls.output.weight` — então quem chama é a única coisa que pode '
          'dizer de qual cabeça se trata. Esse nome vem do card de cabeças '
          'TFLite, ou do que `/v1/litert/status` reportar como carregado. '
          'Nenhum dos dois respondeu, então não há o que enviar.',
      'soc_head_no_class_names': 'Uma cabeça não carrega os próprios nomes de classe. Quem a treinou '
          'sabe o que é a classe 0, e isso é você — ou quem você está '
          'representando.',
      'tv_planning_steps': 'A IA está planejando os passos…',
      'mv_add_api_key': 'Adicionar chave de API',
      'set_no_think_label': 'Responder direto, sem raciocínio (/no_think)',
      'sv_anyone_on_network': 'Qualquer pessoa nesta rede vai poder usar o servidor do app sem '
          'chave. O servidor escuta em todas as interfaces, não só neste '
          'aparelho.',
      'set_apply_template_detail': 'Aplica um template de configuração · traz os modelos de volta',
      'set_think_label': 'Pedir raciocínio antes da resposta (/think)',
      'sv_authorization_bearer': 'Authorization: Bearer <key>',
      'set_bigger_size_detail': 'Automático é o recomendado. Tamanho maior = mais detalhe, mas bem '
          'mais lento e mais memória.',
      'set_backup_configs': 'Backup de configs…',
      'enc_bar_scaled': 'A barra é escalada neste conjunto de resultados, não a partir do '
          'zero. Um logit de cross-encoder não tem escala absoluta — o GTE '
          'medido aqui vai de 0,46 a 0,87 no sigmoid sobre um conjunto em que '
          'um documento é a resposta e três não são, então uma barra a partir '
          'do zero desenharia os quatro quase cheios e esconderia a única '
          'coisa que vale olhar, que é a distância entre eles. Os números são '
          'os absolutos.',
      'mv_chat_template': 'TEMPLATE DE CHAT',
      'set_change_folder': 'Trocar pasta…',
      'wsu_choose_folder': 'Escolher a pasta do workspace',
      'mv_configure_select': 'Configurar e selecionar',
      'set_context_size_a': 'Tamanho do contexto',
      'tv_create_task_hint': 'Crie uma tarefa e a IA vai planejar\nexecutar sozinha',
      'set_custom_search_url': 'URL da API de busca personalizada',
      'set_custom_search_token': 'Token da API de busca personalizada',
      'set_daily_prompts_detail': 'Prompts diários que rodam sozinhos',
      'mv_delete_model': 'Excluir o modelo',
      'tv_describe_task': 'Descreva o que você quer que a IA faça…',
      'set_notification_detail': 'Mostrar uma notificação persistente enquanto houver tarefas '
          'agendadas\nou um modelo carregado em segundo plano.',
      'mv_dont_suggest_again': 'Não sugerir isto de novo',
      'iv_download': 'Baixar',
      'mv_download_any_url': 'Baixe um modelo GGUF ou LiteRT de qualquer URL',
      'mv_download_benchmark': 'Baixar o benchmark?',
      'set_all_cores_big_detail': 'Todos os núcleos deste aparelho são grandes',
      'tv_execute_all_steps': 'Executar todos os passos',
      'mv_file_size': 'TAMANHO DO ARQUIVO',
      'set_faster_more_ram': 'Execução mais rápida, mas usa mais RAM e bateria',
      'mv_hide_api_key': 'Ocultar a chave de API',
      'hf_hide_too_large': 'Esconder GGUFs grandes demais para a memória deste aparelho',
      'mv_image_audio_input': 'Entrada de imagem e áudio — só LiteRT-LM',
      'mv_import_storage': 'Importar do armazenamento',
      'mv_inspect_file': 'Inspecionar o arquivo',
      'mv_keep_models_anyway': 'Manter os modelos assim mesmo',
      'sv_keep_key': 'Guardar a chave',
      'set_keep_screen_open': 'Mantenha esta tela aberta',
      'set_keep_models_detail': 'Mantém a lista local aconteça o que o benchmark disser, e para ele '
          'de oferecer escondê-la',
      'soc_load_one_and_probe': 'Carregue um e toque em re-inspecionar, ou por um cliente: POST '
          '/v1/models/load com "filename" e "accept_risk": true. Um .tflite '
          'não é GGUF, então não responde aqui: a janela acha um sozinha '
          'quando uma cabeça é carregada, e o card de cabeças TFLite na tela '
          'de Modelos abre pelo nome.',
      'mv_low_memory': 'Pouca memória — um modelo grande não vai ficar lento, vai falhar '
          'ao carregar.',
      'mv_model_info': 'INFO DO MODELO',
      'mv_model_url': 'URL DO MODELO',
      'set_max_speed_label': 'Velocidade máxima, pode travar em alguns aparelhos',
      'wsu_explain_projects': 'O MobileLM organiza seu trabalho em projetos. Escolha uma pasta '
          'neste aparelho — cada projeto que você começar depois vira uma '
          'subpasta dentro dela, onde o app consegue ler, criar, editar e '
          'apagar arquivos.',
      'mv_model_id': 'ID do modelo',
      'mv_model_weights': 'Pesos do modelo',
      'set_gpu_experimental_detail': 'Modelos neste tamanho ou acima usam CPU. Modelos menores podem '
          'usar GPU Experimental.',
      'set_more_steps_slower': 'Mais passos = mais qualidade, mas MUITO mais lento!',
      'set_more_threads_detail': 'Mais threads, mas o núcleo mais lento marca o ritmo de cada '
          'operação',
      'set_change_folder_detail2': 'Move todos os arquivos existentes para a nova pasta',
      'encp_no_encoder': 'Nenhum encoder carregado. Estas configurações valem para o '
          'próximo.',
      'mv_no_models_loaded': 'Nenhum modelo carregado. Adicione uma chave de API para atualizar '
          'a lista ao vivo, ou use um ID de modelo personalizado.',
      'tv_no_steps': 'Nenhum passo gerado.',
      'set_no_tasks_detail': 'Nenhuma tarefa ainda. Uma tarefa roda o prompt todo dia no horário '
          'escolhido com o modelo com que foi criada — mesmo com o app '
          'fechado — e publica o resultado aqui na conversa.',
      'encp_nothing_overridden': 'Nada substituído',
      'set_agent_off_detail': 'Desligado — a lista de tools fica fora do prompt',
      'soc_litert_unload': 'POST /v1/litert/unload. O servidor continua de pé e um GGUF '
          'carregado não é tocado — isto libera o modelo LiteRT e nada mais. '
          'É o único unload que a API consegue fazer, porque o do GGUF '
          'derrubaria o servidor junto.',
      'set_workspace_pick_detail': 'Escolha uma pasta para organizar seus projetos',
      'set_projector_cpu_detail': 'O projetor roda na CPU mesmo quando as camadas estão na GPU',
      'mv_provider_settings': 'Configurações do provedor',
      'hf_qat_explained': 'QAT, QAD, QAFT — treinados para 4 bits, então um build Q4_0 fica '
          'bem mais perto da precisão total',
      'sv_require_api_key': 'Exigir chave de API',
      'sv_required_by_toggle': 'Exigido pelo botão acima',
      'set_restore_backup': 'Restaurar backup…',
      'set_benchmark_detail': 'Roda o modelo de 230M e mede a velocidade real',
      'mv_save_key_to_verify': 'Salve a chave para verificá-la e carregar modelos ao vivo.',
      'mv_saved_provider': 'Provedor salvo',
      'mv_search_hf': 'Pesquisar no Hugging Face',
      'mv_search_models': 'Pesquisar modelos...',
      'mv_search_provider_or_id': 'Pesquise os modelos do provedor ou digite um ID de modelo',
      'hf_search_index': 'Pesquisar no índice GGUF',
      'mv_select_model': 'Selecionar modelo',
      'set_send_nothing_default': 'Não enviar nada — o padrão do próprio modelo',
      'mv_set_base_key_id': 'Defina a URL base, a chave e o ID do modelo',
      'set_backup_detail': 'Template de configurações (as chaves de API nunca saem do '
          'aparelho) numa pasta com data, no local que você escolher.',
      'set_settings_template_files': 'Template de configurações · arquivos de modelo opcionais',
      'log_share_full': 'Compartilhar o arquivo de log inteiro',
      'mv_show_api_key': 'Mostrar a chave de API',
      'set_show_models_ignore': 'Mostrar modelos, ignorar benchmarks',
      'mv_showing_local_because': 'Mostrando modelos locais porque você pediu para ignorar os '
          'benchmarks.',
      'set_local_only_detail': 'Mostrando só o que está neste aparelho. Encoders continuam '
          'funcionando.',
      'set_stable_mode_label': 'Modo estável, com velocidade menor',
      'soc_system_one_test_b': 'Teste System One',
      'mv_template': 'Template',
      'set_backup_restore_detail': 'Primeiro o template, depois os arquivos da pasta de backup',
      'mv_test_decision': 'Testar uma decisão',
      'enc_test_as_decision': 'Testar como decisão',
      'set_show_models_ignore_detail': 'O benchmark ainda mostra o número dele, mas nunca mais oferece '
          'esconder a lista local',
      'enc_file_decides_role': 'O arquivo é o que decide o papel. Uma tag é uma intenção, e a '
          'cabeça é um tensor.',
      'encp_loaded_reports': 'O modelo carregado reporta',
      'encp_overrides_apply': 'Os overrides abaixo continuam valendo. A coluna detectada '
          'automaticamente é a parte que precisa do modelo.',
      'set_privileged_note': 'As ferramentas privilegiadas estão listadas em Ferramentas. Cada '
          'uma delas pergunta antes de rodar, inclusive as de leitura.',
      'enc_scores_identical': 'Os scores são idênticos. Nada neste conjunto distingue — ou a '
          'consulta não tem relação com nenhum documento, ou o modelo não '
          'está pontuando. A ordenação abaixo é a ordem de entrada.',
      'lhc_not_zeros': 'Estes não são preenchidos com zero pelo app. Uma cabeça que '
          'precisa deles e não os recebe é recusada pelo nome — um logit '
          'calculado sobre inventos volta vestindo um rótulo confiante.',
      'ppd_choose_folder': 'Esta conversa funciona dentro de uma pasta de projeto. Escolha '
          'onde ficam os arquivos dela, ou mantenha como conversa geral.',
      'set_gpu_first_label': 'Tentar GPU primeiro, com CPU como reserva',
      'sv_turn_off_key': 'Desligar a chave de API?',
      'sv_turning_back_on': 'Ligar de novo gera uma chave nova, e qualquer coisa usando a '
          'antiga para de funcionar.',
      'set_hops_one': 'Modo agente: até @n salto por mensagem',
      'set_hops_many': 'Modo agente: até @n saltos por mensagem',
      'set_unlimited_agent_mode': 'Modo agente sem teto seu',
      'mv_unload_model': 'Descarregar o modelo',
      'mv_update_api_key': 'Atualizar a chave de API',
      'mv_openai_endpoint': 'Use qualquer endpoint compatível com OpenAI. Informe a URL base '
          'sem /chat/completions.',
      'set_workspace_folder': 'Pasta do workspace',
      'set_workspace_not_set_up': 'Workspace não configurado',
      'set_change_folder_detail': 'Seus projetos e arquivos atuais serão copiados para a nova pasta, '
          'e a partir de agora esta passa a ser a usada.',
      'enc_case_paraphrase': 'uma paráfrase e um par sem relação',
      'encp_above_reported': 'acima do que o modelo reportou — usando o do modelo',
      'lhc_accelerator': 'acelerador — o que pedir',
      'set_auto_size': 'tamanho automático',
      'mv_download_lower': 'baixar',
      'soc_free_head': 'liberar a cabeça compilada',
      'enc_hide_console': 'esconder o console, mostrar a conversa',
      'enc_case_storage': 'quanto espaço o cache do mapa offline usa',
      'set_custom_search_url_hint': 'https://searx.example.org/search',
      'set_custom_search_token_hint': 'deixe vazio para SearXNG',
      'soc_empty_uses_default': 'vazio usa o padrão do card do modelo',
      'soc_no_upper_limit': 'Sem teto aqui: uma cabeça tem quantas classes foi treinada. O 24 é '
          'o número do card de decision model.',
      'lhc_not_screened': 'ainda não inspecionado',
      'enc_case_off_domain': 'fora do domínio — os scores devem achatar',
      'lhc_response_tap': 'response — toque para copiar',
      'enc_run_server_off': 'rodar — o servidor está desligado',
      'enc_case_self_match': 'auto-correspondência — o topo da faixa',
      'lhc_show_conversation': 'mostrar a conversa',
      'enc_case_obvious': 'a resposta é óbvia',
      'soc_server_no_answer': 'o servidor não respondeu',
      'enc_what_file_says': 'o que o arquivo diz sobre si mesmo',
      'soc_which_area': 'a que área isto pertence?',
      // ── Texto de tela da varredura ampla (tool/broad_inline.tsv) ────
      // O casamento é por TEXTO e nunca por `arquivo:linha`: reescrever um
      // literal adjacente apaga as linhas do meio, e uma posição medida
      // antes da primeira reescrita aponta para o lugar errado — e a
      // ferramenta aceitaria, porque ela confia na posição.
      'mc_settings_folder_failed': 'Não foi possível criar a pasta de configurações',
      'mc_config_write_failed': 'Não foi possível gravar mobilelm-config.json',
      'mc_not_a_backup': 'Isto não é um backup de configuração do mobileLM.',
      'mc_already_loading': 'Outro modelo já está sendo carregado.',
      'mc_model_loading': 'Carregando modelo',
      'mc_incomplete_file': 'Arquivo de modelo incompleto',
      'mc_incomplete_tip_delete': 'Apague o modelo e baixe-o de novo por inteiro.',
      'mc_incomplete_tip_ram': 'Confira se o aparelho tem pelo menos 2-3 GB de RAM livre.',
      'mc_hide_technical': 'Ocultar detalhes técnicos',
      'mc_show_technical': 'Mostrar detalhes técnicos',
      'mc_ram_low': 'A RAM disponível está abaixo do recomendado. Isto pode travar o '
          'app se o Android não conseguir reservar memória suficiente.',
      'mc_ram_low_model': 'Isto pode travar o app se o Android não conseguir reservar memória '
          'suficiente para o modelo.',
      'mc_ram_more_than_file': 'Carregar modelos locais pode usar mais memória do que o tamanho do '
          'arquivo.',
      'mc_runtime_image': 'Modelo de imagem',
      'mc_import_in_progress': 'Importação em andamento',
      'mc_import_wait': 'Espere a importação atual terminar.',
      'mc_unsupported': 'Modelo não suportado',
      'mc_import_only_formats': 'Só arquivos .gguf, .litertlm, .tflite e .safetensors podem ser '
          'importados.',
      'mc_import_unreadable': 'Não foi possível ler o arquivo selecionado. Tente selecioná-lo do '
          'armazenamento local.',
      'mc_select_file': 'Selecione um arquivo de modelo...',
      'mc_cancel': 'Cancelar',
      'mc_download_failed': 'Falha no download',
      'mc_download_unavailable': 'Download indisponível',
      'mc_no_download_url': 'Este modelo não tem URL de download.',
      'mc_android_only': 'Só no Android',
      'mc_android_only_detail': 'Use o botão de download do app ou importe um modelo local nesta '
          'plataforma.',
      'mc_download_starting': 'Iniciando download...',
      'mc_download_started': 'Download iniciado',
      'mc_arch_unsupported': 'Este GGUF usa uma arquitetura de modelo que o runtime de llama.cpp '
          'incluído não suporta. Atualize o runtime do app ou tente um GGUF '
          'exportado para uma arquitetura suportada.',
      'mc_split_missing': 'Isto parece um GGUF dividido, mas falta um ou mais arquivos '
          'obrigatórios. Importe todas as partes na mesma pasta antes de '
          'carregar.',
      'mc_file_corrupt': 'O arquivo do modelo parece incompleto ou corrompido. Isso costuma '
          'acontecer quando o download é interrompido ou o arquivo é '
          'inválido.',
      'mc_out_of_memory': 'O aparelho ficou sem memória (RAM) ao tentar carregar este modelo. '
          'Aparelhos móveis têm limites rígidos de memória; tente um modelo '
          'menor ou mais quantizado (por exemplo, 1B ou 3B parâmetros, '
          'quantizado q4_k_m).',
      'mc_hw_error': 'Ocorreu um erro de hardware ou de driver da GPU ao iniciar o '
          'modelo. Tente desativar a aceleração de GPU ou passar para '
          'inferência só na CPU, em Configurações.',
      'mc_native_error': 'O motor de IA nativo encontrou um erro inesperado ao carregar o '
          'modelo. Veja os detalhes técnicos abaixo para mais informação.',
      'mv_no_online_model': 'Nenhum modelo online selecionado',
      'mv_save_key': 'Salvar chave',
      'mv_verifying': 'Verificando...',
      'mv_one_download': '1 download em andamento · a barra dele está no próprio card',
      'mv_benchmark_running': 'Benchmark rodando…',
      'mv_benchmark_usability': 'Usabilidade do benchmark',
      'mv_bench_cpu_safe': 'Modo CPU Seguro, uma pergunta curta. Leva alguns segundos para '
          'carregar o modelo, e mais alguns para responder.',
      'mv_bench_what_it_does': 'Roda o modelo de 230M em modo CPU Seguro e informa o seu tok/s de '
          'verdade, para você saber se um modelo local vale o download.',
      'mv_bench_what_it_does2': 'Baixa o modelo de 230M e roda em modo CPU Seguro, depois informa o '
          'seu tok/s de verdade. Nada é baixado nem roda antes de você tocar.',
      'mv_bench_fast': 'Velocidade suficiente para modelos locais. 1B ou menos deve ser '
          'tranquilo; os maiores valem a pena testar antes de baixar.',
      'mv_bench_cpu_nothing': 'A CPU não devolveu nada. Modelos na nuvem são a escolha confiável '
          'neste aparelho.',
      'mv_bench_cpu_path_nothing': 'O caminho pela CPU não devolveu nada, então modelos locais não vão '
          'funcionar aqui. Use os modelos na nuvem — e se isso se repetir, o '
          'problema é o motor, não o tamanho do modelo.',
      'mv_hide_list': 'Ocultar a lista de modelos locais',
      'mv_list_hidden': 'Lista local oculta',
      'mv_not_now': 'Agora não',
      'mv_clear_form': 'Limpar o formulário',
      'mv_enter_model_name': 'Digite o nome do modelo',
      'mv_enter_model_url': 'Digite a URL do modelo',
      'mv_enter_description': 'Digite uma descrição',
      'mv_url_example': 'https://huggingface.co/…/model.gguf',
      'mv_display_name_hint': 'Nome de exibição  (ex.: Qwen3-0.6B)',
      'mv_projector_incomplete': 'O download do projetor não foi concluído',
      'mv_no_mmproj': 'Still não há arquivo mmproj na pasta de modelos. Abra a busca do '
          'HF, baixe o projetor deste repositório e volte para cá.',
      'mv_loading': 'Carregando...',
      'mv_bad_url': 'Formato de URL inválido. Precisa começar com http:// ou https://',
      'mv_size_unresolved': 'Não foi possível resolver o tamanho do arquivo. Confirme que a URL '
          'está acessível.',
      'set_scrape_chain': 'Usando a cadeia de busca.',
      'set_gpu_safety_off': 'A proteção da GPU está desligada. Modelos grandes podem travar ou '
          'congelar na GPU.',
      'set_gpu_safety_high': 'A proteção alta da GPU permite modelos maiores na GPU, e pode '
          'travar, congelar ou superaquecer alguns aparelhos.',
      'set_ctx_may_crash': 'O aparelho pode travar com este valor!',
      'set_ctx_warning': 'Atenção: valores acima de 8192 podem esgotar a memória do '
          'aparelho. Continue só se o aparelho tiver RAM suficiente.',
      'set_ctx_capped': 'Contexto limitado a 4096 para evitar travamento por memória do '
          'driver nos modelos LiteRT.',
      'set_ctx_all_ram': 'Um contexto desse tamanho come toda a sua RAM!',
      'set_ws_move_failed': 'Não foi possível mover o espaço de trabalho.',
      'set_ws_moved': 'Espaço de trabalho movido e ativo.',
      'set_hops_label': 'Defina o máximo de saltos (1–8), ou 0 para não ter teto próprio',
      'set_no_local_files': 'Nenhum arquivo de modelo local encontrado.',
      'set_field_name': 'Nome',
      'sc_what_is_here': 'O que há neste aparelho',
      'sc_load_downloaded': 'Carregar um modelo já baixado',
      'sc_download_catalogue': 'Baixar um do catálogo',
      'sc_download_here': 'Baixar modelos para este aparelho',
      'sc_unload': 'Tirar ou trocar o modelo em uso',
      'sc_list_here': 'Listar o que há no aparelho',
      'sc_use_for_inference': 'Usar o aparelho para inferência',
      'sc_network_warning': 'Qualquer pessoa nesta rede pode usar este servidor.',
      'soc_no_address': 'O servidor da API ainda não tem endereço.',
      'soc_no_address_hint': 'o servidor da API ainda não informou um endereço — abra '
          'Configurações, Servidor de API, e ligue-o',
      'soc_nothing_freed': 'Nada foi carregado, então nada foi liberado.',
      'soc_nothing_loaded': 'nada carregado',
      'soc_is_head': 'este tem cabeça com um conjunto de rótulos próprio',
      'soc_head_labels': 'cabeça com rótulos próprios — é o console de encoder que dirige '
          'essa',
      'soc_not_decided': 'ainda não decidido — nenhum GGUF está carregado',
      'soc_state': 'o estado — os dados que estão sendo avaliados',
      'soc_question': 'a pergunta — opcional',
      'soc_system': 'a instrução de sistema — opcional',
      'soc_default_ok': 'O padrão já diz as três coisas que importam: trate o estado como '
          'dado, escolha exatamente uma, devolva só a letra.',
      'soc_run_head': 'rodar a cabeça',
      'soc_no_tflite': 'nenhum .tflite para nomear',
      'soc_left_empty': 'Vazio, isto não é enviado de todo, e o endpoint diz qual era o '
          'esperado.',
      'soc_left_empty2': 'Vazio, isto não é enviado de todo. Zeros nunca são substituídos: '
          'um logit calculado sobre features inventadas é um número sem '
          'significado, e volta com um rótulo.',
      'soc_options': 'as opções — de 2 a 24, o número do model card',
      'soc_json_envelope': 'Enviado dentro de um envelope JSON, nunca como instrução. Um '
          'ticket com aspas e chaves não pode mudar a forma da pergunta.',
      'soc_copy': 'copiar',
      'soc_answer': 'a resposta',
      'soc_refused': 'a execução foi recusada',
      'soc_reprobe_failed': 'A nova sondagem falhou, então o que aparece abaixo vem do arquivo '
          'como foi lido da última vez. A execução vai usar a resposta do '
          'próprio servidor.',
      'enc_needs_bert': 'Este console pontua uma consulta contra um modelo, então precisa '
          'de um BERT ou ModernBERT. Um GGUF sem essa forma não pode ser '
          'testado aqui.',
      'enc_no_output': 'Esta conversão não tem saída',
      'enc_works_reranker': 'Um reranker que funciona aqui: '
          'gte-reranker-modernbert-base-Q8_0.gguf',
      'enc_works_embed': 'Um modelo de embedding que funciona: bge-small-en-v1.5-f16.gguf',
      'enc_server_off': 'servidor fora — toque para tentar de novo',
      'enc_aux_bad_json': 'auxiliar tem que ser um objeto JSON de nome → números',
      'enc_tap_to_copy': 'toque para copiar',
      'enc_copied': 'a resposta JSON está na área de transferência',
      'enc_role_embed': 'Embeddings transformam texto em um vetor cada.',
      'enc_role_rerank': 'Rerankers pontuam uma consulta contra cada documento.',
      'enc_reread': 'reler',
      'enc_asym_query': 'Prependido a um `input` simples. A outra metade da mesma '
          'assimetria — um modelo treinado com os dois lados marcados devolve '
          'vetores feitos para um tipo de texto se você não marcar nenhum.',
      'enc_normalize': 'Automático segue o modelo. Desligado devolve o vetor cru, para '
          'quem faz a própria normalização.',
      'enc_top_n': 'Quantos documentos voltam. Um pedido que mande o próprio `top_n` '
          'tem a preferência.',
      'enc_split_newline': 'Usado quando `documents` chega como uma string só. Uma quebra de '
          'linha não se distingue de um parágrafo novo, então um documento '
          'enviado com linhas em branco volta partido e ordenado, sem nada '
          'indicando isso.',
      'enc_prob': 'Acrescenta `relevance_score_probability` ao lado do logit cru. O '
          'logit fica como está nos dois casos — é o contrato medido, e o '
          'sigmoid de um cross-encoder não é calibrado de qualquer jeito.',
      'enc_echo': 'Devolve cada documento com sua pontuação, como o Cohere faz. '
          'Desligado corta a resposta pela metade numa lista longa.',
      'hf_nothing_loadable': 'Nada carregável neste repositório. Arquivos divididos e builds '
          'LiteRT para aceleradores de outros fornecedores são pulados.',
      'hf_mergekit': 'Feito com mergekit',
      'hf_format': 'Formato',
      'hf_this_device': 'Este aparelho',
      'lit_still_compiling': 'O LiteRT aceitou o arquivo há 90 s e ainda não informou que '
          'compilou. O log de compilação está em Configurações, Log.',
      'lit_screen_first': 'sondeie um .tflite primeiro — não há nada para rodar',
      'chat_image_failed': '❌ Falha na geração local de imagem.',
      'chat_image_here': 'Aqui está a imagem gerada:',
      'chat_privileged': 'Isto roda um comando privilegiado.',
      'chat_only_media': 'Só são suportados imagem, vídeo, áudio, PDF, DOCX e arquivos de '
          'texto/código.',
      'chat_no_frames': 'Não foi possível ler nenhum quadro deste vídeo.',
      'chat_vae_decoding': 'Decodificação do VAE em andamento…',
      'chat_just_now': 'Agora mesmo',
      'chat_show_conversation': 'mostrar conversa',
      'chat_attached_file': 'Arquivo anexado:',
      'widget_generated_with': 'Gerado com mobileLM',
      'ws_new_name': 'Novo nome',
      'ws_rename_failed': 'Falha ao renomear.',
      'ws_folder_name': 'Nome da pasta',
      'ws_create_folder_failed': 'Não foi possível criar a pasta (o nome pode já estar em uso).',
      'ws_file_name': 'Nome do arquivo (ex.: notas.md)',
      'ws_create_file_failed': 'Não foi possível criar o arquivo (o nome pode já estar em uso).',
      'ws_setup_none': 'Still nenhuma pasta escolhida. Escolha uma para continuar.',
      'task_no_exec': 'Execução de comando não está disponível.',
      'task_cancel': 'Cancelar',
      'cloud_nim': 'Modelos NIM hospedados compatíveis com OpenAI',
      'cloud_url_required': 'A URL base é obrigatória.',
      'cloud_url_invalid': 'Digite uma URL base válida compatível com OpenAI.',
      'cloud_free_list': 'Lista gratuita de modelos · compatível com OpenAI',
      'cloud_native_openai': 'Modelos de chat nativos da OpenAI',
      'cloud_v4': 'Modelos V4 compatíveis com OpenAI',
      'cloud_gemini': 'Modelos da API nativa do Gemini',
      'set_unknown_gpu': 'GPU desconhecida',
      'enc_doc_example': 'O cache de mapas guarda cerca de 340 MB por cidade.\nO cache é '
          'limpo em Configurações.\nAzeite de oliva é prensado a frio.',
    }
  };
}
