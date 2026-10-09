import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/services/typed_decision.dart';

/// A `choice` with three options, the shape the authors' own example uses.
const q3 = DecisionQuestion(
  id: 'department',
  type: DecisionType.choice,
  instructions: 'Which department should handle this?',
  options: ['billing', 'technical support', 'sales'],
);

void main() {
  group('o prompt é o do prompt.py, byte a byte', () {
    test('uma pergunta, sem numeração', () {
      // Do exemplo do card, que é o mesmo `state_first` que o fonte monta.
      expect(
        decisionPrompt(state: 'I was charged twice', questions: [q3]),
        'Context:\nI was charged twice'
        '\n\nQuestion: Which department should handle this?\nOptions:'
        '\n(A) billing'
        '\n(B) technical support'
        '\n(C) sales'
        '\nAnswer: (',
      );
    });

    test('mais de uma pergunta numera as duas metades', () {
      final prompt = decisionPrompt(
        state: 'x',
        questions: const [
          DecisionQuestion(
            id: 'a',
            type: DecisionType.choice,
            instructions: 'A?',
            options: ['p', 'q'],
          ),
          DecisionQuestion(
            id: 'b',
            type: DecisionType.noul,
            instructions: 'B?',
            options: ['true', 'false'],
          ),
        ],
      );
      // `multi` depende da contagem no fonte, e o modelo viu os dois layouts.
      expect(prompt, contains('\n\nQuestion 1: A?\nOptions:'));
      expect(prompt, contains('\nAnswer 1: ('));
      expect(prompt, contains('\n\nQuestion 2: B?\nOptions:'));
      expect(prompt, contains('\nAnswer 2: ('));
      // E termina na última, como `slots.append(len(ids) - 1)` exige.
      expect(prompt.endsWith('\nAnswer 2: ('), isTrue);
    });

    test('o último caractere é sempre o "(" que abre o slot', () {
      final prompt = decisionPrompt(state: 's', questions: [q3]);
      expect(prompt.endsWith('('), isTrue);
    });

    test('single: força o layout de uma pergunta', () {
      final two = [
        q3,
        const DecisionQuestion(
          id: 'b',
          type: DecisionType.noul,
          instructions: 'B?',
          options: ['true', 'false'],
        ),
      ];
      // Declarar `single: true` com duas perguntas renderiza a segunda sem
      // numeração — o que é errado para o modelo e está aqui porque quem chama
      // precisa poder dizer que sabe disso.
      final forced = decisionPrompt(state: 's', questions: two, single: true);
      expect(forced, contains('\n\nQuestion: '));
      expect(forced, contains('\nAnswer: ('));
      expect(forced, isNot(contains('Question 1:')));
    });
  });

  group('o id é a pergunta quando não há instructions', () {
    test('e a regra vem do contrato, não de um chute', () {
      const q = DecisionQuestion(
        id: 'Is a service down?',
        type: DecisionType.noul,
        options: ['true', 'false'],
      );
      expect(q.promptText, 'Is a service down?');
      expect(
        decisionPrompt(state: 's', questions: [q]),
        contains('\n\nQuestion: Is a service down?\nOptions:'),
      );
    });

    test('instructions vazio também cai no id', () {
      const q = DecisionQuestion(
        id: 'refund',
        type: DecisionType.noul,
        instructions: '',
        options: ['true', 'false'],
      );
      expect(q.promptText, 'refund');
    });

    test('instructions presente ganha do id', () {
      const q = DecisionQuestion(
        id: 'refund',
        type: DecisionType.noul,
        instructions: 'Does the sender ask for money back?',
        options: ['true', 'false'],
      );
      expect(q.promptText, 'Does the sender ask for money back?');
    });
  });

  group('o teto de opções é do layout, não do endpoint', () {
    test('10 opções cabem; 11 não', () {
      final ten = [
        for (var i = 0; i < 10; i++) 'opt$i',
      ];
      expect(
        decisionPrompt(state: 's', questions: [
          DecisionQuestion(
            id: 'q',
            type: DecisionType.choice,
            instructions: 'Q?',
            options: ten,
          ),
        ]),
        contains('(J) opt9'),
      );

      final eleven = [
        for (var i = 0; i < 11; i++) 'opt$i',
      ];
      expect(
        () => decisionPrompt(state: 's', questions: [
          DecisionQuestion(
            id: 'q',
            type: DecisionType.choice,
            instructions: 'Q?',
            options: eleven,
          ),
        ]),
        throwsA(
          isA<DecisionRequestError>().having(
            (e) => e.message,
            'message',
            allOf(contains('at most 10'), contains('separate rendering')),
          ),
        ),
      );
    });

    test('a letra fora do alfabeto recusa em vez de inventar', () {
      expect(decisionLetter(0), 'A');
      expect(decisionLetter(9), 'J');
      expect(() => decisionLetter(10), throwsA(isA<DecisionRequestError>()));
      expect(() => decisionLetter(-1), throwsA(isA<DecisionRequestError>()));
    });

    test('o conjunto de letras recusa abaixo de 2', () {
      expect(() => decisionLetterSet(1), throwsA(isA<DecisionRequestError>()));
      expect(decisionLetterSet(2), ['A', 'B']);
    });
  });

  group('o estado respeita string e JSON', () {
    test('string vai como está, sem aspas', () {
      // A regra é por TIPO Dart, não por o texto parsear como JSON: um state que
      // já é string é a frase do chamador, e reencodar colocaria aspas num
      // ticket e mudaria o que o modelo lê.
      expect(decisionState('a ticket'), 'a ticket');
      expect(decisionState('{"a": 1}'), '{"a": 1}');
    });

    test('qualquer outro valor vai por tojson, como o template faz', () {
      expect(decisionState({'a': 1}), '{"a":1}');
      expect(decisionState([1, 2]), '[1,2]');
      expect(decisionState(42), '42');
      expect(decisionState(true), 'true');
    });

    test('null é estado vazio, não "null"', () {
      expect(decisionState(null), '');
    });
  });

  group('os slots apontam para o "(" e o último é o do fim', () {
    test('os deslocamentos de caracter batem com o prompt', () {
      final prompt = decisionPrompt(state: 'STATE', questions: [q3]);
      final offs = decisionSlotOffsets(state: 'STATE', questions: [q3]);
      expect(offs.length, 1);
      expect(prompt[offs.single], '(');
    });

    test('com várias perguntas, cada offset aponta para o seu "("', () {
      final questions = [
        q3,
        const DecisionQuestion(
          id: 'b',
          type: DecisionType.noul,
          instructions: 'B?',
          options: ['true', 'false'],
        ),
      ];
      final prompt = decisionPrompt(state: 'STATE', questions: questions);
      final offs = decisionSlotOffsets(state: 'STATE', questions: questions);
      expect(offs.length, 2);
      for (final o in offs) {
        expect(prompt[o], '(');
      }
      // E o último é o fim do prompt, que é o que torna `-1` seguro.
      expect(offs.last, prompt.length - 1);
      // Os primeiros não são: há texto depois deles.
      expect(offs.first, lessThan(prompt.length - 1));
    });

    test('a lista de slots que o nativo usa é tudo -1', () {
      expect(decisionSlots(3), [-1, -1, -1]);
    });
  });

  group('o softmax aplica a temperatura antes de qualquer número', () {
    test('soma 1', () {
      final p = decisionSoftmax([1.0, 2.0, 3.0], 1.0);
      expect(p.reduce((a, b) => a + b), closeTo(1.0, 1e-12));
      expect(p[2], greaterThan(p[1]));
      expect(p[1], greaterThan(p[0]));
    });

    test('temperatura maior achata, e não muda a ordem', () {
      final sharp = decisionSoftmax([2.0, 1.0], 0.5);
      final flat = decisionSoftmax([2.0, 1.0], 4.0);
      expect(sharp[0], greaterThan(flat[0]));
      expect(sharp[0] > sharp[1], true);
      expect(flat[0] > flat[1], true);
    });

    test('temperatura não desloca o argmax', () {
      // É a razão de o card dizer que a temperatura não muda a resposta.
      for (final t in [0.1, 1.0, 10.0]) {
        final p = decisionSoftmax([0.2, 5.0, 0.1], t);
        var top = 0;
        for (var i = 1; i < p.length; i++) {
          if (p[i] > p[top]) top = i;
        }
        expect(top, 1, reason: 'temperatura $t mudou o vencedor');
      }
    });

    test('temperatura zero ou negativa recusa, não divide', () {
      expect(() => decisionSoftmax([1, 2], 0),
          throwsA(isA<DecisionRequestError>()));
      expect(() => decisionSoftmax([1, 2], -1),
          throwsA(isA<DecisionRequestError>()));
      expect(() => decisionSoftmax([1, 2], double.nan),
          throwsA(isA<DecisionRequestError>()));
    });

    test('logits vazios recusam', () {
      expect(() => decisionSoftmax([], 1.0), throwsA(isA<DecisionRequestError>()));
    });

    test('-inf em todos recusa em vez de devolver NaN', () {
      expect(
        () => decisionSoftmax([double.negativeInfinity, double.negativeInfinity], 1.0),
        throwsA(isA<DecisionRequestError>().having((e) => e.message, 'message',
            contains('underflow'))),
      );
    });

    test('logits enormes não estouram', () {
      final p = decisionSoftmax([1e30, -1e30], 1.0);
      expect(p[0], closeTo(1.0, 1e-12));
      expect(p[1], closeTo(0.0, 1e-12));
    });
  });

  group('a confiança é a da TypeSafe, não a probabilidade do topo', () {
    test('com 2 opções, [0,5,1] vira [0,1]', () {
      expect(decisionConfidence(2, 0.5), closeTo(0.0, 1e-12));
      expect(decisionConfidence(2, 1.0), closeTo(1.0, 1e-12));
      expect(decisionConfidence(2, 0.9), closeTo(0.8, 1e-12));
    });

    test('com 3 opções a fórmula estica diferente', () {
      expect(decisionConfidence(3, 1.0), closeTo(1.0, 1e-12));
      expect(decisionConfidence(3, 1 / 3), closeTo(0.0, 1e-12));
    });

    test('uma opção não define confiança', () {
      expect(() => decisionConfidence(1, 0.5), throwsA(isA<DecisionRequestError>()));
    });
  });

  group('a resposta por tipo', () {
    test('choice traz choice, confidence e probabilities', () {
      final a = answerFromLogits(question: q3, logits: [0.1, 3.0, 0.2]);
      expect(a.type, DecisionType.choice);
      expect(a.choice, 'technical support');
      expect(a.probabilities.keys.toSet(), {'billing', 'technical support', 'sales'});
      expect(a.confidence, isNotNull);
      expect(a.whyNoConfidence, isNull);
    });

    test('score traz score, legend indexada e confidence', () {
      const q = DecisionQuestion(
        id: 'urgency',
        type: DecisionType.score,
        instructions: 'How urgent?',
        options: ['Can wait', 'This week', 'Today'],
      );
      final a = answerFromLogits(question: q, logits: [0.0, 1.0, 5.0]);
      expect(a.score, 2.0);
      expect(a.legend, {0: 'Can wait', 1: 'This week', 2: 'Today'});
      expect(a.confidence, isNotNull);
    });

    test('noul traz a probabilidade de true e diz por que não há confiança', () {
      const q = DecisionQuestion(
        id: 'outage',
        type: DecisionType.noul,
        instructions: 'Is a service down?',
        options: ['true', 'false'],
      );
      final a = answerFromLogits(question: q, logits: [4.0, 0.0]);
      expect(a.noul, greaterThan(0.9));
      expect(a.confidence, isNull);
      expect(a.whyNoConfidence, contains('probability of true'));
    });

    test('empate vai para a opção anterior, e as probabilidades dizem o resto', () {
      final a = answerFromLogits(question: q3, logits: [2.0, 2.0, 2.0]);
      expect(a.choice, 'billing');
      // Três iguais é um terço cada, e o número está lá.
      for (final v in a.probabilities.values) {
        expect(v, closeTo(1 / 3, 1e-9));
      }
    });

    test('uma linha que não bate com as opções recusa, com as duas contagens', () {
      expect(
        () => answerFromLogits(question: q3, logits: [1.0, 2.0]),
        throwsA(
          isA<DecisionRequestError>().having(
            (e) => e.message,
            'message',
            allOf(contains('3 options'), contains('2 logits')),
          ),
        ),
      );
    });
  });

  group('a temperatura por tipo é do arquivo do modelo', () {
    test('os três números são os que o decider-2b publica', () {
      expect(kDecisionTemperature[DecisionType.choice], 1.164);
      expect(kDecisionTemperature[DecisionType.noul], 1.624);
      expect(kDecisionTemperature[DecisionType.score], 1.124);
      expect(kDecisionTemperatureGlobal, 1.145);
    });

    test('noul é a mais alta, como no d1-omni', () {
      // Um padrão que se confirma em dois arquivos de vendors diferentes é um
      // fato sobre a forma, não sobre o modelo.
      final tipos = kDecisionTemperature.values.toList()..sort();
      expect(tipos.last, kDecisionTemperature[DecisionType.noul]);
    });

    test('o mapa do chamador substitui o do módulo', () {
      final a = answerFromLogits(
        question: q3,
        logits: [0.1, 3.0, 0.2],
        temperatureByType: const {DecisionType.choice: 10.0},
      );
      final b = answerFromLogits(question: q3, logits: [0.1, 3.0, 0.2]);
      // Temperatura maior dá confidence menor, e o choice é o mesmo.
      expect(a.choice, b.choice);
      expect(a.confidence!, lessThan(b.confidence!));
    });

    test('um tipo fora do mapa cai no global', () {
      // Passar um mapa com só `noul` tem que deixar `choice` no 1,145 global,
      // e não no 1,164 do módulo. Os dois são próximos o bastante para uma
      // asserção frouxa passar pelos dois — por isso o teste compara com o
      // global EXPLÍCITO e não com a chamada sem mapa.
      final comMapa = answerFromLogits(
        question: q3,
        logits: [0.1, 3.0, 0.2],
        temperatureByType: const {DecisionType.noul: 1.0},
      );
      final comGlobal = answerFromLogits(
        question: q3,
        logits: [0.1, 3.0, 0.2],
        temperature: kDecisionTemperatureGlobal,
      );
      final comModulo = answerFromLogits(question: q3, logits: [0.1, 3.0, 0.2]);
      expect(comMapa.confidence, closeTo(comGlobal.confidence!, 1e-12));
      // E é DIFERENTE do choice do módulo, que é a prova de que o mapa do
      // chamador substitui o do módulo em vez de se juntar a ele.
      expect(comMapa.confidence, isNot(closeTo(comModulo.confidence!, 1e-6)));
    });

    test('temperatura explícita ganha de tudo', () {
      final a = answerFromLogits(question: q3, logits: [0.1, 3.0, 0.2],
          temperature: 0.5);
      final b = answerFromLogits(question: q3, logits: [0.1, 3.0, 0.2]);
      expect(a.choice, b.choice);
      expect(a.confidence!, greaterThan(b.confidence!));
    });
  });

  group('a permutação é a mesma ordem medida do decision_stability', () {
    test('a variante 0 é a lista original', () {
      final p = decisionPermutations([q3], 1);
      expect(p.single.options, q3.options);
    });

    test('cada variante posterior muda a ordem', () {
      final todas = decisionPermutations([q3], 4);
      expect(todas.length, 4);
      expect(todas[0].options, q3.options);
      // E nenhuma_repete a original depois da primeira.
      for (var i = 1; i < todas.length; i++) {
        expect(todas[i].options, isNot(q3.options));
      }
    });

    test('a letra da primeira opção muda entre variantes', () {
      // É o que pega o viés de posição: se `(A)` fosse sempre a mesma opção,
      // um modelo que decora a posição passaria em toda variante.
      final todas = decisionPermutations([q3], 4);
      final primeiras = todas.map((q) => q.options.first).toSet();
      expect(primeiras.length, greaterThan(1));
    });

    test('as permutações são rearranjos, não adições', () {
      final todas = decisionPermutations([q3], 4);
      for (final q in todas) {
        expect(q.options.length, q3.options.length);
        expect(q.options.toSet(), q3.options.toSet());
      }
    });

    test('a ordem das perguntas e os ids sobrevivem', () {
      final questions = [
        q3,
        const DecisionQuestion(
          id: 'outage',
          type: DecisionType.noul,
          instructions: 'Down?',
          options: ['true', 'false'],
        ),
      ];
      final p = decisionPermutations(questions, 3);
      // Três variantes de duas perguntas.
      expect(p.length, 6);
      expect(p[0].id, 'department');
      expect(p[1].id, 'outage');
      expect(p[1].type, DecisionType.noul);
      expect(p[1].instructions, 'Down?');
    });

    test('variants 1 e 0 devolvem a lista sem cópia inútil', () {
      final q = [q3];
      expect(decisionPermutations(q, 1).length, 1);
      expect(decisionPermutations(q, 0).length, 1);
    });

    test('uma opção só não quebra', () {
      const q = DecisionQuestion(
        id: 'x',
        type: DecisionType.noul,
        instructions: 'X?',
        options: ['a', 'b'],
      );
      final p = decisionPermutations([q], 3);
      expect(p.length, 3);
      for (final v in p) {
        expect(v.options.length, 2);
      }
    });
  });

  group('o JSON da resposta usa as chaves do contrato', () {
    test('choice', () {
      final j = answerFromLogits(question: q3, logits: [0.1, 3.0, 0.2]).toJson();
      expect(j['type'], 'choice');
      expect(j['choice'], 'technical support');
      expect(j['confidence'], isA<num>());
      expect(j['probabilities'], isA<Map<String, dynamic>>());
      expect(j.containsKey('why_no_confidence'), isFalse);
    });

    test('noul leva a chave noul e o motivo', () {
      const q = DecisionQuestion(
        id: 'outage',
        type: DecisionType.noul,
        instructions: 'Down?',
        options: ['true', 'false'],
      );
      final j = answerFromLogits(question: q, logits: [4.0, 0.0]).toJson();
      expect(j['type'], 'noul');
      expect(j['noul'], isA<num>());
      expect(j.containsKey('confidence'), isFalse);
      expect(j['why_no_confidence'], isNotNull);
    });

    test('score leva legend indexada por inteiro', () {
      const q = DecisionQuestion(
        id: 'u',
        type: DecisionType.score,
        instructions: 'U?',
        options: ['low', 'high'],
      );
      final j = answerFromLogits(question: q, logits: [0.0, 1.0]).toJson();
      final legend = jsonDecode(jsonEncode(j['legend'])) as Map<String, dynamic>;
      expect(legend.keys.toSet(), {'0', '1'});
      expect(j['score'], 1.0);
    });
  });
}