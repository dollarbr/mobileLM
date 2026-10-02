import 'dart:convert';
import 'dart:io';

/// Escreve as traduções dos literais de tela nos dois mapas e reescreve os
/// literais como `'chave'.tr`.
///
/// Roda **depois** que `tool/inline_english_scan.dart` relê o fonte:
///
///     dart run tool/inline_english_scan.dart --rewrite tool/catalog_inline.json tool/catalog_inline.tsv
///
/// **O inglês vem do fonte, lido pela ferramenta — e é por isso que o arquivo
/// de traduções não tem coluna de inglês.** Digitar o texto de novo seria criar
/// uma segunda cópia que diverge em silêncio, e a divergência apareceria como
/// uma ficha errada na tela em vez de um erro aqui. O que já aconteceu com o
/// escape `\n`: o scanner resolvia para um caractere real, o arquivo tinha os
/// dois caracteres, e os dois lados eram "a mesma frase com uma quebra" em bytes
/// diferentes.
///
/// O que a ferramenta recusa, e recusa **antes** de escrever:
/// - uma posição do TSV que não existe mais no fonte;
/// - uma chave repetida;
/// - uma linha do fonte que não tem tradução.
///
/// E o que ela **não** recusa é o `.tr` de uma chave sem valor no mapa: isso é
/// o que o `l10n_keys_test` pega, e é o lugar certo para pegar — é o mesmo
/// defeito que 38 chaves já produziram.
void main(List<String> args) {
  final en = <String, String>{};
  final pt = <String, String>{};
  final textoParaChave = <String, String>{};
  final enPorChave = <String, String>{};

  final bruto = File('tool/catalog_inline.tsv').readAsStringSync();
  for (final linha in bruto.split('\n')) {
    if (linha.trim().isEmpty || linha.startsWith('#')) continue;
    final p = linha.split('\t');
    // 4 campos: texto, chave, tradução e um comentário de origem (`#2x` quando
    // o mesmo texto aparece em dois lugares). O quarto é opcional para que o
    // arquivo continue legível quando ninguém anotou nada.
    if (p.length < 3 || p.length > 4) {
      stderr.writeln('ERRO: linha com ${p.length} campos, esperado 3 ou 4:\n'
          '  $linha');
      exit(1);
    }
    final texto = p[0].replaceAll(r'\n', '\n').replaceAll(r'\t', '\t');
    final chave = p[1].trim();
    // **Texto repetido só é problema quando as traduções divergem.** Há nove
    // textos que aparecem em dois lugares com a mesma tradução — "Context Size"
    // em dois cartões, "Show API key", "System One test" — e é isso que torna o
    // casamento por texto seguro. Se um dia um deles precisar de traduções
    // diferentes, esta é a hora de dizer: o arquivo de casar-por-texto não
    // distingue os dois e a segunda tradução é a que a tela mostra.
    final anterior = textoParaChave[texto];
    if (anterior != null && pt[anterior] != p[2]) {
      stderr.writeln('ERRO: o mesmo texto tem duas traduções\n'
          '  "${texto.length > 40 ? '${texto.substring(0, 40)}…' : texto}"\n'
          '  ${anterior}: ${pt[anterior]}\n'
          '  $chave: ${p[2]}\n'
          'O casamento por texto precisa de volta a posição no fonte.');
      exit(1);
    }
    if (pt.containsKey(chave)) {
      stderr.writeln('ERRO: chave repetida $chave');
      exit(1);
    }
    if (anterior == null) textoParaChave[texto] = chave;
    // **Toda chave recebe o texto, mesmo quando o texto ja apareceu.** E o
    // que faz o mapa ingles ter as duas entradas de "Context Size".
    enPorChave[chave] = texto;
    pt[chave] = p[2];
  }
  stdout.writeln('traducoes lidas: ${pt.length}');

  // **O valor em inglês vem da PRIMEIRA coluna do TSV, e não do JSON.** O JSON é
  // indexado por texto e tem uma entrada por texto — 113 — enquanto o mapa
  // precisa de uma entrada por CHAVE, e são 123. Nove textos aparecem em duas
  // chaves com a mesma tradução; escrevendo o JSON direto, a segunda chave de
  // cada um não entrava no mapa inglês e a tela mostrava o identificador.
  for (final e in enPorChave.entries) {
    en[e.key] = e.value;
  }
  stdout.writeln('valores em ingles: ${en.length}');

  // E o JSON serve de conferência: o texto de cada chave foi realmente lido do
  // fonte, e não digitado aqui. Divergência entre os dois é o sinal de que o
  // scanner precisa rodar antes do escritor.
  final enBruto =
      File(args.isNotEmpty ? args[0] : 'tool/catalog_inline_en.json');
  if (enBruto.existsSync()) {
    final mapa =
        json.decode(enBruto.readAsStringSync()) as Map<String, dynamic>;
    var divergentes = 0;
    mapa.forEach((chave, texto) {
      final noTsv = enPorChave[chave as String];
      final t = texto as String;
      if (noTsv != null && noTsv != t) {
        divergentes++;
        stderr.writeln('  $chave: TSV '
            '"${noTsv.length > 44 ? '${noTsv.substring(0, 44)}…' : noTsv}" x '
            'fonte "${t.length > 44 ? '${t.substring(0, 44)}…' : t}"');
      }
    });
    if (divergentes > 0) {
      stderr.writeln('ERRO: $divergentes textos divergem entre o arquivo de '
          'traduções e o fonte. Rode o scanner antes do escritor.');
      exit(1);
    }
    stdout.writeln('conferido contra o fonte: ${mapa.length} textos');
  }

  // **Uma contagem, e por chave.** O inglês vem de `enPorChave` e a tradução de
  // `pt`; se um grew/desseu, alguma das leituras perdeu uma linha e o mapa sai
  // com uma chave só num idioma — que é o defeito que a auditoria de cobertura
  // dos dois mapas existe para pegar.
  if (enPorChave.length != pt.length) {
    stderr.writeln('ERRO: ${enPorChave.length} chaves com texto em inglês para '
        '${pt.length} traduções.');
    exit(1);
  }

  _acrescentar('en_US', en);
  _acrescentar('pt_BR', pt);
  stdout.writeln('mapa de traducoes reescrito');
}

/// Acrescenta as chaves novas no mapa pedido, mantendo o corpo que já existe.
///
/// **O mapa é um literal Dart com literais adjacentes**, então ele é lido e
/// reescrito com o mesmo cuidado do `constants.dart`: um `\n` dentro de um valor
/// é um caractere real na string do Dart, e trocar por `\\n` produziria uma
/// quebra a mais na tela.
void _acrescentar(String lang, Map<String, String> novas) {
  final caminho = 'lib/l10n/app_translation.dart';
  final src = File(caminho).readAsStringSync();
  final abre = src.indexOf("'$lang': {");
  if (abre < 0) {
    stderr.writeln('ERRO: mapa $lang não encontrado');
    exit(1);
  }
  final ini = abre + "'$lang': {".length;

  // O fim do mapa é o `\n    }` que fecha este literal, e não o primeiro
  // `}` do arquivo: há `}` dentro de interpolação e dentro de strings.
  var fim = src.length;
  var cursor = ini;
  int profundidade = 1;
  while (cursor < src.length) {
    final c = src[cursor];
    if (c == r'\' && cursor + 1 < src.length) {
      cursor += 2;
      continue;
    }
    if (c == "'" || c == '"') {
      cursor = _pulaLiteral(src, cursor);
      continue;
    }
    if (c == '{') profundidade++;
    if (c == '}') {
      profundidade--;
      if (profundidade == 0) {
        fim = cursor;
        break;
      }
    }
    cursor++;
  }

  final corpo = src.substring(ini, fim);
  // **Um comentário para o bloco inteiro, e um por entrada não.** A primeira
  // versão punha `// Localizada por tool/...` antes de cada chave: 204 linhas de
  // comentário para 204 entradas, e a informação que importa — de onde a
  // tradução veio — é uma só.
  final linhas = <String>[
    '      // ── Traduzidas por tool/inline_english_scan.dart ─────────────',
    '      // A posição no fonte é o que amarra a tradução ao texto: um texto',
    '      // repetido em dois lugares seria traduzido duas vezes, e a segunda',
    '      // tradução é a que a tela mostra. Use `.tr` e apague o literal.',
  ];
  for (final entrada in novas.entries) {
    linhas.add('      ${_literal(entrada.key)}: '
        '${_quebra(entrada.value)},');
  }
  final blob = corpo.replaceAll(RegExp(r'\n\s*$'), '') +
      '\n' +
      linhas.join('\n') +
      '\n    ';
  File(caminho)
      .writeAsStringSync(src.substring(0, ini) + blob + src.substring(fim));
}

int _pulaLiteral(String src, int i) {
  final delim = src[i];
  var k = i + 1;
  while (k < src.length) {
    final c = src[k];
    if (c == r'\' && k + 1 < src.length) {
      k += 2;
      continue;
    }
    if (c == delim) return k + 1;
    k++;
  }
  return k;
}

String _literal(String chave) =>
    "'${chave.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";

/// Quebra o valor em linhas de 66 colunas, com o espaço **dentro** do literal.
///
/// O espaço entre segmentos vai dentro porque o Dart concatena literais vizinhos
/// sem separador — `'a' 'b'` é `ab`. É o mesmo detalhe que já colou
/// `"…aparelhos compouca RAM"` no catálogo, e a quebra aqui é do próprio
/// formatador, não do `dart format`, que reformata o arquivo inteiro.
/// Escapa um valor de runtime para dentro de um literal Dart simples.
///
/// **Char a char, e não por `replaceAll`.** Duas tentativas anteriores erraram
/// por substituição em cascata: `\\n` no fonte (que o Dart lê como barra mais
/// `n`) e uma **quebra de linha real dentro do literal**, que não compila — e a
/// segunda chegou a ser escrita num arquivo de 1200 linhas, com o erro
/// apontando para a linha 491 em vez de para a causa.
///
/// A quebra de linha do valor tem que virar `\n` **no fonte**; uma quebra real
/// no fonte é erro de sintaxe, e uma `\` duplicada é texto errado na tela.
String _quebra(String texto) {
  const largura = 66;
  // **Normaliza antes de escapar.** A entrada vem em duas representações: o
  // inglês é extraído do fonte e sai com **quebra real**; a tradução vem do
  // arquivo TSV, que é uma entrada por linha e portanto carrega `\n` como
  // **escape de duas letras**. Converter os dois para caractere aqui é o que
  // faz `\n` virar `\n` no fonte e a quebra real virar `\n` também — sem isso a
  // primeira vira `\\n` (barra mais n, lida como texto) e a segunda vira uma
  // quebra de linha dentro do literal, que não compila.
  texto = texto.replaceAll(r'\n', '\n').replaceAll(r'\t', '\t');
  final sb = StringBuffer();
  for (final r in texto.runes) {
    final c = String.fromCharCode(r);
    switch (c) {
      case '\\':
        sb.write(r'\\');
        break;
      case "'":
        sb.write(r"\'");
        break;
      case r'$':
        sb.write(r'\$');
        break;
      case '\n':
        sb.write(r'\n');
        break;
      case '\t':
        sb.write(r'\t');
        break;
      case '\r':
        break;
      default:
        sb.write(c);
    }
  }
  final palavras = sb.toString().split(' ');
  final linhas = <String>[];
  var atual = '';
  for (final p in palavras) {
    final cand = atual.isEmpty ? p : '$atual $p';
    if (cand.length > largura && atual.isNotEmpty) {
      linhas.add(atual);
      atual = p;
    } else {
      atual = cand;
    }
  }
  if (atual.isNotEmpty) linhas.add(atual);
  final ultimo = linhas.length - 1;
  // **Concatenação, e não interpolação.** A versão com `".map((l) =>
  // "'\${l}\${...}'")` gravava `\$` no fonte do mapa — que o Dart lê como
  // dólar literal, não como interpolação — e as 102 entradas saíram com o
  // próprio código dentro do literal: `'$l${l == linhas[ultimo] ...}'`. Isso
  // são 1432 issues e uma mensagem que aponta para o `map`, não para o lugar
  // onde o texto foi gerado.
  final buf = StringBuffer();
  for (var i = 0; i < linhas.length; i++) {
    if (i > 0) buf.write('\n          ');
    buf.write("'");
    buf.write(linhas[i]);
    if (i != ultimo) buf.write(' ');
    buf.write("'");
  }
  return buf.toString();
}
