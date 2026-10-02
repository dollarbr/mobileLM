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
  final re = RegExp("\\'([^\\'\\\\n]{2,90})\\'|\"([^\"\\\\n]{2,90})\"");
  for (final f in telas()) {
    final src = f.readAsStringSync();
    for (final m in re.allMatches(src)) {
      final texto = (m.group(1) ?? m.group(2) ?? '').trim();
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
    const teto = 61;
    final texto = broad();
    expect(texto.length, lessThanOrEqualTo(teto),
        reason:
            'literal em inglês que é texto de tela. views e widgets estão em '
            'zero; o que sobra é `lib/controllers`. A lista de não-texto é '
            '`TextLanguage.naoTexto`, com o motivo de cada entrada.\n'
            '${texto.length - teto} a mais que o teto:\n'
            '  ${texto.skip(teto).map((a) => '${a.onde}  ${a.texto}').join('\n  ')}');
    expect(texto.where((a) => !a.onde.contains('/controllers/')), isEmpty,
        reason: 'views e widgets estão em ZERO. Se um literal apareceu aí, é '
            'regressão e não dívida — e a lista de diretórios é o que a trava '
            'mede, então uma pasta a mais já é um teto que protege menos do que '
            'parece.');
    // **O irmão que prova que o filtro de não-texto ainda filtra alguma coisa.**
    // Sem ele, uma lista de exclusão que passa a casar tudo zera os dois números
    // e o teste passa pelo motivo errado.
    expect(TextLanguage.naoTexto.length, greaterThan(15));
    expect(TextLanguage.naoTexto.values.every((m) => m.length > 20), isTrue,
        reason:
            'toda entrada da lista precisa dizer por quê — uma exclusão sem '
            'motivo é uma exclusão que ninguém confere');
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
