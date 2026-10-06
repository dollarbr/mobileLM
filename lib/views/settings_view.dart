import '../utils/cpu_topology.dart';
import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import 'package:mobilelm/services/text_interpolation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_litert_lm/flutter_litert_lm.dart';
import '../controllers/settings_controller.dart';
import '../core/colors.dart';
import '../controllers/chat_controller.dart';
import 'server_view.dart';
import '../core/constants.dart';
import '../services/inference_service.dart';
import '../services/language_preference.dart';
import '../services/cpu_self_test.dart';
import '../services/cpu_self_test_service.dart';
import '../controllers/model_controller.dart';
import '../services/download_service.dart';
import '../services/hive_service.dart';
import '../services/local_image_service.dart';
import '../services/device_info_service.dart';
import '../services/workspace_service.dart';
import '../services/privileged_service.dart';
import '../services/tools/builtin_tools.dart';
import '../services/device_info_native.dart' as platform_info;
import '../services/encoder_settings_service.dart';
import '../services/image_generation_notification_service.dart';
import '../services/scheduled_task_service.dart';
import '../ffi/sd_ffi_bindings.dart';
import 'encoder_parameters_panel.dart';
import 'log_view.dart';

class SettingsView extends GetView<SettingsController> {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
        title: Text('settings'.tr,
            style:
                GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 34)),
        toolbarHeight: 56,
      ),
      body: Obx(() => ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              const SizedBox(height: 8),
              _sectionLabel(context, 'section_appearance'),
              _CollapsibleGroup(
                isDark: isDark,
                icon: Icons.palette_outlined,
                title: 'appearance'.tr,
                children: [
                  for (final mode in [
                    ThemeMode.light,
                    ThemeMode.dark,
                    ThemeMode.system
                  ])
                    _appleListTile(
                      context,
                      isDark,
                      leading: Icon(_themeModeIcon(mode),
                          size: 20, color: Theme.of(context).hintColor),
                      title: _themeModeName(mode).tr,
                      trailing: controller.themeMode.value == mode
                          ? Icon(Icons.check,
                              size: 18,
                              color: isDark
                                  ? const Color(0xFF0A84FF)
                                  : AppColors.primary)
                          : null,
                      showDivider: mode != ThemeMode.system,
                      onTap: () => controller.setThemeMode(mode),
                    ),
                  const Divider(height: 0.5, indent: 16),
                  _buildFontSizeCard(context, isDark),
                  const Divider(height: 0.5, indent: 16),
                  _buildLanguageCard(context, isDark),
                ],
              ),
              const SizedBox(height: 16),
              _sectionLabel(context, 'section_inference_mode'),
              _appleGroupedCard(context, isDark, children: [
                _appleListTile(
                  context,
                  isDark,
                  leading:
                      _iconBox(AppColors.success, Icons.phone_iphone_rounded),
                  title: 'local_on_device'.tr,
                  subtitle: _localSubtitle(),
                  trailing: controller.inferenceMode.value == 'local'
                      ? Icon(Icons.check,
                          size: 18,
                          color: isDark
                              ? const Color(0xFFB9F53E)
                              : AppColors.primary)
                      : null,
                  showDivider: true,
                  onTap: () => controller.setInferenceMode('local'),
                ),
                _appleListTile(
                  context,
                  isDark,
                  leading: _iconBox(AppColors.secondary, Icons.cloud_outlined),
                  title: 'cloud_api'.tr,
                  subtitle: controller.cloudProvider.value.toUpperCase(),
                  trailing: controller.inferenceMode.value == 'cloud'
                      ? Icon(Icons.check,
                          size: 18,
                          color: isDark
                              ? const Color(0xFFB9F53E)
                              : AppColors.primary)
                      : null,
                  showDivider: false,
                  onTap: () => controller.setInferenceMode('cloud'),
                ),
              ]),
              const SizedBox(height: 24),
              _sectionLabel(context, 'section_model_settings'),
              _CollapsibleGroup(
                isDark: isDark,
                icon: Icons.tune_rounded,
                title: 'default_system_prompt'.tr,
                subtitle: 'applies_to_local_and_cloud'.tr,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: TextField(
                      controller: controller.globalSystemPromptController,
                      minLines: 3,
                      maxLines: 6,
                      style: GoogleFonts.inter(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'system_prompt_hint'.tr,
                        suffixIcon: IconButton(
                            icon: const Icon(Icons.check_circle_outline,
                                size: 20),
                            onPressed: () => controller.setGlobalSystemPrompt(
                                controller.globalSystemPromptController.text)),
                      ),
                      onSubmitted: (v) => controller.setGlobalSystemPrompt(v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _CollapsibleGroup(
                isDark: isDark,
                icon: Icons.chat_bubble_outline_rounded,
                title: 'text_generation'.tr,
                subtitle: controller.liteRtPerformanceMode.value == 'auto_fast'
                    ? 'Auto Fast · thinking ${controller.thinkingMode.value}'
                    : '${controller.liteRtPerformanceMode} · thinking ${controller.thinkingMode.value}',
                children: [
                  _buildLiteRtCard(context, isDark),
                  const Divider(height: 0.5, indent: 16),
                  _buildThinkingCard(context, isDark),
                  const Divider(height: 0.5, indent: 16),
                  _buildComputeCard(context, isDark),
                ],
              ),
              const SizedBox(height: 10),
              // Sampling gets its own group instead of a card nested inside Text
              // generation, because the two are not the same decision and are not
              // touched at the same time. "Which runtime, and do I think" is
              // something you settle once per model; temperature and top-p are
              // something you move while you read the output. Nesting the second
              // inside the first also meant the sampling numbers were two levels
              // deep in a screen that already carries three encoder groups, so
              // they were the hardest panel in the app to reach.
              //
              // The inline literal rather than a `.tr` key is deliberate: the map
              // is pt_BR-only, and a key that is not in it renders as its own name
              // — which is how a title ends up reading `text_parameters`.
              _CollapsibleGroup(
                isDark: isDark,
                icon: Icons.tune_rounded,
                title: 'Text parameters',
                subtitle: _textParametersSubtitle(),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildParametersPanel(context, isDark),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Embedding and rerank parameters live apart from the text ones
              // because almost none of them mean the same thing on both sides. A
              // temperature is a text-generation dial and has no meaning for a
              // vector; a token ceiling is the one thing they share, and it is
              // not a preference on either side — it is a hard limit read from
              // the file. Merging them into one panel would mean either dead
              // controls per role or controls whose meaning changes when the
              // loaded model does.
              _CollapsibleGroup(
                isDark: isDark,
                icon: Icons.gradient_rounded,
                title: 'Embeddings',
                subtitle: _encoderSubtitle(context, 'embed'),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child:
                        EncoderParametersPanel(role: 'embed', isDark: isDark),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _CollapsibleGroup(
                isDark: isDark,
                icon: Icons.low_priority_rounded,
                title: 'Rerank',
                subtitle: _encoderSubtitle(context, 'rerank'),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child:
                        EncoderParametersPanel(role: 'rerank', isDark: isDark),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _CollapsibleGroup(
                isDark: isDark,
                icon: Icons.handyman_rounded,
                title: 'tools'.tr,
                subtitle: controller.toolsEnabled.value
                    ? '${controller.enabledTools.length} enabled'
                    : 'Off',
                children: [_buildToolsCard(context, isDark)],
              ),
              const SizedBox(height: 10),
              _CollapsibleGroup(
                isDark: isDark,
                icon: Icons.terminal_rounded,
                title: 'adb_shizuku'.tr,
                subtitle: Get.find<PrivilegedService>().state.value.label,
                children: [_buildShizukuCard(context, isDark)],
              ),
              const SizedBox(height: 10),
              _CollapsibleGroup(
                isDark: isDark,
                icon: Icons.image_outlined,
                title: 'image_generation'.tr,
                subtitle:
                    '${controller.imageSteps.value} steps · ${controller.imageGenSize.value == 0 ? 'set_auto_size'.tr : "${controller.imageGenSize.value}px"}',
                children: [_buildImageGenerationCard(context, isDark)],
              ),
              const SizedBox(height: 24),
              _sectionLabel(context, 'section_device_information'),
              _buildDeviceCard(context, isDark),
              const SizedBox(height: 10),
              if (Platform.isAndroid) _buildNpuCard(context, isDark),
              const SizedBox(height: 24),
              _sectionLabel(context, 'section_storage'),
              _buildStorageCard(context, isDark),
              const SizedBox(height: 24),
              _sectionLabel(context, 'section_workspace'),
              _buildWorkspaceCard(context, isDark),
              const SizedBox(height: 24),
              _sectionLabel(context, 'section_agent'),
              _appleGroupedCard(context, isDark, children: [
                _appleListTile(
                  context,
                  isDark,
                  leading: _iconBox(
                      const Color(0xFF8B7CFF), Icons.smart_toy_outlined),
                  title: 'tool_round_trips'.tr,
                  // The plural was wrong on screen, measured here on the A72:
                  // the default is 1, and the tile read "up to 1 hops". The same
                  // sentence appears in the ending message the loop writes, and
                  // that one had the fix; this one had the bug.
                  // **A interpolação é montada aqui e não no mapa, e por dois
                  // motivos.** Primeiro: `.tr` devolve o valor da chave e um
                  // `@n` dentro dele não é substituído — `trParams` faz isso, e
                  // a forma do plural continua sendo do português, não do
                  // Dart. Segundo, e é o que a auditoria mediu: o literal
                  // `'Agent mode: up to ${…} hop…'` **é recusado pelo filtro de
                  // idioma de propósito**, porque `TextLanguage.looksEnglish`
                  // devolve falso para qualquer texto com `$` — o valor no
                  // fonte não é o valor na tela, e trocar o literal inteiro por
                  // uma chave apagaria a parte que muda. O que está é o padrão
                  // para o caso: duas chaves, uma para cada número, e a
                  // contagem volta por cima.
                  subtitle: controller.agentMaxHops.value == 0
                      ? 'set_unlimited_agent_mode'.tr
                      : _agentHopSubtitle(controller.agentMaxHops.value),
                  trailing: InkWell(
                    onTap: () => _showHopInputDialog(context),
                    child: controller.agentMaxHops.value == 0
                        ? Text('∞',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF8B7CFF)))
                        : Text('${controller.agentMaxHops.value}',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF8B7CFF))),
                  ),
                  showDivider: false,
                  onTap: () {
                    const ladder = [0, 1, 2, 3, 4, 6, 8];
                    final i = ladder.indexOf(controller.agentMaxHops.value);
                    controller.setAgentMaxHops(ladder[(i + 1) % ladder.length]);
                  },
                ),
              ]),
              const SizedBox(height: 10),
              _scheduledTasksTile(context, isDark),
              const SizedBox(height: 10),
              _sectionLabel(context, 'section_diagnostics'),
              _appleGroupedCard(context, isDark, children: [
                // The benchmark tile and the two switches that govern it used to
                // live inside _buildLiteRtCard, which is only built when a
                // LiteRT model is selected. On a GGUF phone they did not exist:
                // no card on the Models screen, no tile in Settings, and the
                // benchmark could only be reached from a build where the run had
                // already been performed once. Found on the Galaxy A72 by
                // dumping the accessibility tree instead of tapping coordinates
                // at a remembered row — `input tap` on a screen that does not
                // respond to touch fails silently, so the absence looked like a
                // navigation mistake repeated nine times.
                //
                // A CPU benchmark does not care which runtime is loaded: it
                // always loads its own 230M GGUF. So it belongs with the
                // diagnostics, where it is reachable regardless.
                Obx(() {
                  final svc = Get.find<CpuSelfTestService>();
                  final st = svc.state;
                  return _appleListTile(
                    context,
                    isDark,
                    leading: _iconBox(
                        isDark ? const Color(0xFFB9F53E) : AppColors.primary,
                        Icons.speed_rounded),
                    title: 'set_cpu_benchmark'.tr,
                    subtitle: st.running.value
                        ? 'set_benchmark_running'.tr
                        : st.summary.value.isEmpty
                            ? 'set_benchmark_detail'.tr
                            : st.summary.value,
                    trailing: st.running.value
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: isDark
                                    ? const Color(0xFFB9F53E)
                                    : AppColors.primary),
                          )
                        : Switch(
                            value: svc.offerEnabled,
                            onChanged: (v) =>
                                v ? svc.restoreOffer() : svc.dismissOffer(),
                          ),
                    onTap: st.running.value ? null : () => _runBenchmark(svc),
                  );
                }),
                Obx(() {
                  final mc = Get.find<ModelController>();
                  return _appleListTile(
                    context,
                    isDark,
                    leading: _iconBox(
                        isDark ? const Color(0xFFB9F53E) : AppColors.primary,
                        Icons.visibility_off_outlined),
                    title: 'set_show_models_ignore'.tr,
                    subtitle: mc.ignoreBenchmarkAdvice.value
                        ? 'set_show_models_ignore_detail'.tr
                        : mc.localCatalogueHidden.value
                            ? 'set_local_only_detail'.tr
                            : 'set_keep_models_detail'.tr,
                    trailing: Switch(
                      value: mc.ignoreBenchmarkAdvice.value,
                      onChanged: mc.setIgnoreBenchmarkAdvice,
                    ),
                    onTap: () => mc.setIgnoreBenchmarkAdvice(
                        !mc.ignoreBenchmarkAdvice.value),
                  );
                }),
                _appleListTile(
                  context,
                  isDark,
                  leading:
                      _iconBox(const Color(0xFF5AC8FA), Icons.article_outlined),
                  title: 'logs'.tr,
                  subtitle: 'view_errors_warnings'.tr,
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => Get.to(() => const LogView()),
                ),
                _appleListTile(
                  context,
                  isDark,
                  leading:
                      _iconBox(const Color(0xFFB9F53E), Icons.dns_outlined),
                  title: 'local_api_server'.tr,
                  subtitle: 'openai_compatible_endpoint'.tr,
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  showDivider: false,
                  onTap: () => Get.to(() => const ServerView()),
                ),
              ]),
              const SizedBox(height: 24),
              _sectionLabel(context, 'section_about'),
              _appleGroupedCard(context, isDark, children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              isDark
                                  ? const Color(0xFFB9F53E)
                                  : AppColors.primary,
                              AppColors.secondary
                            ]),
                            borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.auto_awesome_rounded,
                            color: Colors.white, size: 22)),
                    const SizedBox(width: 14),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('mobile_lm'.tr,
                              style: GoogleFonts.inter(
                                  fontSize: 17, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                              controller.appVersion.value.isEmpty
                                  ? 'Version unavailable · by dollarbr'
                                  : 'v${controller.appVersion.value} · by dollarbr',
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: Theme.of(context).hintColor)),
                        ]),
                  ]),
                ),
              ]),
              const SizedBox(height: 40),
            ],
          )),
    );
  }

  // ── Apple grouped card container ──
  Widget _scheduledTasksTile(BuildContext context, bool isDark) {
    final taskCount = Get.find<ScheduledTaskService>().tasks.length;
    return _appleGroupedCard(context, isDark, children: [
      _appleListTile(
        context,
        isDark,
        leading: _iconBox(const Color(0xFF8B7CFF), Icons.schedule_rounded),
        title: 'scheduled_tasks'.tr,
        subtitle: taskCount == 0
            ? 'set_daily_prompts_detail'.tr
            : '$taskCount daily task${taskCount == 1 ? '' : 's'}',
        showDivider: false,
        onTap: () => _openScheduledTasksSheet(context, isDark),
      ),
    ]);
  }

  Widget _scheduledTaskNotificationTile(BuildContext context, bool isDark) {
    final hive = Get.find<HiveService>();
    final showNotif = hive.getSetting<bool>(
          AppConstants.keyScheduledTaskNotifications,
          defaultValue: true,
        ) ??
        true;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('show_background_notification'.tr),
      subtitle: Text('set_notification_detail'.tr),
      trailing: Switch(
        value: showNotif,
        onChanged: (v) async {
          await hive.setSetting(AppConstants.keyScheduledTaskNotifications, v);
          if (!v) {
            await Get.find<ImageGenerationNotificationService>()
                .cancelScheduledNotification();
          }
        },
      ),
    );
  }

  Widget _appleGroupedCard(BuildContext context, bool isDark,
      {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  // ── Apple-style list tile ──
  Widget _appleListTile(
    BuildContext context,
    bool isDark, {
    Widget? leading,
    required String title,
    String? subtitle,
    Widget? trailing,
    bool showDivider = true,
    VoidCallback? onTap,
  }) {
    return Column(children: [
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            if (leading != null) ...[leading, const SizedBox(width: 14)],
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Text(title,
                      style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: isDark ? Colors.white : Colors.black)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: GoogleFonts.inter(
                            fontSize: 13, color: Theme.of(context).hintColor))
                  ],
                ])),
            if (trailing != null) trailing,
          ]),
        ),
      ),
      if (showDivider)
        Divider(
            height: 0.5,
            indent: leading != null ? 58 : 16,
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06)),
    ]);
  }

  Widget _iconBox(Color color, IconData icon) {
    return Container(
        width: 30,
        height: 30,
        decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(7)),
        child: Icon(icon, size: 17, color: Colors.white));
  }

  void _showHopInputDialog(BuildContext context) {
    final current = Get.find<SettingsController>().agentMaxHops.value;
    final ctl = TextEditingController(text: current == 0 ? '∞' : '$current');
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text('tool_round_trips'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // **This is where the "unlimited" label did the most damage**, because
            // it is the screen where somebody chooses it. It read *"Infinite agent
            // mode (no ceiling)"* next to a field whose `0` reached the loop as
            // `while (hop < 0)` — so the promise was made at the exact moment it
            // was broken, and the tile above said the same thing.
            //
            // There is a ceiling now, and it is the app's, so it is named here
            // rather than left for the user to discover on a stuck spinner. The
            // number is interpolated from the constant so the two cannot drift.
            Text(
              current == 0
                  ? 'No cap of your own — the app stops at '
                      '${AppConstants.agentHopBackstop} if the model keeps '
                      'asking for tools'
                  : 'set_hops_label'.tr,
              style: GoogleFonts.inter(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              keyboardType: const TextInputType.numberWithOptions(
                  signed: false, decimal: false),
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Value',
                hintText: 'set_hops_hint'.tr,
              ),
              onSubmitted: (v) {
                final val = int.tryParse(v);
                if (val != null && val >= 0 && val <= 8) {
                  Get.find<SettingsController>().setAgentMaxHops(val);
                  Navigator.pop(dlgCtx);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () {
              final val = int.tryParse(ctl.text.trim());
              if (val != null && val >= 0 && val <= 8) {
                Get.find<SettingsController>().setAgentMaxHops(val);
                if (dlgCtx.mounted) Navigator.pop(dlgCtx);
              }
            },
            child: Text('ok'.tr),
          ),
        ],
      ),
    );
  }

  void _openScheduledTasksSheet(BuildContext context, bool isDark) {
    try {
      final service = Get.find<ScheduledTaskService>();
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) => Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.surface : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, 24 + MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Obx(() => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('scheduled_tasks'.tr,
                      style: GoogleFonts.inter(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  if (service.tasks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'set_no_tasks_detail'.tr,
                        style: GoogleFonts.inter(
                            fontSize: 13, color: Colors.grey.shade500),
                      ),
                    ),
                  ...service.tasks.map((t) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t.name,
                            style:
                                GoogleFonts.inter(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${t.frequencyLabel} ${t.hour.toString().padLeft(2, '0')}:'
                          '${t.minute.toString().padLeft(2, '0')}'
                          '${t.modelName == null ? "" : " · ${t.modelName}"}'
                          '${t.keepModelLoaded ? " · model kept loaded" : ""}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: t.enabled,
                              onChanged: (v) async {
                                await service.setEnabled(t, v);
                                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () async {
                                final edited = await _editScheduledTaskDialog(
                                    sheetCtx, service, t);
                                if (edited && sheetCtx.mounted)
                                  Navigator.pop(sheetCtx);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () {
                                service.remove(t.id);
                                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                              },
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 8),
                  _scheduledTaskNotificationTile(context, isDark),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () async {
                      final created =
                          await _createScheduledTaskDialog(sheetCtx, service);
                      if (created && sheetCtx.mounted) Navigator.pop(sheetCtx);
                    },
                    icon: const Icon(Icons.add),
                    label: Text('new_daily_task'.tr),
                  ),
                ],
              )),
        ),
      );
    } catch (e, st) {
      if (context.mounted) {
        Get.snackbar('error'.tr, '$e', snackPosition: SnackPosition.BOTTOM);
      }
    }
  }

  Future<bool> _createScheduledTaskDialog(
      BuildContext context, ScheduledTaskService service) async {
    final nameCtl = TextEditingController();
    final promptCtl = TextEditingController();
    TimeOfDay time = const TimeOfDay(hour: 8, minute: 0);
    String frequency = 'daily';
    bool keepModelLoaded = false;
    final modelCtrl = Get.find<ModelController>();
    final downloaded = modelCtrl.downloadedFiles.toList();
    if (downloaded.isEmpty) {
      Get.snackbar('scheduled_tasks'.tr, 'set_no_local_files'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return false;
    }
    String selectedModel = downloaded.first;
    var ok = false;
    await showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setState) => AlertDialog(
          title: Text('new_task'.tr),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtl,
                decoration: InputDecoration(labelText: 'set_field_name'.tr),
              ),
              TextField(
                controller: promptCtl,
                minLines: 3,
                maxLines: 5,
                decoration: InputDecoration(labelText: 'prompt_to_run'.tr),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: frequency,
                decoration: const InputDecoration(labelText: 'Frequency'),
                items: [
                  DropdownMenuItem(value: 'daily', child: Text('daily'.tr)),
                  DropdownMenuItem(value: 'hourly', child: Text('hourly'.tr)),
                  DropdownMenuItem(
                      value: 'every2h', child: Text('every_2h'.tr)),
                  DropdownMenuItem(
                      value: 'every4h', child: Text('every_4h'.tr)),
                  DropdownMenuItem(
                      value: 'every6h', child: Text('every_6h'.tr)),
                  DropdownMenuItem(
                      value: 'every8h', child: Text('every_8h'.tr)),
                  DropdownMenuItem(value: 'once', child: Text('just_once'.tr)),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => frequency = v);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_rounded),
                title: Text(time.format(dlgCtx)),
                subtitle: frequency == 'once'
                    ? Text('run_this_single_time_at_the_chosen_hour'.tr)
                    : frequency == 'hourly' || frequency.startsWith('every')
                        ? Text('at_this_minute_past_each_interval'.tr)
                        : Text('at_this_time_every_day'.tr),
                onTap: () async {
                  final picked =
                      await showTimePicker(context: dlgCtx, initialTime: time);
                  if (picked != null) setState(() => time = picked);
                },
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                title: Text('keep_model_loaded_between_runs'.tr),
                subtitle: Text('set_faster_more_ram'.tr),
                value: keepModelLoaded,
                onChanged: (v) => setState(() => keepModelLoaded = v ?? false),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedModel,
                decoration: InputDecoration(labelText: 'set_model_label'.tr),
                items: downloaded
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => selectedModel = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: Text('cancel'.tr),
            ),
            FilledButton(
              onPressed: () {
                if (nameCtl.text.trim().isEmpty ||
                    promptCtl.text.trim().isEmpty) return;
                ok = true;
                Navigator.pop(dlgCtx);
              },
              child: Text('create'.tr),
            ),
          ],
        ),
      ),
    );
    if (!ok) return false;
    try {
      final modelPath =
          await Get.find<DownloadService>().modelPath(selectedModel);
      await service.add(
        name: nameCtl.text.trim(),
        prompt: promptCtl.text.trim(),
        modelPath: modelPath,
        modelName: selectedModel,
        hour: time.hour,
        minute: time.minute,
        frequency: frequency,
        keepModelLoaded: keepModelLoaded,
      );
      Get.snackbar('scheduled_tasks'.tr, 'set_task_created'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return true;
    } catch (e) {
      Get.snackbar('scheduled_tasks'.tr, preencher('set_failed', {'e': '$e'}),
          snackPosition: SnackPosition.BOTTOM);
      return false;
    }
  }

  Future<bool> _editScheduledTaskDialog(BuildContext context,
      ScheduledTaskService service, ScheduledTask task) async {
    final nameCtl = TextEditingController(text: task.name);
    final promptCtl = TextEditingController(text: task.prompt);
    TimeOfDay time = TimeOfDay(hour: task.hour, minute: task.minute);
    String frequency = task.frequency;
    bool keepModelLoaded = task.keepModelLoaded;
    final modelCtrl = Get.find<ModelController>();
    final downloaded = modelCtrl.downloadedFiles.toList();
    String selectedModel = task.modelName ?? downloaded.firstOrNull ?? '';
    var ok = false;
    await showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setState) => AlertDialog(
          title: Text('edit_task'.tr),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtl,
                decoration: InputDecoration(labelText: 'set_field_name'.tr),
              ),
              TextField(
                controller: promptCtl,
                minLines: 3,
                maxLines: 5,
                decoration: InputDecoration(labelText: 'prompt_to_run'.tr),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: frequency,
                decoration: const InputDecoration(labelText: 'Frequency'),
                items: [
                  DropdownMenuItem(value: 'daily', child: Text('daily'.tr)),
                  DropdownMenuItem(value: 'hourly', child: Text('hourly'.tr)),
                  DropdownMenuItem(
                      value: 'every2h', child: Text('every_2h'.tr)),
                  DropdownMenuItem(
                      value: 'every4h', child: Text('every_4h'.tr)),
                  DropdownMenuItem(
                      value: 'every6h', child: Text('every_6h'.tr)),
                  DropdownMenuItem(
                      value: 'every8h', child: Text('every_8h'.tr)),
                  DropdownMenuItem(value: 'once', child: Text('just_once'.tr)),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => frequency = v);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_rounded),
                title: Text(time.format(dlgCtx)),
                subtitle: frequency == 'once'
                    ? Text('run_this_single_time_at_the_chosen_hour'.tr)
                    : frequency == 'hourly' || frequency.startsWith('every')
                        ? Text('at_this_minute_past_each_interval'.tr)
                        : Text('at_this_time_every_day'.tr),
                onTap: () async {
                  final picked =
                      await showTimePicker(context: dlgCtx, initialTime: time);
                  if (picked != null) setState(() => time = picked);
                },
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                title: Text('keep_model_loaded_between_runs'.tr),
                subtitle: Text('set_faster_more_ram'.tr),
                value: keepModelLoaded,
                onChanged: (v) => setState(() => keepModelLoaded = v ?? false),
              ),
              if (downloaded.isNotEmpty) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedModel.isEmpty ? null : selectedModel,
                  decoration: InputDecoration(labelText: 'set_model_label'.tr),
                  hint: Text('select_model'.tr),
                  items: downloaded
                      .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => selectedModel = v);
                  },
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: Text('cancel'.tr),
            ),
            FilledButton(
              onPressed: () {
                if (nameCtl.text.trim().isEmpty ||
                    promptCtl.text.trim().isEmpty) return;
                ok = true;
                Navigator.pop(dlgCtx);
              },
              child: Text('save'.tr),
            ),
          ],
        ),
      ),
    );
    if (!ok) return false;
    try {
      final modelPath = selectedModel.isNotEmpty
          ? await Get.find<DownloadService>().modelPath(selectedModel)
          : task.modelPath;
      final modelName = selectedModel.isEmpty ? null : selectedModel;
      final updated = ScheduledTask(
        id: task.id,
        name: nameCtl.text.trim(),
        prompt: promptCtl.text.trim(),
        modelPath: modelPath,
        modelName: modelName,
        hour: time.hour,
        minute: time.minute,
        frequency: frequency,
        keepModelLoaded: keepModelLoaded,
        enabled: task.enabled,
        lastRunAt: task.lastRunAt,
      );
      await service.update(updated);
      Get.snackbar('scheduled_tasks'.tr, 'set_task_updated'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return true;
    } catch (e) {
      Get.snackbar('scheduled_tasks'.tr, preencher('set_failed', {'e': '$e'}),
          snackPosition: SnackPosition.BOTTOM);
      return false;
    }
  }

  /// One line saying what the panel's overrides currently are, so the collapsed
  /// header is not a bare title.
  ///
  /// Reads the count and not the values: a header that tried to summarise them
  /// would have to be as wide as the longest prefix, and the useful signal is
  /// "is anything overridden at all".
  String _encoderSubtitle(BuildContext context, String role) {
    final e = Get.find<EncoderSettingsService>();
    if (role == 'embed') {
      final parts = <String>[];
      if (e.embedQueryPrefix.value != null) parts.add('query prefix');
      if (e.embedPassagePrefix.value != null) parts.add('passage prefix');
      if (e.embedNormalize.value != null) {
        parts.add(e.embedNormalize.value! ? 'normalise' : 'raw');
      }
      if (parts.isEmpty) return 'set_all_from_model'.tr;
      return parts.join(' · ');
    }
    final parts = <String>[];
    if (e.rerankTopN.value != null) parts.add('top ${e.rerankTopN.value}');
    if (e.rerankDocumentSeparator.value != '\n') {
      parts.add('sep "${e.rerankDocumentSeparator.value}"');
    }
    if (!e.rerankReturnDocuments.value) parts.add('no documents');
    if (parts.isEmpty) return 'set_all_from_model'.tr;
    return parts.join(' · ');
  }

  /// Rótulo de seção em caixa alta.
  ///
  /// **O `.tr` é aqui, não no call site**, e o `toUpperCase` vem **depois**.
  /// Eram literais em inglês numa tela que já falava português — que é
  /// exatamente o sintoma visível do defeito que o seletor de idioma veio
  /// fechar: um título de seção numa língua que a pessoa não escolheu, acima
  /// de uma tela que fala a dela.
  ///
  /// `.tr` e depois `toUpperCase` porque PT-BR e EN diferem na caixa de letras
  /// acentuadas, e a regra de exibição (caixa alta, entreletra 1.4) pertence ao
  /// estilo da seção, não à tradução.
  Widget _sectionLabel(BuildContext context, String chave) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 6),
      child: Text(chave.tr.toUpperCase(),
          style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
              color: Theme.of(context).hintColor)),
    );
  }

  String _localSubtitle() {
    final inf = Get.find<InferenceService>();
    final localImage = Get.find<LocalImageService>();
    if (inf.isModelLoaded.value) {
      return 'Active: ${inf.loadedModelName.value}';
    } else if (localImage.isModelLoaded.value) {
      return 'Active: ${localImage.loadedModelName.value}';
    }
    return 'no_model_loaded'.tr;
  }

  Widget _buildDeviceCard(BuildContext context, bool isDark) {
    return Obx(() {
      final device = Get.find<DeviceInfoService>();
      Color tierColor;
      IconData tierIcon;
      switch (device.deviceTier.value) {
        case 'low':
          tierColor = AppColors.error;
          tierIcon = Icons.battery_alert;
          break;
        case 'mid':
          tierColor = AppColors.warning;
          tierIcon = Icons.phone_android;
          break;
        case 'high':
          tierColor = AppColors.success;
          tierIcon = Icons.smartphone;
          break;
        case 'ultra':
          tierColor = AppColors.primary;
          tierIcon = Icons.rocket_launch;
          break;
        default:
          tierColor = Theme.of(context).hintColor;
          tierIcon = Icons.phone_android;
      }

      final soc = device.socFamily.value;
      final quantWarning = soc.quantWarning;

      return _appleGroupedCard(context, isDark, children: [
        Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              _iconBox(tierColor, tierIcon),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(device.tierDescription,
                        style: GoogleFonts.inter(
                            fontSize: 15, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    // **Três valores, uma frase, e a ordem muda entre idiomas.**
                    // `'@ram GB'` em português vira `'@ram GB'` em inglês, mas
                    // `Context: @ctx` não pode virar `@ctx de contexto` sem
                    // reescrever o mapa inteiro — e é por isso que `preencher`
                    // substitui por nome em vez de interpolar.
                    Text(
                        preencher('set_device_budget', {
                          'ram': device.availableRamGB.value.toStringAsFixed(1),
                          'ctx': '${device.recommendedContextSize}',
                          'tok': '${device.recommendedMaxTokens}',
                        }),
                        style: GoogleFonts.inter(
                            fontSize: 12, color: Theme.of(context).hintColor)),
                  ])),
            ])),
        // SoC + quantization recommendation
        if (soc != platform_info.SocFamily.unknown) ...[
          const Divider(height: 1, indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(children: [
              _iconBox(const Color(0xFF5856D6), Icons.memory_outlined),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(soc.displayName,
                        style: GoogleFonts.inter(
                            fontSize: 14, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 3),
                    Text('Recommended: ${soc.recommendedQuant}',
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: quantWarning != null
                                ? const Color(0xFFFF9500)
                                : Theme.of(context).hintColor)),
                  ],
                ),
              ),
            ]),
          ),
        ],
        // Warning banner for problematic SoCs
        if (quantWarning != null) ...[
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9500).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 16, color: Color(0xFFFF9500)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(quantWarning,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFFFF9500),
                        fontWeight: FontWeight.w500,
                      )),
                ),
              ],
            ),
          ),
        ],
      ]);
    });
  }

  /// Master switch plus one row per tool.
  ///
  /// The per-tool rows only appear once the master switch is on, and they are
  /// what the prompt is built from — a tool the user unticked is never
  /// advertised to the model, so it cannot be called and then refused.
  ///
  /// The catalogue is read from [buildDefaultToolRegistry] with no filter, so a
  /// tool added there shows up here without touching this file.
  /// The privileged block's own card: its tools are useless without a binder,
  /// and the three not-ready states each need a different action from the
  /// user, so they get told which one applies.
  Widget _buildShizukuCard(BuildContext context, bool isDark) {
    final service = Get.find<PrivilegedService>();
    return Obx(() {
      final state = service.state.value;
      final identity = service.identity.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state == ShizukuState.ready && identity.isNotEmpty
                ? '${state.label} · $identity'
                : state.label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          if (state.hint.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              state.hint,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
            ),
          ],
          if (state == ShizukuState.ready) ...[
            const SizedBox(height: 6),
            Text(
              'set_privileged_note'.tr,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(children: [
            if (state == ShizukuState.needsPermission) ...[
              FilledButton(
                onPressed: service.requestPermission,
                child: Text('grant_permission'.tr),
              ),
              const SizedBox(width: 8),
            ],
            OutlinedButton(
              onPressed: service.refresh,
              child: Text('re_check'.tr),
            ),
          ]),
        ],
      );
    });
  }

  Widget _buildToolsCard(BuildContext context, bool isDark) {
    final enabled = controller.toolsEnabled.value;
    final accent = isDark ? const Color(0xFFB9F53E) : AppColors.primary;
    // Build the full registry (core + file + photo tools) so the count in
    // the subtitle matches what the model actually sees — otherwise it can
    // show "22 of 16" when file/photo tools are counted in on.length but not
    // in the visible catalogue.
    final chat = Get.find<ChatController>();
    final catalogue = buildDefaultToolRegistry(
      customSearchUrl: controller.customSearchUrl.value,
      customSearchToken: controller.customSearchToken.value,
      extra: [
        ...buildFileTools(projectPath: () => chat.currentProjectPath.value),
        ...buildPhotoTools(projectPath: () => chat.currentProjectPath.value),
        ...privilegedToolsIfReady(),
      ],
    ).all.toList();
    final others = catalogue
        .where((t) => t.name != 'web_search' && t.name != 'read_url')
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final ordered = [
      ...others,
      catalogue.firstWhere((t) => t.name == 'read_url'),
      catalogue.firstWhere((t) => t.name == 'web_search'),
    ];
    final on = controller.enabledTools;

    return _appleGroupedCard(context, isDark, children: [
      _appleListTile(
        context,
        isDark,
        leading: _iconBox(accent, Icons.handyman_rounded),
        title: 'tools'.tr,
        subtitle: enabled
            ? '${on.length} of ${catalogue.length} enabled'
            : 'set_agent_off_detail'.tr,
        trailing: enabled ? Icon(Icons.check, size: 18, color: accent) : null,
        showDivider: enabled,
        onTap: () => controller.setToolsEnabled(!enabled),
      ),
      if (enabled)
        for (var i = 0; i < ordered.length; i++)
          _appleListTile(
            context,
            isDark,
            leading: _iconBox(
                ordered[i].requiresNetwork ? AppColors.warning : accent,
                ordered[i].requiresNetwork
                    ? Icons.public_rounded
                    : Icons.offline_bolt_rounded),
            title: ordered[i].name,
            subtitle: ordered[i].requiresNetwork
                ? 'Needs internet — ${ordered[i].description}'
                : ordered[i].description,
            trailing: on.contains(ordered[i].name)
                ? Icon(Icons.check, size: 18, color: accent)
                : null,
            showDivider: i < ordered.length - 1,
            onTap: () => controller.toggleTool(
                ordered[i].name, !on.contains(ordered[i].name)),
          ),
      if (enabled && on.contains('web_search'))
        _buildCustomSearchFields(context, isDark),
    ]);
  }

  /// Optional search endpoint for web_search.
  ///
  /// Only shown once web_search is ticked, since it configures nothing else.
  /// Left empty, search falls back to scraping Brave, then Startpage, then
  /// DuckDuckGo — which works but breaks whenever one of them redesigns. A URL
  /// here points at something with an actual contract: a SearXNG instance
  /// (no token, plain GET) or a service like Tavily (token, JSON POST).
  Widget _buildCustomSearchFields(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          'set_search_endpoint_hint'.tr,
          style: GoogleFonts.inter(
              fontSize: 12, color: Theme.of(context).hintColor),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller.customSearchUrlController,
          style: GoogleFonts.inter(fontSize: 14),
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'set_custom_search_url'.tr,
            hintText: 'set_custom_search_url_hint'.tr,
            suffixIcon: IconButton(
              icon: const Icon(Icons.check_circle_outline, size: 20),
              onPressed: () => controller.setCustomSearchUrl(
                  controller.customSearchUrlController.text),
            ),
          ),
          onSubmitted: controller.setCustomSearchUrl,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller.customSearchTokenController,
          style: GoogleFonts.inter(fontSize: 14),
          autocorrect: false,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'set_custom_search_token'.tr,
            hintText: 'set_custom_search_token_hint'.tr,
            suffixIcon: IconButton(
              icon: const Icon(Icons.check_circle_outline, size: 20),
              onPressed: () => controller.setCustomSearchToken(
                  controller.customSearchTokenController.text),
            ),
          ),
          onSubmitted: controller.setCustomSearchToken,
        ),
        const SizedBox(height: 6),
        Text(
          controller.customSearchUrl.value.isEmpty
              ? 'set_scrape_chain'.tr: 'Using ${controller.customSearchUrl.value}'
                  '${controller.customSearchToken.value.isEmpty ? " (GET, no auth)" : " (POST, bearer token)"}'
                  ' first, scrapes as fallback.',
          style: GoogleFonts.inter(
              fontSize: 11, color: Theme.of(context).hintColor),
        ),
      ]),
    );
  }

  Widget _buildThinkingCard(BuildContext context, bool isDark) {
    // Reasoning models take a literal `/think` / `/no_think` in the prompt.
    // Default is Auto — a model that never learned the token should not be sent
    // one on every turn.
    final modes = [
      (
        value: 'auto',
        title: 'Thinking: Auto',
        subtitle: 'set_send_nothing_default'.tr,
        icon: Icons.auto_awesome_rounded
      ),
      (
        value: 'on',
        title: 'Thinking: On',
        subtitle: 'set_think_label'.tr,
        icon: Icons.psychology_rounded
      ),
      (
        value: 'off',
        title: 'Thinking: Off',
        subtitle: 'set_no_think_label'.tr,
        icon: Icons.bolt_rounded
      ),
    ];
    return _appleGroupedCard(context, isDark, children: [
      for (var i = 0; i < modes.length; i++)
        _appleListTile(
          context,
          isDark,
          leading: _iconBox(
              isDark ? const Color(0xFFB9F53E) : AppColors.primary,
              modes[i].icon),
          title: modes[i].title,
          subtitle: modes[i].subtitle,
          trailing: controller.thinkingMode.value == modes[i].value
              ? Icon(Icons.check,
                  size: 18,
                  color: isDark ? const Color(0xFFB9F53E) : AppColors.primary)
              : null,
          showDivider: i < modes.length - 1,
          onTap: () => controller.setThinkingMode(modes[i].value),
        ),
    ]);
  }

  /// Read-only report on the NPU rung.
  ///
  /// Both halves have to be there — the dispatch library we ship and the
  /// vendor driver the device exposes — so the useful thing to show is what
  /// the probe actually found, not a yes/no. Probed on build rather than
  /// cached: it costs a directory listing plus a dlopen, and the answer can
  /// change between installs.
  Widget _buildNpuCard(BuildContext context, bool isDark) {
    return FutureBuilder<NpuStatus>(
      future: NpuStatus.probe(),
      builder: (context, snapshot) {
        final status = snapshot.data;
        final subtitle = switch ((snapshot.connectionState, status)) {
          (ConnectionState.done, final s?) => s.toString(),
          (ConnectionState.done, null) => 'Probe failed: ${snapshot.error}',
          _ => 'Checking…',
        };
        return _appleGroupedCard(context, isDark, children: [
          _appleListTile(
            context,
            isDark,
            leading: _iconBox(
                status?.available == true
                    ? AppColors.success
                    : (isDark ? const Color(0xFFB9F53E) : AppColors.primary),
                Icons.memory_rounded),
            title: 'NPU',
            subtitle: subtitle,
            showDivider: false,
          ),
        ]);
      },
    );
  }

  /// CPU threads and the vision-encoder backend.
  ///
  /// Both are exposed rather than decided for the user because both are
  /// per-device facts we cannot know: ggml syncs threads at every op, so on a
  /// big.LITTLE phone more threads can be slower, and whether a projector runs
  /// faster on the GPU depends on how much of the ViT that driver actually
  /// implements.
  /// Vision-encoder backend choice. The thread count lives in the Text
  /// Generation parameters panel — it is a sampler-adjacent knob, not a
  /// per-device diagnostic.
  Widget _buildComputeCard(BuildContext context, bool isDark) {
    final accent = isDark ? const Color(0xFF0A84FF) : AppColors.primary;
    return Obx(() => _appleGroupedCard(context, isDark, children: [
          _appleListTile(
            context,
            isDark,
            leading: _iconBox(accent, Icons.image_search_rounded),
            title: 'Vision encoder on CPU',
            subtitle: controller.mmprojForceCpu.value
                ? 'set_projector_cpu_detail'.tr
                : 'set_projector_auto_detail'.tr,
            trailing: controller.mmprojForceCpu.value
                ? Icon(Icons.check, size: 18, color: accent)
                : null,
            showDivider: false,
            onTap: () =>
                controller.setMmprojForceCpu(!controller.mmprojForceCpu.value),
          ),
        ]));
  }

  /// Runs the CPU benchmark from Settings. Separate from the Models-tab card
  /// because this one is the durable entry point: it is here after a
  /// dismissal, and it carries the switch that brings the card back.
  Future<void> _runBenchmark(CpuSelfTestService svc) async {
    final models = Get.find<ModelController>().availableModels.toList();
    final r = await svc.run(availableModels: models);
    if (svc.state.cancelled.value) return;
    Get.snackbar(
      r.passed ? 'CPU works' : 'CPU problem',
      describeCpuSelfTest(r),
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 5),
    );
  }

  Widget _buildLiteRtCard(BuildContext context, bool isDark) {
    final modes = [
      (
        value: 'auto_fast',
        title: 'Auto Fast',
        subtitle: 'set_gpu_first_label'.tr,
        icon: Icons.auto_awesome_rounded
      ),
      (
        value: 'gpu_fast',
        title: 'GPU Fast',
        subtitle: 'set_max_speed_label'.tr,
        icon: Icons.bolt_rounded
      ),
      (
        value: 'cpu_safe',
        title: 'CPU Safe',
        subtitle: 'set_stable_mode_label'.tr,
        icon: Icons.shield_outlined
      ),
    ];
    return _appleGroupedCard(context, isDark, children: [
      for (var i = 0; i < modes.length; i++)
        _appleListTile(
          context,
          isDark,
          leading: _iconBox(
              isDark ? const Color(0xFFB9F53E) : AppColors.primary,
              modes[i].icon),
          title: modes[i].title,
          subtitle: modes[i].subtitle,
          trailing: controller.liteRtPerformanceMode.value == modes[i].value
              ? Icon(Icons.check,
                  size: 18,
                  color: isDark ? const Color(0xFFB9F53E) : AppColors.primary)
              : null,
          showDivider: i < modes.length - 1,
          onTap: () => controller.setLiteRtPerformanceMode(modes[i].value),
        ),
      // The CPU benchmark tile and the "Show models, ignore benchmarks" switch
      // used to be here, at the end of the LiteRT card. That card is only built
      // when a LiteRT model is selected, so on a phone running a GGUF the
      // benchmark had no way to be started at all. They now live in the
      // DIAGNOSTICS group, where they are reachable with any model loaded —
      // the benchmark loads its own 230M GGUF and does not care which runtime
      // the app happens to be holding.
    ]);
  }

  Widget _buildImageGenerationCard(BuildContext context, bool isDark) {
    final stepsValue = controller.imageSteps.value.toDouble();
    const safeMax = 8.0;
    final isOver = stepsValue > safeMax;
    final accent = isOver
        ? AppColors.warning
        : (isDark ? const Color(0xFFB9F53E) : AppColors.primary);
    final selectedBackend = controller.imageGenBackend.value;
    final gpuBackend = controller.recommendedImageGpuBackend();
    final gpuAvailable = gpuBackend != Backend.cpu;

    return _appleGroupedCard(context, isDark, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.image_rounded, size: 16, color: accent),
            const SizedBox(width: 8),
            // `Expanded` here, not `Flexible`, and the reason is the `Spacer`:
            // a row with `Expanded`, a `Spacer` and an unbounded `Text` in it
            // is a row that has already decided to overflow, because both flex
            // children ask for space while the `Text` asks for all of it. The
            // `Spacer` was doing nothing that `Expanded` does not do better.
            //
            // `Expanded` rather than `Flexible` on purpose: this is a settings
            // tile, and the label should occupy the gap between the icon and the
            // value rather than hug the icon. At 15 dp with a 27-character
            // translation and 32 dp of group padding it fit — this was not the
            // broken one. It is here because the audit's threshold flagged it and
            // the shape is the same shape, one translation away from not fitting.
            Expanded(
              child: Text('image_gen_steps'.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      fontSize: 15, fontWeight: FontWeight.w400)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(controller.imageSteps.value.toString(),
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      color: accent,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
          Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('recommended_max_8'.tr,
                  style: GoogleFonts.inter(
                      fontSize: 12, color: Theme.of(context).hintColor))),
          Slider(
              value: stepsValue.clamp(1, 20),
              min: 1,
              max: 20,
              divisions: 19,
              activeColor: accent,
              onChanged: (v) => controller.setImageSteps(v.toInt())),
          if (isOver)
            Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Icon(Icons.warning_amber_rounded, size: 14, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text('set_more_steps_slower'.tr,
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              color: accent,
                              fontWeight: FontWeight.w400))),
                ])),
        ]),
      ),
      const Divider(height: 1, indent: 16, endIndent: 16),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.photo_size_select_large_rounded,
                size: 16,
                color: isDark ? const Color(0xFFB9F53E) : AppColors.primary),
            const SizedBox(width: 8),
            Text('image_size'.tr,
                style: GoogleFonts.inter(
                    fontSize: 15, fontWeight: FontWeight.w400)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: (isDark ? const Color(0xFFB9F53E) : AppColors.primary)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(
                  controller.imageGenSize.value == 0
                      ? 'Auto'
                      : '${controller.imageGenSize.value}px',
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      color:
                          isDark ? const Color(0xFFB9F53E) : AppColors.primary,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
          Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 10),
              child: Text('set_bigger_size_detail'.tr,
                  style: GoogleFonts.inter(
                      fontSize: 12, color: Theme.of(context).hintColor))),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in const [
                (value: 0, label: 'Auto'),
                (value: 256, label: '256'),
                (value: 320, label: '320'),
                (value: 384, label: '384'),
                (value: 512, label: '512'),
              ])
                ChoiceChip(
                  label: Text(option.label),
                  selected: controller.imageGenSize.value == option.value,
                  onSelected: (_) => controller.setImageGenSize(option.value),
                  visualDensity: VisualDensity.compact,
                  labelStyle: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: controller.imageGenSize.value == option.value
                        ? Colors.white
                        : Theme.of(context).hintColor,
                  ),
                  selectedColor:
                      isDark ? const Color(0xFFB9F53E) : AppColors.primary,
                  backgroundColor: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                  side: BorderSide(
                    color: controller.imageGenSize.value == option.value
                        ? Colors.transparent
                        : Theme.of(context).dividerColor.withValues(alpha: 0.3),
                  ),
                  showCheckmark: false,
                ),
            ],
          ),
          if (controller.imageGenSize.value >= 512)
            Container(
                margin: const EdgeInsets.only(top: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 14, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text('set_512_detail'.tr,
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.warning,
                              fontWeight: FontWeight.w400))),
                ])),
        ]),
      ),
      const Divider(height: 1, indent: 16, endIndent: 16),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.shield_outlined,
                size: 16,
                color: isDark ? const Color(0xFFB9F53E) : AppColors.primary),
            const SizedBox(width: 8),
            Text('gpu_safety'.tr,
                style: GoogleFonts.inter(
                    fontSize: 15, fontWeight: FontWeight.w400)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: (isDark ? const Color(0xFFB9F53E) : AppColors.primary)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(
                  controller.imageGenGpuGuardMb.value <= 0
                      ? 'Off'
                      : '${controller.imageGenGpuGuardMb.value} MB',
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      color:
                          isDark ? const Color(0xFFB9F53E) : AppColors.primary,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
          Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('set_gpu_experimental_detail'.tr,
                  style: GoogleFonts.inter(
                      fontSize: 12, color: Theme.of(context).hintColor))),
          Slider(
              value:
                  controller.imageGenGpuGuardMb.value.toDouble().clamp(0, 4096),
              min: 0,
              max: 4096,
              divisions: 16,
              activeColor: isDark ? const Color(0xFFB9F53E) : AppColors.primary,
              onChanged: (v) => controller.setImageGenGpuGuardMb(v.toInt())),
          if (controller.imageGenGpuGuardMb.value <= 0 ||
              controller.imageGenGpuGuardMb.value > 2048)
            Container(
                margin: const EdgeInsets.only(top: 2, bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 14, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(
                          controller.imageGenGpuGuardMb.value <= 0
                              ? 'set_gpu_safety_off'.tr: 'set_gpu_safety_high'.tr,
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.warning,
                              fontWeight: FontWeight.w400))),
                ])),
        ]),
      ),
      const Divider(height: 1, indent: 16, endIndent: 16),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _iconBox(
                isDark ? const Color(0xFFB9F53E) : AppColors.primary,
                selectedBackend == Backend.cpu
                    ? Icons.memory_rounded
                    : Icons.bolt_rounded),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('image_backend'.tr,
                        style: GoogleFonts.inter(
                            fontSize: 15, fontWeight: FontWeight.w400)),
                    const SizedBox(height: 3),
                    Text(controller.imageGpuLabel(),
                        style: GoogleFonts.inter(
                            fontSize: 12, color: Theme.of(context).hintColor)),
                  ]),
            ),
          ]),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                    value: false,
                    icon: Icon(Icons.memory_rounded, size: 16),
                    label: Text('cpu'.tr)),
                ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.bolt_rounded, size: 16),
                    label: Text(
                      'GPU',
                      style: TextStyle(
                        color: selectedBackend == Backend.cpu
                            ? const Color(0xFFFF6B6B)
                            : Colors.white,
                      ),
                    )),
              ],
              selected: {selectedBackend != Backend.cpu},
              onSelectionChanged: (values) {
                final useGpu = values.first;
                if (useGpu && !gpuAvailable) return;
                controller.setImageBackendMode(useGpu);
              },
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: WidgetStatePropertyAll(GoogleFonts.inter(
                    fontSize: 12, fontWeight: FontWeight.w500)),
              ),
            ),
          ),
          if (selectedBackend != Backend.cpu) ...[
            const SizedBox(height: 6),
            Text('gpu_is_experimental'.tr,
                style: GoogleFonts.inter(
                    fontSize: 11,
                    color: const Color(0xFFFF6B6B),
                    fontWeight: FontWeight.w500)),
          ],
        ]),
      ),
    ]);
  }

  /// Seletor de idioma: **auto**, inglês ou português do Brasil.
  ///
  /// **Três opções e nenhum `Switch`**, porque não são dois estados: `auto` não é
  /// "português desligado", é uma terceira coisa que se decide sozinha. Um par de
  /// botões de radio deixa a diferença visível — quem escolhe `auto` precisa de
  /// poder dizer o que ele faz, e é a linha de detalhe embaixo do valor.
  ///
  /// **Os rótulos NÃO passam por `.tr`**, e é deliberado: o nome de um idioma é
  /// o dado, e um dado traduzido deixa de identificar o idioma. Em português o
  /// item diz "Português (Brasil)"; em inglês diz "Portuguese (Brazil)". Um
  /// rótulo localizado diria "Inglês" dentro de uma lista de Idiomas e quem lê em
  /// inglês não reconheceria o próprio idioma.
  ///
  /// **A troca vale na hora**, por `Get.updateLocale`, e o card inteiro se
  /// reconstrói junto — inclusive o título desta seção, que é a prova visível de
  /// que funcionou. Um idioma que só muda no próximo cold start parece quebrado.

  /// A legenda do tile de voltas de ferramenta, nos dois idiomas.
  ///
  /// **Duas chaves, uma para cada contagem, e o número entra por cima.** A
  /// alternativa seria uma chave só com `@n` e `trParams`, que é o padrão do
  /// GetX — mas o **plural** ficaria em português e em inglês ao mesmo tempo, e
  /// uma chave só teria de escolher. Um literal interpolado é recusado pelo filtro
  /// de idioma de propósito (`TextLanguage.looksEnglish` devolve falso para
  /// qualquer `$`), então o que sobra é a chave por forma.
  String _agentHopSubtitle(int maxHops) {
    final chave = maxHops == 1 ? 'set_hops_one' : 'set_hops_many';
    return chave.tr.replaceAll('@n', '$maxHops');
  }

  Widget _buildLanguageCard(BuildContext context, bool isDark) {
    final accent = Theme.of(context).colorScheme.primary;
    final escolha = controller.language.value;
    final locale = Get.locale;

    // O detalhe muda com a escolha porque é a parte que responde "o que isso
    // faz por mim" — e em `auto` a resposta depende do aparelho, não da tela.
    final detalhe = escolha == LanguagePreference.auto
        ? (LanguagePreference.ehPortugues(Get.deviceLocale)
            ? 'language_auto_detail_pt'.tr
            : 'language_auto_detail_en'.tr)
        : escolha == LanguagePreference.english
            ? 'language_english_detail'.tr
            : 'language_portuguese_brazil_detail'.tr;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.translate_rounded, size: 16, color: accent),
            const SizedBox(width: 8),
            Text('language'.tr,
                style: GoogleFonts.inter(
                    fontSize: 15, fontWeight: FontWeight.w400)),
            const Spacer(),
            Text(
              LanguagePreference.rotulo(escolha, locale),
              style: GoogleFonts.inter(
                  fontSize: 13, color: accent, fontWeight: FontWeight.w600),
            ),
          ]),
          const SizedBox(height: 4),
          Text(detalhe,
              style: GoogleFonts.inter(
                  fontSize: 12, color: Theme.of(context).hintColor)),
          const SizedBox(height: 10),
          // `Wrap` e nao `Row`: os tres rotulos nao cabem numa linha de 360 dp
          // com o texto no tamanho que este app permite, e o `AGENTS.md` já
          // pagou por `Row` sem `Expanded` em quatro lugares. Ver também
          // `test/row_overflow_audit_test.dart`.
          Wrap(
            spacing: 8,
            children: [
              for (final opcao in LanguagePreference.opcoes)
                ChoiceChip(
                  selected: escolha == opcao,
                  onSelected: (_) => controller.setLanguage(opcao),
                  label: Text(LanguagePreference.rotulo(opcao, locale),
                      style: GoogleFonts.inter(fontSize: 13)),
                  selectedColor: accent.withValues(alpha: 0.18),
                  labelStyle: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight:
                        escolha == opcao ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFontSizeCard(BuildContext context, bool isDark) {
    const min = 0.8;
    const max = 1.4;
    final accent = isDark ? const Color(0xFFB9F53E) : const Color(0xFFB9F53E);

    String scaleLabel(double v) {
      if (v <= 0.85) return 'XS';
      if (v <= 0.95) return 'small'.tr;
      if (v <= 1.05) return 'Recommended';
      if (v <= 1.15) return 'large'.tr;
      if (v <= 1.25) return 'XL';
      return 'XXL';
    }

    return _appleGroupedCard(context, isDark, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.format_size_rounded, size: 16, color: accent),
            const SizedBox(width: 8),
            Text('font_size'.tr,
                style: GoogleFonts.inter(
                    fontSize: 15, fontWeight: FontWeight.w400)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(scaleLabel(controller.fontScale.value),
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      color: accent,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 4),
          Text('default_size'.tr,
              style: GoogleFonts.inter(
                  fontSize: 12, color: Theme.of(context).hintColor)),
          Slider(
            value: controller.fontScale.value.clamp(min, max),
            min: min,
            max: max,
            divisions: 12,
            activeColor: accent,
            onChanged: (v) => controller.setFontScale(v),
          ),
          // Scale markers
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('XS',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: Theme.of(context).hintColor)),
                Text('small'.tr,
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        color: controller.fontScale.value >= 0.9 &&
                                controller.fontScale.value <= 0.95
                            ? accent
                            : Theme.of(context).hintColor,
                        fontWeight: controller.fontScale.value >= 0.9 &&
                                controller.fontScale.value <= 0.95
                            ? FontWeight.w600
                            : FontWeight.w400)),
                Text('large'.tr,
                    style: GoogleFonts.inter(
                        fontSize: 11, color: Theme.of(context).hintColor)),
              ],
            ),
          ),
        ]),
      ),
    ]);
  }

  /// Slider panel with every open-weight sampler knob. Lives under Text
  /// Generation; values apply from the next generation on.
  /// What the closed group shows. The three sampler values, because they are the
  /// ones a reader wants to check without opening anything, and the context size
  /// because that is the value that has to be right before a long prompt, and it
  /// is silently clamped for LiteRT models.
  String _textParametersSubtitle() {
    return 'temp ${controller.temperature.value.toStringAsFixed(2)}'
        ' · top-p ${controller.topP.value.toStringAsFixed(2)}'
        ' · top-k ${controller.topK.value}'
        ' · ctx ${controller.contextSize.value}';
  }

  /// The sampling body, no group around it.
  ///
  /// It used to return its own `_CollapsibleGroup` titled "Parameters" and live
  /// inside the "Text generation" group, which put a collapsible card inside a
  /// collapsible card and a second "Parameters" heading on a screen that has three
  /// encoder groups below it. The wrapper now belongs to the caller, so this is
  /// just the contents.
  ///
  /// `stretch` because `_CollapsibleGroup` lays children out in a `Column` with
  /// the default `center` cross axis, and a plain `Column` here would shrink-wrap
  /// itself around the widest slider instead of filling the row.
  Widget _buildParametersPanel(BuildContext context, bool isDark) {
    final accent = isDark ? const Color(0xFF0A84FF) : AppColors.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _modelParameterSlider(
          context,
          isDark,
          label: 'Temperature',
          value: controller.temperature.value,
          min: 0.0,
          max: 2.0,
          divisions: 40,
          safeMax: 1.0,
          onChanged: (v) => controller.setTemperature(v),
          icon: Icons.thermostat_rounded,
          warning: 'High temperature = unpredictable output!',
        ),
        _parameterDivider(isDark),
        _modelParameterSlider(
          context,
          isDark,
          label: 'Top P',
          value: controller.topP.value,
          min: 0.05,
          max: 1.0,
          divisions: 19,
          safeMax: 1.0,
          onChanged: (v) => controller.setTopP(v),
          displayValue: controller.topP.value.toStringAsFixed(2),
          icon: Icons.percent_rounded,
          warning: '',
        ),
        _parameterDivider(isDark),
        _modelParameterSlider(
          context,
          isDark,
          label: 'Top K',
          value: controller.topK.value.toDouble(),
          min: 1,
          max: 200,
          divisions: 199,
          safeMax: 200,
          onChanged: (v) => controller.setTopK(v.toInt()),
          displayValue: controller.topK.value.toString(),
          icon: Icons.filter_alt_rounded,
          warning: '',
        ),
        _parameterDivider(isDark),
        _modelParameterSlider(
          context,
          isDark,
          label: 'Min P',
          value: controller.minP.value,
          min: 0.0,
          max: 0.5,
          divisions: 25,
          safeMax: 0.5,
          onChanged: (v) => controller.setMinP(v),
          displayValue: controller.minP.value.toStringAsFixed(2),
          icon: Icons.vertical_align_bottom_rounded,
          warning: '',
        ),
        _parameterDivider(isDark),
        _modelParameterSlider(
          context,
          isDark,
          label: 'Repeat Penalty',
          value: controller.repeatPenalty.value,
          min: 1.0,
          max: 2.0,
          divisions: 40,
          safeMax: 1.3,
          onChanged: (v) => controller.setRepeatPenalty(v),
          icon: Icons.repeat_rounded,
          warning: 'High penalty degrades fluency!',
        ),
        _parameterDivider(isDark),
        (() {
          final cores = Platform.numberOfProcessors;
          // Read the same topology the loader reads, so this label describes what
          // will actually happen. It used to say "half the cores" and promise
          // "Leaves the little cores out of the sync barrier", which on a Galaxy
          // A72 was the opposite of the truth: half of eight is cpu0-3 and all
          // four of those are A55, so the default took the little cores *into*
          // the barrier. A label that overstates what the code does is worse than
          // no label, because it is what stops anyone from suspecting it.
          final bigCores =
              bigCoreCount(readMaxFreqPerCoreSync(), totalCores: cores);
          final selected = controller.cpuThreads.value;
          final options = <({int value, String title, String subtitle})>[
            (
              value: 0,
              title: preencher('set_threads_auto', {'n': '$bigCores'}),
              subtitle: bigCores >= cores
                  ? 'set_all_cores_big_detail'.tr
                  : preencher('set_cores_left_out', {'n': '${cores - 1}'}),
            ),
            (
              value: cores,
              title: 'Threads: All cores ($cores)',
              subtitle: 'set_more_threads_detail'.tr,
            ),
          ];
          return _appleGroupedCard(context, isDark, children: [
            for (var i = 0; i < options.length; i++)
              _appleListTile(
                context,
                isDark,
                leading: _iconBox(accent, Icons.developer_board_rounded),
                title: options[i].title,
                subtitle: options[i].subtitle,
                trailing: selected == options[i].value
                    ? Icon(Icons.check, size: 18, color: accent)
                    : null,
                showDivider: i < options.length - 1,
                onTap: () => controller.setCpuThreads(options[i].value),
              ),
          ]);
        })(),
        _parameterDivider(isDark),
        _maxTokensContextSliders(context, isDark),
      ],
    );
  }

  /// The two RAM-sensitive sliders (Max Tokens, Context Size), unchanged in
  /// behaviour — including the manual-entry dialogs behind the value chips.
  Widget _maxTokensContextSliders(BuildContext context, bool isDark) {
    return Column(children: [
      _modelParameterSlider(
        context,
        isDark,
        label: 'Max Tokens',
        value: controller.maxTokens.value.toDouble(),
        min: 64,
        max: 4096,
        divisions: 63,
        safeMax: Get.find<DeviceInfoService>().maxSafeTokens.toDouble(),
        onChanged: (v) => controller.setMaxTokens(v.toInt()),
        displayValue: controller.maxTokens.value.toString(),
        icon: Icons.tag_rounded,
        warning: 'set_ctx_may_crash'.tr,
        onTapValue: () {
          SettingsController.showManualEntryDialog(
            context: context,
            field: 'maxTokens',
            label: 'Max Tokens',
            currentValue: controller.maxTokens.value,
            min: 64,
            max: SettingsController.maxManualMaxTokens,
            warningThreshold: SettingsController.memoryWarningThreshold,
            warningMessage:
                'set_ctx_warning'.tr,
            controller: controller,
            onApplied: () {},
          );
        },
      ),
      _parameterDivider(isDark),
      (() {
        final inference = Get.find<InferenceService>();
        final savedRuntime = Get.find<HiveService>()
                .getSetting<String>(AppConstants.keyLocalModelRuntime) ??
            '';
        final isLiteRtActive = (inference.isModelLoaded.value &&
                inference.loadedModelRuntime.value == 'litert') ||
            (!inference.isModelLoaded.value &&
                savedRuntime.toLowerCase() == 'litert');
        final saved = controller.contextSize.value.toDouble();
        final maxContext =
            isLiteRtActive ? 4096.0 : (saved > 8192.0 ? saved : 8192.0);
        final divisions = isLiteRtActive ? 7 : (maxContext ~/ 512) - 1;
        final currentValue = saved.clamp(512.0, maxContext);

        if (isLiteRtActive && currentValue != saved) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            controller.setContextSize(currentValue.toInt());
          });
        }

        return _modelParameterSlider(
          context,
          isDark,
          label: 'set_context_size_a'.tr,
          value: currentValue,
          min: 512,
          max: maxContext,
          divisions: divisions,
          safeMax: Get.find<DeviceInfoService>().maxSafeContextSize.toDouble(),
          onChanged: (v) => controller.setContextSize(v.toInt()),
          displayValue: currentValue.toInt().toString(),
          icon: Icons.memory_rounded,
          warning: isLiteRtActive
              ? 'set_ctx_capped'.tr: 'set_ctx_all_ram'.tr,
          onTapValue: () {
            SettingsController.showManualEntryDialog(
              context: context,
              field: 'contextSize',
              label: 'set_context_size_a'.tr,
              currentValue: controller.contextSize.value,
              min: 512,
              max: SettingsController.maxManualContextSize,
              warningThreshold: SettingsController.memoryWarningThreshold,
              warningMessage:
                  'set_ctx_warning'.tr,
              controller: controller,
              onApplied: () {},
            );
          },
        );
      })(),
    ]);
  }

  /// Workspace root: shows status and lets the user set it up or relocate it.
  Widget _buildWorkspaceCard(BuildContext context, bool isDark) {
    final workspace = Get.find<WorkspaceService>();
    return _appleGroupedCard(context, isDark, children: [
      Obx(() {
        final ready = workspace.isReady;
        return Column(children: [
          _appleListTile(
            context,
            isDark,
            leading: _iconBox(
                ready ? const Color(0xFFB9F53E) : const Color(0xFF8B7CFF),
                ready ? Icons.workspaces_outlined : Icons.workspaces_rounded),
            title: ready
                ? 'set_workspace_folder'.tr
                : 'set_workspace_not_set_up'.tr,
            subtitle: ready
                ? (workspace.treeUri.value ?? '')
                : 'set_workspace_pick_detail'.tr,
            showDivider: workspace.supported,
            onTap: workspace.supported
                ? () async {
                    if (!ready) {
                      await workspace.pickWorkspace();
                    } else {
                      await _relocateWorkspace(context, workspace);
                    }
                  }
                : null,
          ),
          if (workspace.supported && ready)
            _appleListTile(
              context,
              isDark,
              leading: _iconBox(
                  const Color(0xFFFF9500), Icons.drive_file_move_outlined),
              title: 'set_change_folder'.tr,
              subtitle: 'set_change_folder_detail2'.tr,
              trailing: const Icon(Icons.chevron_right, size: 18),
              showDivider: false,
              onTap: () => _relocateWorkspace(context, workspace),
            ),
        ]);
      }),
    ]);
  }

  Future<void> _relocateWorkspace(
      BuildContext context, WorkspaceService workspace) async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: Text('change_workspace_folder'.tr),
        content: Text('set_change_folder_detail'.tr),
        actions: [
          TextButton(
              onPressed: () => Get.back(result: false),
              child: Text('cancel'.tr)),
          FilledButton(
              onPressed: () => Get.back(result: true),
              child: Text('continue'.tr)),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await workspace.relocateWorkspace();
    Get.snackbar(
      'Workspace',
      ok ? 'set_ws_moved'.tr: 'set_ws_move_failed'.tr,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  /// Downloaded model files: name and size, straight from the download dir.
  Widget _buildStorageCard(BuildContext context, bool isDark) {
    return FutureBuilder<List<String>>(
      future: () async {
        final dir = await Get.find<DownloadService>().modelsDir;
        // The listing returns bare names; resolve them so sizes are real.
        final names = await Get.find<DownloadService>().getDownloadedModels();
        return names.map((n) => '$dir/$n').toList();
      }(),
      builder: (context, snap) {
        final files = snap.data ?? const <String>[];
        return _appleGroupedCard(context, isDark, children: [
          if (snap.connectionState != ConnectionState.done && files.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (files.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('no_models_downloaded_yet'.tr,
                  style: GoogleFonts.inter(
                      fontSize: 13, color: Theme.of(context).hintColor)),
            )
          else
            for (var i = 0; i < files.length; i++)
              _appleListTile(
                context,
                isDark,
                leading: _iconBox(
                    const Color(0xFF5856D6), Icons.insert_drive_file_outlined),
                title: files[i].split('/').last,
                subtitle: () {
                  try {
                    final f = File(files[i]);
                    final mb =
                        (f.existsSync() ? f.lengthSync() : 0) / (1024 * 1024);
                    return '${mb.toStringAsFixed(0)} MB';
                  } catch (_) {
                    return '—';
                  }
                }(),
                showDivider: i < files.length - 1,
              ),
          Obx(() {
            final mc = Get.find<ModelController>();
            final backing = mc.isBackingUp.value;
            final overall = mc.backupTotalBytes.value > 0
                ? (mc.backupCopiedBytes.value / mc.backupTotalBytes.value)
                : null;
            return Column(children: [
              if (backing) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(children: [
                    const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${mc.backupDoneFiles.value}/${mc.backupTotalFiles.value}'
                        ' · ${mc.backupFile.value}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 13),
                      ),
                    ),
                    Text(
                      '${(mc.backupCopiedBytes.value / (1024 * 1024)).toStringAsFixed(0)}'
                      '/${(mc.backupTotalBytes.value / (1024 * 1024)).toStringAsFixed(0)} MB',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: Theme.of(context).hintColor),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: LinearProgressIndicator(value: overall),
                ),
              ],
              _appleListTile(
                context,
                isDark,
                leading: _iconBox(AppColors.success, Icons.save_as_outlined),
                title: backing ? 'Backing up…' : 'set_backup_configs'.tr,
                subtitle: backing
                    ? 'set_keep_screen_open'.tr
                    : 'set_settings_template_files'.tr,
                trailing:
                    backing ? null : const Icon(Icons.chevron_right, size: 18),
                showDivider: true,
                onTap: backing ? null : () => _showBackupSheet(context),
              ),
              // Always offered: restoring a config backup into a fresh
              // install is exactly when it is needed.
              _appleListTile(
                context,
                isDark,
                leading:
                    _iconBox(const Color(0xFFFF9500), Icons.restore_rounded),
                title: 'set_restore_backup'.tr,
                subtitle: 'set_apply_template_detail'.tr,
                trailing: const Icon(Icons.chevron_right, size: 18),
                showDivider: false,
                onTap: () => _showRestoreSheet(context),
              ),
            ]);
          }),
        ]);
      },
    );
  }

  Widget _parameterDivider(bool isDark) {
    return Divider(
      height: 1,
      indent: 16,
      endIndent: 16,
      color: isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.black.withValues(alpha: 0.06),
    );
  }

  Widget _modelParameterSlider(
    BuildContext context,
    bool isDark, {
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required double safeMax,
    required ValueChanged<double> onChanged,
    required IconData icon,
    required String warning,
    String? displayValue,
    VoidCallback? onTapValue,
  }) {
    final isOver = value > safeMax;
    final danger = safeMax < max
        ? ((value - safeMax) / (max - safeMax)).clamp(0.0, 1.0)
        : 0.0;
    final accent = isOver
        ? Color.lerp(AppColors.warning, AppColors.error, danger)!
        : (isDark ? const Color(0xFFB9F53E) : AppColors.primary);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 8),
          Text(label,
              style:
                  GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w400)),
          GestureDetector(
            onTap: onTapValue,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(displayValue ?? value.toStringAsFixed(2),
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      color: accent,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
        if (safeMax < max)
          Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  'Recommended max: ${safeMax.toInt() > 0 ? safeMax.toInt().toString() : safeMax.toStringAsFixed(1)}',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: Theme.of(context).hintColor))),
        Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            activeColor: accent,
            onChanged: (v) {
              if (v > safeMax && value <= safeMax) {
                HapticFeedback.heavyImpact();
                Get.snackbar('set_warning_title'.tr, warning,
                    snackPosition: SnackPosition.BOTTOM,
                    backgroundColor: AppColors.error.withValues(alpha: 0.9),
                    colorText: Colors.white,
                    duration: const Duration(seconds: 3),
                    margin: const EdgeInsets.all(12));
              } else if (v > safeMax) {
                HapticFeedback.mediumImpact();
              }
              onChanged(v);
            }),
        if (isOver)
          Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded, size: 14, color: accent),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(warning,
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: accent,
                            fontWeight: FontWeight.w400))),
              ])),
      ]),
    );
  }

  /// A chave do modo de tema; o `.tr` é no call site.
  ///
  /// Devolver o texto já traduzido aqui congelaria o idioma: `title:` recebe a
  /// string pronta e não teria onde traduzir. E `_themeModeName` é chamada de
  /// um `build`, não de um `const`, então o valor continua sendo reavaliado a
  /// cada quadro.
  String _themeModeName(ThemeMode m) => m == ThemeMode.light
      ? 'theme_light'
      : m == ThemeMode.dark
          ? 'theme_dark'
          : 'theme_system';
  IconData _themeModeIcon(ThemeMode m) => m == ThemeMode.light
      ? Icons.wb_sunny_outlined
      : m == ThemeMode.dark
          ? Icons.dark_mode_outlined
          : Icons.brightness_auto_outlined;
}

Future<void> _showBackupSheet(BuildContext context) async {
  final mc = Get.find<ModelController>();
  var includeModels = false;
  final selected = <String>{};
  // Built once: recreating it inside StatefulBuilder would re-run the
  // FutureBuilder on every toggle, and its empty-guard would then refill
  // the selection the user had just cleared ("None" looked broken).
  final namesFuture = Get.find<DownloadService>().getDownloadedModels();
  var autoSelectDone = false;
  await showModalBottomSheet(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setSheet) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('backup_configs'.tr,
                  style: GoogleFonts.inter(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('set_backup_detail'.tr,
                  style: GoogleFonts.inter(
                      fontSize: 12, color: Theme.of(context).hintColor)),
              const SizedBox(height: 10),
              CheckboxListTile(
                value: includeModels,
                onChanged: (v) => setSheet(() => includeModels = v ?? false),
                title: Text('include_model_files'.tr),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              if (includeModels)
                Flexible(
                  child: FutureBuilder<List<String>>(
                    future: namesFuture,
                    builder: (context, snap) {
                      final names = snap.data ?? const <String>[];
                      if (!autoSelectDone && names.isNotEmpty) {
                        autoSelectDone = true;
                        selected.addAll(names);
                      }
                      return Column(children: [
                        Row(children: [
                          TextButton(
                              onPressed: () =>
                                  setSheet(() => selected.addAll(names)),
                              child: Text('all'.tr)),
                          TextButton(
                              onPressed: () => setSheet(selected.clear),
                              child: Text('none'.tr)),
                        ]),
                        SizedBox(
                          height: 180,
                          child: ListView(children: [
                            for (final n in names)
                              CheckboxListTile(
                                dense: true,
                                value: selected.contains(n),
                                title: Text(n,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                onChanged: (v) => setSheet(() =>
                                    v! ? selected.add(n) : selected.remove(n)),
                              ),
                          ]),
                        ),
                      ]);
                    },
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.backup_outlined),
                  label: Text('start_backup'.tr),
                  onPressed: () {
                    Navigator.pop(ctx);
                    mc.backupConfigs(
                      includeModels: includeModels,
                      modelFiles: Set<String>.from(selected),
                    );
                  },
                ),
              ),
            ]),
          ),
        );
      });
    },
  );
}

Future<void> _showRestoreSheet(BuildContext context) async {
  final mc = Get.find<ModelController>();
  await showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('restore_backup'.tr,
              style:
                  GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore_rounded),
            title: Text('everything_configs___models'.tr),
            subtitle: Text('set_backup_restore_detail'.tr),
            onTap: () {
              Navigator.pop(ctx);
              mc.restoreEverything();
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_suggest_outlined),
            title: Text('configs_template_json'.tr),
            subtitle: Text('overwrites_current_settings'.tr),
            onTap: () {
              Navigator.pop(ctx);
              mc.restoreConfigs();
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_copy_outlined),
            title: Text('model_files_from_the_backup_folder'.tr),
            subtitle: Text('skips_files_already_present_and_identica'.tr),
            onTap: () {
              Navigator.pop(ctx);
              mc.restoreModelsFromBackup();
            },
          ),
        ]),
      ),
    ),
  );
}

class _CollapsibleGroup extends StatefulWidget {
  final bool isDark;
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  const _CollapsibleGroup({
    required this.isDark,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.children,
  });

  @override
  State<_CollapsibleGroup> createState() => _CollapsibleGroupState();
}

class _CollapsibleGroupState extends State<_CollapsibleGroup> {
  bool _open = false;

  Color get _accent =>
      widget.isDark ? const Color(0xFF0A84FF) : AppColors.primary;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              _iconBoxFor(context),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.title,
                          style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color:
                                  widget.isDark ? Colors.white : Colors.black)),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(widget.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Theme.of(context).hintColor)),
                      ],
                    ]),
              ),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(Icons.expand_more_rounded,
                    size: 20, color: Theme.of(context).hintColor),
              ),
            ]),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          sizeCurve: Curves.easeInOut,
          crossFadeState:
              _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Column(mainAxisSize: MainAxisSize.min, children: [
            const Divider(height: 0.5, indent: 16, endIndent: 16),
            ...widget.children,
          ]),
        ),
      ]),
    );
  }

  Widget _iconBoxFor(BuildContext context) {
    return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
            color: _accent.withValues(alpha: widget.isDark ? 0.22 : 0.12),
            borderRadius: BorderRadius.circular(7)),
        child: Icon(widget.icon, size: 17, color: _accent));
  }
}
