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
      // O noul deu 0.5188 numa pergunta cuja resposta óbvia é sim.
      expect(DecisionPreset.byId('outage')!.measured, contains('0.5188'));
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