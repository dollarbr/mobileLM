# System One e decision models

O que já existe no app, o que a Liquid AI lançou em outubro, o que foi medido de
verdade nos dois aparelhos, e por que uma "porcentagem de certeza" por alternativa
seria uma mentira — mesmo quando parece a coisa mais razoável do mundo.

## O que é um System One

Um modelo que responde a **uma pergunta estruturada com uma classe**, em vez de
gerar texto. Você dá um `state`, uma `question` e um conjunto de opções; ele
devolve a opção. Zero tokens gerados.

O nome vem de quatro que valeram o batismo — **Jev, Laya, Tev1 e Bespoke-Nimble** —
e a classe é **aberta**: "um modelo que responde a uma pergunta estruturada com
uma classe", e o próximo publicado entra nela sem ninguém editar código.

No app isso já é uma superfície inteira, não um plano:

| arquivo | o que é |
|---|---|
| `lib/services/system_one.dart` | 1064 linhas. `SystemOneShape`, modelo de opções/letras, parse de resposta |
| `lib/services/decision_model.dart` | "prompt in, one letter out". Monta o prompt e acha a letra no que o modelo disse |
| `lib/views/system_one_console.dart` | a janela "Test System One" |
| `POST /v1/classify` | três shapes: `.tflite` head, GGUF head, **decision model** |

### Três shapes, decididos por fato do arquivo

```dart
final tflite = isTflite ?? (filename?.toLowerCase().endsWith('.tflite') ?? false);
if (tflite) return SystemOneShape.tfliteHead;
if (hasClassificationHead == null) return SystemOneShape.unknown;
return hasClassificationHead ? SystemOneShape.ggufHead : SystemOneShape.decision;
```

O nome do arquivo **nunca** é consultado — só a extensão e o `cls.output.weight`.
A regra é do 0.4.0 dos encoders: **o papel vem do que o arquivo é, nunca do que
ele se chama**. Já aconteceu de `bge-small-en-v1.5` ser classificado como
classifier porque algo leu o nome.

### O shape `decision` é um LM comum que responde uma letra

Esse é o ponto que decide metade deste documento. O shape `decision` **não** usa
suporte nativo de decision do llama.cpp. Ele monta um prompt, chama
`inference.generate()` pelo caminho normal, e casa a letra por regex no texto
gerado. É por isso que a `libllama.so` instalada tem **zero** strings de
`decision`, `systemone`, `lfm2-d1` ou `noul` — verificado no APK extraído, não
na fonte.

## A família d1 da Liquid AI

Lançada em 07/10/2026, open-weight. **Não existe "d3-3B"** — a família se chama
`d1`, e são dois checkpoints:

| modelo | params | entrada | GGUF |
|---|---|---|---|
| **d1-3B** | 3,1B | texto + imagem | 1,6 GB (Q4_K_M) + 557 MB mmproj |
| **d1-omni-600M** | 587M | texto + imagem **ou** texto + áudio | 389 MB (Q8_0) + 251 MB mmproj |

O `d1-3B` é `Lfm2VlForConditionalGeneration` com `text_config:
Lfm2ForCausalLM` — ou seja, é LFM2.5-VL-3B com uma decision head em cima. **O
app já suporta lfm2.**

### Não existe `LLAMA_ARCH_D1`

Nem arch nova, nem tensor novo. Nos 266 tensores do `d1-3B` não há cabeça de
saída nem decision head:

```
30x  blk.N.attn_{q,k,v,output,norm}    (só 8 camadas têm atenção)
22x  blk.N.shortconv.*                 (o resto é convolução — LFM2 híbrido)
 1x  token_embd.weight                 ← entrada E saída, atadas
```

Com `tie_word_embeddings: true`. Ou seja: **`lfm2-d1` é literalmente um LFM2
comum, lido no último token do prompt com os logits restritos às letras A/B/C.** O
comportamento de decisão vem inteiro do prompt mais essa leitura.

No llama.cpp viram dois tipos distintos, em **caminhos de código diferentes**:

| decision type | como lê | modelo |
|---|---|---|
| `lfm2-d1` | `logits[label]` no último token (estilo openjev) | d1-3B |
| `lfm2-d1-omni` | saída de **embeddings**, marcador por opção (estilo laya) | d1-omni-600M |

O `d1-omni-600M` ainda traz `cls.output.weight` de shape `(1024,)` com bias `(1,)` —
uma cabeça de **uma** classe sobre embeddings. O detector do app veria isso e
rotearia para `ggufHead`, que espera pontuar *todas* as classes de uma vez. **Esse
não entra limpo.** Nenhum dos dois declara `pooling_type`, então `nativeEncode`
recusa os dois por desenho.

### Estado do nosso vendor

O vendor está em `08b1d2aea`. Os PRs do upstream foram mergeados em **07/10 e
08/10**, depois disso. E o patch **não aplica** — verificado numa cópia:

```
erro: falha no patch: conversion/lfm2.py:127
erro: falha no patch: gguf-py/gguf/constants.py:6071
erro: tools/server/server-decision.cpp: Arquivo ou diretório inexistente
```

`tools/server/` **não existe no nosso vendor** — só sobrou `tools/mtmd`. E é
justamente lá que mora `server-decision.cpp`, que é 100% da API de decisão.
`include/llama.h` não ganhou nenhuma API pública nova: os PRs mexeram só em
`common/`, `tools/server/`, `conversion/`, `tools/mtmd/`.

**Nada disso é necessário para o `d1-3B`**, pelos motivos do próximo tópico.

## O que foi medido: o d1-3B roda no app, sem código nenhum

### No Samsung A72 (SM-A725M, SD 720G, 4,8 GB total, 2,7 GB livres)

| evento | resultado |
|---|---|
| carga | `Model loaded successfully` |
| tentativa GPU | **falhou** (`llama_model_load_from_file_impl: failed to load model`) |
| fallback | mmap, CPU, 2 threads pinados em cpu6,7 |
| compute buffer | 264 MiB |
| RAM | 2,9 GB → 1,45 GB disponível |

O app avisou antes: *"RAM disponível 2549 MB / Tamanho do modelo 1597 MB / Isto
pode travar o app..."*. Aviso correto, e não travou.

O roteamento foi automático — `d1-3B` não tem `cls.output.weight`, então caiu em
`decision` sem tocar em código:

```json
POST /v1/classify
{ "input": "Fatura 2026-09 vencida, R$ 340,00. Preciso renegociar...",
  "question": "Qual fila deve tratar esta mensagem?",
  "choices": {"A":"Suporte tecnico","B":"Financeiro","C":"Recursos humanos","D":"Juridico"} }

→ { "object": "classification", "choice": "B", "label": "Financeiro",
    "relevance_score": null,
    "feature_source": "No vector: a state and a question, as text, with 4 options..." }
```

### Bateria no A72

| caso | d1-3B | tev1 (controle) |
|---|---|---|
| fatura / renegociação | ✅ Financeiro | ✅ Financeiro |
| consulta médica | Suporte técnico | Suporte técnico |
| servidor fora do ar | ✅ Suporte técnico | ✅ Suporte técnico |
| **spam** | ✅ **Spam** | ❌ "legítima" |
| dúvida sobre fatura | ❌ Suporte técnico | ❌ Suporte técnico |
| latência | 6,6–23,8 s | ~51 s |

Ressalva: os ~51 s do tev1 vieram com cadência de **8,0 s por token exatos** e 6
tokens amostrados. Isso é contenção/swap no 720G, não velocidade do modelo — não
tratar como número de latência.

## "Pode ser config errada no template ou na integração?"

**Não.** Isso foi separado por experimento, e as três hipóteses caem assim.

### 1. O prompt do mobileLM dá o mesmo resultado que o canônico

O template systemone do GGUF é **flat** — `user\n…assistant\n`, **sem papel de
system** — enquanto o app monta `systemPrompt` (instrução do Tev1 + `/no_think`) e
um `userPrompt` em JSON. Prompturas diferentes. Resultado, no desktop:

| caso | `/v1/systemone` (canônico) | prompt do mobileLM |
|---|---|---|
| fatura/renegociacao | `b` (0,94, conf 0,92) | `'B'` |
| dúvida sobre fatura | `a` (0,68, conf 0,58) | `'A'` |
| spam | `b` (0,99, conf 0,97) | `'B'` |

Idênticos. E o mobileLM no A72 deu **as mesmas 5 de 5** que o caminho canônico no
desktop, **inclusive as erradas**.

### 2. Logo, os erros são do modelo, não do app

Reproduzidos, não inferidos: o mesmo modelo, a mesma pergunta, o mesmo erro, em
máquina diferente e por caminho de código diferente. Isso é fraqueza do modelo,
e o único jeito de melhorar é prompt melhor ou outro modelo — não configuração.

### 3. E não é viés de posição — nos casos que importam

24 permutações das 4 opções, nos dois casos:

| caso | estabilidade | confiança |
|---|---|---|
| fatura / renegociação | **24/24 → Financeiro** | 0,80–0,94 |
| dúvida sobre fatura | **13/24 → Suporte, 11/24 → Financeiro** | 0,32–0,63 |

A resposta que o modelo dá com convicção é **permutation-stable**. A que ele erra
**não é**. Não é viés de posição: é ausência de opinião.

## Por que "uma porcentagem que soma 1" seria errado

Para os shapes **head** a ideia está certa: logits → softmax é probabilidade de
verdade, e a rota de rerank já expõe `relevance_score_probability`. Para o shape
**decision** a ideia está errada, e por três motivos concretos.

**1. Softmax sempre soma 1, mesmo quando o modelo não sabe.** Medido no
`d1-omni-600M` com o servidor fora do ar:

```
score 1,22 · confidence 0,0 · 0,34 / 0,25 / 0,28 / 0,14
```

Softmaxado vira "34% baixa, 25% média…" — parece uma preferência suave quando a
verdade é *"não sei, e escolhi errado"*. É o que o `decision_model.dart` chama de
*"a coin flip that looks stable in every metric"*.

**2. Já foi tentado no reranker, e medido.** Em
`openai_server_service_io.dart:1030`:

> *"spans 0,46–0,87 on a set with one obvious answer, which is not a probability
> of anything"* … *"Both, never one instead of the other."*

Normalizar não cria confiança; só empurra os números para dentro de (0,1), onde
passam a parecer probabilidades sem serem.

**3. A calibração existe — e não no modelo que roda.** ⚠️ **Isto estava escrito
aqui como "o d1 embarca a calibração", e está errado.** Medido nos dois arquivos em
08/10/2026:

```
d1-3B-Q4_K_M.gguf      0 chaves lfm2.decision.temperature.*   <- o que roda
d1-omni-600M-Q8_0.gguf 10 chaves                              <- o que está fora

d1-omni:  choice      = 1.0     choice.2     = 1.7465
          choice.3_5  = 1.3999  choice.6_10  = 1.1751  choice.11 = 1.3725
          noul.2      = 1.6663  score.3_5    = 1.7301
```

O `d1-3B` carrega **só** `lfm2.decision.type = "lfm2-d1"` — nenhuma chave com
`temperature` em nenhuma das suas 43 chaves. As temperaturas são por tipo de
pergunta (`choice`, `noul`, `score`) e por **faixa de quantidade de opções**, e
foram treinadas porque os logits não são probabilidades.

**A consequência que importa:** o modelo para o qual a calibração foi escrita é
exatamente o que o app não consegue rodar, e o que roda não a tem. Ler a
temperatura quando a chave existe continua sendo a leitura certa — mas **não é um
argumento que se aplique ao `d1-3B`**, e todos os números deste documento foram
medidos no `d1-3B`. O argumento que sobrevive é o do softmax: soma 1 inclusive na
incerteza total.

### O que dá para mostrar, por shape

| shape | leitura honesta |
|---|---|
| `ggufHead` / `tfliteHead` | softmax dos logits **+ margem top-2**, com o logit cru ao lado |
| `decision` **com** temperaturas | probabilidade calibrada, dizendo que a fonte é a temperatura do modelo — **e nenhum modelo deste repositório está neste ramo hoje** |
| `decision` **sem** temperaturas | **estabilidade por permutação + margem top-2, rotulado "não é probabilidade"** — e é o ramo de todo `decision` que o A72 mediu |

E sempre o texto bruto que o modelo devolveu, para o caso de prosa ser visível em
vez de virar uma resposta limpa inventada.

### O substituto: consistência por permutação

Rodar a mesma pergunta com as opções embaralhadas e reportar se a resposta muda.
É mensurável, é barato, e pega exatamente o que a porcentagem esconde. O llama.cpp
já faz isso — `n_variants` retorna 2 pra choice do LEV, *"to cancel the preference
for the first label"*.

Com os dados acima, a janela mostraria:

```
fatura/renegociacao   Financeiro   4/4 estável   confiança alta
dúvida sobre fatura   Suporte      2/4 estável   confiança baixa  ⚠ instável
```

O caso instável é o que precisa de revisão humana. Um número normalizado diria
"68% Suporte técnico" nos dois.

## Um bug que o teste expôs

### ⚠️ Correção: "respondeu em prosa" foi palpite, e estava errado

O log do tev1 no A72:

```
15:00:19  Sampling token 2 → 271
15:00:27  Sampling token 3 → 248069
15:00:35  Sampling token 4 → 271
15:00:43  Sampling token 5 → 32
15:00:51  Stream onDone — 5 tokens
```

Li "6 tokens" como prosa. **Não é.** O `AGENTS.md` do projeto já documenta que o
`tev1` responde `<think>\n\n</think>\n\nB`, que **são** ~6 tokens, e o
`parseDecisionAnswer` devolve a letra pela regra do bloco. Não consegui decodificar
os ids para confirmar — o `gguf-py` do PyPI não instala sem `pip` neste host, e o
leitor GGUF escrito à mão erra o offset do array de strings.

O sintoma real era **latência**: 8,0 s por token com o núcleo no piso. Um `d1-3B`
de 3 B leva 6,6–23,8 s pela mesma CPU, então 51 s para um `tev1` de 0,8 B é
anomalia de aparelho, não de formato de resposta. Registrado aqui porque a forma do
erro é a que mais importa: **documentei como fato uma leitura de log, e a leitura
não sustentava o fato.**

### O bug que o `DecisionMatch` expôs, e que era pior

Escrever o enum obrigou a exercitar as três regras do parser. A **regra 3** casava
a primeira letra de **qualquer palavra**, porque tudo depois da letra é opcional:

```
parseDecisionAnswer('account')  ->  letra A, label "bug"
parseDecisionAnswer('bug')      ->  letra B, label "billing"
```

A **regra 4** — casar o rótulo inteiro — era a rede exatamente para isso e era
**código morto**. Conserto: lookahead `(?=\s|[.):\-]|$)`.

Isto importa mais que a incerteza em si: é o modo de falha que o
`decision_model.dart` descreve ("taking the first letter of a sentence"), e ele
estava **no código que existe para impedir que aconteça**. Com 28 testes, nenhum
cobrindo um modelo que responde com rótulo em vez de letra.

## Os quatro presets, e por que dois deles estão aqui errado

`lib/services/system_one_presets.dart` — quatro entradas que preenchem estado,
pergunta, opções e tipo de uma vez, e que **levam a janela para o readout de
logit**. A regra é a mesma dos presets do reranker e a razão é a mesma: **um
preset é um controle, não uma demonstração.**

Quem digita um estado, escolhe três opções e recebe uma letra não tem como
saber se o erro é do modelo, do prompt ou do readout. A janela também não sabe
por ele. O preset fixa os dois primeiros e sobra o terceiro, que é o único que
se mede.

| preset | tipo | medido no A72 | por que está aqui |
|---|---|---|---|
| `charge` | choice | **0,6972** billing, confidence **0,5458** | o que funciona |
| `outage` | noul | **P(true) 0,5188** | **a resposta óbvia é sim** |
| `urgency` | score | **nível 0** (*Can wait*), 0,5537 | **o modelo não foi treinado para nível** |
| `forgot` | choice | **C (account) em 50,7 s** | o custo é do readout, não do ticket |

**Dois dos quatro estão aqui porque erram, e é a parte útil.** Um preset cujas
respostas estão todas corretas ensina que o caminho funciona e nada mais. O
`outage` é exatamente o número que o card da Laya descreve — *"its mean
confidence never drops below 0.885 at any accuracy level"* —: a resposta está
certa e a confiança não ajuda. O `urgency` é um decision model de **LETRA**
perguntado sobre um nível ordenado, e o 0,3305 de confidence ao lado do 0,5537
do topo é o único sinal.

**A ordem é "responde algo que o anterior não respondia", não alfabética.** Por
id, `forgot` vinha em quarto e o primeiro toque da pessoa seria o que leva
50,7 s — e o cartão pareceria travado.

**O preset `charge` NÃO usa o default de `choice` da janela, e isso é
deliberado.** Ele traz `billing / technical support / account`, que é o trio do
`curl` cujo 0,6972 foi medido; o starter da janela é `bug / billing / account`.
São duas perguntas diferentes — uma classifica um ticket de cobrança, a outra
testa o classificador de área — e um preset que trocasse as opções trocaria a
pergunta, que é a única coisa que ele existe para fixar. A primeira versão do
teste afirmava que eram a mesma lista e **reprovou**; a premissa é que estava
errada.

### O seletor de tipo vai no pedido dos **dois** readouts

`questionType` entra no mesmo `systemOneBody`, e o que diferencia os dois
caminhos é **o destino da resposta**, não o pedido. Uma `noul` pedida no
caminho da letra continua escrevendo as duas próprias afirmações e voltando
como letra.

**A primeira versão escondia a carta atrás do readout `logit`, e a janela abria
sem ela.** Um teste de widget achou com `Bad state: No element` — o defeito se
apresenta como "a carta não foi desenhada" quando o defeito é "a carta não
existe neste readout". E o preset **troca para o logit**, de modo que a omissão
ficava invisível justamente no caminho principal.

`noul` **esconde** o cartão de opções em vez de desabilitá-lo: o endpoint
escreve as duas afirmações nas palavras com que o modelo foi calibrado, e um
cartão que aceita texto e não faz nada com ele é pior do que não haver cartão.

### Cinco defeitos, e nenhum deles visível em revisão

Todos achados por `test/system_one_presets_widget_test.dart`:

1. **`_applyPreset` não gravava `_presetId`.** O `setState` existia e a
   atribuição simplesmente não estava nele — o cartão mostrava
   `soc_presets_none` com os campos cheios.
2. **A carta do tipo escondida atrás do readout `logit`** (acima).
3. **O comentário de `_presetId` prometia apagar quando a pessoa edita, e não
   havia listener nenhum.** Três foram ligados nos controladores de estado,
   pergunta e instrução; os de opção são um caminho **separado** — o `TextField`
   de cada opção nasce com um controller novo, então nenhum listener de tela
   dispara — e por isso têm teste próprio. Foi uma **mutação sobrevivente** que
   mostrou que o segundo caminho não tinha cobertura.
4. **`add an option` era literal em inglês** numa tela traduzida, ao lado de
   uma nota que ESTA sim estava traduzida. A assimetria é o que denuncia: o
   mesmo cartão com metade traduzida. A varredura estreita não o via porque
   não é o primeiro argumento de um `Text(` — é o `label:` de um `_add`.
5. **A ordem dos três cartões novos**: presets e tipo vêm depois do readout,
   para o preset estar ao alcance sem rolar até o fundo.

Cinco mutações, cinco reprovações: tipo escondido, `_presetId` não gravado,
`_edited` no-op, `_setOption` sem apagar, `decisionTypeNeedsOptions` invertida.

### Quatro armadilhas de `ListView`, e a sexta ocorrência

Este repo já pagou a dobra preguiçosa quatro vezes; o arquivo de presets pagou
**duas formas novas** e é a sexta ocorrência:

| armadilha | o que acontece |
|---|---|
| `dragUntilVisible` para quando o nó **existe** | o chip saiu em `Offset(180.0, 1206.0)` numa janela de 1200 dp, e `tap` recusou com "would not hit test" |
| ele **só desce** | alvo acima da posição atual é inalcançável, e o erro chega como `Bad state: No element` — que se lê "não desenhado" quando foi, só que fora do cache |
| `findsNothing` num `ListView` | afirma **"não está nesta janela"**, que é verdade da última linha da tela tanto quanto de uma carta nunca adicionada |
| `widgetWithText(TextField, …)` | **não acha campo nenhum**: um `TextField` desenha `EditableText` e não tem `Text` descendente. E `EditableText.at(2)` é `RangeError` com a lista rolada, porque só dois estão construídos |

`everAppears` percorre a lista inteira e é a única ausência que um `ListView`
sustenta; `tapVisible` faz `dragUntilVisible` + `ensureVisible` + uma guarda que
diz "desenhado mas fora da tela" — porque "não achou" e "achou e não dá para
tocar" são defeitos diferentes e a mensagem precisa distinguir.

### ⚠️ O campo `question` da tela NÃO vai no corpo — e isso custou uma resposta errada

**Medido no A72 com `d1-3B`, mesmo estado e mesmas três opções, duas vezes:**

| o que foi perguntado | resposta | A | B | C |
|---|---|---|---|---|
| **`decision`** (o id da pergunta) | **C: account** | 0,1307 | 0,2846 | **0,5847** |
| `a que área isto pertence?` (a instrução) | **A: billing** | **0,5312** | 0,1640 | 0,3047 |

`A: billing` é a resposta certa para uma cobrança duplicada. A primeira linha é
o que o preset produzia — e **mostrava `medido: billing` ao lado**, que é a
pior forma de erro possível: o número certo e a pergunta errada.

A causa: `systemOneBody` **não tem parâmetro `question`**. Quem manda a
pergunta ao modelo é `instructions`; o campo `question` da tela é exibido e
**não sai**. Sem `instructions`, o contrato do endpoint usa o **id** da pergunta
como o texto dela — e o id desta janela é a palavra `decision`.

A primeira versão do preset `charge` punha a pergunta em `question` e deixava
`instruction` nula, e `_applyPreset` fazia `p.instruction ?? ''`. **Um preset
que produz a resposta errada e mostra a medição certa ao lado é pior do que
nenhum preset**, e só o aparelho mostrou: o `curl` com a pergunta certa deu
`A: billing` **quatro vezes seguidas, byte a byte**, contra o `C: account` da
janela.

Duas correções, e a segunda é a que importa:

1. `charge` e `forgot` **declaram** a instrução. `outage` e `urgency` já
   declaravam.
2. **`_applyPreset` não apaga mais o campo de instrução.** Ele faz
   `if (p.instruction != null)` em vez de `p.instruction ?? ''`. Um preset
   preenche o que sabe e **não destrói o que não sabe** — e o sintoma de um
   `?? ''` ali é a tabela de cima.

**E a guarda do ponto 2 é código inatingível hoje**, porque os quatro presets
têm instrução: voltar ao `?? ''` não reprova nada, e isso está escrito no
arquivo de teste em vez de comentado fora. Quem a torna alcançável é o teste de
invariante "todo preset com opções tem instrução" — um preset com
`instruction: null` reprovaria nele.

### O `confidence` é `(n·p_max − 1)/(n − 1)`, e a tabela acima o confirma

0,5847 de topo com três opções dá `(3 × 0,5847 − 1)/2 = 0,3770`, que é
exatamente o `confiança 0.3770` que a tela pintou. E 0,5312 dá **0,2968**, o
que o `curl` devolveu. Confiança não é probabilidade do topo, e as duas linhas
da tabela são a mesma conta feita de dois jeitos.

### ⚠️ O título lia o campo do `choice` — e as outras duas formas estavam erradas

**O A72 mostrou `(no label)` num `noul`.** Medido, os três shapes lado a lado
com `d1-3B`:

| forma | o que o endpoint mandou | o que a tela mostrava | agora |
|---|---|---|---|
| `choice` | `choice: "A: billing"` | `A: billing` | `A: billing` |
| `noul` | `noul: 0,5522` + dois `probabilities` | **`(no label)`** | `yes, the statement holds` |
| `score` | `score: 2.0`, `legend: {"2": "Today"}` | **`2.0`** | `Today` |

Um `noul` **não tem** `choice`, e um `score` tem `choice` que é o índice — as
duas eram lidas como `choice`, que é o campo do `choice`. **Um booleano sem
título e um nível como `2.0` são a mesma linha errada.**

**O `noul` é o argmax das duas afirmações, e o endpoint é quem as nomeou.** O
corpo traz `probabilities: {"yes, the statement holds": 0,5522, "no, …":
0,4478}` e a resposta de um booleano é a das duas que o modelo prefere. Não é o
app inventando um rótulo.

**Empate devolve `null`, e não uma das duas.** Um `noul` em exatamente 0,5/0,5 é
o modelo sem opinião — e escolher uma seria fabricar a preferência que ele não
tem. É a mesma forma de erro que o `d1-omni` com `confidence: 0.0` sobre
`0,34/0,25/0,28`: parece preferência quando é não-opinião. A distribuição está
na tela ao lado.

**O `score` mostra a legenda, e um teste pré-existente afirmava o contrário.**
O teste se chamava *"o `label` do score é o índice"* e afirmava `'2.0'` — o
nome diz índice, o valor diz ponto flutuante, e **um dos dois está errado**.
Era o artefato de `'${score.toDouble()}'` escrito a partir do que o código
fazia, sem justificativa ao lado. `legend` existe para ser usada; o índice
continua em `r.score` para quem quiser o número.

**E o teste novo afirma as TRÊS formas, e essa é a parte que fecha.** O arquivo
afirmava `label` só no caso de `choice` — e é por isso que as outras duas
ficaram erradas em silêncio. Um reader exercitado só no `choice` é um reader
cujo `noul` e cujo `score` ninguém viu.

Três mutações, três reprovações: `noul` voltando a ler `choice`, `score`
ignorando a legenda, e o empate de `noul` escolhendo uma das duas.

### E o `P(true)` do `noul` é quase uma moeda em **dois** modelos

`0,5188` no Tev1 (medido antes) e **`0,5522` no `d1-3B`** (medido hoje) para
"is a service down?" contra um checkout devolvendo 500 desde as 9h. A resposta
óbvia é sim nos dois, e os dois ficam em torno de 0,5. **É o número que o card
da Laya descreve, medido em duas máquinas diferentes** — e o preset `outage`
diz exatamente isso.

## Referência rápida

```bash
# desktop, caminho canônico (llama.cpp master)
llama-server -m d1-3B-Q4_K_M.gguf --mmproj mmproj-d1-3B-Q8_0.gguf -c 4096 -t 4
curl -s localhost:8098/v1/systemone -d '{"state":"…","questions":{"t":{"type":"choice",
  "instructions":"…","criteria":{"a":"…","b":"…"}}}}'

# no app
adb -s $S forward tcp:8091 tcp:8091
curl -s -X POST localhost:8091/v1/classify -H "Authorization: Bearer $KEY" \
  -d '{"input":"…","question":"…","choices":{"A":"…","B":"…"}}'
```

A chave da API aparece truncada no campo de texto da tela de Servidor. O valor
inteiro está em `settings.hive`, chaves `server_use_api_key` / `server_api_key`.