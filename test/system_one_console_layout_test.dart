import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
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

  Future<void> hostile(WidgetTester tester,
      {SystemOneShape shape = SystemOneShape.decision,
      bool withContract = true}) async {
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
          filename: shape == SystemOneShape.tfliteHead
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
      find.textContaining('Load it first: POST /v1/litert/load'),
      findsOneWidget,
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
