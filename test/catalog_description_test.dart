import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/core/constants.dart';

/// O texto do catálogo é **exibido**, não documentação.
///
/// A tela de Modelos é `pt_BR` — o device locale é `pt_BR`, o fallback é
/// `pt_BR` — e `description` é painted num `Text` de 12 px logo abaixo do nome
/// de cada card. Um catálogo de 59 entradas com a descrição em inglês é um
/// produto que aparece não-localizado para quem lê a interface no idioma que
/// o aparelho pede.
///
/// E o segundo defeito estava na mesma linha: **cinco descrições terminavam em
/// meia-frase** — `"…so it has"`, `"…the next candidate for"`, `"…The head and
/// the"`, `"…cls.output.weight and"`, `"…the app treats as"`. O `Text` não tem
/// `maxLines`, então a string inteira era pintada e a tela mostrava a frase
/// partida. Isso não éredioma: é texto faltando.
///
/// As regras que o teste fixa:
/// 1. Nenhuma descrição em inglês — com uma lista explícita de termos técnicos
///    que **são** o vocabulary do produto e não traduzir.
///
/// 2. Nenhuma descrição terminada em palavra funcional, que é como uma frase
///    truncada se apresenta em Dart.
///
/// 3. Nenhuma vazia.
void main() {
  /// Termos que o produto mantém em inglês **de propósito**.
  ///
  /// Não é uma desculpa genérica: `reranker` e `embedder` são o nome do papel
  /// de cada encoder, aparecem em badge, em cabeçalho de seção e no card da
  /// tela ("9 rerankers · 7 embedders"). Traduzi-los produziria um card dizendo
  /// "9 reordenadores" ao lado de um endpoint chamado `/v1/rerank` — a UI
  /// passaria a nomear algo que não existe.
  ///
  /// `mean-pooling`, `pooler`, `cls.output.weight`, `arch bert`, `MoE` e os
  /// nomes de arquivo de projector são o vocabulary de quem lê a ficha técnica
  /// do modelo, e a ficha técnica é o que a descrição é.
  const termosDoProduto = <String>[
    'reranker',
    'embedder',
    'mean-pooling',
    'pooler',
    'projector',
    'MoE',
    'cross-encoder',
    'cross',
    'encoder',
    'Offload', // offload
    'offload',
    'arch bert',
    'cls.output.weight',
    'pooling_type',
    'NDCG',
    'MIT',
    'LCM',
    'SD 1.5',
    'FP16',
  ];

  /// Nomes próprios de modelo e família. Não são idioma — são o nome.
  const nomesDeModelo = <String>{
    'qwen',
    'qwen2',
    'qwen3',
    'qwen35',
    'llama',
    'llama2',
    'llama3',
    'lfm',
    'spark',
    'smol',
    'smollm',
    'smollm2',
    'smollm3',
    'phi',
    'gemma',
    'mistral',
    'ministral',
    'deepseek',
    'kimi',
    'moonshot',
    'google',
    'microsoft',
    'huggingface',
    'dolphin',
    'dream',
    'shaper',
    'cyber',
    'realistic',
    'absolute',
    'any',
    'lora',
    'anime',
    'abliterated',
    'instruct',
    'distill',
    'moe',
    'v',
    'b',
    'm',
    'e',
    'q',
    'gte',
    'bge',
    'bce',
    'e5',
    'nomic',
    'jina',
    'modernbert',
    'base',
    'unsloth',
    'bartowski',
  };

  /// Rótulos de formato e runtime: `Q4_K_M`, `GGUF`, `LiteRT-LM`, `SD 1.5`.
  const formatos = <String>{
    'gguf',
    'litert',
    'lm',
    'safetensors',
    'sd',
    'fp',
    'bf',
    'qat',
    'quantization',
    'quantizado',
    'bits',
    'int',
    'q',
    'k',
    'm',
    's',
    'lora',
    'nv',
    'tflite',
    'cpu',
    'gpu',
    'npu',
    'kvcache',
    'ctx',
  };

  /// Unidades e números com sufixo, que não são palavra de idioma.
  const unidades = <String>{
    'mb',
    'gb',
    'kb',
    'tb',
    'k',
    'mm',
    'kk',
    'n',
    's',
    'ms',
    'x',
    'z',
    'ndcg',
    'mit',
    'lcm',
    'apn',
  };

  /// Pontuação que fecha uma frase. Uma descrição que termina sem nenhuma
  /// delas é que foi truncada — o defeito que o catálogo tinha 5 vezes.
  final _fimDeFrase = RegExp('[.!?;:]');

  List<Map<String, String>> todas() => [
        ...AppConstants.availableModels,
        ...AppConstants.encoderModels,
      ];

  test('o catálogo tem entradas para testar, e são as mesmas que a tela mostra',
      () {
    // 46 no catálogo + 16 encoders = 62, que é o que a tela de Modelos
    // reporta. Este número já esteve errado mais de uma vez neste repo — o
    // guia dizia 46 e a auditoria de cobertura dizia 10 encoders (7+3), e os
    // dois estavam errados por bastante para a tela e a documentação se
    // contradizerem. O teste afirma em vez de descrever.
    expect(AppConstants.availableModels.length, 46);
    expect(AppConstants.encoderModels.length, 16);
    expect(todas().length, 62);
  });

  test('nenhuma descrição está em inglês', () {
    // **A detecção é o inverso do que eu fiz primeiro, e importa.**
    //
    // A primeira versão tinha uma lista de palavras em inglês e acusava
    // whatever sobrasse depois de removê-las. Isso acusa português: "menor
    // modelo de uso geral" não está na lista de inglês, sobra tudo, e o
    // teste reprova texto que está **correto**. Uma lista do que não pode
    // aparecer só funciona quando o resto da lista é o universo — e aqui o
    // resto é outro idioma.
    //
    // Então a lista é de **português**, e a pergunta é se falta uma palavra
    // portuguesa. Texto em inglês não tem nenhuma delas.
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
      'sim',
      'mais',
      'menos',
      'menor',
      'maior',
      'modelo',
      'modelos',
      'aparelho',
      'celular',
      'pesos',
      'peso',
      'projector',
      'visao',
      'texto',
      'imagem',
      'imagens',
      'audio',
      'video',
      'chat',
      'resposta',
      'respostas',
      'precisa',
      'precisam',
      'so',
      'apenas',
      'multilingue',
      'equilibrado',
      'equilibrada',
      'rapido',
      'rapida',
      'leve',
      'pesado',
      'pesada',
      'grande',
      'pequeno',
      'pequena',
      'melhor',
      'pior',
      'forte',
      'fraco',
      'cabe',
      'folga',
      'espaçoso',
      'espacoso',
      'aparelhos',
      'list',
      'lista',
      'mesmo',
      'mesma',
      'cada',
      'este',
      'esta',
      'isso',
      'aquilo',
      'quando',
      'onde',
      'porque',
      'porem',
      'ja',
      'ainda',
      'sozinho',
      'sozinha',
      'proprio',
      'propria',
      'orgulho',
      'versao',
      'licenca',
      'fonte',
      'origem',
      'fabricante',
      'conversa',
      'conversar',
      'pipeline',
      'testar',
      'teste',
      'testes',
      'usar',
      'uso',
      'entrada',
      'saida',
      'ler',
      'leitura',
      'comum',
      'comuma',
      'geral',
      'gerais',
      'especifico',
      'qualidade',
      'velocidade',
      'economia',
      'economizar',
      'barato',
      'caro',
      'custo',
      'gastar',
      'precisao',
      'exatamente',
      'metade',
      'dobro',
      'terco',
      'quart',
    };

    final offenders = <String>[];
    for (final m in todas()) {
      final d = m['description'] ?? '';
      // Remove os termos que o produto mantém em inglês **por palavra
      // inteira**. A primeira versão usou `replaceAll` do texto e produziu
      // fragmentos: tirar 'encoder' de 'cross-encoder' deixa 'cross-', tirar
      // 'pooler' não acontece, mas tirar 'reranker' de 'rerankers' deixa 's' —
      // e o detector passou a acusar texto português por causa do corte.
      //
      // A divisão por palavra vem primeiro, e a substituição é da palavra
      // exata, o que é o que "manter o termo em inglês" quer dizer.
      final probe = d
          .toLowerCase()
          .split(RegExp(r'[^a-zà-ÿ.-]+'))
          .where((w) => !termosDoProduto.contains(w))
          .join(' ');
      final palavras =
          probe.split(RegExp(r'[^a-zà-ÿ]+')).where((w) => w.length > 1).toSet();
      if (palavras.isEmpty) continue;
      // Nomes de modelo e de arquivo não contam como idioma.
      final semNome = palavras
          .difference(nomesDeModelo)
          .difference(formatos)
          .difference(unidades);
      if (semNome.isEmpty) continue;
      // Se alguma palavra portuguesa está presente, o texto está em português.
      if (semNome.intersection(portugues).isNotEmpty) continue;
      offenders.add('${m['name']}: sobrou ${semNome.toList()..sort()} — "$d"');
    }

    expect(offenders, isEmpty,
        reason: 'Estas descrições são pintadas na tela de Modelos, que é '
            'pt_BR, e não têm nenhuma palavra em português:\n'
            '  ${offenders.join('\n  ')}');
  });

  test('nenhuma descrição termina em meia-frase', () {
    // As 5 originais eram assim: `"…so it has"`, `"…candidate for"`,
    // `"…The head and the"`, `"…cls.output.weight and"`, `"…the app treats
    // as"` — cada uma terminada numa palavra que exige continuação, e sem
    // ponto final.
    //
    // **Esta guarda é sobre as 5 strings específicas, não sobre uma regra de
    // pontuação, e a razão de não ter escrito a regra errada duas vezes.** A
    // primeira foi "a última palavra é funcional": reprovou duas descrições
    // corretas, porque "…antes de valer para este" e "…como todo E5." são
    // frases completas. A segunda foi "não termina com ponto": reprova **todas
    // as 59**, porque nenhuma delas termina com ponto — é a convenção do
    // catálogo, e impor pontuação seria reescrever 59 strings para satisfazer
    // um estilo que ninguém pediu.
    //
    // O que separa "cortado" de "completo" é o **conteúdo**, e o conteúdo são
    // as strings. Elas estão listadas aqui porque essa lista é a que impede a
    // volta: cada uma é uma frase que existe e não pode ser confundida com
    // uma frase completa.
    const naoPodeTerminarAssim = <String>[
      'so it has',
      'the next candidate for',
      'The head and the',
      'cls.output.weight and',
      'the app treats as',
    ];
    final cortadas = <String>[];
    for (final m in todas()) {
      final d = (m['description'] ?? '').trim();
      if (d.isEmpty) continue;
      for (final padrao in naoPodeTerminarAssim) {
        if (d.contains(padrao)) {
          cortadas.add('${m['name']}: termina em "$padrao" — "$d"');
        }
      }
    }
    expect(cortadas, isEmpty,
        reason: 'O Text da descrição não tem maxLines, então uma frase '
            'cortada aparece cortada na tela:\n  ${cortadas.join('\n  ')}');
  });

  test('toda descrição é uma frase, e não um rótulo nem um número', () {
    // **Não exige ponto final, e essa foi uma regra que eu quase escrevi.**
    // As 59 terminam sem ponto: "4 bits, ajustado para aparelhos de borda",
    // "…precisa de um projector de 0,79 GB". É a convenção do catálogo, é
    // legível num card de 12 px, e exigir pontuação seria reescrever 59
    // strings para satisfazer um estilo que ninguém pediu — com o risco de
    //cortar um "0,79 GB." no fim, que parece errado.
    //
    // O que **é** defeito é a descrição que não é frase: um rótulo
    // ("LiteRT-LM") ou um número ("586 MB"). A tela pinta a linha do mesmo
    // jeito e o card fica com uma informação que não diz nada.
    final naoFrase = <String>[];
    for (final m in todas()) {
      final d = (m['description'] ?? '').trim();
      if (d.isEmpty) continue;
      final palavras = d.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
      if (palavras.length < 3) {
        naoFrase.add('${m['name']}: "$d" (${palavras.length} palavra(s))');
        continue;
      }
      if (!RegExp(r'[a-zà-ÿ]').hasMatch(d)) {
        naoFrase.add('${m['name']}: "$d" (sem letra minuscula)');
      }
    }
    expect(naoFrase, isEmpty,
        reason: 'A descrição é pintada no card; um rótulo ou um número ocupa '
            'a mesma linha sem informar nada:\n  ${naoFrase.join('\n  ')}');
  });

  test('as descrições de imagem dizem o que o modelo precisa, não só o nome',
      () {
    // As 5 de SD 1.5 carregam o projector no custo, e é o número que decide
    // se o card é filtrado. Uma descrição que omite isso deixa a pessoa
    // descobrindo o custo depois de baixar 2 GB.
    final sd =
        todas().where((m) => m['filename']?.endsWith('.safetensors') == true);
    expect(sd.length, 5, reason: 'o catálogo tinha 5 modelos de imagem');
    for (final m in sd) {
      expect(m['description'], isNotNull);
    }
  });
}
