import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_litert_lm/flutter_litert_lm.dart';
import '../controllers/settings_controller.dart';
import '../core/colors.dart';
import '../core/constants.dart';
import '../services/inference_service.dart';
import '../controllers/model_controller.dart';
import '../services/download_service.dart';
import '../services/hive_service.dart';
import '../services/local_image_service.dart';
import '../services/device_info_service.dart';
import '../services/tools/builtin_tools.dart';
import '../services/device_info_native.dart' as platform_info;
import '../ffi/sd_ffi_bindings.dart';
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
        title: Text('Settings',
            style:
                GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 34)),
        toolbarHeight: 56,
      ),
      body: Obx(() => ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              const SizedBox(height: 8),
              _sectionLabel(context, 'APPEARANCE'),
              _CollapsibleGroup(
                isDark: isDark,
                icon: Icons.palette_outlined,
                title: 'Appearance',
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
                      title: _themeModeName(mode),
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
                ],
              ),
              const SizedBox(height: 16),
              _sectionLabel(context, 'INFERENCE MODE'),
              _appleGroupedCard(context, isDark, children: [
                _appleListTile(
                  context,
                  isDark,
                  leading:
                      _iconBox(AppColors.success, Icons.phone_iphone_rounded),
                  title: 'Local (On-Device)',
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
                  title: 'Cloud API',
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
              _sectionLabel(context, 'MODEL SETTINGS'),
              _CollapsibleGroup(
                isDark: isDark,
                icon: Icons.tune_rounded,
                title: 'Default System Prompt',
                subtitle: 'Applies to local and cloud models',
                children: [
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: TextField(
                      controller: controller.globalSystemPromptController,
                      minLines: 3,
                      maxLines: 6,
                      style: GoogleFonts.inter(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: AppConstants.systemPrompt,
                        suffixIcon: IconButton(
                            icon: const Icon(Icons.check_circle_outline,
                                size: 20),
                            onPressed: () => controller.setGlobalSystemPrompt(
                                controller
                                    .globalSystemPromptController.text)),
                      ),
                      onSubmitted: (v) =>
                          controller.setGlobalSystemPrompt(v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _CollapsibleGroup(
                isDark: isDark,
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Text Generation',
                subtitle: controller.liteRtPerformanceMode.value == 'auto_fast'
                    ? 'Auto Fast · thinking ${controller.thinkingMode.value}'
                    : '${controller.liteRtPerformanceMode} · thinking ${controller.thinkingMode.value}',
                children: [
                  _buildLiteRtCard(context, isDark),
                  const Divider(height: 0.5, indent: 16),
                  _buildParametersPanel(context, isDark),
                  const Divider(height: 0.5, indent: 16),
                  _buildThinkingCard(context, isDark),
                  const Divider(height: 0.5, indent: 16),
                  _buildComputeCard(context, isDark),
                  const Divider(height: 0.5, indent: 16),
                  _buildToolsCard(context, isDark),
                ],
              ),
              const SizedBox(height: 10),
              _CollapsibleGroup(
                isDark: isDark,
                icon: Icons.image_outlined,
                title: 'Image Generation',
                subtitle:
                    '${controller.imageSteps.value} steps · ${controller.imageGenSize.value == 0 ? "auto size" : "${controller.imageGenSize.value}px"}',
                children: [_buildImageGenerationCard(context, isDark)],
              ),
              const SizedBox(height: 24),
              _sectionLabel(context, 'DEVICE INFORMATION'),
              _buildDeviceCard(context, isDark),
              const SizedBox(height: 10),
              if (Platform.isAndroid) _buildNpuCard(context, isDark),
              const SizedBox(height: 24),
              _sectionLabel(context, 'STORAGE'),
              _buildStorageCard(context, isDark),
              const SizedBox(height: 24),
              _sectionLabel(context, 'DIAGNOSTICS'),
              _appleGroupedCard(context, isDark, children: [
                _appleListTile(
                  context,
                  isDark,
                  leading:
                      _iconBox(const Color(0xFF5AC8FA), Icons.article_outlined),
                  title: 'Logs',
                  subtitle: 'View errors, warnings, and debug details',
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  showDivider: false,
                  onTap: () => Get.to(() => const LogView()),
                ),
              ]),
              const SizedBox(height: 24),
              _sectionLabel(context, 'ABOUT'),
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
                          Text('mobileLM',
                              style: GoogleFonts.inter(
                                  fontSize: 17, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                              controller.appVersion.value.isEmpty
                                  ? 'Version unavailable · by orailnoor'
                                  : 'v${controller.appVersion.value} · by orailnoor',
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

  Widget _sectionLabel(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 6),
      child: Text(title,
          style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w400,
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
    return 'No model loaded';
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
                    Text(
                        'Available: ${device.availableRamGB.value.toStringAsFixed(1)}GB · Context: ${device.recommendedContextSize} · Tokens: ${device.recommendedMaxTokens}',
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
  Widget _buildToolsCard(BuildContext context, bool isDark) {
    final enabled = controller.toolsEnabled.value;
    final accent = isDark ? const Color(0xFFB9F53E) : AppColors.primary;
    final catalogue = buildDefaultToolRegistry().all.toList();
    final on = controller.enabledTools;

    return _appleGroupedCard(context, isDark, children: [
      _appleListTile(
        context,
        isDark,
        leading: _iconBox(accent, Icons.handyman_rounded),
        title: 'Tools',
        subtitle: enabled
            ? '${on.length} of ${catalogue.length} enabled'
            : 'Off — the tool list is kept out of the prompt',
        trailing: enabled ? Icon(Icons.check, size: 18, color: accent) : null,
        showDivider: enabled,
        onTap: () => controller.setToolsEnabled(!enabled),
      ),
      if (enabled)
        for (var i = 0; i < catalogue.length; i++)
          _appleListTile(
            context,
            isDark,
            leading: _iconBox(
                catalogue[i].requiresNetwork ? AppColors.warning : accent,
                catalogue[i].requiresNetwork
                    ? Icons.public_rounded
                    : Icons.offline_bolt_rounded),
            title: catalogue[i].name,
            subtitle: catalogue[i].requiresNetwork
                ? 'Needs internet — ${catalogue[i].description}'
                : catalogue[i].description,
            trailing: on.contains(catalogue[i].name)
                ? Icon(Icons.check, size: 18, color: accent)
                : null,
            showDivider: i < catalogue.length - 1,
            onTap: () => controller.toggleTool(
                catalogue[i].name, !on.contains(catalogue[i].name)),
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
          'Optional. Empty means Brave → Startpage → DuckDuckGo.',
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
            labelText: 'Custom search API URL',
            hintText: 'https://searx.example.org/search',
            suffixIcon: IconButton(
              icon: const Icon(Icons.check_circle_outline, size: 20),
              onPressed: () => controller
                  .setCustomSearchUrl(controller.customSearchUrlController.text),
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
            labelText: 'Custom search API token',
            hintText: 'leave empty for SearXNG',
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
              ? 'Using the scrape chain.'
              : 'Using ${controller.customSearchUrl.value}'
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
        subtitle: "Send nothing — the model's own default",
        icon: Icons.auto_awesome_rounded
      ),
      (
        value: 'on',
        title: 'Thinking: On',
        subtitle: 'Ask for reasoning before the answer (/think)',
        icon: Icons.psychology_rounded
      ),
      (
        value: 'off',
        title: 'Thinking: Off',
        subtitle: 'Answer directly, no reasoning (/no_think)',
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
                ? 'Projector runs on the CPU even when layers are on the GPU'
                : 'Auto — benchmarked once, faster backend kept',
            trailing: controller.mmprojForceCpu.value
                ? Icon(Icons.check, size: 18, color: accent)
                : null,
            showDivider: false,
            onTap: () =>
                controller.setMmprojForceCpu(!controller.mmprojForceCpu.value),
          ),
        ]));
  }

  Widget _buildLiteRtCard(BuildContext context, bool isDark) {
    final modes = [
      (
        value: 'auto_fast',
        title: 'Auto Fast',
        subtitle: 'Try GPU first, then CPU fallback',
        icon: Icons.auto_awesome_rounded
      ),
      (
        value: 'gpu_fast',
        title: 'GPU Fast',
        subtitle: 'Maximum speed, may crash on some devices',
        icon: Icons.bolt_rounded
      ),
      (
        value: 'cpu_safe',
        title: 'CPU Safe',
        subtitle: 'Stable mode with lower speed',
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
            Text('Image Gen Steps',
                style: GoogleFonts.inter(
                    fontSize: 15, fontWeight: FontWeight.w400)),
            const Spacer(),
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
              child: Text('Recommended max: 8',
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
                      child: Text(
                          'More steps = better quality but MUCH slower!',
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
            Text('Image Size',
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
              child: Text(
                  'Auto recommended. Bigger size = better detail, but much slower and more memory use.',
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
                      child: Text(
                          '512 gives more detail but can be MUCH slower, heat the phone, and may fail on some devices.',
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
            Text('GPU Safety',
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
              child: Text(
                  'Models at or above this size use CPU. Smaller models can use GPU Experimental.',
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
                              ? 'GPU Safety is off. Large models may crash or freeze on GPU.'
                              : 'High GPU Safety allows larger models on GPU and may crash, freeze, or overheat some phones.',
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
                    Text('Image Backend',
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
                const ButtonSegment(
                    value: false,
                    icon: Icon(Icons.memory_rounded, size: 16),
                    label: Text('CPU')),
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
            Text('GPU is experimental and only used below GPU Safety size.',
                style: GoogleFonts.inter(
                    fontSize: 11,
                    color: const Color(0xFFFF6B6B),
                    fontWeight: FontWeight.w500)),
          ],
        ]),
      ),
    ]);
  }

  Widget _buildFontSizeCard(BuildContext context, bool isDark) {
    const min = 0.8;
    const max = 1.4;
    final accent = isDark ? const Color(0xFFB9F53E) : const Color(0xFFB9F53E);

    String scaleLabel(double v) {
      if (v <= 0.85) return 'XS';
      if (v <= 0.95) return 'Small';
      if (v <= 1.05) return 'Recommended';
      if (v <= 1.15) return 'Large';
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
            Text('Font Size',
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
          Text('1.00x is the default size',
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
                Text('Small',
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
                Text('Large',
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
  Widget _buildParametersPanel(BuildContext context, bool isDark) {
    final accent = isDark ? const Color(0xFF0A84FF) : AppColors.primary;
    return _CollapsibleGroup(
      isDark: isDark,
      icon: Icons.tune_rounded,
      title: 'Parameters',
      subtitle:
          'temp ${controller.temperature.value.toStringAsFixed(2)} · top-p ${controller.topP.value.toStringAsFixed(2)} · top-k ${controller.topK.value}',
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
          final half = (cores ~/ 2).clamp(2, 6);
          final selected = controller.cpuThreads.value;
          final options = <({int value, String title, String subtitle})>[
            (
              value: 0,
              title: 'Threads: Auto — half the cores ($half)',
              subtitle: 'Leaves the little cores out of the sync barrier',
            ),
            (
              value: cores,
              title: 'Threads: All cores ($cores)',
              subtitle: 'More threads, but the slowest core paces every op',
            ),
          ];
          return _appleGroupedCard(context, isDark, children: [
            for (var i = 0; i < options.length; i++)
              _appleListTile(
                context,
                isDark,
                leading:
                    _iconBox(accent, Icons.developer_board_rounded),
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
        warning: 'Your phone may crash with this value!',
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
                'Warning: values above 8192 may cause your device to run out of memory. Continue only if your device has sufficient RAM.',
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
          label: 'Context Size',
          value: currentValue,
          min: 512,
          max: maxContext,
          divisions: divisions,
          safeMax: Get.find<DeviceInfoService>().maxSafeContextSize.toDouble(),
          onChanged: (v) => controller.setContextSize(v.toInt()),
          displayValue: currentValue.toInt().toString(),
          icon: Icons.memory_rounded,
          warning: isLiteRtActive
              ? 'Context capped at 4096 to prevent driver memory crash for LiteRT models.'
              : 'Context this large will eat all your RAM!',
          onTapValue: () {
            SettingsController.showManualEntryDialog(
              context: context,
              field: 'contextSize',
              label: 'Context Size',
              currentValue: controller.contextSize.value,
              min: 512,
              max: SettingsController.maxManualContextSize,
              warningThreshold: SettingsController.memoryWarningThreshold,
              warningMessage:
                  'Warning: values above 8192 may cause your device to run out of memory. Continue only if your device has sufficient RAM.',
              controller: controller,
              onApplied: () {},
            );
          },
        );
      })(),
    ]);
  }

  /// Downloaded model files: name and size, straight from the download dir.
  Widget _buildStorageCard(BuildContext context, bool isDark) {
    return FutureBuilder<List<String>>(
      future: () async {
        final dir = await Get.find<DownloadService>().modelsDir;
        // The listing returns bare names; resolve them so sizes are real.
        final names =
            await Get.find<DownloadService>().getDownloadedModels();
        return names.map((n) => '$dir/$n').toList();
      }(),
      builder: (context, snap) {
        final files = snap.data ?? const <String>[];
        return _appleGroupedCard(context, isDark, children: [
          if (snap.connectionState != ConnectionState.done &&
              files.isEmpty)
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
              child: Text('No models downloaded yet',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: Theme.of(context).hintColor)),
            )
          else
            for (var i = 0; i < files.length; i++)
              _appleListTile(
                context,
                isDark,
                leading: _iconBox(const Color(0xFF5856D6),
                    Icons.insert_drive_file_outlined),
                title: files[i].split('/').last,
                subtitle: () {
                  try {
                    final f = File(files[i]);
                    final mb = (f.existsSync()
                            ? f.lengthSync()
                            : 0) /
                        (1024 * 1024);
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
                ? (mc.backupCopiedBytes.value /
                    mc.backupTotalBytes.value)
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
                leading:
                    _iconBox(AppColors.success, Icons.save_as_outlined),
                title: backing ? 'Backing up…' : 'Backup configs…',
                subtitle: backing
                    ? 'Keep this screen open'
                    : 'Settings template · optional model files',
                trailing: backing
                    ? null
                    : const Icon(Icons.chevron_right, size: 18),
                showDivider: files.isNotEmpty,
                onTap: backing
                    ? null
                    : () => _showBackupSheet(context),
              ),
              if (files.isNotEmpty)
                _appleListTile(
                  context,
                  isDark,
                  leading: _iconBox(
                      const Color(0xFFFF9500), Icons.restore_rounded),
                  title: 'Restore backup…',
                  subtitle: 'Apply a config template · bring models back',
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
                      fontSize: 13, color: accent, fontWeight: FontWeight.w600)),
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
                Get.snackbar('âš ï¸ Warning', warning,
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

  String _themeModeName(ThemeMode m) => m == ThemeMode.light
      ? 'Light'
      : m == ThemeMode.dark
          ? 'Dark'
          : 'System Default';
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
                Text('Backup configs',
                    style: GoogleFonts.inter(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                    'Settings template (API keys never leave the device) '
                    'into a dated folder of your chosen location.',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: Theme.of(context).hintColor)),
                const SizedBox(height: 10),
                CheckboxListTile(
                  value: includeModels,
                  onChanged: (v) => setSheet(() => includeModels = v ?? false),
                  title: const Text('Include model files'),
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
                                child: const Text('All')),
                            TextButton(
                                onPressed: () => setSheet(selected.clear),
                                child: const Text('None')),
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
                                  onChanged: (v) => setSheet(() => v!
                                      ? selected.add(n)
                                      : selected.remove(n)),
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
                    label: const Text('Start backup'),
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
            Text('Restore backup',
                style: GoogleFonts.inter(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.settings_suggest_outlined),
              title: const Text('Configs template (.json)'),
              subtitle: const Text('Overwrites current settings'),
              onTap: () {
                Navigator.pop(ctx);
                mc.restoreConfigs();
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_copy_outlined),
              title: const Text('Model files from the backup folder'),
              subtitle: const Text('Skips files already present and identical'),
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
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                              color: widget.isDark
                                  ? Colors.white
                                  : Colors.black)),
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
          secondChild: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
