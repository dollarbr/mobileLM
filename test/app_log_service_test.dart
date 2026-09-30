// The log service writes an RxList, and something that is very easy to trigger
// writes to it *during a widget build*. That used to throw, and the trace is
// worth keeping because the symptom pointed somewhere else entirely.
//
// Measured on the Galaxy A72, 0.4.0, from app.log rather than inferred:
//
//   ChatController.onInit (chat_controller.dart:161)
//     -> refreshEncoderRole (:253)
//       -> AppLogService.info -> _add -> _push
//         -> RxList.insert -> RxObjectMixin.refresh
//           -> GetStream._notifyData -> ObxState._updateTree -> setState
//
// "setState() or markNeedsBuild() called during build ... The widget which was
// currently being built when the offending call was made was: ChatView".
//
// GetX does not swallow that. It reaches the zone as an uncaught error, the Obx
// is left holding a dirty element, and the subtree under it does not come back.
// The user-visible consequence was not a crash: the tap that opened Settings
// was swallowed and the Logs screen opened instead, which is the kind of thing
// that gets filed as a navigation bug and debugged for a long time.
//
// The writer is the thing that was wrong, not the watcher, so the test drives
// the writer. It reproduces the shape that actually happened — a log call made
// from inside a build, the way a GetX controller does when something does
// `Get.find<ChatController>()` in a build method and its `onInit` logs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mobilelm/services/app_log_service.dart';

void main() {
  testWidgets(
      'a log line written during a build does not take down the Obx watching it',
      (tester) async {
    // No teardown: the two timers in the service are started by onInit, which a
    // unit test has no reason to call, and a teardown that called a method the
    // class does not have is how a test starts failing for the wrong reason.
    final log = AppLogService();

    await tester.pumpWidget(
      MaterialApp(
        home: Obx(() {
          final n = log.entries.length;
          // Written from inside the build, once. This is the whole point: a
          // GetX controller reached by `Get.find` from a build runs `onInit`
          // inside that build, and `onInit` logs.
          if (n == 0) log.info('written during build');
          return Text('entries: $n', textDirection: TextDirection.ltr);
        }),
      ),
    );

    // pump() rethrows anything the framework reported, so reaching the next
    // line at all is half the assertion. The other half is that the line
    // actually arrived — a fix that dropped the entry would pass the above.
    await tester.pump();
    await tester.pump();

    expect(log.entries.length, 1, reason: 'the line must still be recorded');
    expect(log.entries.first.message, 'written during build');
    expect(find.text('entries: 1'), findsOneWidget);
  });

  testWidgets('a log line written outside a build is recorded immediately',
      (tester) async {
    // The deferral above is conditional, and a conditional that always fires is
    // a log that lags behind everything. Outside a build the write stays
    // synchronous, because that is what the poller and the channel callbacks
    // rely on — the ggml ring buffer is drained on a timer and read right after.
    // No teardown: the two timers in the service are started by onInit, which a
    // unit test has no reason to call, and a teardown that called a method the
    // class does not have is how a test starts failing for the wrong reason.
    final log = AppLogService();

    await tester.pumpWidget(const MaterialApp(home: Text('idle')));
    log.info('from a timer');
    expect(log.entries.length, 1);
    expect(log.entries.first.message, 'from a timer');
  });

  testWidgets('writes from several builds in one frame all land, none dropped',
      (tester) async {
    // addPostFrameCallback per entry is not a queue: three writes in the same
    // frame register three callbacks, and the order they run in is the order
    // they were queued. `insert(0, …)` means the newest is first, so the
    // sequence has to come out reversed — this is the assertion that would fail
    // if the deferral ever turned into a single "flush what changed" that
    // collapsed several lines into one.
    // No teardown: the two timers in the service are started by onInit, which a
    // unit test has no reason to call, and a teardown that called a method the
    // class does not have is how a test starts failing for the wrong reason.
    final log = AppLogService();

    await tester.pumpWidget(
      MaterialApp(
        home: Obx(() {
          final n = log.entries.length;
          if (n == 0) {
            log.info('first');
            log.warning('second');
            log.error('third');
          }
          return Text('$n', textDirection: TextDirection.ltr);
        }),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(log.entries.length, 3);
    expect(log.entries.map((e) => e.message).toList(),
        ['third', 'second', 'first']);
  });
}
