import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../download_service.dart';
import '../inference_service.dart';
import '../scheduled_task_service.dart';
import 'calculator.dart';
import 'tool_registry.dart';
import 'web_tools.dart';

/// Every tool the app can offer, offline ones first.
///
/// The offline three answer what a language model genuinely cannot know or
/// reliably compute: the wall clock, arithmetic, and the hardware it runs on.
/// The device pair (clipboard, haptics) and the share sheet stay permission-
/// free; write-class tools ([ToolRisk.write]) pause for user confirmation.
/// The two network tools are listed here too but each one is individually
/// switchable in Settings. Tools needing a runtime permission
/// (location, contacts, camera) are still not wired up.
///
/// [enabled] filters by name; null means every tool. Pass the user's selection
/// so the prompt advertises exactly what will actually run — a model told about
/// a tool that then refuses to run wastes a turn arguing with itself.
ToolRegistry buildDefaultToolRegistry({
  Set<String>? enabled,
  String customSearchUrl = '',
  String customSearchToken = '',
}) =>
    ToolRegistry([
      Tool(
        name: 'get_datetime',
        description: "The device's current date and time, with its time zone.",
        run: (_) async {
          final now = DateTime.now();
          return '${DateFormat('EEEE, d MMMM y, HH:mm:ss').format(now)} '
              '(${now.timeZoneName}, UTC${now.timeZoneOffset.isNegative ? '-' : '+'}'
              '${now.timeZoneOffset.inHours.abs().toString().padLeft(2, '0')}:'
              '${(now.timeZoneOffset.inMinutes.abs() % 60).toString().padLeft(2, '0')})';
        },
      ),
      Tool(
        name: 'calculate',
        description: 'Evaluate an arithmetic expression, e.g. (12.5 * 3) / 2.',
        parameters: {'expression': 'the expression to evaluate'},
        run: (args) {
          final expression = args['expression'] ?? '';
          if (expression.trim().isEmpty) {
            return 'Error: no expression given.';
          }
          final value = Calculator.evaluate(expression);
          return value == null
              ? 'Error: "$expression" is not an expression I can evaluate.'
              : Calculator.format(value);
        },
      ),
      Tool(
        name: 'get_device_info',
        description: 'Model, manufacturer, OS version and SoC of this device.',
        run: (_) async {
          final plugin = DeviceInfoPlugin();
          if (Platform.isAndroid) {
            final a = await plugin.androidInfo;
            return '${a.manufacturer} ${a.model} — Android ${a.version.release} '
                '(API ${a.version.sdkInt}), SoC ${a.hardware}, '
                '${a.supportedAbis.join("/")}';
          }
          if (Platform.isIOS) {
            final i = await plugin.iosInfo;
            return '${i.name} ${i.model} — ${i.systemName} ${i.systemVersion}';
          }
          return 'Unknown platform: ${Platform.operatingSystem}';
        },
      ),
      Tool(
        name: 'web_search',
        description: 'Search the live web for current information — news, '
            'prices, weather, anything past the training cutoff. Returns titles, '
            'URLs and snippets; call read_url on a result for the full page.',
        parameters: {'query': 'what to search for'},
        requiresNetwork: true,
        run: (args) => webSearch(
          args['query'] ?? '',
          customSearchUrl: customSearchUrl,
          customSearchToken: customSearchToken,
        ),
      ),
      Tool(
        name: 'read_url',
        description: 'Fetch a web page and return its readable text. Use after '
            'web_search, or when the user shares a link.',
        parameters: {'url': 'full http(s) URL'},
        requiresNetwork: true,
        run: (args) => readUrl(args['url'] ?? ''),
      ),
      Tool(
        name: 'clipboard_read',
        description: "Read the device's current clipboard text.",
        run: (_) async =>
            (await Clipboard.getData('text/plain'))?.text ??
            'The clipboard is empty or holds no text.',
      ),
      Tool(
        name: 'clipboard_write',
        description: 'Replace the clipboard text. Asks the user first.',
        parameters: {'text': 'the text to put on the clipboard'},
        risk: ToolRisk.write,
        run: (args) async {
          final text = args['text'];
          if (text == null || text.isEmpty) return 'Error: no text given.';
          await Clipboard.setData(ClipboardData(text: text));
          return 'Clipboard set.';
        },
      ),
      Tool(
        name: 'vibrate',
        description: 'Give the device a short haptic buzz.',
        run: (_) async {
          await HapticFeedback.heavyImpact();
          return 'Buzzed.';
        },
      ),
      Tool(
        name: 'share_text',
        description: "Open Android's share sheet so the user can send text "
            'to another app. The user picks the destination.',
        parameters: {'text': 'what to share'},
        run: (args) async {
          final text = args['text'];
          if (text == null || text.isEmpty) return 'Error: no text given.';
          await Share.share(text);
          return 'Share sheet opened.';
        },
      ),
      Tool(
        name: 'schedule_task',
        description:
            'Schedule a daily prompt this assistant runs by itself at a fixed '
            'local time, even with the app closed. The result appears in the '
            'chat afterwards. Asks the user first.',
        parameters: {
          'name': 'short label, e.g. "Morning digest"',
          'prompt': 'the instruction to run every day',
          'hour': '0-23',
          'minute': '0-59',
        },
        risk: ToolRisk.write,
        run: (args) async {
          final name = args['name']?.trim();
          final prompt = args['prompt']?.trim();
          final hour = int.tryParse(args['hour'] ?? '');
          final minute = int.tryParse(args['minute'] ?? '');
          if (name == null || prompt == null || hour == null || minute == null) {
            return 'Error: need name, prompt, hour and minute.';
          }
          if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
            return 'Error: hour must be 0-23 and minute 0-59.';
          }
          final inference = Get.find<InferenceService>();
          final modelName = inference.loadedModelName.value;
          if (modelName.isEmpty) {
            return 'Error: no local model loaded — load one first.';
          }
          final modelPath =
              await Get.find<DownloadService>().modelPath(modelName);
          final task = await Get.find<ScheduledTaskService>().add(
            name: name,
            prompt: prompt,
            modelPath: modelPath,
            hour: hour,
            minute: minute,
          );
          return 'Scheduled "${task.name}" daily at '
              '${hour.toString().padLeft(2, '0')}:'
              '${minute.toString().padLeft(2, '0')}.';
        },
      ),
      Tool(
        name: 'list_scheduled_tasks',
        description: 'List the daily tasks scheduled to run on their own.',
        run: (_) async {
          final tasks = Get.find<ScheduledTaskService>().tasks;
          if (tasks.isEmpty) return 'No scheduled tasks.';
          return tasks
              .map((t) =>
                  '${t.name} — daily ${t.hour.toString().padLeft(2, '0')}:'
                  '${t.minute.toString().padLeft(2, '0')} — '
                  '${t.enabled ? 'enabled' : 'disabled'}')
              .join('\n');
        },
      ),
      Tool(
        name: 'cancel_scheduled_task',
        description:
            'Cancel one scheduled daily task by its exact name. Asks the user first.',
        parameters: {'name': 'exact task name to cancel'},
        risk: ToolRisk.write,
        run: (args) async {
          final name = args['name']?.trim();
          if (name == null || name.isEmpty) return 'Error: no name given.';
          final service = Get.find<ScheduledTaskService>();
          final match = service.tasks.firstWhereOrNull(
            (t) => t.name.toLowerCase() == name.toLowerCase(),
          );
          if (match == null) return 'Error: no task named "$name".';
          await service.remove(match.id);
          return 'Cancelled "${match.name}".';
        },
      ),
    ].where((t) => enabled == null || enabled.contains(t.name)));
