# Workspace e projetos

O workspace é a pasta do aparelho onde o mobileLM guarda o trabalho do usuário.
Cada **projeto** é uma subpasta direta da raiz do workspace, e cada conversa
pode estar ligada a um projeto — é essa ligação que decide onde as tools de
arquivo (`list_files`, `read_file`, `create_file`, `write_file`, `delete_file`,
`rename_file`) podem mexer.

## Peças

| Arquivo | Papel |
|---|---|
| `lib/services/workspace_native.dart` | Canal `com.aichat.ai_chat/workspace` — SAF puro, uma função por operação |
| `lib/services/workspace_stub.dart` | Mesma API na web, onde SAF não existe (`workspaceSupported == false`) |
| `lib/services/workspace_service.dart` | Estado: URI da raiz, pasta atual, listagem; navegação e CRUD |
| `lib/views/workspace_setup_view.dart` | Portão de primeiro uso: escolher a pasta raiz |
| `lib/views/workspace_view.dart` | A aba Workspace: navegador de arquivos |
| `lib/widgets/project_picker_dialog.dart` | Diálogo de escolha/criação de projeto |
| `android/.../MainActivity.kt` | Handlers `wsPickWorkspace`, `wsListDir`, `wsMkdir`, `wsReadFile`, `wsWriteFile`, `wsDelete`, `wsRename`, `wsMoveWorkspace` |

A raiz é uma **tree URI do SAF** com permissão persistida, guardada em
`AppConstants.keyWorkspaceTreeUri`. Nada de caminho absoluto: fora do sandbox
do app, no armazenamento com escopo, só o SAF alcança.

## Como uma conversa entra num projeto

`ChatSession.projectPath` guarda o **nome** da pasta do projeto, relativo à
raiz. Null = conversa geral, sem projeto, e as tools de arquivo não têm base.

O ciclo:

1. **Primeira conversa, nenhum projeto aberto** — o picker aparece. O usuário
   escolhe um projeto existente, cria um novo, ou responde "No project".
2. **Conversas seguintes** — herdam silenciosamente o projeto aberto
   (`ChatController.currentProjectPath`). O picker **não** reaparece.
3. **Trocar de projeto** — pelo chip de projeto na app bar do chat. Ele mostra
   a pasta atual (ou "No project") e abre o mesmo picker, religando a conversa
   aberta.
4. **Abrir uma conversa antiga** — `openChat` restaura `currentProjectPath` a
   partir da sessão e aponta a aba Workspace para aquela pasta.

### Por que a herança em vez de perguntar sempre

Perguntar a cada conversa nova era o comportamento original e tornava o
workspace inutilizável: o picker é uma pergunta sobre *onde o trabalho mora*,
não sobre *como começar a conversar*. A herança só é segura porque existe o
chip na app bar — sem ele, o primeiro projeto escolhido viraria uma prisão.

## Armadilhas já pagas

- **Dois pickers empilhados.** Os chips de sugestão da tela vazia chamavam
  `createNewChat()` sem `await` e mandavam a mensagem em seguida; `sendMessage`
  via `currentSessionId` ainda vazio e chamava `createNewChat()` de novo,
  abrindo um segundo diálogo por cima do primeiro. Duas sessões nasciam e a
  mensagem caía na segunda. Resolvido em duas frentes: o chip agora espera, e
  `createNewChat()` tem guarda de reentrância (`_creatingChat`) — chamadas
  concorrentes entram na mesma criação.
- **O portão de setup não levantava.** `HomeView.build` lia
  `workspace.needsSetup.value` fora de um `Obx`, então não assinava nada:
  escolher a pasta limpava a flag e a tela de setup continuava por cima.
  Agora o corpo do `build` está dentro de `Obx`.
- **`copyWith` não desligava projeto.** `projectPath ?? this.projectPath` não
  distingue "não mexe" de "tira o projeto". `ChatSession.copyWith` ganhou
  `clearProject`.
- **Diálogo dispensado ≠ "sem projeto".** `_askForProject` devolve
  `kNoProjectSentinel` para o "No project" explícito e `null` para dispensa.
  Ao religar uma conversa existente, dispensar não muda nada.

## Limites conhecidos

- `listTreeRecursive`/`wsListDir` não paginam. Uma pasta de projeto com
  milhares de arquivos vai custar uma listagem inteira por navegação.
- A permissão persistida pode ser revogada pelo sistema (reinstalação, limpeza
  de dados). Hoje isso aparece como listagem vazia, não como erro explícito.
