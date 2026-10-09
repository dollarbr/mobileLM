import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/services/system_one.dart';

/// The payload shapes, copied from **three measured A72 calls** rather than
/// written by hand.
///
/// The reason they are copied and not invented is the one this repo has paid for
/// twice: `HeadContract` was written against a payload the device never sent, and
/// the test passed because it fed the test the shape the test believed in. The
/// numbers below are the ones the device produced on 09/10/2026 with
/// `tev1-Q8_0.gguf`, CPU, `gpu_layers=0`.
Map<String, dynamic> noulPayload({
  double yes = 0.5187502236429473,
  double no = 0.4812497763570528,
}) =>
    {
      'object': 'systemone.decision',
      'model': 'tev1-Q8_0.gguf',
      'answers': {
        'outage': {
          'type': 'noul',
          'noul': yes,
          'probabilities': {
            'yes, the statement holds': yes,
            'no, the statement does not hold': no,
          },
          'why_no_confidence':
              'noul answers report the probability of true, which is the '
              'contract for this shape; confidence is defined for choice and '
              'score, where the distance between options carries information '
              'that the probability alone does not.',
        },
      },
      'usage': {'questions': 1, 'passes': 1, 'forward_pass_ms': 8163},
    };

Map<String, dynamic> choicePayload({
  double a = 0.6972008310348793,
  double b = 0.25251591202329776,
  double c = 0.050283256941822875,
  double confidence = 0.545801246552319,
}) =>
    {
      'object': 'systemone.decision',
      'model': 'tev1-Q8_0.gguf',
      'answers': {
        'department': {
          'type': 'choice',
          'choice': 'billing: Charges, refunds and invoices',
          'confidence': confidence,
          'probabilities': {
            'billing: Charges, refunds and invoices': a,
            'technical: Bugs and outages': b,
            'sales: Pre-sale questions': c,
          },
        },
      },
      'usage': {'questions': 1, 'passes': 1, 'forward_pass_ms': 8287},
    };

Map<String, dynamic> scorePayload({
  double level = 0.0,
  double confidence = 0.3305127894396154,
}) =>
    {
      'object': 'systemone.decision',
      'model': 'tev1-Q8_0.gguf',
      'answers': {
        'urgency': {
          'type': 'score',
          'score': level,
          'confidence': confidence,
          'legend': {'0': 'Can wait', '1': 'This week', '2': 'Today'},
          'probabilities': {
            'Can wait': 0.5536751929597435,
            'This week': 0.3239990307893367,
            'Today': 0.12232577625091977,
          },
        },
      },
      'usage': {'questions': 1, 'passes': 1, 'forward_pass_ms': 7971},
    };

void main() {
  group('o leitor de /v1/systemone, contra os tres payloads medidos', () {
    test('noul: a probabilidade de true, e o motivo de nao haver confidence', () {
      final r = const SystemOneResult().fromSystemOne(noulPayload());
      expect(r.shape, SystemOneShape.typedDecision);
      expect(r.readout, SystemOneReadout.logit);
      expect(r.answerType, 'noul');
      expect(r.noul, closeTo(0.5187502236429473, 1e-12));
      expect(r.probabilities.length, 2);
      // A confidence e AUSENTE e o motivo esta la. Um painel com o campo vazio
      // pareceria quebrado; o motivo e o que diz que esta certo.
      expect(r.confidence, isNull);
      expect(r.whyNoConfidence, contains('probability of true'));
      expect(r.passes, 1);
      expect(r.model, 'tev1-Q8_0.gguf');
    });

    test('choice: a confianca medida, e NAO a probabilidade do topo', () {
      final r = const SystemOneResult().fromSystemOne(choicePayload());
      expect(r.answerType, 'choice');
      expect(r.label, 'billing: Charges, refunds and invoices');
      // A diferenca que importa: 0,6972 do topo contra 0,5458 de confianca.
      // Sao numeros diferentes para a mesma decisao, e um painel que mostra
      // qualquer um dos dois como se fosse o outro esta errado.
      final top = r.probabilities.values.reduce((a, b) => a > b ? a : b);
      expect(top, closeTo(0.6972008310348793, 1e-12));
      expect(r.confidence, closeTo(0.545801246552319, 1e-12));
      expect(r.confidence, isNot(closeTo(top, 1e-3)));
      expect(r.noul, isNull);
      expect(r.whyNoConfidence, isNull);
    });

    test('score: o indice do nivel, a legenda por indice e a confianca', () {
      final r = const SystemOneResult().fromSystemOne(scorePayload());
      expect(r.answerType, 'score');
      expect(r.score, 0.0);
      expect(r.legend, {0: 'Can wait', 1: 'This week', 2: 'Today'});
      expect(r.confidence, closeTo(0.3305127894396154, 1e-12));
      // A legenda e indexada por INTEIRO, e o endpoint manda chave de objeto.
      // `Map<String, String>` seria mais facil e perderia a numeracao que o
      // `score` responde — que e o mesmo numero do indice.
      expect(r.legend.keys.toList(), [0, 1, 2]);
    });

    test('o `letter` e NUL nos tres: nada foi gerado', () {
      // Este e o ponto de nao inventar. O shape `decision` tem `letter` porque o
      // modelo emitiu uma letra. Aqui nao houve geracao nenhuma — uma passagem,
      // zero tokens de saida — e mostrar uma letra seria o app fabricando a
      // evidencia do proprio metodo.
      for (final p in [noulPayload(), choicePayload(), scorePayload()]) {
        final r = const SystemOneResult().fromSystemOne(p);
        expect(r.letter, isNull, reason: 'fabricou uma letra');
      }
    });

    test('o `label` do score e o indice, porque a resposta traz um indice', () {
      final r = const SystemOneResult().fromSystemOne(scorePayload(level: 2));
      expect(r.score, 2.0);
      expect(r.label, '2.0');
    });
  });

  group('a recusa e um resultado, e traz a frase do endpoint', () {
    test('o teto de dez opcoes sai com o numero', () {
      final r = const SystemOneResult().fromSystemOne(
        {
          'error':
              'A decision needs between 2 and 10 options, and 11 were given.',
        },
        status: 400,
      );
      expect(r.isFailure, isTrue);
      expect(r.failure, contains('between 2 and 10'));
      expect(r.failure, contains('11 were given'));
      // E continua sendo do shape certo, porque um painel que sobe o erro
      // trocando de aba mostra a pessoa a aba errada.
      expect(r.shape, SystemOneShape.typedDecision);
    });

    test('uma letra que nao e um token traz a contagem', () {
      final r = const SystemOneResult().fromSystemOne(
        {
          'error': 'The letter "B" is 2 tokens in this model\'s vocabulary, '
              'not one. A decision is read by restricting the LM head to '
              'single-letter tokens, so a letter that splits has no logit to '
              'read and the prompt cannot be built. This is a property of the '
              'loaded file, not of the request.',
        },
        status: 400,
      );
      expect(r.failure, contains('"B"'));
      expect(r.failure, contains('2 tokens'));
    });

    test('resposta sem answers NAO e um resultdo vazio: e uma falha nomeada', () {
      final r = const SystemOneResult().fromSystemOne({'model': 'x'});
      expect(r.isFailure, isTrue);
      // A frase diz o que faltou, porque "answers missing" e um diagnostico e
      // um painel em branco nao e.
      expect(r.failure, contains('missing'));
    });

    test('answers vazio tambem e falha, e a frase distingue de missing', () {
      final r = const SystemOneResult().fromSystemOne({
        'model': 'x',
        'answers': <String, dynamic>{},
      });
      expect(r.failure, contains('empty'));
    });
  });

  group('varias perguntas: todas sao contadas, uma e mostrada', () {
    test('o payload de duas perguntas conta as duas', () {
      // Medido: 2 perguntas numa chamada = 2 passagens = 16.141 ms.
      final r = const SystemOneResult().fromSystemOne({
        'model': 'tev1-Q8_0.gguf',
        'answers': {
          'outage': {
            'type': 'noul',
            'noul': 0.61,
            'probabilities': {'yes, the statement holds': 0.61},
          },
          'department': {
            'type': 'choice',
            'choice': 'technical: Bugs and outages',
            'confidence': 0.4,
            'probabilities': {'technical: Bugs and outages': 0.4},
          },
        },
        'usage': {'questions': 2, 'passes': 2, 'forward_pass_ms': 16141},
      });
      expect(r.passes, 2);
      // Uma mostrada, as duas contadas — e o painel diz qual.
      expect(r.notes.any((n) => n.contains('2 questions answered')), isTrue);
      expect(r.notes.any((n) => n.startsWith('question: ')), isTrue);
      // A ordem do mapa decide qual aparece, e o endpoint manda na ordem do
      // request — a primeira pergunta é a que a pessoa mandou primeiro.
      expect(r.answerType, 'noul');
    });

    test('um id repetido é dito, porque o JSON não guarda dois', () {
      final r = const SystemOneResult().fromSystemOne({
        'model': 'x',
        'answers': {
          'same': {'type': 'noul', 'noul': 0.5},
        },
        'why_answers_dropped':
            'These question ids appeared more than once, and a JSON object '
            'holds one value per key: same.',
        'usage': {'questions': 2, 'passes': 2, 'forward_pass_ms': 16},
      });
      expect(r.notes.any((n) => n.contains('holds one value per key')), isTrue);
    });
  });

  group('o corpo que a tela monta, e por que nao é `options`', () {
    final opts = SystemOneOptions(
      const [
        SystemOneOption('A', 'billing'),
        SystemOneOption('B', 'technical support'),
        SystemOneOption('C', 'sales'),
      ],
    );

    test('choice manda criteria como MAPA, com a letra como valor', () {
      final body = const SystemOneResult().systemOneBody(
        state: 'charged twice',
        questionId: 'department',
        questionType: 'choice',
        options: opts,
        instructions: 'Which team?',
      );
      final q = (body['questions'] as Map)['department'] as Map;
      expect(q['type'], 'choice');
      expect(q['instructions'], 'Which team?');
      // Mapa e nao lista: o endpoint renderiza `key: description`, que e o
      // prompt com que o modelo foi calibrado. Uma lista aqui daria um pedido
      // valido com outro prompt.
      expect(q['criteria'], isA<Map>());
      expect((q['criteria'] as Map).keys.toList(), ['A', 'B', 'C']);
      expect((q['criteria'] as Map)['A'], 'billing');
    });

    test('score manda criteria como LISTA, porque o índice É o valor', () {
      final body = const SystemOneResult().systemOneBody(
        state: 's',
        questionId: 'urgency',
        questionType: 'score',
        options: opts,
      );
      final q = (body['questions'] as Map)['urgency'] as Map;
      expect(q['criteria'], isA<List>());
      expect(q['criteria'], ['billing', 'technical support', 'sales']);
      // E sem instructions, porque o id é a pergunta — a regra do contrato.
      expect(q.containsKey('instructions'), isFalse);
    });

    test('noul nao manda criteria: o endpoint escreve as frases do modelo', () {
      final body = const SystemOneResult().systemOneBody(
        state: 's',
        questionId: 'outage',
        questionType: 'noul',
        options: opts,
        instructions: 'Is a service down?',
      );
      final q = (body['questions'] as Map)['outage'] as Map;
      expect(q['type'], 'noul');
      expect(q['instructions'], 'Is a service down?');
      // Mandar criteria para um noul seria um pedido que o modelo le como um
      // choice de tres opcoes.
      expect(q.containsKey('criteria'), isFalse);
    });

    test('temperature é omitido por padrao, e isso é uma decisão', () {
      final body = const SystemOneResult().systemOneBody(
        state: 's',
        questionId: 'q',
        questionType: 'choice',
        options: opts,
      );
      // O endpoint aplica a temperatura por tipo que o proprio arquivo traz.
      // Uma tela que mandasse 1.0 sobrescreveria uma calibracao que nao ve.
      expect(body.containsKey('temperature'), isFalse);
      // E mandando, ele vai.
      final comT = const SystemOneResult().systemOneBody(
        state: 's',
        questionId: 'q',
        questionType: 'choice',
        options: opts,
        temperature: 1.5,
      );
      expect(comT['temperature'], 1.5);
    });

    test('o state vai como o chamador escreveu, sem embrulhar', () {
      final body = const SystemOneResult().systemOneBody(
        state: 'um ticket de texto',
        questionId: 'q',
        questionType: 'choice',
        options: opts,
      );
      expect(body['state'], 'um ticket de texto');
      // O endpoint decide string-vs-JSON pelo TIPO Dart, e re-encodar aqui
      // colocaria aspas num ticket e mudaria o que o modelo le.
      expect(body['state'], isA<String>());
    });
  });

  group('o shape novo e as regras que dependem dele', () {
    test('typedDecision responde classe, como as outras tres formas', () {
      expect(isClassAnswering(SystemOneShape.typedDecision), isTrue);
    });

    test('unknown NAO responde classe, e typedDecision nao muda isso', () {
      expect(isClassAnswering(SystemOneShape.unknown), isFalse);
    });

    test('systemOneShapeOf NAO devolve typedDecision: nenhum arquivo o produz',
        () {
      // O shape de um arquivo e decidido por fatos do arquivo, e nenhum arquivo
      // tem este shape — ele é uma ESCOLHA de leitura. Devolver aqui seria um
      // detector affirmando algo que não mediu.
      for (final head in [true, false]) {
        expect(
          systemOneShapeOf(hasClassificationHead: head),
          isNot(SystemOneShape.typedDecision),
        );
      }
      expect(
        systemOneShapeOf(filename: 'x.tflite'),
        SystemOneShape.tfliteHead,
      );
    });

    test('os dois readouts sao nomeados e o parse cai no letter', () {
      expect(SystemOneReadout.parse('logit'), SystemOneReadout.logit);
      expect(SystemOneReadout.parse('letter'), SystemOneReadout.letter);
      // Desconhecido cai no letter, que e o caminho que existia antes: uma tela
      // que nao sabe o que ler mostra o que sempre mostrou.
      expect(SystemOneReadout.parse('nope'), SystemOneReadout.letter);
      expect(SystemOneReadout.parse(null), SystemOneReadout.letter);
    });

    test('um /v1/classify normal NAO ganha readout', () {
      // O payload antigo nao tem `answers` e nao tem `confidence`; afirmar um
      // readout seria a tela inventando a procedencia de um numero.
      final r = const SystemOneResult().fromClassify({
        'model': 'tev1-Q8_0.gguf',
        'label': 'bug',
        'choice': 'B',
        'match': 'letter',
        'followed_contract': true,
      });
      expect(r.readout, isNull);
      expect(r.confidence, isNull);
      expect(r.probabilities, isEmpty);
      expect(r.letter, 'B');
      expect(r.shape, SystemOneShape.decision);
    });
  });

  group('a tabela de mutações deste arquivo', () {
    test('ler o `letter` do `choice` tipado reprova', () {
      // A mutação é `letter: type == 'choice' ? (first['choice'] as String)[0] : null`
      // — "a letra é a inicial da opção". Ela produziria `b` para
      // "billing: …", que é a letra **fabricada**, e o painel mostraria uma
      // evidência de método que não existe.
      final r = const SystemOneResult().fromSystemOne(choicePayload());
      expect(r.letter, isNull);
      expect(r.label, isNotNull);
    });

    test('mostrar a probabilidade do topo como confidence reprova', () {
      final r = const SystemOneResult().fromSystemOne(choicePayload());
      final top = r.probabilities.values.reduce((a, b) => a > b ? a : b);
      expect(r.confidence, isNot(closeTo(top, 1e-3)));
    });

    test('ler a legenda como Map<String, String> reprova', () {
      final r = const SystemOneResult().fromSystemOne(scorePayload());
      expect(r.legend.keys.every((k) => k is int), isTrue);
      expect(r.legend.keys.any((k) => k is String), isFalse);
    });

    test('engolir a recusa reprova', () {
      final r = const SystemOneResult().fromSystemOne(
        {'error': 'A decision needs between 2 and 10 options'},
        status: 400,
      );
      expect(r.isFailure, isTrue);
    });
  });
}