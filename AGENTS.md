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

Estudo completo (em português) na raiz do workspace: `docs/KMP_MIGRATION_ANALYSIS.md`
(começa por um fact-check datado), `docs/KMP_MIGRATION_PLAN.md`,
`docs/KMP_BUILD_LIMITATIONS.md`. **Reabrir só se o Llamatik ganhar LiteRT** ou se o
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
APK **não tem interpretador TFLite** — `liblitertlm_jni.so` é LiteRT-LM
generativo e não serve. Isso é a primeira coisa a resolver, e é por isso que
`/v1/classify` foi landado agora sem modelo atrás: o endpoint é o contrato, o
modelo vem na 0.4.1.

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
gancho equivalente aqui — `planLiteRtTier` decide por `npuAvailable` e nunca
mediu.

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

## O que falta: micro-benchmark no LiteRT (decidido, não implementado)

`planLiteRtTier({required String mode, required bool npuAvailable})` devolve
NPU → GPU → CPU e **nunca mediu nada**. Para o GGUF isso foi consertado pela
faixa de tamanho, que é extrapolação acima de 1B; para o LiteRT **não há nem
isso**, porque a escolha é feita antes de qualquer número existir.

Se for implementado, o que já está medido e precisa ser respeitado:

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
  roda a cada carga custa mais do que ele informa. Por isso a resposta honesta
  para GPU pode ser "sempre GPU, e é isso" — o que precisa ser **medido uma vez**,
  não decidido de memória.

O que faria a frase "isto faz X, que antes não existia" sair verdadeira: hoje
não há como saber qual backend o LiteRT deveria usar neste aparelho. Com o
micro-benchmark, há — e ele é por aparelho e por modelo, não por tabela.

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

## Sugestões de próximas features

Ver [`docs/suggestions.md`](docs/suggestions.md) para lista completa organizada
por esforço/impacto. Top 3: exportar conversa, chips de sugestão rápida,
sumarização automática de contexto.
