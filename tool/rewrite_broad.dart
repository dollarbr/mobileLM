/// Reescreve os literais de tela da **varredura ampla** como `'chave'.tr`, e
/// escreve a chave nos dois mapas de tradução.
///
///     dart run tool/rewrite_broad.dart tool/broad_inline.tsv
///     dart run tool/rewrite_broad.dart tool/broad_inline.tsv --sozinhos
///
/// **Por que uma ferramenta e não a mão.** São 177 literais em 20 arquivos, e o
/// que a reescrita tem de acertar é mecânico e repetido: casar o valor **inteiro**
/// (literal adjacente de três linhas é um literal só), tirar o `const` que o
/// governa, e repor o construtor. Feito à mão, cada um desses é uma chance de
/// esquecer o `const` — e o sintoma de esquecer é um erro de compilação longe da
/// causa, que é a mesma falha que o `write_inline_translations.dart` jáPagou para
/// não repetir.
///
/// **O casamento é por TEXTO, nunca por `arquivo:linha`.** Ver
/// `write_inline_translations.dart`: reescrever um literal adjacente como
/// `'chave'.tr` apaga as linhas do meio e empurra todas as de baixo, então uma
/// posição medida antes da primeira reescrita aponta para o lugar errado — e a
/// ferramenta aceitaria, porque ela confia na posição. **Foi o único erro deste
/// trabalho que não dava aviso nenhum.** O texto é seguro como chave porque o
/// escritor recusa um texto repetido cujas traduções divergem.
///
/// **O literal interpolado é recusado, de propósito.** `looksEnglish` devolve
/// falso para qualquer `$` porque o valor no fonte não é o valor na tela, e
/// trocar o literal inteiro por uma chave apagaria a parte que muda. A solução é
/// `lib/services/text_interpolation.dart` — `preencher('chave', {'n': valor})` —,
/// que é uma edição por mão. A ferramenta **conta** quantos recusou e diz quais,
/// para que a omissão seja um número e não um silêncio.
library;

import 'dart:convert';
import 'dart:io';

import 'package:mobilelm/services/text_language.dart';

void main(List<String> args) {
  final caminho = args.isNotEmpty ? args[0] : 'tool/broad_inline.tsv';
  final en = <String, String>{};
  final pt = <String, String>{};
  final textoParaChave = <String, String>{};
  final enPorChave = <String, String>{};
  final interpolados = <String>[];

  for (final linha in File(caminho).readAsStringSync().split('\n')) {
    if (linha.trim().isEmpty || linha.startsWith('#')) continue;
    final p = linha.split('\t');
    if (p.length < 3 || p.length > 4) {
      stderr.writeln('ERRO: linha com ${p.length} campos, esperado 3 ou 4:\n'
          '  $linha');
      exit(1);
    }
    // **O texto é desserializado antes do casamento.** O arquivo é uma entrada
    // por linha, então `\n` chega como barra mais `n` enquanto o literal tem uma
    // quebra de verdade — e os dois não casam. São exatamente as entradas que
    // sobraram na primeira passada do escritor dos interpolados.
    final texto = p[0].replaceAll(r'\n', '\n').replaceAll(r'\t', '\t');
    final chave = p[1].trim();
    final traducao = p[2].replaceAll(r'\n', '\n').replaceAll(r'\t', '\t');

    if (p.length == 4 && p[3].trim() == 'interpolado') {
      // **Registrado, não traduzido.** A chave entra nos dois mapas porque o
      // texto é o valor em inglês e a pessoa precisa dele; a reescrita do fonte
      // é que fica para a mão.
      enPorChave[chave] = texto;
      pt[chave] = traducao;
      interpolados.add('$chave  "$texto"');
      textoParaChave[texto] = chave;
      continue;
    }

    // **Texto repetido só é problema quando as traduções divergem.** Há textos
    // que aparecem em dois lugares com a mesma tradução — "Cancel" em três
    // diálogos — e é isso que torna o casamento por texto seguro.
    final anterior = textoParaChave[texto];
    if (anterior != null && pt[anterior] != traducao) {
      stderr.writeln('ERRO: o mesmo texto tem duas traduções\n'
          '  "$texto"\n'
          '  $anterior: ${pt[anterior]}\n'
          '  $chave: $traducao\n'
          'O casamento por texto precisa de volta a posição no fonte.');
      exit(1);
    }
    if (pt.containsKey(chave)) {
      // **Chave que já existe é reaproveitada, não é erro — mas só se o valor
      // bater.** `close` e `mc_runtime_local` já estavam no mapa de uma rodada
      // anterior, com as duas traduções, e recusar a linha inteira obrigava a
      // editar o fonte à mão. O que não pode é a chave ficar com o valor velho
      // enquanto o TSV promete outro: a tela mostra o do mapa, e a segunda
      // tradução é a que ela mostra. Por isso a conferência é por chave e o
      // erro diz as duas.
      final jaPt = pt[chave];
      final jaEn = enPorChave[chave];
      if (jaPt != traducao || (jaEn != null && jaEn != texto)) {
        stderr.writeln('ERRO: a chave $chave já existe com outro valor\n'
            '  no mapa: EN=${jaEn ?? "(ausente)"}  PT=$jaPt\n'
            '  no TSV:  EN=$texto  PT=$traducao\n'
            'Renomeia a chave ou corrige o valor — as duas não podem coexistir.');
        exit(1);
      }
    }
    if (anterior == null) textoParaChave[texto] = chave;
    enPorChave[chave] = texto;
    pt[chave] = traducao;
  }
  stdout.writeln('traducoes lidas: ${pt.length}');

  // ── a reescrita do fonte ──
  final pendente = <String, String>{};
  final porArquivo = <String, _Arquivo>{};
  for (final f in _arquivos()) {
    porArquivo[f.path] = _Arquivo(f.path, f.readAsStringSync());
  }

  var reescritos = 0;
  var semChave = 0;
  for (final arquivo in porArquivo.values) {
    arquivo.achados(textoParaChave, interpolados);
    final n = arquivo.substituir();
    if (n > 0) {
      pendente[arquivo.path] = arquivo.buf;
      reescritos += n;
    }
    if (arquivo.semChave.isNotEmpty) semChave += arquivo.semChave.length;
  }
  pendente.forEach((p, src) => File(p).writeAsStringSync(src));
  stdout.writeln('literais reescritos: $reescritos');

  // **O mapa é gravado ANTES de qualquer saída com erro.** A ordem anterior
  // escrevia o fonte, contava o que faltava e saía com 1 — e `_acrescentar`
  // estava depois, então nenhuma chave nova chegava ao mapa. O sintoma era
  // `l10n_keys_test` accusing 40 chaves `.tr` que não existiam em nenhum dos
  // dois idiomas, com o fonte já reescrito e o analyzer em zero: o estado
  // **inconsistente é o estado de saída**, e foi preciso desfazer as duas
  // metades separadamente.
  //
  // E a contagem precisa bater nos dois idiomas antes disso: são duas entradas
  // por chave, e metade delas é o valor em inglês.
  if (enPorChave.length != pt.length) {
    stderr.writeln('ERRO: ${enPorChave.length} chaves com texto em inglês para '
        '${pt.length} traduções.');
    exit(1);
  }
  _acrescentar('en_US', enPorChave);
  _acrescentar('pt_BR', pt);
  stdout.writeln('mapa de traducoes reescrito');

  // As pendências são relatório, e não motivo para não gravar o que já está
  // certo. Um literal sem chave é texto em inglês na tela — grave como está.
  if (semChave > 0) {
    final todos = porArquivo.values.expand((a) => a.semChave).toList();
    stderr.writeln('\n$semChave literais de tela em inglês SEM chave no '
        'arquivo — nenhum foi reescrito:\n  ${todos.join('\n  ')}');
    exit(1);
  }
  if (interpolados.isNotEmpty) {
    stdout.writeln('\ninterpolados — ${interpolados.length} reescrita manual '
        'com preencher():\n  ${interpolados.join('\n  ')}');
  }
}

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

/// Um arquivo, seus literais de tela em inglês e o buffer que está mudando.
class _Arquivo {
  _Arquivo(this.path, this.src);
  final String path;
  String src;
  String buf = '';

  /// Preenche [buf] com as substituições, sem tocar o disco.
  ///
  /// **A ordem é por posição decrescente, e é por isso que ela é decrescente.**
  /// Cada substituição muda o comprimento do buffer, e aplicar de cima para baixo
  /// deixa os índices das de baixo intactos. A versão anterior aplicava em ordem
  /// de arquivo e produziu **111.828 linhas inseridas** em catorze arquivos: a
  /// lista de achados é montada percorrendo os rótulos um a um — todos os
  /// `Text`, depois todos os `title` — e reverter inverte a ordem *dos rótulos*,
  /// não a das posições.
  int substituir() {
    buf = src;
    final achados = _pendentes
      ..sort((a, b) => b.ini.compareTo(a.ini));
    for (final a in achados) {
      // **O `fim` é relido no buffer atual, e não o da descoberta.** Processar
      // de trás para a frente mantém `ini` válido — tudo que já mudou está
      // acima dele — mas o `fim` guardado é índice do **fonte original**, e uma
      // substituição anterior pode ter deslocado o que está entre `ini` e `fim`.
      // É o caso do literal aninhado: `'${x ? 'a' : 'b'}'` tem o `fim` do externo
      // **depois** do interno, então trocar o externo primeiro move o índice do
      // interno e a troca seguinte escreve no lugar errado. O sintoma foi um
      // `RangeError (end): Invalid value: Not in inclusive range` numa reescrita
      // de 172 literais — que pelo menos não é silencioso.
      final (joined, fim) = TextLanguage.juntarSegmentos(buf, a.ini);
      if (joined.isEmpty) continue;
      // O `const` precisa sair: `'chave'.tr` é método de runtime e
      // `const Text('chave'.tr)` não compila.
      //
      // **Apaga-se a palavra `const` e nada mais.** Três versões anteriores
      // repunham um prefixo, e as três perderam alguma coisa: a primeira trocava
      // `const Text(` inteiro e deixava `label: 'chave'.tr),` (118 erros de
      // sintaxe); a segunda repunha `Nome(` e **perdia os argumentos nomeados**,
      // porque eles estão entre o `(` e o literal — `InputDecoration(labelText:
      // 'x')` virava `InputDecoration('chave'.tr')`; a terceira, achando que
      // uma lista literal não tem construtor para repor, não repôs nada e
      // **apagou as linhas entre `const [` e o literal**, o que em
      // `cloud_model_controller.dart` desmontou a lista de provedores e deixou
      // `final providers = 'cloud_nim'.tr,`. Apagar só a palavra é o único jeito
      // que não precisa saber o que havia no meio.
      final g = _governanteConst(buf, a.ini);
      final semConst = g == null
          ? buf.substring(0, a.ini)
          : buf.substring(0, g.inicio) +
              g.troca +
              buf.substring(g.fimDaPalavra, a.ini);
      buf = "$semConst'${a.chave}'.tr" + buf.substring(fim);
    }
    return achados.length;
  }

  final List<_Achado> _pendentes = [];



  /// Acha os literais de tela em inglês deste arquivo que têm chave.
  ///
  /// **A chave vem do casamento por TEXTO, lido do arquivo de traduções** — e o
  /// valor em inglês é conferido contra o que está no fonte. Um literal que não
  /// casa é **contado e listado**, não pulado em silêncio: uma chave no arquivo
  /// que não casa é ou um texto que já foi traduzido por outro caminho, ou um
  /// texto que ninguém viu — e os dois precisam de um número, não de um buraco.
  void achados(Map<String, String> textoParaChave, List<String> interpolados) {
    final re = RegExp("\\'([^\\'\\n]{2,240})\\'|\"([^\"\\n]{2,240})\"");
    // **`vistos` é POR ARQUIVO**, e um literal adjacente tem um inicio por
    // segmento: marcar só o primeiro e o fim deixa cada inicio do meio
    // reportar a mesma frase sem o primeiro segmento, que é texto que não existe
    // na tela. Medido: 87 grupos com 155 inicios extras. Ver `juntarSegmentos`.
    final vistos = <int>{};
    for (final m in re.allMatches(src)) {
      if (!vistos.add(m.start)) continue;
      final inicios = <int>[];
      final (joined, fim) =
          TextLanguage.juntarSegmentos(src, m.start, inicios: inicios);
      if (joined.isEmpty) continue;
      vistos.addAll(inicios);
      vistos.add(fim);
      final texto = joined.trim();
      if (texto.length < 3) continue;
      if (!TextLanguage.pareceInglesAmplo(texto)) continue;
      // **Já é `.tr`?** O que vem depois da aspa é o que decide. Sem esta
      // guarda, `'settings'.tr` vira `'nav_settings'.tr.tr`, que **compila** e
      // mostra a chave no lugar do texto — e nenhum teste reclama, porque o
      // analyzer não tem o que dizer e a chave existe no mapa.
      var k = m.end;
      while (k < src.length && ' \n\t'.contains(src[k])) {
        k++;
      }
      if (src.startsWith('.tr', k)) continue;
      // **Chave de payload da API não é texto.** `json['loaded']` e
      // `json['error']` são campos do que o servidor devolve; traduzi-los deixa
      // o painel vazio sem nenhum erro.
      if (src.startsWith(']', k)) continue;
      if (!TextLanguage.eTextoDeTela(texto, src, m.start)) continue;
      final chave = textoParaChave[texto];
      if (chave == null) {
        semChave.add('$path  "$texto"');
        continue;
      }
      // **Interpolado não se reescreve.** A chave existe (o arquivo a traz) e o
      // valor em inglês também, mas trocar o literal inteiro apagaria a parte que
      // muda. A edição é `preencher('chave', {...})`, por mão.
      if (texto.contains(r'$')) {
        interpolados.add('$path  $chave  "$texto"');
        continue;
      }
      _pendentes.add(_Achado(m.start, fim, chave));
    }
  }

  /// Literais de tela em inglês **sem chave** no arquivo de traduções.
  final List<String> semChave = [];
}

class _Achado {
  _Achado(this.ini, this.fim, this.chave);
  final int ini;
  final int fim;
  final String chave;
}

/// O `const` que governa um literal em [ini], e o construtor que ele qualifica.
/// O `const` que governa um literal em [ini].
///
/// Carrega **as duas pontas da palavra**, e não um prefixo para repor: o que
/// precisa sair do fonte é o `const` e o espaço depois dele, e nada do que está
/// entre ele e o literal.
class _Governante {
  _Governante(this.inicio, this.fimDaPalavra, this.troca);
  final int inicio;

  /// Logo depois do `const` **e do branco que o segue** — cortar aqui é o que
  /// transforma `const Text(` em `Text(` em vez de ` Text(`.
  final int fimDaPalavra;

  /// O que entra no lugar da palavra.
  ///
  /// **Apagar serve para qualificar uma construção, e não para declarar uma
  /// variável.** `const Text('x')` → `Text('x')` compila. `static const _misc =
  /// <String, String>{…}` → `static _misc = <String, String>{…}` **não**:
  /// `missing_const_final_var_or_type`, porque um campo estático sem tipo nem
  /// modificador não é declaração. Aí o lugar do `const` é `final`, que é a
  /// mesma garantia para um valor que só é atribuído na inicialização.
  final String troca;
}

/// O `const` que governa um literal em [ini], e o construtor que ele qualifica.
///
/// **A regra é "o literal está dentro da lista de argumentos ou de itens do
/// `const`", e nada menos que isso.** A versão anterior aceitava só equilíbrio
/// (`abre` = `fecha`) entre o `const` e o literal, o que é uma condição mais
/// frouxa do que parece: um `const` **vizinho** também fica equilibrado.
///
/// ```dart
/// color: isDark ? const Color(0xFF0F0F11) : _busy ? A : 'running',
/// ```
///
/// `const Color(0xFF0F0F11)` abre e fecha, e o que vem depois é o ramo `:` de
/// um ternário — equilibrado, e do outro lado de um `const` que **não governa
/// nada**. A ferramenta tirou o `const Color(0xFF0F0F11) : ` inteiro e deixou
/// `('soc_running'.tr: _serverUp`, e **386 linhas de widget sumiram** do
/// `litert_head_console.dart` num único arquivo. É o pior modo de falha possível
/// num reescritor: não é sintaxe inválida, é código válido que faz outra coisa.
///
/// Por isso a condição é a **profundidade**, não o saldo: depois da abertura, a
/// profundidade tem que ficar **≥ 1 até o literal**. `const InputDecoration(
/// labelText: 'x')` e `const [ CloudProviderInfo(description: 'x'), … ]` passam;
/// o `Color` do ternário volta a 0 antes do literal e é recusado.
///
/// Aceita as três aberturas porque o repositório usa as três, e cada uma devolve
/// um construtor diferente: `(` devolve `Nome(`, e `[`/`{` **não devolvem nada** —
/// uma lista literal não tem construtor para repor, e `dart format` não exige
/// `const` em lista nem em mapa.
_Governante? _governanteConst(String buf, int ini) {
  final antes = buf.substring(0, ini);
  // O `const` **como palavra**: `myconst` e `constante` não qualificam nada, e
  // um `contains('const')` pegaria os dois.
  final re = RegExp(r'(?<![A-Za-z0-9_])const(?![A-Za-z0-9_])');
  for (final m in re.allMatches(antes).toList().reversed) {
    // O `const` precisa qualificar **algo**: identificador seguido de abertura.
    var k = m.end;
    while (k < ini && ' \n\t'.contains(antes[k])) {
      k++;
    }
    while (k < ini && RegExp(r'[A-Za-z0-9_]').hasMatch(antes[k])) {
      k++;
    }
    // **Identificador seguido de `=` é DECLARAÇÃO, não qualificação.** O nome da
    // declaração é o identificador que acabou de ser lido; a abertura que
    // governa o literal é o que vem **depois** do `=` e do tipo.
    var nome = antes.substring(m.end, k).trim();
    while (k < ini && ' \n\t'.contains(antes[k])) {
      k++;
    }
    final declara = k < ini && antes[k] == '=';
    // **O `=` entre o nome e o tipo.** `static const _misc = <String, String>{…}`
    // é a forma das facetas do hub no `hf_search_sheet.dart`, e sem pular o `=`
    // o `abre` dá `=`, que não é abertura nenhuma, o `const` não é reconhecido e
    // a `.tr` fica dentro de um `const` — `const_eval_extension_method`.
    if (k < ini && antes[k] == '=') {
      k++;
      while (k < ini && ' \n\t'.contains(antes[k])) {
        k++;
      }
    }
    // **`<…>` entre o `const` e a abertura.** `static const <String, String>{
    // … }` é a mesma família sem o `=`, e sem este salto dá o mesmo erro.
    if (k < ini && antes[k] == '<') {
      var profundidade = 0;
      while (k < ini) {
        if (antes[k] == '<') profundidade++;
        if (antes[k] == '>') {
          profundidade--;
          if (profundidade == 0) {
            k++;
            break;
          }
        }
        k++;
      }
    }
    while (k < ini && ' \n\t'.contains(antes[k])) {
      k++;
    }
    if (k >= ini) continue;
    final abre = antes[k];
    if (abre != '(' && abre != '[' && abre != '{') continue;
    if (!_dentroDaAbertura(antes.substring(k, ini))) continue;
    // O corte vai até depois do primeiro branco: `const Text(` → `Text(`.
    var fim = m.end;
    while (fim < ini && (antes[fim] == ' ' || antes[fim] == '\t')) {
      fim++;
    }
    // Declaração de variável/campo recebe `final`, e não nada — ver [_Governante].
    assert(!declara || nome.isNotEmpty, 'const sem nome não declara nada');
    return _Governante(m.start, fim, declara ? 'final ' : '');
  }
  return null;
}

/// O trecho está **inteiro dentro** de uma lista de argumentos ou de itens?
///
/// Começa na abertura (a primeira posição) e nunca pode voltar a zero antes do
/// fim — que é o que separa `('x')` do argumento de quem chamou de
/// `) : _busy ? A : 'x')`, o ramo de um ternário cujo `const` já fechou.
bool _dentroDaAbertura(String trecho) {
  var profundidade = 0;
  var i = 0;
  while (i < trecho.length) {
    final c = trecho[i];
    if (c == "'" || c == '"') {
      final delim = c;
      i++;
      while (i < trecho.length) {
        if (trecho[i] == r'\' && i + 1 < trecho.length) {
          i += 2;
          continue;
        }
        if (trecho[i] == delim) {
          i++;
          break;
        }
        i++;
      }
      // Um literal fecha logo antes do fim, e `i` pode ter passado dele.
      if (profundidade < 1) return false;
      continue;
    }
    if (c == '(' || c == '[' || c == '{') {
      profundidade++;
    } else if (c == ')' || c == ']' || c == '}') {
      profundidade--;
      if (profundidade < 1) return false;
    }
    i++;
  }
  return profundidade >= 1;
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

  // O fim do mapa é o `\n    }` que fecha este literal, e não o primeiro `}`
  // do arquivo: há `}` dentro de interpolação e dentro de strings.
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
  final linhas = <String>[
    '      // ── Texto de tela da varredura ampla (tool/broad_inline.tsv) ────',
    '      // O casamento é por TEXTO e nunca por `arquivo:linha`: reescrever um',
    '      // literal adjacente apaga as linhas do meio, e uma posição medida',
    '      // antes da primeira reescrita aponta para o lugar errado — e a',
    '      // ferramenta aceitaria, porque ela confia na posição.',
  ];
  // **Chave que já está no mapa não é escrita de novo.** Um literal de mapa
  // aceita chave repetida e o Dart não reclama — a segunda sobrescreve a
  // primeira, o app funciona e o arquivo mente. `l10n_keys_test` conta
  // ocorrências no fonte, e é o único que vê.
  final corpoTexto = src.substring(ini, fim);
  for (final entrada in novas.entries) {
    final chave = entrada.key;
    final valor = entrada.value;
    final chaveEsc = _literal(chave);
    if (corpoTexto.contains('$chaveEsc:')) continue;
    linhas.add('      $chaveEsc: ${_quebra(valor)},');
  }
  if (linhas.length <= 4) return; // só havia o cabeçalho: nada a escrever
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
/// `"…aparelhos compouca RAM"` no catálogo.
String _quebra(String texto) {
  const largura = 66;
  // **Normaliza antes de escapar.** A entrada vem em duas representações: o
  // inglês é extraído do fonte e sai com quebra real; a tradução vem do TSV, que
  // é uma entrada por linha e portanto carrega `\n` como escape de duas letras.
  // Converter os dois para caractere aqui é o que faz `\n` virar `\n` no fonte e
  // a quebra real virar `\n` também — sem isso a primeira vira `\\n` (barra mais
  // n, lida como texto) e a segunda vira uma quebra de linha dentro do literal,
  // que não compila.
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
