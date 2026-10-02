// Extrai os literais de tela que ainda estão em inglês, lendo o valor
// INTEIRO com o scanner do Dart.
//
// Existe porque **quase todos os 63 são literais adjacentes** — o Dart concatena
// os vizinhos em tempo de compilação, então o texto ocupa três a cinco linhas.
// Uma regex que lê só o primeiro segmento é exatamente o que fez 18 fichas de
// catálogo parecerem truncadas, e a lição está escrita no `AGENTS.md`.
//
// Não reescreve nada. Só relata, para que a tradução seja escrita sobre o texto
// completo e não sobre um pedaço dele:
//
//     dart run tool/inline_english_scan.dart            > /tmp/scan.txt
//     dart run tool/inline_english_scan.dart --rewrite tool/catalog_inline.json
//
// Com `--rewrite`, substitui cada literal pela chamada de `.tr` da chave que o
// mapa declara. **A chave nunca sai do texto novo**: ela vem do arquivo de
// traduções, e um literal cujo nome de chave não exista ali é recusado em vez
// de virado num `.tr` que devolve o próprio identificador — que é o defeito que
// o GetX produz quando a tradução falta.

import 'dart:convert';
import 'dart:io';

import 'package:mobilelm/services/text_language.dart';

/// Locais de chamada cujo primeiro argumento é texto de tela.
///
/// **`subtitle` estava faltando, e era metade dos que sobraram.** As três
/// legendas que o A72 mostrou em inglês depois de a trava reportar zero eram
/// todas `subtitle:` de `ListTile` — e a lista não tinha o nome. É a mesma
/// classe de "a trava media menos do que dizia", agora por **omissão** em vez de
/// por regex: um teto em zero com três telas em inglês ao lado.
///
/// Os parâmetros são os do Flutter que **pintam texto**. `message` e `hint` não
/// entram porque aparecem em código que não é tela, e a lista é o que a trava
/// conta — broaden aqui é o caminho para o teto subir sem ninguém traduzir.
///
/// **A lista é o que a trava conta**, e por isso ela está aqui e não
/// duplicada no teste: dois lugares com a mesma lista divergem sem ninguém ver.
const callSites = <String>[
  'Text',
  'title',
  'subtitle',
  'labelText',
  'hintText',
  'helperText',
  'prefixText',
  'suffixText',
  'errorText',
  'semanticCounterText',
  'tooltip',
  'label',
];

void main(List<String> args) {
  final reescrever = args.contains('--rewrite');
  // Posicional 1 = traduções, positional 2 = mapa de posições. Sem eles o modo
  // leitura funciona sozinho, que é como a ferramenta é usada primeiro.
  // Os posicionais são **depois** de `--rewrite`: `args` traz o flag na
  // posição 0, e ler `args[0]` como arquivo dá "arquivo não encontrado" com o
  // nome `--rewrite` na mensagem — que é a pista de que o flag é o flag.
  var posicionais = args.where((a) => !a.startsWith('--')).toList();
  // **O casamento é por TEXTO, e não por `arquivo:linha`.** A linha se move:
  // reescrever um literal adjacente de três linhas como `'chave'.tr` apaga duas
  // linhas e empurra todas as abaixo, então as posições medidas antes da
  // reescrita apontam para o literal errado — e a ferramenta aceitou, porque
  // confia na posição. Foi o único erro deste trabalho que não dava nenhum
  // aviso.
  final chavePor = reescrever
      ? _carregarPorTexto(posicionais.last)
      : const <String, String>{};

  final achados = <_Achado>[];
  for (final f in _arquivos()) {
    final src = f.readAsStringSync();
    for (final a in _varrer(src)) {
      achados.add(a.comArquivo(f.path));
    }
  }

  stdout.writeln('chaves casadas: ${chavePor.length}');

  if (!reescrever) {
    // **Uma linha por literal, e a quebra de linha escapada.** A listagem
    // anterior era `### posicao` seguido do texto em uma ou mais linhas, e o
    // texto que contém `\n` ocupava duas: quem lia o relatório tinha de saber
    // onde a entrada terminava, e a segunda linha de um texto de duas linhas
    // era indistinguível do começo da entrada seguinte. Um relatório que exige
    // convenção de leitura é um relatório que alguém vai ler errado — e aqui a
    // leitura errada troca uma tradução pelo texto vizinho.
    for (final a in achados) {
      stdout.writeln('${a.arquivo}:${a.linha}\t'
          '${a.constante}\t${_umaLinha(a.texto)}');
    }
    stdout.writeln('TOTAL ${achados.length}');
    return;
  }

  // O texto em inglês sai daqui, e **não** de uma coluna do arquivo de
  // traduções: digitar de novo seria criar uma segunda cópia que diverge em
  // silêncio, e a divergência apareceria como uma ficha errada na tela em vez de
  // um erro aqui.
  File('tool/catalog_inline_en.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
    for (final a in achados)
      if (chavePor[a.texto] != null) chavePor[a.texto]!: a.texto
  }));
  stdout.writeln('textos em ingles extraidos');

  int aplicadas = 0;
  // **Falta de chave é aviso; falta de tradução é erro.** A distinção é o que
  // permite a migração em duas passadas: a primeira reescreve o que já está
  // traduzido, a segunda varre o que apareceu depois e traduz. Com as duas como
  // erro, a primeira passagem é recusada por 21 literais que ainda nem têm
  // chave — e o arquivo inteiro fica por reescrever.
  final semChave = <String>[];
  final semTraducao = <String>[];

  // **A ordem é por POSIÇÃO, decrescente — e `reversed` não é isso.**
  // `achados` é montada percorrendo os rótulos um a um: todos os `Text`, depois
  // todos os `title`, depois todos os `labelText`. Reverter a lista inverte a
  // ordem *dos rótulos*, não a das posições, então uma substituição cedo foi
  // aplicada sobre índices que já não valiam — e o resultado foram **111.828
  // linhas inseridas** em catorze arquivos, que é a forma mais barata de
  // descobrir que o índice é a premissa.
  final ordenados = List<_Achado>.from(achados)
    ..sort((a, b) {
      final c = a.arquivo.compareTo(b.arquivo);
      return c != 0 ? c : b.ini.compareTo(a.ini);
    });
  for (final a in ordenados) {
    final chave = chavePor[a.texto];
    if (chave == null) {
      semChave.add('${a.arquivo}:${a.linha}  '
          '${a.texto.length > 50 ? '${a.texto.substring(0, 50)}…' : a.texto}');
      continue;
    }
    if ((_traducoesDoArquivo[chave] ?? '').trim().isEmpty) {
      semTraducao.add('chave "$chave" sem traducao em ${posicionais.last}');
      continue;
    }
    a.substituir(chave);
    aplicadas++;
  }
  if (semChave.isNotEmpty) {
    stdout.writeln('aviso: ${semChave.length} literais sem chave, '
        'deixados como estao:');
    for (final s in semChave) {
      stdout.writeln('  $s');
    }
  }
  if (semTraducao.isNotEmpty) {
    stderr.writeln('ERRO: ${semTraducao.length} sem traducao:');
    for (final s in semTraducao) {
      stderr.writeln('  $s');
    }
    exit(1);
  }
  // Só os arquivos que **tiveram** um literal entram em `_pendente`, e um
  // arquivo sem nenhum não está no mapa. Iterar `_arquivos()` e forçar o
  // `!` derrubou a ferramenta em `Null check operator used on a null value` —
  // que é a forma mais cara de dizer "não escreva o que você não leu".
  for (final caminho in _pendente.keys.toList()..sort()) {
    File(caminho).writeAsStringSync(_pendente[caminho]!);
  }
  stdout.writeln(
      'literais reescritos: $aplicadas em ${_pendente.length} arquivos');
}

/// Arquivos de tela. `_pendente` guarda o texto em edição por caminho, porque a
/// substituição acontece no trecho e o arquivo só é escrito no fim.
final _pendente = <String, String>{};

/// Os diretórios que a varredura cobre.
///
/// **`lib/controllers` entrou depois do `dump` do A72**, que mostrou um texto de
/// tela em inglês morando no controller. A lista de diretórios é o que a
/// ferramenta e a trava medem, e as duas têm que ter a mesma: enquanto só
/// `views` e `widgets` estavam aqui, a ferramenta dizia **0** e a trava
/// acusava **1** — as duas medindo coisas diferentes e nenhuma reclamando.
List<File> _arquivos() {
  final out = <File>[];
  for (final raiz in ['lib/views', 'lib/widgets', 'lib/controllers']) {
    final d = Directory(raiz);
    if (!d.existsSync()) continue;
    out.addAll(d
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart')));
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

Map<String, String> _carregar(String caminho) {
  final bruto = File(caminho).readAsStringSync();
  final out = <String, String>{};
  for (final linha in bruto.split('\n')) {
    if (linha.trim().isEmpty || linha.startsWith('#')) continue;
    final i = linha.indexOf('\t');
    if (i < 0) continue;
    out[linha.substring(0, i)] = linha.substring(i + 1);
  }
  return out;
}

/// Mapa de **texto em inglês** → chave de tradução.
///
/// **Um texto repetido vale uma chave só.** Há nove: "Show API key" em dois
/// cartões, "Hide API key", "System One test", "Context Size", "Download",
/// "settings", "Model ID", "Faster execution…", "what the file says about
/// itself". Todos com **tradução idêntica** nas duas chaves, que é o que torna
/// o casamento seguro. `test/inline_english_ratchet_test.dart` vigia essa
/// propriedade; se um dia dois usos divergirem, o casamento passa a escolher um
/// dos dois por ordem de arquivo e o arquivo precisa de volta a posição.
Map<String, String> _carregarPorTexto(String caminho) {
  final bruto = File(caminho).readAsStringSync();
  final saida = <String, String>{};
  final textos = <String, String>{};
  for (final linha in bruto.split('\n')) {
    if (linha.trim().isEmpty || linha.startsWith('#')) continue;
    final p = linha.split('\t');
    if (p.length < 3) continue;
    // **O texto do arquivo é desserializado antes do casamento.** A quebra de
    // linha de um valor tem que virar `\n` no TSV, porque o arquivo é uma
    // entrada por linha — e então o texto lido here tem uma barra e um `n`
    // enquanto o literal tem uma quebra de verdade, e os dois não casam. São
    // exatamente as duas entradas que sobraram na primeira passada, e a
    // mensagem era a de "literal sem chave", que não diz onde está o problema.
    final texto = p[0].replaceAll(r'\n', '\n').replaceAll(r'\t', '\t');
    // A primeira ocorrência define a chave; as seguintes são o mesmo texto.
    if (saida.containsKey(texto)) continue;
    saida[texto] = p[1].trim();
    textos[p[1].trim()] = p[2];
  }
  _traducoesDoArquivo = textos;
  return saida;
}

/// Traduções do último arquivo lido. Fica em topo de arquivo porque os dois
/// leitores são chamados em sequência e nenhum dos dois recebe o outro.
Map<String, String> _traducoesDoArquivo = const <String, String>{};

class _Achado {
  _Achado(this.src, this.ini, this.fim, this.texto, this.rotulo, this.constante)
      : linha = src.substring(0, ini).split('\n').length;
  final String src;
  final int ini;
  final int fim;
  final String texto;
  final String rotulo;
  final bool constante;
  final int linha;
  String arquivo = '';

  _Achado comArquivo(String p) {
    arquivo = p;
    _pendente.putIfAbsent(p, () => src);
    return this;
  }

  /// Troca o literal por `'chave'.tr` e tira o `const` de cima.
  ///
  /// **O `const` precisa sair.** `'chave'.tr` é uma chamada de runtime — `.tr`
  /// lê o locale atual — e `const Text('chave'.tr)` não compila. Uma versão
  /// anterior deste arquivo ignorava isso e a falha aparecia longe: um erro de
  /// constante no meio de um arquivo de 3000 linhas.
  void substituir(String chave) {
    final p = arquivo;
    var buf = _pendente[p]!;
    // **O `const` a remover é o que governa ESTE literal, e ele numa linha
    // acima.** A primeira versão só olhava `antes.endsWith('const ')`, o que
    // pega `const Text('x')` na mesma linha e erra os outros 26: `subtitle:
    // const Text(` com a string na linha seguinte, `decoration: const
    // InputDecoration(`, `const _SectionLabel(`, `return const [`.
    //
    // Andar para trás a partir do literal: pula branco, **exige uma abertura de
    // construtor** (`(`, `[`, `{`), sobe o identificador, pula branco de novo e
    // só então aceita `const`. Exigir a abertura é o que impede de remover o
    // `const` de um **irmão** — `const SizedBox(...)` logo acima não governa o
    // `Text` que vem depois dele.
    final g = _governanteConst(buf, ini);
    final semConst =
        g == null ? buf.substring(0, ini) : buf.substring(0, g.inicio);
    // **O construtor volta.** `const Text('x')` precisa virar
    // `Text('chave'.tr)`, e a primeira versão trocava `const Text(` inteiro
    // por `'chave'.tr` — o que deixa `label: 'chave'.tr),` e **118 erros de
    // sintaxe** em vez de 29 de `const`. Remover o `const` é metade do
    // trabalho; a outra metade é repor o nome que ficou na frente dele.
    final prefixo = g == null ? '' : g.construtor;
    // **Só a chamada nova entra no buffer.** A primeira versão escrevia
    // `novo = semConst + "'$chave'.tr"` e depois prefixava `semConst` de novo:
    // o começo do arquivo era acrescentado duas vezes por substituição, e o
    // resultado foram 111.830 linhas inseridas em catorze arquivos. O sintoma
    // é `lenBuf` dobrando na primeira substituição e não voltando — que é como
    // se descobre que a premissa (o índice) estava certa e a composição, não.
    final novo = "$prefixo'$chave'.tr";
    buf = buf.substring(0, semConst.length) + novo + buf.substring(fim);
    _pendente[p] = buf;
  }
}

/// O literal que termina em [fim] já é argumento de um `.tr`?
///
/// O que olha é o que vem **depois** da aspa de fechamento, pulando branco —
/// `'x'.tr` e `'x'.toUpperCase()` têm a mesma forma e só a primeira é uma
/// tradução. E o que importa é o `.tr` colado: `'x'.toString().tr` é uma
/// tradução que passou por uma transformação, e `'x'.translate()` não é nada.
bool _jaTraduzido(String src, int fim) {
  var k = fim;
  while (
      k < src.length && (src[k] == ' ' || src[k] == '\n' || src[k] == '\t')) {
    k++;
  }
  return src.startsWith('.tr', k);
}

/// O texto com a quebra de linha virada em escape, para caber numa linha.
///
/// E a tabulação também, porque a listagem é separada por tabulação e um `\t`
/// dentro do texto trocaria a coluna. Só os dois aparecem em literal de tela.
String _umaLinha(String t) =>
    t.replaceAll('\\', '\\\\').replaceAll('\n', r'\n').replaceAll('\t', r'\t');

/// Percorre `src` e devolve os literais de tela, com o valor já juntado.
///
/// **O rótulo precisa de fronteira de palavra à esquerda.** `Text` é **sufixo**
/// de `labelText`, `hintText` e `tooltip`, e uma busca por substring contava o
/// mesmo literal até três vezes — 125 achados para 112 posições. Uma contagem
/// inflada por duplicata é pior que uma contagem errada: o teto sobe sem
/// ninguém traduzir, e a trava deixa de proteger exatamente o que parece
/// proteger.
List<_Achado> varrer(String src) => _varrer(src);

List<_Achado> _varrer(String src) {
  final out = <_Achado>[];
  final vistos = <int>{};
  for (final rotulo in callSites) {
    // (?<![A-Za-z_]) é o que impede `labelText` de casar como `Text`.
    final re = RegExp('(?<![A-Za-z_])${RegExp.escape(rotulo)}'
        "\\s*(?:\\(|:)\\s*['\"]");
    for (final m in re.allMatches(src)) {
      final ini = m.end - 1;
      // Um literal, uma posição: dois rótulos que casam o mesmo texto contam
      // uma vez só.
      if (!vistos.add(ini)) continue;

      final valor = _lerLiteral(src, ini);
      if (valor == null) continue;
      // **Um literal que JÁ é argumento de `.tr` não é texto de tela em
      // inglês — é uma tradução.** Sem esta guarda a ferramenta escreve por
      // cima: `'settings'.tr` vira `'nav_settings'.tr.tr`, que compila (o
      // segundo `.tr` é só mais uma chamada na mesma string) e mostra a chave
      // no lugar do texto. Aconteceu em três linhas e **nada reclamou**:
      // `flutter analyze` não tem o que dizer sobre isso e o teste de chaves
      // continua verde, porque a chave existe no mapa.
      if (_jaTraduzido(src, valor.fim)) continue;
      if (valor.texto.length < 8) continue;
      // **O filtro é o MESMO da trava**, importado de `TextLanguage`. Duas
      // listas em dois arquivos divergem em silêncio, e é o modo de falha que já
      // atingiu três auditorias deste repo.
      if (!TextLanguage.looksEnglish(valor.texto)) continue;

      final antes = src.substring(0, ini);
      out.add(_Achado(src, ini, valor.fim, valor.texto, rotulo,
          antes.trimRight().endsWith('const')));
    }
    out.addAll(_ramosDeCondicional(src, rotulo));
  }
  return out;
}

/// Os literais que estão nos **ramos de um ternário**, e não no primeiro
/// argumento.
///
/// `subtitle: cond ? 'The benchmark still shows…' : 'Showing only what is on…'`
/// é a forma de quase todo tile deste app — e uma varredura que só olha o
/// argumento **imediatamente** depois de `subtitle:` não vê nenhum dos dois. É a
/// mesma classe de erro de "mede menos do que diz" que já pegou `Text` como
/// sufixo de `labelText`: um limite que esconde metade do texto.
///
/// A janela vai do rótulo até a **próxima linha com indentação menor ou igual**,
/// que é o fim da expressão. Cortar por `;` não serve: um ternário raramente
/// tem ponto e vírgula, e o `;` seguinte pode estar três linhas abaixo e
/// pertencer a outro statement.
List<_Achado> _ramosDeCondicional(String src, String rotulo) {
  final out = <_Achado>[];
  final re = RegExp('(?<![A-Za-z_])${RegExp.escape(rotulo)}\\s*:');
  for (final m in re.allMatches(src)) {
    final indentRotulo = src.substring(0, m.start).split('\n').last.length;
    var fim = src.indexOf('\n', m.end);
    var limite = src.length;
    while (fim > 0) {
      final prox = src.indexOf('\n', fim + 1);
      if (prox < 0) break;
      final linha = src.substring(fim + 1, prox);
      if (linha.trim().isNotEmpty) {
        final ind = linha.length - linha.trimLeft().length;
        if (ind <= indentRotulo) break;
      }
      fim = prox;
    }
    if (fim > 0 && fim < src.length) limite = fim;
    final janela = src.substring(m.end, limite);
    // **A aspa tem que vir IMEDIATAMENTE depois de `?` ou `: `.** A primeira
    // versão casava qualquer aspa na janela e trouxe `? settings.openaiModel.value`
    // e `).first;` como "literais" — 119 falsos positivos para 30 textos. Um
    // ternário de verdade tem a forma `cond ? 'a' : 'b'`, e exigir a aspa
    // colada no operador é o que separa os dois.
    for (final lit in RegExp("[?:]\\s*(['\"])(?=[^\\s])").allMatches(janela)) {
      final ini = m.end + lit.end - 1;
      if (_primeiroArgumento(src, ini)) continue;
      final valor = _lerLiteral(src, ini);
      if (valor == null) continue;
      if (valor.texto.length < 8) continue;
      if (!TextLanguage.looksEnglish(valor.texto)) continue;
      final antes = src.substring(0, ini);
      out.add(_Achado(src, ini, valor.fim, valor.texto, rotulo,
          antes.trimRight().endsWith('const')));
    }
  }
  return out;
}

/// O literal em [ini] é o **primeiro** argumento do rótulo que o contém?
///
/// Sem isto, `subtitle: cond ? 'a…' : 'b…'` contaria `'a…'` duas vezes: uma como
/// primeiro argumento e outra como ramo de ternário.
bool _primeiroArgumento(String src, int ini) {
  for (final rotulo in callSites) {
    final re = RegExp('(?<![A-Za-z_])${RegExp.escape(rotulo)}'
        "\\s*(?:\\(|:)\\s*['\"]");
    final m = re.firstMatch(src.substring(0, ini + 1));
    if (m != null && m.end - 1 == ini) return true;
  }
  return false;
}

/// O `const` que governa um literal, e o construtor que ele qualifica.
///
/// Devolve `null` quando não há `const` a remover. O índice é do **`c`**, e não
/// do começo da linha, para que o espaço depois da palavra saia junto.
class _Governante {
  _Governante(this.inicio, this.construtor);
  final int inicio;

  /// `Text(`, `InputDecoration(`, e vazia para uma lista literal.
  final String construtor;
}

_Governante? _governanteConst(String buf, int ini) {
  bool branco(int i) =>
      i >= 0 && (buf[i] == ' ' || buf[i] == '\n' || buf[i] == '\t');
  var k = ini - 1;
  while (branco(k)) {
    k--;
  }
  if (k < 0) return null;
  // A forma `label: 'x'` tem **dois-pontos** antes do literal e a forma
  // `Text('x')` não. Sem pular o `:`, um `label:` dentro de um `const [` de
  // registros não encontra o `const` da lista.
  if (buf[k] == ':') {
    k--;
    while (branco(k)) {
      k--;
    }
    if (k < 0) return null;
  }
  if (buf[k] != '(' && buf[k] != '[' && buf[k] != '{') return null;
  final abre = k;
  k--;
  while (branco(k)) {
    k--;
  }
  final fimIdent = k + 1;
  while (k >= 0 && RegExp(r'[A-Za-z0-9_]').hasMatch(buf[k])) {
    k--;
  }
  final construtor = buf.substring(k + 1, abre + 1);
  if (k + 1 == fimIdent) return null;
  while (branco(k)) {
    k--;
  }
  if (k - 4 < 0) return null;
  if (buf.substring(k - 4, k + 1) != 'const') return null;
  // `const` precisa estar sozinho: a letra anterior não pode ser parte de outra
  // palavra, senão o nome é `myconst`.
  if (k - 5 >= 0 && RegExp(r'[A-Za-z0-9_]').hasMatch(buf[k - 5])) return null;
  return _Governante(k - 4, construtor);
}

/// Interpreta o caractere depois da barra.
///
/// **Escrever `src[k + 1]` direto não é desescapar.** Para `\n` isso grava a
/// letra `n`, e o texto saía `"…tasks arenscheduled…"` em vez de
/// `"…tasks are\nscheduled…"` — uma frase sem separador, que passa em revisão de
/// código e só aparece na tela.
String _unescape(String c) {
  switch (c) {
    case 'n':
      return '\n';
    case 't':
      return '\t';
    case 'r':
      return '\r';
    default:
      return c;
  }
}

class _Lit {
  _Lit(this.texto, this.fim);
  final String texto;
  final int fim;
}

_Lit? _lerLiteral(String src, int i) {
  final n = src.length;
  var j = i;
  while (j < n && (src[j] == ' ' || src[j] == '\n' || src[j] == '\t')) {
    j++;
  }
  if (j >= n) return null;
  if (src[j] != "'" && src[j] != '"') return null;
  var abre = j;

  final partes = <String>[];
  // O delimitador pode mudar entre segmentos: `'a' "b"` é um valor só.
  while (true) {
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
    if (!fechado) return null;
    partes.add(sb.toString());

    var m = k;
    while (m < n && (src[m] == ' ' || src[m] == '\n' || src[m] == '\t')) {
      m++;
    }
    if (m < n && (src[m] == "'" || src[m] == '"')) {
      abre = m;
      continue;
    }
    return _Lit(partes.join(), m);
  }
}
