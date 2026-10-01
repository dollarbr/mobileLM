# mobileLM — Agent Guide

Objetivo do repo: mix do **PrivateLM** (motor local Flutter) com **PocketStrike-AI**
(camada de agente). Fonte da verdade do roadmap: [`docs/PLAN.md`](docs/PLAN.md) — leia antes de qualquer tarefa.

## Estado atual

M1 ✅ · M2 ✅ · M3 ✅ · M4 ✅ · M5 ✅ — releases publicadas em
<https://github.com/dollarbr/mobileLM/releases>. Versão atual: **0.5.1+2008**.
Engine local (GGUF + LiteRT-LM 0.17.1) + agente multi-passo + tools nativas
(24 built-in, 8 privilegiadas via Shizuku) + tarefas agendadas + image gen +
servidor OpenAI compatível + **encoders (embeddings/rerank/classify, BERT e
ModernBERT)** + cloud models com auto-detect de contexto/capabilidades.

## Encoders — o que a 0.4.0 trouxe (leia antes de mexer)

**Dezesseis** encoders no catálogo (9 `rerank`, 7 `embed`), served por
`/v1/embeddings`, `/v1/rerank` e `/v1/classify`. As regras que custaram tempo
para achar, todas medidas:

- **O papel vem do campo `role` da entrada do catálogo, nunca do nome do
  arquivo.** Um nome não carrega arquitetura — `bge-small-en-v1.5` já foi
  identificado como classificador uma vez porque algo leu o nome e adivinhou.
- **Arch válida E cabeça de classificação é o que carrega**, nunca um dos dois
  sozinhos. `gte-multilingual-reranker-base` tem a cabeça `[768]` perfeita e
  arch `new`, que não despacha em `llama-graph.cpp:3722-3757`. A lista de archs
  é **veto**, não condição: deixar um bom modelo de fora é seguro.
- **`relevance_score` é o logit cru e não muda.** É o contrato medido (spread
  2,0698, NDCG@10 0,9981) e o console lê o campo. A probabilidade entrou como
  `relevance_score_probability` ao lado.
- **`is_encoder` continua sendo `pooling != NONE` e não deve ser mexido.** Era
  exatamente esse o motivo pelo qual o jina sumia: arch válida, pooling `NONE`,
  `is_encoder: false`, nenhuma palavra na tela. Mudá-lo faria o servidor mentir
  que um modelo que embeda perfeitamente é encoder. O novo `isHeadless` (arch é
  encoder **e** pooling é NONE) é só para relatar.
- **`config.json` no HF é pre-flight, não reparo:** descreve forma e intenção,
  nunca peso. `general.tags` apareceu em 1 de 4 arquivos medidos.
- **`Column` com `mainAxisSize: max` como filho direto de `ListView`** lança em
  layout e leva a lista inteira, não só a linha. Já foi paid for em três
  lugares.
- **`ListTile` com `onTap` dentro de um `Container` decorado** levanta um
  `debugAssert` que **leva a lista inteira da tela**, sem exceção legível no log
  e com a app bar de cima funcionando. Use `Material`. Isso custou 8 builds e
  está fixado em `test/material_scaffold_test.dart` — leia o teste antes de
  criar um tile novo.
- **O catálogo de encoders é lido uma vez no boot** (`ModelController.onInit`) e
  as listas por papel guardam as **mesmas instâncias** que vão para
  `availableModels`. Filtrar o catálogo dentro do `build` aloca 10 objetos por
  frame.
- **Laya e OpenJev estão fora, com dados** — ver a seção 0.4.0 em
  [`docs/suggestions.md`](docs/suggestions.md). A 0.4.1 é TFLite do
  `litert-community`, e o APK **não** tem interpretador TFLite hoje.

Medido no Edge 60 com `gte-reranker-modernbert-base` (Q8_0): **111 ms por par**,
NDCG@10 **0,9981**, logits −0,1463 a +1,9235, sigmoid 0,4635–0,8725.

## Regras herdadas (aprendidas nas sessões anteriores)

- Base M1 = PrivateLM, já importada neste repo. Não recriar engine, plugins nativos
  (`local_plugins/*`) nem escada de aceleração do zero.
- O fork local `../privateLM` **não existe mais** (apagado, junto com o repo no GitHub).
  A referência é o upstream <https://github.com/orailnoor/cross-platform-llm-client>, e
  o que havia de trabalho só naquela pasta está registrado em
  [`docs/PRIVATELM_REFERENCE.md`](./docs/PRIVATELM_REFERENCE.md) — inclusive o bug de BOS
  duplicado no Llama-3.x, que provavelmente também vale aqui.
- De PocketStrike portar **padrões e catálogo**, não código Kotlin inteiro:
  `[TOOL_CALL]`, lazy registry, parser tolerante. A base já tem parser tolerante em
  `lib/services/tools/` — estender, não duplicar.
- Tool que escreve/envia/apaga exige **confirmação humana** na UI. Leitura pura pode ser auto.
- Agente multi-passo só atrás de toggle, com teto de iterações (modelos pequenos loopam).
- Nativo arm64-only; licenças MIT dos upstreams devem ser citadas (README/LICENSE já cobrem).
- **Flutter analyze não compila Kotlin.** Se remover imports de `MainActivity.kt`, o bug só aparece no `flutter build`. Verifique o Kotlin manualmente após qualquer alteração nos `.kt`.
- **Modelos custom adicionados via URL/search só são removidos da lista se o predicado
  `isStaleImport` em `refreshDownloaded()` olhar `isCustom` também.** O bug antigo
  deletava o arquivo do disco mas mantinha o entry no Hive, fazendo o modelo
  reaparecer depois de qualquer refresh. Corrigido em `0.2.4`: a condição agora é
  `(m.isImported || m.isCustom) && !files.contains(m.filename)`.

## Workspace

Pasta raiz via SAF + projetos como subpastas; conversa liga-se a um projeto por
`ChatSession.projectPath`. Detalhes, ciclo de vida e as armadilhas já pagas em
[`docs/WORKSPACE.md`](docs/WORKSPACE.md) — leia antes de mexer no picker, no
`WorkspaceService` ou em `createNewChat`.

## Alternativas de stack já avaliadas

**Llamatik** ([ferranpons/Llamatik](https://github.com/ferranpons/Llamatik), MIT,
`com.llamatik:library:1.10.1` no Maven Central) é uma biblioteca Kotlin Multiplatform que
embrulha llama.cpp + whisper.cpp + stable-diffusion.cpp numa API só, com multimodal por
`mmproj` e Multi-Token Prediction. Trocaria os três plugins vendorizados de
`local_plugins/` por uma dependência.

**Está parado, e a razão é concreta: Llamatik não fala LiteRT-LM.** Sem isso caem os
modelos `.litertlm` (5 dos 24 do catálogo, incluindo gemma-4 E2B/E4B) e toda a escada
NPU → GPU → CPU. Também não tem o dispatch por variante ARM
(`GGML_CPU_ALL_VARIANTS`) que evita SIGILL em aparelhos pré-2017. Manter um plugin
LiteRT à parte anularia o ganho de consolidar.

Estudo completo (em português) **na raiz do workspace**, um nível acima deste
arquivo: [`../docs/KMP_MIGRATION_ANALYSIS.md`](../docs/KMP_MIGRATION_ANALYSIS.md)
(começa por um fact-check datado), [`../docs/KMP_MIGRATION_PLAN.md`](../docs/KMP_MIGRATION_PLAN.md),
[`../docs/KMP_BUILD_LIMITATIONS.md`](../docs/KMP_BUILD_LIMITATIONS.md).

O `../` é o ponto. A forma antiga resolvia para `mobileLM-app/docs/`, que não os
contém — a prosa dizia "na raiz do workspace" e só quem já conhecia o layout
acertava o caminho. É a mesma classe do `HYBRID_CORE.md` ausente, e a mesma
regra: **um caminho num guia tem que resolver a partir de onde o guia está.** **Reabrir só se o Llamatik ganhar LiteRT** ou se o
caminho NPU for abandonado de vez.

## Tools privilegiadas (Shizuku)

Oito tools de leitura e settings que só existem quando há Shizuku. **O app nunca
chama `su` nem exige root** — decisão de produto. Detalhes, os quatro estados, a
regra de argv-nunca-string-de-shell e o teto de saída em
[`docs/SHIZUKU.md`](docs/SHIZUKU.md) — leia antes de mexer em
`privileged_commands.dart` ou no `ShizukuShell`.

## Identidade

Spec completa em `docs/brand/palette.md`. Ícone: `docs/brand/logo.svg`.
Dark-first, accent Volt `#B9F53E`, Pulse `#8B7CFF` com parcimônia.

## Comandos

```bash
cd mobileLM-app
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings   # 92 issues pre-existentes, 0 erros
flutter test                                           # único arquivo: flutter test test/x_test.dart
./tool/jni-syntax.sh                                   # sintaxe do JNI, ~8 s
flutter run --debug
flutter build apk --debug --target-platform android-arm64
flutter build apk --release --split-per-abi --target-platform android-arm64
```

**`tool/jni-syntax.sh` antes de qualquer push que toque `jni_wrapper.cpp`.**
`flutter analyze` não compila C++ nem Kotlin, e cada um dos dois erros que
apareceram só no CI custou um run de 22 minutos. O script compila o
`jni_wrapper.cpp` real contra o `llama.h` vendorizado, no alvo aarch64, com o
clang do NDK, em segundos. Ele **não** cobre Kotlin (não há `kotlinc` aqui) nem
link — o que ele cobre é o que o CI demora 22 minutos para dizer.

Ele usa o clang do NDK, não o `g++` do host: misturar os headers do NDK com a
libstdc++ do host dá `__GLIBC_PREREQ` quebrado e uma parede de erros que não tem
nada a ver com o seu código. E compilar para arm64 **é** possível nesta máquina
aarch64 — o `AGENTS.md` da raiz diz que as ferramentas do NDK são x86-64, o que é
verdade para *executar* o artefato e para linkar, mas um compilador cruz produz
saída aarch64 de um host x86-64 sem custo.

## Branch e commit

Trabalho e commits vão para a **`main`**. **Não existe branch `dev`** — este guia dizia
que existe desde que o fork foi importado, e não existe. `main` é o que trackeia
`origin/main`; sobraram só umas `pdf-markdown-*` locais.

A branch **`core/rust-hybrid` continua no remoto e não deve ser apagada** — é onde o
núcleo híbrido Rust está, em ~20 commits. Ele saiu do APK em 0.3.5, não do git; ver
[`docs/HYBRID_CORE.md`](docs/HYBRID_CORE.md) antes de mexer em qualquer coisa que
dependa dela.

**Minor = feature, patch = conteúdo.** Um catálogo maior não é feature. Antes de subir um
minor, escreva "isto faz X, que antes não existia" — se a frase não sai, é patch.

`0.4.0` foi o **suporte a embeddings, rerank e classificação** (BERT/ModernBERT,
servidos pelo `openai_server_service`): modelos que até 0.3.5 não rodavam nada no
app. A frase "isto faz X, que antes não existia" saiu verdadeira — os três
endpoints não existiam, e `/v1/classify` continua sem nenhum modelo do catálogo
usando, porque os classificadores queexists não são GGUF carregável (ver a seção
Encoders acima e a 0.4.0 em [`docs/suggestions.md`](docs/suggestions.md)).

**O classificador de verdade é a `0.5.2`, e a rota é TFLite.** Ele estava
reservado para a `0.4.1`, nunca existiu, foi absorvido pela `0.5.0` com o
pinning, e a `0.5.1` tomou a correção da escada de aceleração. Ele estava
reservado para a `0.4.1`, e a `0.4.1` nunca existiu — nem tag nem release — de
modo que a reserva foi absorvida pela `0.5.0` quando o pinning dos threads de
cálculo subiu como minor. Verificado antes de decidir: `gh release list` para
em `0.4.0`, e o APK não tem nenhuma lib TFLite e o catálogo não menciona
TFLite. Laya
(`litert-community/Laya-English-LiteRT`) vem como `.tflite`, não como GGUF, e o
APK **não tinha** interpretador TFLite — `liblitertlm_jni.so` é LiteRT-LM
generativo e não serve. Isso era a primeira coisa a resolver, e é por isso que
`/v1/classify` foi landado sem modelo atrás: o endpoint é o contrato, o modelo
vem depois.

⚠️ **Esse parágrafo descreve um estado que já passou, e ele se contradiz com a
seção "O runtime LiteRT (`.tflite`)" mais abaixo deste arquivo.** Naquele
momento o APK não tinha interpretador; **agora tem** — `local_plugins/litert_flutter/`
traz o LiteRT 2.2.0, e o act head real da Laya roda no A72 a 159 ms. O que
ainda não existe é o *host* (o encoder ModernBERT de 705 MB que produz as
features), que é trabalho de orquestração e não de aparelho: os 804 MB de pesos
cabem folgados no orçamento de `maxModelBytes` do A72 (1,19 GB). Ver
[`docs/HANDOFF.md`](docs/HANDOFF.md) §4.1, e leia o parágrafo acima como
"antes de resolver", não como o estado atual.

Todo commit em mobileLM-app deve ser **documentado** (pedido explícito do usuário) —
diferente do resto do workspace, onde commit só ocorre se pedido.

## CI e release

Três workflows ativos: `ci.yml`, `debug-apk.yml` (APK debug arm64 por push, ~22 min) e
`release.yml` (dispara na tag).

O `ci.yml` tem **um** job, `analyze` (analyze + test, ~2 min). Havia outros dois —
`rust-core` (fmt, clippy e testes do crate Rust) e `rust-core-android` (cross-compile
arm64 + `readelf -d`) — e saíram junto com o núcleo, em 0.3.5. Tinham de ser jobs
separados porque são toolchains diferentes: um erro de lint Dart e um `std` aarch64
faltando não têm relação entre si, e juntar os dois esconde qual quebrou. Vale
lembrar se algum dia houver outro toolchain aqui.

Nenhum workflow compila Rust hoje, e nenhum baixa artefato nativo. `debug-apk.yml` e
`release.yml` imprimem as `.so` arm64 que realmente entram no APK, o que é o jeito
barato de notar uma exclusão de `packagingOptions` ou um filtro de ABI — foi assim
que os 37,2 MB do `liblitert-lm.so` ficaram visíveis por semanas.

Release é por tag, e a tag tem que bater com a versão do `pubspec` **sem** o
`+build`: `0.5.1+2008` → tag `0.5.1`. O workflow falha de propósito se divergirem.
Tags com prefixo `v` (ex: `v0.3.0`) também são aceitas. As notas saem agrupadas por
prefixo de Conventional Commit; o que não casa com nenhum prefixo cai em "Other",
então nada some.

Release tags publicadas: `0.5.1` (a escada de aceleração passou a ver o tamanho do modelo), `0.5.0` (pinning automático nos núcleos grandes + benchmark de CPU corrigido), `0.2.3` (M4), `0.3.0` (cloud + métricas), `0.3.1` (exportar, chips, sumarização), `0.3.2` (PDF→markdown, clamp cloud correto, tools de arquivo removidas quando documento anexado), `0.3.3` (catálogo: LFM2.5-VL, Spark X2.5, Qwen3.5), `0.3.4` (release signed com a chave de verdade), `0.4.0` (encoders: `/v1/embeddings`, `/v1/rerank` e `/v1/classify`; 10 encoders no catálogo; console de encoder; parâmetros por papel; `config.json` como pre-flight no HF).

**A `0.3.5` foi preparada e nunca publicada.** O commit existe
(`ffd30471b`), o pubspec chegou a `0.3.5+2005` e este guia dizia que ela estava
publicada — mas a tag nunca foi para o remoto e não há release. O último APK
publicado é o da `0.3.4`, medido com `aapt2 dump badging`:
`versionCode='4004'`. O conteúdo da 0.3.5 (botão de ir para o final, núcleo
híbrido Rust removido do APK, tok/s de ponta a ponta) **entra na `0.4.0`**, e é
por isso que o número pulou de `+2004` para `+2006`: 4005 foi reservado e nunca
usado, e um build number pulado é inofensivo desde que o publicado só cresça.

Isso está escrito aqui porque é exatamente o modo de falha que este guia descreve
em cima: uma versão repetida em três lugares em prosa, uma delas errada, e nada
no repositório que reclame. Confirme sempre com `gh release list` antes de
descrever uma release como publicada.

**0.3.4 é a primeira release assinada com a chave do projeto** (`CN=dollarbr`, SHA-256
`1cd43cb7…`). Quem instalou uma das anteriores precisa **desinstalar** antes — o Android
recusa substituir por assinatura diferente, e desinstalar apaga modelos baixados,
histórico e workspace. Avisado no README.

Isso não é novidade: **as 7 releases anteriores têm 7 chaves de debug diferentes**,
uma por run do CI, porque o runner efêmero gerava um `debug.keystore` novo a cada
build. Nenhuma instalava por cima de outra — todo bump de versão já era desinstalar e
reinstalar. Verificado com `apksigner verify --print-certs` em cada asset. As chaves
antigas não existem mais; recriar as releases antigas não resolveria nada, porque quem
tem 0.3.3 instalado tem o APK assinado com uma chave que está perdida.

**O `versionCode` publicado NÃO é o `+build` do pubspec. É `+build + 2000`.**

Isso não é detalhe menor nem folklore: com `--split-per-abi` o FlutterPlugin
sobrescreve o versionCode por ABI (`FlutterPlugin.kt`,
`output.versionCodeOverride = abiVersionCode * 1000 + versionCode`), para que
APKs de ABIs diferentes possam coexistir. Os índices estão em
`FlutterPluginConstants.ABI_VERSION`:

| ABI | índice | `0.5.1+2008` sai como |
|---|---|---|
| `armeabi-v7a` | 1 | 3008 |
| `arm64-v8a` | **2** | **5008** |
| `x86_64` | 4 (o 3 foi reservado e removido) | 6008 |

O APK arm64 da 0.3.5 tem `versionCode='4005'`, medido com `aapt2 dump badging` —
`2 * 1000 + 2005`. Sem `--split-per-abi` o override não se aplica e o versionCode é
o número cru; é por isso que as releases antigas (2001, 2002, 2003) batem com o
build number e a 0.3.4 não bate. **Não compare pubspec com `dumpsys` sem essa conta.**

Regra prática: o que precisa crescer é o **publicado**. Os publicados até 0.3.3
foram 2002, 2003, 2001, 2001, 2001, 2001, 2001 — ad-hoc, e 0.2.1 (2001) é *menor*
que 0.2.0 (2003), uma regressão. O maior publicado é **5007** (0.5.0, medido), e
a 0.5.1 usa `+2008` e publica 5008. Daqui
em diante: bump de release ⇒ build number tal que `build + 2000` fique acima do
publicado anterior, senão o update falha com
`INSTALL_FAILED_VERSION_DOWNGRADE`.

**O núcleo híbrido Rust saiu do APK em 0.3.5.** O código continua na branch
`core/rust-hybrid` (não a apague); a decisão, as medições e a rota para retomar
estão em [`docs/HYBRID_CORE.md`](docs/HYBRID_CORE.md). **Leia a tabela de tags
desse documento antes de gastar um build de 22 minutos** — a pergunta deixou de ser
"dá para fazer o envio funcionar" e passou a ser "vale a pena", e a resposta tem
que enfrentar 37,2 MB e o fato de o caminho mais rápido do app já existir.

Os três motivos, em uma linha cada, porque são eles que decidem:

1. **A C API do LiteRT-LM mais nova que existe tem quatro tags.** `litert_lm_c_api`
   só existe na `v0.16.0`; a `v0.17.1` **é** a última versão e publica só
   `xcframework` da Apple. Consequência já vista, não hipotética: a rota C API não
   alcança um sampler, e `litert_lm_sampler_params_create(1)` devolve ponteiro
   não-nulo num runtime que não implementa o tipo 1 — a recusa chega 3 s depois, na
   geração. "O `create()` devolveu ponteiro?" não responde "este tipo existe?".
2. **A amarra não compra velocidade.** O engine é C++ e continua C++; 21,2 tok/s de
   prefill contra 3,4 no Vulkan é o engine, não o transporte.
3. **37,2 MB, e a flag desligada não era de graça.** `liblitert-lm.so` é a segunda
   maior lib do APK, e o `main.dart` fazia `dlopen` dela a cada cold start só para
   imprimir uma linha de log.

O que a remoção custou: `mobilelm_core::plan` era o dono da escada de aceleração, e
`planLiteRtTier` em Dart perguntava a ele. O corpo Dart puro voltou a ser o caminho
(é o mesmo código, sem a delegação) e continua coberto por
`test/acceleration_test.dart`. Nada se perdeu funcionalmente.

## ABI: arm64 e só

Não existe APK 32-bit, e o `README.md` já dizia o contrário (oferecia um
`armeabi-v7a` "cloud only") por anos. A regra, para não voltar:

- Todo workflow de build passa `--target-platform android-arm64`. Com
  `--split-per-abi` isso rende **um** arquivo. Sem o `--target-platform`, rende um
  `app-release.apk` gordo. Não remova o `--target-platform` achando que ele é
  redundante ao lado do split.
- Os três plugins nativos fixam arm64: `llama_flutter_android` e
  `sd_flutter_android` declaram `abiFilters 'arm64-v8a'`. O
  `llama_flutter_android/.../llama.cpp/examples/llama.android/lib/build.gradle.kts`
  também menciona `x86_64`, mas é código de exemplo do upstream que **não é
  compilado** por este projeto — não é evidência de nada.
- O alvo web (`web/`, no Firebase) **não é fallback**: `inference_stub.dart` não
  tem engine local, só providers cloud. Não escreva no README que 32-bit usa a
  web.
- Para conferir o que uma release entregou de fato:
  `gh release view <tag> --repo dollarbr/mobileLM --json assets`.

## Catálogo de modelos — como adicionar sem quebrar

Entradas em `AppConstants.availableModels` (`lib/core/constants.dart`). Os campos
que importam: `filename` (nome local), `url`, `size`, `description`, `template`
(rótulo apenas — o engine lê o chat template dos metadados do GGUF, em
`jni_wrapper.cpp` via `llama_model_chat_template`), `runtime` (`llama` | `litert` |
`sd`) e, para visão, `vision: 'true'` + `mmprojUrl` + `mmprojFilename`.

Duas regras que custam tempo se ignoradas:

- **O `mmprojFilename` tem que ser único.** O app baixa e guarda o projector por
  esse nome (`model_controller.dart`), não pelo nome do arquivo na URL. Os repos
  do Qwen3.5, por exemplo, publicam todos o projector como `mmproj-F16.gguf`, e
  dois modelos da mesma família sobrescrevem o projector um do outro em silêncio —
  195 MB virando 637 MB, com o modelo pequeno recebendo o projector do grande.
  Nome local específico, URL real.
- **Verifique a URL antes de commitar.** Um 404 só aparece na hora do download e
  não tem outro sintoma:
  `curl -sI "<url>" | grep -iE "^HTTP|content-length"` — o `content-length` tem que
  bater com o campo `size`. As 21 URLs do lote 2026-09-27 foram conferidas assim.

**Todo workflow que compila precisa liberar disco antes.** Os nativos vendorizados
— llama.cpp com backend Vulkan e seus ~300 objetos de shader, LiteRT, Stable
Diffusion — enchem os ~14 GB livres do runner com intermediários, e o release ainda
soma R8. O `release.yml` ficou a vida toda sem esse passo (nunca havia rodado) e
morreria em `No space left on device` na primeira tag; corrigido em `ea9a828`.

**Assinatura: release sempre com a chave de release, nunca com a de debug.**

O `build.gradle.kts` lança exceção em dois casos, e ambos são fatais de propósito:

1. `isReleaseBuild` e sem `GITHUB_ACTIONS`/`CI` — release só no CI.
2. `isReleaseBuild` e sem `android/key.properties` — **não há mais fallback para a
   chave de debug.** Um escape que existe é um escape que alguém ativa, e a falha
   que ele causa é invisível até alguém conferir um certificado.

Não reintroduza `MOBILELM_ALLOW_DEBUG_RELEASE_SIGNING`. Ele existia, o
`release.yml` o definia como `"true"` incondicionalmente, e por isso **todo APK
publicado até 0.3.3 saiu com `CN=Android Debug`** — ou seja, falsificável, já que
a chave de debug é pública. Os três secrets `RELEASE_*` estavam configurados no
repo e nenhum workflow os lia. O keystore nunca esteve errado; ninguém o usava.

Hoje o `release.yml` materializa o keystore dos secrets, e o passo
"The APK is signed with the release key" confere **três** coisas no APK pronto:
o SHA-256 do certificado tem que ser `1cd43cb7…`, não pode ser
`CN=Android Debug`, e tem que haver exatamente 1 signer.

O pin do fingerprint é o que importa e o que é fácil de não entender. As outras
duas checagens **passam tranquilamente para uma chave nova** — que é exatamente a
forma do bug original: uma release que compila, assina e fica verde sendo assinada
pela chave errada. Testado com um keystore descartável de mesmo DN
(`CN=dollarbr, OU=mobileLM, O=mobileLM, C=BR`) e fingerprint
`1904a3bc…`: a checagem antiga aceitava, a nova rejeita. Só o fingerprint separa
"a nossa chave" de "alguma outra chave que não é de debug".

É essa checagem que converte "toda release da 0.3.4 em diante é assinada com a
mesma chave" de algo que precisa lembrar para algo que o build exige. **Rotacionar
a chave de propósito significa mudar o `EXPECTED_CERT` no mesmo commit que troca o
secret** — e essa fricção é o ponto, não um obstáculo. A chave e a senha também
estão no Bitwarden, na entrada `mobileLM` (keystore em base64 num campo, porque
anexo é feature Premium).

O alias da chave é **descoberto do próprio keystore** no CI, não guardado num
quarto secret — um secret que precisa ficar em sincronia com um arquivo acaba
dessincronizando, e um alias errado aparece como "keystore password was
incorrect", indistinguível de senha errada. E a descoberta parseia a saída
**não-verbose** de `keytool -list`: a verbose é traduzida ("Nome do alias:" em
pt_BR), a linha de entrada `alias, <data>, PrivateKeyEntry,` não é.

**Os três secrets vivem no environment `release`, não no repositório.** E o job
declara `environment: release`. Duas coisas decorrem, e as duas são o ponto:

- Só um job que declara aquele environment lê os secrets. No nível de repositório
  eles eram visíveis para **todo** workflow do repo, inclusive o `debug-apk.yml`,
  que roda a cada push.
- O environment tem política de ref customizada **só para tags**. Push em branch
  não chega perto da chave. Verificado: um run disparado por branch é rejeitado
  em 2s com `Branch "..." is not allowed to deploy to release due to environment
  protection rules`, e um disparado por tag abre os secrets e o certificado confere.

`gh secret list --repo` deve voltar **vazio**. Se aparecer algo ali, o environment
não está protegendo nada.

**Required reviewers NÃO funciona neste repositório.** A API responde `App not
installed on organization`: revisão obrigatória em environment é feature de
organização, e `dollarbr/mobileLM` é de conta pessoal. A restrição por tag cobre
o cenário concreto (alguém faz push), mas não dá o portão humano que um org
permitiria. Se um dia o repo mover para uma org, vale adicionar.

**Secret scanning está ligado** (`secret_scanning` e
`secret_scanning_push_protection`, ambos `enabled`). Grátis em repo público, e é a
rede contra alguém um dia fazer `git add -f` de um secret.

Debug APK continua com chave de debug — é o correto, elas não são distribuídas e
precisam instalar por cima de qualquer build.

## Aparelhos de teste

| Aparelho | Papel | Regra |
|---|---|---|
| **Galaxy A72** (SM-A725M, Snapdragon 720G / SM7125, **/e/OS e-4.3, Android 15**, 5,6 GB, `adb root`) | **debug** — é onde tudo é medido | recebe debug à vontade. A tela dele **estraga**: a imagem aparece mas o touch não responde, então tudo é feito por comando adb, nunca por toque. Não é quebra do aparelho e não é reparável aqui. |
| **Motorola Edge 60** (Dimensity 7300, Mali-G615) | **só release** | nunca instalar debug. Instalar debug sobre uma release significa trocar a assinatura → desinstalar → perde modelos, histórico e workspace. É por isso que a 0.4.0 ficou um ciclo inteiro sem conseguir testar no Edge 60. |

Medir no A72 é a escolha certa mesmo sendo mais fraco: um número que sai dele é um
piso, não uma média.

## Onde as threads de cálculo ficam (leia antes de mexer em afinidade)

**O app prende os workers de cálculo do ggml nos núcleos grandes, sozinho.** Um
230M no Galaxy A72 respondeu a **6,5 tok/s** sem isso e **18,0 tok/s** com, no
mesmo build e na mesma ROM, minutos separados.

O ganho **não é de clock**. `time_in_state` do cpu6 do A72 tem **3.811.046
ticks em 652.800 Hz contra 39.018 em 2.323.200** — o cluster quase nunca sai do
piso, preso ou não. O que muda é a **utilização**: `schedutil` decide frequência
pela utilização *por núcleo*, dois threads soltos em oito núcleos deixavam cada
A76 lendo quase zero, e presos os dois A76 leem ~50%. **Cortar frequência não
resolve** — é o que a tentativa anterior fez, e não fez nada.

Três coisas que contrariam o suficiente para valerem o comentário no código:

1. **`cpumask` é indexado por WORKER, não por núcleo.** Com `strict_cpu = 1`,
   `ggml_thread_cpumask_next` (`ggml-cpu.c:2723`) dá ao worker *j* o *j*-ésimo
   bit ligado — **um núcleo por worker**. Escrever `cpumask[0..n_threads-1] =
   true` prende os dois workers no cpu6 e eles serializam.
2. **`ggml_threadpool_new`/`_free` não linkam.** Moram em
   `libggml-cpu-android_armv8.*.so`, carregada por `dlopen`; a chamada direta dá
   `ld.lld: undefined symbol`. Vêm do registro CPU por
   `ggml_backend_reg_get_proc_address`.
3. **A máscara é lida com `int`, e `int` desloca.** Qualquer `cpu >= 32` dá
   deslocamento indefinido e o hardware guarda os bits baixos, então uma máscara
   de 0xC0 reportava 18 membros: `6,7,38,39,70,71,102,103,134,...`. Só limitar
   o laço pela largura da máscara resolve; `1ULL` **não** resolve, porque
   `1ULL << 70` também é indefinido. E `1 << cpu` sobre um `cpu_set_t` de 1024
   bits, em `buildCpuSet`, era permissão para **rodar em** 18 núcleos — o oposto
   de pin.

Rota: `llama_attach_threadpool(ctx, pool, pool_batch)`, API pública do
`llama.h` vendorizado (linha 491). **Nenhum arquivo vendorizado foi alterado.**

Escopo, deliberado: só na contagem **automática** (uma contagem digitada em
Settings é override do usuário) e só no caminho **GGUF**. O LiteRT não tem
gancho equivalente aqui — todo o pinning vive em `jni_wrapper.cpp` e o caminho
LiteRT passa por `liblitert-lm.so`, sem acesso a nenhum daqueles símbolos.

**Isso deixou de ser uma nota de escopo e passou a ser a explicação de um número
medido.** O backend de CPU do LiteRT roda **sem pin**, e o pinning sozinho vale
2,8× neste aparelho. Medido: LiteRT 0.6B na CPU dá 3,0 tok/s contra 18,6 que um
GGUF do mesmo tamanho daria pela lei `k/parâmetros` — os 6,2× de diferença que
restam são kernels, não thread. Ver "O micro-benchmark do LiteRT" abaixo.

Medido: 1 thread dá 11,6 tok/s e 2 dão 18,0. A hipótese de que 1 thread ganharia
— 100% de um núcleo parece melhor ao `schedutil` do que 50% — é **medida e falsa**.

## O benchmark de CPU é melhor-de-N, e por quê

`measureGeneration` roda o modelo **até três vezes e fica com a melhor**, porque
a primeira run depois de abrir o processo não é a velocidade do aparelho. Mesmo
processo, mesmo modelo, mesmo build, runs separadas por segundos:

| run | prefill | tok/s | 1º token |
|---|---|---|---|
| 1ª | 2.820 ms | **0,2** | 71,4 s |
| 2ª | 137 ms | **17,4** | 0,7 s |

**87×**, e a causa é o governor, não o engine. Isso importa mais do que parece
porque é o número que decide se o app oferece esconder o catálogo local: um
usuário que instala e toca no botão uma vez seria dito 25× mais lento do que é.

**Um warm-up contado em tokens não resolve, e isso foi medido:** 8 tokens de
warm-up deram 0,3 tok/s, porque 8 tokens na taxa fria são 23 s e o rampa é mais
longo que isso. As tentativas **são** o warm-up. Melhor-de-N é o erro na
direção certa: subestimar custa os modelos do usuário, superestimar custa uma
ideia errada sobre o próprio telefone.

Dois erros de medição que existiram e que só o aparelho mostrou:

- **TTFT era o tempo total usando o rótulo** — `gotFirst` era um `bool` e o
  stopwatch era lido depois da geração inteira.
- **Tokens eram palavras** — `split(RegExp(r'\s+')).length`. Só corrigir isso
  levou o mesmo aparelho de 17,4 para 32,0 tok/s.

Contar por `onToken` é correto porque o engine chama uma vez por token que ele
contou, então a assinatura dele não precisou mudar.

## O micro-benchmark do LiteRT: a pergunta mudou de forma

`planLiteRtTier({required String mode, required bool npuAvailable})` devolve
NPU → GPU → CPU e, **até esta medição, nunca tinha medido nada**. Para o GGUF isso
foi consertado pela faixa de tamanho, que é extrapolação acima de 1B; para o
LiteRT não havia nem isso, porque a escolha era feita antes de qualquer número
existir.

**Um modelo foi medido nos dois backends, e a resposta é "sempre GPU" — por 27%.**

| LiteRT Qwen3 0.6B | TTFT | decode |
|---|---|---|
| `cpu_safe` → `backend=cpu` | 4,58 s | **3,0** tok/s |
| `auto_fast` → `backend=gpu` | 2,94 s | **3,8** tok/s |

As quatro amostras de cada lado são idênticas (`3.0 3.0 3.0 3.0` e
`3.8 3.8 3.8 3.8`), porque a GPU não passa pelo rampa do governor que a CPU
sofre. E o que motivou o A/B foi um **erro meu na documentação**, não uma ideia
nova: eu tinha escrito que a GPU era 8× mais lenta que a CPU aqui, comparando o
LiteRT-na-GPU com os GGUFs-na-CPU — o que compara **dois runtimes**, não dois
backends. A tabela de medição do catálogo traz a correção completa.

**O que isso muda sobre a pergunta original.** A versão anterior desta seção
pedia um micro-benchmark que escolhesse o backend por aparelho e por modelo. Ele
não faria o que se esperava: escolheria GPU, e o LiteRT continuaria **6,2× mais
lento que o llama.cpp** para o mesmo tamanho de modelo. O gargalo não é a escolha
do backend, é o engine.

Se ainda assim for implementado, o que já está medido e precisa ser respeitado:

- **A carga é o custo, não a geração.** Comparar CPU e GPU de verdade significa
  carregar duas vezes. E o LiteRT tem fallback **nativo** — `Backend.{cpu,gpu,npu}`
  mapeado em Dart→Kotlin, com NPU→GPU→CPU do lado nativo. Então "pedi GPU" e
  "rodei na GPU" não são a mesma coisa, e o AGENTS desta arquivo já diz: reportar
  o backend **real**, não o tier pedido. Um micro-benchmark que mede o fallback
  em vez do pedido mede a coisa errada.
- **A primeira run é 87× mais lenta** (medido, ver acima). O benchmark de CPU
  descarta; o do LiteRT teria que descartar do mesmo jeito, senão ele mede o
  ramp do governor e escolhe o backend errado — que é o pior jeito de errar.
- **O NPU é o caso perigoso.** No Edge 60 ele é inalcançável a nível de driver
  (o linker namespace bloqueia `libneuron_adapter_mgvi.so`) e no MT6878 não há
  prova. Benchmark de NPU pode ser ruído, e ruído aqui vira escolha de backend.
- **O ganho do GGUF foi de 4-6×.** Se o LiteRT der 1,1×, um micro-benchmark que
  roda a cada carga custa mais do que ele informa. **O medido foi 1,27×** — dentro
  dessa faixa, e por isso a resposta honesta para GPU é "sempre GPU, e é isso".
- **Um número só não generaliza.** Os outros 4 `litert` do catálogo não foram
  medidos e nenhum é um 0.6B. A lei `tok/s ≈ k/parâmetros` foi ajustada em GGUF;
  a LiteRT pode ter outra curva, e a diferença entre os dois engines é
  estrutural (o LiteRT não alcança o pinning, que vale 2,8× sozinho), não uma
  constante que valha entre modelos.

## A memória mostrada é `MemAvailable`, e no A72 isso é 4×

O card de memória na tela de Modelos mostra o que o telefone pode entregar
agora. A escolha de `MemAvailable` em vez de `MemFree` não é preferência de
estilo — no aparelho de teste ela muda a resposta:

| | A72, `/proc/meminfo` real | lido como "livre" |
|---|---|---|
| `MemFree` | 641.596 kB | **12,8%** → "modelo grande vai falhar" |
| `MemAvailable` | 2.430.788 kB | **48,5%** → folgado |

`MemFree` exclui cache reclamável, então num telefone ocioso ele lê baixo com
memória de sobra. Usá-lo faria o card avisar que um modelo não carrega num
aparelho com 2,4 GB disponíveis — um aviso falso, que é pior do que nenhum,
porque o usuário troca de modelo à toa. A barra é `MemTotal - MemAvailable`,
que é o que o low-memory killer do próprio Android raciocina; o limiar de
**15%** é onde um modelo de 1-2 GB deixa de caber e a carga falha de vez, em
vez de ficar lenta.

A aritmética é pura e testada em `lib/services/memory_readout.dart` (17 testes,
`test/memory_readout_test.dart`), pelo mesmo motivo de `acceleration.dart` ser
pura: as três afirmações que podem estar erradas em silêncio — legível, apertado,
qual fração — ficam fora do alcance de um aparelho. O serviço só busca o texto;
`getMeminfo()` devolve `/proc/meminfo` **cru** e o parser faz o resto. Uma
versão anterior devolvia bytes já parseados e o serviço re-serializava para o
parser ler de novo — um passo inútil no meio, no caminho quente de um timer de
2 s.

iOS e web **não têm o card**: não há `/proc`, e o `deviceLocalMemoryBytes` do
plugin é o heap local do aparelho, não RAM física. Reportar como "total" seria
uma mentira que o card não conseguiria detectar depois.

O poll liga e desliga com o que está acontecendo, não fica rodando: é um
leitor para assistir a uma carga, não um painel. E ele mora no `State` do
widget, não no `build` — iniciar timer de dentro de `build` é o mesmo erro do
`setState() during build`, só que falha mais quieto: vaza um timer por rebuild
em vez de lançar.

## O card do benchmark: `Wrap`, e por que o `Row` estourava

As três ações do veredito ficavam lado a lado numa `Row` sem `Expanded` nem
`Wrap`: "Hide the local model list", "Show it anyway" e "Keep models anyway".
A combinação mais longa são três frases em inglês numa linha, sem nada
limitando nenhuma delas, num card que fica no meio da lista de modelos — então
o overflow horizontal **leva o catálogo inteiro**, o mesmo formato dos outros
dois casos já registrados acima.

`Wrap` é a correção certa e não só a que não estoura: são alternativas, e
empilhá-las diz isso de um jeito que três botões deitados não dizem.

`test/benchmark_card_layout_test.dart` fixa o caso a **360 dp com texto a 2×**,
mais estreito que os ~393 dp do A72, e o último teste é o que **prova que o
harness é hostil o bastante**: ele afirma que a `Row` *estoura*. Se ele um dia
passar, as larguras deixaram de ser hostis e os outros três testes deixaram de
provar nada.

Duas armadilhas do próprio teste, que custaram um run cada e valem para
qualquer teste de layout aqui:

- **`ListView` é lazy.** Com uma dúzia de linhas antes do card ele nunca é
  construído, toda asserção passa no vazio e o teste do `Row` falha porque nada
  renderizou. Card no topo — que é a ordem real da tela.
- **Escala de texto vai pelo `platformDispatcher`, não por um `MediaQuery` na
  mão.** Um `MediaQueryData(textScaler: ...)` novo zera todos os outros campos,
  tamanho incluído, e a subárvore leia contra uma viewport de tamanho zero. O
  sintoma é "os botões sumiram". E `textScaleFactorTestValue` conflita com os
  overrides de `tester.view` usados para o tamanho, deixando a árvore
  não-construída. O caminho que funciona é `MaterialApp(builder:)` com
  `MediaQuery.of(context).copyWith(...)`.

## A API local também controla os modelos — e três coisas que só o aparelho mostrou

`GET /v1/models/local`, `POST /v1/models/{download,load,unload}`. A superfície
existe porque **medir o catálogo é a parte lenta**: nove modelos para baixar,
carregar e interrogar, cada um com um diálogo de confirmação que só um humano
pode responder. Tudo isso vira `curl`.

`/v1/models` continua **exatamente** o contrato OpenAI — só o modelo carregado.
Um cliente que encontrasse as 62 entradas do catálogo ali tentaria usar todas e
tomaria 404 na primeira geração.

**Nada bloqueia.** Download de 2 GB são minutos; uma carga no A72 mediu 25 s de
primeiro token e 60 s de orçamento de prefill. Um request que pendura esse
tempo é um timeout no cliente, e timeout é indistinguível de queda. Tudo
responde `202` e se acompanha em `GET /v1/models/local`. **Conflito é recusado,
nunca enfileirado**: carregar durante uma geração chega ao engine como duas
coisas ao mesmo tempo e o sintoma é um modelo que responde besteira.

O relatório traz `backend`, que é o **real** — `loadedBackend`, não o tier
pedido. LiteRT cai NPU → GPU → CPU no nativo, então "pediu GPU" e "rodou na GPU"
são coisas diferentes, e relatar o pedido seria relatar um desejo.

### `load` exige `accept_risk`, e `unload` é recusado

`loadModel` mostra um diálogo de memória. Ninguém o responde por HTTP, e as duas
respostas erradas são ruins: deixar o diálogo em pé prende o cliente para sempre,
e deixar `loadModel` correr sem decisão **libera o modelo antigo e não carrega
nada** — foi o que a primeira versão fez, respondendo 202 num aparelho que ficou
sem modelo. Agora `POST /v1/models/load` sem `accept_risk` devolve `409`
explicando, e com ele pula **só os dois diálogos**; todos os guardas continuam
rodando e continuam recusando (arquivo incompleto, safetensors inválido, LiteRT
inválido, memória insuficiente). O flag representa o toque em "Load", que é a
única coisa que se pedia a uma pessoa.

`unload` é `409` **de propósito**: `ModelController.unloadModel()` chama
`_stopServerForMissingModel()`, porque sem isso os endpoints continuam
respondendo 200 sem nada atrás e `capabilities` continua dizendo
`running: true`. Responder antes de parar não salva — o socket fecha antes do
flush e o cliente vê `Empty reply from server`, sem código HTTP nenhum, que é
por que o `curl` daqui reportava `000`. A assimetria é real e intencional:
**carregar mantém o servidor no ar** (`InferenceService.unloadModel` é o
primeiro passo de toda carga e não toca no servidor), então é `load` que troca
modelo — e é nele que a campanha inteira roda.

### A resposta vai antes da operação

Chamar `unawaited(controller.loadModel(...))` e **depois** escrever o 202 prende
o isolate do Dart — é uma chamada JNI síncrona — antes de o socket ter algo
para enviar. Medido: `000` em toda requisição que disparava operação real
(`load` com `accept_risk`, `unload`), enquanto o `409` — que responde e só então
descobre que o corpo está errado — funcionava. Isso isola a causa: não era o
POST, nem o forward, nem o servidor; era a ordem. `GET` respondia o tempo todo
porque nada bloqueava. Agora é resposta, um turno do event loop, e só então a
operação.

## O servidor sobe sem modelo — e por que a troca de runtime é recusada

O toggle recusava: "Load a local GGUF or LiteRT-LM model first". Era circular
depois que a API ganhou gestão de modelos — **o servidor é como se carrega um
modelo pela rede**, então exigir um modelo para subi-lo impede a feature de se
inicializar sozinha, e um cliente que quisesse trocar de modelo tinha que ir
até o telefone. O portão saiu.

O que substitui o portão são recusas que já existiam e são melhores que uma
porta fechada: `_localModelError` para geração e `_encoderUnavailable` para
embeddings/rerank/classify. Um servidor no ar que reporta `loaded: null` e
responde 400 com uma frase é melhor do que uma porta que não está escutando.

A mensagem de recusa **nomeia o caminho por onde sair**, que agora é o próprio
HTTP: `POST /v1/models/load` com um filename de `GET /v1/models/local`. Um
cliente que não sabe que existe um toggle num telefone que não está na mão
recebeu a instrução errada.

A tela do servidor deixou de dizer "requires a loaded model" — isso
contradiria o toggle duas linhas acima que agora funciona. Sem modelo, os
primeiros exemplos são os de gestão, que são os que funcionam.

### `load` entre runtimes diferentes é recusado, e era um `202` que não fazia nada

GGUF roda num `.so` e LiteRT-LM em outro. A sessão se amarra a um deles na
primeira carga e não troca sem restart — `_sessionNativeRuntime`. Isso não é um
aviso, é um fato sobre o processo, e a resposta de `loadModel` era um terceiro
diálogo.

O primeiro sintoma: `POST /v1/models/load {"filename":"Qwen3-0.6B.litertlm",
"accept_risk":true}` respondia **`202 accepted`** e 24 s depois o GGUF seguia
carregado e o LiteRT nunca carregou. **Um 202 que não é seguido da coisa que
promete é pior que uma recusa** — o cliente acredita que vai ter aquilo. Agora é
`409` dizendo qual runtime seria preciso, qual a sessão está usando, e que o
caminho é reiniciar e repetir (depois de um restart não há runtime de sessão, e
carrega sem pedir restart). E o modelo carregado **não é tocado** pela recusa.

Medido no A72, partida a frio, 19 verificações e zero falhas:

| | |
|---|---|
| servidor sem modelo | sobe, `/health` 200, `loaded: null` |
| os 5 endpoints que precisam de modelo | 400 cada um, com o caminho na mensagem |
| `capabilities` sem modelo | `{}` — não promete nada |
| `load` de GGUF pela API | 202, carrega em 3 s, `backend=cpu gpu_layers=0` |
| `load` de LiteRT pela API | 202, carrega em 6 s, **`backend=gpu`** |
| `unload` | 409, e o servidor fica de pé |
| `load` entre runtimes | 409, e o modelo carregado continua |
| chave | 401 sem / 401 errada / 200 certa / 200 com `bearer` minúsculo |
| `gemma-3-270m` baixado pela API | aparece como `downloaded` |

O `backend=gpu` do LiteRT contra o `backend=cpu` do GGUF de 142 MB é a
assimetria que a seção do micro-benchmark do LiteRT descreve, agora vista de
um jeito que a API torna reproduzível: `planLiteRtTier` sempre prefere GPU,
`planAcceleration` mantém GGUF pequeno na CPU.

**Essa assimetria é a que confunde, e a API é o jeito de sair dela.** Os dois
`backend` são a resposta certa a perguntas **diferentes**: `gpu` no LiteRT é um
modelo de 586 MB rodando a 3,8 tok/s, e `cpu` no GGUF é um modelo de 142 MB
rodando a 49,3. Comparar os dois números como se fossem o mesmo eixo foi
exatamente o erro que produziu "a GPU é 8× mais lenta que a CPU" nesta
documentação. A tabela com os dois backends do **mesmo** arquivo LiteRT está na
seção do micro-benchmark, e é a única comparação que responde à pergunta.

## `stream: true` não fazia streaming, e o watchdog entre tokens cortava a resposta

Dois defeitos que só apareceram quando a medição do catálogo passou a usar a
API — e os dois se anunciam como "o modelo é lento", que é a conclusão errada.

### `stream: true` devolvia a resposta inteira no fim

O handler já escrevia um chunk por token, via `onToken`. O cliente recebia
**uma** chunk e o `[DONE]`, ambos no mesmo instante:

```
t= 25.86s  data: {"id":"chatcmpl-...","choices":[...]}
t= 25.86s  data: [DONE]
```

25 segundos de espera e depois a resposta inteira, que é o oposto de streaming.
A causa é o buffer do `HttpResponse` do Dart: `write()` enfileira e o que vai
para o socket sai no `close()`. Com `bufferOutput` no padrão — e ele nunca era
 mexido em lugar nenhum do arquivo — os chunks ficavam na fila até o fim.
`response.bufferOutput = false` antes do primeiro `write` resolve, e a medição
depois do conserto:

```
t= 8.00  8.12  8.41  8.62  8.82  8.94  9.23  9.34  9.64  9.73   -> 25 tokens
```

Importa por dois motivos, e o segundo é o que a medição dependia: um cliente
que usa streaming por latência percebida não recebia nada mais cedo, e **não
havia como medir TTFT pelo stream** enquanto isso.

### O watchdog de 5 s entre tokens truncava a resposta em 1 token

O menor modelo do catálogo, **SmolLM2 135M**, respondia com exatamente uma
palavra. Sempre. O log dizia `Sampled token 1` e 4,6 s depois
`Idle timeout — 1 tokens`.

Não era o modelo nem o engine. Os dois núcleos grandes estavam no **piso**:
`652.800 Hz` de `2.323.200`, governor `schedutil`, `/proc/loadavg` em `0.00`.
No piso o segundo token leva mais de 5 s, o watchdog dispara e a geração
termina.

O número estava errado de um jeito que não se vê no código: **5 s parece
generoso para "por token", e é.** O que o watchdog tenta distinguir é *engine
travado* de *engine lento*, e a diferença é que um engine travado não produz
token **nunca**, enquanto um lento produz um a cada 8 s. Cinco segundos não sabe
dizer as duas coisas, e escolher o lado errado corta a resposta do usuário.
Subiu para **30 s**: um watchdog existe para pegar travamento, não para impor
velocidade. Quem impõe velocidade é o `prefillBudget` de 60 s, que conta os
tokens como um todo — e se um token leva 25 s neste aparelho, a resposta já foi
declarada perdida há muito tempo, e aí o que importa é a mensagem de erro, que
diz para escolher um modelo menor.

Depois do conserto, no mesmo aparelho e nas mesmas condições: **25 tokens**.

### O número de tok/s que sai daqui depende do clock, e isso não é detalhe

| | A72, núcleo no piso | A72, núcleo rimado |
|---|---|---|
| SmolLM2 135M, decode | **4,8-5,0 tok/s** | — |
| TTFT | 8 s | — |
| LFM2.5 230M, medido antes em sessão quente | — | **18,0 tok/s** |

Fator de quase 4× no mesmo aparelho, no mesmo modelo, sem nenhuma alteração no
código — só o clock. `schedutil` decide frequência pela utilização *por núcleo*,
e duas threads com uma pausa de alguns segundos entre pedidos não sustentam
carga o bastante para rimar.

**Consequência para a campanha: medir com pausas entre pedidos mede o governor,
não o modelo.** O protocolo certo é pedidos **consecutivos sem pausa** e melhor
de N, que é a mesma conclusão a que o `AGENTS.md` já chega para o benchmark de
CPU — "o rampa do governor é medido em segundos de carga, não em tokens". A
medida por request isolado que eu comecei a usar está errada por construção, e
vale mais estar escrito aqui do que refazido.

## Decision models (Tev1, Bespoke-Nimble) — o que é possível e o que não é

Não são modelos de chat. São classificadores fine-tuned para emitirem **uma
letra**, com uma interface de decisão: um system instruction, um `state`, uma
`question` e 2–24 opções.

**A análise de Laya e OpenJev não se aplica a eles, e vale dizer por quê** —
porque "mesma categoria" costuma significar "mesmo motivo para estar de fora", e
aqui não é. O que excluía Laya era específico: `general.architecture = "ggmlc"`,
fora dos nomes que o llama.cpp vendorizado conhece, e **zero** tensores `cls.*` —
a cabeça existe mas está em `ggmlc.graph_spec`, estruturalmente incompatível com
o `mul_mat` que `llama-graph.cpp` faz. OpenJev era 28,6 GB em Q8_0. Tev1 é um
`qwen35` comum, que emite uma letra como token seguinte. Categoria igual,
mecanismo completamente diferente, e por isso ele **entra**.

### Tev1-0.8B: funciona, medido no A72

Fine-tune de `Qwen/Qwen3.5-0.8B` (Together AI). Conferido antes de baixar os
774 MB, lendo o cabeçalho do GGUF por `Range` — `gguf_header.py` no
`~/.cache/mobilelm-tools/`. A regra do catálogo é conferir a URL antes de
entrar, e descobrir que a arch não é suportada depois de 774 MB é derrota:

```
architecture : qwen35          -> LLM_ARCH_QWEN35, existe no vendorizado
qwen35.block_count 24 | embedding_length 1024 | heads 8 / kv 2
```

Carregado pela API no Galaxy A72:

```
POST /v1/models/load {"filename":"tev1-Q8_0.gguf","accept_risk":true}  -> 202
backend=cpu  gpu_layers=0  gpu=Adreno (TM) 618
```

`gpu_layers=0` com a GPU presente é a regra de tamanho da 0.5.1 funcionando: 774 MB
fica abaixo de 1280 MB, então a CPU — que a medição do Edge 60 diz ser 4× mais
rápida nesse tamanho.

Resposta à interface de decisão, três tickets, `max_tokens=12`, `temperature=0`:

| entrada | esperado | saiu | |
|---|---|---|---|
| "checkout devolvendo 500 desde 9h" | B (bug) | **A** | errou |
| "foi cobrado duas vezes pelo pedido #4417" | A (billing) | **A** | ok |
| "esqueceu a senha e não entra na conta" | C (account) | **C** | ok |

**1,1 s de primeiro token, 10,8–11,0 tok/s de decode**, com os núcleos no piso —
o mesmo 652 MHz em que o SmolLM2 135M fazia 4,8 tok/s. A saída é sempre
`<think>\n\n</think>\n\n<LETRA>`: um bloco de pensamento **vazio**, quatro
tokens jogados fora, e a letra. O README pede `enable_thinking: false` e o app
não envia; com o bloco vazio é inofensivo, mas são 4 tokens numa resposta que
cabe em 1.

O erro no 500 é do modelo, não da integração: um classificador de 0.8B
experimental. O README avisa que o modelo pode estar errado e que o
calibramento não foi avaliado.

### Bespoke-Nimble-9B: não, e não por falta de teste

`provenance.json` diz `artifact_type: "PEFT LoRA adapter"`, `peft_type: LORA`,
r=16, 12 módulos alvo, sobre `Qwen/Qwen3.5-9B` numa revisão pinada. O repositório
tem **165,2 MB de pesos** — é o adaptador, não um modelo. Para rodar é preciso
mesclar o adaptador na base, e a base em Q4_K_M são ~5,5 GB antes de qualquer
cache.

O A72 tem 5,6 GB. A escada recusaria, com razão. O Edge 60 (até 12 GB) caberia,
mas produzir isso é trabalho de mesa — baixar a base, mesclar, quantizar — e o
app não tem suporte a adaptador: `loadModel` recebe um caminho de GGUF único.
Não é entrada de catálogo; no máximo é "importar um GGUF já mesclado", e mesmo
assim são 5,5 GB.

### Os 4 passos que o Tev1 exigia, e o que eles viraram

Isto estava aqui como plano. **Está feito e medido** — a seção "A superfície de
decisão" mais abaixo tem os números. O que fica são as três decisões que os
passos produziram e que ainda valem como regra:

1. **montar o prompt** — `state` vai dentro de um envelope JSON, não em prosa.
   Um ticket de suporte com aspas e chaves mudaria a forma da pergunta, e um
   decision model é exatamente o modelo para o qual se alimenta texto não
   confiável. Ver `decision_model.dart`.
2. **`temperature: 0` e o pensamento desligado** — `generate()` ganhou
   `temperatureOverride` e `maxTokensOverride` para isso, porque nenhum dos dois
   pode vir do Settings. Temperatura 0 é o que torna a decisão reprodutível; o
   `/no_think` é a convenção que o `chat_controller.dart` já usava, reaproveitada
   em vez de reinventada.
3. **mapear a letra de volta** — `parseDecisionAnswer`, e o `<think>` é removido
   **antes**, porque uma letra dentro da deliberação do modelo não é a resposta
   dele. O Tev1 escreve `<think>\n\n</think>\n\nB` e um parser de primeira letra
   devolve `t`.
4. **não inventar confiança** — `relevance_score` é `null` e `scores` mapeia
   tudo para `null`, com um `why_no_scores` na resposta. As probabilidades do
   Nimble vêm da camada de serviço dele, não dos pesos.

O caminho foi estender `/v1/classify` e não criar um endpoint novo, como estava
previsto: o contrato já existe e o `AGENTS.md` diz que o endpoint é o contrato.

**O que continua pendente é de licença, não de código** — e é por isso que o Tev1
**não** é entrada de catálogo. A licença diz "being finalized", o que impede
colocar num app distribuído (não impede um build pessoal); não há Q4, só Q8_0 de
774 MB e f16 de 1,4 GB; e o GGUF vem de um repositório de comunidade com 0
downloads, então a conversão não foi verificada por terceiros. Nenhuma dessas três
se resolve com código.

**O que a integração não precisou:** o app reconhece sozinho um `.gguf`
desconhecido que apareça no diretório de modelos — `refreshDownloaded` o registrou
como entrada 63, com o tamanho certo, sem nenhuma linha de código nova.

## O catálogo medido no A72 — seis modelos, e a curva não é de tamanho

Galaxy A72 (SM-A725M, 2×A76 pinados, /e/OS e-4.3), melhor de 3, pedidos
consecutivos **sem pausa** entre eles. Medido pela API, com streaming.

| modelo | tamanho | backend | layers | TTFT | decode | amostras |
|---|---|---|---|---|---|---|
| LFM2.5 230M (Q4_0) | 0,14 GB | cpu | 0 | 0,18 s | **49,3** | 49,3 / 0,3 / 44,7 |
| LFM2.5 350M (Q4_0) | 0,20 GB | cpu | 0 | 0,34 s | **31,9** | 0,3 / 31,9 / 0,3 |
| Gemma 3 270M (QAT Q4_0) | 230 MB | cpu | 0 | 0,16 s | **31,1** | 31,1 / 0,2 / 1tok |
| Tev1 0.8B (Q8_0) | 774 MB | cpu | 0 | 1,10 s | **11,0** | — |
| SmolLM2 135M (Q4_K_M) | 0,10 GB | cpu | 0 | 8,24 s | **5,1** | 0,2 / 5,1 / 0,2 |
| Qwen 3 0.6B (LiteRT-LM) | 586 MB | **gpu** | 1 | 3,00 s | **3,8** | 3,8 / 3,8 / 3,8 / 3,8 |

Quatro coisas saem daqui que nenhuma delas diz sozinha:

**1. A ordem por tamanho é falsa.** O **SmolLM2 135M é o mais lento de todos**,
apesar de ser o menor arquivo, com 8,24 s de primeiro token — e a medição anterior
do LFM2.5 230M em sessão quente era 18,0 tok/s. O 135M é `Q4_K_M` e os outros são
`Q4_0`; a hipótese honesta é que a diferença é a quantização, não o tamanho, e
**não foi testada**. O que é medido é que "escolha o menor modelo" é advice
errado neste aparelho: o menor é o mais lento.

**2. O LiteRT-LM é ~6× mais lento que o llama.cpp neste aparelho — e a GPU é
*mais rápida*, não mais lenta.** Isto **corrige** o que esta seção dizia antes.
Eu tinha escrito "a GPU é 8× mais lenta que a CPU aqui", comparando os 3,8 tok/s
do LiteRT-na-GPU com os 31–49 dos GGUFs-na-CPU. **Isso compara dois runtimes, não
dois backends**, e a frase deixava parecer que a GPU era o problema.

Medido com o mesmo build, A/B virando o toggle de Settings:

| LiteRT Qwen3 0.6B | TTFT | decode |
|---|---|---|
| `cpu_safe` → `backend=cpu` | 4,58 s | **3,0** tok/s |
| `auto_fast` → `backend=gpu` | 2,94 s | **3,8** tok/s |

A GPU ganha por **27%**. O 8× que eu vi era entre a GGUF-na-CPU e a
LiteRT-na-GPU. Isolando o runtime do backend, com a mesma lei `tok/s ≈ k/parâmetros`
que gave acima:

```
GGUF 0.35B na CPU ..............  31,9 tok/s   medido
GGUF 0.60B esperado ............  18,6 tok/s   extrapolado
LiteRT 0.60B na CPU ............   3,0 tok/s   medido
LiteRT 0.60B na GPU ............   3,8 tok/s   medido
```

**O LiteRT-LM na CPU é 6,2× mais lento que o llama.cpp na CPU**, para trabalho
comparável. A GPU não é a causa: ela não passa nem do teto de ineficiência do
próprio engine.

**Por quê, e é estrutural:** todo o pinning de threads vive dentro de
`jni_wrapper.cpp` — `buildCpuSet`, `ggml_threadpool_new`, `llama_attach_threadpool`.
O caminho LiteRT passa por `liblitert-lm.so` e não tem acesso a nenhum deles, então
o backend de CPU dele roda **sem pin**, e o pinning sozinho vale 2,8× neste
aparelho (6,5 → 18,0 tok/s, medido). O resto da diferença são kernels: ggml com
i8mm/dotprod nos A76 contra o conjunto próprio do LiteRT-LM.

**Consequência para `planLiteRtTier`:** o default de sempre preferir GPU está
**correto neste aparelho**, por 27% — mas estava certo por acaso, porque nunca
mediu. E a resposta honesta da seção "micro-benchmark no LiteRT" muda: o
problema não é escolher o backend, é o engine ser 6× mais lento. Um benchmark que
mede os dois backends escolheria GPU e continuaria 6× atrás de um GGUF do mesmo
tamanho.

**O alcance do número:** um modelo, um aparelho. Os outros 4 `litert` do catálogo
(gemma-4 E2B, E4B, e os outros dois) não foram medidos, e nenhum deles é um
0.6B — a lei `k/parâmetros` foi ajustada em GGUF, e a LiteRT pode ter outra
curva. O que dá para dizer é que **o backend GPU é o melhor LiteRT neste
aparelho**, não que o LiteRT é ruim em todo lugar.

**3. As amostras da CPU variam 150×; as da GPU, não.** O LFM2.5 230M deu 49,3,
0,3 e 44,7 em três pedidos seguidos; o LiteRT deu 3,8 quatro vezes. É o governor
de novo: `schedutil` rimado no Sustained load, e a GPU não passa por isso. Por
isso o número da GPU é reprodutível e o da CPU precisa de melhor-de-N — e por
isso uma tabela de tok/s tirada de um request só é um número sobre o clock
daquele instante.

**4. Todos os GGUFs foram para a CPU com `layers=0`, com a GPU presente.** A
regra de tamanho da 0.5.1 se sustenta em 774 MB, o maior deles, sem exceção.

### Dois erros de medição meus, que custaram uma rodada cada

**O script exigia dois tokens para ter taxa de decode, e o LFM2.5 350M
respondeu `3`** — a resposta certa para "quantos andares o Hotel Eiffel tem", em
um token. O script/reportou "nenhuma geração respondeu". Um número de tokens não
é sinal de vida de um stream; o prompt agora exige duas frases.

**O `adb install` imprimiu só a linha do `pm command`** e eu li como se tivesse
instalado. O APK no aparelho era de 10:00 e a mudança era de 11:17, e foi por isso
que o watchdog de 30 s "não funcionava" — nunca esteve instalado. Agora o
resultado é conferido por palavra e o `lastUpdateTime` é lido.

## A superfície de decisão: `/v1/classify` agora aceita decision models

`decision_model.dart` é puro e tem 28 testes. O despacho é por um **fato sobre o
arquivo**, não por configuração: se o modelo tem `cls.output.weight` o caminho
antigo de cabeça serve; se não tem, o caminho generativo.

Medido no A72 com Tev1-0.8B, `/no_think` ativo, temperatura 0, orçamento de 8
tokens:

| entrada | letra | etiqueta | |
|---|---|---|---|
| "checkout devolvendo 500 desde 9h" | B | bug | 2,2 s |
| "cobrado duas vezes pelo #4417" | A | billing | 2,0 s |
| "esqueceu a senha e não entra" | C | account | 50,7 s |
| "assinatura mais cara que o anunciado" | A | billing | 2,1 s |
| "app trava ao abrir a câmera" | B | bug | 51,1 s |

**5 de 5.** Todos com `relevance_score: null`.

Três decisões que os números impuseram:

**`relevance_score` é null e `scores` mapeia tudo para null.** Um classificador
com cabeça produz um logit por classe. Um decision model devolve uma letra, e só.
O Bespoke-Nimble é servido com probabilidades no Ollama, mas elas vêm da camada
de serviço dele, não dos pesos — colocá-las aqui seria inventar um número, e um
cliente que arredonda para porcentagem exibiria uma ficção. A resposta traz
`why_no_scores` dizendo isso.

**O orçamento é 8 tokens, não 24.** Uma letra mais o bloco `<think>` vazio são
uns cinco. Com 24, um modelo que ignorou a instrução e escreveu prosa queimava o
orçamento inteiro, e no A72 isso são **8–9 s por token** com o núcleo no piso — 24
tokens são três minutos de um request que nunca seria uma decisão. Oito dá conta
da resposta compatível e falha rápido na incompatível, que é o caso que o chamador
mais precisa ouvir.

**A decisão tem prazo, porque uma geração lenta não pode derrubar a API.** Um
504 em 60 s é melhor do que um request pendurado. O `.timeout()` também garante
o `finally`, que é o que libera o `_busy` — sem ele, uma geração abandonada
deixaria o endpoint em 429 para todo request posterior.

**A hipótese que motiveu esse timeout estava errada, e a medição é o motivo de
saber.** Escrevi aqui que o `onDone` se perdia — "o loop nativo termina limpo e o
stream do Dart não entrega `onDone`" — e não era verdade. `onDone` é chamado em
`LlamaFlutterAndroidPlugin.kt:334` e `:459`, `isStopping` é resetado no início de
cada `generate` (linhas 299 e 403), e a contabilidade no log de seis gerações
seguidas deu `Generation loop finished` = 5, `Stream onDone` = 5, `Idle timeout` =
0, `Stream error` = 0. **O `onDone` chega sempre.** O que produzia 51 s por request
era outra coisa, e está na seção do KV cache abaixo. O timeout de 60 s ficou
porque é correto por si — uma decisão que não veio em um minuto não é uma
decisão — mas a razão que eu dei para ele estava errada.

**Prosa é falha, não fallback.** Pegar a primeira letra de uma frase, ou
devolver a primeira opção como padrão, é o que transforma um decision model numa
moeda que parece estável em toda métrica. O `parseDecisionAnswer` devolve null,
a resposta sai 422 com o texto bruto e as opções esperadas. O `<think>` é removido
antes, porque uma letra dentro da deliberação do modelo não é a resposta dele — o
Tev1 escreve `<think>\n\n</think>\n\nB` e um parser de primeira letra devolve
`t`.

## O KV cache nunca era limpo — `g_n_past` crescia para sempre

O comentário na linha 1839 de `jni_wrapper.cpp` dizia *"Clear memory from previous
generation to start fresh"* e **não havia clear**. O único `llama_memory_clear` do
arquivo estava na função de encoder. Então `g_n_past` subia ~183 por geração e
nunca voltava, e o prompt seguinte era decodificado **por cima** do anterior.

Seis pedidos consecutivos para `/v1/chat/completions`, prompt de 165 tokens:

```
Sampling token 1, g_n_past=165    prefill 306 tok/s     1,0 s
Sampling token 1, g_n_past=348    prefill  47,9 tok/s  55,1 s
Sampling token 1, g_n_past=531    prefill 275 tok/s     1,1 s
Sampling token 1, g_n_past=714    prefill  44,4 tok/s  55,4 s
```

São **dois** defeitosnelas quatro linhas, e só o lento aparece:

**1. Respostas erradas.** `batch.pos[...] = g_n_past + tokens_processed + i` —
as posições do prompt começam em `g_n_past`, não em 0. Então os tokens 0-182 do
contexto consultado são o **pedido anterior, sem relação nenhuma**. As seis
respostas saíram byte-idênticas com prompts diferentes: mar, montanha e cidade
deram o mesmo texto. O motor estava respondendo condicionado a uma conversa que
nunca recebeu.

**2. Devagar.** 44 tok/s contra 306, alternando a cada dois pedidos.

**O que foi descartado nunca foi cache.** Os dois chamadores fazem prefill do
prompt **inteiro** a cada turno — o chat do app reenvia o histórico completo, e o
servidor manda um pedido só — então nenhum token é pulado por já estar no cache.
As chaves velhas eram peso morto para a atenção mastigar.

A janela deslizante de `make_room_for` **fica**: dentro de uma única geração um
prompt longo mais 512 tokens ainda pode estourar `n_ctx`, e é o caso para o qual
ela foi escrita. O conserto zera no começo de cada `nativeGenerate`.

Depois, no mesmo aparelho, `g_n_past` volta a 165/167/164 em toda geração, o log
passa a dizer `Resetting KV cache: discarding 188 stale positions`, e **mar,
montanha e cidade dão respostas diferentes**. A variação de 50 tok/s contra
367 tok/s que sobrou é o governor de sempre, não o bug.

**Como isso só apareceu agora:** a medição do catálogo usava um prompt só, então
os pedidos eram idênticos e a resposta byte-idêntica parecia ser o modelo
funcionando. A divergência apareceu com três prompts diferentes no mesmo lote.

## O runtime LiteRT (`.tflite`), e o que ele não sabe dizer

`local_plugins/litert_flutter/` traz o **LiteRT 2.2.0** — o TFLite renomeado —
como plugin separado de `flutter_litert_lm`. Separado porque são **dois runtimes
que só dividem o nome no repositório do Google**: `litertlm-android` é LiteRT-**LM**
(prompt → tokens, `Backend.{cpu,gpu,npu}`), e este é o interpretador de tensores
(`CompiledModel`, buffers nomeados). Um é um classificador de 1 MB, o outro é um
GGUF. Juntá-los seria um plugin com 46 MB de nativas para servir 1 MB.

**Por que 2.2.0 e não 1.4.2, que é 4,3 MB em vez de 8,7.** Duas coisas, e as duas
decidem: `litert` sozinho expõe só a API antiga `org.tensorflow.lite.Interpreter` —
`CompiledModel` e `GpuOptions` estão em `litert-api`, que a 2.2.0 é um AAR (o
`.jar` que o Maven serve tem 1.449 bytes e está vazio) e carrega 0,5 MB de código
nativo; e é a versão que o card da Laya nomeia — *"both graphs use LiteRT 2.2.0
CompiledModel with GpuOptions(precision = FP32)"*. Amarrar a uma versão diferente
da que um modelo publicado foi validado contra é um jeito de descobrir que os
números mudaram.

Custo: **9,28 MB** de `.so` arm64, contra 222,8 MB de nativas no APK. O
`abiFilters 'arm64-v8a'` no módulo de biblioteca é o que os outros plugins já
fazem e **não** controla o APK — quem filtra é o módulo do app, via
`--target-platform`.

### A API liga por nome e não lista nomes — daí o parser em Dart

`run(Map, Map, signatureName)` liga por nome. `createInputBuffers(0)` cria por
**índice de assinatura**, e `getInputTensorType(nome, assinatura)` só funciona se
o nome já for conhecido. **Não há como listar os nomes pela API.** Então o host
precisa lê-los do FlatBuffer, e essa leitura é `/v1/litert/screen`
(`lib/services/litert_model.dart`, 23 testes, incl. o act head real da Laya).

Não é conveniência. O act head guarda **`feats` antes de `pooled_cls`**, enquanto o
`HOST_CONTRACT.md` lista o contrário. Um host que amarrasse a posição 0 entregaria
um tensor de 4 elementos ao `pooled_cls` de 1024.

### Medido no A72, com `laya_en_act_head_fp32.tflite` (1,0 MB, SHA conferido)

| | compila | run | logit 0 | logit 1 |
|---|---|---|---|---|
| CPU (XNNPACK) | **6 ms** | 0–2 ms | +0,284356 | −0,209888 |
| GPU (OpenCL) | 273 ms | 0 ms | +0,284356 | −0,209888 |

**Diferença máxima entre os backends: 2,98e-08** — precisão de float32. Os dois
caminhos calculam a mesma coisa, e a reprodutibilidade entre runs é 0.

E `/v1/classify` com a cabeça dá **exatamente** o que `/v1/litert/run` dá, com
diferença `0.000e+00` — o embrulho não acrescenta nem perde nada.

### O acelerador executado não é exposto, e a resposta diz isso

`CompiledModel` **não tem getter** do acelerador que usou. A classe expõe
`Options` (o que pedir) e nada que leia de volta o que o LiteRT fez, e o LiteRT
cai internamente quando o acelerador pedido não está disponível.

A regra deste repo é reportar o backend que **realmente** rodou, então a resposta
carrega `available` (o que o aparelho diz que aguenta — `Environment
.getAvailableAccelerators()`, já filtrado) e `requested`, e
`executed_accelerator` vem **nulo** com uma nota dizendo por quê. Um accelerator
sob demanda seria uma verdade que o aparelho não sabe.

No aparelho a resposta real sai do logcat, e sai: `NPU accelerator could not be
loaded`, `Dynamically loaded GPU accelerator(libLiteRtClGlAccelerator.so)`,
`XNNPACK CPU accelerator registered` — e `getAvailableAccelerators()` devolve
`["GPU", "CPU"]`. O NPU continua fora, como em todas as outras camadas.

### `/v1/classify` tem três caminhos, e o `.tflite` é o terceiro

Despachado pela **extensão do arquivo**, não por configuração: quem não escolhe
runtime, escolhe modelo. Um campo `runtime` no request seria algo que pode
discordar do arquivo, e a discordância é silenciosa.

**`relevance_score` é `null` e `label` é `null`.** A cabeça produz logits; o
conjunto de rótulos pertence a quem treinou, e só o chamador sabe o que é a
classe 0. `top_index` é o argmax dos logits e nada mais — argmax sobre logits só
é a leitura certa para uma cabeça treinada assim, e este endpoint não sabe disso
sobre um modelo que ele não treinou.

**A regra de qual input é o vetor de features mudou por causa do aparelho.** Era
"o primeiro input", e o act head quebra isso do jeito mais comum possível: guarda
`feats [1,4]` **antes** de `pooled_cls [1,1024]`, então "primeiro" escolhe o
auxiliar de 4 elementos e o endpoint responde, corretamente, *"a cabeça quer 4
features e recebeu 1024"* — resposta certa para a pergunta errada.

O que é verdade entre cabeças é o **tamanho**: o vetor de features é o grande, e
entradas auxiliares são quantidades derivadas e pequenas. Então o default é **o
maior input**, e quem souber melhor diz com `features_input`. A resposta sempre
nomeia qual input foi usado, então errar custa um request e não uma sessão de
debug. `test/tflite_head_shape_test.dart` fixa a regra, e o caso do act head é o
primeiro teste do grupo.

**Entradas auxiliares nunca são preenchidas com zeros.** Um logit computado sobre
features inventadas é um número sem significado, e volta usando um rótulo
confiante. A resposta 400 nomeia o que falta e o tamanho que cada uma quer.

### Três bugs meus que custaram um ciclo cada, e o padrão deles

**O nome do método não batia.** O Kotlin registrava `"load"` e o Dart chamava
`loadModel`, então toda carga caía em `notImplemented()` — que o Flutter reporta
como `MissingPluginException`, cuja mensagem do lado Dart aponta para o
**registro** do plugin. A classe estava no dex, o registrante a referenciava, e a
única pista restante era o nome. A mensagem agora diz que `notImplemented` é
"registrado, mas sem handler com esse nome", que é o caso comum.

**A resposta vinha da thread errada.** O handler do `MethodChannel` roda na
platform thread e `CompiledModel.create` é nativo e bloqueante; responder de lá é
o que a engine Flutter reclama. Todo corpo agora responde por um wrapper que
sempre volta para a platform thread.

**`inputs.every(...)` numa lista vazia é `true`**, então uma assinatura **sem
entradas** passava como ligável — e como o default do modelo é "a primeira
ligável", ela era escolhida e não tinha o que preencher. `bindable` agora exige
entradas e saídas.

O padrão dos três: **um erro que se apresenta como outra coisa.** O sintoma aponta
para o registro quando o problema é o nome; para o crash quando é a thread; para
"sem resposta" quando é uma lista vazia. Nenhum deles é óbvio no código, e todos
os três só apareceram porque a checagem seguinte olhou o log em vez de acreditar
na mensagem.

## `.tflite` é um modelo do app — e a tela tem um `Material` a menos do que você acha

O runtime LiteRT (acima) serve `.tflite` por HTTP. Até a versão anterior ele
**não existia na interface**: a descoberta filtrava por extensão, e `.tflite` não
estava na lista. Um arquivo no diretório de modelos era invisível — sem tamanho,
sem card, sem botão, sem como ser apagado — e o import recusava em Dart **e** em
Kotlin. A API servia o arquivo perfeitamente esse tempo todo, que é o que tornou
isto worth consertar em vez de documentar.

`AiModel.runtimeTflite` é um **quarto runtime**. `litertlm-android` (prompt →
tokens) e o interpretador de tensores (buffers nomeados) só dividem um nome no
repositório do Google. `runtimeFromFilename` não tinha o ramo, então um `.tflite`
caía em `runtimeLlama` — e `isLlamaModel` é
`runtime == runtimeLlama || filename endsWith .gguf`, de modo que a seção, o
badge e o botão diziam "GGUF" sobre um classificador de 1 MB.

### `Get.to` não fornece `Material`, e isso custa três widgets

O console é aberto com `Get.to(() => LitertHeadConsole(...))`. Não há `Scaffold`
no caminho — e é o `Scaffold` que fornece o `Material`. `ChoiceChip`, `TextField`
e `InkWell` chamam `debugCheckHasMaterial` em **si mesmos**, então cada um lança
do próprio `build` e a subárvore inteira para de renderizar enquanto o app bar e
a barra de abas continuam funcionando.

**Um `Material(type: transparency)` na raiz corrige os três de uma vez.** É a
correção certa e não a que satisfaz o assert: um por painel obriga a auditar cada
painel novo, e o primeiro `Material` que eu coloquei — em volta dos chips —
virou redundante e foi removido. Dois mecanismos para uma regra é um mecanismo a
mais.

O sintoma differed por widget, e é por isso que vale saber qual:

| widget | onde aparece |
|---|---|
| `ChoiceChip` | no **log do app**, com `ChoiceChip.build (choice_chip.dart:221)` e `debugCheckHasMaterial` logo abaixo |
| `TextField` | **só num screenshot**, como uma caixa vermelha no lugar do campo |

### O `uiautomator` mente sobre onde o `Switch` aceita toque

O dump do switch do servidor traz `bounds [45,266][1035,542]` — a linha inteira —
e `class="android.widget.Switch"`, `enabled="true"`, `clickable="true"`. Tocar no
centro não faz nada, e `startServer` nunca chega a ser chamado. O alvo de toque
real tem ~169 px na **ponta direita** da linha; o Flutter funde a semântica da
linha inteira num único nó.

O sintoma é "o controle está quebrado" e a pista disponível ("está enabled,
está clickable") confirma isso em vez de refutá-lo. **Confundir o `bounds` do nó de
semântica com a caixa do widget** é o que faz um toggle parecer morto.

O que separa isso de um defeito real é um controle: o switch **Require API key**,
na mesma tela, responde a toque normalmente (ele abre um diálogo). Sem esse
controle, "o `Switch` deste aparelho não responde a `input tap`" e "este `Switch`
está quebrado" são a mesma frase.

### Um `catch` mudo esconde o defeito, e `takeException` devolve uma por vez

`/v1/litert/status` é `GET`. O console o chamava por um `_post`. O `catch` era
`on Object {}` — sem nada — e o console passou a sessão inteira inteira dizendo
"not screened yet" e "device reports: (not read yet)", com o probe dizendo que o
servidor estava de pé. Ele estava.

Três regras que daí saem, e as três já custaram um round:

1. **O helper de HTTP recebe o método como parâmetro.** Um `_post` e um `_get`
   separados deixam a escolha para quem chama, e quem chama erra.
2. **Um `catch` de poll escreve o erro.** Um poll que falha em silêncio é
   exatamente o que faz um painel em branco parecer "o aparelho ainda não
   respondeu".
3. **`takeException()` devolve uma exceção por chamada.** Construir dois widgets
   ofensivos deixa a segunda na fila, e ela aparece no **teste seguinte** como
   "Multiple exceptions were detected during the running of the current test" —
   acusando o teste errado por um assert disparado no certo. Ambos os arquivos de
   teste drenam em laço (`_drain`).

E **perguntas independentes não se encadeiam**: o `screen` era disparado do
caminho de sucesso do `status`, então uma falha no status apagava o screen sem
deixar rastro. São duas chamadas agora.

### O teste de layout que passava com o defeito vivo

O teste do console montava a tela dentro de um `Scaffold`, que fornece `Material`.
Ele passou **contra os dois widgets quebrados acima**, no mesmo aparelho em que
eles estavam quebrados. `test/litert_console_layout_test.dart` monta a tela como
ela é mostrada — sem `Scaffold` — e a prova de que o harness é capaz de falhar
está no próprio arquivo: sem o `Material` da raiz, seis exceções; com ele, oito
de oito.

E o outro lado do `ListView` preguiçoso, já pago três vezes neste repo e agora
mais uma: um `SizedBox(height: 2400)` dentro de `Scaffold(body:)` **não**
move o viewport — o `Scaffold` dá 600 dp e o `Expanded` do console preenche isso.
O que move o viewport é `tester.view.physicalSize`. Sem isso, o `ListView` nunca
constrói as linhas de baixo e todo `find.text` depois da primeira não encontra
nada — o que se lê como "o painel de baixo está faltando".

## Notas de build

- Máquina: 12 hybrid cores (10 e-core + 2 p-core). `org.gradle.workers.max=2` no
  `gradle.properties` — nunca sature todos os núcleos. (10 e-core + 2 p-core). `org.gradle.workers.max=2` no
  `gradle.properties` — nunca sature todos os núcleos. (10 e-core + 2 p-core). `org.gradle.workers.max=2` no
  `gradle.properties` — nunca sature todos os núcleos.
- **Threads: o default é o número de núcleos *grandes*, não metade dos núcleos.**
  Motivo medido, e é o oposto do que parece certo. No A72 (Snapdragon 720G)
  cpu0-5 são A55 a 1804 MHz e cpu6-7 são A76 a 2323 MHz — "metade de 8" = 4, e
  as quatro iam **todas** em A55. O default antigo dava 4 e o modelo travava.
  `lib/utils/cpu_topology.dart` lê `cpuinfo_max_freq` de cada core; o Edge 60
  (4×A78+4×A55) dá 4, que é o número que este guia já recomendava — por
  coincidência, não por ser a mesma fórmula.
- Threads: 4 é o ótimo no Edge 60 (4×A78+4×A55); 8 regressa porque A55 trava A78.
- R8 está desligado (`isMinifyEnabled = false`). Não adicione regras ProGuard por
  precaução — elas não fazem efeito e podem mascarar problemas reais.
- **Um cliente dentro do app tem que mandar a chave da API.** `localApiHeaders()`
  em `server_auth.dart` — mapa vazio quando a chave está desligada, `Bearer`
  quando está ligada e não está vazia. `/v1/**` está atrás de `_isAuthorized` e
  `useApiKey` foi lançado com `false`, então **nenhum cliente dentro do app
  mandava o cabeçalho** e nada quebrou até alguém ligar a chave. Os dois consoles
  vigiam `useApiKey`/`apiKey` além de `isRunning`: ligar a chave deixa toda
  chamada em 401 **sem nenhuma outra observável mudar**.
- **Plugins locais com `dependency_overrides` podem não ser detectados pelo Flutter plugin discovery.** Se `dart_plugin_registrant.dart` não inclui, registrar manualmente no `MainActivity`.
- **Modelo pequeno na CPU, e agora isso é código, não conselho.** A regra "GPU
  (Vulkan) tem overhead de shader que domina até ~2B" morou anos neste arquivo
  como observação, e a escada de aceleração nunca a implementou:
  `planAcceleration` recebia `mode`, `vulkanSupported`, `recommendedGpuLayers` e
  `npuAvailable` — quatro respostas de **capacidade** e nenhuma sobre o que ia
  ser executado. Medido no Edge 60: o benchmark dava **57 tok/s** e a carga do
  mesmo modelo dava **10-14 tok/s com 25 s de primeiro token**, porque o
  `auto_fast` colocou um 230M na GPU.

  | modelo | CPU | GPU |
  |---|---|---|
  | LFM2.5 230M Q4_0 (149 MB) | **57 tok/s** | 10-14 tok/s |
  | 1B Q4_0 (~700 MB) | **21,2 tok/s** | 3,4 tok/s |

  Agora `auto_fast` mantém um GGUF abaixo de 1280 MB na CPU, e o motivo na tela
  nomeia a medição em vez de afirmar uma preferência. **O corte é extrapolação
  acima do que foi medido** — tudo até 1B tem número, nada entre 1B e 2B tem —
  e é por isso que ele é o primeiro candidato a um micro-benchmark de verdade.
  Três fronteiras que os testes fixam: acima da faixa nada muda (e um modelo
  desse tamanho precisa do offload para carregar); `gpu_fast` sobrepõe, porque
  quem pede a GPU foi informado dos números; e tamanho desconhecido (0) não é
  tamanho pequeno.

  Continua valendo, e por um motivo diferente do que se acreditava:
  `n_gpu_layers==0` deve zerar a lista de dispositivos, não apenas pular offload
  — senão ggml sched offloads ops pro Vulkan (`op_offload`).
- **CPU Safe tem que *não abrir* o backend Vulkan, e não só não usá-lo.** As duas
  metades são separadas de propósito, porque só a segunda não bastava.
  `model_params.devices = cpu_only` (o conserto do Edge 60, ~5,5 s) resolve onde os
  **pesos** vão. O que ele não faz é **desregistrar o device**: o
  `ggml_backend_load("libggml-vulkan.so")` acontecia dentro do mesmo `once_flag` do
  backend CPU, incondicionalmente, para o `nativeDetectGpu` poder reportar a GPU.
  Medido no A72 com CPU Safe ligado, Adreno 618: o log dizia
  `Device list restricted to the CPU` e mesmo assim o `llama_decode` passou os 60 s
  inteiros do `prefillBudget` com **todas as threads dormindo e zero CPU em uso**,
  num modelo de 258 MB cujo prefill são segundos de aritmética. Driver presente,
  CPU ociosa: o travamento é o driver sendo tocado, não o cálculo. E o comentário
  do `n_gpu_layers == 0` no Edge 60 descreve **o mesmo ponto**, 10× mais barato.
  Por isso `ensureBackends(withGpu)` no `jni_wrapper.cpp` carrega o Vulkan só quando
  a carga realmente vai usá-lo, e `modeMayOpenGpu()` em `acceleration.dart` impede
  a sondagem — que é o que *carrega* o backend — de rodar em CPU Safe. São dois
  portões porque o Kotlin passa `n_gpu_layers` mas a sondagem é um caminho
  separado. **O `prefillBudget` de 60 s é o sintoma, não a causa** — ver o bloco
  logo abaixo, porque a hipótese do Vulkan **foi testada e está errada**.
- **O segundo portão é o `SD_JNI`, e ele não passa por nenhum desses dois.**
  `SdFlutterAndroid.detectGpuVendor()` é **EGL**, e no A72 o EGL traz o driver
  inteiro do Adreno para dentro do processo — `libvulkan.so` e tudo — só para
  devolver uma string de duas letras que decide entre OpenCL e Vulkan no Stable
  Diffusion. Rodava em `_detectImageGpu()`, no `onInit` do
  `settings_controller.dart`, ou seja **no boot, antes de o usuário abrir as
  configurações de imagem**, e independente do modo do acelerador. Hoje só roda se
  `!imageGenForceCpu`, e `setImageBackendMode(true)` passou a dispará-la — o
  usuário pedindo a GPU é o opt-in. **Ao procurar "por que o driver está no
  processo", procure também fora do llama.cpp:** o sintoma é idêntico, e este
  culpado quase passou batido porque o logcat mostra `AdrenoVK` e não a linha
  `Vulkan backend loaded` que se procurava.

### O `prefillBudget` de 60 s no A72 — hipótese errada, e o que é verdade

**A causa NÃO é o backend Vulkan.** Isto foi medido, não suposto: com os dois
portões acima fechados, `cpu_safe`, o driver fora do processo (zero linhas
`LlamaJNI` e zero `AdrenoVK` vindas do nosso código no boot) e `libggml-vulkan.so`
**não mapeado**, o `llama_decode` **continua estourando os 60 s** do
`prefillBudget`. O que muda é o sintoma, e é por isso que a confusão durou tanto:

| | antes | depois dos portões |
|---|---|---|
| thread de geração | `wchan` sem nada, **0% em R**,aparentando travada | **100% de um core, sem parar** |
| consumo | 0% CPU durante os 60 s | ~204% (2 núcleos), `utime` subindo 1 s por 1 s |
| desfecho | "Model did not respond" | "Model did not respond" (o mesmo) |

Ou seja: **antes ela estava ociosa e agora ela está computando**, e mesmo assim não
termina no orçamento. Isso é aritmética, não espera: um prefill de 545 tokens num
llama 360M tem ~2 × 0,36 B × 545 ≈ 390 MFLOP, e num A76 a ~1,5 GFLOP/s efetivo
(isso é ggml single-stream com Q4_K_M, não um FLOPS de GPU) dá **minutos**. O
número 2.0K de contexto na UI é o que o modelo aceita; o `Context size: 2048` que o
log imprime é o teto real do nativo, e o **system prompt do agente com o catálogo
de 24 tools é ~500 tokens sozinho** — o prefill nunca foi pequeno.

O que está **errado** aqui, e vale mais que a teoria antiga: `prefillBudget =
60 + 240 * mediaCount` foi escrito para um aparelho que faz prefill em segundos.
No A72 ele não é um timeout de rede, é **o tempo do cálculo**. As saídas são
subir o budget (a resposta está chegando, só devagar), reduzir o system prompt
quando não há tools habilitadas, ou escolher um modelo menor. **Não é bug do
engine e não é o driver.** E o `wchan` vazio com 0% de CPU — que parecia deadlock
— era só o `llama_decode` esperando o fim do batch, sem trabalho para fazer.

**O que continua sem explicação:** por que 0% antes e 100% depois, se o Vulkan não
estava mais carregado nos dois casos? A medição do "antes" foi feita com o
`SD_JNI` ainda pulling o driver no boot, então os dois estados não eram
comparáveis. Para comparar de verdade é preciso um build com os dois portões e
rodar em modo `cpu_safe` desde o boot — que é o próximo passo, e é o motivo de o
gate existir mesmo sem ter resolvido isto.

## Cloud features (0.3.0)
## Tradução (PT-BR)

- **Cobertura:** ~394 `.tr` calls no código, 278+ keys em `app_translation.dart`
- **Arquivos:** `lib/l10n/app_translation.dart` (GetX), `lib/l10n/app_en.arb`, `lib/l10n/app_pt_BR.arb`
- **Templates traduzidos:**
  - Sugestões de chat (16 prompts em PT-BR)
  - Views: chat, model, settings, log, task, workspace, HF search
  - Controllers: model, chat, settings
  - Widgets: image_viewer
- **Regra:** strings UI nunca em `const` — `.tr` é método runtime
- **Device locale:** `pt_BR` (confirmado via `adb shell getprop persist.sys.locale`)


- **Round-trip ceiling:** cloud = 20 hops fixo; local = `agentMaxHops` (setting).
  Setting "Tool round-trips" inclui `∞` (valor 0 = infinito) e entrada manual
  (toque no valor → dialog com TextField, valida 0–8).
- **Context window auto-detect:** `_parseContextWindows()` em
  `cloud_model_controller.dart` — OpenRouter, DeepSeek, NVIDIA, Google, OpenAI.
  Safe maxTokens = 25% do contexto, min 256 (`effectiveMaxTokens()`).
- **Capability auto-detect:** vision/tools tags por provider na lista de modelos.
- **Métricas persistentes:** `ChatMessage` armazena `ttftMillis`, `totalTokens`,
  `totalMs`. Exibidas permanentemente após geração no `ChatBubble`. Cores:
  Volt `#B9F53E` (escuro) / verde escuro `#1B5E20` (claro).
- **Cloud TPS:** `cloudTokensPerSecond` observable no chat controller.
- **Tok/s é medido de ponta a ponta**, de quando a requisição foi feita até o
  último token — `endToEndTokensPerSecond` em `lib/utils/token_rate.dart`. Era
  pré-existente e **errado nas duas rotas**: o denominador começava no primeiro
  token, que é onde a *rajada final* começa, então o número subia conforme a
  resposta acabava. Num turno real do LiteRT-LM (106 tokens nos 21 ms depois de
  uma chamada bloqueante) o bubble dizia **5047,6 tok/s** num aparelho cujo modelo
  mais rápido faz 3,1. `test/token_rate_test.dart` fixa o caso.

## A janela de testes dos modelos "System One"

O nome vem dos quatro que deram nome a ele — Jev, Laya, Tev1, Bespoke-Nimble — e
a classe é **aberta**. É "um modelo que responde a uma pergunta estruturada com
uma classe", e o próximo publicado entra nela sem ninguém editar uma lista.
**Nada no código olha para esses quatro nomes**; a forma é decidida pelo que o
arquivo é, como o `/v1/classify` já faz, e `test/system_one_test.dart` tem um
teste que afirma isso para os quatro e para um nome que ninguém ouviu falar.

`lib/services/system_one.dart` (puro, 66 testes) + `lib/views/system_one_console.dart`.
Aberta no **card `.tflite`** (duas ações: *Inspect the file*, que já existia, e
*Test a decision*) e na **tela do servidor** — e **não** nos cards de GGUF, porque
a forma de um GGUF só é visível depois de carregá-lo e um botão "decision" nos 36
cards de chat seriam 36 botões errados.

Quatro regras que a tela guarda, e todas custaram uma decisão:

1. **Os rótulos são do chamador** — e por isso `label: null` e o motivo do
   endpoint aparecem na tela. Transformar logits crus em porcentagem seria o
   primeiro número inventado do app, no único lugar onde alguém vai confiar nele.
2. **A recusa de um decision model é um resultado, não um toast.** O 422 traz o
   texto que o modelo escreveu, que é a única forma de ver o que aconteceu.
3. **Auxiliares nunca são preenchidos com zeros** — nem pela tela, nem pelo
   endpoint. Um campo por entrada auxiliar declarada, com a contagem do arquivo.
4. **2–24 é o limite do decision model, não o de uma cabeça.** São dois tipos
   (`SystemOneOptions`, `SystemOneLabels`) porque os limites não são o mesmo, e
   recusar 25 rótulos de uma cabeça de 512 classes seria inventar uma regra.

**`HeadContract` existe porque eu parseei o payload errado e o teste passou.** A
primeira versão procurava um `signature` **objeto** com `inputs` dentro; o
aparelho devolve uma **array** `signatures`. A consequência foi silenciosa: a
janela dizia "qualquer comprimento serve" para uma cabeça que quer 1024 números,
e o teste unitário passava porque alimentava a forma que eu tinha imaginado. Os
dois payloads dos testes agora são **copiados do A72** — `laya_en_act_head_fp32.tflite`,
`feats [1,4]` **antes** de `pooled_cls [1,1024]`, saída `act_logits [1,2]`.

**A janela pergunta três endpoints, porque as três fontes não se sobrepõem.**
`/v1/models/local` diz o nome e o runtime da **GGUF** — e o campo `loaded` dele é
**só GGUF**, então com uma cabeça `.tflite` carregada ele devolve `null`.
`/v1/server/capabilities` → `capabilities.classify` é o **único** lugar que sabe
se aquela GGUF classifica. `/v1/litert/status` é o único que sabe de um `.tflite`.
Ler `loaded['classifier']` foi o que eu fiz, e **a chave não existe** — um campo
inexistente se lê como um campo falso, então toda GGUF saía como decision model.
Cada sondagem tem seu próprio `try`: um só descartaria as duas respostas que
chegaram.

E **não existe `POST /v1/litert/unload`** — as rotas LiteRT são `screen`, `load`,
`status`, `run`. Uma cabeça só é trocada carregando outra, e o estado "nada
carregado" da janela fica inalcançável depois da primeira carga. Vale uma rota.

Medido no A72: a tela de decisão acerta **3 de 3** com Tev1-0.8B usando o corpo
que ela própria monta, `relevance_score: null` e `scores` todo nulo; a tela da
cabeça renderiza e lê 1024/4/2 do `GET /v1/litert/status` real; `compile_ms` 5–7.
**O `Run` não foi apertado na tela** — a tela do A72 não aceita texto sintético e
o vetor são 1024 números. O contrato de ponta está verificado por `curl` com o
JSON extraído do próprio código; a lacuna é do aparelho, e está escrita assim.

## Sugestões de próximas features

**Comece por [`docs/HANDOFF.md`](docs/HANDOFF.md)** — snapshot datado do estado,
com o que está medido, o que não está, e o próximo passo com o protocolo.

Ver [`docs/suggestions.md`](docs/suggestions.md) para a lista completa
organizada por esforço/impacto.

**Este parágrafo já esteve errado e é a razão de o outro existir.** Ele dizia
"Top 3: exportar conversa, chips de sugestão rápida, sumarização automática de
contexto" — e **as três foram entregues na 0.3.1**, há mais de um ano de
versões. Uma lista de próximos passos que só aponta para o que já foi entregue
não está desatualizada: está **invertida**, e é pior do que não ter, porque
induz quem a lê a concluir que o resto também está pronto.

A regra do repo já vale para prosa em geral — uma versão repetida em três
lugares, uma delas errada, e nada no repositório que reclame — e vale mais ainda
para "o que fazer depois". Um próximo passo que já foi feito custa o mesmo que
um número de versão errado: um ciclo inteiro de trabalho para descobrir que não
havia trabalho.

**A fila aberta, na ordem em que o `HANDOFF` justifica:**

1. **A hipótese da quantização** — `Q4_K_M` contra `Q4_0` do **mesmo** modelo.
   É o único item que muda advice para **36 dos 46** do catálogo, e o advice
   atual está comprovadamente errado (o menor modelo é o mais lento). O
   catálogo **não tem** nenhuma família em duas quantizações, então o par vem de
   fora dele.
2. **Os 4 `litertlm` restantes.** "GPU é o melhor LiteRT neste aparelho" veio de
   **um** modelo, o 0.6B; nenhum dos outros é um 0.6B.
3. **Uma entrada de catálogo `.tflite`.** O console funciona, mas o único arquivo
   utilizável foi empurrado à mão. A rota barata é uma cabeça de **uma entrada**
   só — a regra do "maior input" tornou isso trivial, e ela cobre o caminho feliz
   sem auxiliares.
4. **Fechar a fila antiga de UI**: overflows restantes, nomes e comentários dos
   modelos, quantização por swipe no card.
5. **A 0.6.0**, com o critério do repo: minor = feature, e "isto faz X, que antes
   não existia" tem que sair verdadeiro.
