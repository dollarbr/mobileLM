import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobilelm/services/text_interpolation.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/cloud_model_controller.dart';
import '../controllers/model_controller.dart';
import 'hf_search_sheet.dart';
import '../controllers/settings_controller.dart';
import '../core/colors.dart';
import '../core/constants.dart';
import '../models/ai_model.dart';
import '../services/cpu_self_test.dart';
import '../services/cpu_self_test_service.dart';
import '../services/device_info_service.dart';
import '../services/memory_readout.dart';
import '../services/system_one.dart';
import '../services/download_service.dart';
import '../services/inference_service.dart';
import '../controllers/server_controller.dart';
import '../utils/server_auth.dart';
import 'litert_head_console.dart';
import 'system_one_console.dart';
import '../services/local_image_service.dart';

class ModelView extends GetView<ModelController> {
  const ModelView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('models'.tr,
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
        actions: [
          Obx(() {
            if (controller.modelScope.value != 'local') {
              return const SizedBox.shrink();
            }
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Search lives here and not only in the empty state: that is
                // where it used to be, so it vanished the moment the first
                // model was added — exactly when browsing for a second one
                // starts to make sense.
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'mv_search_hf'.tr,
                  onPressed: () => HfSearchSheet.show(context),
                ),
                IconButton(
                  icon: const Icon(Icons.add_link),
                  tooltip: 'add_model_url'.tr,
                  onPressed: () => _showAddUrlDialog(context),
                ),
                IconButton(
                  icon: const Icon(Icons.file_upload_outlined),
                  tooltip: 'mv_import_storage'.tr,
                  onPressed: () => controller.importModelFromStorage(),
                ),
              ],
            );
          }),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (controller.modelScope.value == 'local') {
            await controller.refreshDownloaded();
          }
        },
        color: AppColors.primary,
        child: Obx(() => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildScopeToggle(context),
                const SizedBox(height: 14),
                // Active model banner
                _buildActiveModelBanner(context),
                const SizedBox(height: 12),

                if (controller.modelScope.value == 'local') ...[
                  _buildImportingProgress(context),
                  _buildEncoderMenu(context),
                  _buildTfliteMenu(context),
                  _buildCpuSelfTestCard(context),
                  _DeviceLoadCard(
                    controller: controller,
                    // Busy = something that can move the numbers. Reading the
                    // observables here is what makes the whole card rebuild
                    // when a download starts or a load starts.
                    busy: controller.isImporting.value ||
                        controller.activeDownloads.isNotEmpty ||
                        Get.find<InferenceService>().modelLoadProgress.value >
                            0,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        preencher('mv_local_models',
                            {'n': '${controller.displayedModels.length}'}),
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).hintColor,
                          letterSpacing: 1.6,
                        ),
                      ),
                      InkWell(
                        onTap: controller.toggleSort,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.sort,
                                size: 14,
                                color: Theme.of(context).hintColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                controller.sortSmallestFirst.value
                                    ? 'mv_size_label'.tr
                                    : 'mv_name_label'.tr,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).hintColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (controller.modelSections.isEmpty)
                    _buildEmptyLocalState(context)
                  else
                    ...controller.modelSections
                        .map((section) => _buildModelSection(context, section)),
                ] else ...[
                  _buildOnlineProviders(context),
                ],
              ],
            )),
      ),
    );
  }

  Widget _buildScopeToggle(BuildContext context) {
    return Obx(() {
      return SegmentedButton<String>(
        segments: [
          ButtonSegment(
            value: 'local',
            icon: Icon(Icons.phone_android),
            label: Text('local'.tr),
          ),
          ButtonSegment(
            value: 'online',
            icon: Icon(Icons.cloud_outlined),
            label: Text('online'.tr),
          ),
        ],
        selected: {controller.modelScope.value},
        onSelectionChanged: (selection) =>
            controller.modelScope.value = selection.first,
      );
    });
  }

  /// The curated encoders, behind their own entry rather than mixed into the
  /// model list.
  ///
  /// A submenu and not a section, because a BERT is not a chat model with a
  /// different size: loading one puts the encoder console on screen instead of a
  /// conversation, and someone who taps it expecting a chat would be right to be
  /// annoyed. Finding that out by scrolling a list of forty is the wrong place.
  /// The two roles are listed apart too, because "scores documents" and "returns
  /// a vector" are different purchases of the same hundred megabytes.
  Widget _buildEncoderMenu(BuildContext context) {
    // No `Obx` here, and the reason is measured rather than stylistic.
    //
    // The list this sits in is built inside an `Obx`, and the scope toggle
    // directly above is an `Obx` of its own. That is one nested builder and it
    // works. Adding a *second* one — even `Obx(() => const ListTile(...))`, with
    // no catalogue access, no `Get.find`, no decoration, nothing — takes the
    // whole list off the screen: no exception, no error widget, just an empty
    // area under a working app bar. GetX's notifier stack does not survive the
    // second nesting and the outer widget stops rendering.
    //
    // Six builds went into that, and the reason is worth writing down: the
    // symptom points at the screen, so every probe exonerated the obvious
    // culprits one at a time while the constant was hiding in plain sight.
    //
    // Nothing reactive is lost by omitting it. Both lists are filled once in
    // `ModelController.onInit` and never change, so the counts on this tile are
    // the same for the life of the process. The cards inside the sheet do need
    // reactivity for download and load state, and they are safe there because the
    // sheet is not inside the list's `Obx`.
    final rerank = controller.curatedRerankers.length;
    final embed = controller.curatedEmbedders.length;
    // A `Material` and not a `Container` with a `BoxDecoration`.
    //
    // This is the bug that cost eight builds. `ListTile` paints its background
    // and its ink splash on the nearest `Material` ancestor, so putting a
    // decorated box between the two does not merely hide the splash — it trips a
    // `debugAssert` inside `ListTile` and takes the whole list off the screen.
    // No exception reached `FlutterError.onError` in any form worth reading, the
    // app bar above kept working, and the assertion only fires on the branch
    // that builds the `InkWell`, so it needed `onTap` *and* a background on the
    // parent. Every build that had one without the other rendered fine, which is
    // why each probe exonerated a real part of the tile in turn.
    //
    // `Material` is also the right thing rather than the fix that satisfies the
    // assert: it gives the tap something to ripple on, so the feedback is
    // visible instead of merely legal.
    return Material(
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(Icons.memory_rounded,
            color: Theme.of(context).colorScheme.primary),
        title: Text('Encoders',
            style:
                GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
        subtitle: Text('$rerank rerankers · $embed embedders',
            style: GoogleFonts.inter(
                fontSize: 12, color: Theme.of(context).hintColor)),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () => _showEncoderSheet(context),
      ),
    );
  }

  /// The `.tflite` menu, for the same reason the encoder menu exists and with
  /// the same three rules.
  ///
  /// It is here because a `.tflite` is a model the user downloads and it does
  /// not chat, and someone who taps its Load expecting a conversation would be
  /// right to be annoyed. A `.tflite` also reaches this screen at all now: it
  /// used to be invisible, because discovery filtered on an extension list that
  /// did not include it — the runtime served the file perfectly well over HTTP
  /// the whole time, which is the part that made it worth fixing rather than
  /// documenting.
  ///
  /// No `Obx` for the same measured reason as the encoder tile above: a second
  /// nested builder inside the list's `Obx` takes the whole list off the screen.
  /// Nothing reactive is lost — the `.tflite` list is derived from files on disk
  /// and is filled by the same `refreshDownloaded` that fills everything else,
  /// and the tile disappears entirely when there is none.
  Widget _buildTfliteMenu(BuildContext context) {
    final heads = controller.displayedModels
        .where((m) => controller.isTfliteModel(m))
        .toList();
    if (heads.isEmpty) return const SizedBox.shrink();
    // `Material`, not a decorated `Container`: `ListTile` needs a `Material`
    // ancestor to paint on and asserts without one, taking the list with it.
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(Icons.hexagon_outlined,
              color: Theme.of(context).colorScheme.primary),
          title: Text('TFLite heads',
              style:
                  GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
          subtitle: Text(
            heads.length == 1
                ? 'mv_one_classification_model'.tr
                : '${heads.length} models · classification, not chat',
            style: GoogleFonts.inter(
                fontSize: 12, color: Theme.of(context).hintColor),
          ),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () => _showTfliteSheet(context),
        ),
      ),
    );
  }

  /// The sheet: one card per `.tflite`, and the console opens from there.
  void _showTfliteSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('TFLite heads',
                style: GoogleFonts.inter(
                    fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Estes também não conversam. Um .tflite é um grafo de tensores: recebe '
              'tensores de entrada nomeados e devolve tensores de saída nomeados, e o '
              'console inspeciona o arquivo primeiro para mostrar o que ele quer. O '
              'servidor da API precisa estar ligado para usar.',
              style: GoogleFonts.inter(
                  fontSize: 12, color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 20),
            for (final m in controller.displayedModels
                .where((m) => controller.isTfliteModel(m))) ...[
              _tfliteCard(context, m),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  /// One `.tflite` in the sheet, with the console as its action.
  ///
  /// The console opens rather than loading, because the two questions are
  /// different: a graph can be perfectly loadable and useless without knowing
  /// what it expects, and a Load button that compiled it and then showed a blank
  /// console would have spent native time to teach nothing.
  Widget _tfliteCard(BuildContext sheetContext, AiModel model) {
    return Material(
      color: Theme.of(sheetContext)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      // **One `child`, so the two actions live in a `Column` under the tile
      // rather than as a second child of the `Material`.** `Material` takes
      // exactly one, and the compile error for that arrives as a
      // positional-argument complaint about a `Padding` a dozen lines further
      // down — which is not a message that points at the thing that is wrong.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.hexagon_outlined, size: 20),
            title: Text(model.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text(controller.modelSizeLabel(model),
                style: GoogleFonts.inter(
                    fontSize: 12, color: Theme.of(sheetContext).hintColor)),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () {
              // `sheetContext`, not the outer one: the sheet is a different route
              // in the Navigator, and popping the outer context would pop the
              // page the user came from instead of the sheet.
              Navigator.of(sheetContext).pop();
              Get.to(() => LitertHeadConsole(
                    onClose: () => Get.back(),
                    filename: model.filename,
                  ));
            },
          ),
          // **Two actions, because they are two different jobs.** The tile above
          // *inspects* the head: what it is, what tensors it wants, what the
          // device can accelerate. The row below *drives* it — the System One
          // window, which asks the head something and shows what came back.
          //
          // The window is reachable from here and not from the GGUF cards, for
          // the same reason the server screen hosts it: a `.tflite`'s shape is
          // settled by its extension before anything is loaded, while a GGUF's
          // is not settled until it is. A "decision" button on 36 chat model
          // cards would be 36 buttons that are wrong for the model they sit on.
          //
          // A `Wrap`, for the fourth time in this file: an icon beside an
          // English label with nothing limiting it is the exact shape of the
          // three overflows this repo has already paid for.
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Wrap(
              spacing: 4,
              runSpacing: 0,
              children: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    Get.to(() => LitertHeadConsole(
                          onClose: () => Get.back(),
                          filename: model.filename,
                        ));
                  },
                  icon: const Icon(Icons.search, size: 15),
                  label: Text('mv_inspect_file'.tr,
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Theme.of(sheetContext).hintColor)),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    Get.to(() => SystemOneConsole(
                          onClose: () => Get.back(),
                          filename: model.filename,
                          // Settled by the extension, with nothing loaded: a
                          // head has no `cls.*` tensor to be recognised by, so
                          // the extension is the only fact there is.
                          shape: SystemOneShape.tfliteHead,
                          // The embedding encoders, so the vector panel can name
                          // where a 1024-number vector comes from instead of
                          // pointing at a bare endpoint.
                          embedders: controller.curatedEmbedders
                              .map((m) => m.filename)
                              .toList(),
                          baseUrl: Get.isRegistered<ServerController>()
                              ? Get.find<ServerController>().baseUrl
                              : null,
                          // The key, when the user turned it on. Every in-app
                          // client that skipped this header made its console read
                          // "server not running" against a running server.
                          authHeaders: Get.isRegistered<ServerController>()
                              ? localApiHeaders(
                                  useApiKey: Get.find<ServerController>()
                                      .useApiKey
                                      .value,
                                  apiKey:
                                      Get.find<ServerController>().apiKey.value,
                                )
                              : const {},
                        ));
                  },
                  icon: const Icon(Icons.rule, size: 15),
                  label: Text('mv_test_decision'.tr,
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Theme.of(sheetContext).hintColor)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The CPU self-test, offered where it is actually relevant.
  ///
  /// It lives here and not only in Settings because this is the screen where the
  /// user decides what to download, and the question it answers is "will this
  /// phone run a model at all".
  ///
  /// Three rules it obeys, all of them about not taking the choice away:
  ///
  /// - **Never automatic.** Nothing runs it. The card offers; the tap decides.
  ///   A self-test that fires by itself is a 150 MB load and a minute of CPU
  ///   the user did not ask for, which is the same complaint as an ad.
  /// - **Dismissible, permanently.** A dismissal is stored, so it does not come
  ///   back on the next visit. "Ask me again on every launch" is nagging, and a
  ///   nag is how a useful suggestion gets removed from the app.
  /// - **Cancellable while it runs.** A test that cannot be stopped is a test
  ///   the user resents, and it is the one that is easy to get wrong because the
  ///   llama.cpp call is not itself cancellable.
  Widget _buildCpuSelfTestCard(BuildContext context) {
    return Obx(() {
      final svc = Get.isRegistered<CpuSelfTestService>()
          ? Get.find<CpuSelfTestService>()
          : null;
      if (svc == null || !svc.offerEnabled) {
        return const SizedBox.shrink();
      }

      final state = svc.state;
      final benchmark = pickBenchmarkModel(controller.availableModels.toList());
      final missing = benchmark != null &&
          !controller.downloadedFiles.contains(benchmark.filename);
      final tested = state.verdict.value != null;

      final accent = Theme.of(context).colorScheme.primary;
      final verdict = state.verdict.value;
      final (icon, color) = switch (verdict) {
        CpuVerdict.ok => (Icons.check_circle_rounded, AppColors.success),
        CpuVerdict.slow => (Icons.speed_rounded, AppColors.warning),
        CpuVerdict.fail => (Icons.error_rounded, AppColors.error),
        null => (Icons.speed_rounded, accent),
      };

      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Material(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: state.running.value
                      ? null
                      : () => _runCpuSelfTest(svc, benchmark, missing),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: state.running.value
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: accent),
                          )
                        : Icon(icon, size: 20, color: color),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: state.running.value
                        ? null
                        : () => _runCpuSelfTest(svc, benchmark, missing),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            state.running.value
                                ? 'mv_benchmark_running'.tr: 'mv_benchmark_usability'.tr,
                            style: GoogleFonts.inter(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(
                          state.running.value
                              ? 'mv_bench_cpu_safe'.tr: missing
                                  ? 'mv_bench_what_it_does2'.tr: tested
                                      ? 'CPU Safe · ${state.summary.value}'
                                      : 'mv_bench_what_it_does'.tr,
                          style: GoogleFonts.inter(
                              fontSize: 12.5,
                              height: 1.35,
                              color: Theme.of(context).hintColor),
                        ),
                        if (tested) ...[
                          const SizedBox(height: 6),
                          _cpuSelfTestAdvice(
                              context, verdict, state.tokensPerSecond.value),
                        ],
                        if (state.running.value) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: svc.cancel,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 32),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text('mc_cancel'.tr,
                                style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.error)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Dismissal is a close button and not a swipe: the rows in this
                // list already have a swipe gesture, and adding a second one
                // makes both of them wrong.
                IconButton(
                  onPressed: () => svc.dismissOffer(),
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  tooltip: 'mv_dont_suggest_again'.tr,
                  icon: Icon(Icons.close_rounded,
                      color: Theme.of(context).hintColor),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  /// The verdict, turned into what to do about it.
  ///
  /// A rate on its own is not actionable, so each verdict says the next step.
  ///
  /// The slow branch offers a button rather than only a sentence, because the
  /// two things it can do — hide the list, or leave it alone — are both
  /// reversible and both one tap. Hiding 40 models the user may still want is
  /// only acceptable if undoing it is easier than scrolling past them, and an
  /// offer with no button is not undoable.
  Widget _cpuSelfTestAdvice(
      BuildContext context, CpuVerdict? verdict, double? tps) {
    final suggestsCloud =
        benchmarkSaysUseCloudModels(verdict ?? CpuVerdict.fail, tps);
    final (text, color) = switch (verdict) {
      CpuVerdict.ok => (
          'mv_bench_fast'.tr,
          AppColors.success
        ),
      CpuVerdict.slow => (
          tps == null
              ? 'mv_bench_cpu_nothing'.tr: 'Under ${kCpuUsableTokensPerSecond.toStringAsFixed(0)} tok/s. '
                  'Cloud models will feel better; a local 230M still works if '
                  'you would rather keep it on the device.',
          AppColors.warning
        ),
      CpuVerdict.fail => (
          'mv_bench_cpu_path_nothing'.tr,
          AppColors.error
        ),
      null => ('', AppColors.primary),
    };

    final hidden = controller.localCatalogueHidden.value;
    final ignored = controller.ignoreBenchmarkAdvice.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.arrow_right_rounded, size: 14, color: color),
            const SizedBox(width: 4),
            Expanded(
              child: Text(text,
                  style: GoogleFonts.inter(
                      fontSize: 12, height: 1.35, color: color)),
            ),
          ],
        ),
        // No offer when the user has declined it in Settings. The number above
        // still stands: declining the consequence is not the same as hiding the
        // measurement.
        if (suggestsCloud && !ignored) ...[
          const SizedBox(height: 4),
          // Wrap, not Row. These are three actions, and the longest
          // combination — "Local list hidden" + "Show it anyway" + "Keep
          // models anyway" — is three English phrases on one line with nothing
          // bounding any of them. A Row of unbounded children overflows
          // horizontally the moment the screen narrows or the text scale goes
          // up, and this card sits on the Models screen, so the overflow takes
          // the catalogue with it. Wrapping onto a second line is also the
          // better read: they are alternatives, and stacking them says so in a
          // way that three buttons abreast does not.
          Wrap(
            spacing: 2,
            children: [
              TextButton(
                onPressed: () => controller.setLocalCatalogueHidden(true),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  hidden ? 'mv_list_hidden'.tr: 'mv_hide_list'.tr,
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: hidden ? AppColors.success : color),
                ),
              ),
              if (hidden)
                TextButton(
                  onPressed: () => controller.setLocalCatalogueHidden(false),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('mv_show_it_anyway'.tr,
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).hintColor)),
                ),
              TextButton(
                onPressed: () => controller.setIgnoreBenchmarkAdvice(true),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('mv_keep_models_anyway'.tr,
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).hintColor)),
              ),
            ],
          ),
        ],
        if (suggestsCloud && ignored) ...[
          const SizedBox(height: 2),
          Text('mv_showing_local_because'.tr,
              style: GoogleFonts.inter(
                  fontSize: 11.5, color: Theme.of(context).hintColor)),
        ],
      ],
    );
  }

  Future<void> _runCpuSelfTest(
    CpuSelfTestService svc,
    AiModel? benchmark,
    bool missing,
  ) async {
    // Asked before anything happens, because the alternative is discovering the
    // cost afterwards: 150 MB to download, then a load the user cannot
    // interrupt. Confirming first is the only place the choice is really theirs.
    if (missing && benchmark != null) {
      final go = await Get.dialog<bool>(
        AlertDialog(
          title: Text('mv_download_benchmark'.tr),
          content: Text(preencher('mv_download_benchmark_note', {
            'n': benchmark.name,
            's': benchmark.size,
          })),
          actions: [
            TextButton(
                onPressed: () => Get.back(result: false),
                child: Text('mv_not_now'.tr)),
            FilledButton(
                onPressed: () => Get.back(result: true),
                child: Text('iv_download'.tr)),
          ],
        ),
      );
      if (go != true) return;
      await controller.downloadModel(benchmark);
      if (!controller.downloadedFiles.contains(benchmark.filename)) return;
    }

    final r =
        await svc.run(availableModels: controller.availableModels.toList());
    if (svc.state.cancelled.value) return;
    if (!Get.isSnackbarOpen) {
      Get.snackbar(
        r.passed ? 'CPU works' : 'CPU problem',
        describeCpuSelfTest(r),
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 5),
      );
    }
  }

  void _showEncoderSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Encoders',
                style: GoogleFonts.inter(
                    fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Estes não conversam. Carregar um substitui a conversa por um '
              'console que roda os endpoints de embeddings, rerank e classify, '
              'e o servidor da API precisa estar ligado para usar.',
              style: GoogleFonts.inter(
                  fontSize: 12, color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 20),
            _encoderSection(
                ctx,
                'Rerank — pontuar uma consulta contra documentos',
                controller.curatedRerankers),
            const SizedBox(height: 22),
            _encoderSection(ctx, 'Embed — transformar cada texto num vetor',
                controller.curatedEmbedders),
          ],
        ),
      ),
    );
  }

  Widget _encoderSection(BuildContext ctx, String title, List<AiModel> models) {
    // `mainAxisSize: min`: a section is a direct child of the sheet's ListView,
    // which hands it unbounded height on the scroll axis, and a Column that
    // sizes itself to max under an unbounded constraint throws in layout.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: Theme.of(ctx).hintColor)),
        const SizedBox(height: 10),
        for (final m in models) _encoderCard(ctx, m),
      ],
    );
  }

  Widget _encoderCard(BuildContext ctx, AiModel model) {
    return Obx(() {
      final inference = Get.find<InferenceService>();
      final isDownloaded = controller.isDownloaded(model.filename);
      final isActive = inference.loadedModelName.value == model.filename;
      final dp = controller.getDownloadProgress(model.filename);
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Theme.of(ctx)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(12),
          border: isActive
              ? Border.all(color: AppColors.primary, width: 1.5)
              : null,
        ),
        // `Material` for the same reason as the tile above: the buttons inside
        // paint their ink on the nearest `Material`, and a decorated `Container`
        // in between is exactly what makes it invisible. The border stays on the
        // `Container` because that is decoration, not a surface.
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(13),
            // `min`: a card is a direct child of the sheet's ListView, which
            // hands it unbounded height on the scroll axis.
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(model.name,
                        style: GoogleFonts.inter(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  // **A sentinela entra guardada no Hive e sai pintada.** Um
                  // modelo importado por URL sem cabeçalho tem `size` igual a
                  // `kUnknownSize`, e `Text(model.size)` é onde esse valor
                  // vira texto. É o único ponto de pintura da sentinela, e ele
                  // existe porque o valor **é** o texto nos dois idiomas: sem
                  // a checagem aqui, o cartão mostraria a string inglesa.
                  Text(
                      model.size == AppConstants.kUnknownSize
                          ? 'mc_unknown_size'.tr
                          : model.size,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: Theme.of(ctx).hintColor)),
                ]),
                const SizedBox(height: 6),
                // O idioma vem de `Get.locale` e não de uma preferência lida
                // de novo: é o mesmo `Locale` que o `GetMaterialApp` empurrou
                // para a árvore, então os dois não podem discordar.
                Text(model.descriptionFor(Get.locale),
                    style: GoogleFonts.inter(
                        fontSize: 12, color: Theme.of(ctx).hintColor)),
                const SizedBox(height: 10),
                Row(children: [
                  // **Sem `const`: `.tr` é método de runtime.** O chip era
                  // `const Chip` e o analyzer acusa "Extension methods can't be
                  // used in constant expressions" — o mesmo erro das 16
                  // substituições da primeira leva, e o mesmo conserto: tirar o
                  // qualificador e devolver o nome do construtor.
                  if (isActive)
                    Chip(
                      avatar: const Icon(Icons.check_circle_rounded,
                          size: 14, color: AppColors.primary),
                      label: Text('mv_state_loaded'.tr,
                          style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                    )
                  else if (isDownloaded)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        controller.loadModel(model.filename);
                      },
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('load'),
                      style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                    )
                  else
                    FilledButton.icon(
                      onPressed: dp != null
                          ? null
                          : () => controller.downloadModel(model),
                      icon: dp != null
                          ? const SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.download_rounded, size: 16),
                      label: Text(
                          dp != null ? 'downloading' : 'mv_download_lower'.tr),
                      style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(0, 34),
                          textStyle: GoogleFonts.inter(fontSize: 12)),
                    ),
                  if (dp != null && dp.progress.value > 0) ...[
                    const SizedBox(width: 10),
                    Text('${(dp.progress.value * 100).toStringAsFixed(0)}%',
                        style: GoogleFonts.inter(fontSize: 11)),
                  ],
                ]),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildLocalActions(BuildContext context) {
    final inference = Get.find<InferenceService>();
    return Row(
      children: [
        Expanded(
          child: Obx(() => OutlinedButton.icon(
                onPressed: controller.isImporting.value ||
                        inference.isLoadingModel.value
                    ? null
                    : () => HfSearchSheet.show(context),
                icon: const Icon(Icons.search, size: 16),
                label: Text('search'.tr),
              )),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Obx(() => OutlinedButton.icon(
                onPressed: controller.isImporting.value ||
                        inference.isLoadingModel.value
                    ? null
                    : () => _showAddUrlDialog(context),
                icon: const Icon(Icons.add_link, size: 16),
                label: Text('url'.tr),
              )),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Obx(() => OutlinedButton.icon(
                onPressed: controller.isImporting.value ||
                        inference.isLoadingModel.value
                    ? null
                    : () => controller.importModelFromStorage(),
                icon: const Icon(Icons.file_upload_outlined, size: 16),
                label: Text('import'.tr),
              )),
        ),
      ],
    );
  }

  /// One heading plus its models, folded away until tapped.
  ///
  /// Everything starts closed: six headings read as an index of what the
  /// phone can run, where thirty cards read as a wall. Sub-headings appear
  /// only when the section actually splits — see ModelController._byModality.
  Widget _buildModelSection(BuildContext context, ModelSection section) {
    final open = controller.isSectionExpanded(section.title);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => controller.toggleSection(section.title),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(
                  open ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                  color: Theme.of(context).hintColor,
                ),
                const SizedBox(width: 4),
                Text(
                  // **O rótulo traduzido, e não a chave.** `section.title` é
                  // o valor persistido de `expandedSections` e é em inglês de
                  // propósito — trocar o texto de exibição quebra a expansão
                  // salva. `.tr` e `toUpperCase` nesta ordem porque PT-BR e EN
                  // diferem na caixa das letras acentuadas.
                  section.label.toUpperCase(),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Theme.of(context).hintColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${section.count}',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color:
                        Theme.of(context).dividerColor.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (open)
          for (final block in section.blocks) ...[
            if (block.label.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8, top: 2),
                child: Text(
                  block.label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).hintColor,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ...block.models.map((model) => _buildModelCard(context, model)),
          ],
      ],
    );
  }

  Widget _buildEmptyLocalState(BuildContext context) {
    // Only reached when every section came up empty, which on a fresh install
    // means nothing has been downloaded and the catalogue found nothing that
    // fits this phone's memory.
    // **Sem `const`.** `'chave'.tr` é método de runtime sobre o locale atual, e
    // `const title = 'x'.tr` não compila — o analyzer diz "Extension methods
    // can't be used in constant expressions". O `const` foi automático quando o
    // texto era literal, e a troca por chave o deixou inválido sem nada no
    // código parecer errado.
    final title = 'mv_no_models_yet'.tr;
    final subtitle = 'mv_import_local_or_url'.tr;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor, width: 0.5),
      ),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 32, color: Theme.of(context).hintColor),
          const SizedBox(height: 10),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Theme.of(context).hintColor,
            ),
          ),
          const SizedBox(height: 14),
          _buildLocalActions(context),
        ],
      ),
    );
  }

  void _showAddUrlDialog(BuildContext context) {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final filenameController = TextEditingController();
    final sizeController = TextEditingController();
    final templateController = TextEditingController(text: 'chatml');
    final isVision = false.obs;
    final isDetecting = false.obs;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.655),
      builder: (ctx) => _AddModelUrlSheet(
        nameController: nameController,
        urlController: urlController,
        filenameController: filenameController,
        sizeController: sizeController,
        templateController: templateController,
        isVision: isVision,
        isDetecting: isDetecting,
        modelController: controller,
      ),
    );
  }

  Widget _buildActiveModelBanner(BuildContext context) {
    return Obx(() {
      if (controller.modelScope.value == 'online') {
        return _buildActiveCloudBanner(context);
      }

      final inference = Get.find<InferenceService>();
      final localImage = Get.find<LocalImageService>();

      // Image model loaded
      if (localImage.isModelLoaded.value) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.15),
                AppColors.secondary.withValues(alpha: 0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  localImage.isUsingGpu.value ? Icons.bolt : Icons.memory,
                  color: localImage.isUsingGpu.value
                      ? AppColors.warning
                      : AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'active_image_model'.tr,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Theme.of(context).hintColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      localImage.loadedModelName.value,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      localImage.isUsingGpu.value
                          ? '⚡ GPU Accelerated'
                          : '🖥 CPU Mode',
                      style: GoogleFonts.firaCode(
                        fontSize: 10,
                        color: localImage.isUsingGpu.value
                            ? AppColors.success
                            : Theme.of(context).hintColor,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.check_circle,
                  color: AppColors.success, size: 20),
            ],
          ),
        );
      }

      // Text model loaded
      if (!inference.isModelLoaded.value) {
        return const SizedBox.shrink();
      }

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withValues(alpha: 0.15),
              AppColors.secondary.withValues(alpha: 0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                inference.isGpuAccelerated.value ? Icons.bolt : Icons.memory,
                color: inference.isGpuAccelerated.value
                    ? AppColors.warning
                    : AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'active_model'.tr,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Theme.of(context).hintColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    inference.loadedModelName.value,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (inference.loadedBackend.value.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      _accelLabel(inference),
                      style: GoogleFonts.firaCode(
                        fontSize: 10,
                        color: inference.isGpuAccelerated.value
                            ? AppColors.success
                            : Theme.of(context).hintColor,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.check_circle, color: AppColors.success, size: 20),
          ],
        ),
      );
    });
  }

  /// One line naming the rung of the NPU > GPU > CPU ladder this model landed
  /// on. Shown for every backend, not just GPU — "it fell back to CPU" is the
  /// case worth seeing.
  String _accelLabel(InferenceService inference) {
    switch (inference.loadedBackend.value) {
      case 'npu':
        return '◆ NPU';
      case 'gpu':
        final layers = inference.gpuLayersUsed.value;
        final name = inference.gpuName.value;
        final where = name.isEmpty ? 'GPU' : 'GPU: $name';
        // **`trParams` não serve aqui.** É um método de `String`, e o
        // resultado de `'chave'.tr` é um `String` estático para o analyzer —
        // a chamada dentro da interpolação não compila. `preencher` faz a
        // mesma troca e é uma função de topo.
        // **Só a forma com camadas vai para o mapa.** `⚡ $where` sem camada é
        // `GPU: Adreno (TM) 618` ou `CPU` — nome de aparelho e de acelerador,
        // que não se traduzem. A chave pega o que é prosa: quantas camadas.
        return layers > 0
            ? preencher('mv_gpu_layers', {'w': where, 'n': '$layers'})
            : '⚡ $where';
      default:
        return '▪ CPU';
    }
  }

  Widget _buildActiveCloudBanner(BuildContext context) {
    final settings = Get.find<SettingsController>();
    final cloudModels = Get.find<CloudModelController>();
    final providerId = settings.cloudProvider.value;
    final provider = cloudModels.providers.firstWhereOrNull(
      (p) => p.id == providerId,
    );
    final providerName = providerId == 'custom'
        ? settings.customCloudName.value
        : provider?.name ?? providerId;
    final model = cloudModels.activeModelFor(providerId);
    final hasSelectedModel =
        cloudModels.canSelectModel(providerId) && model.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.32)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.cloud_done_outlined,
                color: AppColors.secondary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preencher('mv_cloud_provider', {'p': providerName}),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: Theme.of(context).hintColor,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hasSelectedModel ? model : 'mv_no_online_model'.tr,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              if (provider == null) return;
              if (providerId == 'custom') {
                _showCustomProviderSheet(context, cloudModels);
              } else {
                _showProviderActionsSheet(context, cloudModels, provider);
              }
            },
            child: Text('change'.tr),
          ),
        ],
      ),
    );
  }

  Widget _buildModelLoadingProgress(BuildContext context, AiModel model) {
    return Obx(() {
      final inference = Get.find<InferenceService>();
      if (!inference.isLoadingModel.value ||
          inference.loadingModelName.value != model.filename) {
        return const SizedBox.shrink();
      }
      final progress = inference.modelLoadProgress.value;

      return Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.secondary.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.secondary,
                  ),
                ),
                const SizedBox(width: 10),
                // `Flexible` plus ellipsis, which is **the idiom of this very
                // card** — the filename row right below does exactly this, and
                // it was written by someone who had already been bitten by a
                // card that could not wrap. The banner did not get it, so a
                // 21-character translation sat in an unbounded row and the
                // overflow stripe took the whole card down.
                //
                // Ellipsis rather than wrapping is deliberate: a status line that
                // grows to two lines moves the filename under it, and the card's
                // height is part of what the model list is scrolled against.
                Flexible(
                  child: Text(
                    'loading_into_memory'.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.secondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              model.filename,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: Theme.of(context).hintColor,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: inference.modelLoadProgress.value > 0
                    ? inference.modelLoadProgress.value
                    : null,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                color: AppColors.secondary,
                minHeight: 3,
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildImportingProgress(BuildContext context) {
    return Obx(() {
      if (!controller.isImporting.value) return const SizedBox.shrink();
      final percent = controller.importProgress * 100;
      final total = controller.importTotalBytes.value;
      final copied = controller.importCopiedBytes.value;
      final remaining = total <= 0 ? 0 : (total - copied).clamp(0, total);

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.secondary.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.secondary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          controller.importStatus.value
                                  .toLowerCase()
                                  .contains('download')
                              ? 'Downloading'
                              : 'Importing',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.secondary,
                          ),
                        ),
                      ),
                      Text(
                        '${percent.toStringAsFixed(1)}%',
                        style: GoogleFonts.firaCode(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.secondary,
                        ),
                      ),
                      if (controller.externalDownloadId.value != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: InkWell(
                            onTap: controller.cancelExternalDownload,
                            borderRadius: BorderRadius.circular(12),
                            child: const Icon(Icons.close,
                                size: 20, color: AppColors.error),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${controller.importStatus.value} ${controller.importFileName.value}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: controller.importProgress > 0
                          ? controller.importProgress
                          : null,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      color: AppColors.secondary,
                      minHeight: 5,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text(
                        '${DownloadService.formatWholeMb(copied)} / ${DownloadService.formatWholeMb(total)}',
                        style: GoogleFonts.inter(
                            fontSize: 11, color: Theme.of(context).hintColor),
                      ),
                      Text(
                        '${DownloadService.formatWholeMb(remaining)} left',
                        style: GoogleFonts.inter(
                            fontSize: 11, color: Theme.of(context).hintColor),
                      ),
                      Text(
                        DownloadService.formatSpeed(
                            controller.importBytesPerSecond.value),
                        style: GoogleFonts.inter(
                            fontSize: 11, color: Theme.of(context).hintColor),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  // ignore: unused_element

  Widget _buildOnlineProviders(BuildContext context) {
    final cloud = Get.find<CloudModelController>();
    return Obx(() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'providers'.tr,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).hintColor,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          for (final provider in cloud.providers)
            _buildOnlineProviderRow(context, cloud, provider),
        ],
      );
    });
  }

  Widget _buildOnlineProviderRow(
    BuildContext context,
    CloudModelController cloud,
    CloudProviderInfo provider,
  ) {
    final settings = Get.find<SettingsController>();
    final isCustom = provider.id == 'custom';
    final isActive = cloud.activeProvider == provider.id;
    final canUse = cloud.canSelectModel(provider.id);
    final model = cloud.activeModelFor(provider.id);
    final hasSelectedModel = canUse && model.isNotEmpty;
    final modelLabel = hasSelectedModel ? model : 'mv_no_model_selected'.tr;
    final name = isCustom ? settings.customCloudName.value : provider.name;
    final accent = _providerAccent(provider.id);
    final error = cloud.errorByProvider[provider.id];
    final status = isActive && hasSelectedModel
        ? 'ACTIVE'
        : canUse
            ? 'mv_state_ready'.tr
            : cloud.statusLabel(provider.id).toUpperCase();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => isCustom
              ? _showCustomProviderSheet(context, cloud)
              : _openProviderFlow(context, cloud, provider),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive
                    ? accent.withValues(alpha: 0.55)
                    : Theme.of(context).dividerColor.withValues(alpha: 0.55),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(provider.icon, color: accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name.isEmpty ? provider.name : name,
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              _buildStatusPill(
                                context,
                                status,
                                configured: canUse,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            modelLabel,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: hasSelectedModel
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: hasSelectedModel
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Theme.of(context).hintColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'mv_provider_settings'.tr,
                      onPressed: () =>
                          _showProviderActionsSheet(context, cloud, provider),
                      icon: const Icon(Icons.more_vert, size: 20),
                    ),
                  ],
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  _buildErrorBox(context, error),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _providerAccent(String provider) {
    switch (provider) {
      case 'openrouter':
        return AppColors.success;
      case 'deepseek':
        return const Color(0xFF00B8A9);
      case 'google':
        return AppColors.warning;
      case 'nvidia':
        return const Color(0xFF76B900);
      case 'custom':
        return AppColors.info;
      default:
        return AppColors.primary;
    }
  }

  Future<void> _openProviderFlow(
    BuildContext context,
    CloudModelController cloud,
    CloudProviderInfo provider,
  ) async {
    if (!cloud.canSelectModel(provider.id)) {
      _showProviderKeyDialog(
        context,
        cloud,
        provider,
        openModelsAfterSave: true,
      );
      return;
    }

    await cloud.refreshModels(provider.id);
    if ((cloud.errorByProvider[provider.id] ?? '').isNotEmpty) {
      _showProviderKeyDialog(
        context,
        cloud,
        provider,
        openModelsAfterSave: true,
      );
      return;
    }
    _showModelSelectSheet(context, cloud, provider);
  }

  void _showProviderActionsSheet(
    BuildContext context,
    CloudModelController cloud,
    CloudProviderInfo provider,
  ) {
    final settings = Get.find<SettingsController>();
    final isCustom = provider.id == 'custom';

    Get.bottomSheet(SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: SafeArea(
          child: Obx(() {
            final model = cloud.activeModelFor(provider.id);
            final configured = cloud.isConfigured(provider.id);
            final name =
                isCustom ? settings.customCloudName.value : provider.name;
            final accent = _providerAccent(provider.id);

            return Padding(
              padding: EdgeInsets.only(
                left: 22,
                right: 22,
                top: 22,
                bottom: MediaQuery.of(context).viewInsets.bottom + 22,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(provider.icon, color: accent, size: 26),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name.isEmpty ? provider.name : name,
                              style: GoogleFonts.inter(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              model.isEmpty ? provider.description : model,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: Theme.of(context).hintColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: Get.back,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  if (!isCustom) ...[
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      leading: const Icon(Icons.key_outlined, size: 26),
                      title: Text(
                        configured
                            ? 'mv_update_api_key'.tr
                            : 'mv_add_api_key'.tr,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle:
                          Text('required_before_selecting_live_models'.tr),
                      onTap: () {
                        Get.back();
                        _showProviderKeyDialog(
                          context,
                          cloud,
                          provider,
                          openModelsAfterSave: true,
                        );
                      },
                    ),
                    const Divider(height: 1),
                  ],
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    leading: Icon(
                        isCustom ? Icons.tune : Icons.smart_toy_outlined,
                        size: 26),
                    title: Text(
                      isCustom
                          ? 'mv_configure_select'.tr
                          : 'mv_select_model'.tr,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(isCustom
                        ? 'mv_set_base_key_id'.tr
                        : 'mv_search_provider_or_id'.tr),
                    onTap: () {
                      Get.back();
                      if (isCustom) {
                        _showCustomProviderSheet(context, cloud);
                      } else {
                        _openProviderFlow(context, cloud, provider);
                      }
                    },
                  ),
                ],
              ),
            );
          }),

          // isScrollControlled: true,
          // backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          // shape: const RoundedRectangleBorder(
          //   borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          // ),
        )));
  }

  // ignore: unused_element

  void _showProviderKeyDialog(
    BuildContext context,
    CloudModelController cloud,
    CloudProviderInfo provider, {
    bool openModelsAfterSave = false,
  }) {
    final keyController = cloud.apiKeyControllerFor(provider.id);
    final obscureKey = true.obs;
    final isVerifying = false.obs;
    final accent = _providerAccent(provider.id);
    Get.dialog(AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titlePadding: const EdgeInsets.fromLTRB(26, 26, 22, 0),
      contentPadding: const EdgeInsets.fromLTRB(26, 20, 26, 10),
      actionsPadding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
      title: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(provider.icon, color: accent, size: 29),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider.name,
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'api_key_required'.tr,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Obx(
              () => TextField(
                controller: keyController,
                obscureText: obscureKey.value,
                style: GoogleFonts.firaCode(fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'mv_api_key'.tr,
                  hintText:
                      preencher('mv_paste_provider_key', {'p': provider.name}),
                  prefixIcon: const Icon(Icons.key_outlined, size: 23),
                  suffixIcon: IconButton(
                    tooltip: obscureKey.value
                        ? 'mv_show_api_key'.tr
                        : 'mv_hide_api_key'.tr,
                    onPressed: () => obscureKey.value = !obscureKey.value,
                    icon: Icon(
                      obscureKey.value
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 24,
                    ),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Obx(() {
              final error = cloud.errorByProvider[provider.id];
              if (error == null || error.isEmpty) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildErrorBox(context, error),
              );
            }),
            Text(
              'mv_save_key_to_verify'.tr,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Theme.of(context).hintColor,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(closeOverlays: false),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
          child: Text('cancel'.tr),
        ),
        ElevatedButton(
          onPressed: () async {
            final value = keyController.text.trim();
            if (value.isEmpty || isVerifying.value) return;
            isVerifying.value = true;
            await cloud.saveApiKey(provider.id, value);
            await cloud.refreshModels(provider.id);
            isVerifying.value = false;
            if ((cloud.errorByProvider[provider.id] ?? '').isNotEmpty) {
              return;
            }
            Get.back(closeOverlays: false);
            if (openModelsAfterSave) {
              _showModelSelectSheet(context, cloud, provider);
            }
          },
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          ),
          child:
              Obx(() => Text(isVerifying.value ? 'mv_verifying'.tr: 'mv_save_key'.tr)),
        ),
      ],
    ));
  }

  void _showCustomProviderSheet(
    BuildContext context,
    CloudModelController cloud,
  ) {
    final obscureCustomKey = true.obs;
    Get.bottomSheet(
      SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 26,
            bottom: MediaQuery.of(context).viewInsets.bottom + 22,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('custom_provider'.tr,
                    style: GoogleFonts.inter(
                        fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  'mv_openai_endpoint'.tr,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    height: 1.35,
                    color: Theme.of(context).hintColor,
                  ),
                ),
                const SizedBox(height: 18),
                Obx(() {
                  final profiles = cloud.customProfiles;
                  if (profiles.isEmpty) return const SizedBox.shrink();
                  final selected = cloud.customProfileIndex;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            key: ValueKey(selected),
                            initialValue: selected >= 0 ? selected : null,
                            decoration: InputDecoration(
                              labelText: 'mv_saved_provider'.tr,
                              prefixIcon: Icon(Icons.bookmarks_outlined),
                            ),
                            items: [
                              for (var i = 0; i < profiles.length; i++)
                                DropdownMenuItem(
                                  value: i,
                                  child: Text(
                                    profiles[i]['name']?.isNotEmpty == true
                                        ? profiles[i]['name']!
                                        : profiles[i]['baseUrl'] ??
                                            'Custom API',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (index) {
                              if (index != null) {
                                cloud.selectCustomProfile(index);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'Add another provider',
                          onPressed: cloud.beginNewCustomProfile,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  );
                }),
                Obx(() {
                  final error = cloud.customProviderError.value;
                  if (error.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _buildErrorBox(context, error),
                  );
                }),
                TextField(
                  controller: cloud.customNameController,
                  decoration: InputDecoration(
                    labelText: 'mv_cloud_provider_name'.tr,
                    prefixIcon: const Icon(Icons.badge_outlined, size: 23),
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 20, horizontal: 18),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: cloud.customBaseUrlController,
                  decoration: InputDecoration(
                    labelText: 'mv_cloud_base_url'.tr,
                    hintText: 'https://example.com/v1',
                    prefixIcon: const Icon(Icons.link, size: 23),
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 20, horizontal: 18),
                  ),
                ),
                const SizedBox(height: 14),
                Obx(
                  () => TextField(
                    controller: cloud.customApiKeyController,
                    obscureText: obscureCustomKey.value,
                    decoration: InputDecoration(
                      labelText: 'mv_api_key'.tr,
                      prefixIcon: const Icon(Icons.key_outlined, size: 23),
                      suffixIcon: IconButton(
                        tooltip: obscureCustomKey.value
                            ? 'mv_show_api_key'.tr
                            : 'mv_hide_api_key'.tr,
                        onPressed: () =>
                            obscureCustomKey.value = !obscureCustomKey.value,
                        icon: Icon(
                          obscureCustomKey.value
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 24,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 20, horizontal: 18),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: cloud.customModelController,
                  decoration: InputDecoration(
                    labelText: 'mv_model_id'.tr,
                    prefixIcon: Icon(Icons.smart_toy_outlined, size: 23),
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 20, horizontal: 18),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await cloud.saveCustomProvider();
                      if (cloud.customProviderError.value.isEmpty) {
                        Get.back(closeOverlays: false);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    icon: const Icon(Icons.check, size: 22),
                    label: Text('save_and_select'.tr),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: () async {
                      await cloud.clearCustomProvider();
                    },
                    child: Obx(() => Text(
                          cloud.customProfileIndex >= 0
                              ? 'Remove selected provider'
                              : 'mv_clear_form'.tr,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.error,
                          ),
                        )),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    );
  }

  void _showModelSelectSheet(
    BuildContext context,
    CloudModelController cloud,
    CloudProviderInfo provider,
  ) {
    if (!cloud.canSelectModel(provider.id)) {
      _showProviderKeyDialog(
        context,
        cloud,
        provider,
        openModelsAfterSave: true,
      );
      return;
    }

    cloud.searchByProvider[provider.id] = '';
    if ((cloud.modelsByProvider[provider.id] ?? const <String>[]).isEmpty) {
      cloud.refreshModels(provider.id);
    } else if (cloud.canFetchModels(provider.id) &&
        cloud.fetchedAtByProvider[provider.id] == null) {
      cloud.refreshModels(provider.id);
    }

    Get.bottomSheet(
      SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: SafeArea(
          child: Obx(() {
            final isLoading = cloud.isLoadingProvider[provider.id] == true;
            final error = cloud.errorByProvider[provider.id];
            final models = cloud.filteredModelsFor(provider.id);
            final activeModel = cloud.activeModelFor(provider.id);
            final isActiveProvider = cloud.activeProvider == provider.id;
            final canFetch = cloud.canFetchModels(provider.id);
            final freeFirst = cloud.freeFirstByProvider[provider.id] == true;
            final freeModelCount = cloud.freeModelCountFor(provider.id);

            Widget modelList;
            if (isLoading && models.isEmpty) {
              modelList = const Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: CircularProgressIndicator(),
                ),
              );
            } else if (models.isEmpty) {
              modelList = _buildModelSelectEmptyState(context, provider);
            } else {
              modelList = ListView.separated(
                itemCount: models.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final id = models[index];
                  return _buildCloudModelRow(
                    context,
                    cloud,
                    provider,
                    id,
                    activeModel,
                    isActiveProvider,
                  );
                },
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 22,
                right: 22,
                top: 22,
                bottom: MediaQuery.of(context).viewInsets.bottom + 22,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preencher(
                              'mv_select_provider_model', {'p': provider.name}),
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: Get.back,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (value) =>
                        cloud.searchByProvider[provider.id] = value,
                    style: GoogleFonts.inter(fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'mv_search_models'.tr,
                      prefixIcon: Icon(Icons.search, size: 23),
                      contentPadding: EdgeInsets.symmetric(
                        vertical: 18,
                        horizontal: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preencher('mv_provider_model_count', {
                            'n': '${models.length}',
                            'f': cloud.fetchedLabel(provider.id),
                          }),
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                      ),
                      if (provider.id == 'openrouter' ||
                          freeModelCount > 0) ...[
                        TextButton.icon(
                          onPressed: freeModelCount == 0
                              ? null
                              : () => cloud.toggleFreeFirst(provider.id),
                          icon: Icon(
                            freeFirst
                                ? Icons.check_circle
                                : Icons.local_offer_outlined,
                            size: 16,
                          ),
                          label: Text(
                            freeModelCount == 0
                                ? 'Free'
                                : 'Free first ($freeModelCount)',
                          ),
                        ),
                        const SizedBox(width: 2),
                      ],
                      TextButton.icon(
                        onPressed: isLoading || !canFetch
                            ? null
                            : () => cloud.refreshModels(provider.id),
                        icon: isLoading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh, size: 16),
                        label: Text('refresh'.tr),
                      ),
                    ],
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    _buildErrorBox(context, error),
                  ],
                  const SizedBox(height: 12),
                  Expanded(child: modelList),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _showCustomModelIdDialog(context, cloud, provider),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: const Icon(Icons.add, size: 20),
                      label: Text('use_custom_model_id'.tr),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    );
  }

  Widget _buildModelSelectEmptyState(
    BuildContext context,
    CloudProviderInfo provider,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor, width: 0.5),
      ),
      child: Text(
        'mv_no_models_loaded'.tr,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 12,
          color: Theme.of(context).hintColor,
        ),
      ),
    );
  }

  void _showCustomModelIdDialog(
    BuildContext context,
    CloudModelController cloud,
    CloudProviderInfo provider,
  ) {
    final textController =
        TextEditingController(text: cloud.activeModelFor(provider.id));
    Get.dialog(AlertDialog(
      title: Text(preencher('mv_custom_provider_model', {'p': provider.name}),
          style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
      content: TextField(
        controller: textController,
        style: GoogleFonts.firaCode(fontSize: 12),
        decoration: InputDecoration(
          labelText: 'mv_model_id'.tr,
          prefixIcon: Icon(Icons.smart_toy_outlined, size: 18),
        ),
      ),
      actions: [
        TextButton(onPressed: Get.back, child: Text('cancel'.tr)),
        ElevatedButton(
          onPressed: () async {
            final value = textController.text.trim();
            if (value.isEmpty) return;
            if (!cloud.canSelectModel(provider.id)) {
              if (provider.id == 'custom') {
                _showCustomProviderSheet(context, cloud);
              } else {
                _showProviderKeyDialog(context, cloud, provider);
              }
              return;
            }
            await cloud.selectModel(
              provider.id,
              value,
              showSnackbar: false,
            );
            Get.back(closeOverlays: false);
            Get.back(closeOverlays: false);
          },
          child: Text('select'.tr),
        ),
      ],
    ));
  }

  Widget _buildCloudModelRow(
    BuildContext context,
    CloudModelController cloud,
    CloudProviderInfo provider,
    String id,
    String activeModel,
    bool isActiveProvider,
  ) {
    final providerId = provider.id;
    final normalized =
        providerId == 'google' ? id.replaceFirst('models/', '') : id;
    final canUse = cloud.canSelectModel(providerId);
    final isActive = isActiveProvider && normalized == activeModel && canUse;
    final tags = cloud.modelTagsFor(providerId, id);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.secondary.withValues(alpha: 0.12)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive
              ? AppColors.secondary.withValues(alpha: 0.35)
              : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    normalized,
                    style: GoogleFonts.firaCode(
                      fontSize: 13,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (tags.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Wrap(
                    spacing: 5,
                    children: [
                      for (final tag in tags) _buildModelTag(context, tag),
                    ],
                  ),
                ],
                // Auto-detected context window
                if (cloud.contextWindowFor(providerId, id) != null) ...[
                  const SizedBox(width: 8),
                  _buildContextBadge(
                      context, cloud.contextWindowFor(providerId, id)!),
                ],
                // Auto-detected capabilities
                for (final cap in cloud.capabilitiesFor(providerId, id)) ...[
                  const SizedBox(width: 5),
                  _buildCapBadge(context, cap),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          isActive
              ? _buildStatusPill(context, 'ACTIVE', configured: true)
              : TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                  onPressed: () async {
                    if (!canUse) {
                      _showProviderKeyDialog(context, cloud, provider);
                      return;
                    }
                    await cloud.selectModel(
                      providerId,
                      id,
                      showSnackbar: false,
                    );
                    Get.back(closeOverlays: false);
                  },
                  child: Text(canUse ? 'Select' : 'mv_add_key'.tr),
                ),
        ],
      ),
    );
  }

  Widget _buildModelTag(BuildContext context, String label) {
    final isFree = label == 'FREE';
    final color = isFree ? AppColors.success : AppColors.info;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }

  String _formatContextWindow(int tokens) {
    if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(1)}M';
    if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(0)}K';
    return '$tokens';
  }

  Widget _buildContextBadge(BuildContext context, int tokens) {
    final color = tokens >= 128000
        ? const Color(0xFF4ADE80)
        : tokens >= 32000
            ? const Color(0xFF60A5FA)
            : const Color(0xFFFBBF24);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Text(
        _formatContextWindow(tokens),
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildCapBadge(BuildContext context, String cap) {
    final isVision = cap == 'vision';
    final icon = isVision ? '👁' : '🔧';
    final color = isVision ? const Color(0xFFFF7CB3) : const Color(0xFF8B7CFF);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        icon,
        style: const TextStyle(fontSize: 10),
      ),
    );
  }

  Widget _buildStatusPill(
    BuildContext context,
    String label, {
    required bool configured,
  }) {
    final color = configured ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _buildErrorBox(BuildContext context, String error) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Text(
        error,
        style: GoogleFonts.inter(
          fontSize: 11,
          color: AppColors.error,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildModelBadges(BuildContext context, AiModel model) {
    final badges = <({String label, Color color})>[];
    if (controller.isDownloaded(model.filename)) {
      badges.add((label: 'mv_state_downloaded'.tr, color: AppColors.success));
    }
    if (controller.isTfliteModel(model)) {
      // Its own badge, not "LiteRT". The two share a name in Google's Maven
      // repository and nothing else — one streams tokens from a prompt, the
      // other maps named tensors — and a badge that calls a 1 MB classifier
      // "LiteRT" is the same confusion the section heading exists to stop.
      badges.add((label: 'TFLITE', color: AppColors.primary));
    } else if (controller.isLiteRtModel(model)) {
      badges.add((label: 'LiteRT', color: AppColors.primary));
    } else if (controller.isLlamaModel(model)) {
      badges.add((label: 'GGUF', color: AppColors.info));
    }
    if (controller.isUncensoredModel(model)) {
      badges.add((label: 'UNCENSORED', color: AppColors.error));
    }
    if (controller.isVisionModel(model)) {
      badges
          .add((label: controller.modalityLabel(model), color: AppColors.info));
    }
    if (controller.isImageModel(model)) {
      badges.add((label: 'IMAGE', color: AppColors.primary));
    }
    if (model.isImported) {
      badges.add((label: 'IMPORTED', color: AppColors.secondary));
    }
    if (model.isCustom) {
      badges.add((label: 'CUSTOM', color: AppColors.warning));
    }

    if (badges.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final badge in badges)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: badge.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              badge.label,
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: badge.color,
              ),
            ),
          ),
      ],
    );
  }

  void _confirmDownload(BuildContext context, AiModel model) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.cloud_download_outlined, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'download_model'.tr,
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              model.needsMmproj
                  ? 'You are about to download ${model.name} and its '
                      'projector for use in the app.'
                  : 'You are about to download ${model.name} for use in the app.',
              style:
                  GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sd_storage_outlined, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    model.needsMmproj
                        ? 'Weights: ${controller.modelSizeLabel(model)} '
                            '+ projector'
                        : 'Size: ${controller.modelSizeLabel(model)}',
                    style: GoogleFonts.inter(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.wifi, color: AppColors.warning, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'mv_wifi_recommended'.tr,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(
                                0xFFFFD60A) // Brighter warning for dark mode
                            : AppColors.warning,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'mc_cancel'.tr,
              style: GoogleFonts.inter(color: Theme.of(context).hintColor),
            ),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              controller.downloadModel(model);
            },
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            child: Text('download_now'.tr,
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _swipeAction(
      BuildContext context, IconData icon, String label, Color color,
      {required Alignment alignment}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: alignment,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Future<bool> _confirmDeleteModel(
      BuildContext context, String filename) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('delete_model'.tr),
            content: Text(preencher('mv_delete_filename', {'f': filename})),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text('cancel'.tr),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                ),
                child: Text('delete'.tr),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) await controller.deleteModel(filename);
    return confirmed;
  }

  /// Shows a bottom sheet to edit a custom model's metadata.
  void _showEditModelSheet(BuildContext context, AiModel model) {
    final controller = Get.find<ModelController>();
    final nameController = TextEditingController(text: model.name);
    final urlController = TextEditingController(text: model.url);
    // Abre no idioma que a tela está mostrando: um campo de edição que
    // começa em inglês numa tela portuguesa faz a pessoa traduzir a própria
    // ficha antes de poder mexer no resto.
    final descController =
        TextEditingController(text: model.descriptionFor(Get.locale));
    final templateController = TextEditingController(text: model.template);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.edit_rounded,
                  size: 20,
                  color: Theme.of(sheetContext).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'edit_model'.tr,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(sheetContext).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildTextField(
              context,
              controller: nameController,
              label: 'set_field_name'.tr,
              hint: 'mv_enter_model_name'.tr,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              context,
              controller: urlController,
              label: 'url'.tr,
              hint: 'mv_enter_model_url'.tr,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              context,
              controller: descController,
              label: 'Description',
              hint: 'mv_enter_description'.tr,
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              context,
              controller: templateController,
              label: 'mv_template'.tr,
              hint: 'e.g. chatml',
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: Text('cancel'.tr,
                        style:
                            TextStyle(color: Theme.of(sheetContext).hintColor)),
                  ),
                ),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      final updated = model.copyWith(
                        name: nameController.text.trim().isEmpty
                            ? model.name
                            : nameController.text.trim(),
                        url: urlController.text.trim().isEmpty
                            ? model.url
                            : urlController.text.trim(),
                        // Campo vazio NÃO apaga a ficha que existiu — e a edição vale
                        // nos dois idiomas, porque quem escreveu a ficha não
                        // necessariamente sabe em que língua o catálogo a
                        // mostra.
                        descriptionEn: descController.text.trim().isEmpty
                            ? model.descriptionEn
                            : descController.text.trim(),
                        descriptionPt: descController.text.trim().isEmpty
                            ? model.descriptionPt
                            : descController.text.trim(),
                        template: templateController.text.trim().isEmpty
                            ? model.template
                            : templateController.text.trim(),
                      );
                      controller.updateCustomModel(updated);
                      Navigator.of(sheetContext).pop();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          Theme.of(sheetContext).colorScheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text('save'.tr),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(
        color: isDark ? Colors.white : Colors.black,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? Colors.white24 : Colors.black26,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.12),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFFB9F53E) : const Color(0xFFB9F53E),
          ),
        ),
        labelStyle: TextStyle(
          color: isDark ? Colors.white70 : Colors.black87,
        ),
      ),
      keyboardType: maxLines > 1 ? TextInputType.multiline : TextInputType.text,
    );
  }

  /// Vision pairing for one model: pick a projector from device storage,
  /// reuse one already in the models dir, or unpair.
  void _showVisionSheet(BuildContext context, AiModel model) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final current = controller.mmprojRefFor(model.filename);
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(preencher('mv_vision_model', {'m': model.name}),
                style: GoogleFonts.inter(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              current == null
                  ? 'mv_no_projector_paired'.tr
                  : 'Paired: ${current.split("/").last}',
              style: GoogleFonts.inter(
                  fontSize: 13, color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: Text('pick_from_device_storage'.tr),
              subtitle: Text('copies_the_file_into_the_models_folder'.tr),
              onTap: () async {
                Navigator.pop(ctx);
                await controller.importMmprojFor(model.filename);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download_rounded),
              title: Text('from_hugging_face'.tr),
              subtitle: Text('download_the_mmproj_via_the_hf_search_th'.tr),
              onTap: () async {
                Navigator.pop(ctx);
                final downloaded =
                    await controller.downloadedMmprojCandidates();
                if (!context.mounted) return;
                if (downloaded.isEmpty) {
                  Get.snackbar('Vision',
                      'mv_no_mmproj'.tr,
                      snackPosition: SnackPosition.BOTTOM,
                      duration: const Duration(seconds: 6));
                  return;
                }
                _pickDownloadedMmproj(context, model, downloaded);
              },
            ),
            if (current != null)
              ListTile(
                leading: const Icon(Icons.link_off_rounded),
                title: Text('unpair'.tr),
                onTap: () async {
                  Navigator.pop(ctx);
                  await controller.setMmprojOverride(model.filename, null);
                },
              ),
          ]),
        ),
      ),
    );
  }

  void _pickDownloadedMmproj(
      BuildContext context, AiModel model, List<String> candidates) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final path in candidates)
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(path.split('/').last),
              onTap: () async {
                Navigator.pop(ctx);
                await controller.setMmprojOverride(
                    model.filename, path.split('/').last);
              },
            ),
        ]),
      ),
    );
  }

  Widget _buildModelCard(BuildContext context, AiModel model) {
    return Obx(() {
      final isDownloaded = controller.isDownloaded(model.filename);
      final inference = Get.find<InferenceService>();
      final localImage = Get.find<LocalImageService>();
      final isActive = inference.loadedModelName.value == model.filename ||
          localImage.loadedModelName.value == model.filename;
      // The projector is half of a multimodal download, and it keeps going
      // after the weights land, so the card has to stay in the downloading
      // state until both are in.
      final isDownloadingWeights =
          controller.isDownloadingModel(model.filename);
      final isDownloadingProjector = model.needsMmproj &&
          controller.isDownloadingModel(model.mmprojFilename);
      final isCurrentlyDownloading =
          isDownloadingWeights || isDownloadingProjector;
      final isAnyModelLoading =
          inference.isLoadingModel.value || localImage.isLoadingModel.value;
      final isThisTextModelLoading = inference.isLoadingModel.value &&
          inference.loadingModelName.value == model.filename;
      final isThisImageModelLoading = localImage.isLoadingModel.value &&
          localImage.loadedModelName.value == model.filename;
      final isThisModelLoading =
          isThisTextModelLoading || isThisImageModelLoading;
      final disableActions = controller.isImporting.value ||
          isAnyModelLoading ||
          isCurrentlyDownloading;
      final loadPercent = (inference.modelLoadProgress.value * 100)
          .clamp(0.0, 100.0)
          .toStringAsFixed(0);

      final isEditable = model.isImported || model.isCustom;

      return Dismissible(
        key: ValueKey(model.filename),
        direction: isEditable
            ? DismissDirection.horizontal
            : DismissDirection.startToEnd,
        background: _swipeAction(
            context, Icons.delete_outline, 'delete'.tr, AppColors.error,
            alignment: Alignment.centerLeft),
        secondaryBackground: isEditable
            ? _swipeAction(
                context, Icons.edit_rounded, 'Edit', AppColors.primary,
                alignment: Alignment.centerRight)
            : null,
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            // Left-to-right: same as the trash icon.
            if (disableActions) return false;
            return await _confirmDeleteModel(context, model.filename);
          }
          // Right-to-left: edit imported / custom-url models in place.
          _showEditModelSheet(context, model);
          return false;
        },
        child: Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: isActive
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : Theme.of(context).dividerColor.withValues(alpha: 0.4),
            ),
          ),
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.05)
              : Theme.of(context).cardColor,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            model.name,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _buildModelBadges(context, model),
                          const SizedBox(height: 6),
                          Text(
                            model.descriptionFor(Get.locale),
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.color ??
                                  Colors.grey,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            controller.modelSpecLine(
                                model, controller.modelSizeLabel(model)),
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Theme.of(context).hintColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    if (!isCurrentlyDownloading)
                      Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          if (isDownloaded) ...[
                            FilledButton.tonal(
                              onPressed: isActive || disableActions
                                  ? null
                                  : () => controller.loadModel(model.filename),
                              style: FilledButton.styleFrom(
                                backgroundColor: isActive
                                    ? AppColors.success.withValues(alpha: 0.2)
                                    : null,
                                foregroundColor:
                                    isActive ? AppColors.success : null,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              child: Text(
                                isThisImageModelLoading
                                    ? 'mv_loading'.tr: isThisTextModelLoading
                                        ? '$loadPercent%'
                                        : isActive
                                            ? 'Active'
                                            : 'mv_load_action'.tr,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Vision (mmproj) pairing',
                              onPressed: disableActions
                                  ? null
                                  : () => _showVisionSheet(context, model),
                              icon: Icon(
                                controller.mmprojRefFor(model.filename) != null
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_outlined,
                                size: 20,
                                color:
                                    controller.mmprojRefFor(model.filename) !=
                                            null
                                        ? AppColors.success
                                        : Theme.of(context).hintColor,
                              ),
                            ),
                            IconButton(
                              tooltip: isActive
                                  ? 'mv_unload_model'.tr
                                  : 'mv_delete_model'.tr,
                              onPressed: disableActions
                                  ? null
                                  : isActive
                                      ? () => controller.unloadModel()
                                      : () => _confirmDeleteModel(
                                          context, model.filename),
                              icon: Icon(
                                isActive
                                    ? Icons.eject_outlined
                                    : Icons.delete_outline,
                                size: 20,
                                color: isActive
                                    ? AppColors.warning
                                    : AppColors.error,
                              ),
                            ),
                          ] else ...[
                            FilledButton(
                              onPressed: disableActions
                                  ? null
                                  : () => _confirmDownload(context, model),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              child: Text('get'.tr,
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
                if (isCurrentlyDownloading) ...[
                  const SizedBox(height: 16),
                  if (isDownloadingWeights)
                    _buildInlineDownloadProgress(
                      context,
                      model.filename,
                      label: model.needsMmproj ? 'mv_model_weights'.tr : null,
                      totalFallback: controller.modelSizeLabel(model),
                    ),
                  if (isDownloadingProjector) ...[
                    if (isDownloadingWeights) const SizedBox(height: 14),
                    _buildInlineDownloadProgress(
                      context,
                      model.mmprojFilename,
                      label: 'mv_projector'.tr,
                    ),
                  ],
                ],
                if (isThisModelLoading) ...[
                  const SizedBox(height: 16),
                  _buildModelLoadingProgress(context, model),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildInlineDownloadProgress(
    BuildContext context,
    String filename, {
    String? label,
    String? totalFallback,
  }) {
    final dp = controller.getDownloadProgress(filename);
    // The transfer can finish between the card rebuilding and this call.
    if (dp == null) return const SizedBox.shrink();
    return Obx(() {
      final percent = dp.progress.value * 100;
      final totalLabel = dp.totalBytes.value > 0
          ? formatWholeMb(dp.totalBytes.value)
          : (totalFallback ?? '--');
      final remaining = dp.totalBytes.value <= 0
          ? 0
          : (dp.totalBytes.value - dp.downloadedBytes.value)
              .clamp(0, dp.totalBytes.value);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).hintColor,
              ),
            ),
            const SizedBox(height: 6),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: dp.progress.value > 0 ? dp.progress.value : null,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              color: AppColors.secondary,
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${percent.toStringAsFixed(1)}%',
                style: GoogleFonts.firaCode(
                  fontSize: 13,
                  color: AppColors.secondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  DownloadService.formatSpeed(dp.bytesPerSecond.value),
                  style: GoogleFonts.firaCode(
                    fontSize: 12,
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => controller.pauseDownload(filename),
                icon: const Icon(Icons.close, size: 16),
                label: Text('cancel'.tr),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              Text(
                '${DownloadService.formatWholeMb(dp.downloadedBytes.value)} / $totalLabel',
                style: GoogleFonts.inter(
                    fontSize: 11, color: Theme.of(context).hintColor),
              ),
              if (dp.totalBytes.value > 0)
                Text(
                  '${DownloadService.formatWholeMb(remaining)} left',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: Theme.of(context).hintColor),
                ),
              Text(
                'ETA: ${DownloadService.formatDuration(dp.eta)}',
                style: GoogleFonts.inter(
                    fontSize: 11, color: Theme.of(context).hintColor),
              ),
            ],
          ),
        ],
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Model URL — Modern Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AddModelUrlSheet extends StatefulWidget {
  final TextEditingController nameController;
  final TextEditingController urlController;
  final TextEditingController filenameController;
  final TextEditingController sizeController;
  final TextEditingController templateController;
  final RxBool isVision;
  final RxBool isDetecting;
  final ModelController modelController;

  const _AddModelUrlSheet({
    required this.nameController,
    required this.urlController,
    required this.filenameController,
    required this.sizeController,
    required this.templateController,
    required this.isVision,
    required this.isDetecting,
    required this.modelController,
  });

  @override
  State<_AddModelUrlSheet> createState() => _AddModelUrlSheetState();
}

class _AddModelUrlSheetState extends State<_AddModelUrlSheet> {
  static const _templates = ['chatml', 'llama3', 'gemma', 'phi3', 'custom'];
  Timer? _urlDebounce;
  final RxString _urlError = ''.obs;
  final RxString _urlWarning = ''.obs;

  @override
  void initState() {
    super.initState();
    widget.urlController.addListener(_onUrlChanged);
  }

  @override
  void dispose() {
    widget.urlController.removeListener(_onUrlChanged);
    _urlDebounce?.cancel();
    super.dispose();
  }

  String _detectTemplateFromUrlOrFilename(String url, String filename) {
    final textToSearch = '$url $filename'.toLowerCase();
    if (textToSearch.contains('gemma')) {
      return 'gemma';
    } else if (textToSearch.contains('llama3') ||
        textToSearch.contains('llama-3') ||
        textToSearch.contains('llama_3') ||
        textToSearch.contains('llama 3')) {
      return 'llama3';
    } else if (textToSearch.contains('phi3') ||
        textToSearch.contains('phi-3') ||
        textToSearch.contains('phi_3') ||
        textToSearch.contains('phi 3')) {
      return 'phi3';
    }
    return 'chatml'; // Default fallback
  }

  void _onUrlChanged() {
    final url = widget.urlController.text.trim();
    if (url.isNotEmpty) {
      final filename = widget.modelController.filenameFromUrl(url);
      widget.filenameController.text = filename;
      widget.templateController.text =
          _detectTemplateFromUrlOrFilename(url, filename);
    }

    _urlDebounce?.cancel();
    _urlDebounce = Timer(const Duration(milliseconds: 900), () async {
      if (url.isEmpty) {
        _urlError.value = '';
        _urlWarning.value = '';
        widget.sizeController.text = '';
        return;
      }

      // Check if it is a valid HTTP/HTTPS URL format
      final uri = Uri.tryParse(url);
      if (uri == null ||
          !uri.hasScheme ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        _urlError.value =
            'mv_bad_url'.tr;
        _urlWarning.value = '';
        // **O campo fica VAZIO, e não escrito com um rótulo.** Este campo é
        // editável e o que está nele vai para `AiModel.size` quando o usuário
        // confirma — escrever "Tamanho desconhecido" aqui gravaria a tradução no
        // Hive, e o card passaria a exibir português num app em inglês, para
        // sempre. `_submit` já troca campo vazio pela sentinela, e a linha de
        // aviso logo abaixo é o que a pessoa precisa ler.
        widget.sizeController.text = '';
        return;
      }

      _urlError.value = '';
      _urlWarning.value = '';
      widget.isDetecting.value = true;
      try {
        final sizeLabel = await widget.modelController.detectUrlSize(url);
        if (sizeLabel == AppConstants.kUnknownSize) {
          _urlWarning.value =
              'mv_size_unresolved'.tr;
          widget.sizeController.text = '';
        } else {
          _urlWarning.value = '';
          widget.sizeController.text = sizeLabel;
        }
      } catch (e) {
        _urlWarning.value = 'Could not resolve file size: $e';
        widget.sizeController.text = '';
      } finally {
        widget.isDetecting.value = false;
      }
    });
  }

  Future<void> _detectSize() async {
    final url = widget.urlController.text.trim();
    if (url.isEmpty) return;
    widget.isDetecting.value = true;
    try {
      final sizeLabel = await widget.modelController.detectUrlSize(url);
      if (sizeLabel == AppConstants.kUnknownSize) {
        _urlWarning.value =
            'mv_size_unresolved'.tr;
        widget.sizeController.text = '';
      } else {
        _urlWarning.value = '';
        widget.sizeController.text = sizeLabel;
      }
    } catch (e) {
      _urlWarning.value = 'Could not resolve file size: $e';
      widget.sizeController.text = '';
    } finally {
      widget.isDetecting.value = false;
    }
  }

  Future<void> _submit() async {
    final url = widget.urlController.text.trim();
    if (url.isEmpty) return;

    // Validate format synchronously
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      _urlError.value =
          'mv_bad_url'.tr;
      return;
    }

    if (_urlError.value.isNotEmpty) return;
    _urlDebounce?.cancel();

    await widget.modelController.addModelFromUrl(
      name: widget.nameController.text.trim().isEmpty
          ? widget.filenameController.text
          : widget.nameController.text.trim(),
      url: url,
      filename: widget.filenameController.text,
      size: widget.sizeController.text.isEmpty
          ? AppConstants.kUnknownSize
          : widget.sizeController.text,
      description: 'mv_added_custom_url'.tr,
      template: widget.templateController.text,
      isVision: widget.isVision.value,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF13131F) : const Color(0xFFF8F9FC);
    final fieldBg = isDark ? const Color(0xFF1C1C2C) : Colors.white;
    final borderCol =
        isDark ? const Color(0xFF2A2A3D) : const Color(0xFFE2E8F0);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        margin: EdgeInsets.only(bottom: bottomPadding),
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.border : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 4),

            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xFF1A1A2E), const Color(0xFF13131F)]
                      : [const Color(0xFFF1F5F9), const Color(0xFFF8F9FC)],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, Color(0xFF009B7D)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.add_link_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'add_model_url'.tr,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'mv_download_any_url'.tr,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.textSecondary
                                : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded,
                        color:
                            isDark ? AppColors.textSecondary : Colors.black54,
                        size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor:
                          isDark ? AppColors.surface : const Color(0xFFE2E8F0),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                ],
              ),
            ),

            // Accent divider
            Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  AppColors.primary.withValues(alpha: 0.6),
                  AppColors.secondary.withValues(alpha: 0.3),
                  Colors.transparent,
                ]),
              ),
            ),

            // Scrollable form
            Flexible(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel(
                        label: 'mv_model_url'.tr, color: AppColors.primary),
                    const SizedBox(height: 8),
                    _SheetTextField(
                      controller: widget.urlController,
                      hint: 'mv_url_example'.tr,
                      prefixIcon: Icons.link_rounded,
                      keyboardType: TextInputType.url,
                      bg: fieldBg,
                      border: borderCol,
                    ),
                    Obx(() {
                      if (_urlError.value.isNotEmpty) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 6, left: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded,
                                  size: 13, color: AppColors.error),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _urlError.value,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: AppColors.error,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      } else if (_urlWarning.value.isNotEmpty) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 6, left: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  size: 13, color: Colors.orange),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _urlWarning.value,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }),
                    const SizedBox(height: 20),

                    _SectionLabel(label: 'mv_model_info'.tr),
                    const SizedBox(height: 8),
                    _SheetTextField(
                      controller: widget.nameController,
                      hint: 'mv_display_name_hint'.tr,
                      prefixIcon: Icons.label_outline_rounded,
                      bg: fieldBg,
                      border: borderCol,
                    ),
                    const SizedBox(height: 12),
                    _SheetTextField(
                      controller: widget.filenameController,
                      hint: 'Filename  (e.g. qwen3-0.6b.gguf)',
                      prefixIcon: Icons.insert_drive_file_outlined,
                      bg: fieldBg,
                      border: borderCol,
                    ),
                    const SizedBox(height: 20),

                    _SectionLabel(label: 'mv_file_size'.tr),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _SheetTextField(
                            controller: widget.sizeController,
                            hint: 'e.g. 1.2 GB',
                            prefixIcon: Icons.data_usage_rounded,
                            bg: fieldBg,
                            border: borderCol,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Obx(() => _DetectSizeButton(
                              isLoading: widget.isDetecting.value,
                              onTap: _detectSize,
                            )),
                      ],
                    ),
                    const SizedBox(height: 20),

                    _SectionLabel(label: 'mv_chat_template'.tr),
                    const SizedBox(height: 8),
                    _TemplateSelector(
                      controller: widget.templateController,
                      templates: _templates,
                      bg: fieldBg,
                      border: borderCol,
                      accentColor: AppColors.primary,
                    ),
                    const SizedBox(height: 20),

                    Obx(() => _VisionToggle(
                          value: widget.isVision.value,
                          onChanged: (v) => widget.isVision.value = v,
                          bg: fieldBg,
                          border: borderCol,
                        )),
                    const SizedBox(height: 28),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark
                                  ? AppColors.textSecondary
                                  : Colors.black54,
                              side: BorderSide(color: borderCol),
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text('cancel'.tr,
                                style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600, fontSize: 14)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [AppColors.primary, Color(0xFF009B7D)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.4),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: _submit,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 15),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                          Icons.download_for_offline_rounded,
                                          color: Colors.white,
                                          size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        'add_model'.tr,
                                        style: GoogleFonts.inter(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  final Color color;
  const _SectionLabel({required this.label, this.color = AppColors.textMuted});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolvedColor = color == AppColors.textMuted
        ? (isDark ? AppColors.textMuted : const Color(0xFF64748B))
        : color;
    return Text(
      label,
      style: GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
        color: resolvedColor,
      ),
    );
  }
}

// ── Styled text field ─────────────────────────────────────────────────────────
class _SheetTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData prefixIcon;
  final TextInputType? keyboardType;
  final int maxLines;
  final Color bg;
  final Color border;

  const _SheetTextField({
    required this.controller,
    required this.hint,
    required this.prefixIcon,
    this.keyboardType,
    this.maxLines = 1,
    required this.bg,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: GoogleFonts.inter(
            fontSize: 14,
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w400),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.inter(
              fontSize: 13,
              color: isDark ? AppColors.textMuted : const Color(0xFF94A3B8)),
          prefixIcon: Icon(prefixIcon,
              color: isDark ? AppColors.textMuted : const Color(0xFF94A3B8),
              size: 18),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

// ── Detect Size button ────────────────────────────────────────────────────────
class _DetectSizeButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;
  const _DetectSizeButton({required this.isLoading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: isLoading
              ? (isDark ? AppColors.surface : const Color(0xFFE2E8F0))
              : AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isLoading
                ? (isDark ? AppColors.border : const Color(0xFFCBD5E1))
                : AppColors.primary.withValues(alpha: 0.4),
          ),
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                )
              : const Icon(Icons.radar_rounded,
                  color: AppColors.primary, size: 22),
        ),
      ),
    );
  }
}

// ── Template selector ─────────────────────────────────────────────────────────
class _TemplateSelector extends StatefulWidget {
  final TextEditingController controller;
  final List<String> templates;
  final Color bg;
  final Color border;
  final Color accentColor;

  const _TemplateSelector({
    required this.controller,
    required this.templates,
    required this.bg,
    required this.border,
    required this.accentColor,
  });

  @override
  State<_TemplateSelector> createState() => _TemplateSelectorState();
}

class _TemplateSelectorState extends State<_TemplateSelector> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: widget.templates.map((t) {
          final sel = widget.controller.text == t;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => widget.controller.text = t),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: sel
                      ? widget.accentColor.withValues(alpha: 0.18)
                      : widget.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: sel
                        ? widget.accentColor.withValues(alpha: 0.6)
                        : widget.border,
                    width: sel ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  t,
                  style: GoogleFonts.firaCode(
                    fontSize: 13,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                    color: sel
                        ? widget.accentColor
                        : (isDark
                            ? AppColors.textSecondary
                            : const Color(0xFF64748B)),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Vision toggle ─────────────────────────────────────────────────────────────
class _VisionToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color bg;
  final Color border;

  const _VisionToggle({
    required this.value,
    required this.onChanged,
    required this.bg,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = value
        ? (isDark ? Colors.white : AppColors.secondary)
        : (isDark ? AppColors.textSecondary : Colors.black87);

    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: value ? AppColors.secondary.withValues(alpha: 0.12) : bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: value ? AppColors.secondary.withValues(alpha: 0.5) : border,
            width: value ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: value
                    ? AppColors.secondary.withValues(alpha: 0.2)
                    : (isDark ? AppColors.surface : const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                value ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                color: value
                    ? AppColors.secondary
                    : (isDark ? AppColors.textMuted : const Color(0xFF64748B)),
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'multimodal_model'.tr,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                    ),
                  ),
                  Text(
                    'mv_image_audio_input'.tr,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.textMuted
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.secondary,
              activeTrackColor: AppColors.secondary.withValues(alpha: 0.3),
              inactiveThumbColor:
                  isDark ? AppColors.textMuted : const Color(0xFF94A3B8),
              inactiveTrackColor:
                  isDark ? AppColors.surface : const Color(0xFFE2E8F0),
            ),
          ],
        ),
      ),
    );
  }
}

/// RAM right now, and how many weights are landing on this phone.
///
/// Asked for, and the reason it belongs on the Models screen rather than in
/// Settings is that this is where a model gets downloaded and where a model
/// gets loaded. Both are the moments memory decides the outcome — the ladder
/// asks the probe how many layers fit, and a phone 400 MB short answers
/// differently from one that is not — so a number parked in a settings submenu
/// is a number nobody looks at in time.
///
/// Statefulness here is for one reason: the memory poll has to be started and
/// stopped, and a `build` must not have side effects. Starting a timer from
/// `build` is the same mistake as the `setState() during build` that
/// `ChatController.onInit` used to cause — it just fails quieter, leaking a
/// timer per rebuild instead of throwing. So the widget reconciles the watch
/// after the frame, from `didUpdateWidget` and from the first build.
///
/// The bar is `MemTotal - MemAvailable`, which is what Android's own low-memory
/// killer reasons about. `MemFree` is used nowhere: it excludes reclaimable
/// cache and reads low on a phone while plenty is actually available, which
/// makes it useless for predicting whether a load will fail.
class _DeviceLoadCard extends StatefulWidget {
  const _DeviceLoadCard(
      {required this.controller, required this.busy, super.key});

  /// The download map is the only controller state this card reads reactively,
  /// and it lives on the controller, so the controller comes along. A top-level
  /// widget cannot see the view's `controller` field, and reaching for a global
  /// `Get.find` would hide the dependency instead of passing it.
  final ModelController controller;

  /// Whether anything is happening that can move the numbers. Owned by the
  /// parent so the decision of *what counts as busy* is visible where the
  /// sources of busy-ness are.
  final bool busy;

  @override
  State<_DeviceLoadCard> createState() => _DeviceLoadCardState();
}

class _DeviceLoadCardState extends State<_DeviceLoadCard> {
  /// What the service is currently doing, so a rebuild that changes nothing
  /// does not cancel and restart a two-second timer.
  bool _watching = false;

  void _sync(bool busy) {
    if (busy == _watching) return;
    _watching = busy;
    // The service owns the decision (accelerator facts live in the service,
    // never in the UI). This only reports the state it should watch, and does
    // it after the frame so no build ever starts a timer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (Get.isRegistered<DeviceInfoService>()) {
        Get.find<DeviceInfoService>().watchMemory(on: busy);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _sync(widget.busy);
  }

  @override
  void didUpdateWidget(covariant _DeviceLoadCard old) {
    super.didUpdateWidget(old);
    _sync(widget.busy);
  }

  @override
  void dispose() {
    // A screen that goes away must not leave a timer polling /proc for a card
    // nobody is looking at.
    if (_watching && Get.isRegistered<DeviceInfoService>()) {
      Get.find<DeviceInfoService>().watchMemory(on: false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final info = Get.find<DeviceInfoService>();
      // The service hands over bytes; what they mean is decided in
      // `memory_readout.dart`, which is pure and tested. Doing the arithmetic
      // here instead would put the three claims that can be silently wrong —
      // readable, tight, what fraction — outside the reach of a test.
      final m = info.memory.value;

      // Nothing readable here (web, iOS, or a failed read): no card. A bar at
      // 0% would read as "the phone is out of memory", which is a different
      // claim, and a worse one to make up.
      if (!memoryIsReadable(m)) return const SizedBox.shrink();

      final total = m.totalBytes;
      final free = m.availableBytes;
      final active = widget.controller.activeDownloads.length;
      final accent = Theme.of(context).colorScheme.primary;
      final tight = isMemoryTight(m);
      final hint = Theme.of(context).hintColor;

      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Material(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.memory_rounded,
                        size: 18, color: tight ? AppColors.warning : accent),
                    const SizedBox(width: 8),
                    Text('mv_memory_label'.tr,
                        style: GoogleFonts.inter(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    // The reason a person watches this: enough left for the
                    // model they are about to pick, not a percentage for its
                    // own sake.
                    Text(
                      preencher('mv_memory_free', {
                        'f': formatWholeMb(free),
                        't': formatWholeMb(total),
                      }),
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: tight ? AppColors.warning : hint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: memoryUsedFraction(m),
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    color: tight ? AppColors.warning : AppColors.secondary,
                    minHeight: 5,
                  ),
                ),
                if (tight) ...[
                  const SizedBox(height: 8),
                  Text(
                    'mv_low_memory'.tr,
                    style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.warning),
                  ),
                ],
                if (active > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    active == 1
                        ? 'mv_one_download'.tr: '$active downloads in progress · each own bar is on '
                            'its card',
                    style: GoogleFonts.inter(fontSize: 11.5, color: hint),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }
}
