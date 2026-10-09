# mobileLM — Agent Guide

Objetivo do repo: mix do **PrivateLM** (motor local Flutter) com **PocketStrike-AI**
(camada de agente). Fonte da verdade do roadmap: [`docs/PLAN.md`](docs/PLAN.md) — leia antes de qualquer tarefa.

## Estado atual

M1 ✅ · M2 ✅ · M3 ✅ · M4 ✅ · M5 ✅ — releases publicadas em
<https://github.com/dollarbr/mobileLM/releases>. Versão publicada: **0.6.0+2009** (tag `0.6.0`; arm64 medido em `versionCode=4009`).
O pubspec está em **`0.7.0+2010`** — a próxima minor, e ela é a **consistência por
permutação** de um decision model: `/v1/classify` mede se a resposta muda com a ordem
das opções, a resposta diz **como** a letra foi achada, e a janela mostra os dois.
**Meça o asset dela antes de escrever qualquer número**: o esperado é `4010`, e se
der outra coisa é a fórmula e não o pubspec.
Engine local (GGUF + LiteRT-LM 0.17.1) + agente multi-passo + tools nativas
(24 built-in, 8 privilegiadas via Shizuku) + tarefas agendadas + image gen +
servidor OpenAI compatível + **encoders (embeddings/rerank/classify, BERT e
ModernBERT)** + cloud models com auto-detect de contexto/capabilidades.

**`POST /v1/systemone` — o endpoint de decisão tipada — não existe no app, e o
substrato nativo dele já está todo no APK.** O `libllama.so` exporta
`llama_batch_ext_set_decision_order`, tem `llama_model_clef`, tem
`N_DECISION_TYPES = 3` no `lfm2.cpp` e no `modern-bert.cpp`, e `llama-ext.h`
nomeia os três tipos (`noul`/`choice`/`score`) e `option`. **Faltam três arquivos
tocados e nenhum:** Pigeon, `jni_wrapper.cpp`, e a rota. A seção
"`/v1/systemone` é um padrão entre vendors" no fim do guia tem a medição completa
(`nm -D`, `strings`, `examples/`, conversor, e o teto de 1,19 GB do A72).

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

**O último projeto é persistido, e essa era a parte que faltava.** A herança
existia e funcionava — `currentProjectPath` é lido por `_createNewChat` — mas
era **só em memória**: `loadSessions()` carrega a lista e não abre conversa
nenhuma, então num cold start a próxima conversa nova abria o picker de novo
enquanto a tela dizia que a escolha lembrava. `keyLastProjectName` +
`WorkspaceService.rememberedProject` fecham isso, e `_createNewChat` lê três
fontes em ordem: a conversa aberta, o projeto lembrado, o picker.

**Abrir uma conversa não grava o padrão, e "No project" não limpa.** As duas são
decisões, não efeitos colaterais: `openChat` deixar isso reescrever o padrão faria
revisar uma conversa antiga mudar silenciosamente onde as novas caem, e um "No
project" dito sobre *aquela* conversa não é sobre a próxima. Só o picker grava. O
nome é validado contra a listagem viva porque a pasta pode ser apagada fora do
app — o descarte vai para `droppedProject` para a UI poder dizer.

**`openFolder` não desce para uma pasta que repita o nome do pai.**
`WorkspaceEntry` carrega só `name`/`isDir`/`size`, nenhum caminho, então navegar
era relativo e recalculado a cada toque — e `TESTES` dentro de `TESTES` crescia
sem limite. A regra está em `lib/services/workspace_paths.dart` (puro, 12
testes) e a recusa **devolve o caminho atual** em vez de lançar, então o pai
continua terminando no mesmo nome e os toques seguintes também são recusados.
`A/A/B/A` continua legal: a regra é sobre o pai imediato.

**O `Row` do dialogo de projeto virou `Wrap`** — quarta vez que este repo paga
por isso, e o número do log era **24 px na escala de fonte padrão do app**, ou
seja não é caso de quem mexeu no tamanho da letra. `test/
project_picker_layout_test.dart` monta **o `Row` ruim dentro do teste** e afirma
que ele estoura, de propósito: a primeira versão abria o diálogo real e afirmava
o overflow, o que faz a asserção morrer junto com o conserto.
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

**A `0.7.0` foi pedida como `0.6.1` e subiu como minor, e a razão vale mais que o
número.** O trabalho da consistência por permutação cria três coisas que não
existiam: o `/v1/classify` aceita `variants` e mede se a resposta muda com a ordem das
opções; a resposta carrega `match` e `followed_contract`, dizendo **como** a letra foi
achada — o shape `decision` só produzia `label` e `choice`, e esses dois campos são
**idênticos** para `B`, `B.` e `billing`; e a janela mostra os três blocos novos,
inclusive no caminho da recusa. A frase sai verdadeira: *"o app diz se a resposta de
um decision model sobrevive a reordenar as opções, diz como a letra foi encontrada, e
não diz quando isso não foi medido"*. Patch seria uma versão cuja descrição não sabe
dizer o que mudou.

**E foi a segunda vez que um `versionCode` é o que trava a atualização, não a tag.** O
maior publicado é **4009** (`0.6.0`, medido no asset com `aapt2 dump badging`), logo
`build + 2000` tem que passar de 4009: `0.7.0+2010` dá **4010**. Um número folgado
seria aceito e um número parado derrubaria a instalação com
`INSTALL_FAILED_VERSION_DOWNGRADE` — e nenhum dos dois aparece no `pubspec`.

`0.6.0` é o **seletor de idioma**: Auto / English / Português (Brasil), com
**inglês como padrão**. A frase sai verdadeira — *antes não existia escolha de
idioma*: era `locale: Get.deviceLocale` com fallback `pt_BR`, e a consequência
medida foram 62 fichas de modelo em inglês numa tela que se dizia portuguesa.
Agora existem **905 chaves nos dois idiomas** e uma ficha por modelo em cada um.
Isto está em "O idioma é escolhido, e o padrão é inglês".

Não é minor "traduzir o app para inglês": a 0.5.1 já tinha metade das chaves
traduzidas para português, e traduzir não cria nada. O que cria é **a escolha**,
que é o que o dono pediu ao descrever o sintoma.

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

**Um build pode falhar por um download corrompido do NDK, e a falha não é do
código.** `ndkVersion = flutter.ndkVersion` em `android/app/build.gradle.kts` — ou
seja, o NDK **não está fixado neste repo**: ele vem do SDK do Flutter que o
`subosito/flutter-action@v2` instala, e o Gradle o **baixa da CDN do Google na
hora de configurar o projeto**. Em 2026-10-06 o `debug-apk.yml` da `main` morreu
em `Build debug APK` com isto:

```
com.android.builder.sdk.InstallFailedException:
  ndk;27.0.12077973 NDK (Side by side) 27.0.12077973
Caused by: java.util.zip.ZipException: Archive is not a ZIP archive
```

**O que prova que não é o código, e é a checagem de 10 segundos:** no mesmo run,
`flutter analyze` e `flutter test` passaram, e o `Debug APK` **da tag, no commit
idêntico, disparado 13 segundos depois**, passou. `gh run rerun <id> --failed`
resolve quando é isso.

**A mensagem aponta para o SDK e para o `INSTALL_FAILED` do Gradle, e nenhum dos
dois tem a ver com o repositório.** A leitura de quem procura defeito vai direto
para "o build quebrou" e para a versão do plugin — e a versão do plugin é a mesma
do commit que passou ao lado. O conserto real (instalar o NDK com `sdkmanager` e
versão fixada, como passo próprio, para o download ser retentável e a versão não
mudar quando o Flutter muda) **não está feito**; se aparecer de novo e o
`rerun` não resolver, é este passo que falta.

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
`+build`: `0.6.0+2009` → tag `0.6.0`. O workflow falha de propósito se divergirem.
Tags com prefixo `v` (ex: `v0.3.0`) também são aceitas. As notas saem agrupadas por
prefixo de Conventional Commit; o que não casa com nenhum prefixo cai em "Other",
então nada some.

Release tags publicadas: `0.7.0` (a resposta de um decision model diz se ela se sustenta: `/v1/classify` mede a consistência por permutação com `variants`, a resposta carrega `match`/`followed_contract`, e a janela mostra os três blocos — inclusive na recusa; **arm64 medido em `4010`**, assinatura `1cd43cb7…`, 86 MB), `0.6.0` (o idioma é escolhido — seletor Auto /
English / Português (Brasil), **inglês como padrão**, e 905 chaves nos dois
idiomas; fecha o item 3e com a varredura ampla em zero), `0.5.1` (a escada de aceleração passou a ver o tamanho do modelo), `0.5.0` (pinning automático nos núcleos grandes + benchmark de CPU corrigido), `0.2.3` (M4), `0.3.0` (cloud + métricas), `0.3.1` (exportar, chips, sumarização), `0.3.2` (PDF→markdown, clamp cloud correto, tools de arquivo removidas quando documento anexado), `0.3.3` (catálogo: LFM2.5-VL, Spark X2.5, Qwen3.5), `0.3.4` (release signed com a chave de verdade), `0.4.0` (encoders: `/v1/embeddings`, `/v1/rerank` e `/v1/classify`; 10 encoders no catálogo; console de encoder; parâmetros por papel; `config.json` como pre-flight no HF).

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

| ABI | índice | `0.6.0+2009` sai como |
|---|---|---|
| `armeabi-v7a` | 1 | 3009 |
| `arm64-v8a` | **2** | **4009** |
| `x86_64` | 4 (o 3 foi reservado e removido) | 6009 |

**⚠️ A linha do arm64 esteve errada por duas releases, em 1000, e foi a única linha
errada.** A tabela dizia `5008` para `0.5.1+2008`, e as outras duas conferem com
a fórmula — `1 * 1000 + 2008 = 3008` e `4 * 1000 + 2008 = 6008`. O arm64 é
`2 * 1000 + 2008` = **4008**, e o pior não é o número: é que **a linha errada é a
do único ABI que este app publica**, porque todo build passa
`--target-platform android-arm64`.

**E ninguém pode notar uma tabela errada conferindo o build, porque o build não a
consulta.** Os índices são lidos de `ABI_VERSION` por `filterIdentifier`, em
`FlutterPlugin.kt:671`, no SDK — a tabela do guia é documentação, não entrada de
build. Por isso o erro sobreviveu duas releases inteiro: **um número que não
participa de nada também não denuncia nada**, e o único jeito de pegá-lo é medir o
APK.

Conferido contra a fonte e contra os assets, **não calculado**:

| release | `pubspec` | `2 * 1000 + build` | `aapt2 dump badging` |
|---|---|---|---|
| `0.5.1` | `0.5.1+2008` | 4008 | **`4008`** |
| `0.6.0` | `0.6.0+2009` | 4009 | **`4009`** |
| `0.7.0` | `0.7.0+2010` | 4010 | **`4010`** |

A `0.7.0` confirma a fórmula pela terceira vez, e a assinatura também: `CN=dollarbr`,
SHA-256 `1cd43cb7…` — **a mesma chave da `0.3.4`**, que é a primeira assinada com a
chave do projeto. Quem tem a `0.6.0` instalada **atualiza por cima**; quem tem uma
qualquer das sete anteriores, com chave de debug diferente, precisa desinstalar
primeiro.

A prosa tinha o mesmo defeito pelo mesmo motivo: *"O maior publicado é **5007**
(0.5.0, medido)"*. O maior publicado era **4007** — o `5007` é o mesmo salto de
milhar, quase com certeza a transcrição de `4007` que produziu `5007` e que a
tabela depois herdou em vez de conferir contra a fórmula.

**O que a conta errada teria custado.** A regra escrita mandava `build + 2000`
ficar acima do publicado, e o publicado estava errado em 1000: quem a seguisse
precisaria de `+3008` ou mais, quando `+2009` bastava — e o `+3008` seria aceito,
porque **build number folgado não quebra install**. O que quebra é o número ficar
errado para sempre, porque o próximo mede o maior publicado a partir do mesmo
erro e aplica o mesmo deslocamento.

**E eu calculei errado na hora de marcar a tag.** O aviso que fiz para mim mesmo
na shell dizia `2 * 1000 + 2009 = 6009`, e a decisão de subir a minor estava
certo por outro motivo: `4009 > 4008`, que é o que importa. Ou seja, o critério
estava certo e a aritmética que o justificava não estava — **é a forma mais
silenciosa de um número errado**: não muda a decisão, então nada denuncia.

Regra prática: o que precisa crescer é o **publicado**, e o publicado do arm64 é
`build + 2000`. O maior publicado é **4009** (0.6.0, medido no asset com
`aapt2 dump badging`). Daqui em diante: bump de release ⇒ `build` tal que
`build + 2000` fique acima do publicado anterior, senão o update falha com
`INSTALL_FAILED_VERSION_DOWNGRADE`. **Meça o asset depois de cada release** — a
fórmula é de uma linha e a medição leva trinta segundos:
`gh release download <tag> -p '*-arm64-v8a.apk' && aapt2 dump badging <apk> | grep ^package`.

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

### A ficha do catálogo é texto de tela nos dois idiomas

As **62** descrições (46 do catálogo + 16 encoders) estavam em inglês numa tela
`pt_BR`. O `Text` da ficha em `model_view.dart` não tem `maxLines`, então a
string inteira era pintada — e uma ficha que é o nome do arquivo de alguém em vez
da sua é texto faltando, não dialeto.

**Uma das 62 estava truncada de verdade, e este guia disse que cinco.** A
correção importa mais do que o número, porque o erro tem uma forma que se repete
neste repo: **o diagnóstico de "texto faltando" era o meu próprio bug de
extração aparecendo como achado.** Quatro das cinco "frases partidas" terminavam
em `"above"`, `"matters."`, `"matters."` e `"here."` — frases completas. O que
acabava nelas era o **primeiro segmento** de um literal adjacente, e o Dart
concatena os vizinhos em tempo de compilação:

```dart
'description':
    'Reranker cross-encoder, ModernBERT, Portuguese and English. Measured '
    'on an Edge 60 at 111 ms per query with a real logit spread of '
    '2,07. The one to start with.',
```

A única truncada é a `SmolLM2 135M`, que terminava em `"before they describe
this"` — e o `this` pendente é o que denuncia. **Uma lista de supostos defeitos
que a próxima pessoa não vai conferir é pior do que nenhuma**, porque é o que a
convence a não olhar; por isso o teste de hoje fixa **uma** string por idioma, com
`endsWith` e não `contains` — a correção ficou `"…this model"`, que *contém* a
string quebrada, e com `contains` o conserto era reprovado pelo teste que existe
para exigi-lo.

**O defeito de verdade era maior do que parecia, e a regex foi o que escondeu.**
**18 das 62 descrições são literais adjacentes em Dart**, e isso derruba qualquer
regex sobre o arquivo por três motivos ao mesmo tempo: o valor ocupa **várias
linhas**; pode usar **aspas simples ou duplas** (3 entradas usam duplas, porque
contêm `Microsoft's`); e `dart format` **remove o espaço entre os segmentos**,
então `'a ' 'b'` vira `'a' 'b'`. Três versões de regex falharam em sequência, e a
última **colou texto novo em cima do antigo** — `"…aparelhos compouca RAM"`, que
parece traduzido e não está.

**A reescrita é um programa Dart, não uma regex.**
`tool/rewrite_catalog_descriptions.dart` usa o scanner do próprio Dart para achar o
valor, e ele lê **todos** os segmentos, entende **os dois delimitadores** e devolve
**um** literal. As traduções estão em `tool/catalog_pt.json` e
`tool/catalog_en.json`, no formato burro `nome<TAB>texto` — um JSON escrito à mão
quebraria na primeira aspa dentro de um texto, e isso aconteceria.

**O scanner errou de duas maneiras opostas, e as duas dão a mesma mensagem.**
Deixar `i` **na** aspa de abertura (em vez de `j + 1`) devolve um segmento vazio e
para depois do primeiro — foi assim que 18 descrições pareceram truncadas. Avançar
a aspa **duas vezes** (uma em `j + 1` e outra lendo `delim = src[i]`) pega a
letra seguinte e devolve `null`. A primeira simula um problema de aspas duplas; a
segunda parece que o arquivo não fecha.

**O espaço entre segmentos vai DENTRO do literal.** O Dart concatena vizinhos sem
separador, então o espaço vai antes da aspa de fechamento — `'texto '`, e **não**
`'texto' `, que é o que o formatador produz quando tira o espaço entre segmentos e
dá o mesmo resultado: `"…o primeiro qwen3que o app…"`. E a última linha **não** leva
espaço: um `trimRight` no fim do join age sobre a string do fonte, que termina em
`'`, não em branco, e o espaço sobrava *dentro* do valor.

**Não rode `dart format` no `constants.dart` nem no `model_view.dart`.** Nenhum
dos dois está no formato do formatador no `main` — confirme com
`dart format --output=none` antes de confiar num diff. Formatá-los reescreve ~100
linhas sem relação com a tradução: o diff do `model_view.dart` passou de **9
linhas** para **129** só por isso.

### O idioma é escolhido, e o padrão é inglês

`LanguagePreference` (`lib/services/language_preference.dart`, puro) + um seletor
em Configurações → Aparência. **Auto**, **English**, **Português (Brasil)**.

**O app já foi `locale: Get.deviceLocale` com `fallbackLocale: pt_BR`**, e o
resultado medido foi: 62 fichas em inglês numa tela que se dizia portuguesa, e um
aparelho fora do português sem poder pedir outro. Deduzir foi o que produziu o
problema, então deduzir virou **opção explícita** e o padrão passou a ser uma
escolha declarada.

Quatro decisões que não são óbvias:

1. **O padrão é `en`, não `auto`.** O GetX devolve a própria chave para uma
   tradução que não existe, e foi assim que 38 chaves apareceram como
   `tool_round_trips` e `mobile_lm` sem nada lançar. Um idioma sem mapa inteiro
   renderiza 905 identificadores. `LanguagePreference.padrao` tem um teste que
   falha se virar `auto`.
2. **O `fallbackLocale` é `en_US`, não `pt_BR`.** Com o fallback em português, uma
   chave que faltasse em inglês aparecia *traduzida* e ninguém notava que faltava.
   Com o fallback no padrão ela aparece como o próprio identificador, que é o que
   o `l10n_keys_test` transforma em falha de CI.
3. **O `SettingsController` é lido antes do `GetMaterialApp`, não no `builder`.**
   O `locale` é decidido antes do primeiro `build`, e a tela que muda o idioma só
   existe depois. Ler de dentro do `builder` resolve o primeiro quadro num idioma
   e troca depois — o flicker que ninguém pediu.
4. **Os rótulos do seletor NÃO passam por `.tr`.** O nome de um idioma é o dado, e
   um dado traduzido deixa de identificar o idioma: em português o item diz
   "Português (Brasil)", em inglês "Portuguese (Brazil)". `"Automatic"` e
   `"Automático"` é o único que se traduz, porque não é nome de idioma.

**Um valor desconhecido cai em `auto`, e não em `en`.** Um valor corrompido
virando `en` fixo transforma um bug de armazenamento numa preferência que a pessoa
nunca fez e não sabe desfazer; `auto` é a única resposta que não está *errada*.
Mas `EN`, `en_US` e `pt-BR` são **a mesma escolha com outra grafia** e são
normalizados para a opção — a comparação é em minúsculas e o retorno é a grafia
canônica. Jogar `EN` para `auto` troca o idioma da pessoa sem ela pedir, que é
exatamente o modo de falha que a normalização existe para evitar.

**O prompt de sistema segue o idioma da tela**, e a redação é "a língua que o app
está mostrando, e a língua em que você escrever" — não o antigo "responda em
português brasileiro", que agora seria falso metade das vezes. Um app que pede em
português com a interface dizendo que fala inglês é a inconsistência que o seletor
veio tirar.

**Verificado no A72**: install debug, o app abre em inglês com `Hello.` /
`How can I help today?` / `Type your message…`; o seletor aparece com os três
chips (o `Wrap` quebra em duas linhas, como tem que); tocar em **Português (Brasil)**
troca a tela **na hora**, sem reiniciar — `Configurações`, `Aparência`, `Idioma`,
`Português (Brasil)` — e "English" continua escrito em inglês no chip, que é o
comportamento certo.

### Os dois campos com o idioma no nome

`AiModel` tem `descriptionEn` e `descriptionPt`, e **não tem `description`**. Um
campo só que "significa português" é conhecimento tribal de quem lê o catálogo, e
com EN como padrão ele publica português num app inglês **sem nenhum aviso** — a
tela mostra *alguma* descrição, e uma descrição presente não parece erro.
`LanguagePreference.descricao()` é quem decide, e a queda é do pedido para o que
existe, nunca para a string vazia: uma ficha em falta mostra a linha em branco num
card que já tem nome, tamanho e template, e o vazio parece defeito do aparelho.

Uma entrada antiga do Hive tem só `description` — importada antes de o catálogo
ficar bilíngue — e ela vale nos dois idiomas. A alternativa é pintar a linha
vazia.

**`descriptionSearch` é a busca nos dois idiomas.** `isVisionModel` e
`isUncensoredModel` procuram marcadores no texto, e um modelo não fica com visão
nem perde a censura conforme o idioma da tela. Ler só uma metade fazia o `VL` de
uma linha desaparecer quando o app estava em inglês.

### O `.tr` que faltava: 34 textos que eram literais em português

Quatro conjuntos de texto de tela **não passavam pelo mapa** e eram literais em
português — o modo exato de falha que o seletor veio fechar, e nenhum aparecia em
revisão de código:

| onde | o que era |
|---|---|
| `chat_view.dart` | as **16** sugestões do estado vazio, em literais |
| `chat_bubble.dart` | os **6** chips de resposta, rótulo **e** prompt |
| `settings_view.dart` | os **9** rótulos de seção e os **3** modos de tema |
| `settings_view.dart`, `server_controller.dart`, `chat_view.dart` | `"No model loaded"` |

**Os chips têm rótulo e prompt como chaves separadas**, porque o prompt vai para o
modelo: um chip que *parece* localizado e manda um prompt em português para um
modelo em inglês é pior do que chip nenhum. E não podem ser valores `const` já
traduzidos — `.tr` é um método de runtime sobre o locale atual, então uma lista
`static const` congelaria a língua do boot, que não é a que a pessoa escolheu.

**As 16 sugestões ficaram literais de propósito, e não um `'suggestion_$i'.tr`.**
O `l10n_keys_test` reprova chave montada em runtime — porque uma chave dinâmica
**não é auditada**, e a auditoria é o que impede a chave faltar. O teste pegou, e
estava certo.

**Os rótulos de seção levam `.tr` e `toUpperCase` juntos, e nessa ordem**: PT-BR e
EN diferem na caixa de letras acentuadas, e a regra de exibição (caixa alta,
entreletra 1.4) pertence ao estilo da seção, não à tradução.

### Os literais de tela: 63 → 102 → 123 → 0, e uma classe que recusa ser automática

O `AGENTS.md` dizia que sobravam **63**. Eram **102**, depois **123**, e a
contagem esteve errada **cinco vezes**, sempre pelo mesmo motivo: **a trava
media menos do que dizia.** A tabela é o registro, e cada linha é uma omissão
diferente.

| contagem | o que a media mal |
|---|---|
| 51 | filtro mais frouxo que o atual |
| 63 | o regex só casava `Text(`; `title:`, `label:`, `labelText:` e `hintText:` usam **dois-pontos**. Faltavam 39 |
| 102 | `Text` é **sufixo** de `labelText`, `hintText` e `tooltip`. Sem `(?<![A-Za-z_])` o mesmo literal contava 2-3 vezes. Eram 112 posições |
| 123 | a varredura só olhava o **primeiro** argumento depois de `subtitle:`. Quase todo tile deste app tem `subtitle: cond ? 'a' : 'b'` e **os dois ramos eram invisíveis** |
| **0 (com o teto em zero e a tela em inglês)** | **`subtitle` não estava na lista de call sites.** Três legendas em inglês ao lado de um teto em zero |

**A última linha é a que importa.** As três legendas eram `subtitle:` de
`ListTile`, e a lista de call sites — o que a trava conta — não tinha o nome. Um
teto em zero é a **mesma falha** que um teto alto: o número parou de ser
informação, e só o aparelho diz. Foi o A72 que disse, com o build instalado e
`dump` na tela.

**A lista de call sites tem que incluir todo parâmetro que PINTA texto**:
`subtitle`, `helperText`, `prefixText`, `suffixText`, `errorText`,
`semanticCounterText`. `message` e `hint` **não** entram: aparecem em código que
não é tela, e a lista é o que a trava conta — broaden aqui é o caminho para o
teto subir sem ninguém traduzir.

#### Duas varreduras, e por que duas

`tool/inline_english_scan.dart` é **estreita de propósito**: só o primeiro
argumento de `Text`, `title:`, `subtitle:` e companhia, e ignora o que tem `$`.
É o conjunto que a máquina pode reescrever, porque **o valor no fonte é o valor
na tela**. `tool/inline_english_broad.dart` olha **todo** literal e é o que
mostrou que a dívida era de duas ordens de grandeza maior.

Os números que saem:

| varredura | total | de que é |
|---|---|---|
| estreita | **0** | nada sobrou reescrevível |
| ampla | **343** | **0 de texto de tela**, 343 de identificador, dado, rota, exemplo e comentário |

**Os 343 são o que sobrou do item 3e, e o número de texto de tela é zero.**
Antes de traduzir eles foram **216**, e só apareceram porque um bug de regex foi
corrigido — a mesma varredura reportava **zero** com 263 atrás. A seção "O bug
que escondeu 263 textos" está abaixo e vale mais que o número. E eles já foram
**257**: a seção "O `juntarSegmentos` resolveu o primeiro segmento e não os do
meio" diz por que 45 deles nunca foram dívida. Subiram para **252** quando a lista
de palavras foi alargada por uma sonda, caíram para 205 depois das duas correções
que a seção "O `@ramGB` que pintava uma tela vermelha" descreve, voltaram para 216
quando a décima primeira omissão parou de engolir o ramo `:` dos ternários, e
desceram a **zero** com o item 3e — 148 literais diretos e 33 interpolados.

**O total subiu de 526 para 343 sem que nenhum texto novo aparecesse**, e a
explicação é a sonda: `recommended`, `parameters`, `enabled`, `off`, `ram`,
`ultra`, `mid`, `tier`, `detected`, `generation` entraram na lista de palavras e
passaram a classificar **18 literais** que eram dados como texto de tela. **Um
número de total que cai quando a lista de palavras cresce é o detector ficando
mais honesto, e não a tela ficando mais limpa** — é por isso que a contagem de
total nunca foi a métrica.

**`lib/controllers` entrou porque o A72 mostrou `DOWNLOADED` numa tela em
português.** O título da seção do catálogo é texto de tela e vivia no controller,
com `section.title.toUpperCase()` na view — e **as duas varreduras só andavam em
`views` e `widgets`**, então nenhuma via. É a mesma classe de erro pela quinta
vez, e agora por **omissão de pasta** em vez de omissão de parâmetro.

**`section.title` é chave persistida, e é em inglês de propósito.**
`expandedSections` é um `Set<String>` no Hive e `toggleSection` compara por esse
valor: traduzir faria uma seção expandida em inglês **colapsar** quando o app
passa para português, e o conjunto salvo ficaria com as chaves antigas. O
defeito aparece como "a tela perdeu o que eu tinha aberto" e não como erro.
`ModelSection` por isso tem `title` (a chave) e `labelKey` (a tradução), e a view
pinta `section.label.toUpperCase()`.

**GGUF, LiteRT e TFLite não têm chave de tradução** porque não precisam: são o
nome do formato e o do repositório de origem, e traduzi-los diria algo diferente
do que o arquivo é.

**O teto da varredura ampla é ZERO, e a escolha é deliberada nos dois
sentidos.** Com 216 linhas reais, zero seria um teste que passa pelo motivo
errado — a mesma falha do teto alto pelo lado oposto. Zero só é honesto
**depois** de o número medido chegar a zero, e é o que o item 3e fez: **205
textos de tela**, entre 148 literais diretos e 33 interpolados, mais as exclusões
que a lista de não-texto absorveu. O que a varredura mede agora são **343
literais** que são identificador, dado, rota, exemplo ou comentário — cada um com
o motivo escrito. **A trava estreita continua em zero**, e é a que protege o que
a máquina reescreve.

**O item 3e foi fechado pelo aparelho, não pelo contador.** As duas últimas
levas de texto em inglês apareceram no `uiautomator dump` do A72 com o teto em
**zero** — `📱 Mid-range (4.8GB) — Good for 1-3B models` no card de memória e
`NPU unavailable on SM7125 — no vendor driver reachable` no card do NPU. As duas
estão fora do alcance das três varreduras, e por motivos **estruturais**, não de
acerto do detector:

- **`device_info_service.dart` monta a frase do card de memória**, e serviço está
  fora da lista de diretórios. **641** literais de tela estão em `lib/services`,
  e **135 deles são a lista de palavras do próprio detector** — ampliar a trava
  para a pasta agora publicaria um teto de 641 que não protege nada, que é a
  mesma falha de um teto alto. A pasta está **medida e anotada**, não publicada.
- **`NpuStatus.toString()` vive num plugin local**
  (`local_plugins/flutter_litert_lm/`) e é pintado por `s.toString()` na view. Um
  `toString()` que é tela é um literal que nenhum detector de view alcança por
  construção. O conserto é o serviço reportar **fatos** — `available`, `soc`,
  `libraries`, `systemDriver` — e a tela falar; foi o que virou
  `settings_view._npuFrase`.

**E `Recommended: @q` era um literal interpolado na tela que a varredura não
contava**, porque `recommended` não estava na lista de palavras — e é uma palavra
comum de interface, a que qualquer substring de quantização traz junto. **Um
detector que não conhece a palavra não denuncia o texto**, e o teto estava em
zero. A sonda (`tool/word_list_probe.dart`) expôs **6** textos de uma vez, e a
segunda leva de palavras expôs **12** — a mesma regra da décima omissão, agora
com o mecanismo escrito: **a lista só cresce por sonda, nunca por leitura do
código**, porque ler o código é o que dá a lista que já existe.

**O rótulo de bloco do catálogo é chave de ordenação E texto pintado**, que é o
formato do `section.title` de novo. `_byModality` agrupa por `'Text'`/`'Vision'`/
`'Multimodal'`/`'Image generation'` e ordena com `order.indexOf(a)`; traduzir a
string tiraria a ordenação. `ModelBlock` ganhou `labelKey` ao lado de `label`, e
quem pinta é `block.labelKey.tr.toUpperCase()` — caixa alta e `.tr` **nessa
ordem**, porque PT-BR e EN diferem nas letras acentuadas.

**`static const` com valor traduzido congela a língua do boot — e `static final`
congela do mesmo jeito, só mais tarde.** O mapa `pipelineTag` do HF era
`static const` e o conserto natural foi `static final` com `.tr` dentro, porque
`.tr` num `const` não compila (`const_eval_extension_method`). **Essa correção
trocou um defeito por um pior e ninguém notou no aparelho**: `final` de campo é
inicializado **uma vez**, preguiçosamente, na primeira leitura — e essa primeira
leitura congela a língua do boot. Trocar o idioma no seletor reconstrói a tela
inteira e os chips de faceta continuavam no idioma antigo, **sem erro nenhum**.

A regra que fecha os dois é a dos chips de resposta: **o mapa guarda a chave, e
quem pinta traduz.** `Text(e.value.tr)`. Aí o mapa volta a ser `const`, o valor
consultado é a chave, e a tradução acontece no `build` — que é o único lugar que
vê o locale atual.

**E um `.tr` sobre variável não é auditado, que é o lado invisível da mesma
decisão.** `l10n_keys_test` casa `'chave'.tr` **literal**; `e.value.tr` e
`f.label` não são literais, então a chave não existe para o detector. Chave
faltando renderiza o próprio identificador, que é o modo de falha mais silencioso
que existe, e o teste de auditoria continua verde porque nunca viu a chave.
`test/l10n_keys_test.dart` ganhou `chavesIndiretas()`, que faz a **afirmação
oposta** — lê esses mapas no fonte e confere cada valor contra os dois idiomas.

**A defesa tem que poder falhar, e a primeira versão não podia.** O teste passou
com `any('hf_any_X', '')` no enum e `hf_mergekit` fora do mapa. A causa foi um
regex: `any\('([a-z0-9_]+)',` casa **zero** vezes num fonte onde o token está
plainly escrito, e `[^']+` no mesmo lugar casa uma. O enum passou a ser lido
**token a token** (`indexOf("'")`), e a auditoria tem **três provas** de que
falha: chave do mapa sumida, chave do enum sumida, e o mapa inteiro renomeado
(que dá `StateError` com a mensagem, não zero chaves com o teste verde).

**`HfFormat.any.label` era `'Any'` e é agora `labelKey`.** `GGUF` e `LiteRT-LM`
são nome de formato e não se traduzem — e `Any` é o único dos três que é palavra,
num enum que mora em `lib/services`, fora do alcance das três varreduras. A mesma
forma do `ModelBlock.labelKey`: o nome do dado fica, a tradução vem em getter.

**O `hint` de um campo e o cabeçalho de um grupo são texto de tela, e nenhum dos
dois é catálogo.** `Min`/`Max` (dois campos), `Any — or an owner, e.g.
bartowski` (o hint) e os quatro cabeçalhos de grupo (`Modality`, `Provider`,
`Misc`, `Quantisation`) estavam em literal. **E a caixa alta é do estilo, não da
tradução**: os valores do mapa são `Quantização` em forma natural e quem aplica
é `_label` com `.toUpperCase()` — PT-BR e EN diferem nas letras acentuadas, e
`QUANTIZAÇÃO` é o caso que prova.

São **19** rótulos de faceta, não os ~30 que o `HANDOFF` dizia — o número estava
estimado por leitura de nome de mapa em vez de medido, que é o mesmo defeito que
este arquivo descreve em outros lugares.

**`text-generation` é a tag que vai para a API do hub**, e é comparada com a
resposta da busca; traduzir esvazia a lista de resultados sem erro. O que a pessoa
lê é o **valor** do mapa, com chave própria.

**Os 343 da ampla não se traduzem, e a lista diz por quê.**
`TextLanguage.naoTexto` tem 59 entradas, cada uma com o motivo: `'local'` é
identificador de runtime comparado com `==`, `json['loaded']` é chave de payload,
`frequency.startsWith('every')` é comparação, `'List models'` é chave de exemplo
JSON, `'# 202, then poll …'` é comentário de shell. **Traduzir qualquer um deles
muda comportamento sem erro nenhum** — o item some da lista, o acesso devolve
`null` e o `??` cobre. Uma lista de exclusão sem motivo é uma lista que ninguém
confere, e o efeito é o oposto do pretendido.

Cinco regras de contexto, cada uma com forma própria de detecção: **dentro de
comentário** (`//` no começo da linha), **dentro de exemplo de comando** (`curl `,
`client =`, `#`), **dentro de caso de teste do encoder** (`query:` e `documents:`
são o que o modelo recebe), **a própria linha de um exemplo de shell**, e
**fragmento entre dois trechos** (`'x'.split('\n')` casava `).first;\n  model =`
como literal).

**O filtro de não-texto mora em `lib/services/text_language.dart` e é o mesmo
para a ferramenta e para a trava**, junto com a lista de palavras. Duas listas em
dois arquivos divergem em silêncio — foi o que a auditoria de overflow, a de
overflow de linha e a de descrição de catálogo fizeram neste repo — e aqui a
divergência foi **contada**: a ferramenta via `Text('READY')` e a trava não; a
trava via `'No project'` e a ferramenta não.

#### O bug que escondeu 263 textos: a classe de caracteres do regex

A varredura ampla reportava **zero** texto de tela em `views`, `widgets` e
`controllers`, e havia **263** — número que só apareceu quando o teto da trava foi
posto em zero **e** a lista de palavras foi alargada.

**A classe de caracteres estava errada desde que a ferramenta foi escrita.**
`[^\'\\n]` num literal Dart não-raw vira `[\'\\n]` no regex, e essa classe exclui a
**letra `n`** — não a quebra de linha. Qualquer literal com `n` no meio nunca
casava. `'Warning: values above 8192…'` tem um `n` em *Warning*; `'Anúncio'` em
português e `'Cancel'` em inglês ficavam de fora **pelo mesmo motivo, em idiomas
opostos**. Não era um filtro de idioma — era um filtro de letra.

O mesmo valia para a janela `{2,90}`: literal de mais de 90 caracteres nunca
casava, e literal longo é exatamente prosa, que é o que fica em inglês numa tela
traduzida.

**Os três sintomas eram o mesmo: a contagem batia.** Zero texto de tela, zero
controller, zero chave faltando, `flutter test` verde. Um detector que não casa
nada reporta a mesma coisa que um detector que não acha nada, e a única forma de
saber qual é o dos é ter **um irmão que prova que ele ainda vê alguma coisa**.

Isso é a **sétima** vez que a lista do que a trava mede estava incompleta, e a
sexta vez que o número esteve errado. A tabela:

| omitido | como |
|---|---|
| `title:`, `label:` (só casava `Text(`) | o regex ignorava dois-pontos |
| `Text` como sufixo de `labelText` | contava o mesmo literal 2-3 vezes |
| ramos de ternário depois de `subtitle:` | só o primeiro argumento era lido |
| **`subtitle` na lista de call sites** | três legendas em inglês com o teto em zero |
| **`lib/controllers` na lista de diretórios** | `DOWNLOADED` em português, teto em zero |
| **a letra `n` na classe do regex** | 263 textos de tela com o teto em zero |
| a janela de 90 caracteres | as mensagens de aviso mais longas |
| **os inicios do meio de um literal adjacente** | **45 fragmentos no teto, que era 257 e é 212** |
| **`${…}` julgado como idioma** | **36 falsos positivos: `DateTime.now()` é `now`** |
| **palavras medidas fora da lista** | **10 textos que nenhuma das duas varreduras contava** |
| **o ramo `:` de qualquer ternário** | **11 textos engolidos como campo de idioma** |

**A décima segunda e a décima terceira vieram do aparelho com o teto em zero**,
e as duas são a mesma forma da quinta: uma **pasta ou palavra faltando** na lista
do que a trava mede. A quinta foi `lib/controllers` com `DOWNLOADED`; a décima
segunda foi `lib/services` com o card de memória (`📱 Mid-range (4.8GB) — Good
for 1-3B models`); a décima terceira é a lista de palavras sem `recommended`,
`parameters` e `enabled`, que expôs 18 textos de uma vez. **Um serviço pinta texto
e o nome do arquivo não diz que não** — a regra "serviço é lógica, view é tela"
nunca foi escrita em lugar nenhum deste repo, e é a ausência dela que a quinta e a
décima segunda exploraram.

**A lição que vale para as treze**: uma lista do que a trava mede é uma
**afirmação**, e uma afirmação não se prova sozinha. Cada uma delas só apareceu
por causa externa — o `dump` do aparelho, ou a lista de palavras alargada por um
motivo completamente diferente. A defesa não é revisar a lista com cuidado, é
**ter um teste que conte o que está do outro lado**.

⚠️ **A oitava linha é de uma família diferente das outras sete, e é por isso
que ela custou mais para achar.** As sete são **ausência** — uma pasta, um
parâmetro, uma letra na classe do regex. Ausência se nota, porque o que falta
aparece. A oitava é **repetição**, e **repetição não denuncia**: nada está
faltando, o contador só contou a mesma coisa duas vezes, e o resultado é um teto
maior que o necessário — que é a falha mais difícil de ver deste arquivo inteiro,
porque um teto alto parece conservative e não errado.

⚠️ **A nona linha inverte o sinal, e é a única que é um falso positivo.** As oito
anteriores medem de menos; esta media **a mais**, e a defesa é a mesma pergunta
com o sinal trocado: **o que a trava está contando que não é texto?** O caso é
`DateTime.now()`: `now` é palavra da lista, o `${…}` é código, e
`'mobilelm_${DateTime.now()…}.png'` — o nome do arquivo temporário do
compartilhamento de imagem — entrava como texto de tela em inglês. **36 entradas**,
todas com a mesma forma. `pareceInglesAmplo` remove a interpolação antes de
julgar, que é a mesma regra que a trava dos interpolados já usava.

⚠️ **A décima é a mais quieta de todas, porque o sintoma é um teto em zero que
está certo.** As 27 palavras medidas (`show`, `back`, `copy`, `benchmark`,
`clear`, `name`…) expuseram **10 textos que estavam em inglês na tela desde
sempre** e que nenhuma das duas varreduras contava: `Copy important logs`,
`Clear logs`, `Show it anyway`, `Provider name`, `Base URL`, `Projector`, `Turn
off anyway`, `CPU benchmark`, `Back to projects`, `New project name` — mais o
literal interpolado `Available: …GB · Context: …` de Configurações. **Um detector
que não conhece a palavra não denuncia o texto**, e nenhuma das três travas pode
acusar o que elas não veem. A defesa é a sonda: `tool/word_list_probe.dart` julga
a lista pelo lado que falha — texto de tela que ela **deveria** ver e não vê.

⚠️ **A décima primeira é a única que ESCONDE, e por isso é a pior das onze.**
`eCampoDeIdioma` existe porque o `dart format` quebra a atribuição entre o nome do
campo e o literal, e subia uma linha quando a de cima começava com `? `. Isso
tratava o **ramo `: '…'` de qualquer ternário** como campo de idioma:

```dart
showDetails
    ? 'Hide Technical Details'
    : 'Show Technical Details',      // ← não era texto de tela
```

**O sintoma é assimetria dentro do próprio ternário**, e é por isso que só
apareceu quando a tradução começou: `Hide` na lista como TEXTO e `Show` como
DADO, no mesmo `cond ? a : b`. **11 textos** estavam escondidos — um botão, duas
mensagens de estado, um rótulo de campo, dois parágrafos.

**Teto baixo e teto alto são o mesmo defeito: os dois números estão errados, e o
baixo parece prudente.** Um detector que esconde não é menos perigoso que um que
exagera — é mais, porque exagerar é visível no número.

A correção é olhar **duas linhas acima**: a linha do `?` só é ramo de um
`descriptionEn` se o campo estiver antes dela. E a defesa é **a assimetria como
asserção**, não o caso do catálogo: um `descriptionEn` legítimo é raro e está num
arquivo só, um ternário com dois ramos de tela é comum e está em todos — então o
teste afirma que os **dois** ramos do mesmo ternário recebem a mesma classificação,
o que pega a regra larga sem depender de nenhum arquivo em particular.

**A defesa da oitava também é diferente, e é uma pergunta que nenhuma das outras
sete exigiu: quantas vezes a mesma posição é medida?** Detalhar o que a trava mede
não responde isso — as duas contas podem estar certas e ainda assim somar a mesma
frase duas vezes. Está em `test/inline_english_ratchet_test.dart`, com o nome de
`a varredura ampla não conta o mesmo literal duas vezes`, e em
`tool/dup_probe.dart` como a medição que deu 87 grupos e 155 inicios extras.

#### `juntarSegmentos` passou a ser do módulo compartilhado

`[^\'\\n]` mascarava outro defeito: a varredura ampla casava **um segmento por
vez**, e o Dart concatena literais vizinhos em tempo de compilação. Então
`'know whether a local model is worth'` aparecia na lista como pendência — e não
é traduzível, porque **a frase não está ali**: a primeira metade já é `.tr`.

`TextLanguage.juntarSegmentos(src, ini)` devolve `(texto, ondeParou)`, resolve o
escape (`\n` virando a letra `n` é o defeito da `"…tasks arenscheduled…"`) e
entende os dois delimitadores. **As três ferramentas a chamam** — a estreita, a
ampla e a trava — e uma implementação é o que impede a contagem de divergir.

**Um `Set` de posições vistas é POR ARQUIVO, e essa é a parte que custou um
ciclo.** Com um conjunto único para os 27 arquivos, um índice de fim de segmento
em `model_controller.dart` suprime o literal que começa na **mesma posição
numérica** de `server_view.dart`: os arquivos têm comprimentos diferentes e as
posições não significam nada entre eles. A contagem ficava 12 abaixo, e a
ferramenta — que declara o conjunto dentro de `_varre` — dizia 258. Um número
menor não é um número errado que se vê; é um que parece certo e protege menos do
que parece.

#### O `juntarSegmentos` resolveu o primeiro segmento e não os do meio

Com ele a contagem foi para **257**, e **45 deles nunca foram dívida**. O
`vistos` marcava `m.start` e o `fim` da cadeia — e um literal adjacente de quatro
linhas tem **três inicios no meio**, que passavam por `vistos.add` sem estar lá
dentro. Cada um deles **reconstruía a mesma frase sem o primeiro segmento**:

```dart
? 'Downloads the 230M model and runs it in '
    'CPU Safe mode, then reports your real '   // ← contada como achado próprio
    'tok/s. Nothing is downloaded or run '
    'until you tap.'
```

`'CPU Safe mode, then reports your real tok/s. Nothing is downloaded or run
until you tap.'` estava na lista como pendência, e não é traduzível: a frase
completa começa no segmento de cima, e é ela que a tela mostra. Traduzir o
fragmento apagaria o resto da frase.

**`juntarSegmentos` recebe agora `inicios:` e devolve quais posições consumiu.**
Os dois chamadores marcam todos, e o teto passou de 257 para **212**. `tool/
dup_probe.dart` é a medição — 87 grupos, 155 inicios extras — e ela espelha o
`vistos` da ferramenta **letra por letra**, porque uma sonda com lógica própria de
deduplicação mede a si mesma.

**Um literal aninhado não é repetição, e a distinção é o que segura o teste.**
`'${x ? '' : ' '}'` tem dois literais dentro de um terceiro e sempre vai ter: os
três alcançam o mesmo `fim`, mas **só um** passa pelo `vistos`. O que o teste
proíbe é dois **achados** com o mesmo `fim`. Sobram **4** em `server_view.dart` —
aspas duplas dentro de um `'''` de exemplo de `curl`, que o regex vê e o
`juntarSegmentos` atravessa — e os quatro são `DADO`, então não entram no teto,
que conta só texto. Fechar os 4 exige saber que a interpolação raw começou num
`'''`, que o regex não vê; a sonda registra por que eles ficam.

#### A nona omissão: `${…}` é código, e `DateTime.now()` é `now`

`pareceInglesAmplo` julgava o literal **inteiro**, interpolação inclusive, e
`now` é palavra da lista. Então `'mobilelm_${DateTime.now()…}.png'` — o nome do
arquivo temporário do compartilhamento de imagem — entrava como **texto de tela em
inglês**, junto com `$name`, `$filename`, `$e` e cia. **36 entradas**, e nenhuma
delas é dívida.

É a **única** das dez omissões que é um falso positivo: as outras nove medem de
menos, e esta media a mais. E o sintoma de um número alto é o mais difícil de ver
deste arquivo inteiro, porque teto alto parece conservative.

O conserto é `pareceInglesAmplo` chamar `tirarInterpolacoes` antes de julgar, que
é a mesma regra que a trava dos interpolados já usava — o idioma é do **trecho
fixo**, e o trecho fixo é o que vai para o mapa. Não é uma lista de exclusão nova
para cada `${…}` que apareça: é a regra, e a regra não cresce.

#### `Unknown size` era sentinela e texto ao mesmo tempo

A mesma string estava em **dois papéis que não podem coexistir**:

- `detectUrlSize` a devolve, o diálogo compara com `==`, e `AiModel.size` a guarda
  no Hive. **Traduzir quebra a comparação**, e o sintoma não é um texto errado na
  tela: é um `Unknown size` do runtime caindo na frase genérica de erro.
- `Text(model.size)` a pinta, e o campo **é** o valor nos dois idiomas.

Um literal solto não separa "comparei com isto" de "isto vai para a tela", e é essa
separação que a varredura não conseguia fazer. `AppConstants.kUnknownSize` é o
nome, e a tradução existe em **um** ponto de pintura. `hf_search_service` tem os
dois getters pelo mesmo motivo — `sizeLabel` traduzido, `sizeValor` cru — e o
diálogo de adicionar usa o segundo, porque é ele que vai para o Hive.

**O campo de tamanho do diálogo ficou vazio em vez de escrito com um rótulo.** O
campo é editável e o que está nele vira `AiModel.size` quando a pessoa confirma:
escrever "Tamanho desconhecido" ali gravaria a tradução no Hive, e o card
mostraria português num app configurado para inglês, para sempre. A linha de aviso
logo abaixo é o que a pessoa precisa ler.

#### O `@ramGB` que pintava uma tela vermelha

O conserto acima jogou 16 chaves novas no mapa, e uma delas era
`'Available: @ramGB · Context: @ctx · Tokens: @tok'`. O `preencher` lê
`@([A-Za-z_][A-Za-z0-9_]*)`, e **`GB` colado no nome é parte do nome**: `@ramGB` é
*um* placeholder, não `@ram` seguido de `GB`. A tradutora escreveu o que parece
perfeito, porque `@ram` é o nome do valor e `GB` é a unidade, e a leitura humana
faz a separação que o regex não pode fazer.

O sintoma no aparelho foi o pior possível para um erro de texto: a `ArgumentError`
de `preencher` **cai dentro do `build`**, e o Flutter troca o `Text` inteiro por um
retângulo **vermelho** que ocupa a linha toda. O log dizia `a chave
"set_device_budget" tem @ramGB sem valor`, e a tela dizia Configurações inteira
vermelha — a leitura óbvia é "o app quebrou", não "faltou um espaço na tradução".

**A regra: unidade, sufixo e pontuação vão FORA do placeholder.** `@ram GB`,
`@ctx tokens`, `@n×` — nunca `@ramGB`. Sem o espaço não há como distinguir, e a
distinção é o que o helper existe para fazer. O teste novo em
`test/text_interpolation_test.dart` procura `@nome` com letra ou dígito colado em
**todo** valor dos dois mapas.

Isto é a décima omissão da lista de palavras em forma de **consequência**: as 27
palavras medidas expuseram o literal interpolado que nenhuma das duas varreduras
contava, e traduzi-lo **no mesmo dia** expôs o defeito do helper. Nenhum dos dois
seria visível sozinho — o primeiro porque a lista era curta, o segundo porque o
texto estava em inglês e portanto nunca tinha sido escrito como chave.

#### O que a varredura ampla achou que não era texto

Dos achados em `lib/controllers` (item 3d), **onze não eram texto**, e três são
os que machucam se alguém traduzir:

- `'system'` — **role do contrato OpenAI**. O servidor recusa se vier traduzido.
- `'light'`, `'dark'` — valor de tema salvo no Hive, comparado num `switch`.
- `'failed to load gguf split'`, `'failed to load model from buffer'`,
  `'out of memory'`, `'corrupt'` — **substrings procuradas com
  `lower.contains()`** dentro da mensagem de erro do engine. Traduzir
  `'out of memory'` não põe um texto errado na tela: **faz a detecção de falta de
  memória parar de casar**, e o sintoma é um `out of memory` do engine caindo na
  frase genérica de erro.
- `'Custom GGUF Models'` e irmãs — **chave de `expandedSections`, persistida**.
- `'log.error(...)'` — o log vai para o arquivo que a pessoa abre para
  diagnosticar; a busca por `Restore failed` é como se acha um erro.
- `descriptionEn:` — o campo **já é** a tradução em inglês.

**A lista de não-texto não pode crescer sem motivo, e há um teste que a lê pelo
outro lado.** Cada entrada tem que **existir** como literal no fonte — a
afirmação oposta à que a varredura faz. Provado: trocar
`lower.contains('out of memory')` por `lower.contains('memória esgotada')` deixa
a trava **verde**, e é o teste que pega. O mesmo teste acha **entrada morta**:
na primeira rodada ele acusou `step`, `steps` e `Load`, que já não existem mais
porque foram traduzidos — uma lista de exclusão que ninguém audita cresce com
lixo, e o lixo esconde exclusões reais.

**O teste precisa dos dois delimitadores.** `"step"`, `"steps"` e `"Load"` estão
com aspas duplas **dentro** de um literal de aspas simples, e a checagem por
`'x'` não os via — as três entradas estavam vivas na lista e nenhuma aparecendo
no fonte, que é o mesmo resultado de uma lista vazia por um motivo diferente.

**Duas regras de contexto que só `lib/controllers` exigiu:**

- **`log.error(` / `.warning(` / `.info(` / `.debug(`** — o primeiro argumento é
  mensagem de log. A marca é o **nome do método**, não o do receiver, porque
  `Get.snackbar` é justamente o par que a regra precisa separar: as duas frases
  são idênticas e aparecem na mesma tela.
- **`descriptionEn:` / `descriptionPt:`** — o campo **é** a tradução. O nome
  pode estar **uma linha acima**, porque o `dart format` quebra a atribuição entre
  a condição e o literal; ler só a linha do literal dá `false` e o texto entra na
  contagem. Subir só quando a linha de cima é a condição de um ternário, senão um
  `label:` uma linha acima seria pego.

#### `BackButton` já desenha uma seta — o que estava em inglês era o tooltip

O `dump` do A72 mostrou `Back` no botão de voltar da tela do servidor, e a
reação natural é trocar o botão por uma seta. **A seta já estava lá**:
`BackButton` é o `leading` padrão de todo `AppBar`, e ele desenha
`Icons.arrow_back`. O `Back` não era texto pintado — era o
`tooltip`, e o `uiautomator` expõe tooltip como `content-desc`.

E o tooltip vinha de `MaterialLocalizations.backButtonTooltip`, que o GetX
instala **só em inglês**: o `GetMaterialApp` registra o
`DefaultMaterialLocalizations`, um stub sem nenhum outro idioma. O resultado é o
mesmo defeito de sempre — uma tela em português com uma palavra em inglês — e a
mesma ausência de aviso: nada no repositório diz que as strings do Material
existem em dois idiomas, porque elas **não são do app**.

`flutter_localizations` no `pubspec.yaml` e três delegates em `main.dart`
resolvem. E resolvem **muito mais que o tooltip**: `OK`/`Cancel` de
`AlertDialog`, `Copy`, `Retry`, as datas de todos os seletores e qualquer
`tooltip` do Material passam a seguir o idioma escolhido — que é exatamente o
que o seletor de idioma promete.

**`supportedLocales` é obrigatório junto, e sem ele o conserto não pega.** Com os
dois delegates e sem a lista, o `GlobalMaterialLocalizations` resolve só os
idiomas que já vêm no padrão e o `locale` escolhido cai no primeiro. Foi o
segundo `dump` que disse: `Settings`/`Appearance` trocavam, o botão não.

**A ordem dos delegates importa** — Material depois de Cupertino, e o do app por
último, porque cada um sobrescreve o anterior.

Verificado no A72 nos dois sentidos: **Português → `Voltar`**, **English →
`Back`**. O botão em si é a seta nos dois.

**Uma coisa que continua em inglês e não é do Material:** o `AppBar` sem
`AppBarTheme` próprio não tem título de accessibility próprio, e o `Back` do
Material é a única palavra que vinha de fora. Se um dia aparecer outra, o
delegado é o caminho.

#### Dois helpers com o mesmo nome e contratos diferentes

`settings_view.dart` e `server_view.dart` têm **os dois** um
`_sectionLabel`, e nenhum dos dois é visível do outro porque é `private` de
biblioteca. O de settings fazia `Text(chave.tr.toUpperCase())` — recebia **chave**
e traduzia dentro. O do servidor fazia `Text(title)` — recebia **texto pronto**, e
quem chamasse passava a chave sem `.tr` por acidente.

**A tela do servidor showed `sc_section_security` onde deveria mostrar
`SEGURANÇA`.** Nada reclamou: `l10n_keys_test` afirma que a chave **existe** no
mapa, e existia; o `GetX` devolve a própria chave para uma tradução que ele não
encontra, que é o modo de falha mais silencioso que há. Só o `dump` do A72 disse.

O conserto é o contrato, não o `.tr` da chamada: **receber a chave**, como o outro
faz. Quem escreve `_sectionLabel(context, …)` não tem como passar texto sem
`.tr` por acidente, porque a tradução está dentro do helper. Três call sites
passavam literal — `'ENDPOINTS'`, `'USAGE EXAMPLES'` e a chave solta.

**É a mesma família do `.tr.tr`**: um valor que é identificador num lugar e texto
no outro, e a leitura é idêntica nas duas situações. Por isso a regra do repo
continua sendo: **`.tr` é método de runtime e nunca fica em `const` nem é
esquecido dentro de um helper** — o helper recebe a chave.

#### Um mojibake que a varredura achou

`Get.snackbar('âš ï¸ Warning', warning, ...)` — o emoji de aviso gravado como
UTF-8 lido como latin-1: três bytes viraram três caracteres, e um deles é um
espaço não separável. **O título do aviso aparecia como lixo na tela**, e nenhuma
das três varreduras via, porque `'âš ï¸ Warning'` não tem palavra de inglês que a
lista conhecesse. Agora é `set_warning_title`.

#### A reescrita casa por TEXTO, e a linha é a coisa errada

`tool/catalog_inline.tsv` é `texto-em-inglês<TAB>chave<TAB>português`. **A primeira
versão era `arquivo:linha`**, e a linha se move: reescrever um literal adjacente
de três linhas como `'chave'.tr` **apaga duas linhas** e empurra todas as de
baixo. Depois de uma reescrita de 102 literais, as 21 posições medidas antes
apontavam para o lugar errado — e a ferramenta aceitou, porque ela confia na
posição. **Foi o único erro deste trabalho que não dava aviso nenhum.**

O texto é seguro como chave porque **os nove textos repetidos têm tradução
idêntica nas duas chaves** ("Show API key" em dois cartões, "System One test",
"Context Size"). O escritor **recusa** um texto repetido com traduções
diferentes, e o recusa dizendo isso: o casamento por texto não distingue os dois,
e a segunda tradução é a que a tela mostra.

**O inglês nunca é digitado.** `tool/catalog_inline_en.json` é extraído pela
própria ferramenta do fonte, e o escritor **confere** cada valor contra ele antes
de escrever os mapas. Um arquivo de traduções com uma coluna de inglês é uma
segunda cópia que diverge em silêncio, e a divergência apareceria como uma ficha
errada na tela em vez de um erro aqui.

#### Oito defeitos da ferramenta, e a razão de ela ser Dart

Cada um custou um ciclo:

1. **`reversed` não é ordem inversa de posição.** A lista de achados é montada
   percorrendo os rótulos um a um — todos os `Text`, depois todos os `title`.
   Reverter inverte a ordem *dos rótulos*, e uma substituição cedo foi aplicada
   sobre índices que já não valiam: **111.828 linhas inseridas** em catorze
   arquivos.
2. **`novo` já continha o prefixo**, que também era prefixado de novo: o começo
   do arquivo era escrito duas vezes por substituição. O sintoma é o buffer
   dobrando na primeira e não voltando.
3. **O `const` qualificador é removido e o construtor **reposto**. A primeira
   versão tirava `const ` e **não** repunha `Text(`, o que deu **118 erros de
   sintaxe** em vez de 29 de `const`.
4. **A busca do `const` vai para trás a partir do literal**, pulando branco,
   **exigindo uma abertura de construtor**, e para só no fim do statement. Uma
   versão anterior parava na primeira linha acima e não achava
   `subtitle: const Text(` com a string na linha seguinte, `decoration: const
   InputDecoration(`, `const _SectionLabel(`, `return const [` — 16 sobraram.
   **Linha de argumento não encerra a busca**: `labelText: 'Value',` fica entre o
   `const` e o literal.
5. **`src[k + 1]` não desescapa.** Para `\n` grava a letra `n`, e o texto saía
   `"…tasks arenscheduled…"` — uma frase sem separador, que passa em revisão de
   código e só aparece na tela.
6. **Escapar duas vezes.** O `\n` chegava como dois caracteres e o escritor
   dobrava: `\\n` no fonte, que o Dart lê como barra mais `n`. A versão que
   resolvia de um lado e não do outro escreveu **uma quebra de linha real dentro
   de um literal**, que não compila, e o erro apontava para a linha 491 de um
   arquivo de 1200 linhas.
7. **Um literal que JÁ é `.tr` não é texto em inglês.** Sem a guarda,
   `'settings'.tr` virou `'nav_settings'.tr.tr` — que **compila**, porque o
   segundo `.tr` é só mais uma chamada, e mostra a chave no lugar do texto.
   Nenhum teste reclamou: o analyzer não tem o que dizer e a chave existe no mapa.
8. **`.tr.tr` e `src[k+1]` produzem o mesmo tipo de erro**: uma leitura é
   idêntica ao texto em duas formas, e só a checagem seguinte olha.

**Um `setUp` que registra as traduções, e o motivo de ele ser o conserto e não a
edição das asserções.** Três testes de layout procuram **o texto em inglês que
aparece na tela**. Sem `Get.addTranslations`, `.tr` devolve a própria chave e
todos falham sem que nada tenha mudado. Trocar as asserções para a chave faria o
teste parar de checar o texto real.

`Get.addTranslations(AppTranslation().keys)` — o **mapa**, não a classe
`Translations`. E `Get.locale = const Locale('en', 'US')` e **não**
`Get.updateLocale(...)`: o segundo é assíncrono e reconstrói a árvore, o que
dentro de `setUp` dispara `'inTest': is not true`.

#### A classe que recusa ser automática: o literal interpolado

`looksEnglish` devolve **falso** para qualquer texto com `$`, e está certo: o
valor no fonte não é o valor na tela, e trocar o literal inteiro por uma chave
apagaria a parte que muda. A consequência é que a varredura **não vê nada
disso** — e havia **35** em telas, todos no mesmo formato: um trecho fixo em volta
de um ou dois valores.

A trava é a mesma, com uma regra a mais: **o idioma é do que SOBRA depois de
tirar a interpolação.** Passar o literal inteiro a `looksEnglish` dava zero
sempre, e a trava passava com a tela em inglês.

A solução é `lib/services/text_interpolation.dart`, e a função **`preencher`**
troca `@nome` por valor. O GetX tem `trParams`, e ele é o padrão dele — mas
substitui por uma chave só, e metade destes textos tem **dois** valores, um no
meio e outro no fim. **E `trParams` não serve dentro de uma interpolação**: é um
método de `String`, e o resultado de `'chave'.tr` é um `String` estático para o
analyzer.

**Um `@nome` que sobra é erro, e a conferência é ANTES da troca.** Um `@n`
esquecido apareceria na tela como `@n` — o mesmo defeito do GetX devolvendo o
próprio identificador. E conferir **depois** da troca recusa texto legítimo: um
valor com `@` no meio (um email, um nome de arquivo como `meu@model.gguf`) cria
um placeholder que ninguém pediu. O conjunto de placeholders vem da
**tradução**, que é onde ele está escrito.

**Um ternário dentro de um `@valor` não é traduzível.** A escolha acontece em
Dart e o texto dos dois ramos tem que existir nos dois idiomas — foi o que
aconteceu no relatório de status do console `.tflite`, que virou quatro chaves
com a quebra de linha em Dart, e no vetor de features, que tinha um ternário
aninhado com literais próprios dentro da interpolação e virou três.

#### O que a guarda de idioma pegou logo depois de escrevê-las, e era verdade

- `nav_settings` e `nav_appearance` estavam com o valor **em inglês** no mapa PT.
  A auditoria de "as chaves são iguais nos dois idiomas" não pega: a chave está
  nos dois. E as duas eram **duplicatas** de `settings` e `appearance`, que já
  existiam — a rodada anterior criou chave nova para texto que já tinha.
- **Uma palavra emprestada é português**, e a segunda vez: `Template` é a mesma
  palavra nos dois idiomas, e `https://searx.example.org/search` é exemplo de URL.
- **Palavras que são as duas línguas.** `do` é a forma auxiliar do inglês
  ("**Do** not suggest this again") e uma das palavras mais comuns do português;
  `no` é o "não" do inglês e uma preposição do português. Sem uma lista de
  colisões, o detector acusa a frase **inglesa** como portuguesa.

#### Chave repetida: o Dart aceita, a tela funciona, e o arquivo mente

Um literal de mapa aceita chave repetida, e `flutter analyze` **não reclama**. A
segunda sobrescreve a primeira, o app funciona e a linha errada continua no
arquivo. Aconteceu com `set_hops_one` e `set_hops_many`: uma inserção por
`replace` casou as duas ocorrências da âncora, uma no mapa EN e outra no PT.

O resultado na tela estava **certo** — a última vence — e a contagem de chaves
também batia, porque `Map` já havia perdido a multiplicidade e um `Set` de
chaves não vê duplicata. `nenhuma chave é repetida` lê o **fonte**, contando
ocorrências, e é a única forma de ver isso.

**O `l10n_keys_test` lia comentário.** O padrão `'x'.tr` casava o exemplo na
explicação de um `const` removido, e acusava duas chaves que só existem num
comentário. Nenhuma das duas é uma chave, e o teste as pedia no mapa.

## Aparelhos de teste

| Aparelho | Papel | Regra |
|---|---|---|
| **Galaxy A72** (SM-A725M, Snapdragon 720G / SM7125, **/e/OS e-4.3, Android 15**, **4,78 GB** (`MemTotal` 5011844 kB), `adb root`) | **debug** — é onde tudo é medido | recebe debug à vontade. A tela dele **estraga**: a imagem aparece mas o touch não responde, então tudo é feito por comando adb, nunca por toque. Não é quebra do aparelho e não é reparável aqui. |
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

O A72 tem 4,78 GB (`MemTotal` medido). A escada recusaria, com razão. O Edge 60 (até 12 GB) caberia,
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

**O procedimento, e ele funciona — o switch não está quebrado.** O que o
`bounds` do nó não diz é a **posição** do alvo, e é a única coisa que falta.
Medido no A72: a linha vai de `x=45` a `x=1035`, o switch real tem **169 px** e
está na **direita**, ou seja `x` entre 866 e 1035. Tocar no centro da linha
(`540`) acerta o texto e nada acontece; tocar em `950` liga o servidor.

```sh
A=RQ8R3077LMF
adb -s $A forward tcp:8091 tcp:8091        # o forward não é opcional: sem ele
                                             # o curl vai para o vazio, e 000 não
                                             # distingue "servidor fora" de "porta
                                             # fechada"
adb -s $A shell input keyevent KEYCODE_WAKEUP
adb -s $A shell wm dismiss-keyguard
adb -s $A shell input tap 405 2253          # aba Configurações
for i in 1 2 3 4 5 6 7; do adb -s $A shell input swipe 540 1900 540 600; done
adb -s $A shell input tap 540 1596          # o tile "Servidor de API local"
adb -s $A shell input tap 950 404           # PONTA DIREITA da linha, y do switch
curl -s -m 10 http://127.0.0.1:8091/health  # 200 = deu certo
```

Os `y` acima são de uma rolagem específica e **mudam** se a lista mudar; o `x=950`
não muda, porque é a ponta da linha. A sequência robusta é: `dump`, achar o nó
`Switch` cujo texto contém `API Server`, e usar **`x2 - 42`** — um quarto da
largura do switch para dentro da ponta direita:

```sh
# com o dump em /tmp/_s.xml
python3 - <<'PY'
import re
d = open('/tmp/_s.xml', encoding='utf-8', errors='replace').read()
for tag in re.findall(r'<node[^>]*>', d):
    if 'class="android.widget.Switch"' not in tag:
        continue
    t = re.search(r'text="([^"]*)"', tag)
    label = t.group(1) if t else ''
    if 'API Server' not in label:
        continue
    x1, y1, x2, y2 = map(int, re.search(
        r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', tag).groups())
    print(x2 - 42, (y1 + y2) // 2)   # x, y do toque que funciona
PY
```

**Confirme pelo estado, não pelo toque.** `HTTP 200` em `/health` é o teste; o
texto do nó (`API Server Running`) é o segundo. Se os dois falharem, o toque
errou o alvo — não que o switch esteja quebrado, e não peça para o usuário tocar.

### A geração de imagem mata o app — `Cannot invoke native callback outside an isolate`

**Isto é um defeito, não uma limitação do aparelho, e ele nunca aparece antes de
existir um `.safetensors`.** A sequência inteira foi medida no A72 com
`DreamShaper8_LCM` (1,99 GB, sha256 conferido nos dois lados):

```
[LocalImageService] Trying backend: CPU
[LocalImageService] Creating SdIsolateProcessor (backend=CPU, quant=Q4_K (recommended))...
F libc : Fatal signal 6 (SIGABRT) in tid 6679 (DartWorker)
E Dart : runtime_entry.cc: 5327: error: Cannot invoke native callback outside an isolate.
E DartVM: Aborting reentrant request for stack trace.
```

**350 ms entre "criando o processor" e o abort.** O `SIGABRT` é do runtime do
Dart, não do C++: `abort()` chamado pela VM depois que `Dart_InvokeClosure` recusa
uma chamada.

**A causa, e ela é de lifecycle e não de thread.** `setupCallbacks` é chamado
**de dentro** do isolate novo (`sd_isolate_processor.dart:264`) e faz
`Pointer.fromFunction` de dois callbacks. Um `Pointer.fromFunction` só pode ser
invocado **daquele isolate** — a VM guarda a identidade no ponteiro e aborta se a
chamada chegar de outro contexto.

E a chamada chega de outro contexto. `stable-diffusion.cpp` chama o callback de
progresso dos **workers do ggml**, que são threads do processo e não belongs a
isolate nenhum. O caminho do trampoline é
`sd_progress_cb` → `sd_ffi_progress_trampoline` (`:394`) →
`g_ffi_progress(step, steps, time)`, e essa última linha é um ponteiro para Dart
called de uma thread sem isolate. Logo: `Cannot invoke native callback outside an
isolate`, e o processo morre.

**O caminho JNI do mesmo arquivo não tem o problema, e é por isso que ele
funcionava.** `sd_progress_cb` (`:70`) guarda um `jobject` e usa
`thread_local JniEnvGuard` — anexa a thread ao JVM e desanexa na saída. O FFI
não tem equivalente: `Pointer.fromFunction` **não** tem como ser chamado de uma
thread arbitrária, e nenhum guard nativo resolve, porque o problema é a VM do Dart
não a thread.

**Consertado, e a correção tocou os dois lados.** `NativeCallable.listener` no
Dart e um `void*` a mais no typedef C — porque o `listener` exige o `user_data`
como último argumento, e a assinatura antiga de 3 argumentos não é um deles.

O detalhe que custou uma volta: **o `listener` quer retorno `void`, não
`Pointer<Void>`.** Escrevi o contrário com base no nome da API e o analyzer
disse *"The return type of the function passed to 'NativeCallable.listener' must
be 'void' rather than 'Pointer<Void>'"*. A correção no C foi a mesma: `void(*)`
com `void*` no fim, não `void*(*)` com `void*` no fim.

O `user_data` que o C passa é `nullptr` na chamada de passo 0 e o `data` do
ggml nos trampolines. **O lado Dart não o usa**, e é o certo: ele é o handle da
VM para o callable, não carga útil.

**Três coisas no conserto que só a leitura do arquivo inteiro mostra:**

1. **Havia um terceiro call site** do callback, `g_ffi_progress(0, steps, 0.0f)`,
   na linha 596 — o "passo 0 imediato" que o upstream não dá. Ele **não** está
   ao lado dos outros dois, e o `grep` por `g_ffi_progress(` acha três linhas.
   **O compilador do NDK achou em segundos**, com `-fsyntax-only` e sem link.
2. **`setupCallbacks` recria os callables, e não é `??=`.** O `clearCallbacks`
   fecha o par anterior, então guardar o ponteiro e reaproveitar deixaria o
   nativo apontando para um callable que a VM já desregistrou — **o mesmo
   crash, de outro jeito**.
3. **A ordem em `clearCallbacks` não é simétrica.** Os ponteiros nativos são
   zerados **antes** do `close()`. Ao contrário, existe uma janela em que a
   biblioteca segura o ponteiro de um trampoline que não existe mais.

O `jni-syntax.sh` deste repo **não cobre este arquivo** — ele compila o
`jni_wrapper.cpp` do llama.cpp. O comando que cobre o SD, e que achou o erro da
linha 596:

```sh
/opt/android-sdk/ndk/*/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android28-clang++ \
  -fsyntax-only -std=c++17 \
  -Ilocal_plugins/sd_flutter_android/android/src/main/cpp \
  -Ilocal_plugins/sd_flutter_android/android/src/main/cpp/stable-diffusion.cpp/include \
  local_plugins/sd_flutter_android/android/src/main/cpp/sd_jni_wrapper.cpp
```

**Verificado no A72 depois do conserto:** o mesmo modelo que matava o processo
agora carrega e o processo fica de pé.

### A previsão de memória erra para baixo em tudo que é quantizado — e por quê

Medido no A72, `DreamShaper8_LCM` (1,99 GB, sha256 conferido nos dois lados),
mesmo aparelho, mesmo build, mudando só a quantização. RSS lido de
`/proc/<pid>/status`, com o app sem modelo em 455–472 MB de base:

| quantização | RSS real (delta) | previsto (só pesos) | erro |
|---|---|---|---|
| FP16 | **1809 MB** | 1987 MB | −178 MB (−9%) |
| Q4_K | **1377 MB** | 792 MB | **+585 MB (+74%)** |
| Q2_K | **1300 MB** | 574 MB | **+726 MB (+126%)** |

**O FP16 quase acerta.** A previsão erra 9% para cima num caso em que não há
conversão nenhuma, o que faz sentido: ela mede pesos e o processo tem mais coisas
que pesos.

**O Q4_K erra 74%, e o Q2_K erra 126% — o erro cresce na direção oposta ao que a
previsão assume.** Os três números juntos contam a história sem ambiguidade:

```
FP16 -> Q4_K   economiza  432 MB de verdade   (previsto dizia 1195 MB)
Q4_K -> Q2_K   economiza   77 MB de verdade   (previsto dizia  218 MB)
```

**A primeira quantização paga quase todo o ganho, e cada seguinte compra cada vez
menos.** Essa é a assinatura de um **piso que não vem dos pesos** — algo que
independe do formato. O candidato óbvio é o que a previsão nunca incluiu:
**ativações, o buffer de decode do VAE e o backend de cálculo**, que existem
de qualquer jeito. Com o FP16 os pesos dominam e a previsão quase acerta; conforme
os pesos encolhem, o piso fixo engole a diferença.

**A consequência para a tela, e ela é de produto:** a previsão de `sd_weight_estimate.dart`
é **correta sobre os pesos** e **não serve como número de "isto cabe no seu
aparelho"**. Ela acerta a ordem e acerta o FP16, e erra de 74% a 126% no que a
pessoa realmente pergunta, que é se cabe. **Oferecer a lista com esses números
seria dizer uma coisa verificavelmente falsa.**

Duas saídas, e a escolha é sua:

1. **Mostrar o peso previsto e uma linha de "isto não é o total".** Honesto, e
   mantém o dado derivado do código nativo — mas não responde "cabe?".
2. **Trocar a régua: mostrar o RSS medido de uma tabela de referência**, com
   DreamShaper8_LCM como ponto de ancoragem e uma regra para extrapolar. É o que
   responde a pergunta, e é o que a seção "a hipótese da quantização" da fila já
   pede para o caso GGUF.

O que **não** é aceitável é o que eu estava prestes a construir: a lista de
opções com "0,77 GB previsto" e a pessoa decidindo se o telefone aguenta.

**E o filtro de exibição é o que escondeu isso.** Os 5 modelos de imagem são
SD 1.5 FP16 de 1,99 GB, `maxModelBytes` no A72 é **1,19 GB**
(`totalRamGB * 0.25`), então os 5 cards são **filtrados** de `displayedModels` e
não há como nem carregá-los pela tela. `GET /v1/models/local` **lista os 5**,
porque a API não aplica o filtro — e foi por isso que a carga foi possível
disparar e o crash aparecer. **O filtro é de exibição, não de carga**, e as duas
coisas precisam ser lidas como o que são: um card ausente na tela não é um modelo
que não carrega.

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
## Tradução — dois idiomas, e o padrão é inglês

⚠️ **O título desta seção dizia "(PT-BR)" e o "device locale" era `pt_BR`.**
Os dois mudaram: o app agora fala **inglês por padrão** e o idioma é uma
**preferência salva** com três opções. Ver "O idioma é escolhido, e o padrão é
inglês" mais acima, que tem as quatro decisões que não são óbvias.

- **Cobertura auditada, não estimada:** **905 chaves**, **as mesmas nos dois
  idiomas**, e `test/l10n_keys_test.dart` (10 testes) falha se uma faltar em
  **qualquer** dos dois. Antes desta auditoria o mapa tinha 277 e **38 das chaves
  usadas não estavam nele** — `tool_round_trips` à vista num item de Configurações,
  `mobile_lm` no Sobre. O GetX devolve a própria chave para uma que não tem, então
  nada lançou: cada uma renderizou como identificador inglês numa UI portuguesa.
  **Cada teste desse arquivo tem um irmão que prova que ele ainda vê alguma
  coisa**, porque um regex que parou de casar reportaria zero faltando e passaria.
  O `.arb` **não** é fonte para nada: `app_pt_BR.arb` e `app_en.arb` têm 113 chaves
  cada e são um **subconjunto** do mapa, não uma terceira fonte de verdade.
- **`readMap(lang)` recorta o mapa pelo nome dele.** Ler o arquivo inteiro
  devolvia o `pt_BR` para as chaves que existem nos dois — porque a segunda
  entrada sobrescreve a primeira no `Map` — e o mapa inglês nunca era auditado.
  Passou por sorte: `pt_BR` está por último. Se alguém reordenar, o teste continua
  verde e para de olhar o idioma padrão do app.
- **Detectar idioma é a lista do português, não a do inglês.** Uma lista do que
  **não pode** aparecer só funciona se o resto for o universo, e o resto é outro
  idioma: a versão com lista de inglês acusava texto português correto.
- **Os dois mapas são lidos valor a valor, nos dois sentidos.** Duas chaves do
  seletor estavam com o valor em português **no mapa inglês**, e a auditoria de
  "as chaves são iguais" não pega — a chave está nos dois. Só ler o valor pega.
- **Arquivos:** `lib/l10n/app_translation.dart` (GetX, os dois mapas),
  `lib/l10n/app_en.arb`, `lib/l10n/app_pt_BR.arb` (desligados),
  `lib/services/language_preference.dart` (puro, a decisão)
- **Regra:** strings UI nunca em `const` — `.tr` é método runtime. E um
  `static const` de **texto já traduzido** congela a língua do boot, que não é a
  que a pessoa escolheu: é o que os chips de resposta fazem errado se alguém
  "otimizar" a lista.
- **Device locale do A72:** `pt_BR`, e o app abre em **inglês** por padrão — que é
  o ponto: o idioma não é mais deduzido do aparelho.


- **Round-trip ceiling:** cloud = 20 hops fixo; local = `agentMaxHops` (setting).
  O setting **não** alcança cloud, e é de propósito: os 20 são sobre créditos.
  A escada do tile é `[0, 1, 2, 3, 4, 6, 8]` — **um toque chega em 0**, que é o
  caminho mais fácil para o defeito abaixo. Entrada manual pelo valor abre o
  diálogo (valida 0–8).

- **`0` é "sem teto seu", e NÃO é `while (hop < 0)`.** Três lugares descreviam
  `agentMaxHops == 0` e **nenhum era o laço**: o docstring dizia *"0 = infinite
  (no ceiling)"*, o tile dizia `∞` / *"Unlimited agent mode"*, o diálogo dizia
  *"Infinite agent mode (no ceiling)"* — e o laço fazia **zero iterações**. Quem
  escolhia "ilimitado" recebia um agente que não podia chamar uma ferramenta, e a
  tela dizia o contrário. O conserto é no laço, como este guia já pedia, e a
  decisão mora em `lib/services/agent_hops.dart` (puro, 8 testes): `0` mapeia
  para `AppConstants.agentHopBackstop` (50), que existe porque um teto ainda é
  um teto e um spinner que nunca termina é pior.

  **A mensagem de saída tem duas redações** e essa é a parte que valia: com 0, a
  frase antiga `'Tool limit reached ($maxHops hop(s)).'` diria *limite atingido
  (0 hops)*. Quem não pôs teto é dito que **o app** parou em 50; quem digitou um
  número ouve o número dele de volta. Do mesmo defeito: o subtítulo do tile
  dizia *"up to 1 hops"* com o default 1 — medido no A72, agora *"up to 1 hop"*.

  Medido no A72 pelo `uiautomator dump`: tile em 0 mostra `∞` e o diálogo diz
  *"No cap of your own — the app stops at 50 if the model keeps asking for
  tools"*. **O laço rodando com 0 não foi exercitado** — precisaria de modelo
  carregado com tools ligadas, e o A72 não aceita digitação.
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

**⚠️ A frase de onde vem o nome estava errada, e a fonte é do dono — TypeSafe AI.**

Eu escrevi *"o nome vem dos quatro que deram nome a ele — Jev, Laya, Tev1,
Bespoke-Nimble"* e tratei "Jev" como um quarto modelo qualquer. **Jev é o modelo
System One da TypeSafe AI** (<https://docs.typesafe.ai/introduction>), e é o
**primeiro** System One do mundo: *"Jev is TypeSafe's flagship model and the first
System One model."*

E **"System One" é o nome de uma classe da TypeSafe, não um rótulo deste app.**
O nome vem de **Kahneman** — System 1 é o pensamento rápido e intuitivo, System 2
o lento e deliberado —, via <https://docs.typesafe.ai/concepts/system-one>. Os
primitivos da TypeSafe são **Choice, Score e Noul**, e o endpoint deles é
**`POST /v1/systemone`**.

**O que isso muda no app, e é grande:**

| o que a classe da TypeSafe tem | o que este app tem |
|---|---|
| `POST /v1/systemone` | **nada** — zero ocorrências em `lib/` |
| Choice / Score / Noul | só `choices` (letra→rótulo) |
| `confidence` por pergunta | `relevance_score: null`, com o motivo |
| `probabilities` por opção | `scores` mapeado para null |
| **várias perguntas numa passagem** | **uma** pergunta por request |

**A janela deste app é uma interface para o `/v1/classify` com três shapes**, e o
`/v1/classify` é um endpoint **OpenAI de rótulos** — a família é a mesma, o
contrato não é. `DecisionMatch` e a estabilidade por permutação continuam válidos
para o shape `decision` (uma letra gerada), e `relevance_score: null` continua
sendo a resposta certa para um LM que emite uma letra. O que **não** existe aqui
é o que a TypeSafe chama de System One: os três tipos de pergunta, o `confidence`,
a leitura por distribuição e o batch de perguntas.

**Não é o caso de trocar o nome:** o app conversa com `/v1/classify` e o
formulário de três shapes é o que ele sabe descrever. O que é caso é **saber de
onde o nome vem** — porque "System One" nomeando uma coisa da TypeSafe e não
deste app muda o que se pode prometer sobre a 0.7.0, e um guia que inventa a
etimologia de um termo de terceiro é pior do que um guia calado.
**Nada no código olha para nome nenhum** — nem `Tev1`, nem `Jev`, nem `Laya`; a forma é decidida pelo que o
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

**`feature_source` é o que o modelo recebeu, e uma cabeça não embute nada.** O
campo existia no `SystemOneResult` desde o dia da janela, **nenhum endpoint o
mandava** e nenhuma tela o mostrava — e a lacuna que ele cobria é a pergunta de
quem recebe "bug" de um classificador de 0,8 B para um ticket cujo vetor de
features eram 1024 números digitados. Os dois caminhos mandam, por **duas
funções** (`describeVectorSource` e `describeTextSource`) e não uma com
argumentos nulos, porque são fatos diferentes: nomear um tensor no caminho do
decision model seria inventar um. E `fromClassify` lia o campo **só no ramo das
logits** — o decision model recebia do servidor e jogava fora, que é exatamente
o caminho de quem pergunta "por que ele disse isso".

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

**Os dois consoles LiteRT compartilham o TRANSPORTE e o VOCABULÁRIO VISUAL — e a
segunda parte só passou a ser verdade depois de um conserto que este guia
registrou errado uma vez.** `lib/views/api_console_shell.dart` tem o
`ApiConsoleClient` (auth por requisição, `request(method, path)`, `ping`), e
também `ConsolePalette`, `consoleCard`, `consoleField`, `consoleMono`, as três
mensagens e `consoleActions`. O primeiro commit da casca dizia que **todos os dois**
eram compartilhados, e contava **0 ocorrências** de cada símbolo visual nos dois
consoles: existiam, eram testados, e ninguém os usava. Agora são **11 usos** no
console `.tflite` e **8** na janela System One.

**Duas regras que a adoção deixou, e a segunda é a mais importante.** `consoleCard`
e `consoleMono` ganharam `radius` porque as duas telas discordavam — 12 contra 14,
e 10 contra 11 — e a casca passou a ser a **união** das variantes em vez de obrigar
uma tela verificada a mudar de aparência. E `ConsolePalette.explicit` tem **dois**
argumentos: o brilho é deduzido da luminância do próprio card, porque a forma de
três convida a passar um `isDark` que **contradiz a cor** — e nenhum dos dois
consoles precisa dele, já que `consoleCard` só lê a cor.

**O `_field` do console `.tflite` continua local, de propósito, e o motivo está no
arquivo.** Ele usa `TextField` `filled`/`isDense` com borda; a casca usa
`Container` sem borda; e ele tem um `onFirstBuild` porque um controller não se
preenche por `initial` depois de construído. Unificar os dois campos é uma
**decisão visual** numa tela verificada no aparelho, não uma de-duplicação.

**Um parâmetro novo e não coberto é um parâmetro cujos outros valores não são
testados — e foi assim que o `radius` do `consoleMono` passou um assert direto no
aparelho.** Com `radius: 0` o código tomava o ramo `decoration: null`, então o
conflito de `color:` com `decoration:` só existia no ramo novo; o teste da casca
passava e o console `.tflite` travava no primeiro paint. O teste monta os **dois**
raios agora, e `Container` **asserta** que não pode receber cor e decoração ao
mesmo tempo — o que ele faz acontecer dentro do seu próprio construtor, ou seja
antes do layout, e é por isso que o `flutter test` do arquivo não pegava.

Este console **inspeciona** uma cabeça, a janela System One **dirige** um modelo,
e o que elas têm em comum é como falam com o servidor e como desenham a resposta.
Dois `throwOnError` **deliberadamente diferentes**: aqui `true` (todo call site é
`on Object catch`), lá `false` (um 422 do `/v1/classify` traz o texto do modelo e
o texto *é* a resposta).

**O encoder console não participa, e a razão está escrita no arquivo.** Ele é um
monitor do modelo carregado, sobre o chat, com outro ciclo de vida; trocar o
mecanismo dele é mexer numa tela que funciona e cujo teste de layout já se provou
falhando. É decisão dele, não padrão.

**Duas regras da casca que os testes fixam e que vieram de bugs:**
`apiPlan` não escreve corpo num `GET` (um GET com corpo é um pedido que o servidor
pode ignorar, e escrevê-lo esconde o erro de quem chama), e `apiReply` trata um
corpo **não-JSON** como corpo — o `Bad Gateway` de um proxy virava
`FormatException: Unexpected character (at character 1)` em vez do texto.

**E uma coisa que este repo não consegue testar:** `flutter_test` substitui o
`HttpClient` por um stub que responde 400 a tudo, então **um `HttpServer` de
verdade é inalcançável** do lado do cliente e o teste só provaria que o stub
respondeu. Por isso as decisões (`apiPlan`, `apiReply`) são puras e testáveis, e
o socket ficou só com o que só socket faz. Um teste verde que não pode falhar
pelo motivo real é pior do que nenhum.

Medido no A72: a tela de decisão acerta **3 de 3** com Tev1-0.8B usando o corpo
que ela própria monta, `relevance_score: null` e `scores` todo nulo; a tela da
cabeça renderiza e lê 1024/4/2 do `GET /v1/litert/status` real; `compile_ms` 5–7.
**O `Run` não foi apertado na tela** — a tela do A72 não aceita texto sintético e
o vetor são 1024 números. O contrato de ponta está verificado por `curl` com o
JSON extraído do próprio código; a lacuna é do aparelho, e está escrita assim.

**A regra 1 foi confirmada por medição depois**, com um terceiro modelo que não é
Tev1 nem Bespoke-Nimble e não tinha nada de decision model no nome: ver a seção
seguinte.

## A família `d1` da Liquid AI entra pela porta que já existe

Medido em 08/10/2026 no A72, com o `d1-3B-Q4_K_M` importado à mão. Detalhe
completo em [`docs/SYSTEM_ONE.md`](SYSTEM_ONE.md); aqui só o que o guia precisa
saber para não refazer o trabalho.

**Não existe "d3-3B"** — a família se chama `d1`, e são `d1-3B` (3,1 B, texto +
imagem) e `d1-omni-600M` (587 M, texto + imagem **ou** áudio). Ambos open-weight,
lançados em 07/10/2026, ambos com GGUF oficial.

**Não existe `LLAMA_ARCH_D1` também.** O `d1-3B` tem `text_config:
Lfm2ForCausalLM`, `tie_word_embeddings: true`, e nos 266 tensores **não há cabeça
de saída nem decision head** — só `token_embd.weight` e os 30 blocos LFM2 (8 com
atenção, 22 convolução). `lfm2-d1` é um LFM2 comum lido no último token com os
logits restritos às letras. **O app já suporta `lfm2`.**

**E o shape sai certo sozinho, sem uma linha de código.** `systemOneShapeOf`
decide por `hasClassificationHead`, e o `d1-3B` não tem `cls.output.weight` —
caiu em `decision` como um `Tev1` qualquer. `POST /v1/classify` devolveu
`{"choice":"B","label":"Financeiro"}` numa pergunta de renegociação de fatura, que
é a resposta certa.

**Não é config, e isso foi separado por experimento.** O template `systemone` do
GGUF é **flat** (`user\n…assistant\n`, **sem papel de system**); o app monta
`systemPrompt` com a instrução do Tev1 + `/no_think` e um `userPrompt` em JSON.
Prompturas diferentes, **respostas idênticas** — o desktop com o prompt do app deu
`'B'`, `'A'`, `'B'` exatamente onde o caminho canônico deu `b`, `a`, `b`. E o A72
deu as **5 de 5** que o canônico deu no desktop, **inclusive as erradas**. Logo o
erro é do modelo, reproduzido em máquina e código diferentes — não é template,
não é integração, e não há config que conserte.

**E não é viés de posição — que é o que a permutation stability pega.** 24
permutações das 4 opções, dois casos:

| caso | estabilidade | confiança canônica |
|---|---|---|
| fatura / renegociação | **24/24 → Financeiro** | 0,80–0,94 |
| dúvida sobre fatura | **13/24 → Suporte, 11/24 → Financeiro** | 0,32–0,63 |

A resposta que o modelo dá com convicção é permutation-stable. A que ele erra
**não tem opinião nenhuma**, e o número normalizado não distingue as duas: o
`d1-omni` devolve `confidence: 0.0` com `0,34/0,25/0,28/0,14`, que softmaxado
vira "34% baixa, 25% média" e parece preferência. É a regra 1 desta janela
confirmada por medição, não por argumento.

**⚠️ O `d1-omni-600M` NÃO carrega, e a causa é o llama.cpp vendorizado — não o
detector de forma.** Tudo o que esta seção dizia antes sobre o colliding com
`ggufHead` está errado; o conserto está medido e é o fim desta seção.

O que o arquivo realmente é, contado nos tensores:

```
18 blocos (0..17)
  blocos 0..15   ffn_gate + ffn_down + ffn_up, n_ff = 4608
  blocos 16,17   ffn_down + ffn_up + BIASES,  SEM ffn_gate, n_ff = 4096
```

**Os dois últimos blocos têm um FFN sem gate.** E `lfm2.feed_forward_length` **é
um array de 18 valores**, `[4608 ×16, 4096, 4096]`, enquanto nosso vendor lê
`hparams.n_ff` como escalar e assume 4608 para todas as camadas.

Dois erros, **um atrás do outro** — e o segundo só aparece depois que o primeiro é
resolvido:

```
1) check_tensor_dims: tensor 'blk.16.ffn_gate.weight' not found
2) check_tensor_dims: tensor 'blk.16.ffn_down.weight' has wrong shape;
                       expected 4608, 1024, got 4096, 1024, 1, 1
```

**O patch de "gate opcional" sozinho é necessário e insuficiente**, e é por isso
que ele foi revertido em vez de ficar no vendor: ele muda a mensagem de erro e não
faz o modelo carregar, e o repositório tem a invariante escrita — *"nenhum arquivo
vendorizado foi alterado"*. Consertar são **três** coisas, e as três são vendor:

1. `ffn_gate` como `TENSOR_NOT_REQUIRED` (`src/models/lfm2.cpp`);
2. `n_ff` **por camada**, lido do array — isso é `llama-hparams`, não `lfm2.cpp`;
3. `build_ffn` com `gate == NULL` para um FFN não-gated, e o guarda no grafo que
   só soma o residual quando houve FFN.

O ponto 3 é o que separa um conserto de um crash adiado: sem ele o modelo **carrega**
e quebra na primeira inferência, porque `build_ffn` desreferencia os três tensores.

**Três afirmações minhas que estavam erradas, e as três eram sobre este modelo:**

| eu escrevi | o que é |
|---|---|
| "o `d1-omni` colide com o detector: `cls.output.weight [1024]` manda para `ggufHead`" | **`isClassifier => isEncoder && pooling == 'rank' && nClsOut > 1`**, e o arquivo não declara `pooling_type` → `isEncoder` falso → `isClassifier` falso → o dispatch já vai para o **caminho generativo**. Nenhum conserto de detector seria preciso. |
| "o re-sync do vendor não compra suporte de decisão" | **não** — ele compra este modelo. Eu escrevi isso depois de só ter medido o `d1-3B`, que é LFM2 puro e carrega. |
| "a cabeça é `(1024,)` com bias `(1,)`, uma cabeça de uma classe" | a cabeça existe, mas é irrelevante: quem impede o modelo é o FFN sem gate, e ela nunca chega a ser lida |

O padrão é o da **`is_recr`** do LFM2: um LFM2 **pode** intercalar blocos de
convolução, e o vendor assume que todo bloco tem a mesma estrutura de FFN. Um
modelo que usa essa liberdade legal é barrado por um pressuposto, não por um erro.

Para vision só o `d1-3B` serve, e precisa do `mmproj-d1-3B-Q8_0.gguf`.

**Nosso vendor está atrás do merge, e o patch não aplica.** O merge no upstream foi
em 07/10 e 08/10; o vendor está em `08b1d2aea`. Verificado numa cópia:

```
erro: falha no patch: conversion/lfm2.py:127
erro: falha no patch: gguf-py/gguf/constants.py:6071
erro: tools/server/server-decision.cpp: Arquivo ou diretório inexistente
```

`tools/server/` **não existe no nosso vendor** — só sobrou `tools/mtmd` — e é lá
que mora toda a API de decisão. `include/llama.h` não ganhou API pública nova.

**⚠️ "o re-sync não compra decisão" estava errado, e eu escrevi isso depois de só
medir o `d1-3B`.** Ele compra o **`d1-omni-600M`**, que morre em
`llama_model_load` por um pressuposto do vendor sobre blocos LFM2 — e essa seção
do `d1-omni` tem os números. O que o re-sync **não** traz de útil aqui é
`tools/server/` (o app não o usa), `gguf-py` (Python, não é runtime) e a decisão
nativa (que o shape `decision` não precisa).
**Nada disso é necessário para o `d1-3B`**, porque o shape `decision` não usa
suporte nativo: ele prompta, gera, e casa a letra por regex. Por isso a
`libllama.so` instalada tem **zero** strings de `decision`/`systemone`/`lfm2-d1`
— confirmado no APK extraído, não na fonte. Se um dia entrar o suporte nativo,
esse é o caminho, e ele exige re-sync, não cherry-pick.

**⚠️ A afirmação de que o `tev1` "devolveu prosa" foi palpite meu, e estava errada.**
O log mostrava 6 tokens a 8,0 s cada e eu li isso como prosa. Não é: este arquivo
já documenta que o `tev1` responde `<think>\n\n</think>\n\nB`, que **são** ~6
tokens, e o `parseDecisionAnswer` devolve a letra pela regra do bloco. **Não
consegui decodificar os ids** — o `gguf-py` do PyPI não instala sem `pip`, e o
leitor escrito à mão erra o offset do array de strings — então a frase ficou sem
prova e foi documentada como se tivesse. O sintoma real era **latência**: 8,0 s
por token com o núcleo no piso, e um `d1-3B` de 3 B leva 6,6–23,8 s pela mesma
CPU.

**E o trabalho seguinte achou o bug que era silencioso e pior.** Escrever o enum
`DecisionMatch` obrigou a exercitar as três regras do `parseDecisionAnswer`, e a
**regra 3 casava a primeira letra de qualquer palavra** — tudo depois da letra é
opcional no regex. Um modelo que responde `account` casava `a`, que é a opção A, e
voltava **`A = bug`** com confiança total. A regra 4, que casava o rótulo inteiro,
era a rede exatamente para isso e era **código morto**. Medido antes do conserto:
`bug` → `B/billing`, `account` → `A/bug`. Ambos errados, nenhum nulo. O conserto é
um lookahead `(?=\s|[.):\-]|$)`.

É a mesma classe que este arquivo descreve em cima — **um detector que não acha
nada reporta o mesmo que um detector que não existe** — e apareceu em código com
**28 testes**, nenhum cobrindo um modelo que responde com o rótulo em vez da letra.

## O diretório de modelos no host — `<Vendor>/<Família>/`

`/home/dollar/models/` guarda os GGUF e `.safetensors` baixados, organizados por
publisher do HuggingFace e família, que é o mesmo critério com que o `/v1/classify`
decide a forma de um arquivo. 19 arquivos, 13 GB.

```
ConvaiInnovations/Laya/   Google/gemma/        HuggingFaceTB/SmolLM2/
IBM/Granite/              LiquidAI/d1/         LiquidAI/LFM2.5/
Lykon/DreamShaper-8/      OpenBMB/MiniCPM5/    TogetherAI/Tev1/
Qwen/Qwen2.5-Coder/       Qwen/Qwen3/          Qwen/Qwen3.5/
madebyollin/TAESD/
```

O `d1` tem **quatro** arquivos porque um decision model de imagem não funciona
sem o seu: `d1-3B-Q4_K_M` + `mmproj-d1-3B-Q8_0`, e `d1-omni-600M-Q8_0` +
`mmproj-d1-omni-600M-Q8_0`. Separar o par é como quebrar um modelo.

**O app descobre sozinho um `.gguf` avulso, e a prova é uma sonda, não uma
contagem.** `refreshDownloaded` varre o diretório, aceita `.gguf`, `.litertlm`,
`.tflite` e `.safetensors`, e adiciona com `descriptionEn: 'Imported from local
storage'` qualquer nome que não esteja em `availableModels`. Verificado com uma
sonda: copiar um modelo existente com **nome novo** direto no diretório e
reiniciar levou `BAIXADOS 9 → 10` e `MODELOS LOCAIS 65 → 66`. Então
`adb push` + `run-as cp` para `app_flutter/models/` **funciona**, e o picker de
import é o caminho quando não se tem adb — não o único caminho.

**E é fácil contar errado, porque um arquivo é filtrado.**
`_isAuxiliaryImageFile` tira o `taesd.safetensors` da contagem: 10 arquivos no
diretório são **9** em `BAIXADOS`. Quem conta olhando `ls` chega à conclusão
oposta da lista — foi o que aconteceu com o `d1-3B`, que estava nos 9 desde o
push e só foi percebido depois do import. E `refreshDownloaded` chama
`_deletePartialImports()` **primeiro**, então um arquivo que ele considere import
incompleto pode ser apagado antes de ser listado.

**O import pelo SAF copia e não move**, e por isso pergunta *"Model already
imported — Replace it?"* quando o nome já existe. Ele também **não alcança** o
diretório privado nem `/data/local/tmp` — para importar pela tela o arquivo
precisa estar em `/sdcard/Download/` — e **não apaga a origem**: depois de
importar um GGUF grande sobra uma cópia em `/sdcard/Download/`, que só sai com
`adb shell rm`.

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

**Os quatro acima são `patch`, todos, e a lista não dizia isso.** O critério do
repo é "isto faz X, que antes não existia", e nenhum deles cria: (1) corrige
advice comprovadamente errado, (2) e (3) ampliam medição e catálogo — e catálogo
maior não é feature por regra própria deste arquivo, (4) são overflows e um
gesto. **Uma fila ordenada por esforço que não diz o que cada item é às sombras
do minor induz quem a lê a preparar um minor que não tem minor dentro.**

**O que passa no critério, e em ordem de quanto dói deixar de fora:**

1. **A régua de memória por RSS medido.** `sd_weight_estimate.dart` acerta a
   ordem e acerta o FP16, e erra de **74% a 126%** no que a pessoa pergunta, que
   é se cabe — e os 5 cards de imagem somem no A72 porque `maxModelBytes` é
   1,19 GB contra 1,99 GB de pesos. *"Isto faz X, que antes não existia"* → **o
   app responde se o modelo cabe, com número medido, em vez de prever só os
   pesos.** Não é correção de número: a pergunta não tem resposta certa hoje.
   **Bloqueia numa decisão antes de bloqueia em esforço** — as duas saídas estão
   na seção "A previsão de memória erra para baixo", e a segunda é a que
   responde. ⚠️ `lib/services/sd_weight_estimate.dart` e
   `test/sd_weight_estimate_test.dart` estão **untracked de propósito**: não
   entrem num `git add lib/ test/` por accidento, já aconteceu duas vezes.
2. **O host da Laya.** O interpretador e o console existem e estão medidos; o que
   falta é o encoder ModernBERT de 705 MB que produz as features, e ele é
   *orquestração*, não aparelho. *"Isto faz X, que antes não existia"* → **o app
   classifica texto de ponta a ponta**, e não por um `.tflite` empurrado à mão.
3. **`POST /v1/litert/unload`.** As rotas são `screen`, `load`, `status`, `run`:
   uma cabeça só é trocada carregando outra, e o estado "nada carregado" da
   janela System One fica inalcançável depois da primeira carga. *"Isto faz X, que
   antes não existia"* → **uma rota que dá para desfazer a carga.**

**O item 5 desta lista era "A 0.6.0", e ele existia porque nenhuma das três
candidatas acima estava escrita como minor em lugar nenhum.** Uma fila de
trabalho que termina em "e então subir a versão" deixa a pergunta "o que é uma
feature?" sem resposta até o dia de subir — e a resposta fica sendo o que já
foi entregue, que é como este arquivo já esteve errado duas vezes.

## Estabilidade por permutação, e o `DecisionMatch` — 0.7.0

A seção acima mediu instability por permutação **manualmente**, com `curl` no
llama.cpp de mesa. Isso virou código: `lib/services/decision_stability.dart` (puro,
16 testes) e `tool/decision_compare.py` (roda no aparelho e compara com o desktop).

**Estabilidade substitui porcentagem, e a razão é o `relevance_score: null` da
regra 1.** Um decision model emite **uma** distribuição sobre o vocabulário
inteiro, e o único que se lê é o logit dos tokens de letra — que não são
calibrados. Softmax sempre soma 1, **inclusive quando o modelo não tem ideia**:
o `d1-omni` deu `confidence: 0.0` sobre `0,34/0,25/0,28/0,14`, que normalizado
vira "34% baixa" e parece preferência.

**⚠️ Eu escrevi que "a família `d1` embarca a calibração que falta", e está
errado — ela está num modelo só, e não no que roda.** Medido nos dois arquivos em
08/10/2026, pelas 43 e 48 chaves de metadados de cada um:

| arquivo | chaves `lfm2.decision.temperature.*` |
|---|---|
| `d1-3B-Q4_K_M.gguf` — **o que roda no A72** | **0** |
| `d1-omni-600M-Q8_0.gguf` — o que está **fora** | **10** |

O `d1-3B` carrega **só** `lfm2.decision.type = "lfm2-d1"`, e nenhuma chave com
`temperature` em nenhum lugar das 43. A calibração do autor existe, e é por tipo de
pergunta (`choice`, `noul`, `score`) e por **faixa de quantidade de opções** —
`.2`, `.3_5`, `.6_10`, `.11`, com valores de 1,0 a 1,75:

```
choice.2 = 1,7465   choice.3_5 = 1,3999   choice.6_10 = 1,1751   choice.11 = 1,3725
noul.2   = 1,6663   score.3_5 = 1,7301
```

Isto importa mais do que a frase errada: **o modelo que a calibração foi escrita
para é exatamente o que o app não consegue rodar**, e o que roda não a tem. Então
o argumento "usamos estabilidade porque a calibração do autor existe e nós a
ignoramos" é verdadeiro para o `d1-omni` e **falso para o `d1-3B`**. O argumento
que sobra, e que continua de pé sozinho, é o do softmax: soma 1 inclusive na
incerteza total. As duas coisas são measurements independentes e só uma delas
alcança o modelo em uso.

**Permutação é mensurável sem inventar número.** A mesma pergunta com as opções
embaralhadas: se a resposta segue o **conteúdo**, é estável; se segue a
**posição**, é artefato do prompt. O llama.cpp faz o mesmo upstream — `n_variants`
retorna 2 pra choice do LEV, *"to cancel the preference for the first label"*.

**`decisionPermutations` é round-robin por primeira letra, Lehmer dentro do
grupo — e duas ordens anteriores falharam, ambas medidas.**

| ordem | alcança das 6 que invertem |
|---|---|
| rotação (`ABCD`, `BCDA`, `CDAB`, `DABC`) | **0** |
| prefixo de Lehmer (`ABCD`, `ABDC`, `ACBD`, …) | **0** |
| stride sobre os ranks de Lehmer | **0** |
| **round-robin por 1ª letra + Lehmer na cauda** | **3** (`bacd`, `bcad`, `bdca`) |

Rotação cobre **4 das 24** permutações, todas na mesma família cíclica, e nenhuma
das 6 que invertem está nelas. O harness mediu isso no A72: **3/3 "ESTÁVEL"** no
caso que o desktop mostrou instável. Não é azar, é estrutura — e o default de 3
viraria uma tela que não vê o defeito que existe para pegar.

**O default é 12, e o custo é dito no código:** um `d1-3B` no A72 leva
**6,6–23,8 s** por decisão, então 12 variantes de uma pergunta são **1,5–4,5 min**.
Por isso é teste que a pessoa escolhe rodar, nunca default interativo.

**`DecisionMatch` diz COMO a letra foi achada, e as três eram indistinguíveis.**
`B`, `B.` e `billing` devolviam o mesmo `letter`/`label` — `letter` para os dois
primeiros caminhos e `label` para o terceiro, o que é o caso de um modelo que
**ignorou a instrução** e escreveu o rótulo. O endpoint agora manda `match` e
`followed_contract`; `decoratedLetter` conta como **não** limpo, porque tratar
polidez como obediência é como um limiar de drift nunca dispara.

**E o `DecisionMatch` expôs o bug do parser, que era o pior da sessão.** A regra 3
casava a primeira letra de **qualquer palavra** — tudo depois da letra é opcional
no regex — então `account` voltava `A = bug`. A regra 4, que casava o rótulo
inteiro, era a rede para isso e era código morto. 28 testes, nenhum cobrindo um
modelo que responde com rótulo. Conserto em `(?=\s|[.):\-]|$)`.

**⚠️ O `variants` é opt-in no endpoint e o default é 1 — e o guia anterior não
dizia.** `/v1/classify` continua respondendo **uma pergunta com uma decisão**, e
quem não pede reproduzibilidade não paga N× a latência por um número que não vai
ler. Fora do intervalo **clampa** em vez de recusar: `variants: 400` devolve o
teto, `variants: 0` ou uma string devolvem 1. Recusar seria deixar o endpoint mais
estrito do que precisa por causa de um botão de desempenho que tem resposta segura
dos dois lados. A **primeira** execução é a resposta; as outras são diagnóstico
sobre ela, e **nunca** viram uma "consolidação" — média sobre variantes sem
opinião reporta o palpite mais popular como se fosse a conclusão.

**A janela ganhou o controle (chips `1` / `4` / `12`) e mostra os três blocos
novos, e o bloco de estabilidade está no caminho da RECUSA — que é onde ele é mais
necessário.** Um 422 diz "não respondeu"; o bloco diz *quantas vezes foi perguntada e
quantas vezes recusou*, que é a diferença entre "este modelo não sabe" e "sabe, e
uma ordem de opções o fez hesitar". Antes o endpoint mandava o bloco,
`fromClassify` o interpretava, e **o único ramo que mais precisava dele o jogava
fora**. E `soc_model_said` nomeia o texto cru do modelo **nesse** ramo — sem ele a
recusa mostrava o bloco e não mostrava o que o modelo escreveu.

**Uma tela que os testes de layout alcançam exige um argumento de construtor, e o
motivo não é conveniência.** `_result` só é escrito por `_show`, `_show` só vem de
uma resposta de servidor, e `flutter_test` substitui o `HttpClient` por um stub que
responde 400 — então os painéis de resultado são **inalcançáveis** de um teste.
`SystemOneConsole.initialResult` é o que fecha isso, pelo mesmo motivo que
`headContract` já era argumento. E `stableWithTwelve()` monta **doze** probes com
um rótulo de 35 caracteres: a lista de permutações desenha **uma linha monoespaçada
por execução** dentro de um `Column` dentro de um card a 360 dp — exatamente a forma
que já estourou quatro telas deste repo.

**O `_drain` que eu copiei para os testes novos é o defeito, e as quatro mutações
medidas mostram.** Trocar o `Wrap` dos chips por um `Row` deixou **11 de 11 verde**
com `_drain`: o helper descarta a própria coisa que o teste existe para achar. Verifiquei
que um overflow de `RenderFlex` **chega** a `takeException()` neste harness — um
`Row` de duas strings longas a 360 dp e 2× reporta `A RenderFlex overflowed by 9048
pixels on the right` — ou seja o sinal existe, e quem o engole é o helper. Os testes
novos **afirmam que não há exceção** em vez de drenar, e a tabela de mutações está
escrita no próprio arquivo. A quinta mutação — involve a linha da permutação em um
`Row` inquebrável — **ainda passa**, porque a linha está num `Column` com
`CrossAxisAlignment.start` e o texto quebra antes. Está escrito que essa não é
coberta: uma mutação que ninguém tentou é uma mutação que ninguém pode afirmar estar
coberta.

**E o número de chaves subiu 905 → 918, e subir foi o sintoma de um buraco.** As 13
novas são da janela System One, e nenhuma é texto já existente renomeado — são frases
que **não existiam**. Sem elas a tela de decisão diria "how the letter was found" com
o corpo vazio. Este número já esteve errado seis vezes aqui, e o conserto aqui não foi
subir o teto: foi conferir os dois mapas e **perceber que `soc_model_said` faltava**
porque o ramo da recusa era o único que não mostrava o texto do modelo.

**O harness está em `tool/decision_compare.py` e é a forma de medir isso sem
confiar em mim.** Ele monta o prompt do app **byte a byte** (mesma instrução, mesmo
envelope JSON), roda as permutações, e compara com um `llama-server` local quando
passado `--local`. O caso que não responde é contado como **instável**, não
descartado: descartar a recusa deixa um modelo que responde uma vez e recusa três
reportar estabilidade perfeita.

## O round-trip que não existia, e os **dois** bugs que ele achou

O item 1 da fila ("tirar `_stabilityPayload` e `_decisionVariants` do servidor para
um arquivo puro") era sobre **teste**. O que se descobre fazendo é que ele era
sobre duas coisas que estavam **erradas em produção**, e nenhuma delas produzia erro
nenhum — o que é a definição de silencioso.

**Por que estava errado: o formato do wire não tinha dono.** As duas funções eram
`private` da classe do servidor, e os testes carregavam **cópias escritas à mão** do
payload. Uma cópia não é contrato. Medido antes de mexer, e as duas mutações
passavam a suíte inteira:

| mutação | o que acontece em produção | antes |
|---|---|---|
| `distinct_answers` → `distinctCount` | nada: o cliente **recalcula** | **607/607** |
| remover o clamp de `variants` | `variants: 400` vira 400 gerações, ~2 h no A72 | **607/607** |

A primeira é **benigna e continua benigna** depois do conserto — e vale entender por
que, porque é o desenho certo: os campos de resumo do payload são **redundantes por
construção**, o cliente deriva o veredito dos `probes` com a mesma função pura que o
servidor usou. Renomear um deles não quebra nada porque **ninguém os lê**. É a regra
1 desta janela aplicada ao próprio payload de decisão. O que **não** é redundante é
`probes`, e é o que os testes fixam.

**O `order` é uma lista no wire e o leitor exigia um mapa.** O endpoint manda
`p.order.keys.toList()` — uma **lista**, porque é a ordem que é o dado, e a ordem das
chaves de um objeto JSON não é garantida. `SystemOneResult._stability` fazia
`p['order'] as Map`, que devolve `null` para uma lista, e cada probe voltava com a
ordem **vazia**.

**Como isso aparecia na tela:** o console imprime `order.keys.join(' ')`, então as
doze linhas de permutação saíam **em branco** — um relatório de permutação sem as
permutações. **Todos os números continuavam certos**, que é o que fez passar a
medição no aparelho: o teste contou `runs`, `failed` e `distinct`, e nenhum dos três
depende da ordem. É a mesma classe do `HeadContract` — objeto onde o aparelho manda
array — e na **direção oposta**: aqui o payload escrito à mão era o que o leitor
queria, então **os dois lados do teste concordavam e o aparelho discordava dos dois**.

**E o segundo bug é pior: o leitor descartava as recusas.** O guarda era
`if (p is Map && p['label'] is String)`, e uma recusa tem `label: null`. Ou seja:
**um modelo que responde uma vez e recusa onze reportava `1/1 estável`**, porque as
onze recusas não estavam lá para discordar. É literalmente o defeito que o cabeçalho
de `decision_stability.dart` diz impedir — *"descartar a recusa deixa um modelo que
responde uma vez e recusa três reportar estabilidade perfeita"* — e o próprio
arquivo o cometia.

**As quatro mutações que reprovam hoje** (`test/decision_stability_test.dart`, e a
tabela está no arquivo):

| mutação | resultado |
|---|---|
| remover o clamp de `parseVariants` | **reprova** |
| o leitor voltar a exigir `Map` | **reprova** |
| o filtro voltar a descartar recusas | **reprova** |
| `isStable => true` | **reprova** |
| rotação no lugar do round-robin | **reprova** |
| lookahead do parser removido | **reprova** |

E uma que **não** reprova, escrita no arquivo como não coberta: renomear
`distinct_answers`, porque o campo é redundante por desenho. **Isso é o conserto
funcionando, e não uma lacuna** — mas só depois de se explicar por quê, porque um
teste que não reprova é a mesma frase de "não testado" com outro nome.

**O assert que faltava, e a lição dele.** A primeira versão do round-trip afirmava
`runs`, `failed`, `distinct`, `leading`, `leadingRuns` e `isStable` — e **todas as
contagens sobrevivem a um leitor que joga a ordem fora**. Por isso remover de novo o
ramo `List` de `_probeOrder` deixou o arquivo **verde**. O que fecha é uma linha que
não existia:

```dart
expect(back.probes[1].order.keys.toList(), ['B', 'A']);
```

**Uma asserção sobre contagem não prova que a ordem sobreviveu**, e a ordem é o que
o painel inteiro mostra. É a mesma lição do ratchet de tradução, uma oitava vez: uma
lista do que a trava mede é uma afirmação, e ela só aparece quando a medição falha de
um jeito que ninguém esperava.

## Os quatro arquivos da Liquid AI, conferidos por HEAD antes de entrarem

A regra do catálogo é conferir a URL antes de entrar — *"descobrir que a arch não é
suportada depois de 774 MB é derrota"*. Os quatro respondem **200**, e o
`Content-Length` bate **byte a byte** com o que está em `/home/dollar/models/`:

```
200  LiquidAI/d1-3B-GGUF/d1-3B-Q4_K_M.gguf              1.674.456.672
200  LiquidAI/d1-3B-GGUF/mmproj-d1-3B-Q8_0.gguf           583.109.728
200  LiquidAI/d1-omni-600M-GGUF/d1-omni-600M-Q8_0.gguf   407.207.584
200  LiquidAI/d1-omni-600M-GGUF/mmproj-...-Q8_0.gguf     262.791.232
```

**E `Q4_K_M` é a menor quantização publicada do `d1-3B`**: BF16 5,03 GB, F16 5,03,
Q8_0 2,68. Não há uma menor para escapar do teto, e por isso o card do `d1-3B`
**não aparece no A72** — 1,56 GB contra `maxModelBytes` de **1,20 GB**.

**O A72 tem 4,78 GB, não 5,6.** `MemTotal: 5011844 kB` em `/proc/meminfo`, que é
exatamente o que o app lê (`device_info_native.dart:145`, `int.parse / 1024 / 1024`
— MB, não GB). 4,780 × 0,25 = **1,195 GB**. Eu escrevi 5,6 GB aqui e no teste, e
o teste **passava pela razão errada**: 1,56 GB é maior que 1,20 e também maior que
1,40, então a asserção era verdadeira nos dois casos e não podia distinguir um
número do outro. Um teste que passa por dois motivos não está medindo nenhum deles.

**30 das 47 entradas de catálogo são filtradas por esse teto no A72** — medido, não
contado à mão. Só 17 aparecem. O `d1-3B` está entre as 30.

**Os quatro nomes de repositório vieram de HEAD, não de memória.** A API do Hub
respondeu `Invalid username or password` e o `GGUF` **não carrega a URL do próprio
repositório** — só `general.name` (`d1-3B`), `general.basename` (`d1`),
`general.license.name` (`lfm1.0`) e `general.base_model.0.repo_url`, que é o
**modelo base**, não o repo do GGUF. `LiquidAI/d1-3B-GGUF` é o que responde 200;
`LiquidAI/LFM2-d1-3B-GGUF` dá 401, e existiu como candidato na minha cabeça porque
o nome do modelo **parece** LFM2. Um nome que parece certo e um repositório que
responde 401 são a mesma forma de erro.

## Importar por `run-as` só funciona a partir de `/data/local/tmp`

**`run-as` não consegue ler `/sdcard`, e o guia dizia o caminho sem o motivo.** O
`cp` a partir de `/sdcard/Download/` dá `Permission denied`, e um
`cat < /sdcard/... > models/...` via `sh -c` **não dá erro nenhum e deixa um
arquivo de 0 bytes** — que o app aceita como modelo e só falha depois, em
`llama_model_load: GGUF model file is empty or incomplete`.

O que funciona:

```sh
adb push <arquivo> /data/local/tmp/x.gguf
adb shell chmod 644 /data/local/tmp/x.gguf          # sem isto, o run-as não lê
adb shell "run-as <pkg> cp /data/local/tmp/x.gguf \
           /data/data/<pkg>/app_flutter/models/x.gguf"
```

**Um arquivo de 0 bytes é a falha que não dá aviso**, e ela só aparece 40 segundos
depois, no log nativo, com uma mensagem que fala de GGUF e não de cópia. O sintoma
— "o modelo aparece na lista e não carrega" — não aponta para o transporte, e o
modelo parece culpado.

## O `d1-3B` entra no catálogo como **role**, não como nome

A entrada existe (`lib/core/constants.dart`) e é a **primeira** do catálogo com
`'role': 'decision'`. O bloco novo é **Decision models**, e ele vem **primeiro**
na `order`, antes de Text.

**O papel é um campo, e não é um palpite a partir do filename.** Já aconteceu
neste repositório: `bge-small-en-v1.5` foi identificado como classificador porque
alguém leu o nome e adivinhou. `bge-small-en-v1.5` não diz nada sobre
`pooling_type`. A regra é a mesma dos encoders, que já têm `'role'`.

**São dois fatos e não são o mesmo:**

- o **catálogo** diz o que a entrada **declara** ser — um card é desenhado antes
  de qualquer coisa ser carregada;
- o **endpoint** diz o que o **arquivo** virou — `/v1/classify` decide em tempo de
  execução por `hasClassificationHead` e, atrás dele, `pooling_type`.

Um card que discordasse do endpoint estaria errado de um jeito que nenhum teste
veria. Por isso o campo é uma **declaração**, não uma detecção.

**`role: 'decision'` ganha precedência sobre a modalidade.** O `d1-3B` tem
`mmproj`, então por modalidade ele cairia em Multimodal — o que é verdadeiro e
inútil, porque "dá para mandar uma imagem" não é o que quem procura o modelo está
perguntando. O teste do role vem **primeiro** na cadeia ternária de `_byModality`
por isso.

**O rótulo do bloco é `mv_block_decision`, não o literal.** `'Decision models'`
entrou em `naoTexto` com o mesmo motivo de `'Text'`/`'Vision'`/`'Multimodal'`:
é chave de ordenação em `_byModality`, e traduzir a string tiraria a ordenação.
O que se pinta é o `labelKey`.

**O card não aparece no A72.** `Q4_K_M` é a **menor quantização publicada** —
BF16 5,03 GB, F16 5,03, Q8_0 2,68. São 1,56 GB contra um `maxModelBytes` de
1,40 GB. Não existe opção menor para contornar. É o filtro funcionando, e o mesmo
mecanismo que esconde os cinco modelos de imagem.

## A mutação M3: 633/633 verdes com o bloco sem tradução

**Um `switch` privado que mapeia rótulo para chave de tradução não é testado por
consequência — e a consequência é silenciosa.**

A mutação trocou

```dart
'Decision models' => 'mv_block_decision',   // -> 'Decision models',
```

e **todos os 633 testes passaram**. Três testes que já existiam não podiam ver:

- `language_preference_test.dart` exige que cada entrada de `naoTexto`
  **exista como literal no fonte**. `'Decision models'` continua existindo, em
  três outros lugares. *O literal estar presente não é o rótulo estar traduzido.*
- o teste de contagem lê 919 nos dois mapas. `mv_block_decision` **nunca saiu** de
  nenhum dos dois, então contar não enxerga que o código parou de usá-la.
- **nada afirmava o mapeamento em si.**

O efeito era um usuário em português vendo um cabeçalho em inglês, e uma
`labelKey` virando código morto. É a mesma forma do `order.indexOf` devolvendo
`-1`: **um padrão silencioso comendo um erro real.**

`test/model_role_test.dart` fecha os dois lados agora — toda chave devolvida pelo
switch existe nos dois idiomas, e nenhuma `mv_block_*` está morta. O switch é
lido do fonte porque a função é privada e o controller não pode ser construido em
um teste. O teste que garante que **o parser ainda casa** é o que impede o grupo
de passar em silêncio caso o switch mude de forma.

**Registrado porque o nome engana:** o `ps` mostra `clamd` com 9,8% de CPU e isso
é média desde o start, não consumo atual. Medir instantâneo antes de culpar um
daemon. E uma mutação que sobrevive precisa de um grupo de testes que a **mate**,
não de um teste novo que só passa.

## `d1-omni-600M` não carrega — e são **três** causas, não duas

Medido com um carregador de 30 linhas compilado **contra o fonte vendorizado**, não
contra o `llama.cpp` do sistema. O build precisa de `-DLLAMA_BUILD_APP=OFF`, porque
o vendor é uma cópia podada e o `CMakeLists.txt:258` faz
`add_subdirectory(app)` sem o diretório — sem essa flag o configure falha antes de
compilar qualquer coisa.

O erro que o celular dá, e que a cópia dá igual:

```
llama_model_load: error loading model: check_tensor_dims:
    tensor 'blk.16.ffn_gate.weight' not found
```

**Três incompatibilidades, e cada uma só aparece depois que a anterior é corrigida.**

| # | o arquivo tem | o código exige | onde |
|---|---|---|---|
| 1 | `ffn_gate` nos blocos **0..15**; 16 e 17 não | `ffn_gate` nas 18 | `lfm2.cpp:61` |
| 2 | `attn_qkv` fundido **só nos blocos 16 e 17** | `attn_q_norm` quando `!is_recr(i)` | `lfm2.cpp:73-74` |
| 3 | `feed_forward_length = [4608×16, 4096, 4096]` | um `n_ff` só, `n_ff_arr[0]` | `lfm2.cpp:61-63` |

A 1 resolve com `TENSOR_NOT_REQUIRED` — que devolve `nullptr` e **já é tratado**:
`build_ffn` abre com `if (gate)` (`llama-graph.cpp:1795`). **A segunda causa só ficou
visível porque a primeira foi corrigida.** Isso é o padrão: corrigir uma deixa a
seguinte aparecer, e um relatório que parasse na primeira erradoiria por construção.

A 3 é a que **não é opcional**: `n_ff` é uma variável só antes do loop, então mesmo
que o gate e o `q_norm` passem, o tensor de 16/27 seria criado com 4608 em vez de
4096.

**A 2 é a mais cara e a mais fácil de subestimar.** O `d1-omni` funde Q, K e V num
tensor só — e só nas duas últimas camadas. Isso não é o mesmo modelo com outro
tamanho: o `d1-3B`, que roda, **não tem nenhum** `attn_qkv`. UmGGUF novo da família
`d1` pode trazer um terceiro layout.

**Os números do `feed_forward_length` são um array de 18 valores e `llama-gguf` não
imprime valores de kv, só nomes.** Quem estourou antes foi inferir `n_ff` de
`n_elts / n_embd`, e isso deu 144 e 128 — errados, porque o FFN não é
`n_ff × n_embd`. Os númerosTrue só apareceram lendo o valor da chave.

## O card do `d1-3B` na tela do A72, medido — e onde ele aparece

Verificado no aparelho com o APK debug instalado (0.7.0, `versionCode` 2010).
**A tela do A72 é 1080x2400, mas a imagem é exibida reduzida** — ler coordenadas na
versão reduzida erra o alvo por um fator de 1,17. Foi o que fez três toques seguidos
não abrirem o grupo GGUF e o quarto abrir.

**O card aparece, em `BAIXADOS`, sob o bloco `MODELOS DE DECISÃO`**, e **não** sob
`GGUF`. Isso é a regra `modelSectionKey` funcionando: `downloaded` é testado
**antes** de `fits`, então o teto de RAM nunca esconde um modelo que já está no
disco. Confirmado no aparelho — `d1-3B-Q4_K_M.gguf` tem `1674456672` bytes lá,
idêntico ao `Content-Length` conferido por HEAD.

O card mostra `1.56 GB · 3B · 32k ctx`, `BAIXADO` / `GGUF` / `MULTIMODAL`, botão
**Carregar**, e o ícone de apagar.

**Em `GGUF` ele não está, e é o filtro.** O maior card do GGUF na tela é o
`Qwen3.5 2B` a **1,19 GB** — exatamente o maior que passa no teto de 1,195 GB. Os
37 `.gguf` do catálogo, 16 passam.

**O `GGUF 26` da tela bate com a conta, e só porque o badge conta encoders também:**
16 `.gguf` que passam + 10 encoders = 26. Um número que se lê sem essa conta não
diz nada.

**Os dois grupos e os cards só abrem por toque**, e o toque do A72 responde de forma
irregular — o `Encoders` abriu no primeiro toque, o `GGUF` só no quarto. Toda
medição de tela aqui é por `adb shell input`, nunca por dedo.

## `d1-omni-600M` CARREGA com o vendor re-sincronizado — e não serve como classificador

**O que era verdade continua: o re-sync foi necessário e foi o que resolveu.** Sem
ele, `check_tensor_dims: 'blk.16.ffn_gate.weight' not found`. Com ele, o A72
carrega `d1-omni-600M-Q8_0.gguf` e `/v1/models` responde 200 com ele — medido, com
o build no aparelho.

**O re-sync** foi `src/`, `include/`, `ggml/` e `common/` do upstream
`a657f7e98` (08/10/2026, *"add LiquidAI/d1-omni-600M decision model"*), **402
arquivos**. Preservados 6 que o upstream removeu (`iqp.cpp/h`, `fa.metal`,
`unary_softplus.cpp`, `fattn-buffers.*` — backends que este projeto não compila).
O `libllama.so` novo tem **30** strings `decision`/`systemone`/`lfm2-d1`; a antiga
tinha **0**.

**Dois ajustes foram obrigatórios, e ambos divergem do upstream:**

1. `find_package(SPIRV-Headers CONFIG REQUIRED)` voltou a ser condicional no
   Android. O upstream tornou `REQUIRED` em todo host, e sem os headers o
   `configure` morre antes de compilar qualquer coisa.
2. **`minSdk` do plugin: 26 → 28.** O `ggml-vulkan` novo usa
   `vkGetPhysicalDeviceFeatures2`, e a stub do NDK só exporta isso a partir da
   **API 28**; na 26 o link morre com `undefined symbol`, com todo o resto
   compilando. **O comentário antigo dizia *"Android 8.0 (for SharedMemory
   support)"*, e essa razão não existe no plugin**: `SharedMemory`, `ashmem` e
   `memfd_create` não aparecem em nenhum arquivo do JNI — e `memfd_create` é API
   30. 28 é o que `android/app/build.gradle.kts` já declarava, então isto **alinha
   o plugin ao app**, não baixa o teto do app.

### E o `d1-omni` carrega mas **não classifica** — e isso é do modelo

`/v1/classify` responde **422** com

```
raw: '<|pad|><|pad|><|pad|><|pad|><|pad|><|pad|><|pad|><|pad|>'
```

A geração simples responde `<|reserved_4|><|reserved_25|>` em 16 s: são **tokens
de interface**, não prosa nem letra.

**Medido no desktop contra o mesmo fonte, com o `systemone` montado à mão a partir
do `tokenizer.chat_template.systemone` do próprio GGUF e os special tokens
passados como id** (`<|startoftext|>`=1, `<|reserved_7|>`=17 … `<|reserved_11|>`=21):

| perguntas | opções | resultado |
|---|---|---|
| 3, estado muda, ordem normal | 3 | topo = **índice 2 sempre** |
| 3, estado muda, ordem invertida | 3 | topo = **índice 2 ainda** |
| 2 opções, 6 combinações | 2 | acerta **2 de 6**, e o topo **não segue o estado** |

**Inverter a ordem das opções não muda a resposta**, e o estado não muda o
resultado. **Não é viés de posição, e não é o prompt:** é que o vetor de saída
**tem sempre 3 valores, qualquer que seja o número de opções** — `n_embd_out = 3`,
e 2, 3 ou 4 opções dão 3 valores cada vez. O estado **muda os valores**
(`billing` → `0,4242/0,2622/0,4972`; texto sem relação → todos negativos), então o
modelo está lendo o prompt; ele só não está produzindo uma distribuição **sobre as
opções**.

**Três valores, e três formas de decisão.** A calibração do próprio GGUF nomeia
exatamente três: `choice`, `score` e `noul` (`.2`, `.3_5`, `.6_10`, `.11`, com
temperatura por faixa). O `d1-omni` é um **classificador de forma**, não de
opção — e `n_embd_out = 3` é a assinatura disso.

**Então a integração está errada, e o erro é do app, não do modelo:** o
`d1-omni` **não** é um classificador de opções, e o `/v1/classify` com `choices`
é o contrato errado para ele. Ele precisaria de um endpoint que mande os **três
tipos de resposta** e case o `raw` contra os tokens da interface — e o `d1-3B`, que
**é** um LFM2 generativo e emite uma letra, continua sendo o modelo certo para
`/v1/classify`.

**`capabilities` reporta `classify: false`, e está certo** — mas por um motivo que
ninguém esperava. `isClassifier` exige `pooling == 'rank'`, e este arquivo não
declara `pooling_type`; o caminho **generativo** é que pega o modelo, e é por ele
que ele carrega e responde tokens de interface.

**Uma coisa que eu errei e que muda o quadro:** escrevi que o `d1-omni` estava
"em LFM2 puro" e seria uma alternativa pequena ao `d1-3B`. **Não é** — ele tem 2
blocos de decisão (`lfm2.decision.block_count = 2`), o `attn_qkv` fundido nas duas
camadas finais, e uma cabeça de 3 saídas. São três arquiteturas diferentes na
mesma família, e as três estão medidas aqui.

## O card do `d1-omni-600M` contradiz três coisas que eu escrevi

Lido em <https://huggingface.co/LiquidAI/d1-omni-600M> depois de medir. Ele não
contradiz o que está medido — **contradiz como eu interpretei**, e a diferença
importa porque uma das três muda o diagnóstico.

**1. "É um classificador de forma, não de opção" — eu estava errado, e a forma
está no `criteria`.** O card diz: *"{name: description}"* em `choice`, e o exemplo
é

```python
"team": {"type": "choice", "instructions": "Which team should handle this?",
         "criteria": {"billing": "Charges, refunds, invoices", ...}}
```

que é **exatamente** o prompt que montei. A forma não é "classificador de forma" —
é uma decisão tipada, e `noul`/`choice`/`score` são os **tipos da pergunta**, não as
saídas. `n_embd_out = 3` são as três **perguntas** do exemplo do card, lidas numa
passagem só: `refund` (noul), `team` (choice), `urgency` (score).

**Isso explica a medição que eu interpretei errado.** Eu mandei **uma** pergunta de
tipo `choice` com 3 opções e li 3 valores como "a forma". Na verdade mandei
**três perguntas** e recebi **três respostas** — uma por pergunta, e cada uma com o
tipo dela. O erro foi meu: **não contei o que pedi**.

**2. Zero tokens de saída — e isso é o que realmente o torna incompatível.**
*"It returns typed answers with **zero output tokens**: every answer is read
directly from the model's distribution over the options, with no generation and no
parsing."* E a resposta traz `"usage": {"input_tokens": n, "output_tokens": 0}`.

O app **só tem o caminho generativo** para este arquivo: `generate()` e ler tokens.
Um modelo sem token de saída não tem o que ler. Foi por isso que o
`/v1/classify` viu `<|pad|>`×8 — não é o modelo recusando a pergunta, é o app
perguntando por uma letra onde a resposta é uma distribuição.

**3. ⚠️ "O autor mede o omni como ~3× pior" — eu escrevi isso e está ERRADO.**

O card tem **duas** tabelas, e eu só li uma:

| | `d1-omni-600M` | `d1-3B` | Decider 4B | Decider 2B |
|---|---|---|---|---|
| **Decision Index** | **15,95** | **48,57** | 51,10 | 26,79 |
| **Média "benchmarks as decisions"** | **78,4** | 82,9 | 81,1 | **77,1** |

**A mesma empresa mediu o mesmo modelo em duas tabelas que discordam em 62,5
pontos.** `d1-omni` é o **pior dos onze** no Decision Index e o **segundo de
quatro** na média de benchmarks. Isso não é contradição do autor — é porque as
tabelas medem coisas diferentes:

- O **Decision Index** tem seis eixos (Knowledge 8,3 · Language 12,9 · Retrieval
  35,0 · Tools 15,1 · Arts 6,8). Um eixo que pede *saber responder* precisa de
  **token de saída**, e o `d1-omni` tem **zero** por construção. Ele não é medido
  como modelo ruim; é medido num formato que ele estruturalmente não faz.
- Os **benchmarks as decisions** são SQuAD 2.0, BoolQ, XNLI, PAWS-X, Civil
  Comments, MASSIVE intent e PubMedQA — todos pontuáveis **lendo a distribuição**.
  É exatamente o que o modelo faz.

E o padrão confirma: onde o omni **vence** é `Civil Comments 95,8` e `PAWS-X 79,5`,
**os dois melhores da tabela**, batendo o `Decider 4B` (4,7 B) por 10,3 e 9,7
pontos. Onde ele perde é nos eixos que exigem texto.

**O número honesto é o de decisão, e é o do omni:** 78,4 contra **77,1** do
`Decider 2B`, que tem **2,3 B — quase 4× mais parâmetros**.

**Então a conclusão muda de direção.** Eu escrevi que o ganho seria "um modelo que
o autor mede como o mais fraco dos dois". Não: é **o único de 600 M, o único com
visão e áudio, o único com `confidence` calibrada, e o que ganha de modelos 4×
maiores em tarefa de decisão.**

**⚠️ E a nota de proveniência:** o card diz que as linhas do `d1` na tabela do
Decision Index foram pontuadas pelo **scorer oficial**, e as demais vieram do
**leaderboard público v0.2.1**. Para a tabela de benchmarks ele diz *"internal
evaluations"* e **não diz** se as colunas do Decider vieram da mesma avaliação
interna. Então a comparação do omni contra o Decider 2B é **direção**, não prova.

**Um detalhe do card que é regra de uso e não folclore:** ele foi treino em
`float32`, e em GPU `float16` dá a mesma resposta enquanto **`bfloat16` muda a
resposta em 0,8% das linhas de texto e 1,7% de áudio**. Qualquer backend novo
deste app tem que respeitar isso.

---

## `/v1/systemone` é um padrão entre vendors — e o substrato C++ JÁ ESTÁ NO APK

Esta é a seção mais consequente do guia, e ela é resultado de medir o `.so`, não de
ler prosa. Ela responde à pergunta "dá para implementar o endpoint que falta?".

### A classe é uma só, e agora é prova de quatro empresas

| modelo | empresa | arch | parâmetros | licença |
|---|---|---|---|---|
| **Jev** | TypeSafe | API Only | — | — |
| **Clef** | Cloudflare | `clef` | **27B** (Qwen3.8-27B) | Apache-2.0 |
| **Clef-Flash** | Cloudflare | `clef` | **9B** (Qwen3.5-9B) | Apache-2.0 |
| **d1-omni-600M** | Liquid AI | **`lfm2`** | 0,587B | lfm1.0 |
| **d1-3B** | Liquid AI | `lfm2` | 3,0B | lfm1.0 |
| **Laya** | Convai | ModernBERT-large | 421M | Apache-2.0 |
| **laya-multilingual** | Convai | **mmBERT-base** | 322M | Apache-2.0 |

O card do Clef diz, sem ambiguidade: **"The Clef API is fully compatible with Jev
and SystemOne."** E as tags do repositório são `clef`, `cloudflare`, `systemone`,
`decision-model`. O card do `laya-multilingual` usa a tag `system-one`. **Quatro
empresas, quatro times, um nome de classe e um formato de request.**

O leaderboard do Decision Index que a Cloudflare publica tem **seis** colunas de
modelo — Clef, Clef-flash, **Jev**, **DiffusionGemma Jev**, **Kev 9B**, **Laya** —
o que confirma que a classe é maior ainda e que o "Jev" é **apelido de família**,
não nome de um produto só.

### O contrato, como a Cloudflare o escreve

Corpo de `POST /v1/systemone`:

```json
{
  "model": "clef",
  "state": "Our checkout started returning errors and orders are blocked.",
  "questions": {
    "department": {"type": "choice", "instructions": "Which team should handle the message?",
                   "criteria": {"billing": "Payments or invoices", "technical": "Bugs or outages"}},
    "urgency":    {"type": "score",   "criteria": ["Can wait", "This week", "Today"]},
    "outage":     {"type": "noul",    "instructions": "Is a service down?"}
  }
}
```

Resposta: `model`, `answers` **indexado por id de pergunta**, `usage`.

| tipo | o que a resposta traz |
|---|---|
| `choice` | `choice`, **`confidence`**, **`probabilities`** |
| `score` | `score`, `confidence`, **`legend`**, `probabilities` |
| `noul` | a probabilidade de `true` |

`state` é string **ou JSON**. `criteria` é mapa para `choice`, **lista indexada
de 0** para `score`, e descrições opcionais de `true`/`false` para `noul`.
`instructions` é opcional — sem ele o id da pergunta é a pergunta.

**É exatamente a tabela que eu escrevi em "o que a classe da TypeSafe tem e o que
este app tem". A Cloudflare descreve o mesmo contrato em 2026, e a Liquid AI
entregou um modelo que o implementa.**

### ⚠️ O que o llama.cpp VENDORIZADO JÁ TEM — medido, não inferido

Isto é o que muda o custo da resposta anterior, onde eu escrevi *"o contrato
inteiro não existe no app"* e *"é trabalho de produto, não uma adaptação de
endpoint"*. **A parte cara já está feita e já está no aparelho.**

`src/llama-ext.h` define a ordem de decisão por token:

```c
enum llama_decision_order {
    LLAMA_DECISION_ORDER_NONE            = 0, // not read by the head
    LLAMA_DECISION_ORDER_QUESTION_NOUL   = 1, // text of a question
    LLAMA_DECISION_ORDER_QUESTION_CHOICE = 2,
    LLAMA_DECISION_ORDER_QUESTION_SCORE  = 3,
    LLAMA_DECISION_ORDER_OPTION          = 4, // text of an option
};
LLAMA_API bool llama_batch_ext_set_decision_order(struct llama_batch_ext * batch,
                                                  int32_t idx, enum llama_decision_order order);
```

**Os três tipos que o app não tem, nomeados no cabeçalho nativo, com o mesmo nome
do contrato.** E o `.so` que o app carrega:

```
$ nm -D --defined-only libllama.so | grep -i decision
00000000001a7da4 T _Z34llama_batch_ext_set_decision_orderP15llama_batch_exti20llama_decision_order

$ strings libllama.so | grep -i 'decision\|clef' | sort -u
16llama_model_clef            decision.proj_global       decision.scorer
25llm_graph_input_attn_clef   decision.proj_memory       decision.scorer_out
clef                          decision.proj_option_context  decision.scales
                              decision.proj_option_lexical  decision.option_norm
                              decision.proj_option_question decision.field_norm
                              decision.hidden_norm       decision.option_summary_norm
decision model is missing the scorer tensors
decision model must have one token type per question type
```

E `LLM_ARCH_CLEF` está registrado em `llama-arch.cpp:43` como `"clef"`, com
`llama_model_clef` instanciado em `llama-model.cpp:80`.

**⚠️ Correção de arquitetura minha:** eu disse que o `d1-omni` era um modern-bert com
blocos de decisão. Não é. Lendo o cabeçalho GGUF do arquivo no aparelho:

```
GGUF v3  tensores=179  kvs=55
  general.architecture            = lfm2
  general.name                    = d1-omni-600M
  general.license.name            = lfm1.0
  general.base_model.0.name       = LFM2.5 Encoder 350M
```

São **três** mecanismos de decisão distintos no mesmo vendor, e vale saber qual é
qual:

| arquivo do vendor | arch | `n_embd_out` | de quem |
|---|---|---|---|
| `src/models/lfm2.cpp` | `lfm2` | **3** (`N_DECISION_TYPES`) | Liquid AI — `d1-omni`, `d1-3B` |
| `src/models/modern-bert.cpp` | `modern-bert` | **3** (`N_DECISION_TYPES`) | modern-bert com decisão |
| `src/models/clef.cpp` | `clef` | **1** | Cloudflare — Clef, sobre backbone `qwen35` |

E o `lfm2.cpp:75` recusa carregar se os tipos não baterem:
`"decision model must have one token type per question type"`, com
`type_embd = {n_embd, n_token_types}`. **Os três tipos são um eixo do tensor de
embedding de tipos de token** — o que explica o `n_embd_out = 3` que medi no
aparelho, e explica por que inverter a ordem das opções não muda o índice
principal: a pergunta é o eixo, não a posição.

### ⚠️ O que FALTA é só a ponte, e ela é pequena

| camada | estado | evidência |
|---|---|---|
| cabeçalho de decisão | **presente** | `llama-ext.h:107-115` |
| célula `llama_batch_ext` | **presente** | `llama-batch.cpp:1262` |
| batch repassa a ordem | **presente** | `llama-batch.cpp:207,302,879,907,952` |
| kernels `clef` compilados | **presente no `.so`** | `nm -D` + `strings` acima |
| `llama_model_clef` registrado | **presente** | `llama-arch.cpp:43`, `llama-model.cpp:80` |
| `Clef` no conversor | **AUSENTE** | 220 registros em `conversion/`, **nenhum** `Clef` |
| `Lfm2Model` no conversor | **presente** | `conversion/lfm2.py` |
| `Qwen3_5ForConditionalGeneration` | **presente** | `conversion/qwen.py` — o backbone do clef converte |
| **JNI expõe a chamada** | **AUSENTE** | `llama_batch_ext` aparece **0×** em `jni_wrapper.cpp` |
| **Pigeon declara o método** | **AUSENTE** | `decision_order`/`clef` = **0×** em todo `.dart` |
| **rota HTTP `/v1/systemone`** | **AUSENTE** | `systemone` = **0×** em todo o vendor |
| **implementação HTTP de referência** | **AUSENTE** | `examples/` não tem `server/` |

O que falta, então, são **três arquivos tocados e nenhum**:

1. **Pigeon** — um método que leva a lista de perguntas tipadas e a ordem por token
2. **`jni_wrapper.cpp`** — uma função que chama
   `llama_batch_ext_set_decision_order`, roda o batch e devolve `float[3]` por
   pergunta mais `float[n_opcoes]` por pergunta de `choice`
3. **`openai_server_service_io.dart`** — a rota `/v1/systemone`, com `answers`
   indexado e `confidence` de verdade

**Não há `server/` no vendor para portar** — a rota `/v1/systemone` do llama.cpp
existe no upstream, mas a árvore vendorizada é podada e não a traz. A implementação
é nova, sobre uma base nativa que já está toda lá.

### ⚠️ E o tamanho fecha a porta para o Clef no A72

`maxModelBytes = totalRamGB * 0.25`, e o A72 tem `MemTotal 5011844 kB` = 4,78 GB.
O teto é **1,19 GB**.

| modelo | melhor quantização plausível | cabe em 1,19 GB? |
|---|---|---|
| Clef (27B) | IQ2_XXS ~9 GB | **não, ~7,5× acima** |
| Clef-Flash (9B) | IQ2_XXS ~3,1 GB | **não, ~2,6× acima** |
| **d1-omni-600M** | Q8_0 = **388,3 MB, medido no aparelho** | **sim, sobra 800 MB** |

### ⚠️ O Clef tem TRÊS bloqueios independentes, e medidos

1. **O conversor não sabe produzi-lo.** `conversion/` tem 21.672 linhas, 87
   arquivos e **220 registros** de `ModelBase.register` — e `Clef` não é um deles.
   Não existe `clef.py`. O `Qwen3_5ForConditionalGeneration` **está** registrado, ou
   seja, o *backbone* converte e a *cabeça* não. **Um `Cloudflare/clef` não vira
   GGUF neste vendor.** (`Lfm2Model` e `ModernBertModel` **estão** registrados, o
   que é consistente com o `d1-omni` já estar no aparelho em GGUF.)
2. **O tamanho não cabe.** 27B e 9B contra um teto de **1,19 GB** — 7,5× e 2,6×
   acima. Nenhum quantization do Clef entra no catálogo do A72.
3. **A ponte falta**, como para todo mundo.

**Isso não é argumento para nunca implementar.** É argumento para implementar
**no `lfm2`**, porque é o único `arch` de decisão que (a) converte, (b) cabe e
(c) já tem os três tipos no kernel.

A mesma tabela do card do Clef dá a **latência mediana**, e ela é o outro lado da
moeda:

| | mediana | p95 |
|---|---|---|
| **Laya** | **5,8 ms** | 222,5 ms |
| Clef-Flash | 38,8 ms | 122,4 ms |
| Kev 9B | 51,4 ms | 187,9 ms |
| Jev | 524,1 ms | 536,0 ms |
| Clef | 209,3 ms | 238,6 ms |

**O Laya é o mais rápido da classe por 6,7×, e é o mais fraco** — BFCL 38,1,
SATA-Bench 0,3, Home appliance 0,0. **Velocidade e qualidade de decisão não andam
juntas: `SATA-Bench 0,3` e `Home appliance 0,0` significam "não tenta", não
"tentou e errou"**
— é o que a cabeça de 1 MB faz quando o encoder não está lá.

---

## Laya, `laya-multilingual` e o que o card deles prova sobre este app

O card de <https://huggingface.co/convaiinnovations/laya-multilingual> foi lido na
íntegra. Três coisas nele são medíveis contra este app: **o que não converte**, **o
que é a cabeça de 1 MB que já está no aparelho**, e **a evidência mais forte de que
o desenho de estabilidade por permutação deste app está certo.**

### A família, e qual peça de cada uma existe aqui

| checkpoint | backbone | params | ctx | converte com o vendor? |
|---|---|---|---|---|
| `convaiinnovations/laya` (EN) | ModernBERT-large | 421M | 512 | **sim** — `ModernBertModel` existe |
| **`laya-multilingual`** | **mmBERT-base** | 322M | 1024 (até 8192) | **NÃO** |
| `laya-typed-decisions` | ModernBERT-large | 421M | 1024 | **sim**, mesma arch |

**⚠️ `laya-multilingual` é um beco sem saída com o vendor atual, e é fato do
conversor, não opinião.** `conversion/bert.py` registra:

```
BertModel · DistilBertModel · RobertaModel · NomicBertModel · NeoBert ·
EuroBertModel · XLMRobertaModel · JinaBertV2Model · ModernBertModel
```

**Nenhum `MMBertModel`.** O `mmBERT` é da Apple (bidirecional, 22 camadas, hidden
768, **vocabulário de 256 mil**), e `mmbert` não existe como arch em
`llama-arch.h` — nem `xlmroberta`, nem `roberta` como arch próprio (o
XLMRoberta do conversor reconverte para `bert`). **Sem arch, sem GGUF, sem
carregar.** Isso vale registrar porque `laya-multilingual` é o checkpoint que o
card manda usar para **tudo que não seja inglês**, e ele é exatamente o que este
vendor não sabe ler.

### A cabeça de 1,0 MB que já está no aparelho

O `laya_en_act_head_fp32.tflite` de **1,0 MB** no `app_flutter/models` é a
cabeça **act/escalate** do checkpoint **inglês** — *"a decision head trained from
scratch: 2 transformer layers, an option-marker scorer, and an act/escalate
head"*. O app mediu 6 ms de compilação e 0–2 ms de run no XNNPACK, contra 273 ms
na GPU, e ela dá exatamente os mesmos logits que o `/v1/litert/run`.

Os **1024 features** que ela quer são a saída do **ModernBERT-large de 421 MB**,
e esse encoder não está no app. **É o item 2 da fila, e agora sabemos o nome
exato dele**: `convaiinnovations/laya`, ModernBERT-large, e é o backbone que o
conversor **sabe** ler. A peça de 1 MB e a de 421 MB são do mesmo checkpoint — o
app tem uma e não tem a outra, e por isso a mais rápida do mundo não roda de
ponta a ponta.

### ⚠️ Convertível não é servível — e aqui está por quê

O mecanismo do Laya é **marcadores de opção**: *"every option is scored at its own
`[MASK]` token, then softmaxed over that question's options"*. Isso exige
**logits em posições escolhidas** de um encoder bidirecional.

O caminho de encoder do llama.cpp — que o app usa e mediu — emite **embeddings** e
a saída de uma cabeça `cls.output`. A `conversion/bert.py` registra
`ModernBertForMaskedLM`, mas um GGUF de masked-LM continua sendo lido pelo mesmo
`cls.output`: o llama.cpp **não lê logits por posição** num encoder. Não há
`logprobs` em lugar nenhum do binding Dart deste app.

**Então: registrar `ModernBertForMaskedLM` no conversor não destrava o Laya.** O
que destravaria é ler posição por posição, que é o que a cabeça `clef` faz de um
jeito diferente — roteando evidência do estado para cada pergunta em vez de pôr um
`[MASK]` por opção. **O Laya e o Clef são a mesma classe com dois mecanismos
diferentes, e só um dos dois tem base no vendor deste app.**

### ⚠️ O card prova, com número, por que este app trocou porcentagem por estabilidade

Esta é a parte que vale mais, e ela **valida uma decisão já tomada** com dado de
terceiro:

**1. Confiança não detecta erro — e o card diz isso com todas as letras.**

> Its mean confidence never drops below **0.885** at any accuracy level, so
> **confidence gating cannot catch it.**

Khmer: **0,000 de acerto a 0,952 de confiança**. Hebrew 0,060. Armenian 0,050
(exatamente aleatório). Bengali 0,080. **Todos reportados entre 0,89 e 0,96 de
confiança.** Macro ECE do checkpoint inglês: **0,733**; o multilíngue, 0,387.

É por isso que `relevance_score` é `null` neste app com o motivo anexado, e é por
isso que a nota de catálogo do `d1-3B` promete **estabilidade por permutação** e
não porcentagem. **Um bar chart de logits rotulados de confiança é mentira
deixada em forma de gráfico** — e o Laya é o caso de estudo.

**2. O viés de posição é real, tem nome e é medido.**

> Ordinal `score` questions are the weakest primitive (SST-5 0.282), and this
> checkpoint has a **measured position bias on them**: it rarely picks the
> first-listed level, in any language, including English (**0 of 290** in one
> independent run).

**"0 of 290"** é o mesmo defeito que `variants` existe para pegar neste app: um
modelo que responde diferente conforme a ordem das opções não está decidindo, está
decorando a posição. A permutação **round-robin por primeira letra + Lehmer
dentro do grupo** do `decision_stability.dart` é a resposta a isso, e o Laya
confirma que a pergunta não éredi — é como esses modelos funcionam.

**3. `noul` subdeclara o `true`.** *"On a clearly positive input, one measurement
put `P(true)` at about 0,5 while the negative case was correctly near 0"* — e o
próprio card sugere a checagem: a mesma pergunta como `choice` de duas opções com
chaves neutras. **É exatamente um teste de permutação, escrito por quem mediu o
problema.**

**4. O limite de ~20 opções por `choice` é o mesmo teto do `d1`.** *"Options share
the fixed 256-token head budget, so a very large label space leaves only a few
tokens per label"*. O app já cobra esse limite no `/v1/classify` com o erro
*"at least two, at most twenty-four"*.

**5. E a calibração é pós-hoco, com um formato específico:** `temperature` por
**(tipo de pergunta, contagem de opções)**, medindo ECE 0,314 → 0,106. **Esse é o
parâmetro que o app não tem e que valeria ter** — e é o formato exato das
permutas que ele já faz.

### O número do Laya na tabela da Cloudflare, e o que ele significa

`Laya` na tabela do Decision Index é o **mais rápido** (mediana **5,8 ms**) e o
**mais fraco** (BFCL 38,1 · API-Bank 11,5 · SATA-Bench 0,3 · Home appliance
**0,0** · MMLU 30,7). `RouterBench 57,1` é a única linha em que ele não está
perto do chão.

**Um 0,0 numa benchmark significa "não tenta", e há uma razão mecânica para isso
que eu posso apontar:** a cabeça de 1 MB está no app sem o encoder de 421 MB que a
alimenta. **E é a única comparação honesta entre o Laya e o `d1-omni`, porque os dois são
pequenos e ambos publicam número próprio.** O `laya-multilingual` em intent de 20
opções nas 51 línguas do MASSIVE: macro 0,366, macro ECE 0,387, e **45 de 51
línguas acima de 3× o aleatório** — contra 23 de 51 do checkpoint inglês. O
`d1-omni` tem 78,4 de média em benchmarks-as-decisions e 0 tokens de saída.

**Nenhum dos dois é "o modelo de decisão". São dois formatos de 300–600 MB, e o
formato é a escolha, não o tamanho.**
