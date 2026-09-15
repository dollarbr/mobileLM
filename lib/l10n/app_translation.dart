import 'package:get/get.dart';

class AppTranslation extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {
    'pt_BR': {
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
      'describe_video': 'Descreva o que acontece neste vídeo.',
      'transcribe_audio': 'Transcreva ou analise este áudio.',
      'review_file': 'Revise este arquivo.',
      'review_attachment': 'Revise este anexo.',
      'file_truncated': '[Arquivo truncado para tamanho de contexto]',
      'could_not_extract': '[Não foi possível extrair texto de',
      
      // Tools
      'tools': 'Ferramentas',
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
        'new_chat': 'Nova conversa',
    }
  };
}