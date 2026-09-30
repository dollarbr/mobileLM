// The benchmark card's action row, and why it is a Wrap.
//
// This is the third time the Models screen has lost its whole list to a layout
// problem, and the first two are already written down in AGENTS.md: a `Column`
// with `mainAxisSize: max` as a direct child of `ListView`, and a `ListTile`
// with an `onTap` inside a decorated `Container`. All of them kill every row on
// the screen, not just the offending one, and none of them is visible in a
// screenshot taken on a device that happens to be wide enough.
//
// So the test is deliberately hostile: 360 dp, narrower than the A72's ~393 dp,
// and a doubled system text scale. A layout test that only passes at the width
// and font size the author happened to have is not a test — it is a screenshot
// with assertions on it.
//
// The labels are copied out of the card rather than reached into, because the
// real widget needs GetX services and a model download behind it. What is under
// test is the layout decision, and the labels are the reason it was the wrong
// one: the card offered "Hide the local model list", "Show it anyway" and
// "Keep models anyway" side by side in a Row, with nothing bounding any of
// them.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The A72 is 1080 px at 2,75x, about 393 dp. 360 dp is narrower than that.
const narrowPhone = Size(360, 800);

const _labels = [
  'Local list hidden',
  'Show it anyway',
  'Keep models anyway',
];

List<Widget> _actionButtons() => [
      for (final label in _labels)
        TextButton(
          onPressed: () {},
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 30),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(label),
        ),
    ];

/// The Models screen's shape around the card: a long list, one card, more list.
///
/// The rows above and below are the point. An overflow in the card is only
/// survivable if the rest of the screen still laid out, and this reproduces the
/// conditions where it is not.
Widget _screen({
  required Widget cardBody,
  double textScale = 1.0,
}) {
  return MaterialApp(
    // `builder` with `copyWith`, not a hand-built `MediaQueryData`. A fresh
    // `MediaQueryData(textScaler: ...)` zeroes every other field, size
    // included, and the subtree lays out against a zero-sized viewport — which
    // presents as "the buttons vanished" and is a harness failure wearing the
    // costume of a code failure. That cost one run here.
    //
    // `platformDispatcher.textScaleFactorTestValue` is the other way, and it
    // also failed: it conflicts with the `tester.view` overrides used for the
    // size, and the two together left the tree unbuilt.
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        // The card first, and this is the real screen's order, not a
        // convenience: `model_view.dart` puts the benchmark and memory cards at
        // the top and the catalogue below. It is also load-bearing here, because
        // a `ListView` builds lazily — with a dozen rows above the card it is
        // never constructed at all, every assertion below passes vacuously, and
        // the "Row overflows" test fails because nothing rendered. A green
        // layout test that never laid anything out is the trap.
        body: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  Expanded(child: Column(children: [cardBody])),
                  IconButton(onPressed: () {}, icon: const Icon(Icons.close)),
                ],
              ),
            ),
            for (var i = 0; i < 12; i++)
              ListTile(title: Text('catalogue row $i')),
          ],
        ),
      ),
    ),
  );
}

void _narrow(WidgetTester tester) {
  tester.view.physicalSize = narrowPhone * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('the catalogue above the card survives a 2x text scale',
      (tester) async {
    // The control. If the harness itself is broken, this fails first and says
    // so, instead of every later failure pointing at the card.
    _narrow(tester);
    await tester.pumpWidget(_screen(cardBody: Wrap(children: _actionButtons()),
        textScale: 2.0));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('catalogue row 0'), findsOneWidget);
  });

  testWidgets('a Wrap carries three actions at 2x on a 360 dp phone',
      (tester) async {
    _narrow(tester);
    await tester.pumpWidget(_screen(
        cardBody: Wrap(spacing: 2, children: _actionButtons()),
        textScale: 2.0));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the actions wrap to a second line rather than running off',
      (tester) async {
    // Asserted through geometry, because "it did not throw" would also pass for
    // a card that kept one button and dropped the other two.
    _narrow(tester);
    await tester.pumpWidget(_screen(
        cardBody: Wrap(spacing: 2, children: _actionButtons()),
        textScale: 2.0));
    await tester.pumpAndSettle();

    final lines = <double>{
      for (final label in _labels) tester.getTopLeft(find.text(label)).dy,
    };
    expect(lines.length, greaterThan(1),
        reason: 'the three labels cannot share one line at this width, so the '
            'layout has to stack them');
  });

  testWidgets('every action stays reachable, none truncated away',
      (tester) async {
    _narrow(tester);
    await tester.pumpWidget(_screen(
        cardBody: Wrap(spacing: 2, children: _actionButtons()),
        textScale: 2.0));
    await tester.pumpAndSettle();

    for (final label in _labels) {
      expect(find.text(label), findsOneWidget, reason: '$label must survive');
    }
  });

  testWidgets('a Row of the same three actions overflows — the bug, pinned',
      (tester) async {
    // The regression this file exists for. It is expected to fail; if it ever
    // passes, the widths stopped being hostile and the three tests above have
    // stopped proving anything.
    _narrow(tester);
    await tester.pumpWidget(_screen(
        cardBody: Row(children: _actionButtons()), textScale: 2.0));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNotNull,
        reason: 'Row of unbounded action labels is the overflow');
  });
}
