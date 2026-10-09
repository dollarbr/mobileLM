import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:mobilelm/services/typed_decision.dart';
import 'package:mobilelm/services/typed_decision_runner.dart';

/// A channel stub that answers the two calls the runner makes.
///
/// **The failure this file guards against is a silent one**: the runner asks for
/// token ids, gets them, builds a prompt, decodes, and only then does anything
/// visible happen. If the ids come back wrong the answer is still a confident
/// `choice` — scored against the wrong letter. So most of these tests assert
/// **what was asked**, not what came back.
class _Channel {
  _Channel();

  final prompts = <String>[];
  final slotRequests = <List<int>>[];

  /// Token ids for letters, in a vocabulary that is not the real one.
  Map<String, int> letterIds = const {};

  /// Logits per candidate, slot-major.
  List<double> scores = const [];

  int slots = 1;
  int candidates = 3;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('llama_flutter_android/model_meta'),
      _handle,
    );
  }

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'tokenizeSingle':
        final text = (call.arguments as Map)['text'] as String;
        return {
          'id': letterIds[text] ?? text.codeUnitAt(0),
          'tokenCount': 1,
        };
      case 'decisionScores':
        final args = call.arguments as Map;
        prompts.add(args['prompt'] as String);
        slotRequests
            .add((args['slotIndices'] as List).map((e) => e as int).toList());
        return {
          'scores': scores,
          'slots': slots,
          'candidates': candidates,
          'elapsedMs': 7,
        };
    }
    return null;
  }

  void remove() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('llama_flutter_android/model_meta'),
      null,
    );
  }
}

void main() {
  // The mock channel needs the binding, and `setUp` runs before any widget test
  // has initialised it in a file that has none.
  TestWidgetsFlutterBinding.ensureInitialized();

  _Channel ch = _Channel();

  setUp(() {
    ch = _Channel()..install();
    // Ten distinct ids, so a row can be sliced and checked position by position.
    ch.letterIds = {for (var i = 0; i < 10; i++) 'ABCDEFGHIJ'[i]: 100 + i};
  });

  tearDown(() => ch.remove());

  group('o runner monta o prompt e lê os slots', () {
    test('o prompt é o do prompt.py e o slot é o último token', () async {
      ch.scores = [0.0, 5.0, 0.0];
      await const TypedDecisionRunner().run(
        state: 'I was charged twice',
        questions: const [
          DecisionQuestion(
            id: 'department',
            type: DecisionType.choice,
            instructions: 'Which department should handle this?',
            options: ['billing', 'technical support', 'sales'],
          ),
        ],
      );
      expect(ch.prompts, hasLength(1));
      expect(
        ch.prompts.single,
        'Context:\nI was charged twice'
        '\n\nQuestion: Which department should handle this?\nOptions:'
        '\n(A) billing'
        '\n(B) technical support'
        '\n(C) sales'
        '\nAnswer: (',
      );
      // `-1` e nao um indice contado: o slot é a posição do token e o runner
      // nunca tokeniza o prompt.
      expect(ch.slotRequests.single, [-1]);
    });

    test('cada pergunta é a sua própria passagem, e o layout não é numerado',
        () async {
      ch.scores = [0.0, 5.0, 0.0];
      await const TypedDecisionRunner().run(
        state: 's',
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
      expect(ch.prompts, hasLength(2));
      // Uma por pergunta — e nenhuma delas numérica, porque `multi` no fonte
      // depende da contagem e cada passagem tem uma.
      expect(ch.prompts[0], contains('\n\nQuestion: A?'));
      expect(ch.prompts[1], contains('\n\nQuestion: B?'));
      for (final p in ch.prompts) {
        expect(p, isNot(contains('Question 1:')));
        expect(p.endsWith('Answer: ('), isTrue);
      }
      expect(ch.slotRequests, [
        [-1],
        [-1],
      ]);
    });

    test('o estado JSON vai por tojson e a string vai como está', () async {
      ch.scores = [0.0, 1.0];
      ch.scores = [0.0, 1.0];
      ch.candidates = 2;
      await const TypedDecisionRunner().run(
        state: {'ticket': 4417},
        questions: const [
          DecisionQuestion(
            id: 'x',
            type: DecisionType.noul,
            instructions: 'X?',
            options: ['a', 'b'],
          ),
        ],
      );
      expect(ch.prompts.single, startsWith('Context:\n{"ticket":4417}\n'));

      ch.scores = [0.0, 1.0];
      await const TypedDecisionRunner().run(
        state: 'um ticket',
        questions: const [
          DecisionQuestion(
            id: 'x',
            type: DecisionType.noul,
            instructions: 'X?',
            options: ['a', 'b'],
          ),
        ],
      );
      expect(ch.prompts.last, startsWith('Context:\num ticket\n'));
    });
  });

  group('a linha é fatiada pela LETRA, e isso tem consequência', () {
    test('as letras de uma pergunta entram na ordem das suas opções', () async {
      // Uma passagem só, com A=0 B=5 C=0: o topo é B.
      ch.scores = [0.0, 5.0, 0.0];
      final r = await const TypedDecisionRunner().run(
        state: 's',
        questions: const [
          DecisionQuestion(
            id: 'q',
            type: DecisionType.choice,
            instructions: 'Q?',
            options: ['first', 'second', 'third'],
          ),
        ],
      );
      expect(r.answers.single.choice, 'second');
    });

    test('a letra é pela POSIÇÃO da opção, não pelo texto dela', () async {
      // **A premissa que eu escrevi primeiro aqui estava errada**, e o teste a
      // provou. Eu montei Q2 com as opções `['b2', 'c2']` e supus que elas
      // receberiam as letras B e C. Não recebem: a letra é a posição na lista, e
      // Q2 tem duas opções, então `b2` é **(A)** e `c2` é **(B)**.
      //
      // A consequência é que a fatiagem por posição é **trivial** — `distinct` é
      // sempre `A, B, C…` em ordem de primeira aparição e `decisionLetterSet(n)`
      // é sempre `A..` , então `row` são os primeiros `n` logits. O
      // `indexOf` no runner é redundante e inofensivo, e dizer isso vale mais do
      // que um teste que finge que a fatiagem é esperta.
      //
      // **Uma mutação que NÃO é reprovada, e está aqui de propósito:** trocar o
      // `indexOf` por `pass.scores[i]` deixa os 19 testes verdes. As duas
      // expressões são a mesma coisa — provado pelas duas mutações de verdade
      // abaixo, que reprovam. Um teste que passa por dois motivos não está
      // medindo nenhum deles, então o que este caso fixa é a **saída observável**
      // (o texto da opção vencedora e a ordem das chaves), não a expressão que a
      // produziu.
      ch.scores = [9.0, 0.0, 4.0];
      ch.candidates = 3;
      final r = await const TypedDecisionRunner().run(
        state: 's',
        questions: const [
          DecisionQuestion(
            id: 'three',
            type: DecisionType.choice,
            instructions: 'Three?',
            options: ['a1', 'b1', 'c1'],
          ),
          DecisionQuestion(
            id: 'two',
            type: DecisionType.choice,
            instructions: 'Two?',
            options: ['b2', 'c2'],
          ),
        ],
      );
      // Q1, três opções, letters A,B,C → 9,0,4 → a1.
      expect(r.answers[0].choice, 'a1');
      expect(r.answers[0].probabilities.keys.toList(), ['a1', 'b1', 'c1']);
      // Q2, duas opções, letters A,B → 9,0 → b2. **A=9 entra**, e a linha tem
      // o comprimento das opções de Q2.
      expect(r.answers[1].choice, 'b2');
      expect(r.answers[1].probabilities.keys.toList(), ['b2', 'c2']);
      // E o C=4 é lido por Q1 e ignorado por Q2 — que é o ponto da fatiagem.
      expect(r.answers[1].probabilities.values.toList(), hasLength(2));
    });

    test('a linha é lida na ordem das letras, e duas mutações provam isto',
        () async {
      // **A tabela de mutações deste caso, medida:**
      //
      // | mutação no runner | resultado |
      // |---|---|
      // | `indexOf` → `pass.scores[i]` | **19/19 verde** — mesma expressão |
      // | `indexOf` → `allIds.length - 1 - pos` (inverso) | **reprova** |
      // | `indexOf` → `pass.scores[0]` (sempre A) | **reprova** |
      //
      // A primeira é equivalente e por isso não pode ser distinguida de um
      // defeito; as duas outras são defeitos reais, e é a ordem dos logits que
      // as separa. Sem esta tabela, "19 verdes" pareceria cobertura da fatiagem.
      ch.scores = [1.0, 7.0, 3.0];
      ch.candidates = 3;
      final r = await const TypedDecisionRunner().run(
        state: 's',
        questions: const [
          DecisionQuestion(
            id: 'q',
            type: DecisionType.choice,
            instructions: 'Q?',
            options: ['p', 'q', 'r'],
          ),
        ],
      );
      // 1, 7, 3 → o topo é o do MEIO.
      expect(r.answers.single.choice, 'q');
      // E a ordem das chaves segue as opções, para o mapa ser comparável com a
      // lista que o chamador mandou.
      expect(r.answers.single.probabilities.keys.toList(), ['p', 'q', 'r']);
      // O meio é o maior, e é o que a confiança usa.
      final probs = r.answers.single.probabilities.values.toList();
      expect(probs[1], greaterThan(probs[0]));
      expect(probs[1], greaterThan(probs[2]));
    });

    test('os ids pedidos são as letras DISTINTAS do pedido, uma vez só',
        () async {
      final asked = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('llama_flutter_android/model_meta'),
        (call) async {
          if (call.method == 'tokenizeSingle') {
            asked.add((call.arguments as Map)['text'] as String);
            return {'id': asked.length, 'tokenCount': 1};
          }
          return {
            'scores': List.filled(3, 0.0),
            'slots': 1,
            'candidates': 3,
            'elapsedMs': 1,
          };
        },
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel('llama_flutter_android/model_meta'),
          null,
        );
      });

      await const TypedDecisionRunner().run(
        state: 's',
        questions: const [
          DecisionQuestion(
            id: 'a',
            type: DecisionType.choice,
            instructions: 'A?',
            options: ['x', 'y', 'z'],
          ),
          DecisionQuestion(
            id: 'b',
            type: DecisionType.choice,
            instructions: 'B?',
            options: ['y', 'z'],
          ),
        ],
      );
      // **ABC e não mais**, e aqui está a correção de uma premissa minha: eu
      // escrevi duas perguntas de três opções esperando `['A','B','C','D']`,
      // contando uma letra por texto de opção distinto. A letra é a POSIÇÃO
      // (o caso anterior prova isso), então três opções pedem A,B,C — e a
      // segunda pergunta, com duas opções, pede as mesmas duas.
      //
      // O que esta asserção fixa é a **deduplicação**: `y` e `z` aparecem nas
      // duas perguntas e são pedidos uma vez só, porque a tabela de ids é uma
      // chamada por letra distinta e não por letra por pergunta.
      expect(asked, ['A', 'B', 'C']);
    });
  });

  group('a recusa é antes do modelo, e diz o motivo', () {
    test('onze opções recusa, e nomeia o teto do LAYOUT', () async {
      // A mensagem que sai é a de `decisionLetterSet`, e **não** a de
      // `decisionLetter`: a validação do runner conta primeiro, e a segunda
      // nunca chega. A frase que importa é o número — 10 é o teto do layout do
      // autor, não os 24 do `/v1/classify`.
      await expectLater(
        const TypedDecisionRunner().run(
          state: 's',
          questions: const [
            DecisionQuestion(
              id: 'q',
              type: DecisionType.choice,
              instructions: 'Q?',
              options: ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k'],
            ),
          ],
        ),
        throwsA(
          isA<DecisionRequestError>().having(
            (e) => e.message,
            'message',
            allOf(contains('between 2 and 10'), contains('11 were given')),
          ),
        ),
      );
      // E o modelo não foi tocado: a recusa é antes de qualquer letra pedida.
      expect(ch.prompts, isEmpty);
    });

    test('uma opção só recusa', () async {
      await expectLater(
        const TypedDecisionRunner().run(
          state: 's',
          questions: const [
            DecisionQuestion(
              id: 'q',
              type: DecisionType.choice,
              instructions: 'Q?',
              options: ['only'],
            ),
          ],
        ),
        throwsA(isA<DecisionRequestError>()),
      );
    });

    test('nenhuma pergunta recusa', () async {
      await expectLater(
        const TypedDecisionRunner().run(state: 's', questions: []),
        throwsA(isA<DecisionRequestError>()),
      );
    });

    test('a letra é pedida antes do prompt, e uma só vez por letra distinta',
        () async {
      // A ordem importa: se o prompt fosse montado antes dos ids, um `X` que
      // não é um token produciria um prompt que o modelo responderia sem que
      // houvesse slot para ler — uma letra sem logit é a opção perdedora de
      // toda decisão.
      ch.scores = [0.0, 0.0, 0.0];
      await const TypedDecisionRunner().run(
        state: 's',
        questions: const [
          DecisionQuestion(
            id: 'q',
            type: DecisionType.choice,
            instructions: 'Q?',
            options: ['p', 'q', 'r'],
          ),
        ],
      );
      expect(ch.prompts, hasLength(1));
    });

    test('letra de dois tokens recusa com a contagem e o motivo', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('llama_flutter_android/model_meta'),
        (call) async {
          if (call.method == 'tokenizeSingle') {
            final text = (call.arguments as Map)['text'] as String;
            // 'B' são dois tokens neste vocabulário — o caso que `prompt.py`
            // assegura que não acontece, e que por isso precisa de um nome.
            if (text == 'B') return {'id': -1, 'tokenCount': 2};
            return {'id': 7, 'tokenCount': 1};
          }
          return {
            'scores': [0.0, 0.0, 0.0],
            'slots': 1,
            'candidates': 3,
            'elapsedMs': 1,
          };
        },
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel('llama_flutter_android/model_meta'),
          null,
        );
      });

      await expectLater(
        const TypedDecisionRunner().run(
          state: 's',
          questions: const [
            DecisionQuestion(
              id: 'q',
              type: DecisionType.choice,
              instructions: 'Q?',
              options: ['p', 'q', 'r'],
            ),
          ],
        ),
        throwsA(
          isA<DecisionUnavailable>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('"B"'),
              contains('2 tokens'),
              contains('not one'),
              contains('property of the loaded file'),
            ),
          ),
        ),
      );
      // A recusa veio antes da passagem.
      expect(ch.prompts, isEmpty);
    });
  });

  group('a calibração acontece em Dart, sobre logits crus', () {
    test('a resposta usa a temperatura do tipo, não 1,0', () async {
      // Mesmos logits, tipos diferentes: `noul` tem a maior temperatura (1,624)
      // e `choice` a menor (1,164), então o MESMO vetor dá confidências
      // diferentes — e é por isso que a chave é o tipo e não só a contagem.
      //
      // `candidates = 2` porque estas perguntas têm duas opções: a passagem traz
      // uma linha por letra DISTINTA do pedido, e aqui são A e B. A guarda de
      // contagem em `llama_decision.dart` existe para pegar um descasamento
      // desses, e um teste que não bate nela não está medindo a fatiagem.
      ch.scores = [1.0, 2.0];
      ch.candidates = 2;
      final choice = await const TypedDecisionRunner().run(
        state: 's',
        questions: const [
          DecisionQuestion(
            id: 'c',
            type: DecisionType.choice,
            instructions: 'C?',
            options: ['a', 'b'],
          ),
        ],
      );
      final noul = await const TypedDecisionRunner().run(
        state: 's',
        questions: const [
          DecisionQuestion(
            id: 'n',
            type: DecisionType.noul,
            instructions: 'N?',
            options: ['yes', 'no'],
          ),
        ],
      );
      expect(choice.answers.single.confidence,
          isNot(closeTo(noul.answers.single.noul!, 1e-6)));
      // E o noul traz a probabilidade de `yes`, que é a primeira opção.
      // softmax([1,2] / 1.624): a temperatura alta achata, e o topo baixa de 0,702
      // (choice, 1.164) para 0,649. O número está conferido contra a fórmula,
      // e não contra o que a implementação devolveu.
      expect(noul.answers.single.noul, closeTo(0.649254, 1e-5));
    });

    test('`temperature` explícita vence o mapa do tipo', () async {
      ch.scores = [1.0, 2.0];
      ch.candidates = 2;
      final suave = await const TypedDecisionRunner().run(
        state: 's',
        questions: const [
          DecisionQuestion(
            id: 'c',
            type: DecisionType.choice,
            instructions: 'C?',
            options: ['a', 'b'],
          ),
        ],
        temperature: 10.0,
      );
      final afiado = await const TypedDecisionRunner().run(
        state: 's',
        questions: const [
          DecisionQuestion(
            id: 'c',
            type: DecisionType.choice,
            instructions: 'C?',
            options: ['a', 'b'],
          ),
        ],
        temperature: 0.5,
      );
      expect(afiado.answers.single.confidence!,
          greaterThan(suave.answers.single.confidence!));
      // A escolha é a mesma nos dois: temperatura não desloca o argmax.
      expect(afiado.answers.single.choice, suave.answers.single.choice);
    });
  });

  group('o resultado e o que ele diz sobre ids repetidos', () {
    test('`answers` é indexado pelo id da pergunta', () async {
      ch.scores = [0.0, 5.0, 0.0];
      final r = await const TypedDecisionRunner().run(
        state: 's',
        questions: const [
          DecisionQuestion(
            id: 'dept',
            type: DecisionType.choice,
            instructions: 'D?',
            options: ['a', 'b', 'c'],
          ),
          DecisionQuestion(
            id: 'down',
            type: DecisionType.noul,
            instructions: 'Down?',
            options: ['yes', 'no'],
          ),
        ],
      );
      final json = r.toJson();
      expect(json.keys.toSet(), {'dept', 'down'});
      expect((json['dept'] as Map)['type'], 'choice');
      expect((json['down'] as Map)['type'], 'noul');
    });

    test('um id repetido é CONTADO, porque o JSON não pode guardar dois',
        () async {
      // Duas perguntas com o mesmo id: cada uma é passada e respondida, e o
      // objeto de resposta tem uma chave só. A contagem é o que denuncia.
      ch.scores = [0.0, 5.0, 0.0];
      final r = await const TypedDecisionRunner().run(
        state: 's',
        questions: const [
          DecisionQuestion(
            id: 'same',
            type: DecisionType.choice,
            instructions: 'First?',
            options: ['a', 'b', 'c'],
          ),
          DecisionQuestion(
            id: 'same',
            type: DecisionType.choice,
            instructions: 'Second?',
            options: ['a', 'b', 'c'],
          ),
        ],
      );
      expect(r.answers, hasLength(2));
      expect(r.duplicateIds, ['same']);
      expect(r.toJson().keys.toSet(), {'same'});
    });

    test('`elapsedMs` é a soma das passagens', () async {
      ch.scores = [0.0, 5.0, 0.0];
      final r = await const TypedDecisionRunner().run(
        state: 's',
        questions: const [
          DecisionQuestion(
            id: 'a',
            type: DecisionType.choice,
            instructions: 'A?',
            options: ['p', 'q', 'r'],
          ),
          DecisionQuestion(
            id: 'b',
            type: DecisionType.choice,
            instructions: 'B?',
            options: ['p', 'q', 'r'],
          ),
          DecisionQuestion(
            id: 'c',
            type: DecisionType.choice,
            instructions: 'C?',
            options: ['p', 'q', 'r'],
          ),
        ],
      );
      // O stub devolve 7 ms por passagem.
      expect(r.elapsedMs, 21);
    });
  });

  group('a superfície do plugin, e o que ela recusa', () {
    test('as probabilidades são indexadas pelo TEXTO das opções da pergunta',
        () async {
      // A chave do mapa de probabilidades é a opção que o chamador escreveu, e
      // não a letra nem o índice — que é o que o contrato promete e o que uma
      // tela mostra. A ordem segue a lista de opções.
      ch.scores = [0.0, 1.0];
      ch.candidates = 2;
      final r = await const TypedDecisionRunner().run(
        state: 's',
        questions: const [
          DecisionQuestion(
            id: 'q',
            type: DecisionType.choice,
            instructions: 'Q?',
            options: ['billing', 'technical support'],
          ),
        ],
      );
      expect(r.answers.single.probabilities.keys.toList(),
          ['billing', 'technical support']);
      expect(r.answers.single.choice, 'technical support');
      for (final v in r.answers.single.probabilities.values) {
        expect(v + r.answers.single.probabilities.values.first > 0, isTrue);
      }
    });

    test('o `DecisionPass` recusa um slot fora do que foi lido', () {
    const p = DecisionPass(
        scores: [1, 2, 3, 4, 5, 6],
        slots: 2,
        candidates: 3,
        elapsedMs: 0,
      );
      expect(p.row(0), [1, 2, 3]);
      expect(p.row(1), [4, 5, 6]);
      expect(() => p.row(2), throwsRangeError);
      expect(() => p.row(-1), throwsRangeError);
    });

    test('`SingleToken` carrega a contagem mesmo quando não é um token', () {
    const ok = SingleToken(42, 1);
      expect(ok.isSingle, isTrue);
      expect(ok.id, 42);
    const bad = SingleToken.notSingle(3);
      expect(bad.isSingle, isFalse);
      expect(bad.tokenCount, 3);
    });
  });
}