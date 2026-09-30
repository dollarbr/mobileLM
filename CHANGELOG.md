# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

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
