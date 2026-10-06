import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/services/text_language.dart';

/// Quantos textos de tela ainda são literais em inglês dentro do código.
///
/// **Este arquivo é uma trava, não uma lista de defeitos.** Ele não afirma que
/// um texto específico está errado — afirma que o número **não cresce**. A
/// lista dos 47 que sobraram está escrita em `AGENTS.md`, com o arquivo e a
/// linha de cada um, e ela é dívida conhecida e medida.
///
/// ## Por que uma trava e não a tradução inteira
///
/// Os 47 que restam são parágrafos de ajuda em telas secundárias, e quase
/// todos são **literais adjacentes** — o Dart concatena os vizinhos em tempo de
/// compilação, então o texto ocupa três a cinco linhas e um `\n` no meio. É a
/// mesma forma que já custou três builds em `constants.dart` na mesma sessão, e
/// reescrever 47 delas com regex é o caminho que produz
/// `"…aparelhos compouca RAM"`: texto novo colado em cima do antigo, que parece
/// traduzido e não está.
///
/// Uma trava é mais útil aqui do que uma tradução apressada. O sintoma que o
/// dono do app descreveu — texto no idioma errado na tela — não era falta de
/// tradução: era um idioma que ninguém escolhia e literais que ninguém
/// localizava. Os dois foram fechados. O que sobra é texto de referência, e a
/// trava garante que ele não vira texto de interface sem ninguém perceber.
///
/// **A guarda que pega o crescimento é a segunda metade do arquivo**: ela
/// recusa literais novos com as palavras que aparecem nesta lista, e diz
/// exatamente onde.
/// Um literal da varredura **ampla**: onde está e se é texto de tela.
class _Achado {
  _Achado(this.onde, this.texto, this.eTexto);
  final String onde;
  final String texto;
  final bool eTexto;
}

/// Os literais da varredura ampla que são **texto de tela**.
///
/// **Mesma lista, mesma classificação, mesmo módulo.** `looksEnglish`,
/// `naoTexto` e as cinco regras de contexto estão em
/// `lib/services/text_language.dart`, que a ferramenta de linha de comando
/// também importa. Um detector em dois arquivos diverge em silêncio — foi o que a
/// auditoria de overflow, a de overflow de linha e a de descrição de catálogo
/// fizeram neste repo, cada uma com a mesma causa — e a divergência aqui seria
/// um teto que protege uma coisa e a ferramenta escreve outra.
///
/// **O que a varredura estreita não vê, e é o motivo de existir deste:** a
/// lista de call sites é o conjunto que a máquina pode reescrever, e `Size`,
/// `READY`, `DOWNLOADED` e o rótulo `Model` de um `InputDecoration` não estão
/// nela. O A72 mostrou `LOCAL MODELS (64)` e `Memory` em inglês com a trava em
/// zero.
List<_Achado> broad() {
  final out = <_Achado>[];
  // **Não é raw string, e a razão são as duas aspas.** `r'…'` fecha num `'`
  // interior e `r"…\"…"` fecha no `\"`, porque raw string não processa escape.
  // String normal resolve, com `\\` na frente de cada aspa e de cada `n`.
  // **A classe de caracteres estava errada, e era o bug maior de todos.**
  // `[\'\\n]` num literal não-raw vira `[\'\\n]` no regex, que exclui a **letra
  // `n`** — não a quebra de linha. Qualquer literal com `n` no meio nunca casava,
  // e `'Warning: values above 8192…'` tem um `n` em *Warning*. Não era um filtro
  // de idioma: era um filtro de letra, e pegava `'Anúncio'` em português e
  // `'Cancel'` em inglês pelo mesmo motivo.
  //
  // **A janela era de 90 e é de 240**, pelo mesmo motivo: literal longo é
  // exatamente prosa, que é o que fica em inglês numa tela traduzida.
  final re = RegExp("\\'([^\\'\\n]{2,240})\\'|\"([^\"\\n]{2,240})\"");
  for (final f in telas()) {
    final src = f.readAsStringSync();
    // `vistos` é **por arquivo**, e esse é o detalhe. Com um conjunto só para
    // tudo, um índice de fim de segmento em `model_controller.dart` suprime o
    // literal que começa na **mesma posição numérica** de `server_view.dart`:
    // os arquivos têm comprimentos diferentes e as posições não significam nada
    // entre eles. A contagem ficava 12 abaixo, e a ferramenta — que declara o
    // conjunto dentro de `_varre` — dizia 258. Um número menor não é um número
    // errado que se vê; é um que parece certo e protege menos do que parece.
    //
    // **`vistos` marca os inicios que `juntarSegmentos` consumiu, e não só o
    // primeiro e o fim.** Ver a nota do teto abaixo: marcar os dois extremos
    // deixava passar o início de cada segmento do meio, e cada um reportava a
    // mesma frase sem o primeiro segmento.
    final vistos = <int>{};
    for (final m in re.allMatches(src)) {
      if (!vistos.add(m.start)) continue;
      // **Os mesmos passos e a mesma função da ferramenta**, porque as duas têm
      // que contar a mesma coisa: enquanto a ferramenta juntava segmentos e o
      // teste não, os números divergiam sem nenhum dos dois reclamar.
      //
      // **`vistos` marca os inicios que `juntarSegmentos` consumiu, todos.**
      // Marcando só o primeiro e o fim, cada início do meio de um literal
      // adjacente reportava a mesma frase sem o primeiro segmento — e o teto
      // media dívida que não existe. Foi o que o `tool/dup_probe.dart` contou:
      // 87 grupos, 155 inicios extras.
      final inicios = <int>[];
      final (joined, fim) =
          TextLanguage.juntarSegmentos(src, m.start, inicios: inicios);
      if (joined.isEmpty) continue;
      vistos.addAll(inicios);
      vistos.add(fim);
      final texto = joined.trim();
      if (texto.length < 3) continue;
      if (!TextLanguage.pareceInglesAmplo(texto)) continue;
      // já é `.tr`? o que vem DEPOIS da aspa é o que decide.
      var k = m.end;
      while (k < src.length &&
          (src[k] == ' ' || src[k] == '\n' || src[k] == '\t')) {
        k++;
      }
      if (src.startsWith('.tr', k)) continue;
      // **Chave de payload da API não é texto.** `json['loaded']` e
      // `json['error']` são campos do que o servidor devolve; traduzi-los deixa
      // o painel vazio sem erro, porque o acesso devolve `null` e o `??` cobre.
      if (src.startsWith(']', k)) continue;
      if (!TextLanguage.eTextoDeTela(texto, src, m.start)) continue;
      out.add(_Achado(
          '${f.path}:${src.substring(0, m.start).split('\n').length}',
          texto.length > 62 ? '${texto.substring(0, 62)}…' : texto,
          true));
    }
  }
  return out;
}

/// Arquivos de tela. Os `.arb` ficam de fora: eles não são fonte para nada.
List<File> telas() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    // **`lib/controllers` entra, e a entrada veio do aparelho.** O título da
    // seção do catálogo era texto de tela em inglês morando no controller, com
    // `section.title.toUpperCase()` na view — o `dump` do A72 mostrava
    // `DOWNLOADED` numa tela em português e **nenhuma das duas varreduras via**,
    // porque as duas só andavam em `views` e `widgets`. A lista de diretórios é o
    // que a trava mede, então uma pasta a menos é um teto que protege menos do que
    // parece.
    .where((f) =>
        f.path.contains('/views/') ||
        f.path.contains('/widgets/') ||
        f.path.contains('/controllers/'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

void main() {
  /// Interpreta o caractere depois da barra. Mesma regra da ferramenta, e a razão
  /// de estar aqui e não ali: `src[k + 1]` grava a LETRA `n` de um `\n`, e o
  /// texto saía sem separador nenhum — "…tasks arenscheduled…".
  ///
  /// O nome é `_unescape` como na ferramenta de propósito: são a mesma regra e
  /// mudar um dos dois deixa as contagens divergindo sem ninguém avisar.
  String _unescape(String c) => c == 'n' ? '\n' : (c == 't' ? '\t' : c);

  /// **A lista de call sites é a mesma da ferramenta, e ela tem que incluir
  /// todo parâmetro que PINTA texto.** `subtitle` entrou depois de o A72
  /// mostrar três legendas em inglês com a trava em zero; `helperText`,
  /// `prefixText`, `suffixText`, `errorText` e `semanticCounterText` entraram
  /// na mesma leva. `message` e `hint` NÃO entram: aparecem em código que não
  /// é tela, e a lista é o que esta trava conta — broaden aqui é o caminho para
  /// o teto subir sem ninguém traduzir.
  ///
  /// **O filtro é `TextLanguage.looksEnglish`, o mesmo da ferramenta.**
  ///
  /// A primeira versão deste arquivo tinha a lista de palavras **aqui dentro**,
  /// e a ferramenta tinha a dela. Duas listas em dois arquivos divergem em
  /// silêncio — foi o que a auditoria de overflow, a de overflow de linha e a
  /// de descrição de catálogo fizeram neste repo, cada uma com a mesma causa.
  ///
  /// E a primeira versão também **contava menos do que devia**: o regex dela
  /// era `(?:Text|title|...)\s*\(\s*'...'`, que só casa a forma com parêntese.
  /// `title:`, `labelText:`, `hintText:` e `label:` usam **dois-pontos**, e
  /// nenhuma entrava. O contador dizia 63 e a verdade eram 125 — um teste que
  /// se praises de medir e mede metade é pior do que nenhum, porque o teto
  /// protege menos do que parece.
  ///
  /// **A forma de parêntese e a de dois-pontos contam o mesmo literal**, e o
  /// `[^']{8,}` só lê o primeiro segmento de um literal adjacente — o que não
  /// muda a **contagem** (um call site, um literal) e por isso o teto bate com
  /// o que a ferramenta relata.

  /// Junta os segmentos de um literal adjacente a partir de [ini].
  ///
  /// **O Dart concatena literais vizinhos em tempo de compilação**, então o texto
  /// de tela ocupa três a cinco linhas e o valor real é a concatenação. Ler só o
  /// primeiro segmento é o que fez 18 fichas de catálogo parecerem truncadas, e é
  /// também por isso que o contador inicial ficava **10 abaixo** do verdadeiro: um
  /// primeiro segmento curto como `'No '` não tem palavra de inglês, mas a frase
  /// completa tem.
  ///
  /// O delimitador pode mudar entre segmentos (`'a' "b"` é um valor só), e o escape
  /// é obrigatório: `'…da Microsoft's…'` fecha num `'` que não é o fim da string.
  /// Junta os segmentos de um literal adjacente a partir de [ini], e devolve
  /// **onde parou**.
  ///
  /// O segundo valor é o que permite a guarda de `.tr`: sem ele a única forma de
  /// saber onde a aspa de fechamento está é `ini + texto.length + 2`, e o `+2` é o
  /// tamanho das aspas — que muda quando o delimitador é duplo. Uma conta que só
  /// funciona em metade dos casos é a que some em silêncio na outra.
  (String, int) juntarSegmentos(String src, int ini) {
    final n = src.length;
    var abre = ini;
    final partes = <String>[];
    while (true) {
      while (abre < n && ' \n\t'.contains(src[abre])) {
        abre++;
      }
      if (abre >= n || (src[abre] != "'" && src[abre] != '"')) return ('', ini);
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

  /// O literal que termina em [fim] já é argumento de um `.tr`?
  ///
  /// **Um literal que já é `.tr` é uma tradução, não texto de tela em inglês.** Sem
  /// esta guarda a trava acusa as três sobras da rodada anterior — `'settings'.tr`
  /// duas vezes e `'appearance'.tr` — que renderizam `Configurações` e `Aparência`
  /// corretamente.
  ///
  /// E a regra precisa ser a mesma da ferramenta: com a guarda só na ferramenta as
  /// duas divergem, e foi o teste de contagem que pegou — 3 contra 0.
  bool jaTraduzido(String src, int fim) {
    var k = fim;
    while (
        k < src.length && (src[k] == ' ' || src[k] == '\n' || src[k] == '\t')) {
      k++;
    }
    return src.startsWith('.tr', k);
  }

  /// Um literal é "de tela em inglês" quando é uma frase com palavra de inglês.
  /// Um identificador (`OpenAI`, `GGUF`) e um exemplo de API (`curl $base/v1/…`)
  /// não entram, e é por isso que a lista `notText` existe.
  List<String> varre() {
    final achados = <String>[];
    for (final f in telas()) {
      final src = f.readAsStringSync();
      for (final m in RegExp(
              r"""(?<![A-Za-z_])(?:Text|title|subtitle|labelText|hintText|helperText|prefixText|suffixText|errorText|semanticCounterText|tooltip|label)\s*(?:\(|:)\s*(['"])""")
          .allMatches(src)) {
        final ini = m.end - 1;
        final (bruto, fim) = juntarSegmentos(src, ini);
        if (bruto.length < 8) continue;
        // **Um literal que já é argumento de `.tr` é uma tradução, não texto de
        // tela em inglês.** Sem esta guarda a trava acusa as três sobras da
        // rodada anterior — `'settings'.tr`, `'settings'.tr` e `'appearance'.tr`
        // — que renderizam `Configurações` e `Aparência` corretamente. E a regra
        // precisa ser a mesma da ferramenta: com a guarda só na ferramenta as
        // duas divergem, e foi o teste de contagem que pegou — 3 contra 0.
        if (jaTraduzido(src, fim)) continue;
        if (!TextLanguage.looksEnglish(bruto)) continue;
        achados.add('${f.path}:${src.substring(0, ini).split('\n').length}'
            '  ${bruto.length > 62 ? '${bruto.substring(0, 62)}…' : bruto}');
      }
    }
    return achados;
  }

  test('o número de literais em inglês não cresce', () {
    // **ZERO em 2026-10-02**, depois que os 137 literais de tela em telas
    // secundárias foram traduzidos por `tool/inline_english_scan.dart`.
    //
    // **Este teto já foi 51, 63, 102 e 123, e cada número mediu menos do que
    // dizia — sempre pelo mesmo motivo: a lista de call sites estava incompleta.**
    //
    //  - **51** veio de um filtro mais frouxo que o atual.
    //  - **63** porque o regex só casava a forma com parêntese — `title:`,
    //    `label:`, `labelText:` e `hintText:` usam **dois-pontos** e nenhuma
    //    entrava. Faltavam 39.
    //  - **102** porque `Text` é **sufixo** de `labelText`, `hintText` e
    //    `tooltip`: sem `(?<![A-Za-z_])` o mesmo literal era contado duas ou
    //    três vezes. Eram 112 posições.
    //  - **123** (102 + 21) porque a varredura só olhava o **primeiro**
    //    argumento depois de `subtitle:`, e quase todo tile deste app tem
    //    `subtitle: cond ? 'a' : 'b'` — os dois ramos eram invisíveis.
    //
    // E o que fechou em 123 foi o que **ningu** dos números acima previa:
    // **`subtitle` não estava na lista de call sites.** Três telas em inglês ao
    // lado de um teto em zero, todas `subtitle:` de `ListTile`. Um teto em zero
    // é a mesma falha de um teto alto: o número parou de ser informação, e só o
    // aparelho diz. É por isso que `a contagem da trava bate com a da
    // ferramenta` existe e que o irmão conta os literais **antes** do filtro.
    //
    // Um teto que protege menos do que parece é pior do que nenhum, porque dá
    // confiança falsa.
    //
    // **A trava sobe quando alguém traduz, e nunca afrouxa sozinha.** É
    // deliberado: um teto que cede sozinho deixa de ser uma promessa.
    const teto = 0;
    final hoje = varre();
    expect(hoje.length, lessThanOrEqualTo(teto),
        reason: 'O idioma da tela é uma escolha agora, e texto de interface '
            'que não passa pelo mapa existe numa língua só. Se você adicionou '
            'literal em inglês, use `.tr` e uma chave nos dois mapas '
            '(`lib/l10n/app_translation.dart`). Se você traduziu os que já '
            'existiam, baixe o teto para o número medido:\n'
            '${hoje.length - teto} a mais que o teto:\n'
            '  ${hoje.take(teto + 1).skip(teto).join('\n  ')}');
  });

  /// Quantos literais a varredura **vê**, antes do filtro de idioma.
  ///
  /// É o irmão que prova que o harness é hostil o bastante. Quando o teto era
  /// 102, o próprio número servia: um regex que parasse de casar reportaria
  /// zero e o teto passaria pelo motivo errado. **Com o teto em zero isso
  /// deixou de valer** — o número certo e o harness quebrado dão a mesma
  /// leitura — então a contagem bruta é a que se asserta agora.
  int vistos() {
    var n = 0;
    for (final f in telas()) {
      final src = f.readAsStringSync();
      for (final m in RegExp(
              r"""(?<![A-Za-z_])(?:Text|title|labelText|hintText|tooltip|label)\s*(?:\(|:)\s*(['"])""")
          .allMatches(src)) {
        if (juntarSegmentos(src, m.end - 1).$1.length >= 8) n++;
      }
    }
    return n;
  }

  test('a varredura ainda enxerga os literais, filtro ou não', () {
    expect(vistos(), greaterThan(150),
        reason:
            'se a varredura parou de casar, o teto de zero passa por não ter '
            'o que medir — e um teto que passa sem ver nada não é trava');
  });

  test('o filtro separa inglês de português, e não filtra por posição', () {
    // **O teto zero não diz que o filtro funciona** — diz que ninguém sobrou.
    // Um filtro que aceitasse tudo também daria zero. Estas são as duas
    // direções, e a segunda é a que pega um filtro que nunca rejeita.
    expect(TextLanguage.looksEnglish('Port the server listens on.'), isTrue);
    expect(TextLanguage.looksEnglish('A porta em que o servidor escuta.'),
        isFalse);
    // E um identificador com nome de palavra inglesa não é frase de tela.
    expect(TextLanguage.looksEnglish('OpenAI GGUF LitertLens'), isFalse);
    // E um texto com `$` é dinâmico: trocá-lo por uma chave apagaria a parte
    // que muda, que é o que a pessoa precisa ver.
    expect(TextLanguage.looksEnglish('Could not read: \$_loadError'), isFalse);
  });

  test('o ramo : de um ternário é texto de tela, e o campo de idioma não o engole',
      () {
    // **A décima primeira omissão, e ela esconde em vez de exagerar.**
    //
    // `eCampoDeIdioma` existe porque o `dart format` quebra a atribuição entre o
    // nome do campo e o literal:
    //
    // ```dart
    // descriptionEn: description == null || description.trim().isEmpty
    //     ? 'Added from custom URL'
    //     : description.trim(),
    // ```
    //
    // A versão que existia subia uma linha quando a de cima começava com `? ` —
    // e isso tratava o **ramo `: '…'` de qualquer ternário** como campo de idioma.
    // O sintoma é **assimetria dentro do próprio ternário**, e é por isso que só
    // apareceu quando a tradução começou: `Hide` na lista como TEXTO e `Show`
    // como DADO, no mesmo `cond ? a : b`. Onze textos estavam escondidos.
    //
    // **Um detector que esconde é pior do que um que exagerar**, porque teto
    // baixo não protege e teto alto não engana ninguém: os dois números estão
    // errados, e o baixo parece prudente. Onze textos de tela — um botão, duas
    // mensagens de estado, um rótulo de campo — estavam em inglês e nenhuma das
    // três travas podia acusar o que elas não viam.
    //
    // **A defesa é a assimetria como asserção**, e não o caso do catálogo: um
    // `descriptionEn` legítimo é raro e está num arquivo só; um ternário com dois
    // ramos de tela é comum e está em todos. Verificar que os **dois** ramos do
    // mesmo ternário recebem a mesma classificação pega a regra larga sem
    // depender de nenhum arquivo em particular.
    const fonte = '''
void f(BuildContext context, bool showDetails) {
  Text(
    showDetails
        ? 'Hide Technical Details'
        : 'Show Technical Details',
  );
}
''';
    final iniRamoHide = fonte.indexOf("'Hide");
    final iniRamoShow = fonte.indexOf("'Show");
    expect(TextLanguage.eCampoDeIdioma(fonte, iniRamoHide), isFalse,
        reason: 'o ramo ? de um ternário que não é campo de idioma');
    expect(TextLanguage.eCampoDeIdioma(fonte, iniRamoShow), isFalse,
        reason: 'o ramo : de um ternário NÃO é campo de idioma, e dizer que é '
            'tira o texto da lista de pendências sem nenhum aviso');
    // **E o caso que a regra existe para continua sendo campo de idioma**, com o
    // nome do campo DUAS linhas acima do literal.
    const catalogo = '''
      descriptionEn: description == null || description.trim().isEmpty
          ? 'Added from custom URL'
          : description.trim(),
''';
    expect(
        TextLanguage.eCampoDeIdioma(catalogo, catalogo.indexOf("'Added")), isTrue);
  });

  test(
      'nenhum literal interpolado com inglês, que é a classe que o filtro recusa',
      () {
    // **A varredura de cima cega este arquivo de propósito.** `looksEnglish`
    // devolve falso para qualquer texto com `$`, porque o valor no fonte não é o
    // valor na tela — trocar o literal inteiro por uma chave apagaria a parte que
    // muda. A consequência é que a trava reportava **zero** com dezenove telas em
    // inglês no aparelho, todas no mesmo formato: um trecho fixo em volta de um
    // ou dois valores.
    //
    // **É a única trava deste arquivo que conta por conteúdo e não por
    // chave**, e a diferença é o motivo dela existir: casar por chave é o que
    // `catalog_inline.tsv` faz e o que o escritor consome, e uma chave de
    // interpolação não vem do scanner — vem de `lib/services/text_interpolation.dart`
    // e de uma lista de traduções à mão.
    final interpolados = <String>[];
    for (final f in telas()) {
      final src = f.readAsStringSync();
      for (final m in RegExp(
              r"""(?<![A-Za-z_])(?:Text|title|subtitle|labelText|hintText|helperText|prefixText|suffixText|errorText|semanticCounterText|tooltip|label)\s*(?:\(|:)\s*'([^']*\$[^']*)'""",
              dotAll: true)
          .allMatches(src)) {
        final bruto = m.group(1)!.split(' ').join(' ');
        // **O idioma é do que SOBRA depois de tirar a interpolação.** Passar o
        // literal inteiro a `looksEnglish` não funciona, e por construção: a
        // função devolve falso para qualquer `$`, que é exatamente o que este
        // regex exige. A primeira versão filtrou por `looksEnglish` primeiro e a
        // trava reportava **zero** com um literal interpolado em inglês no fonte
        // — a mesma classe de erro que ela existe para pegar.
        final fixo = TextLanguage.tirarInterpolacoes(bruto);
        if (!TextLanguage.looksEnglish(fixo)) continue;
        interpolados.add(
            '${f.path}:${src.substring(0, m.start).split('\n').length}'
            '  ${bruto.length > 62 ? '${bruto.substring(0, 62)}…' : bruto}');
      }
    }
    expect(interpolados, isEmpty,
        reason: 'literal interpolado em inglês — a varredura acima não pode '
            'ver nenhum deles, por desenho. A tradução é '
            '`lib/services/text_interpolation.dart`: '
            "preencher('chave', {'n': valor}).\n"
            '  ${interpolados.take(5).join('\n  ')}');
  });

  test('nenhum texto de tela em inglês fora dos call sites', () {
    // **A segunda varredura, e ela é mais larga de propósito.**
    // `tool/inline_english_scan.dart` só olha o primeiro argumento de `Text`,
    // `title:`, `subtitle:` e companhia — o conjunto que a máquina pode reescrever
    // porque o valor no fonte é o valor na tela. Este teste roda o **mesmo
    // arquivo** `tool/inline_english_broad.dart`, que olha todo literal.
    //
    // A diferença entre os dois números é o que ela mede: **41** no amplo contra
    // **0** no estreito, e os 41 são identificador de runtime (`'local'`),
    // chave de payload (`json['loaded']`), documento de caso de teste do encoder
    // e exemplo de shell — **nenhum é texto de tela**, e traduzir qualquer um
    // deles muda comportamento sem erro nenhum. Por isso o teto do amplo é
    // **zero para os de texto** e a lista de não-texto é do próprio arquivo, com o
    // motivo de cada entrada.
    //
    // **Uma lista de exclusão sem motivo é uma lista para ninguém auditar.** As
    // 16 entradas de `naoTexto` e as cinco regras de contexto existem para que a
    // próxima pessoa consiga ler "por que isto não é texto" sem abrir o diff.
    // **61, e todos em `lib/controllers`.** Este número não é zero porque
    // **largar a lista de diretórios achou mais uma pasta**: o título da seção do
    // catálogo era texto de tela em inglês morando no controller, e o `dump` do
    // A72 mostrou `DOWNLOADED` numa tela em português enquanto as duas varreduras
    // diziam que não havia nada. views e widgets estão em zero; o que sobrou são
    // títulos e corpos de snackbar e diálogo do `chat_controller`, do
    // `model_controller` e do `server_controller` — tela, todos eles, e o bloco
    // seguinte.
    //
    // **O teto é o número medido, não zero**, e a escolha é deliberada: um teto
    // em zero com 61 linhas reais seria um teste que passa pelo motivo errado,
    // que é a mesma falha do teto alto. **Zero em views/widgets** está na
    // asserção seguinte, e é lá que ela não pode voltar.
    // **212, e este número é o terceiro a nascer de um defeito da própria
    // varredura, não de trabalho novo.**
    //
    // A varredura ampla reportava **zero** texto de tela com 263 textos em
    // inglês na tela, porque a classe de caracteres do regex estava errada desde
    // que a ferramenta foi escrita: ela excluía a **letra `n`** em vez da quebra
    // de linha, então nenhum literal com `n` no meio casava. `'Warning: values
    // above 8192…'` tem um `n` em *Warning*. Não era um filtro de idioma: era um
    // filtro de letra, e pegava `'Anúncio'` em português e `'Cancel'` em inglês
    // pelo mesmo motivo.
    //
    // **Os três sintomas eram o mesmo: a contagem batia.** Zero texto de tela,
    // zero controller, zero chave faltando, `flutter test` verde. Um detector
    // que não casa nada reporta a mesma coisa que um detector que não acha nada,
    // e a única forma de saber qual é o dos é ter **um irmão que prova que ele
    // ainda case com alguma coisa** — que é este teste.
    //
    // Corrigir a classe e subir a janela para 240 levou a 264, dos quais 12 eram
    // fragmentos de literal adjacente: a varredura ampla não juntava segmentos,
    // e o Dart concatena vizinhos em tempo de compilação, então
    // `'know whether a local model is worth'` é a **segunda metade** de uma frase
    // cuja primeira metade já é `.tr`. `TextLanguage.juntarSegmentos` é agora a
    // implementação única, e as três ferramentas a chamam.
    //
    // **O `juntarSegmentos` resolveu o primeiro segmento e não os do meio.** Com
    // ele a contagem foi para 257 — e era **12 a mais** do que a dívida real,
    // que é a **sexta** vez que a lista do que a trava mede estava incompleta,
    // agora por *omissão de posição*. O `vistos` marcava `m.start` e o `fim`, e um
    // literal adjacente de quatro linhas tem **três inicios no meio**: cada um
    // passava por `vistos.add` sem estar lá dentro e reportava a mesma frase
    // **sem o primeiro segmento**. `tool/dup_probe.dart` mediu **87 grupos com
    // 155 inicios extras**, e nenhum deles era dívida. `juntarSegmentos` passou a
    // devolver **quais inicios consumiu**, e são 212.
    //
    // **O número antigo estava em três lugares deste repositório** — este teto,
    // `AGENTS.md` e `docs/HANDOFF.md` — e a tabela de omissões já tinha sete
    // linhas. A oitava é esta, e a forma dela é diferente das outras sete: as
    // anteriores eram uma **ausência** (uma pasta, um parâmetro, uma letra), e
    // esta é uma **repetição**, que nenhuma lista de "o que a trava cobre"
    // denuncia. Repetição não se acha olhando o que a trava mede; só se acha
    // perguntando **quantas vezes ela mede a mesma coisa** — e essa pergunta não
    // tinha sido feita em nenhum dos itens anteriores.
    //
    // **O que sobrou são 216 literais** de `views`, `widgets` e `controllers` —
    // rótulos, mensagens de `snackbar` e diálogo, e prosa de explicação. São
    // tela, todos eles, e é o item 3e do `HANDOFF`.
    //
    // **A nona omissão é a primeira cujo sintoma é um teto ALTO.** As oito
    // anteriores faziam a trava medir de menos, e um número baixo parece
    // seguro. Esta fazia o contrário: `pareceInglesAmplo` julgava **código**
    // dentro de `${…}` como se fosse idioma, e `DateTime.now()` é `now`, que é
    // palavra da lista — então `'mobilelm_${DateTime.now()…}.png'`, o nome do
    // arquivo temporário do compartilhamento de imagem, entrava como texto de
    // tela. Medido: **36 entradas**, todas com a mesma forma (`$name`,
    // `$filename`, `$e`, `DateTime.now`). Remover a interpolação **antes** de
    // julgar é a mesma regra que a trava dos interpolados já usava.
    //
    // **E a décima omissão estava do lado do conteúdo, não do alcance.** As 27
    // palavras medidas (`show`, `back`, `copy`, `benchmark`, `clear`, `name`…)
    // expuseram **10 textos** que estavam em inglês na tela desde sempre e que
    // nenhuma das duas varreduras contava: `Copy important logs`, `Clear logs`,
    // `Show it anyway`, `Provider name`, `Base URL`, `Projector`, `Turn off
    // anyway`, `CPU benchmark`, `Back to projects`, `New project name` — mais o
    // literal interpolado `Available: …GB · Context: …` de Configurações. Um
    // detector que não conhece a palavra não denuncia o texto, e o teto em zero
    // da varredura estreita era verdadeiro **e** a tela estava em inglês.
    //
    // **A décima primeira é a mais cruel das onze, porque ela esconde em vez de
    // exagerar.** `eCampoDeIdioma` subia uma linha quando a linha de cima
    // começava com `? `, e isso tratava o **ramo `: '…'` de qualquer ternário**
    // como campo de idioma:
    //
    // ```dart
    // showDetails
    //     ? 'Hide Technical Details'
    //     : 'Show Technical Details',      // ← não era texto de tela
    // ```
    //
    // **O sintoma é assimetria dentro do próprio ternário**, e é por isso que só
    // apareceu na tradução: `Hide` estava na lista como TEXTO e `Show` como DADO,
    // no mesmo `cond ? a : b`. Onze textos voltaram a ser contados — `Show
    // Technical Details`, `Local model`, `server not running — tap to retry`,
    // `Rerankers score a query against each document.`, `Clear form`,
    // `Benchmark usability`, `Attached file:`, `Generated with mobileLM`,
    // `Thinking for @s` e mais dois. A correção é a **duas linhas acima**: a
    // linha do `?` só é ramo de um `descriptionEn` se o campo estiver antes
    // dela.
    const teto = 216;
    final texto = broad();
    expect(texto.length, lessThanOrEqualTo(teto),
        reason: 'literal em inglês que é texto de tela. A lista de não-texto é '
            '`TextLanguage.naoTexto`, com o motivo de cada entrada.\n'
            '${texto.length - teto} a mais que o teto:\n'
            '  ${texto.skip(teto).map((a) => '${a.onde}  ${a.texto}').join('\n  ')}');
    // **A lista de não-texto não pode crescer sem motivo novo.** Onze entradas
    // têm um motivo porque a tradução as exigiu; uma decima segunda sem motivo é
    // a exclusão que ninguém confere, e é o modo de falha que a lista existe
    // para evitar.
    expect(TextLanguage.naoTexto.length, greaterThan(30));
    expect(TextLanguage.naoTexto.values.every((m) => m.length > 25), isTrue,
        reason:
            'toda entrada da lista precisa dizer por quê — uma exclusão sem '
            'motivo é uma exclusão que ninguém confere');
  });

  test('toda exclusão da lista de não-texto ainda existe literal no fonte', () {
    // **A trava é negativa e a lista de não-texto é um buraco por natureza.**
    // Um identificador comparado com `==` ou procurado com `contains()` deixa de
    // ser encontrado quando é traduzido — porque o texto traduzido não tem
    // palavra de inglês, que é o critério da varredura. Provado: trocar
    // `lower.contains('out of memory')` por `lower.contains('memória esgotada')`
    // deixa a trava **verde**, e o efeito é o `out of memory` do engine caindo
    // na mensagem genérica de erro.
    //
    // A lista é o único registro de que aquilo **não** é para traduzir, e um
    // registro que não é lido não protege nada. Este teste a lê pelo outro lado:
    // cada entrada tem que **existir** no fonte, que é a afirmação oposta à que a
    // varredura faz.
    //
    // **Frases também, e são as que mais importam.** A primeira versão pulava
    // tudo com espaço — ou seja, pulava exatamente as quatro entradas que
    // quebram comportamento quando traduzidas, e a prova de que isso importa foi
    // feita exatamente nelas.
    final fonte = telas().map((f) => f.readAsStringSync()).join('\n');
    // **O mesmo texto que a lista de não-texto casa: o literal já juntado.**
    // Uma entrada pode ser a frase inteira de um literal adjacente de várias
    // linhas, e aí `fonte.contains(entrada)` é falso mesmo com a entrada viva —
    // o fonte tem `'a '` numa linha e `'b'` na seguinte. As duas entradas que
    // falhavam aqui são exatamente essa forma: uma cauda de frase que só existe
    // concatenada. Procurar só por texto cru acusaria as duas de mortas, e elas
    // estão vivas protegendo comparação de comparação real.
    final juntado = <String>{};
    for (final f in telas()) {
      final src = f.readAsStringSync();
      for (var i = 0; i < src.length; i++) {
        if (src[i] != "'" && src[i] != '"') continue;
        final inicio = i;
        final (texto, fim) = TextLanguage.juntarSegmentos(src, inicio);
        if (texto.isEmpty) {
          i = inicio;
          continue;
        }
        juntado.add(texto);
        i = fim > inicio ? fim - 1 : inicio;
      }
    }
    final ausentes = <String>[];
    for (final entrada in TextLanguage.naoTexto.keys) {
      if (entrada.contains(' ')) {
        if (!fonte.contains(entrada) && !juntado.contains(entrada)) {
          ausentes.add(entrada);
        }
        continue;
      }
      // **Os dois delimitadores.** `"step"`, `"steps"` e `"Load"` estão com aspas
      // duplas **dentro** de um literal de aspas simples, e a checagem por `'x'`
      // não os via. A primeira versão passou com as três entradas vivas na lista
      // e nenhuma aparecendo no fonte — o mesmo resultado de uma lista vazia, por
      // um motivo diferente.
      final re = RegExp('([\'"])${RegExp.escape(entrada)}\\1');
      if (!re.hasMatch(fonte)) ausentes.add(entrada);
    }
    expect(ausentes, isEmpty,
        reason: 'esta entrada da lista de não-texto não existe mais como '
            'literal no fonte. Ou a comparação que ela protegia foi removida — e '
            'aí a entrada sai da lista — ou alguém traduziu o valor, que é '
            'exatamente o que ela existe para impedir:\n'
            '  ${ausentes.join('\n  ')}');
  });

  test('a varredura ampla não conta o mesmo literal duas vezes', () {
    // **Este é o irmão do defeito do teto, e ele é uma pergunta nova.** As sete
    // omissões anteriores eram uma **ausência** — uma pasta, um parâmetro de
    // call site, uma letra na classe do regex — e nenhuma delas se acha olhando
    // o que a trava mede: acha-se porque **faltou** algo, e falta se nota. Esta é
    // uma **repetição**, e repetição não denuncia: ela só aparece perguntando
    // **quantas vezes a mesma posição é medida**.
    //
    // O `vistos` da varredura marcava o início do primeiro segmento e o fim da
    // cadeia. Um literal adjacente de quatro linhas tem **três inicios no meio**,
    // e cada um passava por `vistos.add` sem estar lá dentro — reconstruindo a
    // mesma frase **sem o primeiro segmento**. `'know whether a local model is
    // worth the download.'` estava na lista como pendência, e não é traduzível:
    // a frase completa está no segmento de cima, e é ela que a tela mostra.
    //
    // **`tool/dup_probe.dart` mediu 87 grupos com 155 inicios extras** e o teto
    // estava 45 acima do real. `juntarSegmentos` agora devolve quais inicios
    // consumiu, e os dois os marcam.
    //
    // **Um literal aninhado não conta aqui, e a distinção é o que faz o teste
    // valer.** `'${x ? '' : ' '}'` tem dois literais dentro de um terceiro, e
    // sempre vai ter: os três alcançam o mesmo `fim`, mas **só um** passa pelo
    // `vistos`. O que este teste proíbe é dois **achados** com o mesmo `fim`, e
    // não dois literais que se encontram — que é uma propriedade do fonte e não
    // um defeito. Os 4 que sobram em `server_view.dart` são aspas duplas dentro
    // de um `'''` de exemplo de `curl`, classificados `DADO`, e o teto conta só
    // texto; a sonda registra por que eles ficam.
    final repetidos = <String>[];
    for (final f in telas()) {
      final src = f.readAsStringSync();
      final re = RegExp("\\'([^\\'\\n]{2,240})\\'|\"([^\"\\n]{2,240})\"");
      final vistos = <int>{};
      // `fim` -> o texto do achado que chegou nele. Dois achados com o mesmo `fim`
      // leram o mesmo trecho do fonte, e um é um fragmento do outro.
      final fins = <int, String>{};
      for (final m in re.allMatches(src)) {
        if (!vistos.add(m.start)) continue;
        final inicios = <int>[];
        final (joined, fim) =
            TextLanguage.juntarSegmentos(src, m.start, inicios: inicios);
        if (joined.isEmpty) continue;
        vistos.addAll(inicios);
        vistos.add(fim);
        final antes = fins[fim];
        if (antes == null) {
          fins[fim] = joined;
          continue;
        }
        // **Só o que é texto de tela reprova.** Os 4 de `server_view.dart` são
        // exemplo de HTTP e Python dentro de `'''`, e o teste não pode exigir
        // que o scanner entenda interpolação raw para contar uma dívida que
        // ele não está contando.
        if (!TextLanguage.eTextoDeTela(joined, src, m.start)) continue;
        repetidos
            .add('${f.path}:${src.substring(0, m.start).split('\n').length}'
                '  "$joined"\n    repetindo "$antes"');
      }
    }
    expect(repetidos, isEmpty,
        reason: 'a varredura ampla reportou o mesmo literal mais de uma vez, e '
            'cada uma das cópias é um fragmento que não é traduzível:\n'
            '  ${repetidos.join('\n  ')}');
  });

  test('a lista notText não engole telas inteiras', () {
    // `notText` existe para não acusar `OpenAI` e `GGUF`. Um termo colocado
    // ali por engano — `model`, `light`, `about` — apagaria dezenas de linhas
    // do contador de uma vez e o teto passaria sem que ninguém traduzisse
    // nada. Cada termo tem que ser algo que **nunca** é português nem aparece
    // em frase de tela.
    for (final termo in const [
      'model',
      'light',
      'dark',
      'about',
      'settings',
      'test',
      'steps',
      'plan',
      'template',
      'key',
      'port',
      'default',
      'memory',
      'quality',
      'size',
      'speed',
      'time'
    ]) {
      expect(TextLanguage.notText, isNot(contains(termo)),
          reason: '"$termo" é palavra de interface, não nome próprio: '
              'colocá-la em notText apaga linhas do contador em silêncio');
    }
  });

  test('a contagem da trava bate com a da ferramenta', () {
    // **As duas medem a mesma coisa e é por isso que este teste existe.** A
    // ferramenta e a trava vivem em arquivos diferentes, com o filtro hoje
    // compartilhado em `TextLanguage`; se o padrão de call site divergir de
    // novo, a contagem diverge em silêncio e uma das duas proteções mente.
    //
    // O valor esperado é o que `dart run tool/inline_english_scan.dart`
    // relata. Ele é fixo aqui de propósito: se as duas divergirem, este teste
    // falha **antes** do teto, e a mensagem diz qual dos dois está errado.
    const esperado = 0;
    expect(varre().length, esperado,
        reason: 'a trava mediu uma coisa e a ferramenta mede outra. Rode '
            '`dart run tool/inline_english_scan.dart` e veja o TOTAL: se ele '
            'diferir deste número, uma das duas listas de call site mudou.');
  });
}
