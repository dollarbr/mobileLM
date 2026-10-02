/// Detecta se um literal de tela está escrito em inglês.
///
/// Vive num módulo **puro e compartilhado** porque dois consumidores precisam
/// da mesma lista: a ferramenta que reescreve os literais
/// (`tool/inline_english_scan.dart`) e a trava que conta
/// (`test/inline_english_ratchet_test.dart`). Duas listas em dois arquivos
/// divergem em silêncio — foi o que a auditoria de overflow, a de overflow de
/// linha e a de descrição de catálogo fizeram neste repo, cada uma com a mesma
/// causa: dois detectores que discordam e nenhum que reclame.
///
/// **A lista é de inglês e a pergunta é "esta frase tem palavra de inglês que não
/// é nome de modelo nem exemplo de API".** A alternativa — listar o que *não*
/// pode aparecer e acusar o que sobrar — só funciona se o resto da lista for o
/// universo, e o resto é outro idioma. Foi assim que um detector de catálogo
/// reprovou texto português correto.
///
/// Não é tradutor. Não traduz, não corrige, não decide o que é melhor: só
/// responde "isto parece inglês", e quem chama decide o que fazer com a
/// resposta.
class TextLanguage {
  const TextLanguage._();

  /// Palavras que marcam um literal de tela em inglês.
  static const englishWords = <String>{
    'the',
    'and',
    'with',
    'for',
    'from',
    'your',
    'this',
    'that',
    'these',
    'those',
    'there',
    'here',
    'they',
    'their',
    'when',
    'where',
    'which',
    'while',
    'would',
    'should',
    'could',
    'must',
    'only',
    'also',
    'very',
    'most',
    'more',
    'less',
    'than',
    'then',
    'into',
    'about',
    'after',
    'before',
    'without',
    'within',
    'across',
    'every',
    'each',
    'never',
    'always',
    'nothing',
    'everything',
    'someone',
    'anywhere',
    'ready',
    'settings',
    'model',
    'models',
    'download',
    'delete',
    'cancel',
    'save',
    'saved',
    'load',
    'loaded',
    'search',
    'choose',
    'pick',
    'enable',
    'disable',
    'failed',
    'waiting',
    'warning',
    'success',
    'error',
    'screen',
    'button',
    'tap',
    'device',
    'folder',
    'file',
    'files',
    'server',
    'network',
    'port',
    'default',
    'appearance',
    'inference',
    'storage',
    'agent',
    'diagnostics',
    'light',
    'dark',
    'system',
    'local',
    'cloud',
    'steps',
    'step',
    'plan',
    'template',
    'backup',
    'inspect',
    'test',
    'key',
    'size',
    'speed',
    'time',
    'memory',
    'quality',
    'created',
    'applied',
    'keeps',
    'turns',
    'carries',
    'declared',
    'scaled',
    'produces',
    'fit',
    'fits',
    'reads',
    'writing',
    'reasons',
    'rules',
    'no',
    'not',
  };

  /// Nomes próprios, formatos e exemplos de API: não são idioma.
  ///
  /// **Cada termo tem que ser algo que nunca é português nem aparece em frase de
  /// tela.** Um termo colocado aqui por engano — `model`, `light`, `about` —
  /// apaga dezenas de linhas do contador de uma vez, e a trava passa sem que
  /// ninguém tenha traduzido nada. `test/inline_english_ratchet_test.dart` tem
  /// um teste que recusa os que são palavra de interface.
  static const notText = <String>{
    'gguf',
    'litert',
    'safetensors',
    'tflite',
    'litertlm',
    'openai',
    'huggingface',
    'qat',
    'qad',
    'qaft',
    'q4_0',
    'q4_k_m',
    'bf16',
    'fp16',
    'int8',
    'npu',
    'gpu',
    'cpu',
    'nvidia',
    'openrouter',
    'base_url',
    'chat/completions',
    'rerank',
    'embed',
    'embeddings',
    'device_local',
  };

  /// O texto que sobra depois de tirar as interpolações: `${…}` e `$ident`.
  ///
  /// Existe porque **`looksEnglish` devolve falso para qualquer `$`, por
  /// construção** — e a trava dos literais interpolados precisa exatamente do
  /// contrário: o idioma é do **trecho fixo**, e é o trecho fixo que vai para o
  /// mapa. Passar o literal inteiro dava zero sempre, e a trava passava com a
  /// tela em inglês.
  ///
  /// O resultado pode ter espaço duplo onde a interpolação estava, e isso não
  /// importa: `looksEnglish` casa por palavra, e o texto só volta a aparecer na
  /// tela já traduzido.
  static String tirarInterpolacoes(String texto) => texto
      .replaceAll(RegExp(r'\$\{[^}]*\}'), ' ')
      .replaceAll(RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*'), ' ');

  // ─────────────────────────── varredura AMPLA ───────────────────────────
  //
  // A lista de call sites (`Text`, `title:`, `subtitle:`) é **estreita de
  // propósito**: é o conjunto que a máquina pode reescrever. A varredura ampla
  // olha todo literal, e por isso precisa dizer o que **não** é texto de tela —
  // e essa lista mora aqui, e não na ferramenta, porque a trava do CI precisa
  // da mesma resposta.

  /// Literal que NÃO é texto de tela, com o motivo.
  ///
  /// **Cada entrada tem que dizer por quê**, e é o que a torna auditável. Uma
  /// lista de exclusão sem motivo é uma lista para ninguém conferir, e o efeito
  /// é o oposto do pretendido: o próximo traduz `'local'` e o app começa a
  /// comparar runtime por texto traduzido, sem erro nenhum.
  static const naoTexto = <String, String>{
    'local': 'identificador de runtime, comparado com ==',
    'cloud': 'identificador de runtime, comparado com ==',
    'online': 'identificador de origem, comparado com ==',
    'ERROR': 'nível de log, filtrado por texto',
    'WARNING': 'nível de log, filtrado por texto',
    'failed': 'estado de tarefa, comparado por texto',
    'models/': 'fragmento de caminho de arquivo, não texto de tela',
    'screen': 'verbo de ação dentro de uma instrução',
    'load': 'verbo de rota, dentro de texto de instrução',
    'delete': 'verbo de rota, dentro de texto de instrução',
    'file': 'rótulo de tipo, dentro de texto de instrução',
    'default': 'rótulo de papel, dentro de texto de instrução',
    'every': 'comparado com startsWith() numa frequência salva',
    'model': 'nome de campo dentro de exemplo curl/Python',
    'step': 'plural interpolado, tratado por chave',
    'steps': 'plural interpolado, tratado por chave',
    'loaded': 'estado de API, dentro de exemplo de shell',
    'Load': 'verbo de um exemplo de shell, não o botão da tela',
    'List models': 'chave de um exemplo JSON, não o rótulo da tela',
    'how much storage does the map cache use':
        'consulta de um exemplo JSON; é o que o modelo recebe',
    'with the model': 'cauda de um exemplo de download, não rótulo',
  };

  /// `texto` tem palavra de inglês **sem** a regra do `$`, para a varredura ampla.
  ///
  /// **É a mesma lista de palavras de `looksEnglish`, com as mesmas exclusões.**
  /// A ferramenta de linha de comando tinha a sua, e as duas contaram coisas
  /// diferentes: a ferramenta via `Text('READY')` e a trava não; a trava via
  /// `'No project'` e a ferramenta não. Duas listas de palavras em dois lugares
  /// é o modo de falha que já atingiu a auditoria de overflow, a de overflow de
  /// linha e a de descrição de catálogo neste repo, e a razão de esta estar aqui
  /// e não em dois arquivos.
  static bool pareceInglesAmplo(String texto) {
    var probe = texto.toLowerCase();
    for (final t in notText) {
      probe = probe.replaceAll(t, ' ');
    }
    return englishWords
        .any((w) => probe.contains(RegExp('\\b${RegExp.escape(w)}\\b')));
  }

  /// O literal em [ini] do fonte [src] é **texto de tela**?
  ///
  /// Cinco exclusões, e cada uma tem uma forma de detecção diferente — nenhuma
  /// delas é "a lista de exclusão":
  ///
  /// 1. valor de [naoTexto];
  /// 2. **dentro de um comentário** (`//` ou `///`) — uma frase em inglês
  ///    explicando o código é comentário;
  /// 3. **dentro de um exemplo de comando** — `curl `, `client =`, `#`;
  /// 4. **dentro de um caso de teste do encoder** — `query:` e `documents:` são o
  ///    que o modelo recebe, e um caso traduzido mede outra coisa;
  /// 5. **a própria linha de um exemplo de shell** — `'# 202, then poll …'`.
  ///    A detecção por linha não pega, porque o `#` está dentro da string.
  ///
  /// E o que fica de fora disto é o `.tr` já aplicado e a **chave de payload**
  /// (`json['loaded']`), que a varredura nem chega a ver porque não éfollowed
  /// de nada.
  static bool eTextoDeTela(String texto, String src, int ini) {
    if (naoTexto.containsKey(texto.trim())) return false;
    // **Uma quebra de linha seguida de espaço é código, não literal.** O
    // regex casa `[^'\n]` então nunca atravessa uma quebra de verdade — o `\n`
    // que aparece no texto é o **escape**, e um literal real deste repo só o
    // usa no fim (`'…loaded.\n'`). Com espaço depois é o intervalo entre dois
    // trechos de código: `'x'.split('\n').map((e) => ...'` casa
    // `).first;\n            model =` como se fosse literal, e era o que
    // inflava a contagem com dez entradas de código.
    if (RegExp(r'\n\s').hasMatch(texto)) return false;
    // **Rota de API, exemplo de JSON e fragmento de código.** Três formas, e
    // todas começam com um caractere que nenhum literal de tela começa: `/`
    // (caminho), `$` ou `{` (interpolação solta ou objeto), `: ` (cauda de
    // expressão). Um literal de tela é palavra e aspas, ou ponto de interrogação.
    if (RegExp(r'^(/|\$|\{|: )').hasMatch(texto.trim())) return false;
    if (texto.contains('/v1/')) return false;
    if (_dentroDeDoc(src, ini)) return false;
    if (_dentroDeCodigo(src, ini)) return false;
    if (_casoDeTeste(src, ini)) return false;
    if (_linhaDeExemplo(texto)) return false;
    return true;
  }

  static bool _dentroDeDoc(String src, int ini) {
    final linha = src.lastIndexOf('\n', ini - 1) + 1;
    return src.substring(linha, ini).trimLeft().startsWith('//');
  }

  static bool _dentroDeCodigo(String src, int ini) {
    final linha = src.substring(src.lastIndexOf('\n', ini - 1) + 1, ini);
    final t = linha.trimLeft();
    return t.startsWith('curl ') ||
        t.startsWith('client =') ||
        t.startsWith('#') ||
        t.startsWith('from openai') ||
        t.startsWith('print(') ||
        t.startsWith('-H ') ||
        t.startsWith('-d ');
  }

  static bool _casoDeTeste(String src, int ini) {
    final antes = src.substring(0, ini);
    for (final campo in const ['query:', 'documents:']) {
      final at = antes.lastIndexOf(campo);
      if (at < 0) continue;
      if (at > antes.lastIndexOf('label:') && ini - at < 1200) return true;
    }
    return false;
  }

  static bool _linhaDeExemplo(String texto) =>
      texto.trimLeft().startsWith('#') ||
      texto.contains(r'\n#') ||
      texto.contains(r'\n  -d ') ||
      texto.contains(r'\n    ') ||
      texto.contains('curl ');

  /// `texto` parece um literal de tela em inglês?
  ///
  /// **A interpolação exclui.** `'$_loadError'` produz um texto de runtime que
  /// não é o do fonte, e trocar o literal inteiro por uma chave apagaria a parte
  /// dinâmica — o que a pessoa lê ficaria sem o erro que ela precisava ver.
  static bool looksEnglish(String texto) {
    if (texto.contains(r'$')) return false;
    return looksEnglishSemDollar(texto);
  }

  /// O mesmo teste **sem** a regra do `$`.
  ///
  /// Existe para a varredura ampla, que por construção só vê literais
  /// interpolados: `looksEnglish` devolve falso para qualquer `$`, e a trava do
  /// amplo precisa justamente do contrário. A regra do `$` fica em
  /// `looksEnglish` porque é ela que protege a reescrita — um literal com `$` tem
  /// o valor em runtime diferente do valor no fonte.
  static bool looksEnglishSemDollar(String texto) {
    var probe = texto.toLowerCase();
    for (final t in notText) {
      probe = probe.replaceAll(t, ' ');
    }
    return englishWords
        .any((w) => probe.contains(RegExp('\\b${RegExp.escape(w)}\\b')));
  }
}
