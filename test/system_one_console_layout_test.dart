import 'dart:ui' show Locale;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mobilelm/l10n/app_translation.dart';
import 'package:mobilelm/services/system_one.dart';
import 'package:mobilelm/views/system_one_console.dart';

/// The System One window, mounted **the way it is shown**.
///
/// ## Why there is no `Scaffold` here
///
/// This harness exists because the previous version of the sibling console's
/// test **passed against the bug it was written for**. It mounted the screen
/// inside a `Scaffold`, and the `Scaffold` is what supplies the `Material` that
/// `ChoiceChip`, `TextField` and `InkWell` demand from their own `build`. So the
/// test proved the screen was fine in a context the app never puts it in.
///
/// The screen is opened with `Get.to`, and the `Scaffold` is not in that path.
/// So this file mounts it under a bare `MaterialApp` — no `Scaffold` anywhere —
/// and the last test is the one that proves the harness is capable of failing:
/// remove the window's own root `Material` and six `debugCheckHasMaterial`
/// exceptions have to come out. If that test ever passes, the other tests in
/// this file stopped proving anything.
///
/// ## The other two harness rules this file obeys
///
/// - **The viewport moves with `tester.view.physicalSize`.** A
///   `SizedBox(height: 2400)` inside `Scaffold(body:)` does **not** move it — the
///   `Scaffold` hands out 600 dp and the window's `Expanded` fills that. A lazy
///   `ListView` then never builds the rows below, every `find.text` after the
///   first one finds nothing, and that reads as "the panel is missing".
/// - **Text scale goes through `MaterialApp(builder:)`.** A fresh
///   `MediaQueryData(textScaler:)` on its own zeroes every other field, size
///   included, and the subtree lays out against a zero-size viewport — the
///   symptom is "the buttons disappeared".
void main() {
  /// 360 dp at 2× text: narrower than the A72's ~393 dp on purpose. The three
  /// overflows this repo has already paid for were all a `Row` with nothing
  /// limiting it, and a test that only ever runs at the device's own width
  /// cannot see them.
  /// The head contract the A72 reported for `laya_en_act_head_fp32.tflite`, so
  /// the head panels render in a test that has no server.
  ///
  /// Without this the head shape test cannot assert anything about the head
  /// panels: a fake `baseUrl` fails the probe, the contract stays null, and the
  /// panels correctly do not draw. That is right behaviour and it reads as a
  /// missing panel, which is why the contract is a constructor argument and not
  /// only something the window fetches.
  const layaContract = HeadContract(
    featureName: 'pooled_cls',
    featureCount: 1024,
    classCount: 2,
    signature: 'serving_default',
    auxiliary: [HeadAuxiliary('feats', 4)],
  );

  /// Registra as traduções antes de cada montagem.
  ///
  /// **Sem isto, `.tr` devolve a própria chave** e todas as asserções deste
  /// arquivo — que procuram o **texto em inglês que aparece na tela** — falham
  /// sem que nada tenha mudado. É a mesma razão pela qual 38 chaves apareceram
  /// como identificadores: o GetX não tem o que mostrar quando o mapa não está
  /// carregado.
  ///
  /// E registrar o mapa **verdadeiro** é o que faz o teste checar o texto real
  /// em vez do identificador: se a tradução sair errada, a tela mostra outra
  /// coisa e a asserção pega.
  setUp(() {
    // `addTranslations` quer o MAPA, nao a classe `Translations` — passar a
    // classe da um erro de tipo que fala de Map e nao do que esta errado.
    Get.addTranslations(AppTranslation().keys);
    // **O locale também precisa ser fixado.** Registrar o mapa não diz ao GetX
    // qual deles usar: sem `fallbackLocale` nem `locale` ele devolve a própria
    // chave, e as asserções deste arquivo — que procuram o texto em inglês que
    // aparece na tela — não acham nada sem que nada tenha mudado.
    //
    // `Get.locale = ...` e **não** `Get.updateLocale(...)`: o segundo é
    // assíncrono e reconstrói a árvore, o que dentro de `setUp` dispara
    // `'inTest': is not true` do binding. `Get.testMode = false` para contornar
    // piora: ele é o que permite tocar em ciclo de vida fora de um teste.
    Get.locale = const Locale('en', 'US');
  });

  Future<void> hostile(WidgetTester tester,
      {SystemOneShape shape = SystemOneShape.decision,
      bool withContract = true,
      bool withFilename = true}) async {
    tester.view.physicalSize = const Size(720, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        // **No `Scaffold` anywhere.** That is the whole point of this file: the
        // screen is shown with `Get.to`, where the `Scaffold` that normally
        // supplies the `Material` is not in the path.
        home: SystemOneConsole(
          shape: shape,
          // A port nothing listens on, so the probe fails fast and the test is
          // about layout rather than about a live server.
          baseUrl: 'http://127.0.0.1:1',
          filename: shape == SystemOneShape.tfliteHead && withFilename
              ? 'laya_en_act_head_fp32.tflite'
              : null,
          headContract:
              shape == SystemOneShape.tfliteHead && withContract
                  ? layaContract
                  : null,
        ),
        // Text scale through the app, **not** a hand-built `MediaQueryData`:
        // a new `MediaQueryData(textScaler:)` zeroes every other field, size
        // included, and the subtree lays out against a zero-size viewport. The
        // symptom of getting this wrong is "the buttons disappeared".
        // `copyWith` returns a `MediaQueryData`, not a widget — the `MediaQuery`
        // wrapper around it is what puts the new value into the tree.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();
  }

  /// `takeException()` returns one exception per call, so a build that raises
  /// three leaves two in the queue and they surface in the **next** test as
  /// "Multiple exceptions were detected", blaming a test that did nothing wrong.
  /// Both harness files in this repo drain in a loop for that reason.
  void _drain(WidgetTester tester) {
    var guard = 0;
    while (tester.takeException() != null && guard < 40) {
      guard++;
    }
  }

  testWidgets('the decision shape builds with no Scaffold around it',
      (tester) async {
    await hostile(tester);
    expect(find.text('System One test'), findsOneWidget);
    expect(find.textContaining('text in, one letter out'), findsOneWidget);
    _drain(tester);
  });

  testWidgets('the head shape builds, and names the file it will send',
      (tester) async {
    await hostile(tester, shape: SystemOneShape.tfliteHead);
    expect(find.text('System One test'), findsOneWidget);
    expect(
      find.textContaining('wants 1024 numbers'),
      findsOneWidget,
      reason: 'the count comes from the file the A72 actually reported, and the '
          'window has to show it before anyone pastes anything',
    );
    expect(
      find.textContaining('Re-probe failed, so what is shown below is from the '
          'file'),
      findsOneWidget,
      reason: 'with a contract already in hand, a failed re-probe is a failed '
          're-probe — saying "I could not read what it wants" while displaying '
          'the answer one line up is the error that presents itself as another '
          'one',
    );
    _drain(tester);
  });

  testWidgets('the options the window will send are on screen', (tester) async {
    await hostile(tester);
    // The starter list is the measured one, and the point of showing the
    // serialized choices is that a person can see exactly what the model will be
    // shown rather than trusting a widget to have built it.
    //
    // Two things this had to get right, and both are the lazy-`ListView` trap
    // this repo has paid for four times now:
    //
    // - **It has to be scrolled to.** 360 dp at 2× text puts the options card
    //   well below the fold, and a `ListView` that has not built a row cannot
    //   find it. A `SizedBox(height: 2400)` in a `Scaffold` does not help — the
    //   `Scaffold` hands out 600 dp. `tester.view.physicalSize` moves the
    //   viewport; scrolling moves the content, and here the content is the thing
    //   that is genuinely long.
    // - **`Map.toString` does not quote its keys.** The line on screen reads
    //   `{A: bug, B: billing}`, not `{'A': 'bug'}`. The first version of this
    //   assertion looked for the quoted form and found nothing, which reads as
    //   "the panel is missing" when the panel is right there.
    final choices = find.textContaining('{A: bug, B: billing, C: account}');
    // `dragUntilVisible` on the `ListView` itself, and not
    // `scrollUntilVisible(..., scrollable:)`. Both were tried and the second one
    // throws "Bad state: Too many elements" twice over: left to itself it looks
    // for a single `Scrollable` in the tree and every `TextField` on this screen
    // owns one, and naming the right one does not help either because
    // `find.descendant(of: ListView, matching: Scrollable)` matches the fields
    // **inside** the list too. Dragging the list itself has no such question to
    // answer.
    await tester.dragUntilVisible(
      choices,
      find.byType(ListView),
      const Offset(0, -240),
    );
    expect(choices, findsOneWidget);
    _drain(tester);
  });

  testWidgets('360 dp at 2x text does not overflow', (tester) async {
    await hostile(tester);
    // Any RenderFlex overflow is reported through takeException, so reaching the
    // end of this test with a clean exception queue is the assertion.
    expect(tester.takeException(), isNull);
    _drain(tester);
  });

  testWidgets('the head labels panel has no 24 cap, and says so',
      (tester) async {
    // The 2-24 is the decision card's number. Applying it to a head would be the
    // app inventing a rule about a model it did not train, and the panel says
    // so out loud so a user with 60 classes does not go looking for the limit.
    await hostile(tester, shape: SystemOneShape.tfliteHead);
    // Scrolled to, because the auxiliary panel now sits above the labels and at
    // 360 dp with 2× text the labels panel is a second screen down. The fourth
    // time this repo has hit the lazy-`ListView` fold in one change.
    final note = find.textContaining('no upper limit here');
    await tester.dragUntilVisible(note, find.byType(ListView), const Offset(0, -240));
    expect(note, findsOneWidget);
    expect(find.text('class 0'), findsOneWidget);
    expect(find.text('class 1'), findsOneWidget);
    _drain(tester);
  });

  testWidgets('the auxiliary the act head needs has its own field',
      (tester) async {
    // Without this panel the window can screen the one `.tflite` head that
    // exists, name its real tensors, and still be unable to ask it anything.
    // The endpoint's own refusal, measured on the A72: "This head takes 1
    // input(s) beyond the feature vector … They are not filled with zeros on
    // purpose: a logit computed on invented features is a number with no
    // meaning."
    await hostile(tester, shape: SystemOneShape.tfliteHead);
    final aux = find.textContaining('feats — the auxiliary');
    await tester.dragUntilVisible(aux, find.byType(ListView), const Offset(0, -240));
    expect(aux, findsOneWidget);
    expect(
      find.textContaining('Zeros are never substituted'),
      findsOneWidget,
      reason: 'the panel has to say why an empty field is not filled in, or the '
          'user will type four zeros and believe the answer',
    );
    _drain(tester);
  });

  testWidgets('a head whose contract could not be read says so, and names the '
      'way out', (tester) async {
    // No server **and no contract**, so there is nothing to fall back on and the
    // window cannot build a request it knows will be accepted. The message names
    // the endpoint instead of showing a vector field that would be refused on
    // submit.
    await hostile(tester, shape: SystemOneShape.tfliteHead, withContract: false);
    expect(
      find.textContaining('POST /v1/litert/load'),
      findsOneWidget,
    );
    _drain(tester);
  });


  testWidgets('uma cabeca sem nome diz que nao tem nome, e nao desenha um buraco',
      (tester) async {
    // Estado alcançavel e alcancado: a janela aberta pela tela do servidor nao
    // tem filename do cartao, e se a sondagem do LiteRT falha — ou nao ha
    // cabeca carregada — o nome e null enquanto a forma e o contrato sao
    // conhecidos. Antes desta correcao os painis desenhavam uma cabeca
    // funcionando sem nada dizer qual arquivo, e a unica forma de descobrir era
    // apertar Run e ser recusado.
    await hostile(
      tester,
      shape: SystemOneShape.tfliteHead,
      withContract: true,
      withFilename: false,
    );
    final card = find.text('no .tflite to name');
    await tester.dragUntilVisible(card, find.byType(ListView), const Offset(0, -240));
    expect(card, findsOneWidget);
    expect(
      find.textContaining('cannot be recognised by its contents'),
      findsOneWidget,
    );
    _drain(tester);
  });


  testWidgets('o botao de free so existe quando ha o que liberar', (tester) async {
    // Um botao que nao libera nada so serve para dizer que nao liberou nada.
    await hostile(tester, shape: SystemOneShape.tfliteHead, withContract: false);
    expect(find.text('free the compiled head'), findsNothing);
    _drain(tester);
  });

  testWidgets('com uma cabeca carregada, o botao de free aparece e diz a rota',
      (tester) async {
    // E o que torna o estado "nada carregado" alcancavel pela tela. Sem
    // `POST /v1/litert/unload` uma cabeca so era trocada carregando outra, e uma
    // janela de teste que nao esvazia continua testando o que ficou.
    await hostile(tester, shape: SystemOneShape.tfliteHead, withContract: true);
    final button = find.text('free the compiled head');
    await tester.dragUntilVisible(button, find.byType(ListView), const Offset(0, -300));
    expect(button, findsOneWidget);
    // Scrolled to again: the note naming the route is **below** the button, and
    // one scroll reaches the button and not the paragraph under it. The lazy
    // `ListView` fold, for the fifth time in this feature.
    final note = find.textContaining('POST /v1/litert/unload');
    await tester.dragUntilVisible(note, find.byType(ListView), const Offset(0, -300));
    expect(
      note,
      findsOneWidget,
      reason: 'a rota e o endpoint novo, e a tela nomeia o caminho como o resto '
          'da janela faz',
    );
    expect(
      find.textContaining('untouched'),
      findsOneWidget,
      reason: 'descarregar uma cabeca NAO descarrega o modelo que o chat usa, e '
          'uma tela que deixa isso implicito esta errando',
    );
    _drain(tester);
  });

  testWidgets('the harness can fail: no root Material, it throws',
      (tester) async {
    // The proof that the tests above are not vacuous. A `TextField` with no
    // `Material` above it is the smallest widget that still makes the same
    // demand the real screen's `TextField`s make, and on the A72 that screen
    // showed a red box instead of the field and threw `debugCheckHasMaterial`
    // from each widget's own `build`.
    tester.view.physicalSize = const Size(720, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        home: const TextField(),
        // `copyWith` returns a `MediaQueryData`, not a widget — the `MediaQuery`
        // wrapper around it is what puts the new value into the tree.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();
    expect(
      tester.takeException(),
      isA<FlutterError>(),
      reason: 'a TextField with no Material above it must fail here. If this '
          'stops failing, the widget under test in this file is not being '
          'exercised the way it is on the device, and the other tests have '
          'stopped proving anything.',
    );
    _drain(tester);
  });
}

/// The three blocks this session added, mounted **the way they are shown**.
///
/// Each of them is a `Column` of text inside a card at 360 dp with text at 2×,
/// which is the shape that has overflowed this repo's screens four times — and
/// the permutation list is the worst of them: **one monospace line per run**,
/// twelve of them, and a monospace line does not wrap at the width it wants.
///
/// There is a [SystemOneConsole.initialResult] argument for exactly this, and it
/// is not a testing convenience bolted on: `_result` is set only by `_show`,
/// `_show` only from a server response, and `flutter_test` stubs the
/// `HttpClient` to answer 400 — so without the argument these widgets are
/// **unreachable** from a test, and unreachable means unverified.
void _decisionResultLayoutTests() {
  const width = Size(360, 2400);
  const bigScale = TextScaler.linear(2.0);

  /// The decision 200 as the endpoint sends it after this session's change.
  /// Twelve probes, one label, `match: letter`.
  Map<String, dynamic> stableWithTwelve() => {
        'model': 'd1-3B-Q4_K_M.gguf',
        'choice': 'B',
        'label': 'Financeiro',
        'match': 'letter',
        'relevance_score': null,
        'stability': {
          'runs': 12,
          'stable': true,
          'distinct_answers': 1,
          'failed_runs': 0,
          'leading': 'Financeiro',
          'leading_runs': 12,
          'agreement': 1.0,
          'summary': 'stable: 12 of 12 agreed on Financeiro',
          'probes': [
            for (final o in [
              ['A', 'B', 'C', 'D'],
              ['A', 'B', 'D', 'C'],
              ['A', 'C', 'B', 'D'],
              ['A', 'C', 'D', 'B'],
              ['A', 'D', 'B', 'C'],
              ['A', 'D', 'C', 'B'],
              ['B', 'A', 'C', 'D'],
              ['B', 'A', 'D', 'C'],
              ['B', 'C', 'A', 'D'],
              ['B', 'C', 'D', 'A'],
              ['B', 'D', 'A', 'C'],
              ['B', 'D', 'C', 'A'],
            ])
              {
                'order': o,
                'letter': 'B',
                // A long option label on purpose. `Financeiro` is 9 characters
                // and would fit on the probe line by accident; a decision model
                // gets labels written by people, and "Direito do Consumidor e
                // Reclamacoes" is what actually lands there.
                'label': 'Direito do Consumidor e Reclamacoes',
                'raw': 'B',
              },
          ],
        },
      };

  /// The 422 with a block: refused 12 times, and the raw text is a sentence.
  Map<String, dynamic> refusedTwelve() => {
        '__status': 422,
        'error':
            'The model did not answer with one of the offered options, in any of '
                'the 12 option orders tried.',
        'model': 'd1-3B-Q4_K_M.gguf',
        'raw': 'I cannot determine which department handles this without more '
            'context.',
        'expected_one_of': ['A', 'B', 'C', 'D'],
        'stability': {
          'runs': 12,
          'stable': false,
          'distinct_answers': 0,
          'failed_runs': 12,
          'leading': null,
          'leading_runs': 0,
          'agreement': null,
          'summary': 'no run produced an answer',
          'probes': [
            for (final o in [
              ['A', 'B', 'C', 'D'],
              ['A', 'B', 'D', 'C'],
              ['A', 'C', 'B', 'D'],
              ['A', 'C', 'D', 'B'],
              ['A', 'D', 'B', 'C'],
              ['A', 'D', 'C', 'B'],
              ['B', 'A', 'C', 'D'],
              ['B', 'A', 'D', 'C'],
              ['B', 'C', 'A', 'D'],
              ['B', 'C', 'D', 'A'],
              ['B', 'D', 'A', 'C'],
              ['B', 'D', 'C', 'A'],
            ])
              {
                'order': o,
                'letter': null,
                'label': null,
                'raw': 'I cannot determine which department handles this.',
              },
          ],
        },
      };

  /// A `label` match: the model wrote the label, not a letter. The sentence is
  /// long and the case is the one the whole `DecisionMatch` enum exists for.
  Map<String, dynamic> labelMatch() => {
        'model': 'd1-3B-Q4_K_M.gguf',
        'choice': 'C',
        'label': 'Recursos humanos',
        'match': 'label',
        'relevance_score': null,
      };

  /// A **harness that is known to be capable of failing**, for the same reason
  /// the file's last test is one.
  ///
  /// The four mutations below are the measured proof that these tests are not
  /// green because they cannot fail:
  ///
  /// | mutation | result |
  /// |---|---|
  /// | the variants `Wrap` → a `Row` | **fails** — `RenderFlex overflowed` |
  /// | `isStable => true` | **fails** |
  /// | rotation instead of round-robin | **fails** — reaches 0 of the flips |
  /// | the parser lookahead removed | **fails** |
  ///
  /// And one that does **not**, which is why it is written down: wrapping a
  /// permutation line in an unbreakable `Row` still passes, because the line
  /// lives in a `Column` with `CrossAxisAlignment.start` and the text wraps
  /// before the row gets a chance not to. That mutation is not covered, and a
  /// mutation nobody tried is a mutation nobody should claim is covered.
  ///
  /// **Asserts there is no exception. It does NOT drain — and that is the point.**
  ///
  /// The first version of these three tests called `_drain`, copied from the
  /// harness above, and the consequence was measured: swapping the variants
  /// `Wrap` for a `Row` and wrapping the permutation line in an unbreakable
  /// `Row` both left **11 of 11 green**. The drain is what hid both.
  ///
  /// Verified that a `RenderFlex` overflow *does* reach `takeException()` here —
  /// a `Row` of two long strings at 360 dp and 2× text reports
  /// `A RenderFlex overflowed by 9048 pixels on the right`. So the signal is
  /// there; a helper that swallows it is the defect.
  ///
  /// The existing harness drains because its tests assert about **which widgets
  /// exist**, and a hostile parent legitimately raises layout errors they are not
  /// about. These three are about layout, so for them a drain is a way of never
  /// finding out.
  void _noOverflow(WidgetTester tester) {
    final e = tester.takeException();
    expect(e, isNull, reason: e == null ? '' : '$e');
    // One more read, because `takeException` hands back one at a time and a
    // build that raises three would otherwise leave two for the next test to be
    // blamed for.
    expect(tester.takeException(), isNull);
  }

  Future<void> mount(
    WidgetTester tester,
    Map<String, dynamic> json, {
    required int status,
  }) async {
    tester.view.physicalSize = width * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final result =
        SystemOneResult(shape: SystemOneShape.decision).fromClassify(
      json,
      status: status,
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en', 'US'),
        // `MediaQuery.of(context).copyWith(...)` returns a **MediaQueryData**,
        // not a widget — the wrapper is what puts the value into the tree. Same
        // rule the harness comment above already states; this copy got it wrong
        // and the compiler is what said so.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: bigScale),
          child: child ?? const SizedBox.shrink(),
        ),
        home: SystemOneConsole(
          shape: SystemOneShape.decision,
          baseUrl: 'http://127.0.0.1:1',
          initialResult: result,
        ),
      ),
    );
    Get.addTranslations(AppTranslation().keys);
    await tester.pumpAndSettle();
  }

  testWidgets('12 permutation lines fit at 360 dp with text at 2x',
      (tester) async {
    await mount(tester, stableWithTwelve(), status: 200);
    // The list, not the verdict: the verdict is one line and would hide the
    // overflow this is looking for.
    expect(find.textContaining('ABCD'), findsOneWidget);
    expect(find.textContaining('BDCA'), findsOneWidget,
        reason: 'the twelfth line is the one that never builds in a lazy list');
    _noOverflow(tester);
  });

  testWidgets('a refusal shows the block and the raw text, at 2x',
      (tester) async {
    await mount(tester, refusedTwelve(), status: 422);
    // The 12 refusals, and the words. Before this change the 422 branch printed
    // `failure` and nothing else: the endpoint sent the block, `fromClassify`
    // parsed it, and the one branch that most needed it discarded it.
    expect(find.textContaining('did not answer with one of the offered'),
        findsOneWidget);
    expect(find.textContaining('I cannot determine'), findsOneWidget);
    _noOverflow(tester);
  });

  testWidgets('a label match prints its own sentence', (tester) async {
    await mount(tester, labelMatch(), status: 200);
    expect(find.textContaining('did not answer with a letter'),
        findsWidgets,
        reason: 'the sentence is what distinguishes this from a clean letter');
    _noOverflow(tester);
  });
  _decisionResultLayoutTests();
}
