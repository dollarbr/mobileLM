# O que veio do fork do PrivateLM

O fork `dollarbr/privateLM` foi apagado (pasta local e repositório no GitHub).
Ele existia só como referência, e a referência de verdade continua pública em
**[orailnoor/cross-platform-llm-client](https://github.com/orailnoor/cross-platform-llm-client)**
— o upstream do qual aquele fork saiu.

O que morreu junto foi o trabalho que estava **só** naquela pasta: o commit
`65592dc` (nunca empurrado para nenhum remote) e algumas edições soltas. Este
documento registra o que aquilo fazia e o que funcionou, para poder ser refeito
no mobileLM sem redescobrir nada.

## `65592dc` — model metadata, backup e settings

~2.700 linhas em 18 arquivos. As partes que valeram:

### Sonda do header GGUF (o que mais vale a pena trazer)

`LlamaModelMeta` (`local_plugins/llama_flutter_android/lib/src/llama_meta.dart`)
lia metadados do modelo por um `MethodChannel` próprio,
`llama_flutter_android/model_meta`, com duas operações:

- `get(key)` — valor de uma chave do modelo **carregado**.
- `probeFile(path)` — lê `arch`, `context_length` e `size_label` direto do
  header de um GGUF **em disco, sem carregar o modelo**. Devolve mapa vazio
  quando o arquivo some ou não é um GGUF legível.

Canal próprio em vez da API Pigeon porque o schema gerado não está no repo e a
busca chave/valor se basta sozinha. A tela de lista e a de detalhe do modelo
foram reconstruídas em cima desses dados sondados — em vez de adivinhar
tamanho e contexto pelo nome do arquivo.

### BOS duplicado no Llama-3.x — bug real, corrigido

Em `jni_wrapper.cpp`. Os chat templates já embutem o BOS quando o modelo
precisa; tokenizar isso com `add_special = true` produzia **dois** tokens BOS
(o llama.cpp avisa com `check_double_bos_eos`) e degradava a saída do
Llama-3.x de forma mensurável.

A correção foi uma função `prompt_already_has_bos(vocab, prompt)`: pega
`llama_vocab_bos(vocab)`, converte para texto com `llama_token_to_piece`, e
compara com o início do prompt. Aí `add_special = !prompt_already_has_bos(...)`
nos dois pontos de tokenização (contagem e tokenização real). Devolve `false`
quando o vocab não tem BOS (`LLAMA_TOKEN_NULL`).

**Se o mobileLM usar chat template com llama.cpp, esse bug existe lá também.**

### Backup/restore por SAF

`lib/services/download_native.dart`, canal nativo:

| Operação | Papel |
|---|---|
| `pickBackupTree` | Abre o seletor de pastas do sistema; a permissão é persistível — escolhe uma vez, reusa sempre |
| `copyToTree` | Copia para o backup. Resultado tri-estado: `0` falhou, `1` copiou, `2` pulou (idêntico já lá) |
| `copyFromTree` | Restaura |
| `ensureTreePath` | Garante um caminho aninhado dentro da árvore concedida, devolve a folha |
| `listTreeRecursive` | Todo arquivo de modelo em qualquer lugar da árvore (pula `settings/`) |
| `restartApp` | Reinício após restaurar |

Arquivos de modelo eram opcionais no backup — são os GB todos.

O mobileLM já tem SAF próprio para o workspace (ver `docs/WORKSPACE.md`), com
outro canal (`com.aichat.ai_chat/workspace`). O tri-estado do `copyToTree` e o
"pula se idêntico" são as ideias reaproveitáveis; o resto seria duplicação.

### Sampling exposto nas settings

`settings_controller` ganhou os knobs persistidos em Hive, com clamp na
escrita: `temperature` 0.20, `topP` 0.9 (0–1), `topK` 40 (1–200), `minP` 0.05
(0–1), `repeatPenalty` 1.1 (1–2), `maxTokens` 1024, `contextSize` 4096,
`imageSteps` 8. Os defaults acima são os que funcionavam bem na prática.

Junto: seção de aparência e uma de informações do aparelho.

## Edições soltas (nunca commitadas)

Trabalho feito no projeto errado — o pedido era para o mobileLM. Não foi
portado; fica o desenho.

### Aba Models em três seções

Um modelo cai em **exatamente uma** faixa, nesta ordem de precedência:

1. **Downloaded** — está em disco (`isDownloaded(filename)`), ganha de tudo.
2. **Custom Models** — adicionado à mão: entrada por URL ou arquivo importado
   do armazenamento (`m.isCustom || m.isImported`).
3. **Curated Models** — o catálogo que vem com o app.

`downloaded` deixou de ser filtro e virou cabeçalho; o filtro padrão passou a
ser `all`.

### Ordenação no sheet do Hugging Face

A API do hub aceita `downloads`, `likes` e `lastModified` em `sort`. **Não
existe chave de tamanho** — um repositório não tem tamanho único enquanto você
não lista os arquivos dele.

Então "smallest" foi ordenação **client-side**, pela contagem de parâmetros que
o nome do arquivo anuncia — que é justamente o número que decide se o celular
consegue carregar. O resto vai como `sort` na query.

Efeito colateral: com ordenação local, uma página inteira pode filtrar para
nada. Precisou de um contador `emptyPages` de páginas vazias consecutivas para
a paginação parar em vez de rodar para sempre.
