# Handoff — onde o mobileLM-app está, e o que fazer depois

Documento escrito em **2026-10-01**, para quem vai retomar o trabalho em outra
sessação sem o histórico da conversa. Ele é um **snapshot**, não uma fonte de
verdade: `AGENTS.md` continua sendo a fonte de verdade, e o que está aqui ou é
verificável em minutos ou diz onde verificar.

Duas regras do repo valem para este documento: **toda versão repetida em prosa é
um lugar a mais para errar** (o `AGENTS.md` já registra uma versão 0.3.5 descrita
como publicada e que nunca foi), e **tudo que aparece medido aqui foi medido no
Galaxy A72** — o aparelho de teste, onde um número é um piso e não uma média.

---

## 1. Estado numérico, conferido agora

| | |
|---|---|
| versão no `pubspec.yaml` | **0.5.1+2008** (tag `0.5.1` publicada) |
| commits do topo | `75f82cd9a` · `5551761fb` |
| `flutter test` | **356 passando, 0 falhas** |
| `flutter analyze` | **127 issues, 0 erros** (pré-existentes; só erros gateiam CI) |
| árvore | limpa, `main` tracks `origin/main` |
|_branch extra_ | `pdf-markdown-*` (locais), `core/rust-hybrid` (no remoto, **não apagar**) |

**A 0.6.0 não foi preparada.** Tudo das últimas sessões está em
`[Unreleased]` do `CHANGELOG.md`. Antes de subir um minor, a frase "isto faz X,
que antes não existia" tem que sair verdadeira.

### O catálogo, contado e não estimado

| lista | entradas | detalhe |
|---|---|---|
| `availableModels` | **46** | 36 `.gguf`, 5 `.litertlm`, 5 `.safetensors`; 18 com visão |
| `encoderModels` | **16** | 9 `rerank`, 7 `embed` |
| **total** | **62** | é o número que a tela de Modelos reporta |

As duas listas são **separadas** porque um BERT não é um modelo de chat com outro
tamanho. No A72 a tela mostrava menos de 46 na seção GGUF porque a regra de
memória (`maxModelBytes`, ~60% da RAM) **esconde** entradas do catálogo que não
cabem — e o A72 tem 5,6 GB, o Edge 60 até 12 GB. As contagens da tabela são do
catálogo, não do que aparece numa tela.

As **5 `.litertlm`** são `Qwen3-0.6B`, `Qwen2.5-1.5B-Instruct`,
`DeepSeek-R1-Distill-Qwen-1.5B`, `gemma-4-E2B-it`, `gemma-4-E4B-it`. **Só a
primeira foi medida.**

### O que está no APK (arm64, conferido com `unzip`)

Nenhuma lib do núcleo Rust — `mobilelm_core|litert_lm` dá **0 ocorrências**. As
nativas são `libllama_jni`, `libllama`, `libggml*` (8 variantes de CPU + Vulkan),
`liblitertlm_jni`, `liblitert_jni`, **`libLiteRt`, `libLiteRtClGlAccelerator`**,
`libsd_jni*`, `libomp`, `libc++_shared`.

⚠️ **`local_plugins/mobilelm_core/` continua no disco** — 223 MB — mas é só
`vendor/` (subdiretórios vazios) e `target/` (cache de build do Rust). Zero
arquivos rastreados pelo git, zero referências no `pubspec.yaml`. **`ls
local_plugins/` mostra cinco plugins e parece que o núcleo Rust voltou**; ele não
voltou. A branch é `core/rust-hybrid` e a história está em
[`HYBRID_CORE.md`](HYBRID_CORE.md).

---

## 2. O que a última sessão entregou (`75f82cd9a`)

**`.tflite` deixou de ser invisível no app.** Até a sessão anterior o runtime
LiteRT servia `.tflite` **pela rede** e não tinha nada na interface: a descoberta
filtrava por extensão, `.tflite` não estava na lista, e o import recusava em Dart
*e em Kotlin. Um arquivo no diretório de modelos não tinha card, não tinha
tamanho, não tinha botão e não podia ser apagado pela UI.

Onde cada parte está:

| o quê | onde |
|---|---|
| descoberta aceita `.tflite` | `lib/services/download_native.dart` |
| guarda de importação (Dart) | `lib/controllers/model_controller.dart` (~2171) |
| guarda de importação (Kotlin) | `android/app/src/main/kotlin/com/dollarbr/mobilelm/MainActivity.kt` (~940) |
| quarto runtime + ramo na extensão | `lib/models/ai_model.dart` (`runtimeTflite`, `runtimeFromFilename`) |
| seções e badge próprios | `model_controller.dart` (`modelSectionKey`, `modelSections`, `isTfliteModel`), `model_view.dart` (~2639) |
| tile + sheet na tela de Modelos | `lib/views/model_view.dart` (`_buildTfliteMenu`, `_showTfliteSheet`) |
| **o console** | `lib/views/litert_head_console.dart` (novo) |
| parser do FlatBuffer + `fromJson` | `lib/services/litert_model.dart` |
| forma da cabeça (`tfliteHeadShape`) | `lib/services/litert_service.dart` |
| rota do HTTP | `lib/services/openai_server_service_io.dart` (117–129) |
| runtime nativo | `local_plugins/litert_flutter/` (LiteRT **2.2.0**) |
| `localApiHeaders()` | `lib/utils/server_auth.dart` |

**Medido no A72** com `laya_en_act_head_fp32.tflite`, do clique ao logit:

```
159 ms
logits [0.2563, -0.2082]      top_index 0
features_input "pooled_cls"   auxiliary_used ["feats"]
```

### Três defeitos que só o aparelho mostrou

O padrão é o de sempre neste repo: **um erro que se apresenta como outro.**

1. **`Get.to` não fornece `Material`.** É o `Scaffold` que normalmente o
   fornece, e `ChoiceChip` e `TextField` chamam `debugCheckHasMaterial` em si
   mesmos. O primeiro apareceu no log do app; o segundo só num screenshot, como
   uma caixa vermelha no lugar do campo. **Um `Material(type: transparency)` na
   raiz corrige os dois** — e o conserto por painel que existiu no meio do
   caminho foi removido.
2. **`POST` numa rota que só aceita `GET`, engolido por um `catch` mudo.**
   `/v1/litert/status` é `GET`. O console disse "not screened yet" a sessão
   inteira com o probe dizendo que o servidor estava de pé — e ele estava.
3. **Nenhum cliente dentro do app mandava `Authorization`.** `useApiKey` foi
   lançado com `false`, então isso dormiu até alguém **ligar** a chave, quando o
   console de encoders passou a dizer "servidor desligado" contra um servidor no
   ar.

Duas armadilhas de harness que custaram rounds e agora estão fixadas em teste:

- **O teste de layout montava a tela num `Scaffold`** — que fornece `Material` —
  e passou contra os dois widgets quebrados, no aparelho em que estavam
  quebrados. O harness tem que montar a tela **como ela é mostrada**.
- **`SizedBox(height: 2400)` dentro de `Scaffold(body:)` não move o viewport.**
  O `Scaffold` dá 600 dp. Quem move é `tester.view.physicalSize`. Sem isso o
  `ListView` preguiçoso nunca constrói as linhas de baixo.
- **`takeException()` devolve uma exceção por chamada.** Duas construções
  ofensivas deixam a segunda na fila, e ela aparece no **teste seguinte** como
  "Multiple exceptions were detected", acusando o teste errado.

E uma de medição, que custa um dia se ninguém avisar: **o `uiautomator` mente
sobre o `Switch`.** O nó de semântica tem os `bounds` da linha inteira
(`[45,266][1035,542]`) e o alvo de toque real tem ~169 px na **ponta direita**.
Tocar no centro não faz nada, com `enabled=true clickable=true` confirmando que
"está quebrado". O que separa isso de defeito real é um **controle**: o switch
`Require API key`, na mesma tela, responde normalmente.

---

## 3. O que está verificado por medição (A72)

### O catálogo, seis modelos, melhor de 3, pedidos consecutivos **sem pausa**

| modelo | backend | lyr | TTFT | decode |
|---|---|---|---|---|
| LFM2.5 230M (Q4_0) | cpu | 0 | 0,18 s | **49,3** |
| LFM2.5 350M (Q4_0) | cpu | 0 | 0,34 s | **31,9** |
| Gemma 3 270M (QAT Q4_0) | cpu | 0 | 0,16 s | **31,1** |
| Tev1 0.8B (Q8_0) | cpu | 0 | 1,10 s | **11,0** |
| SmolLM2 135M (Q4_K_M) | cpu | 0 | 8,24 s | **5,1** |
| Qwen 3 0.6B (LiteRT-LM) | **gpu** | 1 | 3,00 s | **3,8** |

Quatro conclusões que já valem: **a ordem por tamanho é falsa** (o 135M é o mais
lento de todos); **o LiteRT-LM é ~6,2× mais lento que o llama.cpp na CPU** e a
GPU é **mais rápida**, não mais lenta (o "8× mais lento" que a documentação dizia
comparava dois *runtimes*, não dois backends); **as amostras da CPU variam 150×,
as da GPU não** (o governor, de novo); e **todos os GGUFs foram para a CPU com
`layers=0`** mesmo com a GPU presente — a regra de 1280 MB se sustenta até 774 MB.

### LiteRT 2.2.0, o act head da Laya, nos dois backends

| | compila | run | logit 0 | logit 1 |
|---|---|---|---|---|
| CPU (XNNPACK) | **6 ms** | 0–2 ms | +0,284356 | −0,209888 |
| GPU (OpenCL) | 273 ms | 0 ms | +0,284356 | −0,209888 |

Diferença máxima **2,98e-08** — precisão de float32. O aparelho reporta
`available: ["GPU","CPU"]`; o NPU continua inacessível.

### A superfície de decisão

`/v1/classify` serve agora **três** caminhos, despachados pela **extensão do
arquivo** (nunca por um campo `runtime`, que poderia discordar do arquivo em
silêncio): cabeça de classificação GGUF, decision models (Tev1: **5 de 5** no
A72) e cabeça `.tflite`.

### A API local

`GET /v1/models/local`, `POST /v1/models/{download,load,unload}`, o servidor sobe
**sem modelo**, a chave é exigida por padrão, `load` exige `accept_risk`,
`unload` é recusado, e trocar de runtime é recusado com `409`. 19 verificações a
frio no A72, zero falhas.

### Decisões que custaram tempo e continuam valendo

- **Qual input é o vetor de features é o MAIOR, não o primeiro.** O act head
  guarda `feats [1,4]` **antes** de `pooled_cls [1,1024]`; "primeiro" escolhe o
  auxiliar. `features_input` como override, e a resposta sempre nomeia qual foi.
- **Auxiliares nunca são preenchidas com zeros.** Um logit sobre features
  inventadas volta usando um rótulo confiante. A recusa nomeia o que falta.
- **`executed_accelerator` é `null`, com nota.** `CompiledModel` não tem getter do
  acelerador que usou. A resposta traz `available` e `requested`; inventar o
  "real" seria mentira.
- **`relevance_score` é `null`** para decision models, com `why_no_scores`.
- **Prosa é falha, não fallback** — 422 com o texto bruto.
- **Reportar o backend que rodou**, não o tier pedido.

---

## 4. O que **não** está verificado

| pendência | por que importa |
|---|---|
| **os outros 4 `litertlm`** (gemma-4 E2B/E4B e mais dois) | "GPU é o melhor LiteRT neste aparelho" veio de **um** modelo, o 0.6B. Nenhum dos outros é um 0.6B, e a curva do LiteRT pode ser outra |
| **a hipótese da quantização** | o SmolLM2 135M é o mais lento e é o único `Q4_K_M`. Se a causa for a quantização e não o tamanho, a regra de 1280 MB precisa de recorte |
| **o host completo do Laya** | 705 MB de grafo, tabela de embeddings de 98 MB, tokenizer ModernBERT, orquestração de 2 grafos. **Não é memória** — §4.1. É trabalho de host, e a parte cara é *cálculo*, não peso |
| **o NPU** | inalcançável no Edge 60 (o linker namespace bloqueia `libneuron_adapter_mgvi.so`) e não provado no MT6878 |
| **as 3 pendências de licença do Tev1** | licença "being finalized", sem Q4, GGUF de comunidade com 0 downloads. **Não se resolvem com código** |

---

### 4.1 O Laya no A72: uma afirmação minha que a aritmética desmente

Este merece uma subseção, porque os docs diziam **"Cabe no Edge 60, não no
A72"** e isso era **uma afirmação minha, sem medição, que a regra do próprio app
desmente**.

**Os pesos cabem, e sobra.** Conferido contra o código e contra o aparelho agora:

| | número | de onde veio |
|---|---|---|
| grafo do encoder | 705 MB | o modelo publicado |
| tabela de embeddings | 98 MB | o modelo publicado |
| act head | 1,0 MB | **medido no A72** |
| **total** | **804 MB** | |
| `maxModelBytes` no A72 | **1,19 GB** | `totalRamGB × 0.25`, `device_info_service.dart:29` |
| `MemTotal` no A72 | 4,78 GB (5.011.840 kB) | `/proc/meminfo`, lido agora |
| `MemAvailable` no A72 | 2,86 GB (2.997.760 kB) | `/proc/meminfo`, lido agora |

804 MB são **68% do orçamento que o app mesmo se dá**, e 33% do que o telefone
tem disponível agora. A regra dos 25% da RAM física existe porque o
low-memory killer do Android chega antes de os pesos acabarem, e esse raciocínio
não fica menos verdadeiro para um modelo maior. **O A72 nunca foi excluído por
memória, e "não cabe no A72" era eu escrevendo uma conclusão onde havia uma conta
para fazer.**

**O que custaria de verdade é cálculo, e isso ninguém mediu.** Um forward pass
do ModernBERT sobre uma passagem não é decode autoregressivo: não há reaproveitamento
de KV, então o pinning do app — afinado para geração token a token, e que vale
2,8× sozinho — não compra nada aqui, e a passagem toda é um prefill de 12 camadas
de uma vez. Num Snapdragon 720G de 2019 (2×A78 + 6×A55, Adreno 618) a estimativa
honesta é **segundos por passagem, não milissegundos**, e 705 MB por OpenCL num
Adreno 618 que divide RAM com a CPU também não é um plano promissor. **As duas
coisas são chute.** O ponto é que nenhuma das duas é uma parede de memória, e
tratar "é grande demais" como resposta pulou a pergunta.

**Então o bloqueio real é mais estreito do que parecia.** O act head — a parte
que produz os logits — **já roda no A72, 159 ms, nos dois backends**. O que não
existe é um host: ler a passagem, tokenizar com ModernBERT, rodar o encoder de
705 MB, derivar `[top1, top1−top2, entropia, k/255]`, e então rodar o act head. Isso é um trabalho de orquestração em Dart contra um interpretador que já
está no APK e já foi provado neste aparelho, **não** uma pergunta sobre a
capacidade do telefone. Ficou fora do escopo como combinado, e deve ficar — mas
**"fora do escopo" e "não cabe" são frases diferentes**, e só a primeira era
verdadeira.

---

## 5. O próximo passo natural

### Medir a quantização — e ele precisa de um par que o catálogo não tem

**Por que este e não outro.** É o único item da fila que muda advice donnée a
**36 dos 46** modelos do catálogo, e o advice atual está **comprovadamente
errado**: o `AGENTS.md` diz que o menor modelo é o mais lento, o que é uma
recomendação que o aparelho desmente. Os outros itens da fila afetam 5 modelos
(os `litert`) ou 1 (o Laya).

**A pré-condição, verificada agora: o catálogo não tem nenhuma família em duas
quantizações.** As quantizações presentes são `Q4_0` (11), `Q4_K_M` (12) e
`Q8_0` (1), e nenhuma família aparece duas vezes. Então o par tem que vir de fora
do catálogo — o mesmo modelo em `Q4_K_M` e `Q4_0`, do mesmo autor, para que a
única variável seja a quantização.

**O protocolo, e as armadilhas que ele já pagou:**

1. **Mesma família, mesma arquitetura, só a quantização muda.** Nem o nome, nem a
   arquitetura, nem o `n_ctx`. Se a arquitetura mudar, o teste não é sobre
   quantização.
2. **Conferir o cabeçalho antes de baixar**, como foi feito com o Tev1:
   `~/.cache/mobilelm-tools/gguf_header.py`. Descobrir que a arch não é suportada
   depois de 800 MB é derrota.
3. **`curl -sI … | grep content-length` contra o campo `size`** antes de entrar
   no catálogo. Um 404 só aparece na hora do download.
4. **Pedidos consecutivos, sem pausa, e melhor de N.** Uma pausa mede o
   **governor**, não o modelo — foi o erro que deformou a leitura do SmolLM2 para
   5,1 tok/s com núcleo no piso a 652 MHz. O mesmo aparelho, o mesmo modelo, o
   mesmo build: **4× de diferença só no clock**.
5. **Contar tokens por `onToken`**, nunca por `split(RegExp(r'\s+')).length`.
   Só corrigir isso levou o mesmo aparelho de 17,4 para 32,0 tok/s.
6. **O prompt precisa exigir duas frases.** Um script que exige dois tokens para
   ter taxa de decode declara "nenhuma geração respondeu" para um modelo que
   respondeu `3` — a resposta certa, em um token.

**Se a diferença se confirmar**, a regra de 1280 MB ganha um recorte por
quantização e o advice do catálogo muda de "escolha o menor" para "escolha o
menor **Q4_0**". **Se não se confirmar**, a causa do SmolLM2 é o modelo — e aí o
que resta é olhar arch e `n_layer`.

### Depois dele, nesta ordem

1. **Os 4 `litertlm` restantes.** O caminho de medição já existe e é o mesmo; a
   pergunta é estreita ("a GPU continua sendo o melhor LiteRT aqui?") e a resposta
   muda uma frase do `AGENTS.md` que hoje vale para um modelo só.
2. **Uma entrada de catálogo `.tflite`.** **Parcialmente entregue em 2026-10-01:**
   a janela de testes dos modelos *System One* existe, e ela dirige o act head da
   Laya no A72 — inclusive o `feats [1,4]`, que antes não tinha campo em lugar
   nenhum. **O que continua de pé:** não há entrada de catálogo, então o único
   arquivo utilizável ainda é um que foi empurrado à mão; e a janela **não
   embute** um texto com um encoder, que é o que tornaria o vetor de 1024 números
   um botão em vez de um colar. Esse é o próximo incremento natural, e ele são duas
   chamadas e duas cargas de modelo — o que é por que não foi assumido sem medir.
   O host completo da Laya (o encoder ModernBERT de 705 MB) segue fora de escopo,
   e §4.1 diz por quê ele não é um problema de memória.
3. **Fechar a fila antiga de UI** (overflows restantes, nomes e comentários dos
   modelos, quantização por swipe no card).
4. **A 0.6.0**, com o critério deste repo: minor = feature, e a frase tem que sair
   verdadeira.

---

## 6. Como medir de novo (runbook)

**Aparelhos:** **Galaxy A72 (`RQ8R3077LMF`) = debug**, tudo é medido nele.
**Edge 60 = só releases** — instalar debug troca a assinatura → desinstalar →
perde modelos, histórico e workspace. A tela do A72 **estraga** (a imagem aparece
mas o touch não responde), então tudo é por comando `adb`. **Desligar a tela ao
terminar: `adb shell input keyevent 223`** (o `223`, não o `224`).

**Ferramentas** em `~/.cache/mobilelm-tools/`: `medir.py`, `req.sh`, `api.sh`,
`server-only.sh`, `verify-api.py --cold`, `gguf_header.py`, `nodo.py`.
Chave de API atual em `/tmp/opencode/key.txt`.

**Armadilhas que já custaram uma rodada cada:**

- **`adb forward` não sobrevive à reconexão do adbd** — refaça, e repita a
  requisição só quando não houve resposta.
- **`req.sh` tem `--max-time 15`**; para coisa lenta, `TIMEOUT=90`.
- **Sempre conferir `adb install` por palavra** e ler o `lastUpdateTime` — o
  `tail -1` mostra só a linha do `pm command`. Já custava "testar" um build que
  nunca foi instalado.
- **Por USB o adbd é `shell` (uid 2000)**: entrar no diretório privado do app
  exige `adb push` para `/data/local/tmp` + `run-as … cp`.
- **`flutter analyze` não compila Kotlin nem C++.** `./tool/jni-syntax.sh` para o
  JNI (~8 s contra 22 min de CI); `flutter build` para o Kotlin.
- **Build de release falha localmente de propósito** — `build.gradle.kts` exige
  CI.
- **APK de debug é multi-ABI.** `abiFilters` num módulo de biblioteca **não**
  filtra o APK; quem filtra é `--target-platform`.
- **O registrante real é** `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`
  (gitignored). O `.dart_tool/flutter_build/dart_plugin_registrant.dart` é velho e
  não confiável.

**Na tela de Server**, o switch do servidor responde a toque **na ponta direita**
(≈x 906 de 1080), não no centro da linha — ver §2. E `nodo.py toggle` procura um
nó com `checked`, que o Flutter não expõe para esse `SwitchListTile`; o caminho
que funciona é calcular a ponta a partir do `bounds` da linha.

**Logs ficam em arquivo no aparelho**, não no terminal:

```sh
adb exec-out run-as com.dollarbr.mobilelm cat app_flutter/logs/app.log > /tmp/mobilelm.log
```

**Medir pelo log é o que resolve.** Foi decisivo em todos os diagnósticos
desta série — inclusive nos três bugs acima, nenhum dos quais tinha sintoma
próprio.

## Fila — do mais fácil ao mais difícil

Ordenada por **risco de quebra**, não por tamanho. O item 0 é o único que **mata
o app**, então vai primeiro apesar de não ser o menor.

| # | Item | Tamanho | Por que nesta posição |
|---|---|---|---|
| 0 | ~~A geração de imagem mata o app~~ | **feito** | `Cannot invoke native callback outside an isolate`: SIGABRT **350 ms** depois de `Creating SdIsolateProcessor`. `Pointer.fromFunction` só pode ser chamado do isolate que o criou, e o `stable-diffusion.cpp` chama dos **workers do ggml**, que são threads do processo. **Consertado e verificado no A72**: `NativeCallable.listener` no Dart + o `void*` que ele exige no typedef C. Três coisas que só a leitura do arquivo inteiro mostra: havia um **terceiro call site** do callback (`g_ffi_progress(0, steps, 0.0f)`, o passo-0 do upstream), `setupCallbacks` **recria** os callables em vez de `??=` senão o nativo fica apontando para um callable fechado, e `clearCallbacks` **zerou antes de fechar** porque a ordem inversa abre janela. Detalhe em `AGENTS.md`. |
| 0b | **O seletor de quantização de imagem: qual número a tela mostra** | médio, decisão | O item 0 está feito, e a medição que ele destravou **invalida o plano do item 4**. A previsão de pesos acerta o FP16 (erro −9%) e erra **+74% no Q4_K e +126% no Q2_K**. `Q4_K -> Q2_K` economiza **77 MB** de verdade quando a previsão diz 218. A primeira quantização paga quase todo o ganho e as seguintes compram cada vez menos — a assinatura de um piso que não é de pesos. **Oferecer a lista com "0,77 GB previsto" seria dizer uma coisa verificavelmente falsa.** As duas saídas estão em `AGENTS.md`; a segunda (tabela de RSS medido) é a que responde "cabe?". |
| 1 | ~~Adotar o vocabulário visual da casca~~ | **feito** | **11 usos** no console `.tflite` e **8** na janela System One, contra 0 antes. Custou um bug: `consoleMono` ganhou `radius` e o `Container` passou a receber `color:` **e** `decoration:`, que ele **asserta** não poder — o console `.tflite` travou no primeiro paint e o teste passava, porque com `radius: 0` o ramo `decoration: null` escondia o conflito. O teste monta os dois raios agora. `consoleCard`/`consoleMono` ganharam `radius` (a **união** das duas variantes), `ConsolePalette.explicit` passou a 2 argumentos deduzindo o brilho da cor, e o `_field` do `.tflite` **continua local** com o motivo escrito — unificá-lo é decisão visual, não de-duplicação. |
| 2 | ~~Varredura de overflow de verdade~~ | **feito** | `test/row_overflow_audit_test.dart`, 5 testes. Um **scanner estático**, não montagem de tela: nenhuma view é montável (dependem de Hive + controllers GetX), então a auditoria de layout por site é trabalho separado. Ele resolve `.tr` contra `app_translation.dart` e colapsa interpolações para 1 caractere antes de contar, com threshold de 20 caracteres pintados — **sem resolver o `.tr` ele conta 24 achados, com isso conta 3**, e o literal no fonte raramente é o texto que aparece na tela. Os 3 achados foram **corrigidos**, não listados, e por isso a allowlist fica `const <String>[]` **de propósito**: uma allowlist deixa o verde indistinguível dos bugs já consertados e ensina o próximo a listar em vez de ler o próprio `Row`. `chat_view.dart` (pill de escuta → `Flexible`), `model_view.dart` (banner → `Flexible` + ellipsis) e `settings_view.dart` (tile de passos → `Expanded` + ellipsis, `Spacer` removido). **Prova de que falha:** remover o `Flexible` do pill por string exata faz a auditoria acusar `chat_view.dart:831  39 chars  Ouvindo — toque no microfone para parar`. Verificado no A72 a 1.4× de fonte. |
| 3 | ~~Nomes e comentários dos modelos do catálogo~~ | **feito** | As **62** fichas estavam em inglês numa tela `pt_BR`, e **uma** terminava em meia-frase — o guia disse cinco, e quatro das cinco eram o meu bug de extração lendo só o primeiro segmento de um literal adjacente. Traduzidas nos **dois** idiomas (`descriptionEn`/`descriptionPt`). Detalhe e a correção em `AGENTS.md`. |
| 3b | ~~Seletor de idioma~~ | **feito** | Auto / English / Português (Brasil), **padrão inglês**. O app era `locale: Get.deviceLocale` com fallback `pt_BR` — deduzir foi o que produziu as 62 fichas em inglês. **463 chaves nos dois mapas**, `lib/services/language_preference.dart` puro, verificado no A72 (troca na hora, sem reiniciar). |
| 3c | ~~Os literais de tela~~ | **feito (views/widgets)** | O `AGENTS.md` dizia 63; eram **123**, e o número esteve errado cinco vezes porque a lista de call sites ficava incompleta — a última omissão foi **`subtitle`**, visível só com o **teto em zero e três legendas em inglês no A72**. Duas varreduras: a estreita (`tool/inline_english_scan.dart`, reescrevível, **0**) e a ampla (`tool/inline_english_broad.dart`). Mais **35 interpolados**, que o filtro recusa por desenho, via `lib/services/text_interpolation.dart`. **596 chaves nos dois idiomas.** |
| 3d | ~~`lib/controllers`: 61 textos de tela~~ | **feito** | Os 61 eram títulos e corpos de `snackbar` e diálogo — tela, todos eles. **Onze não eram texto** e quatro são os que machucam se alguém traduzir: `'system'` (role do contrato OpenAI), `'light'`/`'dark'` (tema salvo, comparado num `switch`) e as substrings procuradas com `lower.contains()` dentro da mensagem de erro do engine — traduzir `'out of memory'` **faz a detecção de falta de memória parar de casar**, e nenhum teste pegava. `ModelSection.title` é **chave persistida no Hive** e não pode ser traduzida — só o `labelKey`. Há agora um teste que afirma o **contrário** da varredura: cada entrada de `TextLanguage.naoTexto` tem que **existir** como literal no fonte, e ele acha também entrada morta. |
| 3e | **0 textos de tela** — 205 traduzidos | **fechado** | A varredura ampla está em **zero** e o teto dela desceu a **zero** com ela. Os 205 eram 148 literais diretos (`tool/rewrite_broad.dart`, com `tool/broad_inline.tsv` como fonte) e 33 interpolados (`preencher('chave', {...})` — trocar o literal inteiro apagaria a parte que muda; 4 deles tinham ternário dentro do `@valor`, que não é traduzível e virou concatenação de duas chaves). O mapa foi de **674 para 886 chaves**. **Fechado pelo aparelho, não pelo contador:** as duas últimas levas apareceram no `dump` do A72 com o teto em zero — `📱 Mid-range (4.8GB) — Good for 1-3B models` e `NPU unavailable on SM7125 — no vendor driver reachable`. **Medido e não fechado:** `lib/services` tem **641** literais de tela e 135 deles são a lista de palavras do próprio detector, então ampliar a trava para a pasta publicaria um teto que não protege nada. **`NpuStatus.toString()`** mora no plugin local e era pintado por `s.toString()`; agora o serviço reporta fatos e a view fala (`settings_view._npuFrase`). **Os rótulos de faceta do HF** (os mapas `_misc`, `_quant` e `_taskLabels` do `hf_search_sheet.dart`) continuam em inglês: são os rótulos que o app dá às facetas do hub, e são ~30. Armadilhas fechadas: `'Unknown size'` era sentinela **e** texto; **unidade colada no placeholder** (`@ramGB`) fazia o `preencher` lançar dentro do `build`; `'running'` é status gravado no Hive **e** rótulo de botão, e a ordem é traduzir o rótulo primeiro (`soc_run_now`) e só depois declarar a comparação como dado; **o `toString()` de um serviço é tela**; **`static const` com valor traduzido congela a língua do boot**. |
| 4 | **Quantização por swipe no card** | médio, UI | Prometido no `0.2.x`, nunca entregue. Move o `Slider` para longe do cartão e dá um alvo de toque grande. |
| 5 | **Entrada de catálogo `.tflite`** | médio, dado | O console funciona, mas o único `.tflite` utilizável foi empurrado à mão. A rota barata é uma cabeça de **uma entrada** só — a regra do "maior input" tornou isso trivial e cobre o caminho feliz sem auxiliares. |
| 6 | **O `.arb` está morto** | pequeno, limpeza | `app_pt_BR.arb` tem 112 chaves, **91 usadas** com `.tr` e 106 já no mapa — então é um **subconjunto**, não a "fonte divergente" que eu escrevi aqui e no CHANGELOG. As 6 que só existem nele são traduções de rótulos que o app **já mostra em português** como literais inline nos chips de ação rápida, então **não há bug visível**: quase consertei uma não-bug. O que sobra é uma fonte morta que alguém pode editar achando que muda algo. Decidir: apaga ou passa a ser gerado. |
| 7 | **A hipótese da quantização** | alto, **medição** | `Q4_K_M` contra `Q4_0` do **mesmo** modelo. Único item que muda advice para 36 das 46 entradas, e o advice atual está comprovadamente errado (o menor modelo é o mais lento). O catálogo não tem nenhuma família em duas quantizações, então o par vem de fora. |
| 8 | **Os 4 `litertlm` restantes** | alto, **medição** | "GPU é o melhor LiteRT neste aparelho" veio de **um** modelo, o 0.6B, e nenhum dos outros é um 0.6B. |
| 9 | **A `0.6.0`** | — | Minor = feature, e "isto faz X, que antes não existia" tem que sair verdadeiro. Depende de escolher o que entra. |

### Não está na fila, e por quê

- **A memória devolvida pelo `/v1/litert/unload`** — precisa de um grafo grande o
  bastante para aparecer contra 2,9 GB de `MemAvailable`; a única cabeça no
  aparelho tem 1,0 MB. Bloqueado por falta de material, não por código.
- **O encoder console adotar a casca** — decisão deliberada e escrita: é um
  monitor do modelo carregado, sobre o chat, com outro ciclo de vida, e o teste
  de layout dele já se provou falhando. Refazer essa decisão é trabalho, não
  bug.
- **NPU** — o linker namespace do Edge 60 bloqueia `libneuron_adapter_mgvi.so` e
  o MT6878 não tem prova. Precisa de dispatch reconstruída *e* de firmware.
- **As 3 pendências de licença do Tev1** — nenhuma se resolve com código.
- **O host completo da Laya** (o encoder ModernBERT de 705 MB) — fora de escopo
  por acordo, e agora se sabe que **não** é problema de memória: 804 MB contra
  `maxModelBytes` de 1,19 GB.
