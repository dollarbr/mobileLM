# Tools privilegiadas via Shizuku

Oito tools que só existem quando há um shell privilegiado: cinco de leitura, e
escrita em settings e permissões.

## O app nunca precisa de root

Isso é decisão de produto, não limitação. Em nenhum caminho o app chama `su` nem
exige aparelho rooteado. O **Shizuku** é o único caminho privilegiado.

O Shizuku em si *pode* ter sido iniciado como root pelo usuário — nesse caso os
comandos rodam com uid 0. O app apenas **reporta** isso; o que ele não faz é
pedir. Por isso o diálogo de confirmação mostra a identidade: o mesmo
`settings put` faz coisas diferentes sob 2000 e sob 0.

Também não há cliente ADB embutido. O adb é *como* o Shizuku ganha privilégio,
não um provedor concorrente.

## Os quatro estados

Não é um "indisponível" só, porque cada estado pede uma coisa diferente de você:

| Estado | O que fazer |
|---|---|
| `Shizuku not found` | Instalar o Shizuku — é um app separado |
| `Shizuku stopped` | Iniciar por depuração sem fio; fica de pé até reiniciar o aparelho |
| `Awaiting permission` | Botão "Grant permission" no card das Settings |
| `Active · shell 2000` / `Active · root 0` | Pronto |

**Sem binder pronto, o bloco some do prompt inteiro.** Não aparece e falha — o
`tool_registry.dart` já argumenta o porquê no filtro `enabled`: um modelo avisado
de uma tool que depois se recusa a rodar desperdiça um turno discutindo consigo
mesmo.

## As tools

| tool | comando |
|---|---|
| `list_apps` | `pm list packages` (`only` = all/user/system, `filter`) |
| `app_info` | `dumpsys package <pkg>` |
| `get_logcat` | `logcat -d -t <lines>` (`lines` ≤ 500, `tag`, `priority`) |
| `read_system_prop` | `getprop <key>` |
| `read_setting` | `settings get <ns> <key>` |
| `set_setting` | `settings put <ns> <key> <value>` |
| `grant_permission` | `pm grant <pkg> <perm>` |
| `revoke_permission` | `pm revoke <pkg> <perm>` |

Todas são `ToolRisk.privileged` e **todas confirmam, leitura inclusive**. Não é
excesso de zelo: um `get_logcat` carrega notificações, tokens e conteúdo de
outros apps. Privilégio de shell não tem modo "só olhando".

## Argv, nunca string de shell

Esta é a única razão pela qual tools estreitas são mais seguras que um
`run_shell`. O comando é montado como lista de argumentos e executado por
`ProcessBuilder` dentro do `UserService` — **nenhum shell é criado**, então um
metacaractere num argumento é sempre literal.

`uninstall_app(package="foo; rm -rf /data")` com concatenação de string seria
execução arbitrária sob o uid do Shizuku. Por isso as regras são código com
teste, não cuidado no lugar da chamada:

- pacote casa `^[A-Za-z0-9._]+$`
- chave de setting e de prop casam `^[A-Za-z0-9._-]+$`
- namespace ∈ {`system`, `secure`, `global`}
- o **valor** de `set_setting` não é validado de propósito: um caminho ou nome DNS
  pode conter quase tudo, e a segurança vem do argv, não de um padrão

**Não colapse o `ProcessBuilder` em `sh -c`.** Toda a validação do lado Dart é
escrita para preservar essa propriedade.

## Teto de 8 KB na saída

`dumpsys package` de um app grande passa de 1 MB e o LiteRT está travado em
ctx 4096. Saída sem teto não desperdiça o turno, ela encerra o turno.

Resultado cortado termina com `[... truncated, N KB omitted]`. O marcador importa
tanto quanto o corte: um modelo que recebe um fragmento silencioso conclui em
cima de dados parciais com a mesma confiança.

## Peças

| Arquivo | Papel |
|---|---|
| `lib/services/tools/privileged_commands.dart` | Puro: validação, argv, teto de saída |
| `lib/services/tools/privileged_tools.dart` | As oito tools sobre um runner injetado |
| `lib/services/privileged_service.dart` | Estado, identidade, canal; e o gate `privilegedToolsIfReady` |
| `android/.../IPrivilegedService.aidl` | Contrato AIDL |
| `android/.../PrivilegedUserService.kt` | Roda no processo do Shizuku |
| `android/.../ShizukuShell.kt` | Bind, probe, permissão, execução |

## Armadilhas já pagas

- **Android 11+ esconde outros pacotes.** Sem `<package android:name="moe.shizuku.privileged.api"/>`
  dentro de `<queries>`, o teste de "está instalado?" responde não para sempre.
  O manifesto já tinha um bloco `<queries>`; entrou nele, não num segundo.
- **AIDL não aceita ids parciais.** O Shizuku chama `destroy()` num id de
  transação fixo (`16777114`), então todos os métodos são numerados.
- **`flutter analyze` não lê Kotlin.** Erro de import aqui só aparece no build.
  Este repo já perdeu uma sessão para exatamente isso.

## Fora de escopo no v1

Gerenciamento de apps (instalar, desinstalar, congelar, limpar dados) e
automação de tela (`input`, `screencap`, `am start`). Decisão, não omissão.

Nota: com este bloco o registry vai de 18 para 26 tools. O comentário no
`tool_registry.dart` manda revisitar o desenho sem meta-tools acima de
"roughly a dozen" — esse limite já tinha sido cruzado antes daqui, e a pergunta
sobre `list_tools`/`search_tools` continua aberta.
