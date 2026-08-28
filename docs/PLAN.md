# mobileLM — Plano do produto

**Tese:** um assistente de IA que roda no bolso (local-first) E age no celular
(agente). PrivateLM já resolve o "cérebro"; PocketStrike provou o "corpo".
mobileLM junta os dois num app Flutter só.

## O que vem de onde

| Camada | Origem | Como entra |
|---|---|---|
| Engine local (GGUF/Vulkan/CPU ladder, LiteRT, mtmd, SD) | PrivateLM | Fork direto da codebase (M1) |
| Chat, anexos multimodais, thinking toggle, HF browser | PrivateLM | Já vem no fork |
| Catálogo de tools nativas (~42 ideias: SMS, contatos, arquivos, sensores, tela) | PocketStrike | Portar conceito; implementar via MethodChannel Kotlin |
| Convenção `[TOOL_CALL]` + lazy registry (`list_tools`/`search_tools`) | PocketStrike | Adaptar ao registry tolerante existente em `lib/services/tools/` |
| Scheduler de tarefas em background | PocketStrike | M3 — WorkManager + permissão de bateria |
| Web UI / Telegram bot / ADB raw | PocketStrike | **Fora de escopo** (cliente-only, sem root) |

## Fases

### M0 — Bootstrap ✅
Repo, plano, identidade visual, LICENSE MIT com atribuição dupla.

### M1 — Rebase da marca (≈1 semana)
- Importar codebase privateLM como histórico inicial deste repo.
- Renomear: app `mobileLM`, applicationId `com.dollarbr.mobilelm`, título, splash.
- Ícone adaptativo novo a partir de `docs/brand/logo.svg`; tema → paleta Ink/Volt.
- CI copiada do privateLM (`ci.yml`, `debug-apk.yml`, `release.yml`) com nome novo.
- **Critério:** app abre, chama local e cloud, APK debug sai por tag de CI.

### M2 — Espinha dorsal do agente (≈2–3 semanas)
- Expandir registry de 5 → ~20 tools nativas, em ondas por classe de permissão:
  1. sem risco (já existem: relógio, calculadora, device info)
  2. leitura (arquivos, contatos-ler, clipboard, sensores, bateria, rede)
  3. escrita com confirmação na UI (enviar SMS, criar contato, apagar arquivo, tocar mídia)
- Executor com **confirmação humana por classe**; tool de escrita nunca auto-executa.
- Card de execução no chat: tool, argumentos, resultado, botão refazer/negar.
- **Critério:** "manda uma mensagem pra X dizendo Y" pede confirmação e envia.

### M3 — Modo agente (≈2 semanas)
- Multi-passo com teto de iterações (default 8) atrás de toggle nos ajustes.
- Tarefas agendadas simples (WorkManager): "todo dia 8h resuma minhas notificações".
- Memória de tarefa isolada da conversa principal.
- **Critério:** tarefa agendada roda com app fechado e aparece no chat.

### M4 — Release 0.1
- Tag `0.1.0`, release notes por Conventional Commits, README público com screenshots.

## Riscos

- **Permissões sensíveis** (SMS/contatos): Play Store exige justificativa — distribuição
  prioritária = APK direto/GitHub Releases (mesma estratégia do privateLM).
- **Modelos pequenos + tools**: loop de chamadas é real (privateLM limita a 1 hop);
  M2/M3 precisam de testes com LFM2-1.6B e Qwen 1.7B no Edge 60 antes de abrir o multi-passo.
- **APK size**: engine já carrega +31 MB; cada tool nativa é barata, mas vigiar.

## Decisões abertas

- Nome exibido: "mobileLM" ou algo derivado? (repo já fixa mobileLM)
- Manter servidor OpenAI-compat embutido do privateLM? (provável sim, custo zero)
