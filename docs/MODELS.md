# A aba Models

## Seções

A lista local não é mais um filtro com chips — são seções empilhadas, todas
visíveis na mesma rolagem. Um modelo aparece em **exatamente uma**, e a ordem
dos testes é a regra:

1. **Downloaded** — está em disco. Ganha de tudo, inclusive de "custom".
2. **Custom GGUF Models** / **Custom LiteRT Models** — adicionado à mão
   (`isCustom` ou `isImported`), separado por runtime.
3. **GGUF** / **LiteRT** / **Image** — o catálogo, separado por runtime.

Seção vazia não aparece. Quem decide isso é `modelSectionKey`, uma função pura
no topo de `lib/controllers/model_controller.dart` — está fora do controller
de propósito, porque a precedência é o que quebra e precisa de teste
(`test/model_sections_test.dart`).

### Sub-blocos

Dentro de uma seção, `_byModality` agrupa em **Text**, **Vision**,
**Multimodal** e **Image generation**. Se só existir um grupo, a seção
renderiza sem sub-cabeçalho.

Esses quatro são os únicos que o catálogo consegue distinguir de verdade:
existe um flag `vision` e a presença de um arquivo mmproj, e nada mais. **Não
há campo dizendo "audio" ou "omni"** — e os arquivos LiteRT multimodais
(gemma-4 E2B/E4B) passam fala e imagem pelo mesmo encoder, então separá-los
seria adivinhação em cima do nome do arquivo. Se um dia o catálogo ganhar um
campo de modalidade, os blocos saem de graça daqui.

### O teto de memória

Entradas do catálogo só aparecem se couberem em `DeviceInfoService.maxModelBytes`
(60% da RAM). Um modelo curado que não carrega é pior que nenhum.

**O teto não vale para o que o usuário baixou ou adicionou à mão** — ele pediu
por nome, e escondê-lo seria mentir sobre o que está no aparelho. Isso é o que
o teste `a catalogue model too big for the phone is hidden, not misfiled`
protege.

## Por que Q4_0 e quantização consciente

Os modelos do catálogo marcados **QAT** ou **QAD** foram treinados já sabendo
que terminariam em 4 bits, então o build Q4_0 fica muito mais perto do modelo
em precisão cheia do que um quant pós-treino do mesmo tamanho.

Q4_0 também é o layout que o llama.cpp reempacota para os kernels ARM de
dot-product e i8mm — é o caminho de 4 bits mais rápido num celular. Foi o que
rendeu melhor desempenho na prática aqui.

Cada fabricante batiza a receita de um jeito: **Google diz QAT, Liquid diz
QAD**. São a mesma ideia.

### O que existe de verdade (medido no Hub, ago/2026)

Só esses dois. Foram checados também `QAFT`, `QAF`, `QAT-SFT`, `LQT`, `DQ`,
`QAB`, `QAT_RLHF` e `QAT-DPO`: ou não retornam nada, ou casam com repos que
apenas contêm aquelas letras (`meditron_sr_qaft_7b` é um fine-tune médico,
`PRISM-PRO-DQ` é sufixo de merge, `Qabalah-12B` é o nome do modelo). Nenhum é
um formato de quantização publicado.

### O filtro no sheet do Hugging Face

`QUANTISATION → Quantisation-aware only`. O predicado é `isQuantizationAware`
em `lib/services/hf_search_service.dart`, e casa **tokens inteiros**, nunca
substring: três letras pegam coisa demais senão — `Qabalah-12B` é nome de
modelo, `qafast` é handle de usuário, `PRISM-PRO-DQ` é sufixo de merge. Os
testes em `test/hf_search_service_test.dart` fixam esses três como negativos.

O marcador pode estar **no repo ou só no arquivo**: a Google publica
`google/gemma-4-E2B-it-qat-q4_0-gguf`, mas a LiquidAI publica
`LiquidAI/LFM2.5-1.2B-Instruct-GGUF` com `…-QAD-Q4_0.gguf` dentro. Por isso o
filtro lê o id, as tags e a lista de arquivos — e só quando ele está ligado a
busca pede `full=true` no Hub, que triplica o payload (11 KB → 32 KB por
página de 20).

Para estender: `_quantAwareMarkers`, um lugar só.

### Regras para adicionar ao catálogo

- **Verificar a URL antes de commitar.** Os repos oficiais
  `google/gemma-3-*-qat-q4_0-gguf` são *gated*: devolvem **401** sem token do
  Hugging Face, e o download quebraria no aparelho. Use espelho aberto
  (lmstudio-community, bartowski) — mesmos pesos.
- **Conferir o nome do projetor.** `mmprojFilename` é o nome em disco. O
  espelho unsloth chama o dele de `mmproj-F16.gguf`, genérico o bastante para
  colidir com o de outro modelo. O bartowski usa
  `mmproj-google_gemma-3-4b-it-qat-f16.gguf` — sem colisão.
- **Tamanho vem do `content-length` real**, não do card do modelo.
