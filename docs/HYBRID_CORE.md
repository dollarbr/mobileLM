# O núcleo híbrido Rust — por que saiu do APK, e como voltar

Este documento é a resposta a uma pergunta que não tem outro lugar: *por que o
`mobilelm_core` não está mais no app, e o que teria que ser verdade para ele
voltar?*

O código não está perdido. A branch `core/rust-hybrid` no remoto tem os ~20
commits — o crate Rust, a cdylib, os 15 entry points da ABI, a camada Dart e 74
testes de host. `git log core/rust-hybrid` traz tudo de volta.

O que saiu do APK não foi o código, foram **37,2 MB** que pagavam por ele.

## A decisão

Removido em 2026-09-28, na 0.3.5. Três motivos, e o terceiro é o que decide.

**1. O teto da C API é estrutural, não é esforço.** Todas as tags do LiteRT-LM
foram conferidas na API do GitHub:

| tag | data | traz C API para Android? |
|---|---|---|
| **v0.17.1** (a ponta) | 2026-09-16 | **não** — `CLiteRTLM.xcframework` só |
| v0.17.0 | 2026-09-09 | não — os mesmos dois, mais um binário macOS |
| v0.16.1 | 2026-08-18 | não — um binário macOS |
| **v0.16.0** | 2026-08-11 | **sim** — `litert_lm_c_api-0.1.0.zip`, 154,1 MB |

A 0.17.1 **é** a última versão, e é exatamente por isso que não pode ser usada: o
asset da C API não existe nela nem em nenhuma outra. Não há `main` mais novo para
compilar do fonte. A C API mais nova que existe em qualquer lugar está quatro tags
e cinco semanas atrás.

**2. A consequência já apareceu, e não é um item só.** A rota C API não consegue
configurar um sampler no runtime fixado. E o motivo é o tipo de coisa que só o
aparelho diz:

```
[LiteRt] sampler: top_k, which consults every knob the app set
[Inference] Rust turn failed: UNIMPLEMENTED: Sampler type: 1 not implemented yet.
```

`litert_lm_sampler_params_create(1)` devolve **ponteiro não-nulo** num runtime que
**não implementa** o tipo 1. Criar sempre funciona; a recusa chega na geração, uns
3 s depois, com prefill e decode já construídos. Então "o `create()` devolveu
ponteiro?" **não** responde "este tipo existe?", e uma sonda construída sobre isso
respondeu com um `full: true` confiante — um instante antes de matar o turno. A
rota JNI que o app já usa alcança um sampler; a rota C API do pin não alcança.

A lista do que a C API de 0.16.0 não faz é **maior** que o único item que foi
encontrado, e cada item novo custa um ciclo de build de 22 minutos.

**3. O argumento a favor não se sustenta neste app.** A defesa do núcleo era
*alcance*: Kotlin não faz `dlopen`, então a C API é a única rota de Dart até o
LiteRT-LM. Isso é verdade — e é irrelevante enquanto um plugin Kotlin escrito à mão
fizer o trabalho. Concretamente:

- **O engine é C++ e continua C++.** A amarra não compra velocidade nenhuma. 21,2
  tok/s de prefill contra 3,4 no Vulkan é o engine, não o transporte.
- **O APK cresce 37,2 MB** (`liblitert-lm.so`) contra os 20,8 MB de
  `liblitertlm_jni.so` que saem com o plugin. É a segunda maior lib do APK, atrás
  só do `libsd_jni_vulkan.so` com 52,5 MB.
- **E a flag desligada não é de graça.** Com o switch em `false`, o `main.dart`
  ainda chamava `CoreSelfCheck.run()`, que abre a cdylib e depois
  `symbolsMissing()` — que `dlopen`a o runtime de 37,2 MB e resolve 26 símbolos,
  **a cada cold start**, só para imprimir uma linha de log.

A frase de bump minor exigida pelo repo — "isto faz X, que antes não existia" —
saía como: um slider de temperatura que não faz nada, 37,2 MB a mais, e o mesmo
tok/s. Não é feature. É por isso que o `0.4.0` do núcleo não existiu, e é por isso
que a remoção é patch: sai na 0.3.5, junto do botão de rolar para o final e da
métrica de tok/s, que era um bug pré-existente e independente do núcleo.

## As medições, que são o que torna qualquer comparação futura possível

Edge 60, Qwen3-0.6B.litertlm (614.236.160 B), CPU, ctx 4096, maxTokens 2048,
prompt "Explain in one sentence what is a token.".

| | Kotlin plugin (JNI) | Núcleo Rust (C API) |
|---|---|---|
| carga | `loaded with CPU backend, ctx=4096` | `actual: cpu, fallbackReason: null` |
| caiu para o outro caminho | n/a | **não** |
| TTFT | 11,05 s | **61,96 s** |
| total | 55,9 s | 61,98 s |
| tokens | 139 | 106 |
| tok/s ponta a ponta | 3,1 | **1,71** |
| RSS de pico, ocioso | não medido | 1.836.835 KB (1,75 GiB) |

O caminho de carga **funciona** e foi provado: `actual: cpu`, sem recuo, 1,75 GiB.
O caminho de envio só funcionou depois de remover o sampler, e mesmo assim **não
faz streaming** — os 106 chunks chegaram nos 27 ms finais, e a causa é nossa: a
chamada FFI bloqueia o isolate dono, e o event loop dele não roda enquanto a
chamada não volta, então as invocações do `NativeCallable.listener` se acumulam.
A regra do crate dizia que bloquear era deliberado, para o tempo de vida do
contexto de callback; o contexto é um `int64` e a ponte carrega o `SendPort`, então
o tempo de vida já estava seguro e o bloqueio só custou o streaming.

## O que teria que ser verdade para voltar

1. **Uma C API atual.** Só existem dois caminhos: compilar a 0.17.x do fonte (é um
   projeto de cross-compile C++ grande no CI, e é outra coisa que não é ligar uma
   cdylib num app) ou esperar a Google publicar o asset. Enquanto isso, a lista do
   que falta é desconhecida e se descobre um item por vez.
2. **A escada de sampler por turno.** Um tipo só pode ser provado por um turno, não
   por um `create()` que sempre devolve ponteiro. Isso é uma escada com retry, não
   uma consulta, e custa um run de aparelho por tentativa.
3. **O sink movido para uma thread.** `Box::from_raw(raw)` libera o sink quando
   `stream()` retorna; para a chamada FFI voltar antes, o engine ainda poderia
   atirar para memória liberada.
4. **Um motivo para existir sem o plugin Kotlin.** Como está, o núcleo
   reimplementa em Rust uma rota que já funciona.

E a pergunta que precede todas: **vale a pena, contra os 37,2 MB e contra o fato
de que o caminho de mais rápido do app é o que já existe?**

## O que não foi jogado fora

- A branch `core/rust-hybrid`, com os ~20 commits: o crate Rust, a cdylib, os 15
  entry points da ABI, a camada Dart (`lib/ffi/`) e 74 testes de host.
  `git log core/rust-hybrid` traz tudo de volta.
- A tabela de medições acima, que é o que torna qualquer comparação futura
  possível. Sem ela, um futuro "e se a gente usasse a C API?" recomeça do zero e
  gasta um ciclo de 22 minutos para redescobrir o teto.
- A regra do `dlopen`-nunca-linkar, que é o motivo de `cargo test` rodar num
  laptop. Está no `AGENTS.md` do workspace.
- A escada de aceleração **perdeu o dono em Rust** e voltou ao corpo Dart puro em
  `lib/services/acceleration.dart` — que é exatamente o código que a delegação
  chamava, sem a chamada. Continua coberto por `test/acceleration_test.dart`, então
  nada se perde funcionalmente. É a única coisa que a remoção tirou de verdade.

## O `.gitignore`

As duas entradas `libmobilelm_core.so` e `liblitert-lm.so` continuam listadas em
`android/app/src/main/jniLibs/arm64-v8a/`, e devem ficar. Nada as produz mais, mas
quem tem um worktree antigo ainda tem os dois arquivos em disco, e é exatamente
dali que um `flutter build` local os pegaria. Ignorar por nome — e não por
diretório — continua sendo o certo, porque `libomp.so` mora no mesmo diretório e
é versionado de propósito.
