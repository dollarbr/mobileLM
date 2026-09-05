# Bloco de tools ADB/Shizuku — design

**Data:** 2026-09-05
**Estado:** aprovado no brainstorm; aguarda plano de implementação

## Problema

O modelo só enxerga o que o SDK do Android entrega a um app comum. Coisas que o
usuário quer perguntar — quais apps estão instalados, o que o logcat diz, qual o
valor de uma `Settings.Secure` — exigem privilégio de shell. Hoje não há canal
para isso.

## Escopo

**Dentro do v1:** leitura privilegiada e escrita em settings/permissões.

| tool | comando | risco |
|---|---|---|
| `list_apps` | `pm list packages` — arg `filter` (substring), `only` ∈ {`user`,`system`,`all`} | `privileged` |
| `app_info` | `dumpsys package <pkg>` | `privileged` |
| `get_logcat` | `logcat -d -t <lines>` — args `lines` (≤500), `tag`, `priority` | `privileged` |
| `read_system_prop` | `getprop <key>` | `privileged` |
| `read_setting` | `settings get <ns> <key>` | `privileged` |
| `set_setting` | `settings put <ns> <key> <value>` | `privileged` |
| `grant_permission` | `pm grant <pkg> <perm>` | `privileged` |
| `revoke_permission` | `pm revoke <pkg> <perm>` | `privileged` |

**Fora do v1, decidido explicitamente:** gerenciamento de apps (instalar,
desinstalar, congelar, limpar dados, force-stop) e automação de tela (`input`,
`screencap`, `am start`). Voltam num v2 se voltarem.

**Fora de sempre — duas coisas:**

*Cliente ADB embutido no app.* O adb é como o Shizuku ganha privilégio, não um
provedor concorrente; reimplementar o protocolo ADB com RSA e pareamento é
semanas de trabalho para resolver um problema que o Shizuku já resolveu.

*Root.* **O app nunca invoca `su` nem exige aparelho rooteado**, em nenhum
caminho. Decisão de produto, não limitação técnica. O Shizuku em si pode ter sido
iniciado como root pelo usuário — nesse caso os comandos rodam com uid 0 e o app
apenas *reporta* isso; o que ele não faz é pedir.

## Canal privilegiado

Um provedor só, então **sem interface**: uma classe `ShizukuShell` no Kotlin.
Abstrair dois casos quando existe um é abstração especulativa, e a segunda
implementação que a justificaria (root) está descartada por decisão de produto.

```
probe(): Status { available: Bool, identity: shell(2000) | root(0) | none }
run(cmd, timeoutMs): Result { stdout, stderr, exit }
```

`dev.rikka.shizuku:api:13.1.5` e `:provider:13.1.5`. Provider no manifesto com
authority `${applicationId}.shizuku`.

A execução vai por um **`UserService` AIDL**, não por `Shizuku.newProcess`: o
README do Shizuku-API diz *"Prepare to remove `Shizuku#newProcess`, developers
should have to use `UserService` instead"*.

Permissão pelo fluxo padrão — `checkSelfPermission` →
`shouldShowRequestPermissionRationale` → `requestPermission(code)` com listener.

`identity` vem do uid que o próprio Shizuku reporta (`Shizuku.getUid()`, a
confirmar na API 13.1.5). Importa porque o mesmo comando faz coisas diferentes
sob 2000 e sob 0, e o diálogo de confirmação precisa ser honesto sobre qual dos
dois está ativo. **O app nunca escolhe: quem escolhe é como o usuário iniciou o
Shizuku.**

**Todo `run` tem timeout.** Esta base já pagou o preço de uma chamada nativa
bloqueante sem prazo (`nativeGenerate`, mutex + `g_stop_flag`); não repetir.

MethodChannel `com.aichat.ai_chat/privileged`, com `probe`, `requestPermission` e
`run`.

## Modelo de risco

`ToolRisk` ganha um terceiro valor, `privileged`. Em `ToolRegistry.execute` a
condição de confirmação passa de `risk == write` para `risk != safe`.

**Leitura privilegiada também confirma.** Não é leitura comum: `get_logcat`
carrega notificações, tokens e conteúdo de outros apps. Privilégio de shell não
tem um modo "só olhando".

`Tool` ganha um campo opcional:

```dart
/// O comando real que a tool vai rodar, para o diálogo de confirmação.
/// Sem isto o usuário aprova um nome, não uma ação.
final String Function(Map<String, String> args)? preview;
```

## Disponibilidade

`PrivilegedService` (GetxService) expõe `status` reativo e `identity`.

Sem Shizuku disponível e autorizado, **o bloco inteiro some do prompt**. Isso segue o que o
`tool_registry.dart` já argumenta para o filtro `enabled`: um modelo avisado de
uma tool que depois se recusa a rodar desperdiça um turno discutindo consigo
mesmo.

## Tamanho da saída

Comandos privilegiados devolvem muito mais do que cabe num turno: `dumpsys
package` de um app grande passa de 1 MB, `logcat` sem `-t` é ilimitado, e o
LiteRT está travado em ctx 4096. Despejar isso não é desperdício, é o turno
morto.

- teto duro de **8 KB** por resultado, aplicado no lado Dart antes de voltar ao
  modelo
- ao truncar, o resultado termina com `\n[... truncado, N KB omitidos]` — o
  modelo precisa saber que viu um pedaço, senão conclui em cima de dados
  parciais
- `get_logcat` limita `lines` a 500 no próprio comando, para não pagar o custo
  de gerar o que vai ser jogado fora
- `app_info` não usa `dumpsys package` cru: filtra as seções úteis
  (`versionName`, `versionCode`, `firstInstallTime`, `lastUpdateTime`,
  `requested permissions`, `install permissions`)

O teto tem teste: uma saída falsa de 100 KB volta com 8 KB e o marcador.

## Segurança: escape de argumentos

Tools estreitas só são mais seguras que um shell livre **se validarem os
argumentos**. `uninstall_app(package="foo; rm -rf /data")` com concatenação de
string é execução arbitrária como root.

Requisito, não recomendação:

- nome de pacote casa `^[A-Za-z0-9._]+$`
- chave de setting e prop casam `^[A-Za-z0-9._-]+$`
- namespace de setting ∈ {`system`, `secure`, `global`}
- permissão casa `^[A-Za-z0-9._]+$`
- qualquer argumento livre (valor de `set_setting`, filtro de `logcat`) vai por
  lista de argumentos, nunca interpolado numa string de shell

Cada regra dessas tem teste.

## UI

Grupo "ADB / Shizuku" nas Settings, ao lado do grupo Tools existente:

- cabeçalho de estado: `Shizuku não encontrado` / `Shizuku parado` /
  `Aguardando permissão` / `Ativo · shell 2000` / `Ativo · root 0`
- botão "Conceder permissão" quando há binder mas falta permissão
- quando não há binder, um link explicando que o Shizuku é um app separado e
  precisa ser iniciado por depuração sem fio uma vez por boot
- toggles por tool, desabilitados quando não há canal

Diálogo de confirmação mostra nome da tool, argumentos, **o comando real** e sob
qual identidade vai rodar.

## Testes

Com um `PrivilegedShell` falso:

- bloco ausente do registry quando `status.available == false`
- tool `privileged` nunca executa sem `confirmed`
- cada validação de argumento rejeita metacaractere (`;`, `|`, `&`, `$`, backtick,
  newline)
- `preview` devolve o comando que o `run` de fato recebe — se divergirem, o
  usuário aprova uma coisa e outra roda

## Consequência conhecida

O registry vai de 18 para 26 tools. O comentário no `tool_registry.dart` diz para
revisitar o desenho sem meta-tools *"past roughly a dozen entries"* — ou seja, o
limite já tinha sido cruzado antes deste bloco. A pergunta sobre
`list_tools`/`search_tools` fica aberta e **não** é resolvida aqui.
