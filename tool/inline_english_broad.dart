// Varredura **ampla** de literal em inglês em telas — sem lista de call sites.
//
// Existe porque `tool/inline_english_scan.dart` é **deliberadamente estreito**:
// ele só olha o primeiro argumento de `Text`, `title:`, `subtitle:` e companhia,
// e ignora o que tem `$` porque o valor no fonte não é o valor na tela. É o
// conjunto que pode ser reescrito por máquina. Este olha **todo** literal e é o
// que mostra o tamanho real da dívida — inclusive o que não é texto de tela.
//
//     dart run tool/inline_english_broad.dart            > /tmp/broad.txt
//     dart run tool/inline_english_broad.dart --sozinhos  # só os de UI
//
// **E o número que sai não é "textos em inglês na tela".** Ele mistura três
// coisas que a varredura estreita nunca mistura:
//
//  1. **Texto de tela** — o que se traduz. `Size`, `Cancel`, `DOWNLOADED`.
//  2. **Identificador comparado com `==`** — `'local'`, `'cloud'`, `'online'`,
//     `'ERROR'`, `'WARNING'`, `'failed'`. Traduzir quebra a comparação e o
//     app muda de comportamento sem erro nenhum.
//  3. **Dados que vão para o modelo ou para o log** — os documentos de caso de
//     teste do encoder console, `"the cat sat on the sofa"`, o exemplo de
//     código Python no painel de rerank, um fragmento de caminho (`'models/'`).
//     Traduzir muda o que o modelo recebe, e o caso de teste deixa de medir a
//     mesma coisa.
//
// Por isso a lista `--sozinhos` **não** é "o que sobrou para traduzir": é o que
// sobrou **e é texto**. O resto é um número de contexto, e é um número útil —
// foi ele que mostrou que a dívida é 164 e não 63, e que a maioria não é
// traduzível.
import 'dart:io';

import 'package:mobilelm/services/text_language.dart';

void main(List<String> args) {
  final sozinhos = args.contains('--sozinhos');
  final achados = <_Achado>[];
  // **`lib/controllers` entra, e a entrada veio do aparelho.** O titulo da secao
  // do catalogo era texto de tela em ingles morando no controller, com
  // `section.title.toUpperCase()` na view — o `dump` do A72 mostrava
  // `DOWNLOADED` numa tela em portugues e nenhuma das duas varreduras via, porque
  // as duas so andavam em `views` e `widgets`.
  for (final raiz in ['lib/views', 'lib/widgets', 'lib/controllers']) {
    final d = Directory(raiz);
    if (!d.existsSync()) continue;
    for (final f in d.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      achados.addAll(_varre(f));
    }
  }
  // **A comparação é pela linha pronta, e não pelo objeto.** `_Achado` não é
  // `Comparable` e `List.sort` sem comparador tenta um cast — a exceção sai como
  // `type '_Achado' is not a subtype of type 'Comparable<dynamic>'`, que fala
  // de tipo e não da linha que faltava.
  achados.sort((a, b) => '$a'.compareTo('$b'));
  for (final a in achados) {
    if (sozinhos && !a.eTexto) continue;
    stdout.writeln(a);
  }
  final deTexto = achados.where((a) => a.eTexto).length;
  stdout.writeln('TOTAL ${achados.length}  de texto: $deTexto  '
      'identificador/dado: ${achados.length - deTexto}');
}

/// Uma linha: `arquivo:linha<TAB>classe<TAB>texto`, com `\n` virado em escape.
class _Achado {
  _Achado(this.arquivo, this.linha, this.texto, this.eTexto);
  final String arquivo;
  final int linha;
  final String texto;
  final bool eTexto;
  @override
  String toString() => '$arquivo:$linha\t${eTexto ? 'TEXTO' : 'DADO'}\t'
      '${texto.replaceAll('\n', r'\n').replaceAll('\t', ' ')}';
}

List<_Achado> _varre(File f) {
  final src = f.readAsStringSync();
  final out = <_Achado>[];
  // **Não é raw string, e a razão é a mesma para as duas aspas.** `r'…'` fecha
  // num `'` interior e `r"…\"…"` fecha no `\"`, porque raw string não processa
  // escape. O sintoma de ambos é `the expression doesn't evaluate to a
  // function` em `re.allMatches`, **quatro linhas depois da causa**.
  //
  // Uma string normal resolve, com `\\` na frente de cada aspa e de cada `n`.
  final re = RegExp("\\'([^\\'\\\\n]{2,90})\\'|\"([^\"\\\\n]{2,90})\"");
  for (final m in re.allMatches(src)) {
    final texto = (m.group(1) ?? m.group(2) ?? '').trim();
    if (texto.isEmpty) continue;
    if (!TextLanguage.pareceInglesAmplo(texto)) continue;
    // **Já é `.tr`?** O que vem depois da aspa é o que decide, e é o mesmo
    // critério da ferramenta estreita.
    var k = m.end;
    while (
        k < src.length && (src[k] == ' ' || src[k] == '\n' || src[k] == '\t')) {
      k++;
    }
    if (src.startsWith('.tr', k)) continue;
    // **Chave de payload da API não é texto.** `json['loaded']` e
    // `json['error']` são campos do que o servidor devolve; traduzi-los deixa o
    // painel vazio sem nenhum erro, porque o acesso devolve `null` e o `??`
    // cobre.
    if (src.startsWith(']', k)) continue;
    final eTexto = TextLanguage.eTextoDeTela(texto, src, m.start);
    out.add(_Achado(
        f.path, src.substring(0, m.start).split('\n').length, texto, eTexto));
  }
  return out;
}

/// O literal está dentro de um **comentário de documentação** (`///` ou `//`)?
///
/// Uma frase em inglês dentro de um comentário é comentário. O que a varredura
/// contava era `not bindable —` e `The server said:` de uma discussion sobre o
/// porquê de uma frase estar onde está — texto que explica o código, e que fica

/// O literal está dentro de um registro de caso de teste do encoder console?
///
/// **Os documentos e as consultas dos casos são o que o modelo recebe**, e um
