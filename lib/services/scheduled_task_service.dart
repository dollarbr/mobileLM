import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import 'inference_android.dart' if (dart.library.html) 'inference_stub.dart'
    as platform;

const _schedulerChannel = MethodChannel('com.aichat.ai_chat/scheduler');

Future<void> _ensureBatteryExemption() async {
  try {
    if (!Platform.isAndroid) return;
    await _schedulerChannel.invokeMethod('ensureBatteryExemption');
  } catch (_) {}
}

/// A prompt the agent runs on a schedule, even with the app closed.
class ScheduledTask {
  final String id;
  final String name;
  final String prompt;

  /// Absolute path snapshotted at creation time — the background isolate
  /// resolves nothing, it just loads what it was handed.
  final String modelPath;
  final String? modelName;
  final int hour; // 0-23, device-local
  final int minute;

  /// How often the task runs. 'daily' runs once per day at hour:minute.
  /// 'hourly' runs at minute past every hour. 'every2h' / 'every4h' /
  /// 'every6h' / 'every8h' run every N hours at the given minute offset.
  final String frequency; // daily | hourly | every2h | every4h | every6h | every8h | once
  final bool keepModelLoaded; // keep engine alive between runs

  bool enabled;
  String? lastRunAt; // ISO8601 of the last completed attempt

  ScheduledTask({
    required this.id,
    required this.name,
    required this.prompt,
    required this.modelPath,
    this.modelName,
    required this.hour,
    required this.minute,
    this.frequency = 'daily',
    this.keepModelLoaded = false,
    this.enabled = true,
    this.lastRunAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'prompt': prompt,
        'modelPath': modelPath,
        if (modelName != null) 'modelName': modelName,
        'hour': hour,
        'minute': minute,
        'frequency': frequency,
        'keepModelLoaded': keepModelLoaded,
        'enabled': enabled,
        'lastRunAt': lastRunAt,
      };

  factory ScheduledTask.fromJson(Map<String, dynamic> j) => ScheduledTask(
        id: j['id'] as String,
        name: j['name'] as String,
        prompt: j['prompt'] as String,
        modelPath: j['modelPath'] as String,
        modelName: j['modelName'] as String?,
        hour: j['hour'] as int,
        minute: j['minute'] as int,
        frequency: j['frequency'] as String? ?? 'daily',
        keepModelLoaded: j['keepModelLoaded'] as bool? ?? false,
        enabled: j['enabled'] as bool? ?? true,
        lastRunAt: j['lastRunAt'] as String?,
      );

  /// Human-readable frequency label.
  String get frequencyLabel {
    switch (frequency) {
      case 'hourly':
        return 'Hourly';
      case 'every2h':
        return 'Every 2h';
      case 'every4h':
        return 'Every 4h';
      case 'every6h':
        return 'Every 6h';
      case 'every8h':
        return 'Every 8h';
      case 'once':
        return 'Just once';
      default:
        return 'Daily';
    }
  }

  /// How many minutes between runs. 'once' returns null to signal single-run.
  int? get intervalMinutes {
    switch (frequency) {
      case 'hourly':
        return 60;
      case 'every2h':
        return 120;
      case 'every4h':
        return 240;
      case 'every6h':
        return 360;
      case 'every8h':
        return 480;
      case 'once':
        return null; // single-run task
      default:
        return 1440; // daily
    }
  }
}

/// One finished (or failed) run, waiting to surface in the chat.
class ScheduledResult {
  final String id;
  final String taskId;
  final String taskName;
  final DateTime at;
  final String output;
  bool drained;

  ScheduledResult({
    required this.id,
    required this.taskId,
    required this.taskName,
    required this.at,
    required this.output,
    this.drained = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'taskId': taskId,
        'taskName': taskName,
        'at': at.toIso8601String(),
        'output': output,
        'drained': drained,
      };

  factory ScheduledResult.fromJson(Map<String, dynamic> j) => ScheduledResult(
        id: j['id'] as String,
        taskId: j['taskId'] as String,
        taskName: j['taskName'] as String,
        at: DateTime.parse(j['at'] as String),
        output: j['output'] as String,
        drained: j['drained'] as bool? ?? false,
      );
}

/// Due = next fire time has passed and the task has not run since it.
bool isTaskDue(ScheduledTask task, DateTime now) {
  if (!task.enabled) return false;
  if (task.frequency == 'daily') {
    final fireTime =
        DateTime(now.year, now.month, now.day, task.hour, task.minute);
    if (now.isBefore(fireTime)) return false;
    final last = task.lastRunAt;
    if (last != null && DateTime.parse(last).isAfter(fireTime)) return false;
    return true;
  }
  if (task.frequency == 'once') {
    // Single-run: due only once, at the specified time, and not yet run.
    final fireTime =
        DateTime(now.year, now.month, now.day, task.hour, task.minute);
    if (now.isBefore(fireTime)) return false;
    // If already run, never due again.
    final last = task.lastRunAt;
    if (last != null && DateTime.parse(last).isAfter(fireTime.subtract(const Duration(seconds: 1)))) return false;
    return true;
  }
  // Sub-daily: check if interval has elapsed since last run.
  final last = task.lastRunAt != null ? DateTime.parse(task.lastRunAt!) : null;
  final sinceLast = last == null
      ? Duration.zero
      : now.difference(last);
  return sinceLast.inMinutes >= (task.intervalMinutes ?? 1440);
}

// ── Storage ───────────────────────────────────────────────────────────────
// Plain JSON files so both isolates see the same truth without Hive setup.

Future<File> _tasksFile() async => File(
    '${(await getApplicationDocumentsDirectory()).path}/scheduled_tasks.json');

Future<File> _resultsFile() async => File(
    '${(await getApplicationDocumentsDirectory()).path}/scheduled_results.json');

Future<List<ScheduledTask>> readTasks() async {
  try {
    final raw = await (await _tasksFile()).readAsString();
    return (jsonDecode(raw) as List)
        .map((j) => ScheduledTask.fromJson(j as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
}

Future<void> writeTasks(List<ScheduledTask> tasks) async {
  await (await _tasksFile())
      .writeAsString(jsonEncode(tasks.map((t) => t.toJson()).toList()));
}

Future<List<ScheduledResult>> readResults({bool undrainedOnly = false}) async {
  try {
    final raw = await (await _resultsFile()).readAsString();
    return (jsonDecode(raw) as List)
        .map((j) => ScheduledResult.fromJson(j as Map<String, dynamic>))
        .where((r) => !undrainedOnly || !r.drained)
        .toList();
  } catch (_) {
    return [];
  }
}

Future<void> writeResults(List<ScheduledResult> results) async {
  await (await _resultsFile())
      .writeAsString(jsonEncode(results.map((r) => r.toJson()).toList()));
}

// ── Execution (runs in whatever isolate calls it) ────────────────────────

bool _runInProgress = false;

/// Loads the task's snapshot model fresh, runs the prompt, records the
/// output, notifies. Isolated from the main conversation by construction:
/// the run gets a brand-new engine and empty history.
Future<ScheduledResult> executeScheduledTask(ScheduledTask task) async {
  var output = '';
  try {
    final engine = platform.InferenceEngine();
    final load = await engine.loadModel(
      modelPath: task.modelPath,
      contextSize: AppConstants.defaultContextSize,
      deviceTier: 'medium',
      cpuThreads: 4,
      onProgress: (_) {},
    );
    if (!load.success) {
      throw Exception(load.message);
    }
    output = await engine.generate(
      prompt: task.prompt,
      systemPrompt: AppConstants.systemPrompt,
      modelName: task.modelName ?? task.modelPath.split('/').last,
      maxTokens: AppConstants.defaultMaxTokens,
      temperature: AppConstants.defaultTemperature,
    );
    await engine.dispose();
  } catch (e) {
    output = 'ERROR: $e';
  }
  return ScheduledResult(
    id: const Uuid().v4(),
    taskId: task.id,
    taskName: task.name,
    at: DateTime.now(),
    output: output,
  );
}

Future<void> notifyTaskResult(String name, String snippet) async {
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          'scheduled_tasks',
          'Scheduled tasks',
          description: 'Results from scheduled agent tasks',
          importance: Importance.high,
        ));
    await plugin.show(
      name.hashCode & 0x7fffffff,
      'mobileLM · $name',
      snippet.isEmpty ? '(empty response)' : snippet,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'scheduled_tasks',
          'Scheduled tasks',
          channelDescription: 'Results from scheduled agent tasks',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  } catch (_) {
    // Notifications are sugar; never fail a run over them.
  }
}

Future<void> notifyTaskScheduled(
  String name, {
  int hour = 0,
  int minute = 0,
  String frequency = 'daily',
  bool keepModelLoaded = false,
}) async {
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          'scheduled_tasks',
          'Scheduled tasks',
          description: 'Results from scheduled agent tasks',
          importance: Importance.high,
        ));
    final timeStr = '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
    final freqLabel = _frequencyLabel(frequency);
    final extra = keepModelLoaded ? ' · Model kept loaded' : '';
    final body = 'Running $freqLabel at $timeStr$extra';
    await plugin.show(
      (-name.hashCode) & 0x7fffffff,
      'mobileLM task scheduled · $name',
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'scheduled_tasks',
          'Scheduled tasks',
          channelDescription: 'Results from scheduled agent tasks',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  } catch (_) {
    // Notifications are sugar; never fail a run over them.
  }
}

String _frequencyLabel(String freq) {
  switch (freq) {
    case 'hourly':
      return 'hourly';
    case 'every2h':
      return 'every 2h';
    case 'every4h':
      return 'every 4h';
    case 'every6h':
      return 'every 6h';
    case 'every8h':
      return 'every 8h';
    case 'once':
      return 'once (single run)';
    default:
      return 'daily';
  }
}

/// Cancel a native WorkManager task by id. Standalone so it can be called
/// from both the main-isolate service and the background scheduler loop.
Future<void> _cancelTaskOnNative(String id) async {
  if (!Platform.isAndroid) return;
  try {
    await _schedulerChannel.invokeMethod('cancelTask', {'id': id});
  } catch (_) {}
}

/// Tick installed inside the shared background-service isolate. Every 30 s it
/// fires any enabled task whose daily moment has arrived. The foreground
/// notification keeps Android from reaping us mid-generation.
void startSchedulerLoop(ServiceInstance service) {
  Timer.periodic(const Duration(seconds: 30), (_) async {
    if (_runInProgress) return;
    try {
      final now = DateTime.now();
      final tasks = await readTasks();
      var changed = false;
      for (final task in tasks) {
        if (!isTaskDue(task, now)) continue;
        _runInProgress = true;
        task.lastRunAt = now.toIso8601String();
        changed = true;
        try {
          final result = await executeScheduledTask(task);
          final all = await readResults();
          all.add(result);
          await writeResults(all);
          await notifyTaskResult(task.name,
              result.output.length > 120 ? result.output.substring(0, 120) : result.output);
          // One-time tasks self-delete after running.
          if (task.frequency == 'once') {
            tasks.removeWhere((t) => t.id == task.id);
            await writeTasks(tasks);
            await _cancelTaskOnNative(task.id);
          }
        } finally {
          _runInProgress = false;
        }
      }
      // ponytail: timer-based foreground service instead of WorkManager — a
      // permanent low-key notification is the cost; move firing to WorkManager
      // if that notification ever bothers anyone.
      if (changed) await writeTasks(tasks);
    } catch (_) {
      // A broken tick must never kill the timer.
    }
  });
}

// ── Main-isolate facade ───────────────────────────────────────────────────

class ScheduledTaskService extends GetxService {
  final tasks = <ScheduledTask>[].obs;

  Future<void> init() async {
    tasks.assignAll(await readTasks());
  }

  Future<ScheduledTask> add({
    required String name,
    required String prompt,
    required String modelPath,
    String? modelName,
    required int hour,
    required int minute,
    String frequency = 'daily',
    bool keepModelLoaded = false,
  }) async {
    final task = ScheduledTask(
      id: const Uuid().v4(),
      name: name,
      prompt: prompt,
      modelPath: modelPath,
      modelName: modelName,
      hour: hour,
      minute: minute,
      frequency: frequency,
      keepModelLoaded: keepModelLoaded,
    );
    tasks.add(task);
    await writeTasks(tasks);
    await _syncServiceState();
    unawaited(_scheduleOnNative(task));
    unawaited(notifyTaskScheduled(
      task.name,
      hour: task.hour,
      minute: task.minute,
      frequency: task.frequency,
      keepModelLoaded: task.keepModelLoaded,
    ));
    return task;
  }

  Future<void> remove(String id) async {
    tasks.removeWhere((t) => t.id == id);
    await writeTasks(tasks);
    await _cancelOnNative(id);
    await _syncServiceState();
  }

  Future<ScheduledTask?> update(ScheduledTask updated) async {
    final idx = tasks.indexWhere((t) => t.id == updated.id);
    if (idx < 0) return null;
    tasks[idx] = updated;
    await writeTasks(tasks);
    // Reschedule with new params.
    await _cancelOnNative(updated.id);
    unawaited(_scheduleOnNative(updated));
    await _syncServiceState();
    return updated;
  }

  Future<void> setEnabled(ScheduledTask task, bool enabled) async {
    task.enabled = enabled;
    await writeTasks(tasks);
    if (!enabled) {
      await _cancelOnNative(task.id);
    } else {
      unawaited(_scheduleOnNative(task));
    }
    await _syncServiceState();
  }

  Future<List<ScheduledResult>> drainResults() async {
    final all = await readResults();
    final fresh = all.where((r) => !r.drained).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    if (fresh.isNotEmpty) {
      for (final r in all) {
        r.drained = true;
      }
      await writeResults(all);
    }
    return fresh;
  }

  /// The background service is shared with image generation, so it is only
  /// stopped here when no tasks remain — an SD render in flight wins.
  Future<void> _syncServiceState() async {
    if (!Platform.isAndroid) return;
    final service = FlutterBackgroundService();
    if (tasks.any((t) => t.enabled)) {
      if (!await service.isRunning()) await service.startService();
    } else {
      service.invoke('stopService');
    }
  }

  Future<void> _scheduleOnNative(ScheduledTask task) async {
    if (!Platform.isAndroid) return;
    try {
      await _ensureBatteryExemption();
      await _schedulerChannel.invokeMethod('scheduleTask', {
        'id': task.id,
        'name': task.name,
        'prompt': task.prompt,
        'modelPath': task.modelPath,
        'modelName': task.modelName,
        'hour': task.hour,
        'minute': task.minute,
        'frequency': task.frequency,
        'keepModelLoaded': task.keepModelLoaded,
      });
    } catch (_) {}
  }

  Future<void> _cancelOnNative(String id) async {
    if (!Platform.isAndroid) return;
    try {
      await _schedulerChannel.invokeMethod('cancelTask', {'id': id});
    } catch (_) {}
  }
}
