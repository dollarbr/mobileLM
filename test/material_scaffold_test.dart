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
}
