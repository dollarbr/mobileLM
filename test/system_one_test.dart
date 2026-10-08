import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/services/decision_model.dart';
import 'package:mobilelm/services/system_one.dart';

/// The test window's model layer.
///
/// Every payload below is a **shape the server actually returns**, copied from
/// `openai_server_service_io.dart` — the decision 200, the decision 422, and the
/// `.tflite` 200 with the Laya act head's two logits. Testing against a shape
/// invented here is how a parser passes and the screen shows nothing, which is
/// the failure mode this repo has already paid for three times: something
/// asserted from a promise rather than from what came back.

// ── HeadContract: os payloads sao COPIADOS do A72 ──────────────────────────
//
// Estes dois JSON sao literalmente o que o Galaxy A72 devolveu para
// `laya_en_act_head_fp32.tflite`, capturados com curl. A primeira versao desta
// janela parseou o `signature` como um **objeto** com `inputs` dentro, e o
// aparelho manda uma **array** `signatures` — entao a contagem.features nunca
// aparecia e a janela dizia "qualquer comprimento serve" para uma cabeca que
// quer 1024 numeros. O teste passou porque alimentava a forma que eu tinha
// imaginado. A lição ja esta no repo; o que faltava era o payload real.

/// `POST /v1/litert/screen`, copiado do A72.
const layaScreen = {
  'version': 3,
  'description': 'MLIR Converted.',
  'signatures': [
    {
      'signature': 'serving_default',
      'subgraph': 0,
      'inputs': [
        {'name': 'feats', 'type': 'FLOAT32', 'shape': [1, 4]},
        {'name': 'pooled_cls', 'type': 'FLOAT32', 'shape': [1, 1024]},
      ],
      'outputs': [
        {'name': 'act_logits', 'type': 'FLOAT32', 'shape': [1, 2]},
      ],
      'bindable': true,
    }
  ],
  'default': 'serving_default',
};

/// `GET /v1/litert/status` com a cabeca carregada, copiado do A72
/// (`compile_ms: 7`, `requested: ["CPU"]`, `available: ["GPU","CPU"]`).
const layaStatus = {
  'loaded': {
    'path': '/data/user/0/com.dollarbr.mobilelm/app_flutter/models/'
        'laya_en_act_head_fp32.tflite',
    'signature': 'serving_default',
    'inputs': [
      {'name': 'feats', 'type': 'FLOAT32', 'shape': [1, 4]},
      {'name': 'pooled_cls', 'type': 'FLOAT32', 'shape': [1, 1024]},
    ],
    'outputs': [
      {'name': 'act_logits', 'type': 'FLOAT32', 'shape': [1, 2]},
    ],
    'is_classifier': true,
    'head': {
      'features': {'name': 'pooled_cls', 'type': 'FLOAT32', 'shape': [1, 1024]},
      'logits': {'name': 'act_logits', 'type': 'FLOAT32', 'shape': [1, 2]},
      'auxiliary': [
        {'name': 'feats', 'type': 'FLOAT32', 'shape': [1, 4]},
      ],
    },
    'compile_ms': 7,
    'requested': ['CPU'],
    'available': ['GPU', 'CPU'],
    'executed_accelerator': null,
    'executed_accelerator_note': "LiteRT 2.2.0's CompiledModel does not expose "
        'the accelerator it used.',
  }
};


// ── DeviceState: os tres endpoints, copiados do A72 ───────────────────────
//
// As formas aqui sao o que os tres endpoints **realmente** devolvem. A primeira
// versao da janela leu `loaded['classifier']` de `/v1/models/local` — e esse
// pacote **nao tem essa chave**, entao toda GGUF carregada saia como decision
// model, inclusive uma que tem cabeco de classificacao de verdade. Um campo que
// nao existe se le exatamente como um campo que e falso, e por isso passou.

/// `GET /v1/models/local` com o Tev1 carregado — as chaves sao exatamente estas.
const localWithGguf = {
  'object': 'list',
  'loaded': {
    'filename': 'tev1-Q8_0.gguf',
    'runtime': 'llama',
    'backend': 'cpu',
    'gpu': 'Adreno (TM) 618',
    'gpu_layers': 0,
    'accelerated': false,
    'vision': false,
  },
  'loading': null,
  'transfers_in_progress': 0,
  'data': <dynamic>[],
};

/// `GET /v1/models/local` com so a cabeca .tflite carregada. `loaded` e null
/// porque o `loaded` deste endpoint e so GGUF.
const localWithOnlyTflite = {
  'object': 'list',
  'loaded': null,
  'loading': null,
  'transfers_in_progress': 0,
  'data': <dynamic>[],
};

/// `GET /v1/server/capabilities` — e AQUI que mora o `classify`.
const capsClassifies = {
  'server': 'mobileLM Local OpenAI API',
  'running': true,
  'model': 'gte-reranker-modernbert-base-Q8_0.gguf',
  'capabilities': {'text': false, 'embeddings': false, 'rerank': true, 'classify': true},
};
const capsDoesNotClassify = {
  'server': 'mobileLM Local OpenAI API',
  'running': true,
  'model': 'tev1-Q8_0.gguf',
  'capabilities': {'text': true, 'streaming': true, 'gguf': true, 'classify': false},
};

/// `GET /v1/litert/status` com o act head carregado (compile_ms 7).
const statusWithHead = {
  'loaded': {
    'path': '/data/user/0/com.dollarbr.mobilelm/app_flutter/models/'
        'laya_en_act_head_fp32.tflite',
    'signature': 'serving_default',
    'head': {
      'features': {'name': 'pooled_cls', 'shape': [1, 1024]},
      'logits': {'name': 'act_logits', 'shape': [1, 2]},
      'auxiliary': [
        {'name': 'feats', 'shape': [1, 4]}
      ],
    },
    'compile_ms': 7,
  }
};
const statusEmpty = {'loaded': null};

void main() {
  mainFeatureSource();
  // The 422 as `_handleClassifyGenerative` builds it: a model that ignored the
  // instruction and wrote prose. Declared here rather than inside a group
  // because two of the groups assert on it — a payload scoped to one closure
  // is one rename away from being read by a test that cannot see it.
  const refused = {
    'error': 'The model did not answer with one of the offered options.',
    'model': 'tev1-Q8_0.gguf',
    'raw': 'I am not able to classify this without more context.',
    'expected_one_of': ['A', 'B', 'C'],
  };

  group('systemOneShapeOf', () {
    test('a .tflite is a head, from the extension and nothing else', () {
      // No load, no screen, no `cls.*` tensor to inspect: the extension is the
      // only fact there is, and it is a fact.
      expect(
        systemOneShapeOf(filename: 'laya_en_act_head_fp32.tflite'),
        SystemOneShape.tfliteHead,
      );
      expect(
        systemOneShapeOf(filename: 'Laya-ACT-HEAD.TFLITE'),
        SystemOneShape.tfliteHead,
        reason: 'extensions are case-insensitive in practice and a head named '
            'in caps should not become a different runtime',
      );
    });

    test('a GGUF is unknown until it is loaded, and that is not decision', () {
      expect(systemOneShapeOf(filename: 'tev1-Q8_0.gguf'), SystemOneShape.unknown);
      expect(
        isClassAnswering(SystemOneShape.unknown),
        isFalse,
        reason: 'guessing "probably a decision model" is how the wrong body '
            'gets sent and the refusal reads like a broken model',
      );
    });

    test('a loaded GGUF is told apart by the head, not by its name', () {
      expect(
        systemOneShapeOf(
            filename: 'tev1-Q8_0.gguf', hasClassificationHead: false),
        SystemOneShape.decision,
      );
      expect(
        systemOneShapeOf(
            filename: 'gte-reranker-modernbert-base-Q8_0.gguf',
            hasClassificationHead: true),
        SystemOneShape.ggufHead,
      );
    });

    test('the four names that gave the class its name are not special', () {
      // This is the test that keeps the class open. Jev, Laya, Tev1 and Nimble
      // are what it was named after; the next published model is in the class
      // without anybody editing this file, and a name-based check would have to
      // be edited for it.
      const named = [
        'Jev-8B-Instruct-Q4_K_M.gguf',
        'Laya-English-LiteRT.gguf',
        'tev1-Q8_0.gguf',
        'Bespoke-Nimble-9B.gguf',
        'something-nobody-has-heard-of-yet.gguf',
      ];
      for (final filename in named) {
        expect(
          systemOneShapeOf(filename: filename),
          SystemOneShape.unknown,
          reason: '$filename must not be classified by its name',
        );
        expect(
          systemOneShapeOf(filename: filename, hasClassificationHead: false),
          SystemOneShape.decision,
          reason: '$filename with no head is a decision model whatever it is '
              'called',
        );
      }
    });

    test('a known fact beats a guess at the extension', () {
      // A catalogue entry says what it is; the screen has to be able to trust it
      // rather than re-deriving it and disagreeing silently.
      expect(
        systemOneShapeOf(filename: 'head.gguf', isTflite: false,
            hasClassificationHead: true),
        SystemOneShape.ggufHead,
      );
    });
  });

  group('SystemOneOptions', () {
    test('the starter list is valid, and it is the measured one', () {
      expect(SystemOneOptions.starter.isValid, isTrue);
      expect(SystemOneOptions.starter.toChoices(),
          {'A': 'bug', 'B': 'billing', 'C': 'account'});
    });

    test('one option is not a decision', () {
      const one = SystemOneOptions([SystemOneOption('A', 'bug')]);
      expect(one.isValid, isFalse);
      expect(one.problem, contains('At least two'));
    });

    test('the 24 cap is the card\'s, and it is enforced here too', () {
      final many = SystemOneOptions([
        for (final l in SystemOneOptions.letters)
          SystemOneOption(l, 'label $l'),
      ]);
      expect(many.items.length, 24);
      expect(many.isValid, isTrue, reason: '24 is allowed, not 23');
      expect(many.add().items.length, 24, reason: 'add stops at the cap');
    });

    test('an option with no label is a problem, not a silent drop', () {
      const withBlank = SystemOneOptions([
        SystemOneOption('A', 'bug'),
        SystemOneOption('B', '   '),
      ]);
      expect(withBlank.isValid, isFalse);
      expect(withBlank.problem, contains('B'));
    });

    test('one letter cannot mean two things', () {
      const clash = SystemOneOptions([
        SystemOneOption('A', 'bug'),
        SystemOneOption('a', 'billing'),
      ]);
      expect(clash.isValid, isFalse);
      expect(clash.problem, contains('twice'));
    });

    test('the same letter with the same label twice is not a clash', () {
      // Parsing `A bug` on two lines is a typo, not a decision, and refusing it
      // would be pedantry; what matters is that A does not carry two meanings.
      const same = SystemOneOptions([
        SystemOneOption('A', 'bug'),
        SystemOneOption('A', 'bug'),
      ]);
      expect(same.isValid, isTrue);
    });

    test('toChoices upper-cases the keys', () {
      const lower = SystemOneOptions([
        SystemOneOption('a', 'bug'),
        SystemOneOption('b', 'billing'),
      ]);
      expect(lower.toChoices().keys, ['A', 'B']);
    });

    test('add takes the next unused letter, skipping a pinned one', () {
      const pinned = SystemOneOptions([
        SystemOneOption('A', 'bug'),
        SystemOneOption('C', 'account'),
      ]);
      expect(pinned.add().items.last.letter, 'B');
    });

    test('removeAt out of range changes nothing', () {
      const two = SystemOneOptions([
        SystemOneOption('A', 'bug'),
        SystemOneOption('B', 'billing'),
      ]);
      expect(two.removeAt(5).items.length, 2);
      expect(two.removeAt(-1).items.length, 2);
      expect(two.removeAt(1).items.single.letter, 'A');
    });

    group('parse', () {
      test('a pinned letter is kept', () {
        final o = SystemOneOptions.parse('A bug\nB billing');
        expect(o.items.map((e) => e.letter), ['A', 'B']);
        expect(o.toChoices(), {'A': 'bug', 'B': 'billing'});
      });

      test('a bare label gets the next letter', () {
        final o = SystemOneOptions.parse('bug\nbilling\naccount');
        expect(o.toChoices(), {'A': 'bug', 'B': 'billing', 'C': 'account'});
      });

      test('a label that starts with a capital is not read as a letter', () {
        // "A conta venceu" is a label, not option A followed by "conta venceu".
        // A model card's option list is full of labels that begin this way.
        final o = SystemOneOptions.parse('A conta venceu\nAssunto resolvido');
        expect(o.items.map((e) => e.letter), ['A', 'B']);
        expect(o.items.first.label, 'conta venceu',
            reason: 'the space after the letter is the separator, so a label '
                'starting with a word loses that word otherwise');
      });

      test('a letter out of range is treated as text', () {
        final o = SystemOneOptions.parse('Zebra pattern\nbug');
        expect(o.items.first.letter, 'A');
        expect(o.items.first.label, 'Zebra pattern');
      });

      test('a repeated letter does not win twice', () {
        final o = SystemOneOptions.parse('A bug\nA billing\nC account');
        expect(o.items.map((e) => e.letter), ['A', 'B', 'C']);
        expect(o.toChoices(), {'A': 'bug', 'B': 'billing', 'C': 'account'});
      });

      test('blank lines are skipped, not turned into blank options', () {
        final o = SystemOneOptions.parse('A bug\n\n\nB billing\n');
        expect(o.items.length, 2);
      });

      test('a line with only a letter keeps an empty label so the row shows', () {
        // Dropping it would leave the user with no row to fix.
        final o = SystemOneOptions.parse('A bug\nB');
        expect(o.items.length, 2);
        expect(o.items.last.letter, 'B');
        expect(o.items.last.label, isEmpty);
        expect(o.isValid, isFalse);
      });

      test('round-trips with toText', () {
        const original = SystemOneOptions([
          SystemOneOption('A', 'bug'),
          SystemOneOption('B', 'fatura em duplicidade'),
        ]);
        expect(SystemOneOptions.parse(original.toText()).toChoices(),
            original.toChoices());
      });
    });
  });

  group('SystemOneLabels', () {
    test('the two the act head has, and that is what they are called', () {
      expect(SystemOneLabels.starter.items, ['not a persona', 'is a persona']);
      expect(SystemOneLabels.starter.isValid, isTrue);
    });

    test('the 24 cap does not apply here, and applying it would be invented', () {
      // The 2-24 is the Tev1 card's number for a decision model. A head has as
      // many classes as it was trained with, and refusing 25 labels would be the
      // app making up a rule.
      final many = SystemOneLabels([for (var i = 0; i < 400; i++) 'class $i']);
      expect(many.isValid, isTrue);
      expect(many.length, 400);
    });

    test('one label is enough, unlike a decision', () {
      expect(const SystemOneLabels(['yes']).isValid, isTrue);
      expect(const SystemOneLabels(['yes', 'no']).isValid, isTrue);
    });

    test('no labels at all is not a classification', () {
      expect(SystemOneLabels.empty.isValid, isFalse);
      expect(SystemOneLabels.empty.problem, contains('At least one'));
    });

    test('an empty row names its position, not nothing', () {
      const l = SystemOneLabels(['not a persona', '  ']);
      expect(l.isValid, isFalse);
      expect(l.problem, contains('Label 2'));
    });

    test('toJson trims', () {
      expect(const SystemOneLabels([' a ', 'b ']).toJson(), ['a', 'b']);
    });

    test('edits out of range change nothing', () {
      const l = SystemOneLabels(['a', 'b']);
      expect(l.replace(9, 'z').items, ['a', 'b']);
      expect(l.removeAt(-1).items, ['a', 'b']);
      expect(l.replace(0, 'z').items, ['z', 'b']);
      expect(l.removeAt(1).items, ['a']);
    });

    test('addBlank always leaves somewhere to type', () {
      expect(SystemOneLabels.empty.addBlank().items, ['']);
      expect(SystemOneLabels.starter.addBlank().length, 3);
    });
  });

  group('DeviceState and the shape it resolves to', () {
    test('a GGUF that classifies is a head with its own labels', () {
      final d = DeviceState.fromResponses(
        local: localWithGguf,
        capabilities: capsClassifies,
        litertStatus: statusWithHead,
      );
      expect(d.ggufName, 'tev1-Q8_0.gguf');
      expect(d.ggufClassifies, isTrue);
      expect(resolveSystemOneShape(d), SystemOneShape.ggufHead);
    });

    test('a GGUF that does not classify is a decision model', () {
      final d = DeviceState.fromResponses(
        local: localWithGguf,
        capabilities: capsDoesNotClassify,
        litertStatus: statusEmpty,
      );
      expect(resolveSystemOneShape(d), SystemOneShape.decision);
    });

    test('o `classifier` nao existe em /v1/models/local, e o teste diz isso', () {
      // A forma real do pacote, conferida. Se alguem voltar a ler
      // `loaded['classifier']`, este teste e o que pega — porque a ausencia da
      // chave e o fato, nao um detalhe do mock.
      expect(localWithGguf['loaded'], isNot(contains('classifier')));
      expect(
        DeviceState.fromResponses(local: localWithGguf).ggufClassifies,
        isFalse,
        reason: 'sem capabilities nao se sabe, e "nao se sabe" nao e "nao '
            'classifica" — quem sabe e o capabilities',
      );
    });

    test('so um .tflite carregado: a janela NAO diz "nothing loaded"', () {
      // O bug que o aparelho mostrou. `/v1/models/local` responde `loaded: null`
      // porque o seu `loaded` e so GGUF, e a janela aberta pela tela do servidor
      // dizia "nothing loaded" com a cabeca da Laya carregada e o contrato dela
      // inteiro na tela seguinte.
      final d = DeviceState.fromResponses(
        local: localWithOnlyTflite,
        capabilities: const {'capabilities': <String, dynamic>{}},
        litertStatus: statusWithHead,
      );
      expect(d.hasGguf, isFalse);
      expect(d.hasTflite, isTrue);
      expect(d.tfliteName, 'laya_en_act_head_fp32.tflite');
      expect(resolveSystemOneShape(d), SystemOneShape.tfliteHead);
    });

    test('e a janela assume esse nome, para funcionar de verdade', () {
      final d = DeviceState.fromResponses(
        local: localWithOnlyTflite,
        litertStatus: statusWithHead,
      );
      // Sem o nome o caminho da cabeca nem pode ser montado: uma cabeca nao tem
      // `cls.output.weight` para ser reconhecida, entao quem diz qual e so quem
      // esta chamando.
      expect(resolveSystemOneHeadFilename(d), 'laya_en_act_head_fp32.tflite');
    });

    test('nada carregado e null, nao uma forma adivinhada', () {
      final d = DeviceState.fromResponses(
        local: const {'loaded': null},
        litertStatus: statusEmpty,
      );
      expect(d.isEmpty, isTrue);
      expect(resolveSystemOneShape(d), isNull);
      expect(resolveSystemOneHeadFilename(d), isNull);
    });

    test('um probe que falhou nao apaga o que os outros dois disseram', () {
      // As tres sondas sao independentes. Se a do LiteRT cai, as outras duas
      // continuam valendo — um probe mudo e o que faz um painel em branco
      // parecer "o aparelho ainda nao respondeu".
      final d = DeviceState.fromResponses(
        local: localWithGguf,
        capabilities: capsDoesNotClassify,
        litertStatus: null,
      );
      expect(d.ggufName, 'tev1-Q8_0.gguf');
      expect(resolveSystemOneShape(d), SystemOneShape.decision);
    });

    test('com os dois runtimes carregados, quem decide e a GGUF', () {
      // `/v1/classify` roteia para a GGUF quando ha uma carregada, entao a GGUF
      // e o que a janela tem que dirigir.
      final d = DeviceState.fromResponses(
        local: localWithGguf,
        capabilities: capsDoesNotClassify,
        litertStatus: statusWithHead,
      );
      expect(resolveSystemOneShape(d), SystemOneShape.decision);
      expect(d.hasTflite, isTrue, reason: 'a cabeca continua carregada; e a '
          'janela que escolhe, e escolhe pelo que o endpoint vai usar');
    });

    test('a forma que o cartao nomeou ganha da sondagem', () {
      final d = DeviceState.fromResponses(
        local: localWithGguf,
        capabilities: capsDoesNotClassify,
        litertStatus: statusEmpty,
      );
      expect(
        resolveSystemOneShape(d, given: SystemOneShape.tfliteHead),
        SystemOneShape.tfliteHead,
        reason: 'o cartao que o usuario tocou e uma fonte melhor que um poll',
      );
    });

    test('o nome do cartao ganha do que esta carregado', () {
      final d = DeviceState.fromResponses(litertStatus: statusWithHead);
      expect(
        resolveSystemOneHeadFilename(d, fromCard: 'other-head.tflite'),
        'other-head.tflite',
      );
    });
  });

  group('HeadContract', () {
    test('the screen payload from the A72 yields 1024, not 4', () {
      // **The bug this type exists for.** `feats [1,4]` is stored BEFORE
      // `pooled_cls [1,1024]`, so "the first input" would have told the user a
      // head wants four numbers.
      final c = HeadContract.fromScreen(layaScreen)!;
      expect(c.featureName, 'pooled_cls');
      expect(c.featureCount, 1024);
      expect(c.classCount, 2);
      expect(c.signature, 'serving_default');
      expect(c.auxiliary.map((a) => a.name), ['feats']);
      expect(c.auxiliary.single.count, 4);
    });

    test('the status payload gives the same answer by another route', () {
      final c = HeadContract.fromStatus(layaStatus)!;
      expect(c.featureName, 'pooled_cls');
      expect(c.featureCount, 1024);
      expect(c.classCount, 2);
      expect(c.auxiliary.single.name, 'feats');
      expect(c.auxiliary.single.count, 4);
    });

    test('a single-signature object is accepted too, so the shape is not a '
        'trap for the next reader', () {
      final c = HeadContract.fromScreen({
        'signature': {
          'signature': 'serving_default',
          'inputs': [
            {'name': 'pooled_cls', 'type': 'FLOAT32', 'shape': [1, 8]},
          ],
          'outputs': [
            {'name': 'out', 'type': 'FLOAT32', 'shape': [1, 3]},
          ],
        }
      })!;
      expect(c.featureCount, 8);
      expect(c.classCount, 3);
      expect(c.auxiliary, isEmpty);
    });

    test('nothing loaded is null, and that is a state not a failure', () {
      expect(HeadContract.fromStatus(const {}), isNull);
      expect(HeadContract.fromStatus(const {'loaded': null}), isNull);
      expect(HeadContract.fromStatus(const {'loaded': <String, dynamic>{}}), isNull,
          reason: 'a loaded entry with no head is not a head contract');
    });

    test('a signature with no inputs is null rather than a head wanting zero',
        () {
      expect(HeadContract.fromScreen(const {'signatures': []}), isNull);
      expect(
        HeadContract.fromScreen(const {
          'signatures': [
            {'signature': 's', 'inputs': <dynamic>[]}
          ]
        }),
        isNull,
      );
    });

    test('an unreadable shape is null, not a contract with a null count', () {
      // A null *count* reads as "some number, unknown how many", and the window
      // would then let the user paste anything and learn the answer from a 400.
      // Null says what is true: this is not a head the window can build a
      // request for, and it can say so in the message instead of in a status
      // code the user has to decode.
      expect(
        HeadContract.fromScreen({
          'signatures': [
            {
              'signature': 's',
              'inputs': [
                {'name': 'x', 'type': 'FLOAT32', 'shape': ['a', 'b']},
              ],
              'outputs': <dynamic>[],
            }
          ]
        }),
        isNull,
      );
    });

    test('the product of the shape, not the last dimension', () {
      // On a batch of 1 the two agree, and a batch of 1 is the only batch
      // anybody sends — which is exactly why reading only the last dimension
      // would look right forever.
      final c = HeadContract.fromScreen({
        'signatures': [
          {
            'signature': 's',
            'inputs': [
              {'name': 'x', 'type': 'FLOAT32', 'shape': [4, 8]},
            ],
            'outputs': [
              {'name': 'y', 'type': 'FLOAT32', 'shape': [4, 3]},
            ],
          }
        ]
      })!;
      expect(c.featureCount, 32);
      expect(c.classCount, 12);
    });

    test('a head with one input has no auxiliaries to fill', () {
      // The one-input case is what the handoff calls the trivial
      // `Linear(1024, 2)`, and a window that showed an empty auxiliary editor
      // for it would be inventing work.
      final c = HeadContract.fromScreen({
        'signatures': [
          {
            'signature': 's',
            'inputs': [
              {'name': 'x', 'type': 'FLOAT32', 'shape': [1, 1024]},
            ],
            'outputs': [
              {'name': 'y', 'type': 'FLOAT32', 'shape': [1, 2]},
            ],
          }
        ]
      })!;
      expect(c.auxiliary, isEmpty);
      expect(c.featureCount, 1024);
    });
  });

  group('FeatureVector', () {
    test('separators: spaces, commas, newlines and brackets', () {
      final v = FeatureVector.parse('[1.0, 2.5 3\n-4]')!;
      expect(v.values, [1.0, 2.5, 3.0, -4.0]);
    });

    test('a token that is not a number returns null, never a shorter vector', () {
      // The alternative — dropping the bad element — produces a vector of the
      // wrong length that still looks plausible, and the count check is exactly
      // the thing that would have caught it.
      expect(FeatureVector.parse('1.0 2.0 banana 3.0'), isNull);
      expect(FeatureVector.parse('1,2,x'), isNull);
    });

    test('empty input is null', () {
      expect(FeatureVector.parse('   '), isNull);
      expect(FeatureVector.parse('[]'), isNull);
    });

    test('the count check is the head\'s, and it knows 1024 from 4', () {
      final short = FeatureVector([1, 2, 3], expectedCount: 1024);
      expect(short.isValid, isFalse);
      expect(short.problem, contains('1024'));
      expect(short.problem, contains('3'));

      final right = FeatureVector(List.filled(1024, 0.1), expectedCount: 1024);
      expect(right.isValid, isTrue);
    });

    test('an unknown wanted count is not the same as any length being fine', () {
      // unscreened head: the window must not claim the vector is right.
      final v = FeatureVector([1, 2, 3]);
      expect(v.isValid, isTrue, reason: 'nothing to contradict');
      expect(v.expectedCount, isNull);
    });

    test('the source is carried, because the window cannot verify it', () {
      final v = FeatureVector([1, 2], source: 'gte-base (embed)');
      expect(v.source, 'gte-base (embed)');
    });
  });

  group('SystemOneResult — the decision shape', () {
    // The 200 as `_handleClassifyGenerative` builds it.
    final ok = {
      'object': 'classification',
      'model': 'tev1-Q8_0.gguf',
      'label': 'bug',
      'choice': 'B',
      'relevance_score': null,
      'scores': {'bug': null, 'billing': null, 'account': null},
      'why_no_scores':
          'A decision model returns one letter, not a logit per class.',
    };

    test('the letter and the label come through, and the null stays null', () {
      final r = SystemOneResult().fromClassify(ok);
      expect(r.letter, 'B');
      expect(r.label, 'bug');
      expect(r.logits, isNull, reason: 'there is no logit vector to show');
      expect(r.topIndex, isNull);
      expect(r.isFailure, isFalse);
      expect(r.whyNoScore, contains('one letter'));
    });

    test('the endpoint\'s own reason is kept verbatim', () {
      // A window that dropped this leaves the user looking at a letter with
      // nowhere to put it, and the obvious next question is "how sure?" — which
      // is the one thing this answer cannot answer.
      final r = SystemOneResult().fromClassify(ok);
      expect(r.whyNoScore, ok['why_no_scores']);
    });

    test('a refusal is a result, and it carries the evidence', () {
      final r = SystemOneResult().fromClassify(refused, status: 422);
      expect(r.isFailure, isTrue);
      expect(r.failure, contains('did not answer'));
      expect(r.failure, contains('said: I am not able to classify'),
          reason: 'the raw text is the only way to see what happened');
      expect(r.failure, contains('expected one of A, B, C'));
    });

    test('a refusal never renders as an answer', () {
      // The bug this guards: a 422 handled as "no result" while a stale previous
      // result is still on screen reads as the previous answer.
      final r = SystemOneResult().fromClassify(refused, status: 422);
      expect(r.letter, isNull);
      expect(r.label, isNull);
      expect(r.logits, isNull);
      expect(r.topIndex, isNull);
    });

    test('a non-200 with no error field still says what happened', () {
      final r = SystemOneResult().fromClassify({}, status: 429);
      expect(r.isFailure, isTrue);
      expect(r.failure, 'HTTP 429');
    });
  });

  group('SystemOneResult — the .tflite shape', () {
    // The 200 as `_handleClassifyTflite` builds it, with the Laya act head's
    // real two logits and the real A72 values.
    final laya = {
      'object': 'classification',
      'model': 'laya_en_act_head_fp32.tflite',
      'runtime': 'litert',
      'signature': 'serving_default',
      'features_input': 'pooled_cls',
      'auxiliary_used': ['feats'],
      // Copiado do servidor real depois de `POST /v1/litert/unload` existir.
      // Antes desta linha o payload era o que o A72 mandava, e ele nao mandava
      // este campo — ver o teste "a resposta que o aparelho manda" abaixo.
      'feature_source': describeVectorSource(
        length: 1024,
        tensor: 'pooled_cls',
        auxiliary: {'feats': 4},
      ),
      'n_classes': 2,
      'top_index': 0,
      'logits': [0.25634345, -0.20818722],
      'label': null,
      'relevance_score': null,
      'why_no_score': 'A .tflite head produces logits. Turning them into a '
          'confidence takes a softmax and a temperature.',
      'executed_accelerator': null,
      'executed_accelerator_note': 'CompiledModel has no getter for it.',
    };

    test('logits and top_index come through, and there is no letter', () {
      final r = SystemOneResult(shape: SystemOneShape.tfliteHead)
          .fromClassify(laya);
      expect(r.logits, [0.25634345, -0.20818722]);
      expect(r.topIndex, 0);
      expect(r.letter, isNull,
          reason: 'a logit vector has no letter in it; printing "A" would be a '
              'decision the app made');
      expect(r.auxiliaryUsed, ['feats']);
      expect(r.featuresInput, 'pooled_cls');
      expect(r.notes, contains('runtime: litert'));
      expect(r.notes, contains('n_classes: 2'));
    });

    test('the caller\'s labels are used, because the response has none', () {
      // The endpoint sends `label: null` and no label set, so a window that read
      // labels from the body would print "class 0" for a run the user labelled
      // in the field above it.
      final bare = SystemOneResult(shape: SystemOneShape.tfliteHead)
          .fromClassify(laya);
      expect(bare.hasCallerLabels, isFalse);
      expect(bare.labelledTop, isNull);
      expect(bare.labelAt(0), 'class 0');

      final named = SystemOneResult(shape: SystemOneShape.tfliteHead)
          .fromClassify(laya, callerLabels: ['not a persona', 'is a persona']);
      expect(named.hasCallerLabels, isTrue);
      expect(named.labelledTop, 'not a persona');
      expect(named.labelAt(1), 'is a persona');
    });

    test('a response that does carry labels is used when the caller has none', () {
      final withLabels = {...laya, 'labels': ['neg', 'pos']};
      final r = SystemOneResult(shape: SystemOneShape.tfliteHead)
          .fromClassify(withLabels);
      expect(r.logitLabels, ['neg', 'pos']);
      expect(r.labelledTop, 'neg');
    });

    test('more classes than labels falls back to the index, not to a guess', () {
      final r = SystemOneResult(shape: SystemOneShape.tfliteHead)
          .fromClassify(laya, callerLabels: ['only one']);
      expect(r.logits!.length, 2);
      expect(r.labelAt(1), 'class 1',
          reason: 'the head has a class the caller never named, and inventing a '
              'name for it is the guess this whole file exists to avoid');
    });

    test('the endpoint\'s no-score reason survives on this path too', () {
      final r = SystemOneResult(shape: SystemOneShape.tfliteHead)
          .fromClassify(laya);
      expect(r.whyNoScore, contains('softmax'));
    });

    test('a 400 from a head names the tensors it wants', () {
      final r = SystemOneResult(shape: SystemOneShape.tfliteHead).fromClassify({
        'error': "Missing 'features': an array of 1024 floats.",
        'wants': {'name': 'pooled_cls', 'shape': [1, 1024]},
        'auxiliary_wanted': [
          {'name': 'feats', 'shape': [1, 4]}
        ],
      }, status: 400);
      expect(r.isFailure, isTrue);
      expect(r.failure, contains('1024'));
      expect(r.logits, isNull);
    });

    test('the refusal text is not smuggled into the notes', () {
      // `_notes` draws from a fixed list; iterating the map instead would put
      // `error` and `raw` in a "details" list under a successful-looking run.
      final r = SystemOneResult().fromClassify(refused, status: 422);
      expect(r.notes.any((n) => n.contains('said:')), isFalse);
      expect(r.notes.any((n) => n.startsWith('error')), isFalse);
    });
  });

  group('request bodies', () {
    test('the decision body names the state and the choices', () {
      const options = SystemOneOptions([
        SystemOneOption('A', 'bug'),
        SystemOneOption('B', 'billing'),
      ]);
      final body = SystemOneResult().decisionBody(
        state: 'checkout devolvendo 500 desde 9h',
        question: 'Qual area?',
        options: options,
      );
      expect(body['state'], 'checkout devolvendo 500 desde 9h');
      expect(body['question'], 'Qual area?');
      expect(body['choices'], {'A': 'bug', 'B': 'billing'});
      expect(body.containsKey('instruction'), isFalse);
    });

    test('an empty question is left out rather than sent as ""', () {
      const options = SystemOneOptions([
        SystemOneOption('A', 'bug'),
        SystemOneOption('B', 'billing'),
      ]);
      final body = SystemOneResult()
          .decisionBody(state: 'x', question: '   ', options: options);
      expect(body.containsKey('question'), isFalse);
    });

    test('the tflite body always names the file, because nothing else can', () {
      final body = SystemOneResult().tfliteBody(
        filename: 'laya_en_act_head_fp32.tflite',
        features: FeatureVector([1, 2, 3]),
      );
      expect(body['filename'], 'laya_en_act_head_fp32.tflite');
      expect(body['features'], [1.0, 2.0, 3.0]);
      expect(body.containsKey('auxiliary_inputs'), isFalse);
      expect(body.containsKey('features_input'), isFalse);
    });

    test('auxiliary inputs and an explicit feature tensor are carried', () {
      final body = SystemOneResult().tfliteBody(
        filename: 'head.tflite',
        features: FeatureVector([1, 2], source: 'gte'),
        auxiliary: {'feats': const FeatureVector([0.1, 0.9, 0.2, 0.3])},
        featuresInput: 'pooled_cls',
      );
      expect(body['auxiliary_inputs'], {
        'feats': [0.1, 0.9, 0.2, 0.3]
      });
      expect(body['features_input'], 'pooled_cls');
    });
  });

  group('encodeBody', () {
    test('a normal body round-trips', () {
      expect(encodeBody({'a': 1, 'b': [1.5]}), '{"a":1,"b":[1.5]}');
    });

    test('a diverged logit vector does not become an exception', () {
      // jsonEncode throws on a non-finite double, and a head that produced NaN
      // is a real and diagnosable state — the window would show an exception
      // where the honest answer names the number JavaScript does not have.
      final json = encodeBody({
        'logits': [double.nan, double.infinity, double.negativeInfinity, 0.5]
      });
      expect(json, contains('NaN'));
      expect(json, contains('Infinity'));
      expect(json, contains('-Infinity'));
      expect(json, contains('0.5'));
    });

    test('sanitising reaches inside a nested vector', () {
      final json = encodeBody({
        'features': [1.0, double.nan],
        'auxiliary_inputs': {
          'feats': [double.infinity, 0.0]
        },
      });
      expect(json, contains('"NaN"'));
      expect(json, contains('"Infinity"'));
    });
  });

  group('formatLogits', () {
    test('biggest first, even with no top to mark', () {
      // No `top_index` means nothing is marked, and the order is still the one
      // that puts the answer first — a table in index order makes the caller
      // hunt for the class the response named.
      final text = formatLogits([0.25634345, -0.20818722], SystemOneResult.empty);
      final lines = text.split('\n');
      expect(lines.first, startsWith('0'));
      expect(lines.first, isNot(contains('*')));
      expect(lines.first, contains('0.2563'));
      expect(lines.last, contains('-0.2082'));
    });

    test('the real Laya numbers, read as the screen will', () {
      final r = SystemOneResult(shape: SystemOneShape.tfliteHead).fromClassify({
        'model': 'laya_en_act_head_fp32.tflite',
        'logits': [0.25634345, -0.20818722],
        'top_index': 0,
        'label': null,
      }, callerLabels: ['not a persona', 'is a persona']);
      final text = formatLogits(r.logits!, r);
      expect(text, contains('not a persona'));
      expect(text, contains('is a persona'));
      expect(text, startsWith('0 *'));
    });

    test('without caller labels the index is the honest name', () {
      final text = formatLogits([0.1, 0.2], SystemOneResult.empty);
      expect(text, contains('class 0'));
      expect(text, contains('class 1'));
    });
  });
}

/// `feature_source`: what the model was actually given.
///
/// The field was on `SystemOneResult` from the day the window was written,
/// parsed from `json['feature_source']`, displayed nowhere — and **no endpoint
/// sent it**. So it could never be non-null, and the sentence it stood in for is
/// the one a person needs when a 0.8B classifier answers "bug" for a ticket
/// whose feature vector was 1024 numbers they pasted.
void mainFeatureSource() {
  test('a resposta que o aparelho manda traz feature_source', () {
    // **This is the test for the bug, not for the wording.** The defect was that
    // `SystemOneResult.featureSource` was parsed from a field **no endpoint ever
    // sent**, so it could never be non-null and the line on the result card was
    // unreachable. Asserting the *text* of `describeVectorSource` does not catch
    // that — the function was correct the whole time, it was simply never
    // called. So this asserts the field is in the response at all.
    //
    // The two payloads above are copies of what the A72 returned, which is why
    // the one for a head had to gain this key: a test that feeds the parser a
    // shape the server does not produce is a test that passes against a fiction,
    // and that is the exact mistake `HeadContract` exists in this file to
    // document.
    final cabeca = SystemOneResult().fromClassify({
      'object': 'classification',
      'model': 'laya_en_act_head_fp32.tflite',
      'features_input': 'pooled_cls',
      'feature_source': describeVectorSource(
        length: 1024,
        tensor: 'pooled_cls',
      ),
    });
    expect(cabeca.featureSource, isNotNull,
        reason: 'a head run must be able to say the numbers were the callers');
    expect(cabeca.featureSource, contains('1024'));

    final decisao = SystemOneResult().fromClassify({
      'object': 'classification',
      'model': 'tev1-Q8_0.gguf',
      'choice': 'B',
      'label': 'bug',
      'feature_source': describeTextSource(options: 2),
    });
    expect(decisao.featureSource, isNotNull,
        reason: 'and a decision run must be able to say it read text, so the '
            'absence of numbers is stated rather than left to be assumed');
    expect(decisao.featureSource!.toLowerCase(), contains('no vector'));
  });

  group('a head classifies a vector the caller supplied', () {
    test('the length and the tensor are named', () {
      final s = describeVectorSource(length: 1024, tensor: 'pooled_cls');
      expect(s, contains('1024'));
      expect(s, contains('pooled_cls'));
      expect(s, contains('caller'),
          reason: 'the word that carries the warning: the numbers came from '
              'the caller, and a head does not embed anything');
    });

    test('and it says outright that the head does not embed', () {
      final s = describeVectorSource(length: 1024, tensor: 'pooled_cls');
      expect(s.toLowerCase(), contains('does not embed'),
          reason: 'a head that embeds is a different kind of model, and reading '
              'this sentence is the only way to know which one is loaded');
    });

    test('auxiliary tensors are named with their counts', () {
      // The act head is the case that matters: `feats [1,4]` is declared BEFORE
      // `pooled_cls [1,1024]`, so a run can legitimately consume two tensors and
      // a source line that named only the big one would be hiding half the
      // request.
      final s = describeVectorSource(
        length: 1024,
        tensor: 'pooled_cls',
        auxiliary: {'feats': 4},
      );
      expect(s, contains('feats'));
      expect(s, contains('[4]'));
    });

    test('no auxiliary means no trailing clause', () {
      final s = describeVectorSource(length: 8, tensor: 'in');
      expect(s, isNot(contains('plus')));
      expect(s, isNot(contains(', ,')));
    });
  });

  group('a decision model read text, and there is no vector to name', () {
    test('it does not claim numbers were involved', () {
      final s = describeTextSource(options: 3);
      expect(s.toLowerCase(), contains('no vector'));
      expect(s.toLowerCase(), contains('text'));
      expect(s, isNot(contains('floats')),
          reason: 'naming a feature tensor here would be inventing one — the '
              'whole reason these are two functions and not one with nullable '
              'arguments');
    });

    test('the option count is singular or plural, and it is the count', () {
      expect(describeTextSource(options: 1), contains('1 option.'),
          reason: '"1 options" is the same grammar bug as "1 hops", which this '
              'repo shipped and then had to fix in two places');
      expect(describeTextSource(options: 2), contains('2 options'));
      expect(describeTextSource(options: 24), contains('24 options'));
    });
  });
}

/// The two things this session added, tested at the layer where they can be
/// wrong without a phone: the wire contract and the reading of it.
void _stabilityAndMatchTests() {
  group('decisionBody — the variants key', () {
    const opts = SystemOneOptions.starter;

    test('one decision sends no variants key at all', () {
      final body = const SystemOneResult().decisionBody(
        state: 's',
        question: 'q',
        options: opts,
      );
      expect(body.containsKey('variants'), isFalse,
          reason: 'sending 1 explicitly claims the caller thought about it');
      expect(body['choices'], isA<Map>());
    });

    test('more than one sends the count', () {
      final body = const SystemOneResult().decisionBody(
        state: 's',
        question: 'q',
        options: opts,
        variants: 12,
      );
      expect(body['variants'], 12);
    });

    test('nothing else about the body moved', () {
      final one = const SystemOneResult().decisionBody(
          state: 's', question: 'q', options: opts);
      final many = const SystemOneResult().decisionBody(
          state: 's', question: 'q', options: opts, variants: 12);
      expect(many.keys.where((k) => k != 'variants').toSet(),
          one.keys.toSet());
      for (final k in one.keys) {
        expect(many[k], one[k], reason: k);
      }
    });
  });

  group('fromClassify — match', () {
    /// The reason `match` is a `String` in `SystemOneResult` and not the enum:
    /// this file is pure and does not import `decision_model.dart`. So the
    /// equality between the wire name and the enum's name has to be **asserted**,
    /// and this is that assertion — otherwise the two drift and the screen shows
    /// its fallback sentence for a case it has a translation for.
    test('the wire names are the enum names', () {
      for (final m in DecisionMatch.values) {
        expect(m.name, isIn(['letter', 'decoratedLetter', 'label']));
      }
    });

    test('a compliant answer reads as letter', () {
      // The name comes from `DecisionMatch.letter.name`, not from a literal, so
      // renaming the enum case fails here instead of making the screen show its
      // fallback sentence for a case it has a translation for.
      final r = SystemOneResult().fromClassify({
        'model': 'tev1-Q8_0.gguf',
        'choice': 'B',
        'label': 'billing',
        'match': DecisionMatch.letter.name,
        'relevance_score': null,
      });
      expect(r.match, 'letter');
      expect(r.letter, 'B');
      expect(r.label, 'billing');
    });

    test('a written label is its own kind and still an answer', () {
      final r = SystemOneResult().fromClassify({
        'model': 'x',
        'choice': 'A',
        'label': 'bug',
        'match': 'label',
      });
      expect(r.match, 'label');
      expect(r.isFailure, isFalse, reason: 'it did answer — wrongly formatted');
      expect(r.letter, 'A');
    });

    test('an unknown match name survives as itself, not as good news', () {
      // The console falls back to printing the name. If the reader substituted
      // `letter` for anything it did not recognise, a future enum case would be
      // reported as a compliant answer — the screen would lie about a case nobody
      // wrote a sentence for.
      final r = SystemOneResult().fromClassify({
        'model': 'x',
        'choice': 'B',
        'label': 'billing',
        'match': 'someFutureCase',
      });
      expect(r.match, 'someFutureCase');
      expect(r.match, isNot(DecisionMatch.letter.name));
    });

    test('a head has no match, and that is not a gap', () {
      final r = SystemOneResult().fromClassify({
        'model': 'head.tflite',
        'logits': [0.2, -0.1],
      });
      expect(r.match, isNull);
      expect(r.stability, isNull);
    });

    test('a refusal carries no match', () {
      final r = SystemOneResult().fromClassify(
        {'error': 'did not answer', 'raw': 'I cannot help.', 'status': 422},
        status: 422,
      );
      expect(r.isFailure, isTrue);
      expect(r.match, isNull);
      expect(r.stability, isNull);
    });
  });

  group('fromClassify — the stability block', () {
    Map<String, dynamic> block(List<Map<String, Object?>> probes) => {
          'runs': probes.length,
          'stable': false,
          'distinct_answers': 2,
          'failed_runs': 0,
          'leading': 'Financeiro',
          'leading_runs': 2,
          'agreement': 0.667,
          'summary': 'unstable: 2 different answers across 3 runs',
          'probes': probes,
        };

    test('the verdict is recomputed, not copied off the wire', () {
      // The payload claims `stable: false` and 2 distinct; the probes agree.
      // The point is the reverse direction: a payload that lies.
      final r = SystemOneResult().fromClassify({
        'model': 'd1-3B-Q4_K_M.gguf',
        'choice': 'B',
        'label': 'Financeiro',
        'stability': block([
          {
            'order': ['A', 'B', 'C', 'D'],
            'letter': 'B',
            'label': 'Financeiro'
          },
          {
            'order': ['B', 'C', 'D', 'A'],
            'letter': 'A',
            'label': 'Suporte'
          },
          {
            'order': ['C', 'D', 'A', 'B'],
            'letter': 'B',
            'label': 'Financeiro'
          },
        ]),
      });
      final s = r.stability!;
      expect(s.runs, 3);
      expect(s.distinct, 2);
      expect(s.leading, 'Financeiro');
      expect(s.leadingRuns, 2);
      expect(s.isStable, isFalse);
    });

    test('a refused run is counted, not dropped', () {
      final r = SystemOneResult().fromClassify({
        'model': 'x',
        'choice': 'B',
        'label': 'billing',
        'stability': block([
          {
            'order': ['A', 'B'],
            'letter': 'B',
            'label': 'billing'
          },
          {'order': ['B', 'A'], 'letter': null, 'label': null},
        ]),
      });
      final s = r.stability!;
      expect(s.failed, 1);
      expect(s.isStable, isFalse,
          reason: 'one vote is not two out of two');
      expect(s.describe(), contains('produced no answer'));
    });

    test('all runs agreeing reads stable', () {
      final r = SystemOneResult().fromClassify({
        'model': 'x',
        'choice': 'B',
        'label': 'billing',
        'stability': block([
          for (final o in [
            ['A', 'B'],
            ['B', 'A'],
          ])
            {'order': o, 'letter': 'A', 'label': 'billing'},
        ]),
      });
      final s = r.stability!;
      expect(s.isStable, isTrue);
      expect(s.distinct, 1);
      expect(s.agreement, 1.0);
    });

    test('a tally with no probes still recovers refusals as failures', () {
      // The endpoint may send only the summary. `runs` minus the tally's total
      // is the count of refusals, and calling them failures is what stops
      // "answered twice, refused twice" from reading as stable.
      final r = SystemOneResult().fromClassify({
        'model': 'x',
        'choice': 'B',
        'label': 'billing',
        'stability': {
          'runs': 4,
          'tally': {'billing': 2},
        },
      });
      final s = r.stability!;
      expect(s.runs, 4);
      expect(s.leading, 'billing');
      expect(s.leadingRuns, 2);
      expect(s.failed, 2);
      expect(s.isStable, isFalse);
    });

    test('an empty or absent block is null, not an empty verdict', () {
      // "no permutations were run" and "they ran and disagreed" are different
      // facts, and collapsing them makes a screen say "unstable" about a run
      // that was never tested.
      for (final body in <Map<String, dynamic>>[
        {'choice': 'B', 'label': 'billing'},
        {'choice': 'B', 'label': 'billing', 'stability': null},
        {'choice': 'B', 'label': 'billing', 'stability': <String, Object?>{}},
        {
          'choice': 'B',
          'label': 'billing',
          'stability': {'runs': 0}
        },
      ]) {
        expect(SystemOneResult().fromClassify(body).stability, isNull,
            reason: body.toString());
      }
    });

    test('a single run is a fact about one order, not stability', () {
      final r = SystemOneResult().fromClassify({
        'model': 'x',
        'choice': 'B',
        'label': 'billing',
        'stability': block([
          {'order': ['A', 'B'], 'letter': 'B', 'label': 'billing'},
        ]),
      });
      // One run, one answer, one distinct label — the maths says stable, and it
      // IS, but the endpoint deliberately does not send the block at n=1. This
      // test is here to make the reader tolerate the shape if it ever does.
      expect(r.stability!.runs, 1);
      expect(r.stability!.isStable, isTrue);
    });
  });
  _stabilityAndMatchTests();
}
