// Reescreve as `description` do catálogo a partir de um mapa de traduções.
//
// Existe porque regex não funciona aqui, e a tentativa custou três builds:
// **18 das 59 descrições são literais adjacentes em Dart**, e o Dart concatena
// literais vizinhos automaticamente. Uma regex `(?:'[^']*')+` para no
// apostrofo de `"Microsoft\'s"`, devolve um valor menor que o real, e a
// substituição deixa o texto antigo colado depois do novo.
//
// Este arquivo faz o trabalho com o scanner do próprio Dart, que é quem
// decide o que é uma string. Rodar com:
//
//   dart run tool/rewrite_catalog_descriptions.dart
//
// É ferramenta de uma vez, não código do produto: roda, verifica, e sai.

import 'dart:io';

const catalogo = 'lib/core/constants.dart';

void main(List<String> args) {
  final traducoes = _carregar(args.isEmpty ? 'tool/catalog_pt.json' : args[0]);
  final src = File(catalogo).readAsStringSync();

  final aplicadas = <String>[];
  final saida = _reescrever(src, traducoes, aplicadas);

  if (saida == null) {
    stderr
        .writeln('ERRO: a varredura parou. ja aplicadas: ${aplicadas.length}');
    stderr.writeln(
        'ultima: ' + (aplicadas.isEmpty ? '(nenhuma)' : aplicadas.last));
    exit(1);
  }
  File(catalogo).writeAsStringSync(saida);
  // NÃO roda `dart format`: o arquivo já não está no formato do formatador no
  // main, e formatar aqui reescreve ~100 linhas que não têm nada a ver com a
  // tradução. A quebra de linha é do próprio _formatar, e é a que importa.
  stdout.writeln('aplicadas: ${aplicadas.length}');
}

Map<String, String> _carregar(String caminho) {
  final bruto = File(caminho).readAsStringSync();
  final mapa = <String, String>{};
  // Formato deliberadamente burro: "nome<TAB>texto", um por linha, porque
  // qualquer aspas no texto quebraria um JSON escrito a mao.
  for (final linha in bruto.split('\n')) {
    if (linha.trim().isEmpty || linha.startsWith('#')) continue;
    final i = linha.indexOf('\t');
    if (i < 0) continue;
    mapa[linha.substring(0, i)] = linha.substring(i + 1);
  }
  return mapa;
}

/// Reescreve cada `description`, devolvendo `null` se algo não fechar.
///
/// A estratégia é localizar o par de aspas que delimita o valor **contando**,
/// e o contador trata `\` como escape — que é a única regra que a regex não
/// fazia.
String? _reescrever(
  String src,
  Map<String, String> traducoes,
  List<String> aplicadas,
) {
  final buf = StringBuffer();
  var i = 0;
  final n = src.length;

  // nome da entrada atual, para casar a traducao
  String? nomeAtual;

  while (i < n) {
    // captura 'name': '...' para saber qual entrada é esta
    if (src.startsWith("'name':", i)) {
      final nome = _lerString(src, i + "'name':".length);
      if (nome != null) {
        nomeAtual = nome.valor;
        buf.write(src.substring(i, nome.fim));
        i = nome.fim;
        continue;
      }
    }

    if (src.startsWith("'description':", i)) {
      buf.write(src.substring(i, i + "'description':".length));
      i += "'description':".length;
      // pula espacos
      while (i < n && (src[i] == ' ' || src[i] == '\n' || src[i] == '\t')) {
        buf.write(src[i]);
        i++;
      }
      final atual = _lerValorCompleto(src, i);
      if (atual == null) return null;
      final novo = nomeAtual == null ? null : traducoes[nomeAtual];
      if (novo == null) {
        buf.write(src.substring(i, atual.fim));
      } else {
        buf.write(_formatar(novo, ' ' * (i - src.lastIndexOf('\n', i) - 1)));
        aplicadas.add(nomeAtual!);
      }
      i = atual.fim;
      continue;
    }

    buf.write(src[i]);
    i++;
  }
  return buf.toString();
}

class _Str {
  _Str(this.valor, this.fim);
  final String valor;
  final int fim;
}

/// Lê um literal Dart começando em [i], que precisa estar na aspa de abertura.
///
/// Devolve o valor **sem** os escapes resolvidos: o texto de uma descrição em
/// português não tem `\`, e resolver exigiria desfazer `\"` e `\\` sem saber
/// o que é conteúdo.
_Str? _lerString(String src, int i) {
  final n = src.length;
  // pula espacos ate a aspa
  while (i < n && (src[i] == ' ' || src[i] == '\n' || src[i] == '\t')) {
    i++;
  }
  // O catálogo usa **as duas** formas de literal: 3 entradas abrem com " e
  // o resto com '. Um scanner que só conhece ' para na terceira, e a falha
  // aparece como "a varredura parou na 33ª entrada" — longe da causa, que é
  // uma aspa que ninguém pensou em tratar.
  if (i >= n) return null;
  final delim = src[i];
  if (delim != "'" && delim != '"') return null;
  i++;
  final sb = StringBuffer();
  while (i < n) {
    final c = src[i];
    if (c == r'\' && i + 1 < n) {
      final e = src[i + 1];
      sb.write(e == "'" ? "'" : e);
      i += 2;
      continue;
    }
    if (c == delim) return _Str(sb.toString(), i + 1);
    sb.write(c);
    i++;
  }
  return null;
}

/// Lê o valor de um `description` **coletando todos os segmentos**.
///
/// A concatenação adjacente é a parte que faltava nas duas primeiras versões.
/// O catálogo escreve 18 das 59 descrições em 2 a 5 segmentos, e o Dart os
/// junta sozinho — `listenable()` em tempo de compilação. Ler só o primeiro
/// segmento deixava o resto do texto antigo no arquivo, e o resultado era o
/// texto novo **colado no meio do antigo**: "…aparelhos compouca RAM". É pior
/// que não traduzir, porque parece traduzido.
///
/// Um segmento continua quando a próxima aspa, ignorando espaços e quebras,
/// é de novo uma abertura. Uma aspa no fim de linha que fecha o segmento não
/// é seguida de outra — é a distinção, e ela é o que o scanner precisa saber.
class _ValorCompleto {
  _ValorCompleto(this.valor, this.fim);
  final String valor;
  final int fim;
}

_ValorCompleto? _lerValorCompleto(String src, int i) {
  final n = src.length;
  final partes = <String>[];

  while (true) {
    while (i < n && (src[i] == ' ' || src[i] == '\n' || src[i] == '\t')) {
      i++;
    }
    if (i >= n) return null;
    final delim = src[i];
    if (delim != "'" && delim != '"') return null;
    i++;
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

    var j = i;
    while (j < n && (src[j] == ' ' || src[j] == '\n' || src[j] == '\t')) {
      j++;
    }
    if (j < n && (src[j] == "'" || src[j] == '"')) {
      i = j;
      continue;
    }
    return _ValorCompleto(partes.join(), i);
  }
}

/// Quebra o texto em linhas de [largura], sem cortar dentro de uma palavra.
///
/// O `\` do escape é aplicado **antes** de quebrar, não depois: quebrar depois
/// deixava um apostrofo nu no fim de uma linha e o arquivo parava de
/// compilar com um erro de sintaxe a 200 linhas da causa.
String _formatar(String texto, String indent) {
  const largura = 66;
  final palavras = _escapar(texto).split(' ');
  final linhas = <String>[];
  var atual = '';
  for (final p in palavras) {
    final cand = atual.isEmpty ? p : '$atual $p';
    if (cand.length > largura && atual.isNotEmpty) {
      linhas.add('$atual ');
      atual = p;
    } else {
      atual = cand;
    }
  }
  if (atual.isNotEmpty) linhas.add(atual);

  // **O espaço vai DENTRO do literal, no fim.** O Dart concatena literais
  // vizinhos sem separador, então um espaço *entre* as aspas é whitespace de
  // código e não entra no valor — foi assim que a versão anterior colou
  // "…primeiro qwen3que o app…". Uma versão mais nova punha o espaço depois
  // do `'`, e a falha é idêntica: `'qwen3' 'que'` são dois valores que se
  // juntam sem nada no meio.
  //
  // A última linha não leva espaço, senão a descrição termina com um.
  final ultimo = linhas.length - 1;
  return linhas
      .map((l) => "'${l.trimRight()}${l == linhas[ultimo] ? '' : ' '}'")
      .join('\n$indent');
}

String _escapar(String t) => t.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
