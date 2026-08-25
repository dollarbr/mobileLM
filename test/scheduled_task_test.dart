import 'package:flutter_test/flutter_test.dart';
import 'package:privatelm/services/scheduled_task_service.dart';

void main() {
  final model = '/tmp/model.gguf';

  ScheduledTask task({
    int hour = 8,
    int minute = 0,
    bool enabled = true,
    String? lastRunAt,
  }) =>
      ScheduledTask(
        id: 't1',
        name: 'Digest',
        prompt: 'summarize',
        modelPath: model,
        hour: hour,
        minute: minute,
        enabled: enabled,
        lastRunAt: lastRunAt,
      );

  test('not due before the fire time', () {
    final now = DateTime(2026, 8, 25, 7, 59);
    expect(isTaskDue(task(), now), isFalse);
  });

  test('due right at and after the fire time', () {
    expect(isTaskDue(task(), DateTime(2026, 8, 25, 8, 0)), isTrue);
    expect(isTaskDue(task(), DateTime(2026, 8, 25, 22, 30)), isTrue);
  });

  test('already ran today after fire time -> not due', () {
    final ran = DateTime(2026, 8, 25, 8, 0, 5);
    expect(
      isTaskDue(task(lastRunAt: ran.toIso8601String()),
          DateTime(2026, 8, 25, 9, 0)),
      isFalse,
    );
  });

  test('ran yesterday -> due again today', () {
    final yesterday = DateTime(2026, 8, 24, 8, 1);
    expect(
      isTaskDue(task(lastRunAt: yesterday.toIso8601String()),
          DateTime(2026, 8, 25, 8, 0)),
      isTrue,
    );
  });

  test('disabled never fires', () {
    final now = DateTime(2026, 8, 25, 9, 0);
    expect(isTaskDue(task(enabled: false), now), isFalse);
  });

  test('task json round-trips', () {
    final t = ScheduledTask(
      id: 'x',
      name: 'N',
      prompt: 'P',
      modelPath: model,
      hour: 23,
      minute: 59,
      enabled: false,
      lastRunAt: '2026-08-25T08:00:00.000',
    );
    final back = ScheduledTask.fromJson(t.toJson());
    expect(back.id, 'x');
    expect(back.hour, 23);
    expect(back.enabled, isFalse);
    expect(back.lastRunAt, '2026-08-25T08:00:00.000');
  });
}
