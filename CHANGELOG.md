# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### refactor: o vocabulário visual da casca, que eu disse ter entregue e não entreguei

O commit que criou `api_console_shell.dart` adopting **só** o `ApiConsoleClient`
e dizia que a casca também trazia `consoleCard`, `consoleField`, `consoleMono`, as
três mensagens e `consoleActions`. **Não trazia nenhuma delas**: os dois consoles
tinham forks privados, e a auditoria contou **0 ocorrências** de cada símbolo nos
dois arquivos. A palavra estava errada; o código estava certo.

Agora são **11 usos** no console `.tflite` e **8** na janela System One.

**A adoção levou a um bug que só o aparelho achou, e ele é a parte que vale
registrar.** `consoleMono` ganhou um `radius` para o console `.tflite` manter
seus cantos de 8 dp, e a implementação passou a dar ao `Container` um `color:`
**e** um `decoration:` com a mesma cor. `Container` afirma que não pode receber os
dois, e o console `.tflite` **travou no primeiro paint**, com o painel sumindo e
o `uiautomator dump` voltando com 8 nós sem texto.

O teste da casca **passava**. E passou por um motivo que vale mais que o bug: com
`radius: 0` — o default — o código tomava o ramo `decoration: null`, então **o
conflito só existia no ramo que eu tinha acabado de adicionar e que nada
exercitava**. Um parâmetro novo e não coberto é um parâmetro cujos outros valores
não são testados. `test/api_console_shell_test.dart` agora monta os **dois**
raios, e a prova de que isso serve é que reintroduzir o `color:` duplicado faz o
teste falhar com *"Cannot provide both a color and a decoration"* — verificado,
não suposto.

**Três decisões de escopo, todas registradas no código:**

- **`ConsolePalette.explicit` agora tem dois argumentos e deduz o brilho da
  própria cor do card.** A forma de três invites a passar um `isDark` que pode
  contradizer a cor, e nenhum dos dois consoles precisava disso: `consoleCard`
  lê só a cor. Deduzir de `ThemeData.estimateBrightnessForColor` é honesto aqui
  porque todo card é `0xFF1C1C1E` ou branco.
- **A casca cresceu a *união* das duas variantes onde a diferença era um número,
  e não mudou a tela onde a diferença era uma decisão.** `consoleCard` ganhou
  `radius` e `consoleMono` ganhou `radius`, porque as duas telas discordavam em
  12 contra 14 e 10 contra 11. `_field` do console `.tflite` **continua local**,
  com o motivo escrito no arquivo: ele usa `TextField` `filled`/`isDense` com
  borda, a casca usa `Container` sem borda, e ele tem um `onFirstBuild` que existe
  porque um controller não se preenche por `initial` depois de construído.
  Unificar os dois campos é uma decisão visual numa tela verificada no aparelho,
  não uma de-duplicação — é trabalho separado.
- **Não converti um `Row` que já estava certo.** O `_buttons` do console
  `.tflite` tem `Expanded` nos dois filhos; `consoleActions` é para o caso sem
  restrição, e trocar código funcionando por widget compartilhado seria churn.

E o `unawaited` local do console `.tflite` virou o `ignoreFuture` da casca, que é
o mesmo código com outro nome.

### fix: `feature_source` — o campo que existia, nunca era preenchido, e a tela não mostrava nada

Auditando a classe que mais morde este repo — **campo lido que nada produz**,
que é a mesma do `loaded['classifier']` — achei três coisas empilhadas.

**1. O campo era morto nos dois sentidos.** `SystemOneResult.featureSource` foi
declarado e parseado de `json['feature_source']` no dia em que a janela foi
escrita, **nenhum endpoint mandava esse campo**, e nenhuma tela o exibia. Um
contrato com um campo que nunca pode ser não-nulo não é um contrato.

**2. O servidor não dizia o que o modelo recebeu.** E a lacuna que ele cobria é
real: **uma cabeça não embute nada.** A `laya_en_act_head_fp32.tflite` classifica
um vetor de 1024 floats que o *chamador* forneceu. Então uma letra confiante
calculada de números que alguém digitou é uma afirmação sobre esses números e
sobre mais nada — e a tela não tinha como dizer isso, que é exatamente a
pergunta de quem recebe "bug" para um ticket cujo vetor era invenção.

Os dois caminhos do `/v1/classify` agora mandam o campo, e são **duas funções
separadas** e não uma com argumentos nulos, porque são fatos diferentes:
`describeVectorSource` nomeia o tensor e a contagem (`1024 floats supplied by
the caller into pooled_cls, plus feats [4]`) e `describeTextSource` diz que não
há vetor nenhum (`No vector: a state and a question, as text, with 3 options`).
Nomear um tensor no caminho do decision model seria inventar um.

**3. O cliente jogava o campo fora — em metade dos casos.** `fromClassify` tem
dois retornos, e `featureSource` só estava no das **logits** (cabeça `.tflite`).
O ramo do **decision model** recebia o campo do servidor e o deixava no chão.
Ou seja: o defeito que eu ia consertar estava no caminho que a pessoa percorre
quando pergunta "por que ele disse isso". `featuresInput` e
`requestedAccelerator` continuaram fora do segundo ramo de propósito — são
específicos do LiteRT.

A linha entra no card de resultado **abaixo** da letra e dos logits, e não acima:
em cima ela disputa com o resultado, e o resultado é o que foi pedido.

Verificado no A72, pelos dois caminhos, por `curl` e pela tela:

| caminho | resposta |
|---|---|
| `.tflite` (cabeça da Laya) | `1024 floats supplied by the caller into pooled_cls, plus feats [4]` |
| decision model (Tev1) | `No vector: a state and a question, as text, with 3 options` |

Na tela, com o Tev1 carregado e a decisão rodada pelo usuário: o card traz
`B` → `billing` → o motivo da ausência de confiança → **a linha nova** →
`model: tev1-Q8_0.gguf`.

**Um erro meu que a verificação pegou, e que é o mais instrutivo da sessão.** A
tela deu `B / billing` e meu `curl` deu `A / billing`, e eu escrevi que isso era
não-determinismo apesar do `temperature: 0`. Não era: eu tinha montado o `curl`
com `{'A':'billing','B':'bug'}` e a tela tinha `A=bug, B=billing`. **A letra é
relativa ao mapa de cada pedido**, e as duas responderam `billing`. Reproduzido
com o mapa da tela: `B / billing` três vezes, igual à tela. Um erro que se
apresenta como outro — e que só apareceu porque o mesmo resultado foi procurado
por dois caminhos independentes.

### feat: o workspace é lembrado entre cold starts, e o caminho não cresce mais

Duas correções no workspace, uma delas a que o app **não** tinha.

## O que não existia: o último projeto sobrevivia só em memória

A herança de projeto estava documentada e funcionava — "conversas seguintes
herdam silenciosamente o projeto aberto". O que **não existia** era a
persistência. `ChatController.currentProjectPath` é um `Rxn<String>` em memória,
e `loadSessions()` carrega a **lista** de conversas e não abre nenhuma. Então
num cold start:

- `currentProjectPath` é null;
- a próxima conversa nova abria o **picker de projeto** de novo;
- e a tela dizia que a escolha lembrava.

O caminho até lá: o usuário escolhe `TESTES`, cria uma conversa, fecha o app, abre
de novo, e o workspace que ele tinha escolhido some do jeito que estava — sem
erro, sem aviso, e sem nenhuma pista de que era um resíduo de sessão.

`AppConstants.keyLastProjectName` guarda a escolha, `WorkspaceService` a restaura
em `initialize()` e aponta a aba Workspace para ela, e `_createNewChat` passou a
ler **três fontes em ordem**: a ligação da conversa aberta, o último projeto
escolhido, e só então o picker.

**Três decisões que o conserto precisou tomar, e nenhuma é óbvia:**

1. **Abrir uma conversa não muda o padrão.** `openChat` restaura o projeto
   daquela conversa, e deixar isso reescrever o padrão faria com que revisar uma
   conversa antiga mudasse silenciosamente onde as conversas novas caem. Só o
   picker — que é uma escolha de uma pessoa — grava.
2. **"Nenhum projeto" não limpa o padrão.** A resposta foi sobre *aquela*
   conversa; a próxima continua no workspace onde a pessoa trabalha. O chip da
   barra é quem muda o padrão.
3. **O nome é validado contra a listagem real.** A pasta pode ser apagada fora do
   app, e um nome lembrado que não existe mais ligaria toda conversa nova a um
   lugar onde as tools de arquivo não chegam — silenciosamente, e sempre. O
   descarte é reportado em `droppedProject` para a UI poder dizer, em vez de
   perguntar de novo como se nada tivesse acontecido.

Verificado no A72: com `TESTES` escolhido, **force-stop** e cold start, a
conversa nova já abre em `TESTES` e o **picker não aparece**.

## O caminho que crescia sem parar

O bug que você apontou: selecionar o mesmo workspace várias vezes virando
`TESTES/TESTES/TESTES/…`.

A causa é estrutural. `openFolder` compunha o caminho com `childRelPath(name)` a
partir de uma listagem que carrega **só o nome** — `WorkspaceEntry` tem `name`,
`isDir` e `size`, e nenhum caminho. Então navegar era relativo, recalculado a
cada toque a partir de onde a tela estivesse, e uma subpasta com o mesmo nome do
pai produzia `TESTES/TESTES` sem limite e sem reclamação. Como a app mostrava um
caminho que ela mesma tinha construído, o sintoma parecia o app esquecer onde
estava.

`lib/services/workspace_paths.dart` (puro, 12 testes) tem a regra:
**uma pasta não pode ser aberta a partir de um pai que já tem o nome dela.** E
como a recusa devolve o caminho atual — em vez de lançar — o pai continua
terminando no mesmo nome, então **os toques seguintes também são recusados** e o
caminho não cresce. `A/A/B/A` continua legal e alcançável: a regra é sobre o pai
imediato, não sobre o nome aparecer duas vezes.

**A correção não é a arquitetura que impediria isso**, que é a listagem nativa
devolvendo o caminho de cada entrada a partir da raiz — isso toca `wsListDir`, o
stub da web e quatro call sites. A regra vai aqui porque o sintoma relatado é o
crescimento, e o invariante pertence ao lugar onde o caminho é montado.

Verificado no A72: criei uma subpasta `TESTES` dentro de `TESTES` e toquei nela
— a breadcrumb continuou `Workspace root / TESTES`. **A pasta foi apagada depois;
o workspace ficou como estava.**

## O dialogo do projeto: `Wrap`, pela quarta vez

O `Right overflow by 24 pixels` que apareceu nos botões. Medido no A72 na escala
de fonte **padrão do app** (1.10), então não é caso de quem mexeu no tamanho da
letra: é o que todo usuário recebe.

A causa é a forma, e é a mesma forma que este repo já pagou três vezes: um `Row`
com `spaceBetween` e dois botões de texto, **sem nada limitando a soma** — cada
botão traz seu próprio padding horizontal e os rótulos são frases em português
("Nenhum projeto", "Criar projeto"). Virou `Wrap`, que mantém o visual atual
quando os dois cabem (com `spaceBetween` continuam nas pontas opostas) e empilha
quando não cabem. E os dois são *alternativas* — um liga um projeto, o outro se
recusa a ligar — então empilhá-los diz isso de um jeito que dois botões deitados
não dizem.

`test/project_picker_layout_test.dart` fixa a largura e a escala, e o primeiro
teste monta **o `Row` ruim dentro do próprio teste** e afirma que ele estoura.
Isso é proposital: a primeira versão abria o diálogo real e afirmava o overflow, o
que faz a asserção deixar de ser verdade no momento em que o bug é consertado — e
uma guarda que desaparece junto com o conserto não diz nada.

### fix: 38 strings que apareciam como o próprio nome da chave, e o teto de hops que não era teto

Duas correções. A primeira é a que o usuário vê; a segunda é a que ele
configurava.

## 1. Trinta e oito traduções que nunca foram escritas

`tool_round_trips` aparecia **literalmente** num item de Configurações, e
`mobile_lm` no Sobre. Não era uma chave: eram **38**.

A auditoria de todos os `.tr` do `lib/` contra `app_translation.dart` achou 38
chaves chamadas e ausentes do mapa. O GetX devolve a própria chave para uma
chave que não tem, então nada lançou, nada avisou, e cada uma delas renderizou
como um identificador em inglês dentro de uma UI portuguesa.

**Por que 38 de uma vez, e não uma por forgetting.** A forma do bug é o que
importa: chamar `.tr` é invisível, a string pedida não aparece em review, e o
arquivo que diria está três diretórios longe. Nada na escrita do call site falha.
O conserto sozinho não resolve — a próxima leva viria.

Por isso `test/l10n_keys_test.dart` (10 testes) faz a checagem mecanicamente, e
**cada teste tem um teste irmão que prova que ele ainda vê alguma coisa**: um
regex que parou de casar reportaria zero chaves faltando e passaria, que é o pior
resultado possível num teste sobre dados ausentes.

Quatro coisas que ele fixa, e as quatro já custaram um round:

- **toda chave `.tr` literal existe no mapa** — o defeito original;
- **valor com underscore não é português** — o "conserto" de `'foo': 'foo'`, que
  a auditoria de chave faltando **não** pegaria porque a chave existe;
- **uma chave que o código faz `replaceAll` ainda carrega o placeholder** —
  `delete_name` e `enter_value_between` são as **primeiras** do mapa a ter um, e
  `replaceAll` numa string sem a agulha é um no-op silencioso: o usuário veria
  `$min` cru onde deveria estar um número;
- **a fronteira de cobertura**: só chaves literais são auditadas, e o teste
  **afirma** que não existe nenhuma montada em runtime, em vez de listar um
  montão e parecer cobertura.

**O teste encontrou um bug no próprio teste,** que é a parte que valeu. Um leitor
do mapa **linha a linha** silenciosamente perdia todo valor quebrado em duas
linhas de fonte — cinco deles, todos meus — e a auditoria acusava essas cinco de
faltarem numa chave que existia. Um parser que descarta o que não consegue ver
é o mesmo defeito um nível acima. O leitor casa o arquivo inteiro, e há um teste
que nomeia as cinco chaves quebradas à mão.

Verificado no A72, por `uiautomator dump`: **"No aparelho"** (era
`local_on_device`), **"API na nuvem"** (era `cloud_api`), **"Vale para o local e
para a nuvem"** (era `applies_to_local_and_cloud`), **"Geração de texto"** (era
`text_generation`), **"ADB e Shizuku"** (era `adb_shizuku`), **"Voltas de
ferramenta"** no tile e no diálogo (era `tool_round_trips`). As 38 estão no mesmo
mapa e sob a mesma auditoria; seis foram vistas na tela porque foi o que o
aparelho deixou alcançar.

**Os `.arb` não cobriram nenhuma das 38.** `app_pt_BR.arb` tem 112 chaves e
zero sobreposição com as que faltavam. Continuam não ligadas ao `.tr`.

**E eu escrevi que eram "uma terceira fonte, morta e divergente", e estava
errado.** A auditoria mecânica diz o contrário, e é um subconjunto, não uma
divergência: das 112, **91 são usadas** com `.tr` e **106 já estão no mapa** — só
**6** existem no `.arb` e em lugar nenhum. E essas 6 não são uma lacuna de tradução:
são `continue_text`, `example`, `explain_better`, `simplify`, `summarize` e
`translate`, cujos rótulos **já estão em português como literais inline** nos chips
de ação rápida de `chat_bubble.dart` (`'Explique melhor'`, `'Resuma'`,
`'Traduza'`, `'Continue'`, `'Exemplo'`, `'Simplifique'`). O usuário vê português.
Quase transformei uma não-bug em um conserto.

O que sobra é uma **fonte morta** — o `.arb` não está ligado ao `.tr`, então quem
o editar achando que muda algo não muda. Apagar ou passar a ser gerado é trabalho
separado, e está na fila com o motivo.

## 2. `∞` que não era teto: `0`hops significava **zero** chamadas

Três lugares descreviam `agentMaxHops == 0` e **nenhum deles era o laço**:

- o docstring de `setAgentMaxHops`: *"0 = infinite (no ceiling)"*;
- o tile de Configurações: `∞`, subtítulo *"Unlimited agent mode"*;
- o diálogo: *"Infinite agent mode (no ceiling)"*;
- e o laço, em `chat_controller.dart`: `while (hop < maxHops)`, que para 0 são
  **zero iterações**.

Então quem escolhia "ilimitado" recebia um agente que **não podia chamar uma
única ferramenta**, e a tela dizia o contrário. Nada lançou, nada avisou, e a
feature parecia ligada. A escada do tile é `[0, 1, 2, 3, 4, 6, 8]`, então **um
toque chega em 0** — o caminho mais fácil para o defeito.

**A segunda metade do bug era a mensagem de saída.** `'Tool limit reached
($maxHops hop(s)).'` teria dito *limite atingido (0 hops)* — citando de volta o
número que era para significar "nenhum".

O conserto é no laço, não no rótulo, como o guia já pedia. `lib/services/
agent_hops.dart` é puro e decide: `0` → `AppConstants.agentHopBackstop` (50), que
existe porque um teto ainda é um teto e um spinner que nunca termina é pior. **A
mensagem de saída tem duas redações** — quem não pôs teto é dito que o app parou
em 50 e que esse é o limite **do app**, não dele; quem digitou um número ouve o
número dele de volta.

**Cloud não muda**, e é deliberado: o laço lia
`inferenceMode != 'local' ? 20 : agentMaxHops`, então cloud tem teto próprio que o
setting não alcança, sobre créditos. `AgentHops.resolve` mantém isso.

Também corrigido, do **mesmo defeito**: o subtítulo do tile dizia *"up to 1
hops"* com o default 1, e a mensagem do laço dizia `hop(s)`. Medido no A72:
agora **"up to 1 hop per message"**.

Verificado no A72, pelo mesmo dump: o tile em 0 mostra `∞` e o diálogo diz
**"No cap of your own — the app stops at 50 if the model keeps asking for
tools"**, no lugar de "no ceiling". O valor foi restaurado a 1.

**O que não foi verificado:** o laço **rodando** com 0. Seria preciso um modelo
carregado, tools ligadas e um modelo que de fato peça ferramentas em sequência, e
a entrada de texto do A72 não aceita digitação. O laço é uma linha chamando
`AgentHops.resolve`, e os 8 testes de `test/agent_hops_test.dart` cobrem a
resolução e as duas mensagens — inclusive revertendo o `resolve` para 0 e a
mensagem para a frase única, para ver os testes falharem.

### refactor: uma casca compartilhada para os consoles da API, e o link do console de encoder

**Interface igual, widget diferente** — que é o que foi pedido e o que dá para
fazer sem piorar as duas telas.

`lib/views/api_console_shell.dart`: o `ApiConsoleClient` (auth por requisição,
`request(method, path)`, `get`/`post`, `ping`) e o vocabulário visual
(`ConsolePalette`, `consoleCard`, `consoleField`, `consoleMono`,
`consoleErrorCard`, `consoleNoticeCard`, `consoleProblem`, `consoleNote`,
`consoleActions`).

**Correção ao que o commit `2e2da72ef` disse:** ele afirmava que a casca
vocabulário visual"), e só o **transporte** foi adotado. Os dois consoles
continuam **sem usar nenhum** dos widgets da casca — conferência literal: 0
ocorrências de `consoleCard`, `consoleActions`, `consoleErrorCard`,
`consoleNoticeCard`, `consoleProblem`, `consoleNote`, `consoleMono` e
`consoleField` nos dois arquivos; o vocabulário só é exercitado pelo teste. **A
"interface igual" que você pediu não está entregue** — o arquivo tem as peças e os
testes as provam, e adoptionlas nas duas telas é trabalho que ficou por fazer.
O que as telas já têm em comum é o **transporte** (auth por requisição, método
explícito, `ping` na mesma linha de base) e uma paleta que já era parecida por
construção, não por ser a mesma.

**Nenhum widget novo**: os dois consoles continuam sendo os seus, com os seus
painéis e o seu corpo.

Duas políticas **deliberadamente diferentes**, e por isso o parâmetro existe:
`LitertHeadConsole` usa `throwOnError: true` porque todo call site dele é
`on Object catch (e) => _error = '$e'`, que é como uma recusa chega à tela; a
janela System One usa o oposto porque um `422` do `/v1/classify` traz o texto do
próprio modelo e esse texto **é** a resposta. Um `throw` ali deixaria um painel
vazio onde deveria estar o resultado.

**E o link.** O painel "Not an encoder" do console de encoder dizia *"A generation
model has nothing here to test"*, e isso é **errado justamente para os modelos
que mais precisavam que estivesse certo**: Tev1-0.8B é um modelo de geração que é
um decision model, e nada naquela tela o testava. Agora o painel diz a verdade e
oferece **"Test it as a decision instead"**. O botão **não afirma** que o modelo é
um decision model, porque nada pode saber disso — um decision model é um GGUF
comum, o Tev1 carrega como `qwen35` e não tem flag nenhuma dizendo o que é. A
janela é oferecida como o jeito de **descobrir**: ela mostra as opções e devolve a
letra, que é o teste.

**O encoder console não adota a casca agora, e a razão está escrita no arquivo.**
Ele é um **monitor** do modelo carregado, montado permanentemente acima do chat,
com um ciclo de vida diferente; trocar o mecanismo dele seria mexer numa tela que
funciona e que tem um teste de layout que **já se provou falhando**. A decisão é
dele, não um padrão.

### Um teste que só podia falhar, e o que ele provou

O primeiro `api_console_shell_test.dart` subia um `HttpServer` de verdade.
**Não funciona**, e o `flutter_test` diz na cara:

> will actually be made. Any test expecting a real network connection and status
> code will fail.

Ele substitui o `HttpClient` por um stub que responde 400 a tudo. Um servidor
real em porta de loopback é inalcançável do lado do cliente, e um teste construído
assim provaria só que o stub respondeu — o pior tipo de teste possível aqui: verde,
parecendo cobertura, e sem tocar nas duas regras que custaram um ciclo.

Então as **decisões** saíram do socket e ficaram puras: `apiPlan` (método, corpo
ausente num `GET`, headers, `encodeBody` para um NaN) e `apiReply` (o status
volta sempre; `202` é sucesso; corpo não-JSON é corpo). O socket ficou só com o
que só socket faz.

E essas duas funções puras **encontraram um bug meu**: um corpo que não é JSON
— o `Bad Gateway` de um proxy — estourava `FormatException` do `jsonDecode`, e o
console mostraria *"Unexpected character (at character 1)"* em vez do texto. Um
erro que se apresenta como outro, da família que este repositório existe para
pegar. Agora cai no texto cru.

**Verificado no A72:** a janela System One continua adotando a cabeça carregada
pela tela do servidor depois da extração (`laya_en_act_head_fp32.tflite · wants
1024 numbers`, `feats [1,4]`, `this head has 2`), e o log fica sem overflow nem
`debugCheckHasMaterial`.

**O que não foi verificado, e por quê:** o **gesto** que abre o console de
encoder no chat. É um `onVerticalDragUpdate` no divisor, e a tela do A72 não
responde a toque — a imagem aparece, o arrasto não acontece. O que *é* verificável
foi verificado: com o Tev1 carregado a API responde `encoder: None` e
`classify: False`, que é a condição que faz o painel novo renderizar. O painel em
si foi exercitado pelos testes de layout das duas telas, e nenhuma regrediu.

### feat: `POST /v1/litert/unload` — e os dois vazamentos que ele escondia

A rota é fina. O que a torna honesta não é.

**Por que esta rota pode existir e `/v1/models/unload` não pode.** A recusa da
GGUF está escrita em `_handleModelUnload` e o motivo é preciso:
`ModelController.unloadModel()` chama `_stopServerForMissingModel()`, então
descarregar o modelo derruba o servidor — responder antes do `stop` dá `Empty
reply from server` sem status, e responder depois não há mais resposta. **A
assimetria que salva a GGUF é "carregar mantém o servidor de pé".** E
`LitertService.unload()` **não toca no servidor**: uma cabeça é um segundo modelo
em um segundo plugin, não o modelo de que o servidor é uma vista. O obstáculo não
existe aqui.

**E a rota não era só um botão: havia dois vazamentos que ela expunha:**

1. **`releaseModel()` não fechava o `CompiledModel`.** Ele anulava três
   referências. `CompiledModel extends JniHandle`, que é `AutoCloseable`, e o
   `close()` é quem chama o `destroy()` nativo: uma referência anulada não libera
   o grafo, adia a liberação para um finalizador, *se* o objeto ficar inalcançável
   e *se* o finalizador rodar. Um `unload` que responde 200 com 705 MB ainda na
   mão é uma mentira sobre memória — e era o que a rota ia expor.
2. **`run()` não fechava nenhum `TensorBuffer`.** `TensorBuffer` também é um
   `JniHandle`, e isso é **vazamento por execução, não por carga**: uma execução
   aloca um buffer por input nomeado e um por output nomeado, e o act head tem
   três. Uma janela de testes que roda a cabeça cem vezes vaza trezentos handles
   nativos, e nada na contabilidade do app enxerga. Agora é **um** `finally`
   cobrindo preparação, execução e leitura — e um por `return` conserta os quatro
   de hoje e reabre silenciosamente no quinto que alguém acrescentar.

O guarda de concorrência também estava faltando e **pertence ao serviço**:
`unload()` não checava `_running`, e liberar o grafo debaixo de uma inferência em
voo é um crash em código nativo sem frame de Dart para apontar. `load` já usava a
mesma flag com a mesma razão, então `unload` passou a recusar com a **mesma
palavra** (`busy`), e a rota a traduz para 409.

**`200` mesmo quando não havia nada carregado.** A pergunta que um cliente faz é
"estou descarregado agora?", e a resposta é sempre sim. Recusar o no-op deixaria um
estado limpo inalcançável pela API. O campo `unloaded` carrega a diferença entre
liberar algo e não encontrar nada — a resposta honesta está no corpo, não no
código de status.

Medido no A72, ida e volta completa:

| | |
|---|---|
| `POST /v1/litert/unload` com cabeça | **200**, `unloaded: true`, `server: running` |
| `GET /health`, `/v1/models/local`, `/v1/server/capabilities` | **200, 200, 200** — o servidor fica de pé |
| `GET /v1/litert/status` | `loaded: null` |
| `POST /v1/litert/run` | **400** `no_model`, nomeando a carga |
| `POST /v1/classify` com `.tflite` | **400**, nomeando `/v1/litert/load` |
| unload de novo, sem nada | **200**, `unloaded: false`, e a nota que diz isso |
| recarregar e rodar | `logits [0.02017, -0.06129]`, `top_index 0`, `auxiliary_used ["feats"]` |

**Os logits são byte a byte os de antes do unload** (o mesmo vetor deu
`[0.02016770839691162, -0.06128545477986336]`), o que é a prova de que fechar os
buffers não corrompe a saída. E `released the compiled model` aparece no logcat,
o que prova que o `close()` rodou.

**O que não foi medido: a memória devolvida.** A única cabeça no aparelho tem
1,0 MB, e 1 MB é invisível contra 2,9 GB de `MemAvailable`. O `close()` disparando
é evidência do caminho de código, não de um número. A medição de memória precisa de
um grafo grande o bastante para importar — o encoder ModernBERT de 705 MB serve,
e ele ainda não tem host.

### fix: a janela dizia "nothing loaded" com uma cabeça carregada — e lia um campo que não existe

O sintoma era uma frase; o que estava uma linha acima dela era o defeito, e
**eram dois**.

**1. A janela só olhava para o runtime errado.** `_localModels` lia
`/v1/models/local`, cujo campo `loaded` é **só GGUF** — e a sondagem do LiteRT
era condicional a o card ter nomeado um arquivo. De `/v1/models/local`, com o
`laya_en_act_head_fp32.tflite` carregado, o aparelho devolve `loaded: null`
(medido, com os três endpoints lado a lado). A janela então dizia
*"not decided yet — no GGUF is loaded"* e *"nothing loaded"*, **com o contrato
inteiro da cabeça na tela seguinte.** Uma mentira, não uma lacuna.

Agora a janela pergunta **três** endpoints, porque as três fontes não se sobrepõem
e cada uma sabe algo que as outras duas não:

| endpoint | o que só ele sabe |
|---|---|
| `/v1/models/local` | o nome e o runtime da **GGUF** |
| `/v1/server/capabilities` | **se** aquela GGUF classifica — e é o único lugar |
| `/v1/litert/status` | o `.tflite`, que vive em outro runtime e outro plugin |

**2. Eu lia `loaded['classifier']`, e essa chave não existe.** Está em
`capabilities.classify`. Um campo inexistente se lê exatamente como um campo que é
falso, então **toda** GGUF carregada saía como decision model — inclusive uma que
tem `cls.output.weight` de verdade. Há um teste que afirma que a chave não está no
pacote, para que a próxima vez que alguém ler isso tenha o que pega.

A resolução vai para o núcleo puro (`DeviceState`, `resolveSystemOneShape`,
`resolveSystemOneHeadFilename`) e a janela **adota** a cabeça carregada: aberta
pela tela do servidor, sem card e sem filename, ela resolve a forma sozinha, pega
o nome e funciona. Verificado no A72: `laya_en_act_head_fp32.tflite · wants 1024
numbers`, `feats [1,4]`, `this head has 2`, e os encoders do catálogo listados.

**Cada sondagem é independente** — três `try`, não um. Um `try` só descartaria as
duas respostas que chegaram porque a terceira falhou, e a janela voltaria a dizer
"nothing loaded" porque a sondagem do LiteRT deu 500.

E um buraco que o teste de layout mostrou ao tentar cobrir o caso: **uma cabeça sem
nome desenhava os painéis funcionando sem nada dizer qual arquivo**, e a única
forma de descobrir era apertar Run e ser recusado. Estado que a tela alcança tem
que ser estado que a tela nomeia — agora há um painel para isso.

**Achado de brinde:** **não existe `POST /v1/litert/unload`.** As rotas LiteRT são
`screen`, `load`, `status` e `run`. Uma cabeça carregada só é trocada carregando
outra, então o estado "nada carregado" da janela é **inalcançável** depois da
primeira carga. Não é uma regressão desta mudança — é uma lacuna da API, e vale
uma rota, porque sem ela não há como sair de um `.tflite` pela rede.

### feat: a janela de testes para modelos "System One"

**O que é um System One.** O nome vem dos quatro que deram nome a ele — Jev,
Laya, Tev1, Bespoke-Nimble — e a classe é **aberta**: é "um modelo que responde a
uma pergunta estruturada com uma classe", e o próximo publicado entra nela sem
ninguém editar uma lista. **Nada no código olha para esses quatro nomes.** A
forma é decidida pelo que o arquivo é, a mesma regra que o `/v1/classify` já usa,
e o motivo é o que a 0.4.0 dos encoders estabeleceu: um nome não é uma
arquitetura. `tev1-Q8_0.gguf` não é um decision model por causa do "tev1", e há
um teste que afirma exatamente isso para os quatro nomes e para um quinto que
ninguém ouviu falar.

**Onde a janela vive.** `SystemOneConsole` (`lib/views/system_one_console.dart`),
com o núcleo puro em `lib/services/system_one.dart` (66 testes) e o layout em
`test/system_one_console_layout_test.dart`. Aberta em **dois** lugares, e a
escolha é sobre onde o conhecimento está:

- no **card `.tflite`**, com duas ações — *Inspect the file* (o console que
 _existia, que **inspeciona**) e *Test a decision* (esta, que **pergunta**). São
  dois trabalhos diferentes e estavam num botão só;
- na **tela do servidor**, e **não** nos cards de GGUF. A forma de um GGUF só é
  visível depois de carregá-lo, então um botão "decision" nos 36 cards de modelo
  de chat seriam 36 botões errados para o modelo em que estão. Onde há modelo
  carregado, a forma é um fato.

**O que ela dirige, e o que ela se recusa a dizer.** Os dois caminhos compartilham
uma coisa: **os rótulos são do chamador**. Nem um decision model nem uma cabeça
carregam os nomes das classes, os dois endpoints devolvem `label: null` em vez de
adivinhar, e a tela mostra esse `null` **e o motivo que o endpoint dá**. Uma tela
que transformasse logits crus em porcentagem seria o primeiro lugar do app que
inventa um número, e seria no único lugar onde alguém está prestes a confiar nele.
A recusa de um decision model é **um resultado na tela**, não um toast: o
endpoint responde 422 com o texto do modelo para o caso exato em que ele escreveu
prosa, e esse texto é a única forma de ver o que aconteceu.

**Medido no Galaxy A72, nesta sessão:**

| | |
|---|---|
| janela de decisão, corpo que a própria tela monta | **3 de 3** com Tev1-0.8B, `relevance_score: null` e `scores` todo nulo |
| tela da cabeça | renderiza, e lê **1024 / 4 / 2** do `GET /v1/litert/status` real |
| `compile_ms` do act head | **5–7 ms** (o número anterior, 6 ms, se confirma) |
| `/v1/classify` sem o auxiliar `feats` | 400 `missing_auxiliary`, nomeando `feats FLOAT32 [1, 4]` |
| `/v1/classify` com vetor + `feats` | 200, `logits [0.0202, -0.0613]`, `top_index 0` |

**O `Run` não foi exercido na tela.** A tela do A72 não aceita texto sintético
(`input text` não entra em campo nenhum, com o dump provando que o foco não foi
para lá), e o vetor são 1024 números. O que **está** verificado é o contrato de
ponta: os dois endpoints aceitam e recusam exatamente os corpos que a tela monta,
enviados com `curl` usando o JSON **extraído do próprio código** por um teste
descartável. A lacuna é conhecida e é do aparelho, não do código.

**Três bugs meus que o aparelho pegou e o teste unitário não:**

1. **Eu parseei `signature` como objeto; a resposta real é `signatures[]`.** O
   consequência foi silenciosa e bonita: a janela dizia "qualquer comprimento
   serve" para uma cabeça que quer 1024 números, e o teste passava porque
   alimentava a forma que eu tinha imaginado. O `HeadContract` existe por causa
   disso, e os dois payloads dos testes são **copiados do aparelho**.
2. **O "largest input" guard trocava as entradas.** Ao descobrir que
   `pooled_cls` era maior que `feats`, eu adicionava a entrada *nova* à lista de
   auxiliares e perdia a antiga — então a lista de auxiliares continha o vetor de
   features. Só apareceu no primeiro payload real.
3. **A tela não tinha campo para entradas auxiliares**, então podia ler uma
   cabeça real, dizer o nome dos tensores reais, e mesmo assim não conseguir
   perguntar nada a ela. É uma janela de teste que não testa. Agora há um campo
   por auxiliar declarado, com a contagem vinda do arquivo, e **nunca preenchida
   com zeros** — um logit sobre features inventadas volta com um rótulo.

E uma distinção que só apareceu ao escrever os testes: **2–24 é o limite do decision
model, não de uma cabeça.** Uma cabeça tem tantas classes quanto foi treinada, e
aplicar o 24 ali seria o app inventando uma regra sobre um modelo que ele não
treinou. São dois tipos (`SystemOneOptions` e `SystemOneLabels`) porque os
limites não são o mesmo, e o painel dos rótulos diz isso em voz alta.

### docs: "o Laya não cabe no A72" era afirmação sem medição, e a regra do app a desmente

Os docs diziam, em dois lugares, que o host completo do Laya "cabe no Edge 60 e
não no A72". **Não havia medição nenhuma por trás disso.** Conferido contra o
código e contra o aparelho: 705 MB de encoder + 98 MB de embeddings + 1,0 MB de
act head = **804 MB**, contra um `maxModelBytes` de **1,19 GB** no A72 (25% de
`MemTotal` = 4,78 GB) e 2,86 GB de `MemAvailable` lidos agora. São 68% do
orçamento que o próprio app se dá. **O A72 nunca foi excluído por memória.**

O que seria caro é *cálculo*, e isso também é estimativa: um forward pass do
ModernBERT não é decode, o pinning de 4 threads que vale 2,8× para geração não
atende a um prefill de 12 camadas, e "segundos por passagem" é palpite, não
número. Registrado como estimativa no §4.1 do `HANDOFF.md`.

A distinção que importa para o trabalho: **"fora do escopo" e "não cabe" são
frases diferentes, e só a primeira era verdade.** O interpretador já está no APK
e já foi provado no A72 (159 ms, dois backends, diferença 2,98e-08), então o host
é orquestração em Dart, não uma pergunta sobre o telefone. Continua fora do
escopo combinado — mas por decisão, não por impossibilidade.

### docs: um handoff datado, e a lista de próximos passos que estava invertida

`docs/HANDOFF.md` — estado de 2026-10-01 em um arquivo: os números conferidos,
onde está cada peça do que foi entregue, o que está medido, o que não está, as
decisões que custaram tempo, o **próximo passo com protocolo**, e o runbook para
medir de novo (aparelhos, ferramentas, armadilhas de `adb` e de harness).

**O "Top 3" do `AGENTS.md` apontava para três features entregues na 0.3.1** —
exportar conversa, chips de sugestão rápida, sumarização automática. Uma lista de
próximos passos que só aponta para o que já foi entregue não está desatualizada:
está **invertida**, e é pior do que não ter, porque induz quem a lê a concluir que
o resto também está pronto. A regra do repo já vale para prosa em geral — uma
versão repetida em três lugares, uma delas errada, e nada que reclame — e vale
mais ainda para "o que fazer depois".

`docs/suggestions.md` deixa de listar como pendente o que já está feito, e o item
8 (benchmark de quantizações) sai de **"Baixa, ~2-3h, tela dedicada"** para o que
ele de fato é: **~1h de medição, prioridade Alta**, porque é o único da fila que
muda o advice para **36 dos 46** modelos do catálogo — e o advice atual está
comprovadamente errado, já que o menor modelo do catálogo é o mais lento dos seis
medidos. A tela dedicada fica **depois** da medição, e só se a medição mostrar que
a diferença importa.

**Precondição verificada antes de recomendar:** o catálogo **não tem** nenhuma
família em duas quantizações (`Q4_0` 11, `Q4_K_M` 12, `Q8_0` 1, nenhuma família
repetida), então o par tem que vir de fora dele — do mesmo autor, para que a
única variável seja a quantização.

### feat: `.tflite` é um modelo do app — descoberto, listado e com console

O runtime LiteRT da versão anterior servia `.tflite` **pela rede** e não tinha
nada na interface: o arquivo não era descoberto, não tinha card, não tinha botão
e não podia ser importado. Quem usasse a API HTTP conseguia; quem abrisse o app,
não. A tela de Modelos é o caminho do produto, e o recurso não existia nele.

- **`.tflite` entra na descoberta** (`download_native.dart`) e passa nos guardas
  de importação, em Dart e em Kotlin. Sem isso o arquivo não entrava em
  `downloadedFiles`: sem tamanho, sem card, sem botão, e sem como ser apagado
  pela interface.
- **`AiModel.runtimeTflite`** é um quarto runtime, e não uma variante de
  `runtimeLiteRt`. `litertlm-android` e o interpretador de tensores só dividem um
  nome no repositório do Google: um recebe prompt e devolve tokens, o outro recebe
  tensores nomeados. `runtimeFromFilename` **não tinha** o ramo `.tflite`, então um
  `.tflite` caía em `runtimeLlama` — e `isLlamaModel` afirma
  `runtime == runtimeLlama || filename endsWith .gguf`, ou seja: um classificador
  de 1 MB era arquivado como GGUF e o card oferecia *Load* para um engine que
  rejeita os magic bytes.
- **Seção própria** (`TFLite` / `Custom TFLite Models`) e badge `TFLITE`, porque
  os dois runtimes não têm nada em comum além do nome no repositório do Google.
- **`LitertHeadConsole`**, que passa pelo servidor HTTP como o console de
  encoders, pelo mesmo motivo: o que vale testar num telefone é a superfície de
  API, e um console que fosse direto ao plugin passaria com o endpoint quebrado.
  Ele mostra o que o arquivo diz de si mesmo, pede o acelerador, e roda o
  `/v1/classify` — o caminho que um cliente de verdade usa.

Medido no A72, com `laya_en_act_head_fp32.tflite`, **159 ms** do clique ao
logit: `logits [0.2563, -0.2082]`, `top_index 0`, `features_input "pooled_cls"`,
`auxiliary_used ["feats"]`.

### fix: o console de encoders não mandava a chave da API — e nenhum teste pegava

`/v1/**` está atrás de `_isAuthorized` desde o trabalho da chave, e **nenhum
cliente dentro do app mandava cabeçalho `Authorization`**. `useApiKey` foi
lançado com `false`, então nada quebrou até alguém ligar a chave — momento em que
o probe do console de encoders lia "servidor desligado" contra um servidor no ar,
e o botão de *run* morria sem nada na tela dizendo por quê.

`localApiHeaders(useApiKey:, apiKey:)` fica em `server_auth.dart`: pura, com os
dois valores como argumento, e devolvendo um mapa **vazio** quando a chave está
desligada — para o chamador poder fazer splat sem condicional. Três casos que
importam: chave desligada não manda nada (um cabeçalho aí seria inofensivo mas
errado, e desligar a feature teria que significar também "sem cabeçalho"); chave
ligada e vazia não manda nada, porque o servidor trata chave vazia como "não
exigir chave" e `Bearer ` seria um cabeçalho malformado; e a chave é aparada,
porque uma chave colada traz newline.

Os dois consoles vigiam `useApiKey` e `apiKey` além de `isRunning`. Só `isRunning`
não basta: **ligar a chave deixa toda chamada sem autenticação em 401 sem nenhuma
outra observável mudar**, então um console que vigia só `isRunning` fica com a
última resposta que recebeu.

### Os três defeitos que só o aparelho mostrou, e o padrão deles

**Um `Switch` que o `uiautomator` diz estar em toda a linha e está em 169 px.**
O dump de acessibilidade do switch do servidor tem `bounds [45,266][1035,542]` —
a linha inteira — e `class android.widget.Switch`. Tocar no centro da linha não
faz nada, e `enabled=true clickable=true`, e `startServer` nunca é chamado. O
Flutter funde a semântica da linha; o alvo de toque real do `Switch` tem ~169 px
na ponta direita. **O dump mente sobre onde o toque precisa cair**, e ele mente de
um jeito que parece "o controle está quebrado".

**`ChoiceChip` e `TextField` sem `Material`, na mesma tela, no mesmo build.** O
console é aberto com `Get.to`, que põe a tela sob `GetMaterialApp` sem nada no
meio — e é o `Scaffold` que normalmente fornece o `Material`. Os dois widgets
chamam `debugCheckHasMaterial` em si mesmos, então cada um lançava do próprio
`build`. O primeiro apareceu no log (`ChoiceChip.build` →
`debugCheckHasMaterial`); o segundo só apareceu num screenshot, como uma caixa
vermelha no lugar do campo de entrada. **A correção certa é um `Material` na
raiz, não um por painel** — e ela remove a regra de ter que auditar cada painel
novo. O `Material` por painel que eu coloquei primeiro foi removido: dois
mecanismos para uma regra é um mecanismo a mais.

**`POST` numa rota que só aceita `GET`, engolido por um `catch` mudo.**
`/v1/litert/status` é `GET`; o console o chamava por um `_post`. O catch era
`on Object {}` — sem nada — e o resultado foi um console que dizia "not
screened yet" e "device reports: (not read yet)" **para sempre**, com o probe
dizendo que o servidor estava de pé. Ele estava. O helper passou a receber o
**método como parâmetro**, e a falha do status passou a aparecer em uma linha no
painel. E o `screen` foi desacoplado do `status`: eram duas perguntas, e uma
falha na segunda estava apagando a primeira.

O padrão é o de sempre: **um erro que se apresenta como outro.** O sintoma
apontou para "o servidor não subiu", para "a tela está com defeito", e para "o
aparelho ainda não carregou o modelo".

### O teste que passava com o defeito vivo

O teste de layout do console montava a tela dentro de um `Scaffold` — que
fornece `Material`. Ele passou **contra os dois bugs acima**, no mesmo aparelho em
que eles estavam quebrados. Agora o teste monta a tela como ela é mostrada, sem
`Scaffold`, e a prova de que ele é capaz de falhar está no próprio arquivo:
removendo o `Material` da raiz, seis exceções; com ele, oito de oito.

E uma armadilha do harness já paga em `material_scaffold_test.dart`, agora
documentada nos dois arquivos: `takeException()` devolve **uma** exceção por
chamada. Um teste que constrói dois widgets ofensivos deixa a segunda na fila, e
ela aparece no teste **seguinte** como "Multiple exceptions were detected",
acusando o teste errado por um assert disparado no certo.

### feat: runtime LiteRT 2.2.0 para `.tflite`, e `/v1/classify` servindo cabeças

`local_plugins/litert_flutter/` traz o LiteRT 2.2.0 (o TFLite renomeado) como
plugin **separado** de `flutter_litert_lm`: são dois runtimes que só dividem o
nome no repositório do Google — um é prompt→tokens, o outro é um interpretador de
tensores. 2.2.0 e não 1.4.2 porque `CompiledModel`/`GpuOptions` só existem em
`litert-api` a partir daí, e porque é a versão que o card da Laya nomeia.
**9,28 MB** de `.so` arm64, contra 222,8 MB de nativas no APK.

A API liga tensores **por nome** e não tem como listar os nomes, então o host lê
o FlatBuffer: `/v1/litert/screen` (`litert_model.dart`, 23 testes, um deles
contra o act head real da Laya). Não é conveniência — o act head guarda `feats`
antes de `pooled_cls`, ao contrário do `HOST_CONTRACT.md`.

`POST /v1/litert/screen|load|run` e `GET /v1/litert/status` expõem o runtime.
`/v1/classify` ganhou um terceiro caminho, despacho pela extensão do arquivo.

**Medido no A72 com `laya_en_act_head_fp32.tflite`** (1,0 MB, SHA256 conferido
contra o SHA256SUMS do repo):

| | compila | run | logit 0 | logit 1 |
|---|---|---|---|---|
| CPU (XNNPACK) | 6 ms | 0–2 ms | +0,284356 | −0,209888 |
| GPU (OpenCL) | 273 ms | 0 ms | +0,284356 | −0,209888 |

Diferença máxima entre backends **2,98e-08** (float32), reprodutibilidade entre
runs 0, e `/v1/classify` dá **exatamente** o que `/v1/litert/run` dá.

**`executed_accelerator` é `null`, e a resposta diz por quê.** `CompiledModel` não
expõe o acelerador que usou. A resposta traz `available` e `requested`; inventar
o "real" seria mentir. No logcat: NPU ausente, `libLiteRtClGlAccelerator.so`
carregado, XNNPACK registrado; `getAvailableAccelerators()` devolve
`["GPU", "CPU"]`.

**A regra de qual input é o vetor de features mudou por causa do aparelho.** Era
"o primeiro"; o act head quebra isso, porque `feats [1,4]` vem antes de
`pooled_cls [1,1024]`. O default passou a ser **o maior input**, com
`features_input` como override, e a resposta sempre nomeia qual foi usado.
Auxiliares nunca são preenchidos com zeros — um logit sobre features inventadas
volta com um rótulo confiante.

**Três bugs meus, e o padrão deles:** o nome do método não batia (`load` vs
`loadModel`), que o Flutter reporta como `MissingPluginException` e aponta para o
registro do plugin; a resposta vinha da thread errada; e `every` numa lista vazia
é `true`, então uma assinatura sem entradas passava como ligável. Os três se
apresentam como outra coisa, e nenhum é óbvio no código.


### O LiteRT-LM foi medido nos dois backends, e a GPU é mais rápida

A pergunta estava aberta desde o começo desta linha: *"acredito que GPU seja
melhor, mas vai saber"*. A resposta medida, A/B virando o toggle de Settings, no
mesmo build:

| LiteRT Qwen3 0.6B | TTFT | decode |
|---|---|---|
| `cpu_safe` → `backend=cpu` | 4,58 s | **3,0** tok/s |
| `auto_fast` → `backend=gpu` | 2,94 s | **3,8** tok/s |

A GPU ganha por **27%**, e as quatro amostras de cada lado são idênticas
(`3.0 3.0 3.0 3.0` e `3.8 3.8 3.8 3.8`) — a GPU não passa pelo rampa do governor
que a CPU sofre.

**Isto corrige o `AGENTS.md`, que dizia "a GPU é 8× mais lenta que a CPU aqui".**
Os 3,8 tok/s do LiteRT-na-GPU foram comparados com os 31–49 dos GGUFs-na-CPU, e
isso compara **dois runtimes**, não dois backends. Isolando:

```
GGUF 0.35B na CPU ..............  31,9 tok/s   medido
GGUF 0.60B esperado ............  18,6 tok/s   extrapolado
LiteRT 0.60B na CPU ............   3,0 tok/s   medido
```

**O LiteRT-LM na CPU é 6,2× mais lento que o llama.cpp na CPU** para trabalho
comparável. A GPU não é a causa: não passa nem do teto de ineficiência do engine.

**Por quê, e é estrutural:** todo o pinning de threads vive em
`jni_wrapper.cpp` — `buildCpuSet`, `ggml_threadpool_new`, `llama_attach_threadpool`.
O caminho LiteRT passa por `liblitert-lm.so` e não alcança nenhum deles, então o
backend de CPU do LiteRT roda sem pin, e o pinning sozinho vale 2,8× neste
aparelho. O resto são kernels: ggml com i8mm/dotprod contra o conjunto próprio do
LiteRT-LM.

**O default de `planLiteRtTier` continua certo** — por 27%, e por acaso, porque
nunca mediu. E a resposta honesta ao "micro-benchmark do LiteRT" muda de forma: o
problema não é escolher backend, é o engine ser 6× mais lento. Um benchmark que
mede os dois backends escolheria GPU e continuaria 6× atrás de um GGUF do mesmo
tamanho.

**Alcance:** um modelo, um aparelho. Os outros 4 `litert` do catálogo não foram
medidos e nenhum é um 0.6B.

### `input tap` funciona no A72 — a checagem é que estava errada

O guia de pilotagem registra oito tentativas com `tap.sh` falhando, e a nota
atribui o toque a um defeito do painel. Não é. `input tap` funciona; o que não
funcionava era a **checagem**: `tap.sh` confirmava `mWakefulness=Awake`, e
`dumpsys power` continua dizendo `Awake` com o painel morto. A checagem real é o
**tamanho do screenshot** — 15 KB é um PNG todo preto, 190 KB é conteúdo.

Com wake, `wm dismiss-keyguard` e a checagem do tamanho antes de cada toque, os
toques e os swipes responderam de primeira. `/tmp/opencode/setmode.py` faz a
navegação e confere cada passo por `uiautomator`, incluindo o detalhe de que a tela
do Server é full-screen e não tem a barra de abas — buscar a aba 4 nela falha e o
script acaba rolando a página errada sem nunca sair.


### fix: o KV cache nunca era limpo entre gerações

O comentário no `jni_wrapper.cpp` dizia "Clear memory from previous generation to
start fresh" e não havia clear: o único `llama_memory_clear` do arquivo estava na
função de encoder. `g_n_past` crescia ~183 por geração e nunca voltava, e o prompt
seguinte era decodificado por cima do anterior.

Seis pedidos consecutivos para `/v1/chat/completions`, prompt de 165 tokens:

```
Sampling token 1, g_n_past=165    prefill 306 tok/s     1,0 s
Sampling token 1, g_n_past=348    prefill  47,9 tok/s  55,1 s
Sampling token 1, g_n_past=531    prefill 275 tok/s     1,1 s
Sampling token 1, g_n_past=714    prefill  44,4 tok/s  55,4 s
```

**Respostas erradas, que é o defeito que importa.** As posições do prompt começam
em `g_n_past` e não em 0, então os tokens 0-182 do contexto consultado eram o
pedido anterior. As seis respostas saíram byte-idênticas com prompts diferentes.
Depois do conserto, mar, montanha e cidade dão respostas diferentes.

**O carry-over nunca foi cache.** Os dois chamadores fazem prefill do prompt inteiro
a cada turno — o chat do app reenvia o histórico completo, e o servidor manda um
pedido só — então nenhum token era pulado por já estar no cache. A janela
deslizante de `make_room_for` fica, porque dentro de uma geração um prompt longo
mais 512 tokens ainda estouraria `n_ctx`.

Só apareceu com a medição do catálogo porque ela usava um prompt só: com pedidos
idênticos, uma resposta byte-idêntica parece o modelo funcionando.

### O `onDone` não se perdia — a hipótese que motivou o timeout de 60 s estava errada

A seção da superfície de decisão dizia que o `onDone` podia ser perdido e que
isso derrubava a API. Contabilidade no log de seis gerações seguidas, no A72:

```
Generation loop finished     5
Stream onDone                5
Idle timeout                 0
Stream error                 0
```

`onDone` é chamado em `LlamaFlutterAndroidPlugin.kt:334` e `:459`, e `isStopping` é
resetado no início de cada `generate` (linhas 299 e 403). O que produzia 51 s por
request era o KV cache acima. **O timeout de 60 s fica**, porque é correto por si
— uma decisão que não veio em um minuto não é uma decisão, e o `.timeout()`
garante o `finally` que libera o `_busy` — mas a razão registrada estava errada e
foi corrigida.


### feat: `/v1/classify` aceita decision models, com a resposta honesta

Tev1-0.8B e Bespoke-Nimble são classificadores fine-tuned para emitirem **uma
letra**. O caminho antigo de `/v1/classify` exige `cls.output.weight` — a cabeça
de encoder — que um modelo generativo não tem, então ele respondia "no model
loaded" para um modelo que estava carregado e responderia bem.

O despacho é por um **fato sobre o arquivo**, não por configuração: com a
cabeça, o caminho antigo; sem ela, o generativo. `decision_model.dart` é puro e
tem 28 testes.

Medido no A72 com Tev1-0.8B: **5 de 5** decisões corretas (500 no checkout →
bug, cobrança dupla → billing, senha esquecida → account, preço → billing,
crash na câmera → bug), 2,0–2,2 s quando o contexto está livre.

**`relevance_score` é `null`, e `scores` mapeia tudo para `null`.** Um
classificador com cabeça produz um logit por classe; um decision model devolve
uma letra. As probabilidades do Nimble vêm da camada de serviço dele, não dos
pesos — trazê-las seria fabricar um número. A resposta traz `why_no_scores`.

**O orçamento é 8 tokens.** Uma letra mais o `<think>` vazio são ~5. Com 24, um
modelo que escreveu prosa queimava o orçamento inteiro, e no A72 isso são 8–9 s por
token com o núcleo no piso: 24 tokens seriam três minutos de um request que nunca
seria uma decisão.

**A decisão tem prazo de 60 s.** O loop nativo pode terminar limpo e o stream do
Dart não entregar `onDone`; aí `generate()` não retorna, o `finally` não roda e
`_busy` fica verdadeiro — todo request posterior responde 429 pelo resto da vida
do app. Medido. O timeout devolve 504 e libera o `_busy`. **A causa raiz não foi
corrigida**: o `onDone` perdido é bug do caminho de conclusão do Dart e afeta
`/v1/chat/completions` do mesmo jeito.

**Prosa é falha, não fallback.** O parser devolve null e a resposta sai 422 com
o texto bruto. Pegar a primeira letra de uma frase, ou devolver a primeira opção
como padrão, é o que faz um decision model virar uma moeda que parece estável em
toda métrica. O `<think>` é removido antes, porque uma letra dentro da
deliberação do modelo não é a resposta dele.

### O catálogo medido no A72

Melhor de 3, pedidos consecutivos sem pausa, via API com streaming.

| modelo | backend | layers | TTFT | decode |
|---|---|---|---|---|
| LFM2.5 230M (Q4_0) | cpu | 0 | 0,18 s | **49,3** |
| LFM2.5 350M (Q4_0) | cpu | 0 | 0,34 s | **31,9** |
| Gemma 3 270M (QAT Q4_0) | cpu | 0 | 0,16 s | **31,1** |
| Tev1 0.8B (Q8_0) | cpu | 0 | 1,10 s | **11,0** |
| SmolLM2 135M (Q4_K_M) | cpu | 0 | 8,24 s | **5,1** |
| Qwen 3 0.6B (LiteRT-LM) | **gpu** | 1 | 3,00 s | **3,8** |

- **A ordem por tamanho é falsa.** O SmolLM2 135M é o mais lento de todos, com
  8,24 s de primeiro token, apesar do menor arquivo. "Escolha o menor modelo" é
  advice errado neste aparelho. É o único `Q4_K_M` da lista e a hipótese é a
  quantização — **não testada**.
- **A GPU é 8× mais lenta que a CPU aqui.** O único modelo que foi para a GPU é
  o LiteRT: 3,8 tok/s contra 31–49. É a resposta medida à pergunta que estava
  aberta — `planLiteRtTier` sempre prefere GPU e nunca mediu.
- **As amostras da CPU variam 150×; as da GPU não.** 49,3 / 0,3 / 44,7 para o
  230M; 3,8 quatro vezes para o LiteRT. `schedutil` no Sustained load.
- **Todos os GGUFs foram para a CPU com `layers=0`, com a GPU presente** — a
  regra de tamanho da 0.5.1 se sustenta até 774 MB sem exceção.


### fix: `stream: true` não fazia streaming

O handler escrevia um chunk por token, via `onToken`, e o cliente recebia
**uma** chunk e o `[DONE]`, ambos no mesmo instante — 25,86 s de espera e depois
a resposta inteira. A causa é o buffer do `HttpResponse` do Dart: `write()`
enfileira e o que vai para o socket sai no `close()`. `bufferOutput` nunca era
mexido em lugar nenhum do arquivo. `response.bufferOutput = false` antes do
primeiro `write` resolve; medido depois do conserto, os tokens chegam
individualmente (8,00 / 8,12 / 8,41 / 8,62 … s).

Importa por dois motivos: um cliente que usa streaming por latência percebida
não recebia nada mais cedo, e não havia como medir TTFT pelo stream.

### fix: o watchdog de 5 s entre tokens cortava a resposta em uma palavra

O menor modelo do catálogo, **SmolLM2 135M**, respondia com exatamente uma
palavra, sempre: `Sampled token 1` e 4,6 s depois `Idle timeout — 1 tokens`.

Não era o modelo nem o engine. Os dois núcleos grandes estavam no piso —
`652.800 Hz` de `2.323.200`, `schedutil`, `loadavg 0.00` — e no piso o segundo
token leva mais de 5 s.

**5 s parece generoso para "por token", e é.** O que o watchdog tenta distinguir
é *engine travado* de *engine lento*: um travado não produz token **nunca**, um
lento produz um a cada 8 s. Cinco segundos não sabe dizer as duas coisas, e
escolher o lado errado corta a resposta do usuário. Subiu para **30 s** — um
watchdog existe para pegar travamento, não para impor velocidade, e quem impõe
velocidade é o `prefillBudget` de 60 s, que conta os tokens como um todo.

Depois do conserto, mesmo aparelho e mesmas condições: **25 tokens**.

### O tok/s que sai daqui depende do clock, e isso muda o protocolo

| | A72, núcleo no piso | A72, núcleo rimado |
|---|---|---|
| SmolLM2 135M, decode | **4,8–5,0 tok/s** | — |
| TTFT | 8 s | — |
| LFM2.5 230M (sessão quente) | — | **18,0 tok/s** |

Fator de quase 4× no mesmo aparelho e no mesmo modelo, sem mudança no código —
só o clock. **Medir com pausas entre pedidos mede o governor, não o modelo**: o
protocolo é pedidos consecutivos sem pausa e melhor de N, que é a mesma
conclusão que o benchmark de CPU já carrega.


### feat: o servidor sobe sem modelo, e a gestão de modelo funciona por HTTP

O toggle recusava subir sem modelo ("Load a local GGUF or LiteRT-LM model
first"). Era circular depois que a API ganhou gestão de modelos: **o servidor é
como se carrega um modelo pela rede**, então exigir um modelo para subi-lo
impedia a feature de se inicializar sozinha — e trocar de modelo exigia ir até o
telefone.

O que substitui o portão são recusas que já existiam e são melhores que uma
porta fechada: os cinco endpoints que precisam de modelo respondem 400 com uma
frase, e `capabilities` não promete nada quando não há modelo. A recusa de
geração agora **nomeia o caminho por onde sair por HTTP**
(`POST /v1/models/load` com um filename de `GET /v1/models/local`), porque um
cliente que não sabe que existe um toggle num telefone que não está na mão
recebe a instrução errada.

`load` entre **runtimes diferentes** é recusado com `409`. GGUF e LiteRT-LM são
duas bibliotecas nativas diferentes e a sessão se amarra a uma delas na
primeira carga. O primeiro sintoma era pior do que a recusa: o endpoint
respondia **`202 accepted`** para `Qwen3-0.6B.litertlm` e 24 s depois o GGUF
seguia carregado e o LiteRT nunca carregou — um 202 que não é seguido da coisa
que promete é pior que uma recusa, porque o cliente acredita que vai ter
aquilo. Agora o 409 diz qual runtime seria preciso, qual a sessão tem, e que o
caminho é reiniciar e repetir. E o modelo carregado não é tocado.

### Verificado no A72, partida a frio, 19 verificações e zero falhas

| | |
|---|---|
| servidor sem modelo | sobe, `loaded: null` |
| os 5 endpoints que precisam de modelo | 400 cada um, com o caminho |
| `capabilities` sem modelo | `{}` |
| `load` de GGUF pela API | 202, carrega em 3 s, `backend=cpu gpu_layers=0` |
| `load` de LiteRT pela API | 202, carrega em 6 s, **`backend=gpu`** |
| `unload` | 409, servidor de pé |
| `load` entre runtimes | 409, modelo carregado intacto |
| chave | 401 sem / 401 errada / 200 certa / 200 com `bearer` minúsculo |

O `backend=gpu` do LiteRT contra o `backend=cpu` do GGUF de 142 MB é a
assimetria entre `planLiteRtTier` (sempre prefere GPU) e `planAcceleration`
(que mantém GGUF pequeno na CPU), agora reproduzível em dois comandos.


### feat: a API local controla os modelos, e a chave passa a ser exigida

`GET /v1/models/local`, `POST /v1/models/{download,load,unload}` — listar,
baixar, carregar e descarregar por HTTP, com chave.

**Por que isso é feature e não ferramenta.** O `AGENTS.md` exige que um
modelo só entre no catálogo curado *depois de medido*, e medir significa baixar
nove modelos, carregar cada um e consultar cada um — cada passo com um diálogo
que só uma pessoa responde. A campanha inteira é isso repetido nove vezes.

`/v1/models` segue **exatamente** o contrato OpenAI, só o modelo carregado: um
cliente que encontrasse as 62 entradas do catálogo ali tentaria usá-las todas e
tomaria 404 na primeira geração.

**A chave de API é gerada e exigida por padrão.** O servidor faz bind em
`anyIPv4` — todas as interfaces, não só loopback — e sempre esteve alcançável
pela rede local. Até aqui isso era menor do que parece, porque o pior que um
chamador sem chave podia fazer era gastar CPU pedindo tokens. Os endpoints de
gestão de modelo mudam a resposta: `download` escreve gigabytes no aparelho,
`load` e `unload` mudam o que todo outro cliente da rede está usando, e
`local` lista o que está no telefone. Um servidor aberto num Wi-Fi de café foi
de "gasta bateria" para "usa o celular como armazenamento e muda o estado dele",
e um default de `off` deixa de ser defensável.

- **32 caracteres de um alfabeto de 32** (`a-z2-9`, sem `0`/`O`/`1`/`l`/`I`) =
  160 bits. O alfabeto existe porque a chave vai parar digitada num header
  `curl` em outra máquina, e uma chave errada volta como `401` sem dizer qual
  caractere estava errado.
- **Comparação em tempo constante**, e o esquema do header em qualquer caixa,
  porque `bearer` é um nome registrado e o token do scheme não é.
- **Um install que nunca teve chave ganha uma e passa a exigir.** Um que já
  tinha e estava **desligado de propósito continua desligado** — reativar por
  cima seria o app sobrescrevendo uma decisão de segurança tomada conscientemente, e depois não há como distinguir isso de um bug.
- **Desligar a chave agora pergunta**, com os endpoints nomeados — baixar
  gigabytes, descarregar o modelo sob os pés de qualquer outro cliente, listar o
  que está no aparelho, e usar o telefone para inferência. O botão seguro é a
  ação padrão do diálogo.
- A regra de migração é pura e tem 20 testes, porque uma regra de migração
  errada abre o servidor em silêncio e um teste de aparelho não pega isso.

**`load` exige `accept_risk`.** `loadModel` mostra um diálogo de memória;
ninguém o responde por HTTP, e deixar `loadModel` correr sem decisão **libera
o modelo antigo e não carrega nada** — foi o que a primeira versão fez, com 202
e um aparelho sem modelo. O flag pula **só os diálogos**; arquivo incompleto,
safetensors inválido, LiteRT inválido e memória insuficiente continuam recusando.

**`unload` é recusado, de propósito.** `unloadModel` derruba o servidor junto,
porque sem isso os endpoints respondem 200 sem nada atrás. Responder antes de
parar não salva: o socket fecha antes do flush. Carregar **mantém** o servidor
no ar, então é `load` que troca modelo.

**A resposta vai antes da operação.** `unawaited(loadModel(...))` seguido de
escrever o 202 prende o isolate do Dart na chamada JNI antes de o socket ter
algo para enviar. Medido: `000` em toda requisição que disparava operação real,
enquanto o 409 — que responde antes de fazer qualquer coisa — funcionava.


### feat: memória do aparelho na tela de Modelos, ao vivo

Um card na tela de Modelos mostra quanto o telefone pode entregar agora, e
quantos pesos estão caindo em disco enquanto isso. Fica ali, e não em
Configurações, porque é a tela onde um modelo é baixado e onde um modelo é
carregado — os dois momentos em que a memória decide o resultado. A escada de
aceleração pergunta ao probe quantas camadas cabem, e um aparelho 400 MB mais
curto responde diferente de um que não está.

**`MemAvailable`, não `MemFree`, e no aparelho de teste isso muda a resposta:**

| A72, `/proc/meminfo` real | lido como "livre" |
|---|---|
| `MemFree: 641.596 kB` | **12,8%** → "modelo grande vai falhar" |
| `MemAvailable: 2.430.788 kB` | **48,5%** → folgado |

`MemFree` exclui cache reclamável, então num telefone ocioso lê baixo com
memória de sobra. Usá-lo faria o card avisar que um modelo não carrega num
aparelho com 2,4 GB disponíveis — aviso falso, que é pior do que nenhum,
porque o usuário troca de modelo à toa.

A barra é `MemTotal - MemAvailable`, que é o que o low-memory killer do próprio
Android raciocina, e o limiar de 15% é onde um modelo de 1-2 GB deixa de caber
e a carga **falha** em vez de ficar lenta. Um aviso em 15% ainda dá tempo de
escolher um modelo menor, que é a única remédio nesse ponto.

O poll liga e desliga com o que está acontecendo, não fica rodando. E ele mora
no `State` do widget, não no `build`: iniciar timer de dentro de `build` é o
mesmo erro do `setState() during build` que o `ChatController.onInit` causava,
só que falha mais quieto — vaza um timer por rebuild em vez de lançar.

A aritmética é pura e testada (17 testes) pelo mesmo motivo de
`acceleration.dart` ser pura: as três afirmações que podem estar erradas em
silêncio — legível, apertado, qual fração — ficam fora do alcance de um
aparelho. iOS e web não mostram o card, porque não têm RAM física para relatar.

### fix: as ações do card de benchmark estouravam a tela inteira

Três `TextButton` lado a lado numa `Row` sem `Expanded` nem `Wrap`: "Hide the
local model list", "Show it anyway" e "Keep models anyway". A combinação mais
longa são três frases numa linha sem nada limitando nenhuma delas, num card no
meio da lista de modelos — então o overflow horizontal **leva o catálogo
inteiro**, o mesmo formato de dois outros casos já registrados.

`Wrap` é a correção certa e não só a que não estoura: são alternativas, e
empilhá-las diz isso de um jeito que três botões deitados não dizem.

O teste fixa o caso a 360 dp com texto a 2×, mais estreito que os ~393 dp do
A72, e o último dos cinco **prova que o harness é hostil**: ele afirma que a
`Row` estoura. Se ele um dia passar, as larguras deixaram de ser hostis e os
outros três deixaram de provar nada.


## [0.5.1+2008] - 2026-09-30

Patch. A 0.5.0 entregou o pinning e o benchmark; a 0.5.1 conserta a coisa que a
0.5.0 tornou visível — com o benchmark funcionando, deu para ver que ele e a
carga do modelo discordavam.

### fix: a escada de aceleração não via o tamanho do modelo

No **Edge 60** (Dimensity 7300, Mali-G615) o benchmark dava **57 tok/s** e a
carga do mesmo modelo dava **10-14 tok/s com 25 s de primeiro token**. Os dois
números eram verdadeiros: o `auto_fast` colocou um modelo de 230M na GPU, e na
GPU de um telefone um 230M é mais lento que a CPU do mesmo telefone.

`planAcceleration` recebia `mode`, `vulkanSupported`, `recommendedGpuLayers` e
`npuAvailable` — quatro respostas de **capacidade** e nenhuma palavra sobre o que
ia ser executado. Capacidade não é adequação. Uma Mali-G615 com memória sobrando
responde "sim" a um 230M, corretamente, e a resposta é 4x mais lenta que a CPU
que ela acabou de recusar.

| modelo | CPU | GPU |
|---|---|---|
| LFM2.5 230M Q4_0 (149 MB) | **57 tok/s** | 10–14 tok/s |
| 1B Q4_0 (~700 MB) | **21,2 tok/s** | 3,4 tok/s |

Agora o `auto_fast` mantém um GGUF pequeno na CPU, e o motivo nomeia a medição:

> CPU — 142 MB model, and the GPU is slower than the CPU at this size
> (measured twice on the Edge 60: 57 vs 10-14 tok/s at 230M, 21,2 vs 3,4 at 1B)

Três fronteiras, todas em `test/acceleration_test.dart`:

- **Acima da faixa, nada muda.** O corte é 1280 MB porque é o topo do que foi
  medido. Nada aqui mede a GPU de um telefone acima de ~2B, e um modelo desse
  tamanho precisa do offload para carregar.
- **`gpu_fast` continua sobrepondo.** Quem toca em "GPU Fast" foi informado dos
  números e pediu a GPU; sobrepô-lo é fazer do app a coisa que ele tenta não ser.
- **Tamanho desconhecido não é tamanho pequeno.** 0 significa "não lido", e a
  escada volta ao comportamento anterior em vez de inventar um tamanho.

Verificado no A72, que tem Adreno 618 e o mesmo problema: o probe recomendou
16 camadas e a carga foi para a CPU.

### fix: a máscara de afinidade era lida com um int que desloca, inventando núcleos

`buildComputeThreadpool` e `buildCpuSet` percorriam um `cpu_set_t` (1024 bits)
testando `mask & (1 << cpu)`, com `mask` chegando como `jint` de 32 bits. Para
qualquer `cpu >= 32` o deslocamento é indefinido e o hardware guarda os bits
baixos, então `1 << 38` é `1 << 6` na prática. Uma máscara de 0xC0 — dois
núcleos, cpu6 e cpu7 do A72 — reportava dezoito membros:

> Compute threadpool: 2 thread(s), strict_cpu=1, worker 0..1 pinned to cpu
> 6,7,38,39,70,71,102,103,134,135,166,167,198,199,230,2

O pin em si estava certo, e por sorte e não por correção: o laço sobe, então os
núcleos reais vêm primeiro e o chamador pega os `n_threads` primeiros antes de
qualquer fantasma. **Alargar o deslocamento para 64 bits piorou em vez de
consertar** — `1ULL << 70` também é indefinido, porque a conta excede a
largura, e o período dos fantasmas saiu de 32 para 64 e ficou. Só limitar o
laço pela largura da máscara resolve, e nenhuma escolha de tipo resolveria.

Duas coisas liam os fantasmas, e as duas estavam vivas:

- `cores.size()` os contava, então a guarda "esta máscara nomeia menos núcleos
  que threads, o que serializaria" **nunca podia disparar**. Parecia uma
  verificação funcionando.
- `buildCpuSet` fazia CPU_SET de dezoito núcleos, que é permissão para *rodar
  em* dezoito — o oposto de pin. Esse é o caminho que `nativeSetComputeAffinity`
  usa, e ele hoje não é chamado, então ainda não custou nada. É a função que
  custaria.

Os dois laços agora param em 64 e `mask` é `int64_t`, igual ao lado Dart. O
`jint` de 32 bits no canal é seguro porque `cpu_topology_test.dart` já garante
máscara < `1 << 16`.

Agora a linha diz `worker 0..1 pinned to cpu 6,7`, ao lado de
`cpumask slots set: 6,7` — os dois concordam, que é a única razão para imprimir
os dois.

### Sobre o micro-benchmark lembrado

**Nunca houve um micro-benchmark escolhendo o acelerador.** O que existia era
`core.plan(...)`, no núcleo Rust — um *planejador*, não uma medição — e o
`result.benchmark` era o self-check de boot do próprio núcleo, que decidia se
ele podia ser usado. Os dois saíram na 0.3.5, quando o núcleo deixou o APK. A
regra sempre foi uma regra; estava em Rust, e depois passou a ser este mesmo
corpo em Dart. O que faltava nunca foi a medição. Era o modelo.


## [0.5.0+2007] - 2026-09-29

Minor, e a frase que a regra do repo exige saiu verdadeira: **antes disto o app
mediava a própria máquina com o relógio no chão, e o benchmark decidia o que
mostrar com um número errado.**

### Medido no Galaxy A72 (SM-A725M, Snapdragon 720G, dois A76)

| | tok/s | 1º token | prefill |
|---|---|---|---|
| sem pin, 2 threads soltos | 6,5 | 1,72 s | — |
| **pool pinado, 2 threads** | **18,0** | 1,92 s | — |
| benchmark, 1 thread | 11,6 | 1,1 s | 123 ms |
| **benchmark, 2 threads (caminho oficial)** | **32,0** | **0,1 s** | 127 ms |

### perf(cpu): threads de cálculo presos nos núcleos grandes, automaticamente

O ganho de 6,5 para 18,0 tok/s não veio do clock — veio da **utilização**.
`schedutil` decide frequência pela utilização *por núcleo*; dois threads soltos
em oito núcleos deixavam cada A76 lendo quase zero, e o cluster passava a
geração inteira a 652.800 Hz de um teto de 2.323.200. Presos, cada A76 lê ~50%
e o clock acompanha. `time_in_state` do cpu6: **3.811.046 ticks no piso contra
39.018 no teto** — o clock quase nunca saía do piso, preso ou não.

A rota é `llama_attach_threadpool(ctx, pool, pool_batch)`, API pública do
`llama.h` vendorizado (linha 491). **Nenhum arquivo vendorizado foi alterado.**

Três coisas contr intuitivas, todas comentadas no código porque qualquer uma
delas faz o pinning "não funcionar" de novo:

1. `cpumask` é indexado por **WORKER**, não por núcleo. Com `strict_cpu = 1`,
   `ggml_thread_cpumask_next` dá ao worker *j* o *j*-ésimo bit ligado — um
   núcleo por worker. A primeira versão prendeu os dois workers no cpu6.
2. `ggml_threadpool_new`/`_free` não linkam (moram em
   `libggml-cpu-android_armv8.*.so`, carregada por `dlopen`); vêm do registro
   CPU por `ggml_backend_reg_get_proc_address`.
3. "Núcleo grande" é **lido**, não assumido: `bigCoreMask` pega os que empatam no
   maior `cpuinfo_max_freq` e devolve 0 quando menos da metade dos núcleos é
   legível — e 0 significa "não prender".

Escopo deliberado: só na contagem **automática** de threads (uma contagem
digitada em Settings é override do usuário), e só no caminho GGUF.

### feat(benchmark): o benchmark media o telefone errado, três vezes seguidas

**A primeira run depois de abrir o app não é a velocidade do aparelho.** Mesmo
processo, mesmo modelo, mesmo build, runs separadas por segundos: **0,2 tok/s e
71,4 s** para o primeiro token, depois **17,4 tok/s e 0,7 s**. É o governor, não
o engine. Um warm-up contado em tokens *não* resolve — medido: 8 tokens de
warm-up deram 0,3 tok/s, porque 8 tokens na taxa fria são 23 s e o rampa é mais
longo que isso. Então as tentativas **são** o warm-up: até três, fica a melhor.
Num processo novo o benchmark agora diz **32,0 tok/s** onde dizia 0,2.

Isso importa mais do que parece porque é o número que decide se o app oferece
esconder o catálogo local — e subestimar custa os modelos do usuário.

**O tempo até o primeiro token era o tempo total usando o rótulo.** `gotFirst`
era um `bool` e `ttft` era `sw.elapsedMilliseconds` lido depois da geração
inteira: uma geração cujo prefill levou 2,8 s era reportada como 71,4 s.

**Tokens eram palavras.** `text.split(RegExp(r'\s+')).length` dividia uma
resposta de 24 tokens por quantas palavras o português usou, sempre a favor.
Agora conta as chamadas de `onToken`, que o engine dispara uma vez por token
contado — a assinatura do engine não mudou. Só isso levou o mesmo aparelho de
17,4 para 32,0 tok/s.

`measureGeneration` é função pura com callback, justamente para a regra ser
testável sem telefone; `cpu_self_test_test.dart` reproduz a forma
frio-depois-quente do A72 com uma engine falsa. **Esses testes falham contra o
comportamento anterior** — verificado, não assumido.

### fix: o benchmark não existia em nenhum aparelho com GGUF

O botão e os dois switches que o controlam estavam no fim de
`_buildLiteRtCard`, que só é construído quando um modelo **LiteRT** está
selecionado. Com GGUF não havia card na tela de Modelos nem tile em Settings:
o benchmark era impossível de rodar. Estão em `DIAGNOSTICS` agora, que também é
onde uma medição de CPU pertence — o benchmark carrega o próprio GGUF de 230M e
não depende do runtime que o app está segurando.

### fix(log): o serviço de log escrevia observáveis durante o build

`setState() or markNeedsBuild() called during build ... ChatView`, como zone
error não tratado, depois do qual o `Obx` fica sujo e a subárvore não volta. O
sintoma visível nunca foi um crash: o toque intendedo para Settings era engolido
e a tela de Logs abria no lugar — o que se lê como bug de navegação.

A stack culpa o **escritor**, não o observador: `ChatController.onInit` roda
dentro de um build (o controller é alcançado por `Get.find` de dentro do build
do `ChatView`) e `refreshEncoderRole` escreve dois observáveis antes do primeiro
`await`.

### Também nesta versão

- **`CpuSelfTestService` segurava um segundo `AppLogService`.** GetX só chama
  `onInit` no que passa por `Get.put`, e o timer de flush nasce no `onInit` —
  então toda linha do benchmark ia para uma `_pending` que ninguém drenava. A
  run completava, o card mostrava o veredito, e `grep 'CPU self-test' app.log
  app.log.1` voltava vazio nos dois arquivos.
- **`main.dart` tinha um `print` de debug dentro do `Obx` raiz.** Rodava a cada
  rebuild do app inteiro — e uma geração reconstrói uma vez por token. 498
  linhas idênticas numa sessão, um quinto do orçamento de 1 MiB do log
  gastos dizendo nada.
- **A sonda de GPU do Stable Diffusion não roda mais no boot.**
  `SdFlutterAndroid.detectGpuVendor()` é EGL, e no A72 isso puxa o driver
  Adreno inteiro para dentro do processo — `libvulkan.so` e tudo — só para
  devolver uma string de duas letras. Agora só roda se o usuário pedir a GPU.
- **`lib/utils/logistic.dart`** — a sigmoid do rerank saiu de dentro do handler
  HTTP para uma função pura com teste. Ela era `private static`, que é o único
  lugar onde uma função numérica não alcança um teste.
- **Porta do servidor 8091**, e o texto de ajuda lê de
  `AppConstants.defaultServerPort` em vez de repetir 8080 na string.
- **`tool/drive.sh`** e **`tool/gguf-screen.py`** — as duas armadilhas que
  custaram mais tempo estão escrito neles: `input tap` não acorda a tela e
  falha em silêncio, e o `taskset` do toybox quer hex cru.

### Não medido

- **Bateria e temperatura** do pinning sustentado.
- **`scaling_min_freq`** do A72 é gravável, mas só o root escreve — é ajuste de
  aparelho de teste, não de app.
- **O benchmark de 2 threads pelo caminho oficial** só foi medido depois do
  conserto do `setState`, porque era esse bug que engolia o toque.


## [0.2.2+1] - 2026-09-15
- **Assinatura**: trocado para novo keystore de release (salvo em android/keystore/mobilelm_release.jks).
  Versões anteriores (0.2.1 e abaixo) usavam a chave de debug padrão do Android.
  ⚠️ **Atenção**: atualizar direto de 0.2.1 para 0.2.2+ requer desinstalar o app antigo devido à mudança de assinatura.
- **Internacionalização**: adicionada estrutura de suporte a múltiplos idiomas (i18n) com arquivos ARB para en e pt_BR.
  Ainda não há traduções completas; a base está pronta para receber AppLocalizations em todo o app.
