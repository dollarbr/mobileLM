import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/l10n/app_translation.dart';

/// The pt_BR map must cover **every** key the app asks for.
///
/// ## Why this test exists
///
/// It exists because it did not. `lib/l10n/app_translation.dart` had 277 keys and
/// **38 of the keys the app actually calls were not in it** — `tool_round_trips`
/// among them, on a Settings item, and `mobile_lm` in the About screen. GetX
/// returns the key itself for a key it does not have, so none of this threw, none
/// of it warned, and every one of those 38 strings rendered as its own English
/// identifier inside a Portuguese UI.
///
/// The shape of the bug is what makes it worth a test rather than just a fix:
/// adding a `.tr` call is invisible, the string it asks for is nowhere in
/// review, and the file that would say so is three directories away. Nothing
/// about writing the call site fails. So the check has to be mechanical or it
/// will not happen again by accident.
///
/// ## What it cannot see
///
/// Only **literal** keys. A call like `'prefix_$name'.tr` assembles the key at
/// runtime and is invisible here. The last test lists what it found, so a human
/// knows the coverage boundary instead of assuming it.
///
/// ## Why it reads the files instead of importing something
///
/// A list of keys inside the test would have to be maintained by hand, and a
/// hand-maintained list is the same failure wearing a different hat. Reading
/// `lib/` makes the check true by construction, and the two "the scan actually
/// finds something" tests exist because a regex that silently matches nothing
/// turns this whole file green while it protects nothing.
void main() {
  /// `lib/`, from the package root that `flutter test` runs in.
  final libDir = Directory('lib');
  final mapFile = File('lib/l10n/app_translation.dart');

  /// `'some_key'.tr` and `"some_key".tr`, and nothing built at runtime.
  ///
  /// Raw **triple** quotes because the pattern needs a bare `"` inside: a raw
  /// `r"…"` still ends at the first `"`, and `\"` inside it is backslash-then-
  /// quote as far as Dart is concerned.
  ///
  /// **Um comentário não é uma chamada.** Este padrão casa o exemplo
  /// `'chave'.tr` que aparece na explicação de um `const` removido, e a chave
  /// `chave` não existe — o teste acusou duas faltando que só existem num
  /// comentário. A leitura é idêntica nas duas situações, então o padrão não
  /// tem como distinguir: quem tem de distinguir é o teste, filtrando o que
  /// veio de uma linha de comentário.
  final literal = RegExp(r'''(['"])([A-Za-z0-9_]+)\1\s*\.\s*tr\b''');

  /// **Uma linha que é só comentário**, para descartar os falsos achados acima.
  final linhaDeComentario = RegExp(r'^\s*//');

  /// `replaceAll('\$min', …)` — a needle written with a literal `$`.
  final needle = RegExp(r'''replaceAll\(\s*['"]\\?\$([A-Za-z0-9_]+)''');

  /// Um idioma só, recortado do arquivo pelo **nome do mapa**.
  ///
  /// **Ler o arquivo inteiro não serve desde que existem dois idiomas.** Com
  /// `en_US` antes de `pt_BR` no fonte, um leitor sem recorte devolve o
  /// `pt_BR` para as chaves que existem nos dois mapas — porque a segunda
  /// entrada sobrescreve a primeira no `Map` — e o mapa inglês nunca é
  /// auditado. Passou por sorte: `pt_BR` está por último. Se alguém reordenar,
  /// o teste continua verde e para de olhar o idioma padrão do app.
  Map<String, String> readMap(String lang) {
    final source = mapFile.readAsStringSync();
    // O mapa é um literal Dart, não JSON: aspas simples e `\$` dentro dos
    // valores. Ler como texto mantém este arquivo sem depender do analyzer.
    //
    // **Casado no arquivo inteiro, e não linha a linha — e isso é um bug que
    // este teste já pagou uma vez.** Uma regex `^\s*'key':\s*'...'` ancorada por
    // linha pulava silenciosamente todo valor quebrado em duas linhas de
    // fonte — cinco deles, todos meus — e a auditoria reportava essas cinco
    // chaves como ausentes de um mapa onde estavam. Um parser que descarta em
    // silêncio as entradas que não consegue ver é a mesma falha que um mapa
    // sem elas, um nível acima; por isso a quebra de linha faz parte do padrão
    // e há um teste abaixo nomeando as chaves quebradas à mão.
    final abre = source.indexOf("'$lang': {");
    if (abre < 0) return const {};
    // O fim é o fechamento do mapa: 4 espaços, `}`, e não uma chave — porque
    // uma chave do próprio mapa também é uma linha que começa com 4 espaços e
    // uma aspa.
    int fim = source.length;
    for (var i = abre; i < source.length; i++) {
      if (source[i] == '}' && source.substring(0, i).endsWith('\n    ')) {
        fim = i;
        break;
      }
    }
    final bloco = source.substring(abre, fim);
    final out = <String, String>{};
    final pair = RegExp(r'''([A-Za-z0-9_]+)':\s*'((?:[^'\\]|\\.)*)''');
    for (final m in pair.allMatches(bloco)) {
      out[m.group(1)!] = m.group(2)!;
    }
    return out;
  }

  Map<String, String> readPtBr() => readMap('pt_BR');

  /// As chaves que a auditoria de `'literal'.tr` **não alcança**, porque a
  /// tradução acontece sobre uma **variável**.
  ///
  /// `Text(e.value.tr)` e `f.label` (de `HfFormat`) são `.tr` em runtime: o
  /// regex de [literal] só casa `'chave'.tr` com a chave escrita no fonte, e
  /// nenhuma delas está. A consequência é a mais silenciosa do GetX — chave
  /// faltando **renderiza o próprio identificador**, e o `l10n_keys_test`
  /// continua verde porque nunca viu a chave.
  ///
  /// A defesa é ler o fonte desses mapas e conferir cada valor contra os dois
  /// idiomas, que é a **afirmação oposta** à que `scanUsages` faz.
  List<String> chavesIndiretas() {
    final hf = File('lib/views/hf_search_sheet.dart').readAsStringSync();
    final svc = File('lib/services/hf_search_service.dart').readAsStringSync();
    final out = <String>[];
    for (final mapa in const ['_pipelines', '_misc']) {
      final bloco = RegExp('static const $mapa = <String, String>\\{(.*?)\\n  \\};',
              dotAll: true)
          .firstMatch(hf);
      if (bloco == null) {
        throw StateError('o mapa $mapa sumiu de hf_search_sheet.dart — este '
            'teste audita a lista por nome, e uma lista sumida é zero chaves '
            'com o teste verde');
      }
      for (final m
          in RegExp(r":\s*'([a-z0-9_]+)'\s*,").allMatches(bloco.group(1)!)) {
        out.add(m.group(1)!);
      }
    }
    // **Os dois mapas da janela System One entram aqui pelo mesmo motivo.**
    // `SystemOneReadout.labelKey` e `noteKey` e `kAnswerTypeKey` guardam chaves
    // que a tela pinta com `map[valor]!.tr`, e nenhuma delas é literal no fonte
    // — então a auditoria de `.tr` literal não as vê. A primeira versão deste
    // arquivo auditou só os dois mapas do `hf_search_sheet.dart`, e uma mutação
    // trocando `'soc_readout_logit'` por uma chave inexistente deixou os **11
    // testes verdes**: a chave sumiria do arquivo e renderizaria o próprio
    // identificador numa tela em português, que é a falha exata que o seletor de
    // idioma veio fechar.
    //
    // O parser é o do `hf_search_sheet.dart` — `static const NOME = <…>{…}` até
    // `};` — porque é o formato que o fonte usa, e um formato diferente seria um
    // segundo detector que diverge em silêncio. A âncora está no teste irmão.
    final soc = File('lib/services/system_one.dart').readAsStringSync();
    for (final mapa in const [
      'kReadoutLabelKey',
      'kReadoutNoteKey',
      'kAnswerTypeKey',
    ]) {
      // The type comes before the name — `const Map<K, V> name = {` — and a
      // pattern that assumed `const name = <` would match **zero** maps and
      // then throw here on the first one, which reads as "the map is gone"
      // rather than "the regex is wrong". A detector that finds nothing must
      // not be able to say it found nothing.
      final bloco = RegExp(
              r'const\s+[A-Za-z_][A-Za-z0-9_]*\s*<[^>]*>\s+' '$mapa' r'\s*=\s*\{(.*?)\n\};',
              dotAll: true)
          .firstMatch(soc);
      if (bloco == null) {
        throw StateError('o mapa $mapa sumiu de system_one.dart — este teste '
            'audita a lista por nome, e uma lista sumida é zero chaves com o '
            'teste verde');
      }
      for (final m in RegExp(r":\s*'([a-z0-9_]+)'").allMatches(bloco.group(0)!)) {
        out.add(m.group(1)!);
      }
    }

    // **O enum é lido token a token, e não por regex.** A primeira versão usou
    // `any\('([a-z0-9_]+)',` e casava **zero** vezes num fonte onde o token
    // estava plainly escrito — `any('hf_any', '')` —, então a auditoria do enum
    // não via nada e o teste passava com uma chave que não existe. Um detector
    // que não casa é indistinguível de um detector que não há, e é por isso que
    // [vistas] é conferido contra duas âncoras que o fonte usa por nome.
    final linha = svc.split('\n').firstWhere(
      (l) => l.trimLeft().startsWith('any('),
      orElse: () => throw StateError(
          'a entrada `any(` do enum HfFormat sumiu de hf_search_service.dart — '
          'e sem ela o enum não é auditado, com o teste verde'),
    );
    final abreAspa = linha.indexOf("'");
    final fechaAspa = linha.indexOf("'", abreAspa + 1);
    out.add(linha.substring(abreAspa + 1, fechaAspa));
    return out;
  }
  List<File> dartFiles() => libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  /// Every literal `.tr` key in the app, with the files that ask for it.
  Map<String, List<String>> scanUsages() {
    final out = <String, List<String>>{};
    for (final f in dartFiles()) {
      final src = f.readAsStringSync();
      for (final m in literal.allMatches(src)) {
        // **A linha do match tem de ser código.** O padrão casa o exemplo
        // `'chave'.tr` de um comentário que explica um `const` removido, e essa
        // chave não existe no mapa. Sem este filtro o teste acusa duas faltando
        // por causa da própria documentação do motivo.
        final linha = src.lastIndexOf('\n', m.start) + 1;
        if (linhaDeComentario.hasMatch(src.substring(linha, m.start))) {
          continue;
        }
        (out[m.group(2)!] ??= []).add(f.path);
      }
    }
    return out;
  }

  /// For every key whose translation is assembled with `replaceAll`, the
  /// placeholders the code is going to look for.
  ///
  /// Two steps on purpose: the needle can appear more than once for one key
  /// (`enter_value_between` replaces `$min` **and** `$max`), so the tail after the
  /// `.tr` call is scanned, not just the first match.
  Map<String, Set<String>> scanPlaceholders() {
    final out = <String, Set<String>>{};
    for (final f in dartFiles()) {
      final src = f.readAsStringSync();
      for (final m in literal.allMatches(src)) {
        final linha = src.lastIndexOf('\n', m.start) + 1;
        if (linhaDeComentario.hasMatch(src.substring(linha, m.start))) {
          continue;
        }
        final tail = src.substring(m.end);
        // Bounded by the **next key**, not by the end of the statement. The
        // `confirm_delete` dialog does `Text('confirm_delete'.tr)` as the title
        // and then, as the content, `Text('${'delete_name'.tr}'.replaceAll(
        // '$name', …))` — so a tail cut at the `;` swept the second key's
        // `replaceAll` into the first key's requirements, and the audit then
        // demanded that "Confirmar exclusão" contain a `$name`. A key boundary
        // is where the ownership of a `replaceAll` changes hands.
        final ateSemicolon = tail.indexOf(';');
        final proxChave = literal.firstMatch(tail);
        var limite = ateSemicolon;
        if (proxChave != null && (limite == -1 || proxChave.start < limite)) {
          limite = proxChave.start;
        }
        final trecho = limite == -1 ? tail : tail.substring(0, limite);
        for (final n in needle.allMatches(trecho)) {
          (out[m.group(2)!] ??= {}).add(n.group(1)!);
        }
      }
    }
    return out;
  }

  test('the map is where this test looks for it', () {
    // A path that silently matches nothing would make every other test here
    // pass by finding no usages at all — the failure mode of a test about
    // missing data.
    expect(libDir.existsSync(), isTrue,
        reason: 'tests run from the package root; lib/ must be right there');
    expect(mapFile.existsSync(), isTrue);
  });

  test('the scan actually finds usages', () {
    expect(scanUsages().length, greaterThan(150),
        reason: 'a regex that stopped matching would make the audit below '
            'report zero missing keys and pass — the worst possible outcome, '
            'because the bug it guards is invisible to the user');
  });

  test('the map is readable as text, not silently empty', () {
    expect(readPtBr().length, greaterThan(300),
        reason: 'if the pair regex stopped matching, "every key exists" would '
            'pass for the same reason a broken scan passes');
  });

  test('a value wrapped across two source lines is still read', () {
    // The regression this file was corrected for. These five are wrapped in
    // `app_translation.dart` because they are long sentences, and a per-line
    // reader reported every one of them as absent from the map.
    final map = readPtBr();
    for (final k in const [
      'gpu_is_experimental',
      'recommended_max_8',
      'cloud_models_support_images_and_text_files',
      'some_settings_only_load_at_app_start',
      'unload_before_loading_another',
    ]) {
      expect(map.containsKey(k), isTrue,
          reason: '$k tem o valor quebrado em duas linhas no mapa, e um leitor '
              'por linha o perderia — e o auditoria o acusaria de estar '
              'faltando numa chave que existe');
      expect(map[k]!.length, greaterThan(20),
          reason:
              'e o valor lido tem de ser a frase inteira, não um fragmento');
    }
  });

  test('every literal .tr key exists in BOTH maps', () {
    // **Os dois, e não só o pt_BR.** O GetX devolve a própria chave para uma
    // tradução que não existe, e nenhuma exceção lançou: foi assim que 38
    // chaves apareceram como `tool_round_trips` numa tela portuguesa sem
    // ninguém notar. Com EN como padrão, uma chave faltando nele aparece num
    // app que se dizbilíngue — e é metade do defeito de novo.
    for (final lang in const ['en_US', 'pt_BR']) {
      final map = readMap(lang);
      expect(map, isNotEmpty,
          reason: 'o recorte de $lang devolveu nada, e todo teste abaixo '
              'passaria por não ter o que auditar');
      final faltando = <String, String>{};
      for (final e in scanUsages().entries) {
        if (!map.containsKey(e.key)) faltando[e.key] = e.value.first;
      }
      expect(
        faltando,
        isEmpty,
        reason: 'Estas ${faltando.length} chaves são chamadas com .tr e não '
            'existem no mapa $lang, então o GetX devolve a própria chave e o '
            'usuário lê o identificador na tela:\n'
            '${faltando.entries.map((e) => '  ${e.key}  (${e.value})').join('\n')}',
      );
    }
  });

  test('a value is never the key it answers to', () {
    // The shape of the bug itself: a translation that repeats its key renders as
    // English no matter how many keys exist. This catches the "fix" of adding
    // `'foo': 'foo'`.
    final identicas = readPtBr()
        .entries
        .where((e) => e.value == e.key)
        .map((e) => e.key)
        .toList();
    expect(identicas, isEmpty,
        reason:
            'estas traduções são o próprio nome da chave, que é exatamente o '
            'defeito que o teste anterior existe para evitar');
  });

  test('a translated string carries no leftover English identifier', () {
    // The other half of the same bug: a key that *is* in the map but whose
    // translation was never written down, so the value is the identifier.
    //
    // The tell is the **underscore**. A real Portuguese value never has one —
    // `segundos` is a single lowercase word and is perfectly translated, so
    // flagging "any value that looks like a bare word" flagged correct entries.
    // What cannot be prose is `foo_bar`, which is the shape a leaked key has.
    final suspeitas = readPtBr()
        .entries
        .where(
            (e) => RegExp(r'^[a-z0-9]+(_[a-z0-9]+)+$').hasMatch(e.value.trim()))
        .map((e) => '${e.key} = "${e.value}"')
        .toList();
    expect(suspeitas, isEmpty,
        reason:
            'valores com underscore não são português, são a chave repetida: '
            'alguém "traduziu" a chave para a própria chave\n'
            '${suspeitas.join('\n')}');
  });

  test('a key the code replaces into still carries the placeholder', () {
    // `enter_value_between` and `delete_name` are the **first** keys in this map
    // to have a placeholder, so there is no precedent in the file to copy and no
    // compiler that would object to a missing one: `replaceAll` on a string
    // without the needle is a no-op, and the user sees a raw `$min` where a
    // number should be.
    final usados = scanPlaceholders();
    expect(usados, isNotEmpty,
        reason: 'if the needle regex stopped matching, the check below covers '
            'nothing — the same failure mode as the usage scan');

    final semPlaceholder = <String>[];
    // **Nos dois idiomas.** O consumidor é o mesmo código com o mesmo
    // `replaceAll`, então um placeholder que sobrevive em português e se perde
    // na tradução mostra `$min` cru na tela em inglês — que é metade dos
    // usuários agora que EN é o padrão.
    for (final lang in const ['en_US', 'pt_BR']) {
      final porIdioma = readMap(lang);
      for (final e in usados.entries) {
        for (final p in e.value) {
          if (!porIdioma.containsKey(e.key) || !porIdioma[e.key]!.contains(p)) {
            semPlaceholder.add('$lang ${e.key}: o código troca "\$$p", mas o '
                'valor é "${porIdioma[e.key] ?? "(ausente)"}"');
          }
        }
      }
    }
    expect(semPlaceholder, isEmpty,
        reason: 'o consumidor faz replaceAll e o valor não tem o texto a '
            'substituir, então o placeholder aparece cru na tela:\n'
            '${semPlaceholder.join('\n')}');
  });

  test('the map the app registers is the one this file audits', () {
    // The app resolves `locale:` from a **saved preference**, not from
    // `Get.deviceLocale`, and registers **two** maps. If either registered key
    // were renamed, every value here would be a lookup miss at runtime and this
    // suite would still be green — so the check is on the registered names, not
    // on the file.
    final t = AppTranslation().keys;
    expect(t.keys, contains('pt_BR'));
    expect(t.keys, contains('en_US'));
    expect(t['pt_BR'], isNotNull);
    expect(t['en_US'], isNotNull);
    expect(t['pt_BR']!.length, greaterThanOrEqualTo(300));
    expect(t['en_US']!.length, greaterThanOrEqualTo(300));
  });

  test('the coverage boundary: keys assembled at runtime are not checked', () {
    // Printed, not asserted. The tell for a genuinely dynamic key is a `$`
    // **inside the quotes**: `'prefix_$name'.tr`. The first version of this
    // detector matched `${'runs'.tr` and listed eleven keys as uncovered — but
    // the `$` there is the interpolation sigil, `'runs'` is a literal, and the
    // audit above covers it. Reporting a covered key as a gap is how a coverage
    // note stops being believable.
    final dinamicas = <String>[];
    for (final f in dartFiles()) {
      final src = f.readAsStringSync();
      for (final m in RegExp(r'''['"][^'"\n]*\$[^'"\n]*['"]\s*\.\s*tr\b''')
          .allMatches(src)) {
        dinamicas.add('${f.path}: ${m.group(0)!.replaceAll('\n', ' ')}');
      }
    }
    expect(dinamicas, isEmpty,
        reason: 'a auditoria acima só vê chaves literais, e estas '
            '${dinamicas.length} são montadas em runtime — cada uma precisa de '
            'olho humano:\n${dinamicas.join('\n')}');
  });

  test('toda chave de mapa de faceta e do enum existe nos DOIS idiomas', () {
    // **Irmão que prova que ele ainda vê alguma coisa.** Se `chavesIndiretas()`
    // devolvesse vazio por um erro de regex, `expect(faltando, isEmpty)` passaria
    // e nada anunciaria. Duas chaves que o fonte usa **por nome** são a âncora:
    // uma já estava escrita na auditoria ('text-generation') e a outra entrou
    // agora ('mergekit'), e as duas precisam continuar lá.
    final vistas = chavesIndiretas();
    expect(vistas, contains('hf_task_text_generation'));
    expect(vistas, contains('hf_mergekit'));
    // As âncoras da janela System One. Sem estas, os três mapas de
    // `system_one.dart` poderiam sumir e a auditoria devolveria uma lista menor
    // sem ninguém dizer.
    expect(vistas, contains('soc_readout_letter'));
    expect(vistas, contains('soc_readout_logit'));
    expect(vistas, contains('soc_answer_type_noul'));
    expect(vistas.length, greaterThanOrEqualTo(10),
        reason: 'os dois mapas de faceta somam 10 entradas');

    final faltando = <String>[];
    for (final chave in vistas) {
      for (final lang in const ['en_US', 'pt_BR']) {
        if (!readMap(lang).containsKey(chave)) faltando.add('$chave ($lang)');
      }
    }
    expect(faltando, isEmpty,
        reason: 'chave que o fonte usa por variável e que não existe no mapa. '
            'O GetX devolve a própria chave e a tela mostra o identificador:\n'
            '  ${faltando.join('\n  ')}');
  });
}
