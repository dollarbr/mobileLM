import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/l10n/app_translation.dart';
import 'package:mobilelm/services/language_preference.dart';

/// O idioma é a única coisa do app que ninguém pode deduzir.
///
/// O app já foi `locale: Get.deviceLocale` com `fallbackLocale: pt_BR`, e o
/// resultado medido foi: **62 fichas de modelo em inglês numa tela que se dizia
/// portuguesa**, mais um aparelho fora do português sem poder pedir outro. Não
/// era bug do tradutor — era o idioma nunca ter sido uma escolha de ninguém.
///
/// Estes testes existem porque a decisão tem três formas de sair errado, e as
/// três já foram tentadas aqui:
///
/// 1. **Um idioma sem mapa.** O GetX devolve a própria chave para uma tradução
///    que não existe, e foi assim que 38 chaves apareceram como
///    `tool_round_trips` e `mobile_lm` sem nada lançar. Ligar EN sem o mapa
///    inteiro renderiza 320 identificadores.
/// 2. **Um valor desconhecido virando `Locale` vazio.** O `GetMaterialApp`
///    recebe o `locale` antes do primeiro `build`; um `languageCode` vazio
///    derruba a árvore inteira em vez de cair num idioma.
/// 3. **Metade das traduções.** Um idioma guardado em partes é metade do
///    defeito de novo, e a parte que falta é a que ninguém lê no código.
/// As chaves **como estão no fonte**, com repetição, do mapa pedido.
///
/// O `Map` que `AppTranslation().keys` entrega já perdeu a multiplicidade: uma
/// chave repetida vira uma só, e é por isso que a contagem de chaves e a
/// auditoria de cobertura não conseguem ver uma duplicata. Este lê o arquivo.
///
/// **A região vai de um cabeçalho de mapa ao outro**, e não até o primeiro `}`:
/// um `}` aparece dentro de um valor — `Max 2.0K tokens` não, mas `'}'` de um
/// exemplo de API sim — e cortar no primeiro erra o fim e mistura os dois mapas.
/// `en_US` vem antes de `pt_BR`, então a região do primeiro é o intervalo e a do
/// segundo é o resto do arquivo.
List<String> _chavesDoFonte(String lang) {
  final src = File('lib/l10n/app_translation.dart').readAsStringSync();
  final ini = src.indexOf("'$lang': {");
  expect(ini, greaterThan(-1), reason: 'mapa $lang não encontrado');
  final comecando = ini + "$lang': {".length;
  final outro = lang == 'en_US' ? src.indexOf("'pt_BR': {", comecando) : -1;
  final corpo = src.substring(comecando, outro < 0 ? src.length : outro);
  return RegExp(r"^\s*'([A-Za-z0-9_]+)':", multiLine: true)
      .allMatches(corpo)
      .map((m) => m.group(1)!)
      .toList();
}

void main() {
  // Os dois mapas são lidos **no corpo de `main`**, e não dentro do `group`.
  // Uma variável declarada dentro de um closure de teste só existe naquele
  // closure — e o primeiro draft deste arquivo os declarou no `group` e usou no
  // `group` seguinte, com "Undefined name 'en'".
  final en = AppTranslation().keys['en_US']!;
  final pt = AppTranslation().keys['pt_BR']!;

  group('a lista de opções é o que a tela mostra', () {
    test('são três, e o automatic é o primeiro', () {
      expect(LanguagePreference.opcoes, <String>[
        LanguagePreference.auto,
        LanguagePreference.english,
        LanguagePreference.portugueseBrazil,
      ]);
    });

    test('o padrão é inglês, e o motivo está no arquivo de novo', () {
      // **Se este default mudar para `auto`, o app volta a deduzir** — que é a
      // coisa que o defeito das 62 fichas foi. E o sintoma de um aparelho em
      // português passa a ser uma tela em português com 62 fichas em inglês,
      // que é o bug original com uma camada a mais.
      expect(LanguagePreference.padrao, LanguagePreference.english);
    });
  });

  group('normalizar tolera o que o Hive devolve', () {
    test('os três valores conhecidos passam intactos', () {
      expect(LanguagePreference.normalizar(LanguagePreference.auto), 'auto');
      expect(LanguagePreference.normalizar(LanguagePreference.english), 'en');
      expect(LanguagePreference.normalizar(LanguagePreference.portugueseBrazil),
          'pt_BR');
    });

    test('nulo é o padrão, porque ausente não é escolha de ninguém', () {
      expect(LanguagePreference.normalizar(null), LanguagePreference.padrao);
    });

    test('desconhecido cai em automatic, e a razão importa', () {
      // **Não cai em inglês.** Um valor corrompido virando `en` fixo transforma
      // um bug de armazenamento numa preferência que a pessoa nunca fez e não
      // sabe desfazer. `auto` é a única resposta que não está *errada*: ela
      // segue o aparelho, que é o que quem não sabe o que pediu queria.
      for (final lixo in <String>['', 'zz', 'br', 'português', 'auto2']) {
        expect(LanguagePreference.normalizar(lixo), LanguagePreference.auto,
            reason: 'o valor "$lixo" não é uma opção e não pode virar idioma');
      }
    });

    test('grafia alternativa de uma opção real é a opção, não lixo', () {
      // **`EN` e `en_US` são a escolha de inglês escrita de outro jeito**, e a
      // primeira redação deste teste os listava como lixo. A implementação
      // estava certa e o teste errado: mandar `EN` para `auto` troca o idioma
      // da pessoa sem ela pedir — que é exatamente o modo de falha que a
      // normalização existe para evitar, aplicado ao caso fácil.
      //
      // A comparação é em minúsculas e o retorno é a grafia de [opcoes], então
      // o que chega ao mapa `.tr` é sempre uma das três.
      expect(LanguagePreference.normalizar('EN'), LanguagePreference.english);
      expect(
          LanguagePreference.normalizar('en_US'), LanguagePreference.english);
      expect(
          LanguagePreference.normalizar('en-US'), LanguagePreference.english);
      expect(
          LanguagePreference.normalizar('  en  '), LanguagePreference.english);
    });

    test('as grafias alternativas de português caem em pt_BR', () {
      // `pt` e `pt-BR` são o que a tela e o sistema entregam em Builds
      // diferentes; sem esta normalização o valor guardado nunca casava com
      // `opcoes` e o chip nunca aparecia marcado.
      expect(LanguagePreference.normalizar('pt'), 'pt_BR');
      expect(LanguagePreference.normalizar('pt-BR'), 'pt_BR');
      expect(LanguagePreference.normalizar('pt_br'), 'pt_BR');
    });
  });

  group('resolver vira o Locale que o GetMaterialApp recebe', () {
    test('en e pt_BR são o que a pessoa pediu, sem olhar o aparelho', () {
      // Um aparelho em português com `en` escolhido mostra inglês. O inverso
      // também: quem pediu EN num aparelho português recebe inglês, e é por
      // isso que a opção existe.
      for (final aparelho in <Locale?>[
        const Locale('pt', 'BR'),
        const Locale('en', 'US'),
        const Locale('ja', 'JP'),
        null,
      ]) {
        expect(LanguagePreference.resolver('en', aparelho),
            const Locale('en', 'US'));
        expect(LanguagePreference.resolver('pt_BR', aparelho),
            const Locale('pt', 'BR'));
      }
    });

    test('auto segue o aparelho: português vira pt, o resto vira en', () {
      expect(LanguagePreference.resolver('auto', const Locale('pt', 'BR')),
          const Locale('pt', 'BR'));
      // **Qualquer outra variante de português também conta.** O aparelho
      // pode reportar `pt` sem país, e `pt-PT` é português da pessoa — tratar
      // como "outro idioma" mostra inglês a quem pediu português.
      expect(LanguagePreference.resolver('auto', const Locale('pt')),
          const Locale('pt', 'BR'));
      expect(LanguagePreference.resolver('auto', const Locale('pt', 'PT')),
          const Locale('pt', 'BR'));
      expect(LanguagePreference.resolver('auto', const Locale('en', 'GB')),
          const Locale('en', 'US'));
      expect(LanguagePreference.resolver('auto', const Locale('ja', 'JP')),
          const Locale('en', 'US'));
    });

    test('sem aparelhoknown, o resultado é o padrão e nunca um Locale vazio',
        () {
      // **Este é o caso do boot.** O `deviceLocale` do GetX pode não existir
      // ainda quando o `GetMaterialApp` é montado, e um idioma sem
      // `languageCode` derruba a árvore — que é a falha mais spectacular
      // possível para a menor das decisões.
      final l = LanguagePreference.resolver('auto', null);
      expect(l.languageCode, isNotEmpty);
      expect(l, const Locale('en', 'US'));
      // A guarda de `languageCode.isEmpty` não é teórica **e não é testável
      // com `Locale('')`**: a própria classe afirma `languageCode != ''` no
      // construtor, então um Locale vazio não chega a existir. O que dá para
      // afirmar é que a função trata `null` sem olhar nenhum campo, e é por
      // isso que a guarda existe — para quando o `deviceLocale` vier de uma
      // fonte que não passa pelo construtor do Flutter.
    });

    test('normalizar roda antes de resolver, então um lixo não vaza', () {
      expect(
          LanguagePreference.resolver('lixo', null), const Locale('en', 'US'));
      expect(LanguagePreference.resolver('lixo', const Locale('pt', 'BR')),
          const Locale('pt', 'BR'));
    });
  });

  group('ehPortugues decide o texto, não a preferência', () {
    test('olha o Locale, porque é a tela que pergunta', () {
      // Se isto olhasse a preferência guardada, a descrição do catálogo e a
      // interface poderiam discordar — e o sintoma é uma ficha em português
      // dentro de um app em inglês, sem nenhum aviso em lugar nenhum.
      expect(LanguagePreference.ehPortugues(const Locale('pt', 'BR')), isTrue);
      expect(LanguagePreference.ehPortugues(const Locale('pt')), isTrue);
      expect(LanguagePreference.ehPortugues(const Locale('en', 'US')), isFalse);
      expect(LanguagePreference.ehPortugues(null), isFalse);
    });
  });

  group('os dois mapas de tradução são completos e iguais', () {
    test('existem os dois, e nenhum está vazio', () {
      expect(en, isNotEmpty);
      expect(pt, isNotEmpty);
      expect(en.length, greaterThanOrEqualTo(300));
      expect(pt.length, greaterThanOrEqualTo(300));
    });

    test('as chaves são exatamente as mesmas nos dois idiomas', () {
      // **A assimetria é o defeito.** Com o fallback em pt_BR, uma chave que
      // faltasse em inglês aparecia *traduzida* e ninguém notava que faltava.
      // Agora o fallback é o idioma padrão, e a falta aparece como o próprio
      // identificador — que é o que este teste transforma em falha de CI.
      expect(en.keys.toSet().difference(pt.keys.toSet()), isEmpty,
          reason: 'chaves só no EN');
      expect(pt.keys.toSet().difference(en.keys.toSet()), isEmpty,
          reason: 'chaves só no PT');
      expect(en.length, pt.length);
    });

    test('nenhuma chave é repetida, porque a última vence em silêncio', () {
      // **Um literal de mapa aceita chave repetida, e `flutter analyze` não
      // reclama.** A segunda sobrescreve a primeira, o app funciona e a linha
      // errada continua no arquivo. Aconteceu com `set_hops_one` e
      // `set_hops_many`: uma inserção por `replace` casou as duas ocorrências
      // da âncora, uma no mapa EN e outra no PT, e cada mapa ficou com o par
      // duas vezes — o EN em cima do PT no mapa PT. O resultado na tela estava
      // **certo**, porque a última vence, e a contagem de chaves também
      // batia. Foi a contagem de `Map` que mascarou as duas, e nenhum teste
      // olhava a multiplicidade.
      //
      // A chave repetida também quebra a auditoria de cobertura: um
      // `Set` de chaves não vê duplicata, então "as chaves são as mesmas nos
      // dois idiomas" passa com uma chave a mais num idioma.
      for (final lang in const ['en_US', 'pt_BR']) {
        final contagem = <String, int>{};
        for (final chave in _chavesDoFonte(lang)) {
          contagem[chave] = (contagem[chave] ?? 0) + 1;
        }
        final repetidas = contagem.entries
            .where((e) => e.value > 1)
            .map((e) => '${e.key} x${e.value}')
            .toList();
        expect(repetidas, isEmpty,
            reason: 'chave repetida no mapa $lang — o Dart aceita e a última '
                'vence, então o app funciona e o arquivo mente:\n'
                '  ${repetidas.take(5).toList()}');
      }
    });

    test('nenhum valor é vazio, porque vazio é um bug sem mensagem', () {
      for (final mapa in [en, pt]) {
        for (final entrada in mapa.entries) {
          expect(entrada.value.trim(), isNotEmpty,
              reason: '${entrada.key} está vazio em um dos idiomas');
        }
      }
    });

    test(r'os três placeholders de $ sobreviveram à tradução', () {
      // O consumidor faz `.replaceAll('$min', ...)`, então o valor precisa
      // conter o texto `$min` **literalmente**. Escapar só a barra produz
      // `'$min'` no fonte — que o Dart lê como interpolação, e o analyzer
      // acusa "Undefined name 'min'" em vez de um erro de tradução. Um
      // placeholder sem quem troque é o pior tipo de erro de string: compila.
      for (final chave in const ['delete_name', 'enter_value_between']) {
        expect(en[chave], contains(r'$'), reason: '$chave perdeu o \$ no EN');
        expect(pt[chave], contains(r'$'), reason: '$chave perdeu o \$ no PT');
      }
      expect(en['enter_value_between'], contains(r'$min'));
      expect(en['enter_value_between'], contains(r'$max'));
      expect(en['delete_name'], contains(r'$name'));
    });

    test('o prompt de sistema não manda um idioma fixo', () {
      // **O prompt segue a tela.** Dizer "responda em português brasileiro"
      // num app cuja interface diz que fala inglês é a inconsistência que o
      // seletor veio tirar, e a redação antiga ficaria errada metade das
      // vezes — sem nenhum aviso.
      for (final chave in const [
        'prompt_system',
        'prompt_system_think',
        'prompt_system_no_think',
      ]) {
        expect(en[chave], isNot(matches(RegExp('portugu'))),
            reason: '$chave manda português num app cujo padrão é inglês');
        expect(pt[chave], isNot(matches(RegExp(r'\bportuguese\b'))),
            reason: '$chave manda inglês num app em português');
      }
    });

    test('nenhum valor do mapa EN está em português', () {
      // **Esta é a guarda que teria pegado o erro que existiu.** Duas chaves
      // do seletor de idioma (`language_changed` e
      // `language_portuguese_brazil_detail`) estavam com o valor em português
      // nos **dois** mapas — o EN traduzido como português, que é uma
      // forma que agora parece impossível e sobreviveu porque ninguém olhou o valor
      // daquele item em inglês.
      //
      // O teste de "as chaves são iguais nos dois" não pega: `'Idioma
      // alterado'` está em ambos. O de "o prompt não manda português" não pega
      // também, porque é outra chave. Só a leitura do valor, idioma a idioma,
      // pega — e o mesmo teste rodado no sentido inverso pega o espelho.
      //
      // **A lista é de português de propósito**, pela mesma razão do teste do
      // catálogo: uma lista do que não pode aparecer só funciona se o resto
      // for o universo.
      // **Palavras que são as duas línguas.** `do` é a forma auxiliar do
      // inglês ("Do not suggest this again") e uma das palavras mais comuns do
      // português; `no` é o "não" do inglês e uma preposição do português; `a`
      // é artigo nos dois. Sem esta lista, o detector acusa a frase **inglesa**
      // "Do not suggest this again" como portuguesa — e o aviso passa a ser
      // ruído, que é como um aviso deixa de ser lido.
      const colisoes = <String>{'do', 'no', 'a', 'o', 'so', 'se'};
      const palavras = <String>{
        'de',
        'do',
        'da',
        'dos',
        'das',
        'com',
        'sem',
        'para',
        'nenhum',
        'nenhuma',
        'nunca',
        'sempre',
        'telefone',
        'aparelho',
        'tela',
        'estou',
        'está',
        'esta',
        'este',
        'então',
        'mas',
        'muito',
        'pouco',
        'tudo',
        'todo',
        'toda',
        'todos',
        'todas',
        'cada',
        'quando',
        'como',
        'porque',
        'porem',
        'portanto',
        'voce',
        'você',
        'aqui',
        'ali',
        'agora',
        'ja',
        'ainda',
        'assim',
        'entao',
        'mudou',
        'alterado',
        'funcionar',
        'funciona',
        'mostrar',
        'mostra',
        'falar',
        'fala',
        'português',
        'portugues',
        'ingles',
        'inglês',
        'automatico',
      };
      final suspitas = <String>[];
      for (final e in en.entries) {
        final texto = e.value.toLowerCase();
        // Um valor é suspeito quando tem uma palavra portuguesa **e nenhuma
        // marca de inglês**. Sem a segunda condição, "English" e "Portuguese
        // (Brazil)" — que é o que o seletor mostra de propósito — acusariam.
        // **Um acerto só vale se NÃO for uma das palavras que existem nas duas
        // línguas.** `do` é a forma auxiliar do inglês ("Do not suggest this
        // again") e uma das palavras mais comuns do português; `no` é o "não"
        // do inglês e uma preposição do português; `a` é artigo nos dois. Sem
        // esta condição o detector acusa a frase **inglesa** como portuguesa, e
        // um aviso que dá falso positivo deixa de ser lido.
        final temPt = palavras.any((w) =>
            !colisoes.contains(w) &&
            texto.contains(RegExp('\\b${RegExp.escape(w)}\\b')));
        if (!temPt) continue;
        final marca = RegExp(r'\b(the|and|with|for|always|whatever|phone|'
                r'screen|language|changed)\b')
            .hasMatch(texto);
        if (marca) continue;
        suspitas.add('${e.key} = "${e.value}"');
      }
      expect(suspitas, isEmpty,
          reason: 'Estes valores do mapa EN estão em português. A chave '
              'existe nos dois mapas, então a auditoria de cobertura passa e '
              'ninguém percebe:\n  ${suspitas.join('\n  ')}');
    });

    test('nenhum valor do mapa PT está em inglês', () {
      // O espelho do teste acima, e vale pelo mesmo motivo: é o que garante que
      // escolher português não entrega uma tela que é o mapa EN com três
      // palavras trocadas.
      //
      // **A lista é de inglês**, e o teste de "valor com underscore" que já
      // existia cobre só a forma `foo_bar` de uma chave vazada — não uma
      // frase em inglês.
      const palavras = <String>{
        'the',
        'and',
        'with',
        'for',
        'from',
        'this',
        'that',
        'your',
        'you',
        'will',
        'would',
        'should',
        'always',
        'never',
        'phone',
        'screen',
        'language',
        'changed',
        'settings',
        'model',
        'models',
        'load',
        'delete',
        'cancel',
        'save',
        'answer',
        'reply',
        'question',
        'summarise',
        'summarize',
        'explain',
        'convert',
        'translate',
        'tell',
      };
      // **`download` saiu da lista de propósito.** "Download" é palavra
      // emprestada do português brasileiro — `download`, `download falhou`, "o
      // download do modelo" — e é o que a pessoa lê no aparelho. Um detector
      // que a acusa está acusando a lingua certa, e a correção seria escrever
      // "Transferir" numa interface onde ninguém diz isso.
      final suspitas = <String>[];
      for (final e in pt.entries) {
        final texto = e.value.toLowerCase();
        // **Uma URL não é texto, é endereço, e o detector de inglês acusa o
        // `from` dela.** `https://huggingface.co/…/model.gguf` é o exemplo que o
        // campo de URL mostra, e ele é **igual nos dois idiomas** por
        // definição: traduzir o caminho de um endereço dá um endereço que não
        // existe. A marca é o esquema, e o esquema não muda com o idioma.
        if (RegExp(r'^https?://').hasMatch(texto)) continue;
        if (!palavras
            .any((w) => texto.contains(RegExp('\\b${RegExp.escape(w)}\\b')))) {
          continue;
        }
        // Marca de português: acentos, cedilha, ou uma palavra da lista de
        // termos técnicos que o produto mantém (embedder, reranker, projector).
        //
        // **`screen` entrou na lista de técnicos pela mesma razão de
        // `projector`**: é o nome da rota (`POST /v1/litert/screen`), e a
        // mensagem `screen @n: @e` diz **qual chamada** falhou. Traduzir o nome
        // da rota faria a pessoa procurar `/v1/litert/tela` no log.
        final marcaPt = RegExp('[áàâãéêíóôõúç]').hasMatch(texto) ||
            RegExp(r'\b(embedder|reranker|projector|pooler|screen)\b')
                .hasMatch(texto);
        if (marcaPt) continue;
        suspitas.add('${e.key} = "${e.value}"');
      }
      expect(suspitas, isEmpty,
          reason: 'Estes valores do mapa PT estão em inglês:\n'
              '  ${suspitas.join('\n  ')}');
    });

    test('o seletor de idioma tem as chaves dos dois idiomas', () {
      // As seis: o título já existia, e as outras cinco vieram com o seletor.
      for (final chave in const [
        'language',
        'language_auto',
        'language_auto_detail_pt',
        'language_auto_detail_en',
        'language_english_detail',
        'language_portuguese_brazil_detail',
      ]) {
        expect(en.containsKey(chave), isTrue, reason: '$chave falta no EN');
        expect(pt.containsKey(chave), isTrue, reason: '$chave falta no PT');
      }
    });
  });

  group('os rótulos do seletor não passam pelo mapa', () {
    test('o nome do idioma é o dado, e um dado traduzido deixa de identificar',
        () {
      // Em português o item diz "Português (Brasil)"; em inglês diz
      // "Portuguese (Brazil)". Um rótulo traduzido diria "Inglês" dentro de uma
      // lista de idiomas, e quem lê em inglês não reconheceria o próprio.
      expect(
          LanguagePreference.rotulo('en', const Locale('pt', 'BR')), 'English');
      expect(
          LanguagePreference.rotulo('en', const Locale('en', 'US')), 'English');
      expect(LanguagePreference.rotulo('pt_BR', const Locale('en', 'US')),
          'Portuguese (Brazil)');
      expect(LanguagePreference.rotulo('pt_BR', const Locale('pt', 'BR')),
          'Português (Brasil)');
    });

    test('"automatic" é o único que se traduz, porque não é nome de idioma',
        () {
      // **"Automatic" e "Automático" são o mesmo rótulo em duas línguas**,
      // ao contrário de "English" e "Portuguese". Um nome de idioma traduzido
      // nomeia o idioma errado; um termo de interface traduzido é o que a
      // pessoa espera ler.
      expect(LanguagePreference.rotulo('auto', const Locale('pt', 'BR')),
          'Automático');
      expect(LanguagePreference.rotulo('auto', const Locale('en', 'US')),
          'Automatic');
    });

    test('uma opção desconhecida mostra "automatic", e não uma string vazia',
        () {
      expect(LanguagePreference.rotulo('lixo', const Locale('en', 'US')),
          'Automatic');
    });
  });

  group('este arquivo pode falhar', () {
    // **Um teste verde só vale se ele viu a mudança.** A primeira versão deste
    // conjunto passou com uma tradução faltando no EN, e a causa foi a mais
    // boba possível: o `git checkout` que "desfazia a provocação" rodava antes
    // do resultado ser lido, e apagava a edição. Desde então a provocação é
    // feita e conferida na mesma volta.
    test('a contagem de chaves é a que o catálogo tem hoje', () {
      // 674 = 658 do que já existia + **16 chaves desta rodada**.
      //
      // **Dez delas são o alargamento da lista de palavras expôs.** As 27
      // palavras medidas (`show`, `back`, `copy`, `benchmark`, `clear`, `name`,
      // `open`, `close`…) revelaram uma dívida que nenhuma das duas varreduras
      // contava: `log_copy_important`, `log_clear`, `log_copied`,
      // `log_copied_detail`, `ws_back_to_projects`, `ws_refresh`,
      // `pp_new_project_name`, `pp_name_hint`, `set_cpu_benchmark`,
      // `mv_show_it_anyway`, `mv_cloud_provider_name`, `mv_cloud_base_url`,
      // `mv_projector`, `sc_turn_off_anyway` — 14 literais estreitos mais
      // `set_device_budget`, que é interpolada.
      //
      // **As outras duas são a sentinela de tamanho.** `mc_unknown_size` é o
      // texto do `kUnknownSize`, que viaja como valor comparado e guardado no
      // Hive e só vira texto em um ponto de pintura. Antes disso, `Unknown size`
      // estava nos dois papéis ao mesmo tempo e a varredura não conseguia
      // distinguir: traduzir quebrava a comparação, não traduzir deixava
      // inglês na tela.
      //
      // **`set_device_budget` substituiu um literal com `${…}`** que a trava dos
      // interpolados não via porque `available` não estava na lista de palavras.
      // É a **décima** omissão do ratchet e a primeira em que a lista de
      // palavras — e não o alcance da varredura — é o que estava incompleto.
      //
      // Este número já esteve errado seis vezes neste repo (45, 62, 10 encoders,
      // 484, 522, 535), então o teste afirma em vez de descrever.
      //
      // **905 = 674 + 231 do item 3e**, a rodada que traduziu os 205 textos de
      // tela que a varredura ampla tinha encontrado e nenhuma das outras três
      // contava. Mais `soc_run_now`, que não vem do TSV: `'running'` é status
      // gravado no Hive e o botão que o mostrava precisou de chave própria,
      // porque traduzir o status quebraria a comparação.
      //
      // **919 = 905 + 14: 13 da janela System One, que é a origem desta contagem
      // ter subido: `soc_repeat_orders`, `soc_variants_one`, `soc_variants_many`,
      // `soc_stability`, `soc_stable`, `soc_unstable`, `soc_agreement`,
      // `soc_no_answer`, `soc_match`, as três frases de `soc_match_*` (a letra, a
      // letra enfeitada e o rótulo escrito) e `soc_model_said`, que nomeia o texto
      // cru do modelo **no caminho da recusa** — sem ele a recusa mostrava o bloco
      // de estabilidade e não mostrava o que o modelo escreveu. Nenhuma delas é
      // texto já existente
      // renomeado; são frases que **não existiam**, e sem elas a tela de decisão
      // mostraria "how the letter was found" com o corpo vazio.
      //
      // O número subiu depois de a soma ter sido conferida duas vezes contra os
      // dois mapas, porque **o número é o que acusa** e ele estava 12 abaixo do
      // que o fonte produz. As duas metades do mapa continuam com as mesmas
      // chaves — o teste logo acima é que diz isso.
      //
      // 919 → 932 são as **13** chaves da janela System One: o rótulo dos dois
      // readouts, a frase de custo de cada um, o botão, o tipo de resposta e as
      // três formas, a confiança, o nível e a contagem de passagens. Contadas nos
      // DOIS mapas pelo `l10n_keys_test`, e conferidas uma a uma: nenhuma é
      // texto já existente renomeado — são frases que não existiam.
      expect(en.length, 932);
    });

    test('a lista de opções não encolhe nem cresce sem ninguém ver', () {
      expect(LanguagePreference.opcoes.length, 3);
    });
  });
}
