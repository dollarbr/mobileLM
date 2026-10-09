import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/services/system_one.dart';
import 'package:mobilelm/services/system_one_presets.dart';

void main() {
  group('os presets são controles, não demonstrações', () {
    test('existem quatro, e o primeiro é o que funciona', () {
      // A ordem é por "isto responde algo que o anterior não respondia", e não
      // alfabética: `charge` (choice de três opções), `outage` (noul cuja
      // resposta óbvia é sim), `urgency` (score numa escala), `forgot` (um ticket
      // real, e o lento). Uma lista ordenada por nome punha `forgot` em quarto e
      // o primeiro toque da pessoa seria o que dá timeout.
      expect(DecisionPreset.all.map((p) => p.id).toList(),
          ['charge', 'outage', 'urgency', 'forgot']);
    });

    test('cada preset traz o que o A72 mediu, e dois trazem o ERRADO', () {
      // Um preset cujas todas as respostas estão corretas ensina que o caminho
      // funciona e nada mais. Estes dois existem **por** estar errados.
      for (final p in DecisionPreset.all) {
        expect(p.measured, isNotNull,
            reason: '${p.id} sem medição não é um controle');
        expect(p.note, isNotNull, reason: '${p.id} sem motivo não é um controle');
      }
      // O noul deu 0,5188 (Tev1) e 0,5522 (d1-3B) numa pergunta cuja resposta
      // óbvia é sim. **O ponto é a vírgula:** o número na tela é `0,5188` em
      // português, e um teste que procura `0.5188` reprovaria com a medição
      // certa no lugar — a mesma armadilha de dois-pontos-e-vírgula que já
      // pegou três traduções deste repo.
      expect(DecisionPreset.byId('outage')!.measured, contains('0,5188'));
      // E o score respondeu "pode esperar" para uma cobrança duplicada.
      expect(DecisionPreset.byId('urgency')!.measured, contains('nível 0'));
    });

    test('todo preset é um pedido VÁLIDO', () {
      // Um preset que o endpoint recusa é pior que nenhum: a pessoa clica, leva
      // um 400 e conclui que o caminho não funciona.
      for (final p in DecisionPreset.all) {
        expect(p.state.trim(), isNotEmpty, reason: '${p.id} sem estado');
        expect(p.question, isNotNull, reason: '${p.id} sem pergunta');
        expect(kAnswerTypes.contains(p.type),
            isTrue, reason: '${p.id} com tipo ${p.type}');
        if (decisionTypeNeedsOptions(p.type)) {
          // O teto do LAYOUT é dez, e não os 24 do /v1/classify.
          expect(p.options.length, lessThanOrEqualTo(10));
          expect(p.options.length, greaterThanOrEqualTo(2));
        }
      }
    });

    test('os ids são únicos e o byId acha todos', () {
      final ids = DecisionPreset.all.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final id in ids) {
        expect(DecisionPreset.byId(id)!.id, id);
      }
      // E um id que não existe devolve nulo em vez de lançar: quem chama é a
      // tela, e uma tela que lança por um chip apagado quebra o build inteiro.
      expect(DecisionPreset.byId('nao-existe'), isNull);
    });

    test('as chaves de tradução são derivadas do id, e o id é o nome', () {
      // Uma chave montada em runtime não é auditada, e o `l10n_keys_test`
      // reprova chave dinâmica. Então a chave é uma interpolação **no
      // preshape** e o id é o que a auditoria enxerga.
      for (final p in DecisionPreset.all) {
        expect(p.labelKey, 'soc_preset_${p.id}');
        expect(p.noteKey, 'soc_preset_note_${p.id}');
      }
    });

    test('todo preset que tem opções tem também a INSTRUÇÃO dela', () {
      // **Este é o teste que o A72 pediu, e a razão é medida.** Sem
      // `instructions`, o endpoint usa o **id** da pergunta como o texto dela —
      // e o id desta janela é a palavra `decision`. O mesmo estado, o mesmo
      // `d1-3B` e as mesmas três opções:
      //
      // | pergunta | resposta | A | B | C |
      // |---|---|---|---|---|
      // | `decision` (o id) | **C: account** | 0,1307 | 0,2846 | **0,5847** |
      // | `a que área isto pertence?` | **A: billing** | **0,5312** | 0,1640 | 0,3047 |
      //
      // `A: billing` é a resposta certa para uma cobrança duplicada. A primeira
      // linha é o que o preset produzia — e mostrava `medido: billing` ao lado,
      // que é a pior forma de erro possível: número certo, pergunta errada.
      //
      // **E o `question` do preset não serve para isto.** O campo `question` da
      // janela é exibido e **não vai no corpo** — `systemOneBody` não tem
      // parâmetro `question`. Quem manda a pergunta ao modelo é
      // `instructions`. Um preset com `question` e sem `instruction` manda o
      // modelo perguntar `decision`.
      for (final p in DecisionPreset.all) {
        if (!decisionTypeNeedsOptions(p.type)) continue;
        expect(p.instruction, isNotNull,
            reason: '${p.id} tem ${p.options.length} opções e nenhuma '
                'instrução: o modelo vai receber o id "decision" como '
                'pergunta');
        expect(p.instruction!.trim(), isNotEmpty,
            reason: '${p.instruction} é o id, não uma pergunta');
      }
      // E o `noul` também tem, porque sem instrução ele pergunta `decision`
      // sobre um booleano — que é pior ainda, porque o `noul` não tem opção
      // nenhuma para o modelo se apoiar.
      expect(DecisionPreset.byId('outage')!.instruction,
          isNot(contains('decision')));
    });

    test('a guarda "não apaga o que não sabe" é defensiva e hoje não tem teste',
        () {
      // **Escrito porque uma mutação sobreviveu, e não porque o teste
      // "falha".** `_applyPreset` faz `if (p.instruction != null)` em vez de
      // `p.instruction ?? ''`, e voltar ao `?? ''` **não reprova nada**: os
      // quatro presets têm instrução, então os dois caminhos fazem a mesma
      // coisa. Uma guarda que nenhum dado alcança é código inatingível, e
      // escrever que ela está coberta seria o que este repo já fez sete vezes.
      //
      // A guarda vale porque o próximo preset pode não ter instrução — e o
      // sintoma de um `?? ''` ali é a medição errada ao lado da resposta errada
      // que o teste de cima mediu. **Quem a torna alcançável é o teste de
      // cima**: um preset com `instruction: null` reprovaria nele, e é por
      // isso que ele existe e não é sobre estilo.
      final comInstrucao =
          DecisionPreset.all.where((p) => p.instruction != null).length;
      expect(comInstrucao, DecisionPreset.all.length,
          reason: 'se isto mudar, o `?? \'\'` volta a ser indistinguível do '
              '`if != null` e a guarda perde o único dado que a exercita');
    });

    test('toda medição DIZ DE QUAL MODELO ela é', () {
      // **Isto é uma regra, e ela nasceu de uma medição que a violou.** O
      // preset `urgency` dizia "nível 0 (Can wait) com 0,5537" sem dizer de que
      // modelo — e medido no `d1-3B` o **mesmo preset** respondeu **nível 2
      // (Today)**, que é a resposta certa. Três dos quatro presets citas uma
      // medição sem o modelo, e o aparelho mostrou que a omissão muda o
      // sentido do número.
      //
      // **Sem o nome do modelo a medição é uma afirmação sobre "este aparelho",
      // e o aparelho tem vários modelos.** Um preset é um controle: ele fixa a
      // pergunta para que a diferença entre o medido e o ao vivo seja do modelo,
      // e um controle que não nomeia o que ele comparou não fecha o caso.
      for (final p in DecisionPreset.all) {
        expect(p.measured, isNotNull, reason: '${p.id} sem medição');
        // Os dois nomes que aparecem nas medições deste arquivo. Um terceiro
        // modelo entra aqui **e** na lista, e o teste passa a exigir que o
        // preset o cite.
        expect(
          RegExp(r'\b(tev1|d1-3b)\b', caseSensitive: false)
              .hasMatch(p.measured!),
          isTrue,
          reason: '${p.id} diz "${p.measured}" sem dizer de qual modelo é a '
              'medição. Com mais de um modelo no aparelho, isso é uma '
              'afirmação sobre nada',
        );
      }
      // E o `forgot` diz explicitamente que ainda não foi medido no d1-3B, em
      // vez de fingir que a medição do Tev1 vale para os dois.
      expect(DecisionPreset.byId('forgot')!.note, contains('ainda não foi medido'));
    });

    test('as medições são de DOIS modelos que discordam, e é isso que é útil', () {
      // Um preset com uma medição só é uma afirmação. Com duas, e discordando,
      // ele mostra a coisa que interessa: **o mesmo preset, a mesma pergunta e
      // duas respostas** — que é a diferença entre "o modelo errou" e "o modelo
      // que você tem não é o que foi medido".
      expect(DecisionPreset.byId('urgency')!.measured, contains('nível 0'));
      expect(DecisionPreset.byId('urgency')!.measured, contains('nível 2'));
      // O `charge` acerta a área nos dois e discorda só na força.
      expect(DecisionPreset.byId('charge')!.measured, contains('0,6972'));
      expect(DecisionPreset.byId('charge')!.measured, contains('0,5312'));
      // E o `outage` é quase uma moeda nos dois — o defeito que os dois
      // compartilham, e por isso o mais informativo dos quatro.
      expect(DecisionPreset.byId('outage')!.measured, contains('0,5188'));
      expect(DecisionPreset.byId('outage')!.measured, contains('0,5522'));
    });

    test('o noul não traz opções, e é por isso', () {
      // O endpoint escreve as duas afirmações nas palavras do template do autor.
      // Preencher o cartão com dois campos seria um segundo conjunto de palavras
      // para o mesmo booleano.
      expect(DecisionPreset.byId('outage')!.options, isEmpty);
      expect(decisionTypeNeedsOptions('noul'), isFalse);
      expect(decisionTypeNeedsOptions('choice'), isTrue);
      expect(decisionTypeNeedsOptions('score'), isTrue);
    });

    test('os defaults por tipo batem com o que cada forma pede', () {
      expect(kAnswerTypeDefaultOptions['choice'],
          ['bug', 'billing', 'account']);
      expect(kAnswerTypeDefaultOptions['score'],
          ['Can wait', 'This week', 'Today']);
      // E o noul é vazio, pelo mesmo motivo do preset.
      expect(kAnswerTypeDefaultOptions['noul'], isEmpty);
      // **O preset `charge` NÃO usa o default de `choice`, e minha premissa
      // aqui estava errada.** Ele traz `billing / technical support / account`,
      // que é o trio do `curl` cujo 0,6972 eu medi; o default da janela é
      // `bug / billing / account`, o trio do `tev1` com que a tela já abria. São
      // duas perguntas diferentes — uma classifica um ticket de cobrança, a outra
      // testa o classificador de área — e um preset que trocasse as opções
      // trocaria a pergunta, que é a única coisa que ele existe para fixar.
      expect(DecisionPreset.byId('charge')!.options,
          ['billing', 'technical support', 'account']);
      expect(kAnswerTypeDefaultOptions['choice'], isNot(
          DecisionPreset.byId('charge')!.options));
    });
  });

  group('o corpo que a tela monta a partir de um preset', () {
    final opts = SystemOneOptions([
      for (var i = 0; i < 3; i++)
        SystemOneOption(SystemOneOptions.letters[i],
            ['bug', 'billing', 'account'][i]),
    ]);

    test('cada tipo produz o corpo que o endpoint aceita', () {
      // O mesmo preset, os três corpos, e a diferença entre eles é o que o
      // endpoint documenta: `criteria` como MAPA para choice, como LISTA para
      // score, e AUSENTE para noul.
      final choice = const SystemOneResult().systemOneBody(
        state: 'fui cobrado duas vezes',
        questionId: 'decision',
        questionType: 'choice',
        options: opts,
        instructions: 'a que área isto pertence?',
      );
      final cq = (choice['questions'] as Map)['decision'] as Map;
      expect(cq['criteria'], isA<Map>());
      expect((cq['criteria'] as Map)['A'], 'bug');

      final score = const SystemOneResult().systemOneBody(
        state: 'fui cobrado duas vezes',
        questionId: 'decision',
        questionType: 'score',
        options: opts,
        instructions: 'How urgent?',
      );
      final sq = (score['questions'] as Map)['decision'] as Map;
      expect(sq['criteria'], isA<List>());

      final noul = const SystemOneResult().systemOneBody(
        state: 'checkout devolvendo 500',
        questionId: 'decision',
        questionType: 'noul',
        options: opts,
        instructions: 'Is a service down?',
      );
      final nq = (noul['questions'] as Map)['decision'] as Map;
      // **O cartão de opções fica escondido para um noul**, e o corpo manda as
      // opções que a tela tem em memória e NÃO as usa. Uma janela que passasse
      // `bug/billing/account` para um noul estaria asking duas perguntas.
      expect(nq.containsKey('criteria'), isFalse);
    });

    test('o id da pergunta é estável, e é a chave da resposta', () {
      // `decision` e não o texto: uma chave estável é o que o painel lê, e um id
      // que fosse a pergunta mudaria a cada edição.
      final body = const SystemOneResult().systemOneBody(
        state: 's',
        questionId: 'decision',
        questionType: 'choice',
        options: opts,
      );
      expect((body['questions'] as Map).keys.toList(), ['decision']);
    });
  });

  group('a tabela de mutações deste arquivo', () {
    test('a ordem dos presets mutada reprova', () {
      // Se `forgot` viesse primeiro, o primeiro toque da pessoa seria o que leva
      // 50,7 s, e o cartão pareceria travado.
      final ids = DecisionPreset.all.map((p) => p.id).toList();
      expect(ids.first, 'charge');
      expect(ids.last, 'forgot');
    });

    test('um preset sem medição reprova, porque é só uma demo', () {
      for (final p in DecisionPreset.all) {
        expect(p.measured, isNotNull);
      }
      // E a afirmação oposta: um preset com `measured` e sem `note` não diz por
      // que está aqui, e os dois que erram são os que precisam dizer.
      for (final p in DecisionPreset.all) {
        expect(p.note, isNotNull);
      }
    });

    test('`decisionTypeNeedsOptions` invertida reprova', () {
      // A inversão mandaria `criteria` para o `noul` e esconderia o cartão de
      // opções de uma `choice` — e `noul` leria como choice de três opções.
      expect(decisionTypeNeedsOptions('noul'), isFalse);
      expect(decisionTypeNeedsOptions('choice'), isTrue);
    });

    test('`kAnswerTypes` sem `noul` reprova', () {
      expect(kAnswerTypes, ['choice', 'score', 'noul']);
      // E os três precisam ter um chip, ou a tela mostraria o tipo e não a forma.
      for (final t in kAnswerTypes) {
        expect(kAnswerTypeKey[t], isNotNull);
      }
    });
  });
}