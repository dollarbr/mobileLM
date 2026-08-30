import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:light_sensor/light_sensor.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:share_plus/share_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../download_service.dart';
import '../inference_service.dart';
import '../scheduled_task_service.dart';
import '../workspace_service.dart';
import 'calculator.dart';
import 'tool_registry.dart';
import 'web_tools.dart';

// Singleton accessor instances to avoid repeated instantiation.
final _battery = Battery();
final _screenBrightness = ScreenBrightness();
final _wifi = NetworkInfo();
final _lightSensor = LightSensor();

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
  List<Tool> extra = const [],
}) =>
    ToolRegistry([
      ..._coreTools(enabled, customSearchUrl, customSearchToken),
      ...extra,
    ].where((t) => enabled == null || enabled.contains(t.name)));

List<Tool> _coreTools(
  Set<String>? enabled,
  String customSearchUrl,
  String customSearchToken,
) =>
    [
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
        name: 'battery_status',
        description: "Report the device's current battery level (0–100) and "
            'charging state (charging, discharging, full, not_charging).',
        run: (_) async {
          final battery = _battery;
          try {
            final level = await battery.batteryLevel;
            final state = await battery.batteryState;
            final stateLabel = switch (state) {
              BatteryState.charging => 'charging',
              BatteryState.discharging => 'discharging',
              BatteryState.full => 'full',
              BatteryState.connectedNotCharging => 'connected_not_charging',
              _ => 'unknown',
            };
            return 'Battery: ${level}% — $stateLabel';
          } catch (e) {
            return 'Error reading battery: $e';
          }
        },
      ),
      Tool(
        name: 'screen_brightness',
        description: 'Report the current system screen brightness as a "0.0–1.0" '
            'value; 1.0 is full brightness.',
        run: (_) async {
          try {
            final brightness = await _screenBrightness.system;
            return 'Screen brightness: ${(brightness * 100).toStringAsFixed(0)}% '
                '(${brightness.toStringAsFixed(2)} of 1.0)';
          } catch (e) {
            return 'Error reading brightness: $e';
          }
        },
      ),
      Tool(
        name: 'wifi_status',
        description: 'Report whether Wi-Fi is enabled and, if connected, the SSID '
            'and IP address. Needs location permission on Android 8+.',
        run: (_) async {
          try {
            final ssid = await _wifi.getWifiName();
            final ip = await _wifi.getWifiIP();
            if (ssid == null && ip == null) {
              return 'Wi-Fi is disabled or not connected.';
            }
            return 'Wi-Fi connected — SSID: ${ssid ?? "?"}, IP: ${ip ?? "?"}';
          } catch (e) {
            return 'Error reading Wi-Fi status: $e';
          }
        },
      ),
      Tool(
        name: 'ambient_light',
        description: 'Report the current ambient light level in lux using the '
            'device light sensor (returns 0 if unavailable).',
        run: (_) async {
          try {
            final hasSensor = await LightSensor.hasSensor();
            if (!hasSensor) return 'No light sensor on this device.';
            final lux = await LightSensor.luxStream().firstWhere(
              (v) => v > 0,
              orElse: () => 0,
            );
            return 'Ambient light: $lux lux';
          } catch (e) {
            return 'Ambient light sensor unavailable: $e';
          }
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
          'model': 'filename of a downloaded local model to use',
          'hour': '0-23',
          'minute': '0-59',
        },
        risk: ToolRisk.write,
        run: (args) async {
          final name = args['name']?.trim();
          final prompt = args['prompt']?.trim();
          final model = args['model']?.trim();
          final hour = int.tryParse(args['hour'] ?? '');
          final minute = int.tryParse(args['minute'] ?? '');
          if (name == null || prompt == null || hour == null || minute == null) {
            return 'Error: need name, prompt, hour and minute.';
          }
          if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
            return 'Error: hour must be 0-23 and minute 0-59.';
          }
          final download = Get.find<DownloadService>();
          String modelPath;
          String modelName;
          if (model != null && model.isNotEmpty) {
            if (!await download.isModelDownloaded(model)) {
              return 'Error: model "$model" is not downloaded.';
            }
            modelName = model;
            modelPath = await download.modelPath(model);
          } else {
            final inference = Get.find<InferenceService>();
            modelName = inference.loadedModelName.value;
            if (modelName.isEmpty) {
              return 'Error: no local model loaded — load one first or pass model.';
            }
            modelPath = await download.modelPath(modelName);
          }
          final task = await Get.find<ScheduledTaskService>().add(
            name: name,
            prompt: prompt,
            modelPath: modelPath,
            modelName: modelName,
            hour: hour,
            minute: minute,
          );
          return 'Scheduled "${task.name}" daily at '
              '${hour.toString().padLeft(2, '0')}:'
              '${minute.toString().padLeft(2, '0')} using ${task.modelName ?? "the active model"}';
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
                  '${t.minute.toString().padLeft(2, '0')}'
                  '${t.modelName == null ? "" : " · ${t.modelName}"}'
                  ' — ${t.enabled ? 'enabled' : 'disabled'}')
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
    ];

/// File tools scoped to the active chat's project folder. The [projectPath]
/// callback reads the currently open project (null when the chat has none), so
/// the model can only ever touch files inside it — never the whole workspace.
///
/// Members become write-class ([ToolRisk.write]) so a human confirms deletions,
/// overwrites and renames; pure reads auto-run. All paths are relative to the
/// project folder.
List<Tool> buildFileTools({
  required String? Function() projectPath,
}) {
  WorkspaceService ws() => Get.find<WorkspaceService>();

  // Merges a project-relative path onto the active project folder. Returns
  // null (=> an error the model can relay) when there is no project open.
  String? resolve(String relative) {
    final base = projectPath();
    if (base == null || base.isEmpty) return null;
    var rel = relative.trim();
    if (rel.startsWith('/')) rel = rel.substring(1);
    if (rel.isEmpty) return base;
    return '$base/$rel';
  }

  String notReady() =>
      'Error: no project folder is open in this chat. Start a chat in a '
      'project (or bind this chat to one) before using file tools.';

  return [
    Tool(
      name: 'list_files',
      description: 'List the files and folders in the current project. Reads '
          'are safe to run without asking.',
      parameters: {'path': 'subfolder to list; omit to list the project root'},
      run: (args) async {
        final full = resolve(args['path'] ?? '');
        if (full == null) return notReady();
        final entries = await ws().listDir(full);
        if (entries.isEmpty) return 'The folder is empty.';
        return entries
            .map((e) => '${e.isDir ? '[dir]  ' : '[file] '}${e.name}'
                '${e.isDir ? '' : ' (${e.size} bytes)'}')
            .join('\n');
      },
    ),
    Tool(
      name: 'read_file',
      description: 'Return the text contents of a file in the current project.',
      parameters: {'path': 'file path, relative to the project root'},
      run: (args) async {
        final full = resolve(args['path'] ?? '');
        if (full == null) return notReady();
        final content = await ws().readFile(full);
        if (content == null) return 'Error: could not read that file.';
        const maxChar = 4000;
        if (content.length > maxChar) {
          return '${content.substring(0, maxChar)}\n…(truncated, '
              '${content.length} characters total)';
        }
        return content;
      },
    ),
    Tool(
      name: 'create_file',
      description: 'Create a new empty file in the current project. Fails if '
          'a file with that name already exists.',
      parameters: {
        'path': 'new file path, relative to the project root',
        'content': 'initial contents (optional)',
      },
       risk: ToolRisk.write,
       run: (args) async {
         final full = resolve(args['path'] ?? '');
         if (full == null) return notReady();
         final existing = await ws().readFile(full);
         if (existing != null) {
           return 'Error: ${args['path']} already exists. Use write_file to '
               'overwrite it.';
         }
         final err = await ws().writeFile(full, args['content'] ?? '');
         return err == null
             ? 'Created ${args['path']}.'
             : 'Error: $err';
       },
     ),
     Tool(
       name: 'write_file',
       description: 'Overwrite a file in the current project with new text, '
           'creating it (and any folders) if missing. Asks the user first.',
       parameters: {
         'path': 'file path, relative to the project root',
         'content': 'the full new contents of the file',
       },
       risk: ToolRisk.write,
       run: (args) async {
         final full = resolve(args['path'] ?? '');
         if (full == null) return notReady();
         final err = await ws().writeFile(full, args['content'] ?? '');
         return err == null ? 'Wrote ${args['path']}.' : 'Error: $err';
      },
    ),
    Tool(
      name: 'delete_file',
      description: 'Delete a file (or empty folder) in the current project. '
          'Asks the user first.',
      parameters: {'path': 'file path, relative to the project root'},
      risk: ToolRisk.write,
      run: (args) async {
        final full = resolve(args['path'] ?? '');
        if (full == null) return notReady();
        final ok = await ws().deleteItem(full);
        return ok ? 'Deleted ${args['path']}.' : 'Error: could not delete it.';
      },
    ),
    Tool(
      name: 'rename_file',
      description: 'Rename a file or folder in the current project. Asks the '
          'user first.',
      parameters: {
        'path': 'current path, relative to the project root',
        'new_name': 'new name for the item (a bare name, not a path)',
      },
      risk: ToolRisk.write,
      run: (args) async {
        final full = resolve(args['path'] ?? '');
        if (full == null) return notReady();
        final newName = (args['new_name'] ?? '').trim();
        if (newName.isEmpty || newName.contains('/')) {
          return 'Error: new_name must be a bare file/folder name.';
        }
        final ok = await ws().renameItem(full, newName);
        return ok ? 'Renamed to $newName.' : 'Error: could not rename it.';
      },
    ),
  ];
}

/// Camera tool scoped to the active chat's project folder. Like the file tools
/// it needs a project path, so it is built alongside [buildFileTools] in the
/// chat controller rather than in [buildDefaultToolRegistry].
List<Tool> buildPhotoTools({
  required String? Function() projectPath,
}) {
  WorkspaceService ws() => Get.find<WorkspaceService>();

  String notReady() =>
      'Error: no project folder is open. Open one before taking a photo.';

  return [
    Tool(
      name: 'take_photo',
      description: 'Take a photo with the device camera and save it to the '
          "current project folder. Asks the user first. Returns the file path.",
      risk: ToolRisk.write,
      run: (args) async {
        final picker = ImagePicker();
        final result = await picker.pickImage(source: ImageSource.camera);
        if (result == null) return 'No photo taken.';
        final bytes = await result.readAsBytes();
        final path = projectPath();
        if (path == null || path.isEmpty) return notReady();
        final imgDecoded = img.decodeImage(bytes);
        if (imgDecoded == null) return 'Error: could not decode image.';
        final now = DateTime.now();
        final name = 'photo_${now.millisecondsSinceEpoch}.jpg';
        final full = '$path/$name';
        final err = await ws().writeFile(full, String.fromCharCodes(bytes));
        return err == null
            ? 'Photo saved to $name (${imgDecoded.width}×${imgDecoded.height}).'
            : 'Error saving photo: $err';
      },
    ),
  ];
}