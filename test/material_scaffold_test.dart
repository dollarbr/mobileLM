import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// A `ListTile` with an `onTap` paints its background and its ink splash on the
/// nearest `Material` ancestor, and a `debugAssert` inside `ListTile` fires when
/// something with a background colour sits between the two.
///
/// The cost of finding that out on a device was eight builds, because the
/// assertion does not reach `FlutterError.onError` in any readable form, the app
/// bar above the list keeps working, and the whole list simply disappears. It
/// also only fires on the branch that builds the `InkWell`, so it needs `onTap`
/// *and* a decorated ancestor: each half on its own renders fine, which is
/// enough to send you looking through every other part of the widget.
///
/// This test is the cheap channel. It failed in a second; the device took two
/// hours.
class _Probe extends GetxController {
  final first = <String>[].obs;
  final scope = 'local'.obs;
}

/// Drain every exception the framework has queued for this test.
///
/// `takeException()` returns one per call, so a test that builds two offending
/// widgets leaves the second queued — and it surfaces inside the **next** test as
/// "Multiple exceptions were detected during the running of the current test",
/// naming the wrong test for an assert that fired in the right one. Measured here,
/// and it is why the control test failed on its first run while the bug it
/// controlled for was already fixed.
int _drain(WidgetTester t) {
  var n = 0;
  while (true) {
    final e = t.takeException();
    if (e == null) return n;
    n++;
  }
}

void main() {
  testWidgets('a decorated Container around a tappable ListTile is rejected',
      (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF2C2C2E),
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              title: const Text('Encoders'),
              onTap: () {},
            ),
          ),
        ]),
      ),
    ));
    // Recorded so the failure is not silent if the assert ever stops firing.
    expect(t.takeException(), isNotNull,
        reason: 'the assert this test exists for stopped firing');
  });

  testWidgets('the same tile inside a Material renders', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          Material(
            color: const Color(0xFF2C2C2E),
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              title: const Text('Encoders'),
              onTap: () {},
            ),
          ),
        ]),
      ),
    ));
    expect(t.takeException(), isNull);
    expect(find.text('Encoders'), findsOneWidget);
  });

  group('a nested Obx inside a list Obx', () {
    tearDown(Get.reset);

    testWidgets('several of them render and react', (t) async {
      Get.put(_Probe());
      final c = Get.find<_Probe>();
      c.first.addAll(['a', 'b']);
      await t.pumpWidget(GetMaterialApp(
        home: Scaffold(
          body: RefreshIndicator(
            onRefresh: () async {},
            child: Obx(() => ListView(children: [
                  Obx(() => Text('scope ${c.scope.value}')),
                  const SizedBox(height: 14),
                  Obx(() => Text('count ${c.first.length}')),
                  const SizedBox(height: 14),
                  Material(
                    color: const Color(0xFF2C2C2E),
                    child: ListTile(
                      title: Text('encoders ${c.first.length}'),
                      onTap: () {},
                    ),
                  ),
                ])),
          ),
        ),
      ));
      expect(t.takeException(), isNull);
      expect(find.text('scope local'), findsOneWidget);
      expect(find.text('count 2'), findsOneWidget);
      expect(find.text('encoders 2'), findsOneWidget);

      c.scope.value = 'online';
      await t.pump();
      expect(find.text('scope online'), findsOneWidget);
    });
  });

  // The same assert, the other widget that makes it.
  //
  // `ChoiceChip` calls `debugCheckHasMaterial` on itself, and so the `Container`
  // + `BoxDecoration` pattern this file is about is just as fatal for a chip as
  // for a `ListTile`. Found on the A72 with the TFLite console: the accelerator
  // chips were inside a decorated card, every one of them threw from `build`, and
  // the console's subtree stopped rendering while the app bar and the tab bar
  // kept working — which is the exact failure shape that cost eight builds the
  // first time.
  //
  // Same cost, same blindness, so the fix gets the same kind of test: the broken
  // arrangement has to be asserted as broken, otherwise the working one below it
  // proves nothing about the harness.
  // The exact shape that broke, and the shape that fixes it.
  //
  // Two things had to be got right for this test to be worth anything, and both
  // were wrong first:
  //
  // - **No `Scaffold`.** `Scaffold` inserts a `Material` of its own, so a test
  //   with one passes against a bug the A72 had really hit. The console is shown
  //   by `Get.to`, which puts it under `GetMaterialApp` and nothing else.
  // - **No `MaterialApp` either**, or rather: no *implicit* Material from it. A
  //   `MaterialApp` supplies `MaterialLocalizations`, which the chip needs to
  //   build at all, so removing it makes the chip fail for the wrong reason and
  //   never reach the assert. The arrangement below keeps the localizations and
  //   takes away the `Material`, which is the only way to isolate this assert.
  testWidgets('a decorated card with no Material is rejected', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Wrap(spacing: 8, children: [
          for (final label in ['CPU', 'GPU'])
            ChoiceChip(label: Text(label), selected: false, onSelected: (_) {}),
        ]),
      ),
    ));
    await t.pump();
    expect(_drain(t), greaterThanOrEqualTo(1),
        reason: 'the assert this test exists for stopped firing');
  });

  // The control for the control. Without it, "a Material makes it pass" is an
  // assumption, and the fix in the TFLite console could have been any change that
  // happened to stop the complaint.
  testWidgets('the same card with a transparent Material inside renders', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Wrap(spacing: 8, children: [
            for (final label in ['CPU', 'GPU'])
              ChoiceChip(label: Text(label), selected: false, onSelected: (_) {}),
          ]),
        ),
      ),
    ));
    await t.pump();
    expect(_drain(t), 0,
        reason: 'one Material should stop the assert entirely, not reduce it');
    expect(find.text('CPU'), findsOneWidget);
    expect(find.text('GPU'), findsOneWidget);
  });

  // And it is a real control, not just something that renders: a chip that
  // swallowed the tap would satisfy every assertion above.
  testWidgets('and the chip reacts to a tap', (t) async {
    var picked = <String>[];
    await t.pumpWidget(MaterialApp(
      home: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Builder(builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('accelerator', style: Theme.of(context).textTheme.bodySmall),
              Wrap(spacing: 8, children: [
                for (final label in ['CPU', 'GPU', 'CPU+GPU'])
                  ChoiceChip(
                    label: Text(label),
                    selected: false,
                    onSelected: (_) => picked.add(label),
                  ),
              ]),
            ],
          )),
        ),
      ),
    ));
    await t.pump();
    expect(_drain(t), 0);

    await t.tap(find.text('GPU'));
    await t.pump();
    expect(picked, ['GPU']);
  });
}
