// The TFLite head console, under a hostile viewport.
//
// The four traps this screen sits inside, all already paid for elsewhere in this
// codebase and none of them visible at a comfortable width:
//
// 1. **`Obx` nested inside the models list's `Obx`** takes the whole list off the
//    screen — no exception, no error widget, an empty area under a working app
//    bar. The tile that opens this console has none, on purpose.
// 2. **`ListTile` inside a decorated `Container`** trips a `debugAssert` and takes
//    the list with it. Both sheets here use `Material`.
// 3. **`Column` with `mainAxisSize: max` as a direct child of `ListView`** throws
//    in layout.
// 4. **`Row` of long labels** overflows horizontally and takes the list with it
//    — the reason the benchmark verdict card uses `Wrap`. The accelerator chips
//    and the logits rows are the places here that can grow without bound.
//
// And the one that is specific to this screen: a 1024-value feature vector and a
// logits row per class are both content whose width nobody chose.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mobilelm/views/litert_head_console.dart';

/// Drain every exception the framework has queued for this test.
///
/// `takeException()` returns one per call, so a test that builds several
/// offending widgets leaves the rest queued — and they surface inside the
/// **next** test as "Multiple exceptions were detected during the running of the
/// current test", naming the wrong test for an assert that fired in the right
/// one. Measured in `material_scaffold_test.dart`, where it made a control that
/// was supposed to pass fail with an error from the test before it.
int _drain(WidgetTester t) {
  var n = 0;
  while (true) {
    final e = t.takeException();
    if (e == null) return n;
    n++;
  }
}

void main() {
  // A viewport that is narrower than the A72's ~393 dp and a text scale that
  // makes every label wider. Both are hostile on purpose: at a comfortable size
  // none of these would fail, and a layout test that cannot fail proves nothing.
  //
  // Text scale goes through `MaterialApp(builder:)`, not a hand-made
  // `MediaQueryData` — a fresh one zeroes every other field including size, the
  // subtree lays out against a zero viewport, and the symptom is "the content
  // vanished" rather than "it overflowed".
  /// The viewport: narrow, and through `tester.view` rather than a `SizedBox`.
  ///
  /// A `SizedBox` inside a `Scaffold` body does not do what it looks like: the
  /// `Scaffold` gives its body 600 dp regardless, and the console's own
  /// `Expanded` fills that — so the rows past the fold are never built, every
  /// `find.text` after the first matches nothing, and the layout assertions
  /// below become assertions about a void. Measured here: the bar and the
  /// "no model loaded" panel rendered and nothing else, which reads exactly like
  /// "the panel below is missing" if you do not know about `ListView` laziness.
  ///
  /// `tester.view` is the override that actually moves the viewport, and
  /// `addTearDown(tester.view.reset)` puts it back for the next test.
  ///
  /// Wide enough to build every row; narrow on the axis the traps are on.
  void _viewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 2400) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Widget host({double textScale = 2.0}) {
    Get.testMode = true;
    // `baseUrl: ''` rather than a `ServerController`: that controller reads
    // `HiveService`, `InferenceService` and `AppLogService` in its field
    // initialisers, so standing it up would make this a test of the dependency
    // container. An empty address also puts the console in its honest offline
    // state, which is what most of these assertions are about.
    return MaterialApp(
      // `MediaQuery(data: …, child:)` rather than returning the copyWith result:
      // `builder` is typed to return a Widget, and `MediaQueryData` is not one.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      // **No `Scaffold`, and that is the point.**
      //
      // `Scaffold` supplies a `Material`, and every interactive widget in this
      // console needs one: `ChoiceChip`, `TextField` and `InkWell` each assert
      // `debugCheckHasMaterial` against their own ancestors. With a `Scaffold`
      // here, this file passed against a console that threw on the A72 — twice,
      // once per widget type, each found only by looking at the device.
      //
      // The screen is shown by `Get.to(() => LitertHeadConsole(...))`, which puts
      // it under `GetMaterialApp` with nothing in between. Testing it the way it
      // is shown is the only version of this file that can fail.
      home: LitertHeadConsole(
        baseUrl: '',
        // The named case, which is how the Models screen opens it. With no
        // filename and nothing loaded the console correctly refuses, and that
        // refusal is a separate test below.
        filename: 'laya_en_act_head_fp32.tflite',
      ),
    );
  }

  testWidgets('renders with no model loaded, and says so', (tester) async {
    _viewport(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    expect(find.text('TFLite head console'), findsOneWidget);

    // And the run button is present and enabled even though the server is off:
    // a greyed control cannot say whether it is disabled because the server is
    // down or because it is broken.
    expect(find.text('run — server is off'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('run — server is off'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('nothing overflows at 360 dp with text at 2x', (tester) async {
    _viewport(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    // The harness is only worth anything if it *would* catch a real overflow.
    // This is the assertion that makes the others mean something: it fails loudly
    // if a hostile viewport ever stops being hostile, and then they are no longer
    // evidence of anything.
    final overflow = tester.takeException();
    expect(overflow, isNull,
        reason: 'a RenderFlex overflow here takes the whole list off screen');
  });

  // The rule this whole screen sits on, asserted where it is actually true.
  //
  // Both of these were live bugs on the A72, in the same build, minutes apart:
  // the accelerator `ChoiceChip`s threw `debugCheckHasMaterial`, and then the
  // `TextField`s threw the identical assert. The app log named the first one;
  // the second one was only visible in a screenshot, as a red error box where the
  // feature input should be.
  //
  // Neither was a wrong widget — both were correct widgets with no `Material`
  // above them, because `Get.to` supplies none and the console paints its own
  // background. The fix is one `Material` at the root.
  testWidgets('renders with no Material anywhere above it', (tester) async {
    _viewport(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    // Every interactive widget in the console, not the ones this particular
    // state happens to show. The feature fields only exist once a head has been
    // screened, and the assert inside a `TextField` fires at build time — so a
    // test that only reaches the chips would pass with the fields still broken.
    final chips = find.byType(ChoiceChip);
    expect(chips, findsNWidgets(3));
    expect(_drain(tester), 0,
        reason: 'a widget outside every Material throws from build, and the '
            'whole subtree stops rendering while everything around it keeps '
            'working — which is why this cost two device rounds to find');
  });

  testWidgets('the accelerator chips are a Wrap, not a Row', (tester) async {
    _viewport(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    // Three labels, "CPU+GPU" among them, at 2x text. A Row of those in a 360 dp
    // card overflows, and the horizontal overflow has the same blast radius as
    // every other one here.
    expect(find.text('CPU'), findsOneWidget);
    expect(find.text('GPU'), findsOneWidget);
    expect(find.text('CPU+GPU'), findsOneWidget);

    // Exactly one Wrap holding the chips.
    //
    // Not "a Wrap somewhere below the label": the console has several `Wrap`s
    // and this asserts the chips are in one of them rather than in a `Row` that
    // would overflow. `find.descendant` cannot express that, so the chips are
    // located by text and the `Wrap` is looked up from there — a `Wrap` that
    // merely exists elsewhere on the screen would not be the chips' ancestor.
    for (final label in ['CPU', 'GPU', 'CPU+GPU']) {
      final chip = find.ancestor(
        of: find.text(label),
        matching: find.byType(ChoiceChip),
      );
      expect(chip, findsOneWidget, reason: '$label is a chip, not a button');
      expect(
        find.ancestor(of: find.text(label), matching: find.byType(Wrap)),
        findsWidgets,
        reason: 'the chips sit in a Wrap, so they wrap instead of overflowing',
      );
    }
    // And nothing overflowed while proving it.
    expect(tester.takeException(), isNull);
  });

  // The harness assertion, and the reason the other four mean anything: it
  // builds the same layout deliberately wrongly and requires that it fail. If a
  // future change to this file, or to Flutter, makes 360 dp at 2x comfortable
  // again, this goes red and the other tests stop being evidence of anything.
  testWidgets('the harness would catch a Row of these chips', (tester) async {
    _viewport(tester);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2.0)),
        child: child!,
      ),
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: Row(children: [
            for (final l in ['CPU', 'GPU', 'CPU+GPU']) Text(l),
          ]),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNotNull,
        reason: '360 dp at 2x text is supposed to be hostile; if it stopped '
            'being hostile, every other test here is vacuous');
  });

  // What the A72 showed the first time: the console opened from the file's own
  // card and said "No .tflite loaded", because it asked the runtime what was
  // loaded and nothing was — the user had not pressed Load yet. A console that
  // cannot load the file you opened it from is a dead end, so it now takes the
  // filename from the card and shows the refusal only when it has neither.
  testWidgets('a console with neither a name nor a model says so, and how to fix it',
      (tester) async {
    _viewport(tester);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2.0)),
        child: child!,
      ),
      home: const LitertHeadConsole(baseUrl: ''),
    ));
    await tester.pump();

    // The refusal names the path out, the way every other refusal in this app
    // does. "Nothing here" without a next step is the failure mode it avoids.
    expect(find.text('No .tflite to work on'), findsOneWidget);
    expect(
      find.textContaining('gets a card in Models'),
      findsOneWidget,
      reason: 'the refusal says where to go, not just that there is nothing',
    );
  });

  testWidgets('the screen panel says the file is not read yet', (tester) async {
    _viewport(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    // Stated rather than blank. An empty panel reads as "there is nothing to
    // say" and an unstated one reads as "there was nothing to find".
    expect(find.text('what the file says about itself'), findsOneWidget);
    expect(find.text('not screened yet'), findsOneWidget);
    expect(find.text('screen'), findsOneWidget);
    expect(find.text('load'), findsOneWidget);
  });

  testWidgets('the barrier the console must not cross is on screen', (tester) async {
    _viewport(tester);
    await tester.pumpWidget(host());
    await tester.pump();

    // The accelerator panel's whole job is to not overclaim. The sentence that
    // says LiteRT does not expose the executed accelerator has to be present
    // before anything is loaded, because that is when the user is deciding
    // whether to trust the number.
    expect(
      find.textContaining('does not expose the accelerator'),
      findsOneWidget,
    );
    expect(find.textContaining('requested:'), findsOneWidget);
  });

  tearDown(() {
    Get.reset();
  });
}