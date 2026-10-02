import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
// import 'firebase_options.dart';
import 'controllers/settings_controller.dart';
import 'services/language_preference.dart';
import 'controllers/cloud_model_controller.dart';
import 'controllers/server_controller.dart';
import 'controllers/model_controller.dart';
import 'core/theme.dart';
//////
import 'core/routes.dart';
import 'services/hive_service.dart';
import 'services/inference_service.dart';
import 'services/cloud_service.dart';
import 'services/download_service.dart';
import 'services/device_info_service.dart';
import 'services/litert_service.dart';
import 'services/local_image_service.dart';
import 'services/app_log_service.dart';
import 'services/encoder_settings_service.dart';
import 'services/cpu_self_test_service.dart';
import 'services/crash_reporting_service.dart';
import 'services/image_generation_notification_service.dart';
import 'services/scheduled_task_service.dart';
import 'services/workspace_service.dart';
import 'services/privileged_service.dart';
import 'core/constants.dart';
import 'l10n/app_translation.dart';

void main() {
  final appLogBuffer = <String>[];

  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Register logger first so everything routes to it
    final appLog = AppLogService();
    Get.put(appLog);

    // Flush buffered prints
    for (final line in appLogBuffer) {
      appLog.info(line);
    }
    appLogBuffer.clear();

    appLog.info('app_started'.tr);
    // Once, at startup, where it belongs. The pt_BR-only translation map and the
    // pt_BR fallback mean this is not a detail — an English device silently
    // renders every untranslated `.tr` key as its own name — but it is a fact
    // about the device, not about the widget tree.
    appLog.info('[Intl] deviceLocale=${Get.deviceLocale}');

    // Initialize Firebase before any Firebase-dependent services
    try {
      // await Firebase.initializeApp(
      //   options: DefaultFirebaseOptions.currentPlatform,
      // );
    } catch (e) {
      appLog.error('[firebase] Initialization failed'.tr, details: e);
    }

    // Support phones and tablets in portrait or landscape.
    if (!kIsWeb) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    // Initialize Hive
    await Hive.initFlutter();

    // Register global services
    await Get.putAsync(() => HiveService().init());
    await Get.putAsync(() => DeviceInfoService().init());

    // Settings controller must be initialized before runApp for theme support
    final settingsController = Get.put(SettingsController());

    Get.put(CloudModelController());

    Get.put(InferenceService());
    Get.put(CloudService());
    Get.put(DownloadService());
    Get.put(LocalImageService());
    // Registered with Get.put and not lazily: `/v1/litert/*` resolves it with
    // Get.find, and a lazy registration would make the first HTTP request the
    // thing that decides whether the service exists. It costs nothing to hold
    // — the 8,7 MB of LiteRT natives are in the APK whatever we do, and the
    // Environment handle is the only live object and is not created until
    // something asks what the device can do.
    Get.put(LitertService());
    final crashReporting =
        await Get.putAsync(() => CrashReportingService().init());
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      appLog.error(
        details.exceptionAsString(),
        details: details.stack?.toString() ?? 'no_stack'.tr,
      );
      crashReporting.recordFlutterFatal(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      appLog.error(
        error.toString(),
        details: stack.toString(),
      );
      crashReporting.recordFatal(error, stack, reason: 'platform_dispatcher');
      return true;
    };
    final imageNotifications = Get.put(ImageGenerationNotificationService());
    final scheduledTasks = Get.put(ScheduledTaskService());
    await scheduledTasks.init();
    await imageNotifications.init();
    await imageNotifications.configureBackgroundService();
    Get.put(ServerController(), permanent: true);
    // Registered before ModelController, which reads nothing from it, but before
    // the API server can serve a request — the handlers look it up per request
    // and an unregistered service would be a 500 with a null lookup rather than
    // a default.
    Get.put(EncoderSettingsService(), permanent: true);
    // After ModelController, not before: the self-test resolves the benchmark
    // model out of the catalogue it publishes, and registering earlier would
    // read an empty list.
    Get.put(CpuSelfTestService(), permanent: true);
    Get.put(ModelController());
    final workspace = Get.put(WorkspaceService());
    await workspace.initialize();
    // Probed once at boot; the Settings card re-checks on demand. A missing
    // Shizuku is the normal case, not an error.
    await Get.put(PrivilegedService()).refresh();

    // Auto-configure inference settings based on device RAM
    _autoConfigureForDevice();

    // Keep last model as a quick-load option, but do not auto-load on startup.
    _validateLastModel();

    runApp(const MobileLMApp());

    // Apply system UI after frame is rendered so Get.mediaQuery is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      settingsController.setThemeMode(settingsController.themeMode.value);
    });
  }, (error, stack) async {
    if (Get.isRegistered<AppLogService>()) {
      Get.find<AppLogService>().error(
        'Uncaught zone error: $error',
        details: stack.toString(),
      );
    }
    if (Get.isRegistered<CrashReportingService>()) {
      await Get.find<CrashReportingService>()
          .recordFatal(error, stack, reason: 'run_zoned_guarded');
    }
  }, zoneSpecification: ZoneSpecification(
    print: (self, parent, zone, line) {
      if (Get.isRegistered<AppLogService>()) {
        Get.find<AppLogService>().info(line);
      } else {
        appLogBuffer.add(line);
      }
      parent.print(zone, line);
    },
  ));
}

/// Validates that remembered models still exist on disk.
/// Does NOT auto-load — the HomeView will ask the user on first launch.
void _validateLastModel() async {
  final hive = Get.find<HiveService>();
  final downloadService = Get.find<DownloadService>();

  // Validate last text/LLM model
  final textModelName = hive.getSetting<String>(AppConstants.keyLocalModelName);
  final textModelPath = hive.getSetting<String>(AppConstants.keyLocalModelPath);
  if (textModelName != null &&
      textModelName.isNotEmpty &&
      textModelPath != null &&
      textModelPath.isNotEmpty) {
    if (!await downloadService.isModelDownloaded(textModelName)) {
      await hive.setSetting(AppConstants.keyLocalModelPath, '');
      await hive.setSetting(AppConstants.keyLocalModelName, '');
    }
  }

  // Validate last image model
  final imageModelName =
      hive.getSetting<String>(AppConstants.keyImageModelName);
  final imageModelPath =
      hive.getSetting<String>(AppConstants.keyImageModelPath);
  if (imageModelName != null &&
      imageModelName.isNotEmpty &&
      imageModelPath != null &&
      imageModelPath.isNotEmpty) {
    if (!await downloadService.isModelDownloaded(imageModelName)) {
      await hive.setSetting(AppConstants.keyImageModelPath, '');
      await hive.setSetting(AppConstants.keyImageModelName, '');
    }
  }
}

/// Auto-set optimized inference params based on device RAM (only on first launch).
void _autoConfigureForDevice() {
  final hive = Get.find<HiveService>();
  final device = Get.find<DeviceInfoService>();

  // Only auto-configure if user hasn't already set values (first launch)
  final hasConfigured =
      hive.getSetting<bool>('device_auto_configured') ?? false;
  if (hasConfigured) return;

  hive.setSetting(AppConstants.keyContextSize, device.recommendedContextSize);
  hive.setSetting(AppConstants.keyMaxTokens, device.recommendedMaxTokens);
  hive.setSetting(AppConstants.keyTemperature, 0.3);
  hive.setSetting('device_auto_configured', true);

  Get.find<AppLogService>().info(
      '[AutoConfig] Set context=${device.recommendedContextSize}, '
      'maxTokens=${device.recommendedMaxTokens} for ${device.totalRamGB.value.toStringAsFixed(1)}GB RAM');
}

class MobileLMApp extends StatelessWidget {
  const MobileLMApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Get.find<SettingsController>();
    return Obx(() {
      final themeMode = settings.themeMode.value;
      final scale = settings.fontScale.value; // read here → Obx tracks it
      // No print here. This line is inside the root Obx's build, so it runs on
      // every rebuild of the entire app — and a benchmark generation rebuilds
      // once per token. Measured on the A72: 498 lines of the same string in
      // one session, which is a fifth of the 1 MiB log budget spent saying
      // nothing, and it costs a `print` on the frame that is also decoding
      // tokens. The locale is now reported once, below, where it is a fact
      // about startup rather than about the build.
      return GetMaterialApp(
        title: 'mobileLM',
        translations: AppTranslation(),
        // ── O idioma é uma PREFERÊNCIA LIDA, não o deviceLocale deduzido ──────
        //
        // Este era `locale: Get.deviceLocale` com `fallbackLocale: pt_BR`, e o
        // resultado foi 62 fichas de modelo em inglês numa tela que se dizia
        // portuguesa — mais um aparelho em outro idioma vendo português sem
        // poder pedir outro. Deduzir foi o que produziu o problema, então
        // deduzir virou a opção "auto" e o padrão passou a ser uma escolha
        // declarada (inglês).
        //
        // `SettingsController` é lido aqui e não dentro do `builder`, e a razão
        // é de ordem: o `locale` do `GetMaterialApp` é decidido **antes** do
        // primeiro `build`, e a tela que muda o idioma só existe depois.
        // Ler a preferência de dentro do `builder` resolve o primeiro quadro
        // com um idioma e troca depois — o flicker que ninguém pediu.
        locale: LanguagePreference.resolver(
          Get.isRegistered<SettingsController>()
              ? Get.find<SettingsController>().language.value
              : LanguagePreference.padrao,
          Get.deviceLocale,
        ),
        // O fallback é **o idioma padrão**, não português. Com o fallback em
        // pt_BR, uma chave que faltasse em inglês aparecia traduzida e
        // ninguém notava que faltava; com o fallback no padrão ela aparece
        // como a própria chave, que é o que o `l10n_keys_test` transforma em
        // falha de CI.
        fallbackLocale: const Locale('en', 'US'),
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        initialRoute: AppRoutes.home,
        getPages: AppPages.pages,
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
      );
    });
  }
}
