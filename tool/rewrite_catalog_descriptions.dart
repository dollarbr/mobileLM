// Reescreve as descrições do catálogo nos **dois** idiomas.
//
// Existe porque regex não funciona neste arquivo, e a tentativa custou três
// builds. **18 das 62 descrições são literais adjacentes em Dart**, e o Dart
// concatena literais vizinhos em tempo de compilação:
//
//     'description':
//         'Cross-encoder reranker, ModernBERT, Portuguese and English. Measured '
//         'on an Edge 60 at 111 ms per query with a real logit spread of '
//         '2,07. The one to start with.',
//
// Três coisas quebram qualquer regex ao mesmo tempo: o valor ocupa **várias
// linhas**; 3 entradas usam **aspas duplas** (porque contêm `Microsoft's`); e
// `dart format` **remove o espaço entre os segmentos**, então `'a ' 'b'` vira
// `'a' 'b'`. Três versões de regex falharam em sequência, e a última **colou
// texto novo em cima do antigo** — `"…aparelhos compouca RAM"`, que parece
// traduzido e não está.
//
// Este arquivo faz o trabalho com o scanner do próprio Dart, que é quem decide
// o que é uma string. Rodar com:
//
//     dart run tool/rewrite_catalog_descriptions.dart
//
// É ferramenta de uma vez, não código do produto: roda, verifica, e sai.
//
// **Os dois idiomas saem em campos com o idioma NO NOME** (`descriptionEn`,
// `descriptionPt`). Um campo `description` que "significa português" foi a
// versão anterior e é a que produz o bug que o seletor de idioma veio
// consertar: com EN como padrão, alguém adiciona uma entrada com só `description`
// e a tela mostra português num app inglês, sem nenhum aviso. `catalogDescription()`
// resolve, e ela é quem tem o `.tr` da decisão.

import 'dart:io';

const catalogo = 'lib/core/constants.dart';
const enJson = 'tool/catalog_en.json';
const ptJson = 'tool/catalog_pt.json';

void main(List<String> args) {
  final en = _carregar(args.isNotEmpty ? args[0] : enJson);
  final pt = _carregar(args.length > 1 ? args[1] : ptJson);

  // Nenhum idioma pode ter entrada que o outro não tem. Um par assim é uma
  // entrada que aparece em português num app inglês, ou o inverso — e a falha
  // é invisível, porque a tela mostra *alguma* descrição.
  final soEn = en.keys.where((k) => !pt.containsKey(k)).toList();
  final soPt = pt.keys.where((k) => !en.containsKey(k)).toList();
  if (soEn.isNotEmpty || soPt.isNotEmpty) {
    stderr.writeln('ERRO: pares de traducao desiguais.');
    stderr.writeln('  so em EN: $soEn');
    stderr.writeln('  so em PT: $soPt');
    exit(1);
  }

  final src = File(catalogo).readAsStringSync();
  final aplicadas = <String>[];
  final saida = _reescrever(src, en, pt, aplicadas);

  if (saida == null) {
    stderr.writeln('ERRO: a varredura parou. ja aplicadas: ' +
        aplicadas.length.toString());
    stderr.writeln('  ultima: ' +
        (aplicadas.isEmpty ? '(nenhuma)' : aplicadas.last));
    exit(1);
  }
  File(catalogo).writeAsStringSync(saida);
  stdout.writeln('descricoes reescritas: ' + aplicadas.length.toString());

  // NÃO roda `dart format`: o arquivo já não está no formato do formatador no
  // main, e formatar aqui reescreve ~100 linhas que não têm nada a ver com a
  // tradução. A quebra de linha é do próprio _formatar, e é a que importa.
}

Map<String, String> _carregar(String caminho) {
  final bruto = File(caminho).readAsStringSync();
  final mapa = <String, String>{};
  // Formato deliberadamente burro: "nome<TAB>texto", um por linha, porque
  // qualquer aspa no texto quebraria um JSON escrito à mão.
  for (final linha in bruto.split('\n')) {
    if (linha.trim().isEmpty || linha.startsWith('#')) continue;
    final i = linha.indexOf('\t');
    if (i < 0) continue;
    mapa[linha.substring(0, i)] = linha.substring(i + 1);
  }
  return mapa;
}

/// Reescreve cada descrição, devolvendo `null` se algo não fechar.
String? _reescrever(
  String src,
  Map<String, String> en,
  Map<String, String> pt,
  List<String> aplicadas,
) {
  final buf = StringBuffer();
  var i = 0;
  final n = src.length;
  String? nomeAtual;

  while (i < n) {
    if (src.startsWith("'name':", i)) {
      final nome = _lerValor(src, i + "'name':".length);
      if (nome == null) { stderr.writeln('  PAROU em ler nome, i=' + i.toString()); return null; }
      nomeAtual = nome.valor;
      buf.write(src.substring(i, nome.fim));
      i = nome.fim;
      continue;
    }

    // Aceita o nome antigo para poder rodar sobre um arquivo já migrado.
    if (src.startsWith("'description':", i) ||
        src.startsWith("'descriptionEn':", i)) {
      final chave = src.startsWith("'descriptionEn':", i)
          ? "'descriptionEn':"
          : "'description':";
      final indent = i - src.lastIndexOf('\n', i) - 1;
      buf.write("'descriptionEn':\n" + ' ' * (indent + 4));
      i += chave.length;
      while (i < n && (src[i] == ' ' || src[i] == '\n' || src[i] == '\t')) {
        buf.write(src[i]);
        i++;
      }
      final atual = _lerValor(src, i);
      if (atual == null) { stderr.writeln('  PAROU em _lerValor, i=' + i.toString()); return null; }

      if (nomeAtual == null) {
        stderr.writeln('  PAROU: descricao sem nome');
        return null;
      }
      final textoEn = en[nomeAtual];
      final textoPt = pt[nomeAtual];
      if (textoEn == null || textoPt == null) {
        stderr.writeln('  PAROU: sem traducao para ' + nomeAtual);
        return null;
      }

      // O texto antigo em inglês é útil quando o EN não mudou, mas ele também
      // pode estar truncado — e foi, em uma entrada. Então o EN **sempre** vem
      // do JSON, nunca do arquivo: o arquivo é a saída, não a fonte.
      buf.write(_formatar(textoEn, ' ' * (indent + 4)));
      buf.write(",\n" + ' ' * (indent + 4) + "'descriptionPt':\n");
      buf.write(_formatar(textoPt, ' ' * (indent + 4)));
      aplicadas.add(nomeAtual);
      i = atual.fim;
      continue;
    }

    buf.write(src[i]);
    i++;
  }
  return buf.toString();
}

class _Valor {
  _Valor(this.valor, this.fim);
  final String valor;
  final int fim;
}

/// Lê o valor de um literal Dart **coletando todos os segmentos**.
///
/// A concatenação adjacente é a parte que faltou nas duas primeiras versões.
/// O catálogo escreve 18 das 62 descrições em 2 a 5 segmentos, e o Dart os junta
/// sozinho. Ler só o primeiro deixava o resto do texto antigo no arquivo, e o
/// resultado era o texto novo **colado no meio do antigo**.
///
/// Um segmento continua quando a próxima aspa, ignorando espaços e quebras, é
/// de novo uma abertura. Uma aspa no fim de linha que fecha o segmento não é
/// seguida de outra — é a distinção, e ela é o que o scanner precisa saber.
///
/// **O delimitador é lido UMA vez, e o laço interno só lê o corpo.** Foi aqui
/// que a versão anterior gastou uma volta inteira: encadeando, ela punha
/// `i = j + 1` para passar a aspa de abertura, e no topo do laço seguinte lia
/// `delim = src[i]` de novo — dois avanços na mesma aspa. O segundo pegava a
/// **letra** seguinte (`E` de `Edge`), que não é delimitador, e devolvia null
/// claiming que o arquivo não fechava.
///
/// A versão mais antiga tinha o bug oposto: `i = j` deixava a aspa ser lida
/// como fechamento, devolvia um segmento vazio e parava depois do primeiro. As
/// duas falhas produzem a mesma mensagem e causas diferentes, que é o que
/// confunde — a segunda achava que eram aspas duplas não tratadas.
_Valor? _lerValor(String src, int i) {
  final n = src.length;

  while (i < n && (src[i] == ' ' || src[i] == '\n' || src[i] == '\t')) {
    i++;
  }
  if (i >= n) return null;
  final delim = src[i];
  // O catálogo usa **as duas** formas de literal: 3 entradas abrem com " e
  // o resto com '. Um scanner que só conhece ' para na terceira, e a falha
  // aparece como "a varredura parou na 33ª entrada" — longe da causa.
  if (delim != "'" && delim != '"') return null;
  i++;

  final partes = <String>[];
  while (true) {
    final sb = StringBuffer();
    var fechado = false;
    while (i < n) {
      final c = src[i];
      if (c == r'\' && i + 1 < n) {
        sb.write(src[i + 1] == "'" ? "'" : src[i + 1]);
        i += 2;
        continue;
      }
      if (c == delim) {
        i++;
        fechado = true;
        break;
      }
      sb.write(c);
      i++;
    }
    if (!fechado) return null;
    partes.add(sb.toString());

    // Concatenação adjacente? A próxima aspa, ignorando espaços e quebras,
    // tem que ser de novo uma abertura. Uma aspa no fim de linha que fecha o
    // segmento não é seguida de outra — é a distinção.
    var j = i;
    while (j < n && (src[j] == ' ' || src[j] == '\n' || src[j] == '\t')) {
      j++;
    }
    if (j < n && (src[j] == delim || src[j] == "'" || src[j] == '"')) {
      i = j + 1; // passa a aspa de abertura do segmento seguinte
      continue;
    }
    return _Valor(partes.join(), i);
  }
}

/// Quebra o texto em linhas de 66 colunas, sem cortar dentro de uma palavra.
///
/// **O escape é aplicado ANTES de quebrar, não depois.** Quebrar depois deixaria
/// um apostrofo nu no fim da linha (`'…da Microsoft's…'`) e o arquivo parava de
/// compilar com um erro de sintaxe a 200 linhas da causa.
///
/// **E o espaço entre segmentos vai DENTRO do literal.** O Dart concatena
/// vizinhos sem separador, então um espaço *entre* as aspas é whitespace de
/// código e não entra no valor — foi assim que a versão anterior colou
/// `"…o primeiro qwen3que o app…"`. Uma versão mais nova punha o espaço depois
/// do `'`, que dá o mesmo resultado.
String _formatar(String texto, String indent) {
  const largura = 66;
  final palavras = _escapar(texto).split(' ');
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
  // **A última linha NÃO leva espaço**, e o `trimRight` do meio não resolve:
  // ele age sobre a string do arquivo-fonte, que termina em `'`, não em
  // branco — então o espaço ficava *dentro* do literal final e o Dart
  // concatenava um espaço a mais na descrição. A tela não mostra, e é
  // exatamente por isso que passaria despercebido até um teste comparar os
  // dois idiomas.
  final ultimo = linhas.length - 1;
  return linhas
      .map((l) => "'${l}${l == linhas[ultimo] ? '' : ' '}'")
      .join('\n$indent');
}

String _escapar(String t) => t.replaceAll(r'\', r'\\').replaceAll("'", r"\'");