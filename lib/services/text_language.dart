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
    // ── função gramatical ──
    'the', 'and', 'with', 'for', 'from', 'your', 'this', 'that', 'these',
    'those', 'there', 'here', 'they', 'their', 'when', 'where', 'which',
    'while', 'would', 'should', 'could', 'must', 'only', 'also', 'very',
    'most', 'more', 'less', 'than', 'then', 'into', 'about', 'after',
    'before', 'without', 'within', 'across', 'every', 'each', 'never',
    'always', 'nothing', 'everything', 'already', 'instead', 'itself',
    'just', 'now', 'soon', 'ago', 'once', 'twice', 'half', 'whole',
    // ── substantivos e verbos que aparecem em texto de tela ──
    'model', 'models', 'download', 'downloaded', 'delete', 'cancel',
    'save', 'saved', 'load', 'loaded', 'search', 'choose', 'enable',
    'disable', 'failed', 'failure', 'warning', 'success', 'error',
    'screen', 'device', 'folder', 'file', 'files', 'server', 'port',
    'default', 'local', 'online', 'cloud', 'steps', 'step', 'plan',
    'template', 'backup', 'restore', 'config', 'configs', 'inspect',
    'test', 'quality', 'created', 'applied', 'uploaded', 'ready',
    'size', 'speed', 'memory', 'stopped', 'starting', 'running',
    'served', 'serves', 'occupied', 'optimized', 'helper', 'corrupt',
    'valid', 'built', 'updated', 'unknown', 'empty', 'full', 'busy',
    'done', 'stop', 'start', 'restart',
    // ── os 27 buracos que `tool/word_list_probe.dart` mediu ──
    //
    // **A lista é uma afirmação, e uma afirmação não se prova sozinha** — é o
    // mesmo modo de falha das sete omissões de escopo da trava, agora no
    // **conteúdo** em vez do alcance. As sete apareciam por causa externa (o
    // `dump` do aparelho, a lista de palavras alargada por outro motivo); esta
    // apareceu porque alguém leu os 212 achados e encontrou `'Show it anyway'`,
    // `'Benchmark usability'` e `'Verifying...'` **na lista de dívida e na
    // lista de buraco ao mesmo tempo**.
    //
    // **As duas direções da sondagem, e a que importa é a que falha.** Um texto
    // de tela que a lista **vê** é dívida conhecida. Um que ela **não vê** é
    // dívida invisível, e é a mesma forma dos 38 chaves que `.tr` devolvia pelo
    // próprio nome: nada lança, a contagem bate, e o defeito só aparece no
    // aparelho. `word_list_probe.dart` é a sonda, e ela julga a lista com
    // **texto de tela lido no fonte**, não com um resumo de memória.
    //
    // As 27 entradas vieram de uma passagem pelos achados existentes, e cada uma
    // está aqui porque **a retirada devolve um texto de tela ao silêncio**. A
    // ordem é por arquivo, e `back`/`next`/`open`/`close` estão aqui porque são
    // botão — e um botão que a trava não vê é um botão que nunca é traduzido.
    'show', 'hide', 'open', 'close', 'enter', 'clear', 'copy', 'paste',
    'read', 'write', 'send', 'format', 'keep', 'turn', 'next', 'back',
    'loading', 'available', 'verifying', 'benchmark', 'usability', 'anyway',
    'progress', 'projector', 'name', 'url',
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

  /// Junta os segmentos de um literal adjacente a partir de [ini], e devolve
  /// **onde parou**.
  ///
  /// **O Dart concatena literais vizinhos em tempo de compilação**, então o
  /// texto de tela ocupa de uma a cinco linhas e o valor real é a concatenação.
  /// Casar só o primeiro segmento produz metades de frase — `'know whether a
  /// local model is worth'`, `')}.\nThat is the intent, stated'` — e a lista de
  /// pendências enche de texto que **não é traduzível**, porque a frase não está
  /// ali. Foi o que aconteceu com a varredura ampla: ela casava cada segmento e
  /// reportava 263, dos quais boa parte eram fragmentos.
  ///
  /// O segundo valor é o que permite a guarda de `.tr`: sem ele, a única forma de
  /// saber onde a aspa de fechamento está é `ini + texto.length + 2`, e o `+2` é o
  /// tamanho das aspas — que muda quando o delimitador é duplo. Uma conta que só
  /// funciona em metade dos casos é a que some em silêncio na outra.
  ///
  /// **O escape é resolvido, não preservado.** `\n` gravado cru vira a letra `n`
  /// e o texto saía `"…tasks arenscheduled…"` — uma frase sem separador que passa
  /// em revisão de código e só aparece na tela.
  ///
  /// O delimitador pode mudar entre segmentos (`'a' "b"` é um valor só), e o
  /// escape é obrigatório: `'…da Microsoft's…'` fecha num `'` que não é o fim.
  ///
  /// **[inicios] recebe a posição de abertura de cada segmento, e é o que fecha
  /// a sobreposição.** Quem deduplica por posição precisa marcar os inicios
  /// **todos**: um literal adjacente de quatro linhas tem três inicios no meio,
  /// e o de cada um deles reconstrói a mesma frase **sem o primeiro segmento**.
  /// Sem isto a lista de pendências enche de `'know whether a local model is
  /// worth the download.'` — texto que não é traduzível, porque a frase está no
  /// segmento de cima e é ele que a tela mostra. Medido: **87 grupos com 155
  /// inicios extras** em `views`/`widgets`/`controllers`, e nenhum deles é uma
  /// dívida real.
  static (String, int) juntarSegmentos(String src, int ini,
      {List<int>? inicios}) {
    final n = src.length;
    var abre = ini;
    final partes = <String>[];
    while (true) {
      while (abre < n && ' \n\t'.contains(src[abre])) {
        abre++;
      }
      if (abre >= n || (src[abre] != "'" && src[abre] != '"')) return ('', ini);
      inicios?.add(abre);
      final delim = src[abre];
      var k = abre + 1;
      final sb = StringBuffer();
      var fechado = false;
      while (k < n) {
        final c = src[k];
        if (c == r'\' && k + 1 < n) {
          sb.write(_unescape(src[k + 1]));
          k += 2;
          continue;
        }
        if (c == delim) {
          k++;
          fechado = true;
          break;
        }
        sb.write(c);
        k++;
      }
      if (!fechado) return ('', ini);
      partes.add(sb.toString());
      var m = k;
      while (m < n && ' \n\t'.contains(src[m])) {
        m++;
      }
      if (m < n && (src[m] == "'" || src[m] == '"')) {
        abre = m;
        continue;
      }
      return (partes.join(), m);
    }
  }

  /// Interpreta o caractere depois da barra.
  ///
  /// O nome é o mesmo da ferramenta de reescrita de propósito: são a mesma
  /// regra, e mudar um dos dois deixa as contagens divergindo sem ninguém avisar.
  static String _unescape(String c) => c == 'n' ? '\n' : (c == 't' ? '\t' : c);

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
    'loaded': 'estado de API, dentro de exemplo de shell',
    'Load': 'verbo de um exemplo de shell, não o botão da tela',
    'List models': 'chave de um exemplo JSON, não o rótulo da tela',
    'how much storage does the map cache use':
        'consulta de um exemplo JSON; é o que o modelo recebe',
    'with the model': 'cauda de um exemplo de download, não rótulo',
    // ── os 11 achados em `lib/controllers` que NÃO são texto de tela ──
    //
    // Os quatro primeiros são **os que machucam se alguém traduzir**, porque
    // traduzir não põe um texto errado na tela: quebra a comparação que os
    // impedia de aparecer errado.
    'system': 'role do contrato OpenAI; o servidor recusa se vier traduzido',
    'light': 'valor de tema salvo no Hive, comparado num switch',
    'dark': 'valor de tema salvo no Hive, comparado num switch',
    'model.gguf': 'nome de arquivo padrão quando a URI não tem segmento',
    'Backup: folder picker threw': 'texto de log.error(), vai para o arquivo',
    'failed to load gguf split': 'substring procurada com lower.contains() '
        'dentro da mensagem de erro do engine',
    'failed to load model from buffer': 'substring procurada com '
        'lower.contains() dentro da mensagem de erro do engine',
    'out of memory': 'substring procurada com lower.contains() dentro da '
        'mensagem de erro do engine',
    'corrupt': 'substring procurada com lower.contains() dentro da mensagem '
        'de erro do arquivo; o que a pessoa lê é a frase traduzida acima dela',
    'Custom GGUF Models': 'chave de expandedSections, persistida no Hive; o '
        'rótulo vem de labelKey e é traduzido',
    'Custom LiteRT Models': 'chave de expandedSections, persistida no Hive; o '
        'rótulo vem de labelKey e é traduzido',
    'Custom TFLite Models': 'chave de expandedSections, persistida no Hive; o '
        'rótulo vem de labelKey e é traduzido',
    // ── os que a varredura achou depois que a regex parou de casar `n` ──
    'done': 'estado de tarefa, comparado com == num switch e numa condição',
    'download': 'procurado com contains() no id do modelo; é o verbo do campo, '
        'não o botão',
    'mobilelm-config.json': 'nome do arquivo de configuração gravado em SAF',
    'mobilelm-config': 'nome do arquivo de configuração, sem a extensão',
    // ── os que a lista de palavras alargada trouxe ──
    //
    // **Nenhum destes é botão, rótulo nem mensagem.** São chave de mapa,
    // valor de sentinela, nome de pasta e substring comparada. A lista de
    // palavras cresceu 27 entradas e subiu o texto de tela de 212 para 252 — e
    // parte desse acréscimo é dívida de verdade e parte é dado que passou a ter
    // palavra de inglês dentro. Separar os dois é o que a lista faz, e é por
    // isso que cada linha abaixo carrega o motivo.
    //
    // **Uma entrada que também é texto pintado é um buraco silencioso.**
    // `'running'` é o status de um passo de tarefa, comparado com `==` em quatro
    // lugares — e é **também** o rótulo do botão dos dois consoles enquanto o
    // pedido está em curso. Uma entrada no mapa apagaria os dois de uma vez, e o
    // botão ficaria em inglês para sempre sem nada reclamar. A ordem importa:
    // traduzir o rótulo primeiro, e só depois declarar a comparação como dado.
    'name': 'chave de mapa no perfil de cloud salvo em Hive',
    'url': 'chave do payload passado ao plugin de download',
    'unknown': 'sentinela de imageGpuVendor, comparada com == num ternário',
    'once': 'valor de frequência salvo em Hive e comparado com == no subtítulo',
    'downloaded': 'chave do balde de seções do catálogo, comparada por índice',
    'Downloaded': 'title de ModelSection, persistida no Hive como chave de '
        'expandedSections; o rótulo vem de mv_section_downloaded',
    'settings/mobilelm-config.json': 'caminho do arquivo de configuração, '
        'gravado em SAF',
    'new-folder': 'heroTag do FloatingActionButton, identificador do widget',
    'new-file': 'heroTag do FloatingActionButton, identificador do widget',
    'Unknown': 'segmento de caminho usado como nome de pasta no backup '
        '(classifyModelPath monta Vendor/Family)',
    'text-only': 'substring do erro do engine procurada com contains(); '
        'traduzi-la faz a detecção de fallback parar de casar',
    'unknown model architecture': 'substring do erro do engine procurada com '
        'contains() dentro de _getFriendlyErrorMessage',
    'unsupported model architecture': 'substring do erro do engine procurada '
        'com contains() dentro de _getFriendlyErrorMessage',
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
  ///
  /// **As interpolações são removidas antes de julgar, e essa é a nona
  /// omissão.** `DateTime.now()` está dentro de `${…}`, `now` é palavra da
  /// lista, e o literal `'mobilelm_${DateTime.now()…}.png'` — o nome do arquivo
  /// temporário do compartilhamento de imagem — entrava como texto de tela em
  /// inglês. Não é texto: é **código dentro de uma interpolação**, e o nome do
  /// arquivo é o mesmo nos dois idiomas.
  ///
  /// A omissão é do mesmo tipo das outras oito — a lista do que a trava mede
  /// estava incompleta — mas aqui a lista que estava incompleta era a de
  /// **conteúdo**, e o sintoma é o inverso: o teto **sobe** com falso positivo,
  /// que é mais difícil de ver do que um número baixo. Remover as interpolações
  /// é a mesma regra que a trava dos interpolados já usava
  /// ([tirarInterpolacoes]): o idioma é do **trecho fixo**, e o trecho fixo é
  /// o que vai para o mapa de tradução.
  static bool pareceInglesAmplo(String texto) {
    var probe = tirarInterpolacoes(texto).toLowerCase();
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
    if (eCampoDeIdioma(src, ini)) return false;
    if (dentroDeLog(src, ini)) return false;
    // **Caminho de import.** `../models/task_model.dart` é o que o compilador
    // lê, e traduzi-lo não muda a tela: muda o que o Dart resolve. A marca é o
    // `../` inicial, que nenhum literal de tela começa.
    if (RegExp(r'^\.\.?/').hasMatch(texto.trim())) return false;
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

  /// O literal é o valor de um **campo que já é uma tradução**?
  ///
  /// `AiModel` tem `descriptionEn` e `descriptionPt`, e o literal em
  /// `descriptionEn` **é o valor em inglês por projeto** — é o campo que o app
  /// mostra quando o idioma é inglês. Traduzi-lo não deixa um texto errado na
  /// tela: deixa os dois idiomas com a mesma frase, e a guarda que pega valor
  /// português no mapa inglês passa a acusar o ficheiro de catálogo.
  ///
  /// A marca é o nome do campo, e **pode estar uma linha acima**: o
  /// `dart format` quebra a atribuição entre a condição e o literal, e a forma
  /// que sobra no catálogo é
  ///
  /// ```dart
  /// descriptionEn: description == null || description.trim().isEmpty
  ///     ? 'Added from custom URL'
  ///     : description.trim(),
  /// ```
  ///
  /// Ler só a linha do literal dá `false` e o texto entra na contagem — que é o
  /// que aconteceu na primeira passada: 38 em vez de 37, com `'Added from custom
  /// URL'` do lado de `'Imported from local storage'`, que está na mesma linha do
  /// campo e era pegado. **Dois lugares, a mesma frase, regras diferentes**,
  /// porque o formatador quebrou um e não o outro.
  ///
  /// A versão com aritmética de índice (`lastIndexOf` e `substring`) não
  /// funcionava e foi trocada por linhas: `lastIndexOf` **inclui o próprio
  /// índice**, então `ini2 - 1` é a quebra que *termina* a linha anterior e o
  /// trecho saía **vazio** — a condição nunca era satisfeita e o caso do ternário
  /// continuava entrando. Com índice negativo, `lastIndexOf` devolve `-1`
  /// deslocado e o `substring` lançava `RangeError`.
  static bool eCampoDeIdioma(String src, int ini) {
    final campo = RegExp(r'^\s*(descriptionEn|descriptionPt)\s*:');
    final linhas = src.substring(0, ini).split('\n');
    // `linhas.last` é o pedaço da linha do literal **até a aspa**, que é
    // suficiente: o nome do campo vem antes dela.
    if (campo.hasMatch(linhas.last)) return true;
    // **Só sobe se a linha acima for a condição de um ternário.** Subir sempre
    // pegaria o campo de outro literal — `label:` uma linha acima é comum e não
    // é campo de idioma.
    if (linhas.length < 2) return false;
    final acima = linhas[linhas.length - 2];
    if (campo.hasMatch(acima)) return true;
    return RegExp(r'^\s*\?\s').hasMatch(acima);
  }

  /// O literal é a **mensagem de um log**, e não texto de tela?
  ///
  /// `log.error('Restore failed', details: e)` e
  /// `Get.snackbar('Restore failed', e)` aparecem **na mesma tela, com a mesma
  /// frase**, e a diferença é só quem recebe. O log vai para o arquivo que a
  /// pessoa abre e lê para diagnosticar; traduzi-lo deixaria o arquivo em
  /// português enquanto o resto do log está em inglês, e a busca por
  /// `Restore failed` no arquivo — que é como se acha um erro — deixaria de
  /// achar.
  ///
  /// A marca é o **nome do método** logo antes do parêntese, e não o do receiver:
  /// `log.error`, `log.info`, `log.warning`, `log.debug` e
  /// `AppLogService().error/warning/info`. `Get.snackbar` não é log, e é
  /// justamente o par que a regra precisa separar.
  static bool dentroDeLog(String src, int ini) {
    final antes = src.substring(0, ini);
    final abre = antes.lastIndexOf('(');
    if (abre < 0) return false;
    // O primeiro argumento é o que o método recebe logo depois do parêntese.
    final entreParentes = antes.substring(abre + 1);
    if (entreParentes.trimLeft().length != entreParentes.length) {
      // Há um argumento antes deste, então não é o primeiro.
      final virgula = entreParentes.indexOf(',');
      final fechaAntes = entreParentes.lastIndexOf(')');
      if (virgula >= 0 && (fechaAntes < 0 || virgula < fechaAntes))
        return false;
    }
    final antesDoParen = antes.substring(0, abre);
    return RegExp(r'\.(error|warning|info|debug)\s*$').hasMatch(antesDoParen);
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
