# mobileLM — Agent Guide

Objetivo do repo: mix do **PrivateLM** (motor local Flutter) com **PocketStrike-AI**
(camada de agente). Fonte da verdade do roadmap: [`docs/PLAN.md`](docs/PLAN.md) — leia antes de qualquer tarefa.

## Estado atual

M1 ✅ · M2 ✅ · M3 ✅ · M4 ✅ · M5 ✅ — releases publicadas em
<https://github.com/dollarbr/mobileLM/releases>. Versão atual: **0.4.0+2006**.
Engine local (GGUF + LiteRT-LM 0.17.1) + agente multi-passo + tools nativas
(24 built-in, 8 privilegiadas via Shizuku) + tarefas agendadas + image gen +
servidor OpenAI compatível + **encoders (embeddings/rerank/classify, BERT e
ModernBERT)** + cloud models com auto-detect de contexto/capabilidades.

## Encoders — o que a 0.4.0 trouxe (leia antes de mexer)

Dez encoders no catálogo (7 rerankers, 3 embedders), served por
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

**A `0.4.1` é o classificador de verdade, e a rota é TFLite.** Laya
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
`+build`: `0.4.0+2006` → tag `0.4.0`. O workflow falha de propósito se divergirem.
Tags com prefixo `v` (ex: `v0.3.0`) também são aceitas. As notas saem agrupadas por
prefixo de Conventional Commit; o que não casa com nenhum prefixo cai em "Other",
então nada some.

Release tags publicadas: `0.2.3` (M4), `0.3.0` (cloud + métricas), `0.3.1` (exportar, chips, sumarização), `0.3.2` (PDF→markdown, clamp cloud correto, tools de arquivo removidas quando documento anexado), `0.3.3` (catálogo: LFM2.5-VL, Spark X2.5, Qwen3.5), `0.3.4` (release signed com a chave de verdade), `0.4.0` (encoders: `/v1/embeddings`, `/v1/rerank` e `/v1/classify`; 10 encoders no catálogo; console de encoder; parâmetros por papel; `config.json` como pre-flight no HF).

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

| ABI | índice | `0.4.0+2006` sai como |
|---|---|---|
| `armeabi-v7a` | 1 | 3006 |
| `arm64-v8a` | **2** | **4006** |
| `x86_64` | 4 (o 3 foi reservado e removido) | 6006 |

O APK arm64 da 0.3.5 tem `versionCode='4005'`, medido com `aapt2 dump badging` —
`2 * 1000 + 2005`. Sem `--split-per-abi` o override não se aplica e o versionCode é
o número cru; é por isso que as releases antigas (2001, 2002, 2003) batem com o
build number e a 0.3.4 não bate. **Não compare pubspec com `dumpsys` sem essa conta.**

Regra prática: o que precisa crescer é o **publicado**. Os publicados até 0.3.3
foram 2002, 2003, 2001, 2001, 2001, 2001, 2001 — ad-hoc, e 0.2.1 (2001) é *menor*
que 0.2.0 (2003), uma regressão. O maior publicado é **4004** (0.3.4, medido), e
a 0.4.0 usa `+2006` e publica 4006 — pulando o 4005 da 0.3.5 que nunca saiu. Daqui
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

## Notas de build

- Máquina: 12 hybrid cores (10 e-core + 2 p-core). `org.gradle.workers.max=2` no
  `gradle.properties` — nunca sature todos os núcleos.
- Threads: 4 é o ótimo no Edge 60 (4×A78+4×A55); 8 regressa porque A55 trava A78.
- R8 está desligado (`isMinifyEnabled = false`). Não adicione regras ProGuard por
  precaução — elas não fazem efeito e podem mascarar problemas reais.
- **Plugins locais com `dependency_overrides` podem não ser detectados pelo Flutter plugin discovery.** Se `dart_plugin_registrant.dart` não inclui, registrar manualmente no `MainActivity`.
- Modelo pequeno (<2B) prefere CPU no prefill: GPU (Vulkan) tem overhead de shader
  que domina até ~2B parâmetros. `n_gpu_layers==0` deve zerar a lista de dispositivos,
  não apenas pular offload — senão ggml sched offloads ops pro Vulkan (`op_offload`).

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
