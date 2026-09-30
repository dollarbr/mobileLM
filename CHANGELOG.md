# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

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
