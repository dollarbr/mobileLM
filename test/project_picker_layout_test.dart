import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mobilelm/widgets/project_picker_dialog.dart';

/// The project picker's action row, at the width and text scale of the device
/// that showed the problem.
///
/// ## The bug
///
/// A `Row` with `spaceBetween` and two text buttons, nothing constraining it.
/// `TextButton` and `FilledButton` each carry horizontal padding of their own,
/// and the labels are sentences in Portuguese — "Nenhum projeto" and "Criar
/// projeto" — so the row's intrinsic width is the sum of two padded labels with
/// nothing left to give. On the Galaxy A72 at the app's **default** font scale
/// of 1.10 it overflowed by 24 px, which is the number in the log and the banner
/// the user saw.
///
/// ## Why the numbers are the device's, not round
///
/// A layout test that picks a comfortable width proves nothing, because the bug
/// is that this row has no width of its own: it needs the *narrowest* realistic
/// width and the *largest* realistic text. 393 dp is the A72's, and 1.10 is
/// `AppConstants.defaultFontScale` — the new out-of-box size, so the case is the
/// one every user gets, not an edge.
///
/// ## The harness proves it can fail
///
/// The first test asserts the `Row` **does** overflow. If a future change makes it
/// stop overflowing, that test fails and says the widths are no longer hostile —
/// at which point the other tests have stopped proving anything and this file is
/// decoration.
void main() {
  const a72 = Size(393, 851);
  const scaleDoApp = 1.10;

  Widget harness({required double textScale, Size size = a72}) {
    return GetMaterialApp(
      // Wrapped in a `MediaQuery`, not passed as one: `builder` must return a
      // Widget, and `copyWith` hands back `MediaQueryData`. And it goes through
      // the `MediaQuery.of(context)` of the *enclosing* tree rather than a
      // hand-made `MediaQueryData` — a fresh one zeroes every other field,
      // viewport size included, and the sub-tree then lays out against a
      // zero-size viewport. The symptom is "the buttons vanished".
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showProjectPicker(const ['TESTES']),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  setUp(() {
    Get.testMode = true;
  });

  tearDown(Get.reset);

  /// Opens the picker and returns the first exception, draining the queue —
  /// `takeException()` hands back **one** per call, and a leftover shows up in
  /// the *next* test accusing it of a failure that belongs to this one.
  Future<Object?> openAndDrain(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    var first = tester.takeException();
    while (tester.takeException() != null) {
      first ??= tester.takeException();
    }
    return first;
  }

  testWidgets('the harness can fail: an unconstrained Row overflows here',
      (tester) async {
    // **The bad row is built in this file, not taken from the app.** An earlier
    // version of this test opened the real dialog and asserted it overflowed,
    // which meant the assertion stopped being true the moment the bug was fixed
    // — and a guard that disappears with its own fix is a guard that says
    // nothing. The shape is copied from the one that broke; the app's own row
    // is a `Wrap` now and is asserted not to overflow by the tests below.
    tester.view.physicalSize = a72 * 3.0;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(GetMaterialApp(
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c)
            .copyWith(textScaler: const TextScaler.linear(scaleDoApp)),
        child: child!,
      ),
      home: Scaffold(
        body: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(onPressed: () {}, child: Text('no_project'.tr)),
            FilledButton(onPressed: () {}, child: Text('create_project'.tr)),
          ],
        ),
      ),
    ));

    expect(tester.takeException(), isA<FlutterError>(),
        reason: 'if a bare Row of these two labels now fits, this width and this '
            'text scale have stopped being hostile and every other test in this '
            'file has stopped proving anything');
  });

  testWidgets('no overflow at the app default text scale', (tester) async {
    tester.view.physicalSize = a72 * 3.0;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(textScale: scaleDoApp));
    expect(await openAndDrain(tester), isNull);
  });

  testWidgets('no overflow at the largest text the app offers', (tester) async {
    // `AppConstants` caps the font slider at 1.4 ("XXL"). A user who drags it
    // there is not misusing the app, so the row has to hold at that scale too.
    tester.view.physicalSize = a72 * 3.0;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(textScale: 1.4));
    expect(await openAndDrain(tester), isNull);
  });

  testWidgets('no overflow on a narrow phone', (tester) async {
    // Narrower than the A72 on purpose: the narrowest phone in the fleet is the
    // one that decides whether the row needs a constraint.
    tester.view.physicalSize = const Size(360, 800) * 3.0;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(textScale: 1.4, size: const Size(360, 800)));
    expect(await openAndDrain(tester), isNull);
  });

  testWidgets('both actions are still there and still labelled', (tester) async {
    // The overflow is not fixed by removing something, and the two answers mean
    // different things: one binds a project, the other explicitly does not.
    tester.view.physicalSize = a72 * 3.0;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(textScale: scaleDoApp));
    await openAndDrain(tester);

    expect(find.text('no_project'.tr), findsOneWidget);
    expect(find.text('create_project'.tr), findsOneWidget);
    expect(find.text('TESTES'), findsWidgets,
        reason: 'the existing project is offered, not just the create field');
  });

  testWidgets('the row wraps instead of sitting on one overflowing line',
      (tester) async {
    // The shape of the fix, asserted rather than assumed. `Wrap` is what this
    // repo settled on after paying for three of these, and the reason is not
    // only that it stops the overflow: these two are *alternatives*, and
    // stacking them says that in a way two buttons side by side do not.
    tester.view.physicalSize = a72 * 3.0;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(textScale: 1.4));
    await openAndDrain(tester);

    final wrap = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(Wrap),
    );
    expect(wrap, findsWidgets);

    // And at the widest scale the two must be on **different** lines, which is
    // the part "does not overflow" alone does not prove — a single `Expanded` per
    // button would also not overflow, and would clip the labels instead.
    final noProject = tester.getRect(find.text('no_project'.tr));
    final create = tester.getRect(find.text('create_project'.tr));
    final sameLine = (noProject.top - create.top).abs() < 2;
    expect(sameLine, isFalse,
        reason: 'at 1.4 the two labels cannot share a line without clipping; if '
            'they now do, they are being squeezed rather than wrapped');
  });
}
