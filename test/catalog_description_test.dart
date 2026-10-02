import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/core/constants.dart';
import 'package:mobilelm/services/language_preference.dart';

/// A ficha do catálogo é **texto de tela nos dois idiomas**, e ela tem três
/// defeitos que só aparecem quando alguém olha.
///
/// O histórico deste arquivo é instructive e vale como aviso. A primeira versão
/// traduziu as 62 descrições para português e-judou que **cinco** terminavam em
/// meia-frase, com uma lista de cinco strings no teste. **Quatro das cinco
/// não terminavam** — elas terminavam em `"above"`, `"matters."`, `"matters."`
/// e `"here."`. O que acabava nelas era o **primeiro segmento** de um literal
/// adjacente, e o Dart concatena os vizinhos em tempo de compilação.
///
/// Ou seja: **o diagnóstico de "texto faltando" era o meu próprio bug de
/// extração aparecendo como achado.** Uma Description completa e traduzida com
/// confiança no meio de uma lista de supostos defeitos é pior do que nenhuma,
/// porque a lista é o que convence a próxima pessoa a não olhar. **Uma** das
/// 62 estava truncada de verdade — a `SmolLM2 135M`, que termina em
/// `"before they describe this"`, e o `this` pendente é o que denuncia.
///
/// O que fica aqui é o que é verificável sem depender de uma lista de
/// defeitos passados.
void main() {
  const en = Locale('en', 'US');
  const pt = Locale('pt', 'BR');

  List<Map<String, String>> todas() => [
        ...AppConstants.availableModels,
        ...AppConstants.encoderModels,
      ];

  /// Uma entrada é "de catálogo" se tem `filename` — é o que separa as fichas
  /// de modelo de qualquer outro mapa que o app carregue.
  bool ehDeCatalogo(Map<String, String> m) => (m['filename'] ?? '').isNotEmpty;

  test('o catálogo tem entradas para testar, e são as mesmas que a tela mostra',
      () {
    // 46 no catálogo + 16 encoders = 62, que é o que a tela de Modelos
    // reporta. Este número já esteve errado mais de uma vez neste repo — o
    // guia dizia 46 e a auditoria de cobertura dizia 10 encoders (7+3) — e os
    // dois estavam errados por bastante para a tela e a documentação se
    // contradizerem. O teste afirma em vez de descrever.
    expect(AppConstants.availableModels.length, 46);
    expect(AppConstants.encoderModels.length, 16);
    expect(todas().length, 62);
  });

  test('toda entrada tem ficha nos DOIS idiomas, e nenhum deles vazio', () {
    // **O par é o que impede a classe de defeito que o seletor de idioma veio
    // consertar.** Com EN como padrão, uma entrada com só a ficha portuguesa
    // publica português num app inglês sem nenhum aviso: a tela mostra *alguma*
    // descrição, e uma descrição presente não parece um erro.
    final semPar = <String>[];
    for (final m in todas()) {
      if (!ehDeCatalogo(m)) continue;
      final a = (m['descriptionEn'] ?? '').trim();
      final b = (m['descriptionPt'] ?? '').trim();
      if (a.isEmpty || b.isEmpty) {
        semPar.add('${m['name']}: en=${a.isEmpty ? 'VAZIA' : 'ok'} '
            'pt=${b.isEmpty ? 'VAZIA' : 'ok'}');
      }
    }
    expect(semPar, isEmpty,
        reason: 'Estas fichas têm metade do par. A tela mostra uma delas '
            'conforme o idioma, e uma ficha presente não parece erro:\n'
            '  ${semPar.join('\n  ')}');
  });

  test('a ficha em português está em português, e a de inglês em inglês', () {
    // **A lista é de português e a pergunta é se falta uma palavra portuguesa.**
    //
    // A primeira versão fez o inverso: uma lista do que **não pode** aparecer,
    // e acusava o que sobrasse. Isso acusa português — "menor modelo de uso
    // geral" não está na lista de inglês, sobra tudo, e o teste reprova texto
    // que está **correto**. Uma lista do que não pode aparecer só funciona
    // quando o resto da lista é o universo, e o resto é outro idioma.
    const portugues = <String>{
      'o',
      'a',
      'os',
      'as',
      'um',
      'uma',
      'de',
      'do',
      'da',
      'dos',
      'das',
      'em',
      'no',
      'na',
      'nos',
      'nas',
      'com',
      'sem',
      'por',
      'para',
      'pelo',
      'pela',
      'que',
      'se',
      'nao',
      'mais',
      'menos',
      'e',
      'ou',
      'mas',
      'como',
      'quando',
      'onde',
      'porque',
      'porem',
      'ja',
      'ainda',
      'so',
      'ate',
      'menor',
      'maior',
      'modelo',
      'modelos',
      'aparelho',
      'celular',
      'pesos',
      'projector',
      'visao',
      'texto',
      'imagem',
      'imagens',
      'audio',
      'video',
      'chat',
      'resposta',
      'precisa',
      'precisam',
      'apenas',
      'multilingue',
      'equilibrado',
      'equilibrada',
      'rapido',
      'rapida',
      'leve',
      'pesado',
      'grande',
      'pequeno',
      'melhor',
      'pior',
      'forte',
      'fraco',
      'cabe',
      'folga',
      'espaçoso',
      'espacoso',
      'aparelhos',
      'lista',
      'mesmo',
      'mesma',
      'cada',
      'este',
      'esta',
      'isso',
      'aquilo',
      'versao',
      'licenca',
      'conversa',
      'conversar',
      'pipeline',
      'testar',
      'teste',
      'usar',
      'uso',
      'entrada',
      'saida',
      'ler',
      'leitura',
      'geral',
      'qualidade',
      'velocidade',
      'metade',
      'dobro',
      'arquitetura',
      'arquiteturas',
      'formado',
      'formada',
      'sao',
      'tem',
      'tambem',
    };

    /// Termos que o produto mantém em inglês **de propósito**.
    ///
    /// Não é desculpa genérica: `reranker` e `embedder` são o nome do papel de
    /// cada encoder e aparecem em badge e cabeçalho ao lado de um endpoint
    /// chamado `/v1/rerank`. Traduzi-los faria a UI nomear algo que não
    /// existe. `mean-pooling`, `pooler`, `cls.output.weight`, `arch bert`, `MoE`
    /// e os nomes de projector são o vocabulário de quem lê a ficha técnica,
    /// e a ficha técnica é o que a descrição é.
    const termosDoProduto = <String>[
      'reranker',
      'embedder',
      'mean-pooling',
      'pooler',
      'projector',
      'MoE',
      'cross-encoder',
      'offload',
      'arch',
      'cls.output.weight',
      'pooling_type',
      'ndcg',
      'mit',
      'lcm',
      'fp16',
      'bf16',
      'qat',
      'int8',
      'ram',
      'npu',
      'gptq',
      'llama.cpp',
      'ai',
      'api',
      'token',
      'tokens',
      'kv',
      'moe',
      'llm_arch',
      'sparse',
      'e2b',
      'e4b',
      'lite',
      'rt',
      'lm',
      'gguf',
      'safetensors',
      'vram',
      'tc',
      'q4',
      'q8',
      'q2',
      'k',
      'm',
      'b',
      'q',
      'fp',
      'nomic',
      'gte',
      'bce',
      'jina',
      'e5',
      'bge',
      'bert',
      'modernbert',
      'qwen',
      'gemma',
      'llama',
      'lfm',
      'spark',
      'smol',
      'phi',
      'deepseek',
      'kimi',
      'moonshot',
      'google',
      'microsoft',
      'huggingface',
      'mistral',
      'ministral',
      'dolphin',
      'nvidia',
      'openai',
      'dream',
      'shaper',
      'cyber',
      'realistic',
      'absolute',
      'lora',
      'anime',
      'abliterated',
      'unsloth',
      'bartowski',
      'instruct',
      'distill',
      'vision',
      'encoder',
      'embed',
      'gpu',
      'cpu',
      'vision-language',
      'edge',
      'galaxy',
      'screen',
      'screenshots',
      'interface',
      'ui',
    ];

    /// As palavras do próprio nome do modelo não são idioma.
    Set<String> semNome(String texto) {
      final probe = texto
          .toLowerCase()
          .split(RegExp(r'[^a-zà-ÿ0-9.+-]+'))
          .where((w) => w.length > 1)
          .toSet();
      return probe.where((w) => !termosDoProduto.contains(w)).toSet();
    }

    final foraPt = <String>[];
    for (final m in todas()) {
      if (!ehDeCatalogo(m)) continue;
      final sobra = semNome(m['descriptionPt'] ?? '');
      if (sobra.isEmpty) continue;
      if (sobra.intersection(portugues).isEmpty) {
        foraPt.add('${m['name']}: sobrou ${(sobra.toList()..sort()).take(5)}');
      }
    }
    expect(foraPt, isEmpty,
        reason: 'A tela de Modelos é pt_BR quando o idioma é pt_BR, e estas '
            'fichas não têm nenhuma palavra em português:\n'
            '  ${foraPt.join('\n  ')}');
  });

  test('nenhuma ficha termina em meia-frase', () {
    // **Uma regra de pontuação reprovava as 62** — nenhuma delas termina com
    // ponto, é a convenção do catálogo — e **uma lista de palavra funcional
    // reprovava texto correto** ("…antes de valer para este modelo" é uma
    // frase completa; o `E5 Small v2` termina com a citação `"passage: "` e
    // logo depois `como todo E5.`). As duas versões erradas estão aqui
    // registradas porque a tentadora é a mesma.
    //
    // O que separa "cortado" de "completo" é o **conteúdo da última
    // expressão**: uma frase que pede complemento para terminar. Em inglês
    // isso é um demonstrativo ou uma preposição pendurada ("before they
    // describe **this**", "so it **has**"); em português, uma preposição
    // ("…vale para **este modelo**" não pede nada, mas "…medido em teste **no**"
    // pede).
    //
    // **A lista abaixo é o que sobrou: uma string por idioma.** Não é uma regra
    // de estilo — é a transcrição do defeito, e é ela que impede a volta.
    //
    // O casamento é por **`endsWith`, não por `contains`**, e a diferença não é
    // preciosismo: a correção da ficha ficou `"…before they describe this
    // model"`, que **contém** a string quebrada. Com `contains` o conserto era
    // reprovado pelo teste que existe para exigi-lo, e a saída seria afrouxar o
    // defeito para fazer o verde aparecer — o oposto do que o teste quer.
    const naoPodeTerminarAssim = <String>{
      'before they describe this',
    };
    final cortadas = <String>[];
    for (final m in todas()) {
      if (!ehDeCatalogo(m)) continue;
      for (final idioma in const ['descriptionEn', 'descriptionPt']) {
        final d = (m[idioma] ?? '').trim();
        for (final padrao in naoPodeTerminarAssim) {
          if (d.endsWith(padrao)) {
            cortadas.add('${m['name']} [$idioma]: …$d');
          }
        }
      }
    }
    expect(cortadas, isEmpty,
        reason: 'O Text da ficha não tem maxLines, então uma frase cortada '
            'aparece cortada na tela:\n  ${cortadas.join('\n  ')}');
  });

  test('toda ficha é uma frase, e não um rótulo nem um número', () {
    // **Não exige ponto final, e essa foi uma regra que eu quase escrevi.** As
    // 62 terminam sem ponto — "4 bits, ajustado para aparelhos de borda", "…
    // precisa de um projector de 0,79 GB". É a convenção do catálogo, é legível
    // num card de 12 px, e impor pontuação seria reescrever 124 strings para
    // satisfazer um estilo que ninguém pediu — com o risco de cortar um
    // "0,79 GB." no fim, que parece errado.
    //
    // O que **é** defeito é a ficha que não é frase: um rótulo ("LiteRT-LM")
    // ou um número ("586 MB"). A tela pinta a linha do mesmo jeito e o card
    // fica com uma informação que não diz nada.
    final naoFrase = <String>[];
    for (final m in todas()) {
      if (!ehDeCatalogo(m)) continue;
      for (final idioma in const ['descriptionEn', 'descriptionPt']) {
        final d = (m[idioma] ?? '').trim();
        if (d.isEmpty) continue;
        final palavras = d.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
        if (palavras.length < 3) {
          naoFrase.add('${m['name']} [$idioma]: "$d" (${palavras.length} '
              'palavra(s))');
          continue;
        }
        if (!RegExp(r'[a-zà-ÿ]').hasMatch(d)) {
          naoFrase.add('${m['name']} [$idioma]: "$d" (sem palavra)');
        }
      }
    }
    expect(naoFrase, isEmpty,
        reason: 'A ficha é pintada no card; um rótulo ou um número ocupa a '
            'mesma linha sem informar nada:\n  ${naoFrase.join('\n  ')}');
  });

  test('as duas fichas dizem coisas diferentes, senão uma é de mercado', () {
    // Um par idêntico significa que a tradução não aconteceu e ninguém notou,
    // porque a tela mostra um texto qualquer e um texto qualquer parece certo.
    // Já aconteceu com as descrições em inglês numa tela portuguesa.
    final iguais = <String>[];
    for (final m in todas()) {
      if (!ehDeCatalogo(m)) continue;
      final a = (m['descriptionEn'] ?? '').trim();
      final b = (m['descriptionPt'] ?? '').trim();
      if (a.isEmpty || b.isEmpty) continue;
      if (a == b) iguais.add(m['name'] ?? '?');
    }
    expect(iguais, isEmpty,
        reason: 'Ficha EN e PT idênticas: ou a tradução não foi feita, ou foi '
            'colada num idioma que não é o dela:\n  ${iguais.join('\n  ')}');
  });

  test('`descriptionFor` escolhe pelo idioma, e a queda vai para o que existe',
      () {
    // O par vive em dois campos com o idioma no nome justamente para que a
    // escolha aconteça num lugar só. A queda é do pedido para o que existe,
    // nunca para a string vazia: uma ficha em falta mostra a linha em branco
    // num card que já tem nome, tamanho e template, e o vazio parece defeito
    // do aparelho.
    expect(
        LanguagePreference.descricao(
            en: 'English text', pt: 'Português', locale: en),
        'English text');
    expect(
        LanguagePreference.descricao(
            en: 'English text', pt: 'Português', locale: pt),
        'Português');
    // Falta uma metade: a que existe é a resposta, e não a vazia.
    expect(
        LanguagePreference.descricao(en: 'English text', pt: null, locale: pt),
        'English text');
    expect(LanguagePreference.descricao(en: null, pt: 'Português', locale: en),
        'Português');
    // Faltam as duas: vazio, e não a palavra de alguém.
    expect(LanguagePreference.descricao(en: null, pt: null, locale: en), '');
  });

  test('a ficha do catálogo real resolve nos dois idiomas sem cair', () {
    // A regra acima num mapa de mentira passaria mesmo com o catálogo fora de
    // sincronia. Aqui cada entrada real passa pelos dois idiomas.
    for (final m in todas()) {
      if (!ehDeCatalogo(m)) continue;
      final a = LanguagePreference.descricao(
          en: m['descriptionEn'], pt: m['descriptionPt'], locale: en);
      final b = LanguagePreference.descricao(
          en: m['descriptionEn'], pt: m['descriptionPt'], locale: pt);
      expect(a.trim(), isNotEmpty, reason: '${m['name']} ficou vazia em EN');
      expect(b.trim(), isNotEmpty, reason: '${m['name']} ficou vazia em PT');
      expect(a, isNot(equals(b)),
          reason: '${m['name']} devolve a mesma ficha nos dois idiomas');
    }
  });

  test('as fichas de imagem dizem o que o modelo precisa, não só o nome', () {
    // As 5 de SD 1.5 carregam o projector no custo, e é o número que decide
    // se o card é filtrado. Uma ficha que omite isso deixa a pessoa descobrindo
    // o custo depois de baixar 2 GB.
    final sd =
        todas().where((m) => (m['filename'] ?? '').endsWith('.safetensors'));
    expect(sd.length, 5, reason: 'o catálogo tinha 5 modelos de imagem');
    for (final m in sd) {
      for (final idioma in const ['descriptionEn', 'descriptionPt']) {
        expect(m[idioma], isNotNull);
      }
    }
  });
}
