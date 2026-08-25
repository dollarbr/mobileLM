import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/download_service.dart';
import '../services/inference_service.dart';
import '../services/local_image_service.dart';
import '../services/hive_service.dart';
import '../services/app_log_service.dart';
import '../services/device_info_service.dart';
import '../models/ai_model.dart';
import '../core/constants.dart';
import 'settings_controller.dart';

enum _ModelLoadAction { cancel, unload, continueLoad }

class ModelController extends GetxController {
  final DownloadService _download = Get.find<DownloadService>();
  final LocalImageService _localImage = Get.find<LocalImageService>();
  final InferenceService _inference = Get.find<InferenceService>();
  final HiveService _hive = Get.find<HiveService>();
  final SettingsController _settings = Get.find<SettingsController>();

  static const _customModelsKey = 'custom_url_models';
  static const _androidImportChannel =
      MethodChannel('com.aichat.ai_chat/model_import');

  Map<String, DownloadProgress> get activeDownloads =>
      _download.activeDownloads;

  final availableModels = <AiModel>[].obs;
  final downloadedFiles = <String>[].obs;
  final isImporting = false.obs;
  final customModels = <AiModel>[].obs;
  final fileSizes = <String, int>{}.obs;
  final modelScope = 'local'.obs;
  final localFilter = ''.obs;
  final importFileName = ''.obs;
  final importStatus = ''.obs;
  final importCopiedBytes = 0.obs;
  final importTotalBytes = 0.obs;
  final importBytesPerSecond = 0.0.obs;
  final sortSmallestFirst = true.obs;
  final externalDownloadId = Rx<int?>(null);

  void toggleSort() {
    sortSmallestFirst.value = !sortSmallestFirst.value;
  }

  static const localFilters = [
    'downloaded',
    'general',
    'image',
    'uncensored',
    'vision'
  ];

  List<AiModel> get displayedModels {
    final active = _inference.loadedModelName.value;
    final models = [...availableModels];
    models.sort((a, b) {
      if (a.filename == active) return -1;
      if (b.filename == active) return 1;
      final aDownloaded = isDownloaded(a.filename);
      final bDownloaded = isDownloaded(b.filename);
      if (aDownloaded != bDownloaded) return aDownloaded ? -1 : 1;

      if (sortSmallestFirst.value) {
        final aBytes = _knownModelBytes(a);
        final bBytes = _knownModelBytes(b);
        if (aBytes > 0 && bBytes > 0 && aBytes != bBytes) {
          return aBytes.compareTo(bBytes);
        }
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return models;
  }

  List<AiModel> get filteredDisplayedModels {
    final filter =
        localFilter.value.isEmpty ? defaultLocalFilter : localFilter.value;
    return displayedModels.where((model) {
      switch (filter) {
        case 'downloaded':
          return isDownloaded(model.filename);
        case 'uncensored':
          return isUncensoredModel(model);
        case 'vision':
          return isVisionModel(model);
        case 'image':
          return isImageModel(model);
        case 'general':
        default:
          return isGeneralModel(model);
      }
    }).toList();
  }

  String get defaultLocalFilter =>
      downloadedFiles.isNotEmpty ? 'downloaded' : 'general';

  double get importProgress => importTotalBytes.value <= 0
      ? 0.0
      : (importCopiedBytes.value / importTotalBytes.value)
          .clamp(0.0, 1.0)
          .toDouble();

  int get downloadedCount => downloadedFiles.length;

  String get activeLocalModelName => _inference.loadedModelName.value;

  @override
  void onInit() {
    super.onInit();
    _loadCustomModels();
    availableModels.value = AppConstants.availableModels
        .map((m) => AiModel.fromMap(m))
        .toList()
      ..addAll(customModels);
    refreshDownloaded();
    _loadMmprojOverrides();
  }

  void _loadCustomModels() {
    final raw =
        _hive.getSetting<List>(_customModelsKey, defaultValue: []) ?? [];
    customModels.value = raw
        .whereType<Map>()
        .map((m) => AiModel.fromMap(Map<String, String>.from(m)))
        .toList();
  }

  Future<void> _saveCustomModels() async {
    await _hive.setSetting(
      _customModelsKey,
      customModels.map((m) => m.toMap()).toList(),
    );
  }

  Future<void> refreshDownloaded() async {
    await _deletePartialImports();
    final files = (await _download.getDownloadedModels())
        .where((file) => !_isAuxiliaryImageFile(file))
        .toList();
    downloadedFiles.value = files;
    for (final file in files) {
      fileSizes[file] = await _download.getModelSize(file);
    }

    // Add any downloaded files that are not in availableModels
    final existingFilenames = availableModels.map((m) => m.filename).toSet();
    for (final file in files) {
      if (!existingFilenames.contains(file)) {
        final lower = file.toLowerCase();
        final runtime = AiModel.runtimeFromFilename(file);
        final isLiteRt = runtime == AiModel.runtimeLiteRt;
        final isVision = isLiteRt && AiModel.hasVisionMarker(lower);

        availableModels.add(AiModel(
          name: file,
          filename: file,
          url: '',
          size: _formatModelSize(file),
          description: 'Imported from local storage',
          template: isLiteRt ? 'litert' : 'chatml',
          runtime: runtime,
          isImported: true,
          isVision: isVision,
        ));
      }
    }

    // Remove any imported models that are no longer downloaded
    bool isStaleImport(AiModel m) =>
        m.isImported && !files.contains(m.filename);
    availableModels.removeWhere(isStaleImport);
    if (customModels.any(isStaleImport)) {
      customModels.removeWhere(isStaleImport);
      await _saveCustomModels();
    }

    if (localFilter.value.isEmpty) {
      localFilter.value = defaultLocalFilter;
    }
  }

  bool isDownloaded(String filename) => downloadedFiles.contains(filename);

  bool _isAuxiliaryImageFile(String filename) {
    final lower = filename.toLowerCase();
    return lower == 'taesd.safetensors' ||
        lower.startsWith('taesd-') ||
        lower.startsWith('taesd_') ||
        lower == 'diffusion_pytorch_model.safetensors' ||
        lower.endsWith('.vae.safetensors') ||
        lower.startsWith('vae-') ||
        lower.startsWith('vae_');
  }

  bool _isIncompleteCatalogFile(AiModel model, int fileBytes) {
    if (model.url.trim().isEmpty || model.isImported || fileBytes <= 0) {
      return false;
    }
    final expectedBytes = _declaredModelBytes(model);
    if (expectedBytes <= 0) return false;
    // Relax threshold to 85% to comfortably accommodate HuggingFace decimal-scaled catalog sizes 
    // and rounded metadata sizes (e.g. 770.3MB listed as 0.8GB) while still blocking failed downloads.
    return fileBytes < (expectedBytes * 0.85).round();
  }

  bool get isDownloading => _download.isDownloadingAny;

  String get lastLoadedModelName =>
      _hive.getSetting<String>(AppConstants.keyLocalModelName) ?? '';

  bool get canLoadLastModel =>
      lastLoadedModelName.isNotEmpty && isDownloaded(lastLoadedModelName);

  DownloadProgress? getDownloadProgress(String filename) =>
      _download.activeDownloads[filename];

  bool isDownloadingModel(String filename) =>
      _download.activeDownloads.containsKey(filename);

  void setLocalFilter(String filter) {
    if (localFilters.contains(filter)) {
      localFilter.value = filter;
    }
  }

  /// What to call this model's extra inputs, for badges and chips.
  ///
  /// "Vision" undersells the LiteRT-LM multimodal files: gemma-3n and gemma-4
  /// carry an audio encoder in the same file and take speech as readily as
  /// images. The internal flag stays named `vision` because it is what gates
  /// the encoder in the LiteRT config — this is the user-facing word only.
  String modalityLabel(AiModel model) =>
      isLiteRtModel(model) || model.needsMmproj ? 'MULTIMODAL' : 'VISION';

  bool isVisionModel(AiModel model) {
    // GGUF models see through a projector: without a paired mmproj file the
    // weights alone cannot read an image, however the model is named.
    if (!isLiteRtModel(model)) return model.needsMmproj;
    final lower =
        '${model.name} ${model.filename} ${model.description}'.toLowerCase();
    return model.isVision || AiModel.hasVisionMarker(lower);
  }

  bool isUncensoredModel(AiModel model) {
    return AppConstants.isUncensoredModelName(
      '${model.name} ${model.filename} ${model.description}',
    );
  }

  bool isImageModel(AiModel model) {
    final lower = model.filename.toLowerCase();
    return model.runtime == AiModel.runtimeSd ||
        lower.endsWith('.safetensors') ||
        model.template == 'sd';
  }

  bool isLiteRtModel(AiModel model) {
    return model.runtime == AiModel.runtimeLiteRt ||
        model.filename.toLowerCase().endsWith('.litertlm');
  }

  bool isLlamaModel(AiModel model) {
    return model.runtime == AiModel.runtimeLlama ||
        model.filename.toLowerCase().endsWith('.gguf');
  }

  bool isGeneralModel(AiModel model) =>
      !isVisionModel(model) &&
      !isUncensoredModel(model) &&
      !isImageModel(model);

  String modelSizeLabel(AiModel model) {
    final bytes = fileSizes[model.filename] ?? 0;
    if (bytes > 0) return DownloadService.formatBytes(bytes);
    return model.size;
  }

  int _knownModelBytes(AiModel model) {
    final detected = fileSizes[model.filename] ?? 0;
    if (detected > 0) return detected;
    return _declaredModelBytes(model);
  }

  int _declaredModelBytes(AiModel model) {
    final match = RegExp(r'([\d.]+)\s*(GB|MB)', caseSensitive: false)
        .firstMatch(model.size);
    if (match == null) return 0;
    final value = double.tryParse(match.group(1) ?? '') ?? 0;
    final unit = (match.group(2) ?? '').toUpperCase();
    if (unit == 'GB') return (value * 1024 * 1024 * 1024).round();
    if (unit == 'MB') return (value * 1024 * 1024).round();
    return 0;
  }

  String _formatModelSize(String filename) {
    final bytes = fileSizes[filename] ?? 0;
    if (bytes <= 0) return 'Local File';
    return DownloadService.formatBytes(bytes);
  }

  // ── Per-model spec line (params · context · quant) ──────────────────
  /// Filled lazily per card. GGUF headers are read straight from disk —
  /// header-only, milliseconds even on multi-GB files — while LiteRT files
  /// carry no such header, so only what is true by construction shows.
  final modelSpecs = <String, ModelSpec>{}.obs;
  final Set<String> _specLoading = {};

  /// Cached spec, kicking off the read on first ask. Safe to call during
  /// build: the first call returns null and the RxMap insert re-renders.
  ModelSpec? specFor(AiModel model) {
    if (!_specLoading.contains(model.filename)) {
      _specLoading.add(model.filename);
      _loadSpec(model);
    }
    return modelSpecs[model.filename];
  }

  Future<void> _loadSpec(AiModel model) async {
    var params = _paramsFromFilename(model.filename);
    final quant = _quantFromFilename(model.filename);
    int? ctx;
    try {
      if (await _download.isModelDownloaded(model.filename)) {
        final path = await _download.modelPath(model.filename);
        final meta = await LlamaModelMeta.probeFile(path);
        ctx = int.tryParse(meta['context_length'] ?? '');
        // The exporter knows its own count; the filename guess only fills in.
        final label = meta['size_label'];
        if (label != null && label.isNotEmpty) params = label;
      }
    } catch (_) {}
    if (ctx == null && isLiteRtModel(model)) {
      // .litertlm headers carry no context field; the app clamps every
      // LiteRT conversation to this cap, so stating it is not a guess.
      ctx = AppConstants.liteRtContextCap;
    }
    modelSpecs[model.filename] =
        ModelSpec(paramsLabel: params, contextLength: ctx, quantLabel: quant);
  }

  /// Largest "NB" token in the filename (`1B`, `1.2B`, the B in `E2B`), or
  /// null. Same shape as the HF sheet's memory gate: the name is the one
  /// place small models always advertise their size.
  static final RegExp _paramRe =
      RegExp(r'(?:^|[^a-z0-9])(\d+(?:\.\d+)?)\s?b(?=[^a-z0-9]|$)');

  String? _paramsFromFilename(String filename) {
    String? best;
    num bestVal = -1;
    for (final m in _paramRe.allMatches(filename.toLowerCase())) {
      final v = num.tryParse(m.group(1)!);
      if (v != null && v > bestVal) {
        bestVal = v;
        best = '${m.group(1)}B';
      }
    }
    return best;
  }

  /// Trailing quantization tag, uppercase by convention (`…-Q4_K_M.gguf`).
  static final RegExp _quantRe =
      RegExp(r'(IQ?[2-8][A-Z0-9_]*|F16|BF16|F32)(?=\.gguf$)');

  String? _quantFromFilename(String filename) =>
      _quantRe.firstMatch(filename)?.group(1);

  /// The card's fact line: `"4.3 GB · 1.6B · 32k ctx · Q4_0"`. Size first,
  /// then whatever the spec could honestly state.
  String modelSpecLine(AiModel model, String sizeLabel) {
    final parts = <String>[if (sizeLabel.isNotEmpty) sizeLabel];
    final spec = specFor(model);
    if (spec != null) {
      if (spec.paramsLabel != null) parts.add(spec.paramsLabel!);
      if (spec.contextLength != null) {
        final n = spec.contextLength!;
        parts.add('${n >= 1024 ? '${(n / 1024).round()}k' : n} ctx');
      }
      if (spec.quantLabel != null) parts.add(spec.quantLabel!);
    }
    return parts.join(' · ');
  }

  String filenameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final segment = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : 'model.gguf';
    final decoded = Uri.decodeComponent(segment.split('?').first);
    if (decoded.toLowerCase().endsWith('.gguf') ||
        decoded.toLowerCase().endsWith('.litertlm') ||
        decoded.toLowerCase().endsWith('.safetensors')) {
      return decoded;
    }
    return '$decoded.gguf';
  }

  Future<String> detectUrlSize(String url) async {
    try {
      final bytes = await _download.getRemoteFileSize(url);
      if (bytes <= 0) return 'Unknown size';
      return DownloadService.formatBytes(bytes);
    } catch (_) {
      return 'Unknown size';
    }
  }

  Future<void> addModelFromUrl({
    required String name,
    required String url,
    String? filename,
    String? description,
    String template = 'chatml',
    String? size,
    bool isVision = false,
    String mmprojUrl = '',
    String mmprojFilename = '',
  }) async {
    final resolvedFilename = (filename == null || filename.trim().isEmpty)
        ? filenameFromUrl(url)
        : filename.trim();

    final model = AiModel(
      name: name.trim().isEmpty ? resolvedFilename : name.trim(),
      filename: resolvedFilename,
      url: url.trim(),
      size: size == null || size.trim().isEmpty ? 'Unknown size' : size.trim(),
      description: description == null || description.trim().isEmpty
          ? 'Added from custom URL'
          : description.trim(),
      template: template.trim().isEmpty ? 'chatml' : template.trim(),
      runtime: AiModel.runtimeFromFilename(
        resolvedFilename,
        template: template.trim().isEmpty ? 'chatml' : template.trim(),
      ),
      isVision: isVision &&
          AiModel.runtimeFromFilename(
                resolvedFilename,
                template: template.trim().isEmpty ? 'chatml' : template.trim(),
              ) ==
              AiModel.runtimeLiteRt,
      isCustom: true,
      mmprojUrl: mmprojUrl.trim(),
      mmprojFilename: mmprojFilename.trim(),
    );

    customModels.removeWhere((m) => m.filename == model.filename);
    customModels.add(model);
    availableModels.removeWhere((m) => m.filename == model.filename);
    availableModels.add(model);
    await _saveCustomModels();
  }

  /// Updates a custom model's metadata (name, description, url, template, etc.)
  /// in both [customModels] and [availableModels], then persists to Hive.
  Future<void> updateCustomModel(AiModel updated) async {
    final index = customModels.indexWhere((m) => m.filename == updated.filename);
    if (index != -1) {
      customModels[index] = updated;
    } else {
      // Imported models are rebuilt from disk on every refreshDownloaded(),
      // so the edited copy has to be persisted here or it is lost.
      customModels.add(updated);
    }
    final availIndex =
        availableModels.indexWhere((m) => m.filename == updated.filename);
    if (availIndex != -1) {
      availableModels[availIndex] = updated;
    }
    await _saveCustomModels();
  }

  Future<void> downloadModel(AiModel model) async {
    try {
      await _download.downloadModel(
        url: model.url,
        filename: model.filename,
      );
      // A multimodal GGUF is two files, so "download" has to mean both:
      // fetching the projector only at load time makes the first load stall
      // on a second transfer the user never asked for, or silently come up
      // text-only if it fails. The load path keeps its own fetch as a
      // fallback, for models added before this and for a failed projector.
      if (model.needsMmproj &&
          !await _download.isModelDownloaded(model.mmprojFilename)) {
        await _download.downloadModel(
          url: model.mmprojUrl,
          filename: model.mmprojFilename,
        );
      }
      await refreshDownloaded();
    } catch (e) {
      Get.find<AppLogService>().error('Model download failed', details: e);
      Get.snackbar('Download Failed', '$e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> downloadModelToDownloads(AiModel model) async {
    if (model.url.trim().isEmpty) {
      Get.snackbar('Download Unavailable', 'This model has no download URL.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    if (!Platform.isAndroid) {
      Get.snackbar(
        'Android Only',
        'Use the app download button or import a local model on this platform.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    try {
      isImporting.value = true;
      importFileName.value = model.filename;
      importStatus.value = 'Starting download...';
      importCopiedBytes.value = 0;
      importTotalBytes.value = 0;
      importBytesPerSecond.value = 0;

      final result =
          await _androidImportChannel.invokeMapMethod<String, dynamic>(
        'downloadToDownloads',
        {'url': model.url, 'filename': model.filename},
      );
      externalDownloadId.value = result?['downloadId'] as int?;
      final filename = result?['filename'] as String? ?? model.filename;
      Get.snackbar(
        'Download Started',
        '$filename is downloading to your Downloads folder.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } on PlatformException catch (e) {
      isImporting.value = false;
      externalDownloadId.value = null;
      Get.find<AppLogService>().error(
        'Download to Downloads failed',
        details: '${e.code}: ${e.message}',
      );
      Get.snackbar('Download Failed', e.message ?? e.code,
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      isImporting.value = false;
      externalDownloadId.value = null;
      Get.find<AppLogService>()
          .error('Download to Downloads failed', details: e);
      Get.snackbar('Download Failed', '$e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> cancelExternalDownload() async {
    final id = externalDownloadId.value;
    if (id != null) {
      try {
        await _androidImportChannel.invokeMethod('cancelDownloadToDownloads', {'downloadId': id});
      } catch (e) {
        Get.find<AppLogService>().error('Cancel download failed', details: e);
      }
      externalDownloadId.value = null;
      isImporting.value = false;
      importStatus.value = 'Download cancelled';
    }
  }

  void pauseDownload(String filename) {
    _download.pauseDownload(filename);
  }

  Future<void> deleteModel(String filename) async {
    await _download.deleteModel(filename);
    await refreshDownloaded();
    // Unload if this was the active model
    if (_inference.loadedModelName.value == filename) {
      await _inference.unloadModel();
    }
  }

  // ── Per-model vision (mmproj) pairing ──────────────────────────────
  // model filename -> projector filename in the models dir, or an absolute
  // path for files picked straight from device storage.
  static const String _mmprojOverridesKey = 'mmproj_overrides';
  Map<String, String> _mmprojOverrides = {};

  Map<String, String> get mmprojOverrides => _mmprojOverrides;

  Future<void> _loadMmprojOverrides() async {
    try {
      final raw =
          Get.find<HiveService>().getSetting<String>(_mmprojOverridesKey);
      if (raw != null && raw.isNotEmpty) {
        _mmprojOverrides =
            (jsonDecode(raw) as Map<String, dynamic>).cast<String, String>();
      }
    } catch (_) {}
  }

  String? mmprojRefFor(String modelFilename) => _mmprojOverrides[modelFilename];

  Future<void> setMmprojOverride(String modelFilename, String? ref) async {
    if (ref == null || ref.isEmpty) {
      _mmprojOverrides.remove(modelFilename);
    } else {
      _mmprojOverrides[modelFilename] = ref;
    }
    try {
      await Get.find<HiveService>().setSetting(_mmprojOverridesKey,
          jsonEncode(_mmprojOverrides));
    } catch (_) {}
  }

  /// Copies a user-picked file into the models dir and pairs it with
  /// [modelFilename]. The copy survives re-imports of the weights.
  Future<void> importMmprojFor(String modelFilename) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gguf', 'bin'],
    );
    final picked = result?.files.single;
    if (picked == null || picked.path == null) return;
    final dest = '${await _download.modelsDir}/${picked.name}';
    await File(picked.path!).copy(dest);
    await setMmprojOverride(modelFilename, picked.name);
    Get.snackbar('Vision', 'Projector paired: ${picked.name}',
        snackPosition: SnackPosition.BOTTOM);
  }

  /// mmproj files already inside the models dir — the landing spot for
  /// projectors fetched through HF search.
  Future<List<String>> downloadedMmprojCandidates() async {
    try {
      final dir = Directory(await _download.modelsDir);
      return dir
          .listSync()
          .whereType<File>()
          .where((f) {
            final name = f.path.split('/').last.toLowerCase();
            return name.endsWith('.gguf') && name.contains('mmproj');
          })
          .map((f) => f.path)
          .toList()
        ..sort();
    } catch (_) {
      return const [];
    }
  }

  /// Exports downloaded model files to a directory the user picks — a plain
  /// backup of what is on disk. Android may refuse writes outside app space
  /// on secondary storage; that surfaces as an error snackbar.
  // ── Backup progress ─────────────────────────────────────────────────
  final isBackingUp = false.obs;
  final backupFile = ''.obs;
  final backupCopiedBytes = 0.obs;
  final backupTotalBytes = 0.obs;
  final backupDoneFiles = 0.obs;
  final backupTotalFiles = 0.obs;

  /// Byte offsets of each file inside the overall backup, so per-file events
  /// from the platform channel drive one continuous bar.
  Map<String, int> _backupOffsets = {};

  void onBackupProgress({required String filename, required int copied}) {
    if (!isBackingUp.value) return;
    final size = _fileSizes[filename] ?? 0;
    final clamped = copied.clamp(0, size);
    backupFile.value = filename;
    backupCopiedBytes.value =
        (_backupOffsets[filename] ?? 0) + clamped;
    backupTotalBytes.value = _backupOffsets.values.isEmpty
        ? 0
        : _backupOffsets.entries
            .map((e) => e.value + (_fileSizes[e.key] ?? 0))
            .reduce((a, b) => a > b ? a : b);
    backupDoneFiles.value =
        _backupOffsets.keys.where((f) => f != filename).length;
    backupTotalFiles.value = _backupOffsets.length;
  }

  Map<String, int> _fileSizes = const {};

  /// Vendor/family folder names for the on-disk layout, relative to the
  /// tree root — the same tree backupConfigs writes:
  /// `<root>/settings/privatelm-config.json` plus
  /// `<root>/<Vendor>/<Family>/<file>` for the weights. GGUF metadata wins
  /// when it carries general.organization; otherwise the filename decides.
  /// Returns segments AFTER the tree root: [vendor, family].
  Future<List<String>> classifyModelPath(String filePath) async {
    final name = filePath.split('/').last.toLowerCase();

    String vendor = 'Unknown';
    String family = '';
    if (name.contains('gemma')) {
      vendor = 'Google';
      family =
          'Gemma' + (RegExp(r'gemma-?(\d)').firstMatch(name)?.group(1) ?? '');
    } else if (name.contains('granite')) {
      vendor = 'IBM';
      family = 'Granite' +
          (RegExp(r'granite[-_]?(\d+(?:\.\d+)?)').firstMatch(name)?.group(1) ??
              '');
    } else if (name.contains('lfm')) {
      vendor = 'LiquidAI';
      final m = RegExp(r'lfm([\d.]+)').firstMatch(name);
      family = 'LFM' + (m?.group(1) ?? '');
    } else if (name.contains('llama')) {
      vendor = 'Meta';
      family = 'Llama' +
          (RegExp(r'llama-?(\d+(?:\.\d+)?)').firstMatch(name)?.group(1) ?? '');
    } else if (name.contains('qwen')) {
      vendor = 'Alibaba';
      family = 'Qwen' +
          (RegExp(r'qwen[\._]?(\d+(?:\.\d+)?)').firstMatch(name)?.group(1) ??
              '');
    } else if (name.contains('phi')) {
      vendor = 'Microsoft';
      family = 'Phi' + (RegExp(r'phi-?(\d)').firstMatch(name)?.group(1) ?? '');
    } else if (name.contains('minicpm')) {
      vendor = 'OpenBMB';
      family = 'MiniCPM';
    } else if (name.contains('mistral') || name.contains('mixtral')) {
      vendor = 'MistralAI';
      family = 'Mistral';
    } else if (name.contains('deepseek')) {
      vendor = 'DeepSeek';
      family = 'DeepSeek';
    }

    if (filePath.endsWith('.gguf')) {
      try {
        final org = await LlamaModelMeta.get('general.organization');
        if (org != null && org.trim().isNotEmpty && org != '-') {
          vendor = org
              .split(RegExp(r'[\s_-]+'))
              .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
              .join('');
        }
        final basename = await LlamaModelMeta.get('general.basename');
        if (basename != null &&
            basename.trim().isNotEmpty &&
            family.isEmpty) {
          family = basename.split('/').last;
        }
      } catch (_) {}
    }
    if (family.isEmpty) {
      final stem = name.endsWith('.gguf')
          ? name.replaceAll(RegExp(r'\.gguf$'), '')
          : name.replaceAll(RegExp(r'\.litertlm$'), '');
      family = stem.split('-').first;
    }
    return [vendor, family];
  }

  Future<void> backupConfigs({
    required bool includeModels,
    Set<String> modelFiles = const {},
  }) async {
    final log = Get.find<AppLogService>();
    final hive = Get.find<HiveService>();
    var treeUri = hive.getSetting<String>(AppConstants.keyBackupTreeUri);
    if (treeUri == null || treeUri.isEmpty) {
      try {
        treeUri = await _download.pickBackupDirectory();
      } catch (e) {
        log.error('Backup: folder picker threw', details: '$e');
      }
      if (treeUri == null || treeUri.isEmpty) {
        Get.snackbar('Backup', 'No folder selected',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
      await hive.setSetting(AppConstants.keyBackupTreeUri, treeUri);
    }

    isBackingUp.value = true;
    backupDoneFiles.value = 0;
    String? settingsDoc;

    try {
      // Models follow the user's on-disk tree (Vendor/Family/file); configs
      // live in <root>/settings so they never mix with weights.
      settingsDoc = await _download.ensureBackupPath(
          treeUri: treeUri, segments: const ['settings']);
      if (settingsDoc == null) {
        throw Exception('Could not create the settings folder');
      }

      // Configs first: small, and the part that makes the copy meaningful.
      final template = await buildConfigTemplate();
      final tmp = File(
          '${(await getTemporaryDirectory()).path}/privatelm-config.json');
      await tmp.writeAsString(jsonEncode(template));
      _fileSizes = {'privatelm-config.json': await tmp.length()};
      _backupOffsets = {'privatelm-config.json': 0};
      backupTotalFiles.value = 1 + (includeModels ? modelFiles.length : 0);
      backupFile.value = 'settings/privatelm-config.json';
      final cfgOutcome = await _download.copyToBackupDirectory(
        treeUri: treeUri,
        name: 'privatelm-config.json',
        sourcePath: tmp.path,
        parentDocUri: settingsDoc,
      );
      await tmp.delete();
      if (cfgOutcome == 0) {
        throw Exception('Could not write privatelm-config.json');
      }
      backupDoneFiles.value = 1;

      if (includeModels && modelFiles.isNotEmpty) {
        final all = [
          for (final name in modelFiles)
            '${await _download.modelsDir}/$name',
        ].where((p) => File(p).existsSync()).toList();
        _fileSizes = {for (final p in all) p.split('/').last: File(p).lengthSync()};
        var offset = 0;
        _backupOffsets = {
          for (final p in all)
            p.split('/').last: (() {
              final o = offset;
              offset += File(p).lengthSync();
              return o;
            })(),
        };
        backupTotalBytes.value = offset;
        backupTotalFiles.value = all.length + 1;
        var skipped = 0;
        for (final src in all) {
          final name = src.split('/').last;
          backupFile.value = name;
          final segs = await classifyModelPath(src);
          final destDoc = await _download.ensureBackupPath(
              treeUri: treeUri, segments: segs);
          if (destDoc == null) {
            log.error('Backup: could not create ${segs.join("/")}');
            continue;
          }
          // 0 failed · 1 copied · 2 already identical on destination.
          final outcome = await _download.copyToBackupDirectory(
            treeUri: treeUri,
            name: name,
            sourcePath: src,
            parentDocUri: destDoc,
          );
          if (outcome > 0) {
            backupDoneFiles.value++;
            backupCopiedBytes.value += _fileSizes[name] ?? 0;
            if (outcome == 2) skipped++;
          } else {
            log.error('Backup: failed to copy $name -> ${segs.join("/")}');
          }
        }
        if (skipped > 0) {
          log.info('Backup: $skipped file(s) skipped (already identical)');
        }
      }
      log.info('Backup done (settings/ + Vendor/Family tree)');
      Get.snackbar('Backup',
          'Saved: configs in settings/ + models in Vendor/Family folders',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 5));
    } catch (e) {
      log.error('Backup failed', details: '$e');
      Get.snackbar('Backup failed', '$e',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 6));
    } finally {
      isBackingUp.value = false;
    }
  }

  /// Restores a config template picked with the system file picker. Model
  /// files come separately via [restoreModelsFromBackup].
  Future<void> restoreConfigs() async {
    final result = await FilePicker.pickFiles(type: FileType.any);
    final path = result?.files.single.path;
    if (path == null) return;
    try {
      final config =
          jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      if (config['type'] != 'privatelm-config') {
        throw Exception('Not a mobileLM config backup.');
      }
      final settingsCount = (config['settings'] as Map?)?.length ?? 0;
      final confirmed = await _confirmRestore(settingsCount);
      if (!confirmed) return;
      await applyConfigTemplate(config);
      Get.snackbar('Restore', 'Configs applied. Restart to fully reload.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 6));
      final restart = await _askRestart();
      if (restart) await _download.restartApp();
    } catch (e) {
      Get.find<AppLogService>().error('Restore failed', details: '$e');
      Get.snackbar('Restore failed', '$e',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 6));
    }
  }

  Future<bool> _confirmRestore(int settingsCount) async {
    var confirmed = false;
    await Get.dialog(AlertDialog(
      title: const Text('Restore configs?'),
      content: Text('$settingsCount saved value(s) will overwrite the current ones.'),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
        FilledButton(
            onPressed: () {
              confirmed = true;
              Get.back();
            },
            child: const Text('Restore')),
      ],
    ));
    return confirmed;
  }

  Future<bool> _askRestart() async {
    var restart = false;
    await Get.dialog(AlertDialog(
      title: const Text('Restart now?'),
      content: const Text('Some settings only load at app start.'),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text('Later')),
        FilledButton(
            onPressed: () {
              restart = true;
              Get.back();
            },
            child: const Text('Restart')),
      ],
    ));
    return restart;
  }

  /// Copies model files back out of a backup folder the user picks. Returns
  /// how many landed; pairs are rebuilt by filename.
  Future<int> restoreModelsFromBackup() async {
    final hive = Get.find<HiveService>();
    var treeUri = hive.getSetting<String>(AppConstants.keyBackupTreeUri);
    if (treeUri == null || treeUri.isEmpty) {
      treeUri = await _download.pickBackupDirectory();
      if (treeUri == null || treeUri.isEmpty) return 0;
      await hive.setSetting(AppConstants.keyBackupTreeUri, treeUri);
    }
    // Walk the whole granted tree — models live in Vendor/Family folders.
    final entries = await _download.walkBackupTree(treeUri: treeUri);
    final seen = <String>{};
    final files = entries.where((e) {
      final name = e['name'] as String;
      if ((e['size'] as num? ?? 0) <= 0) return false;
      if (!name.endsWith('.gguf') && !name.endsWith('.litertlm')) {
        return false;
      }
      return seen.add(name); // first hit wins on duplicate names
    }).toList();
    if (files.isEmpty) {
      Get.snackbar('Restore', 'No model files found in the backup folder.',
          snackPosition: SnackPosition.BOTTOM);
      return 0;
    }
    final dir = Directory(await _download.modelsDir);
    var restored = 0;
    isBackingUp.value = true;
    backupTotalFiles.value = files.length;
    for (final entry in files) {
      final name = entry['name'] as String;
      final size = (entry['size'] as num?)?.toInt() ?? 0;
      final dest = File('${dir.path}/$name');
      if (dest.existsSync() && dest.lengthSync() == size) continue;
      backupFile.value = name;
      final ok = await _download.copyFromBackupDirectory(
          treeUri: treeUri, name: name, destPath: dest.path, subFolder: 'models');
      if (ok) restored++;
      backupDoneFiles.value = restored;
    }
    isBackingUp.value = false;
    await refreshDownloaded();
    Get.snackbar('Restore', '$restored model file(s) restored',
        snackPosition: SnackPosition.BOTTOM);
    return restored;
  }

  /// Keys that must never leave the device, and device-local state that
  /// would be meaningless (or harmful) on another install.
  bool _isExportableSetting(String key) {
    final k = key.toLowerCase();
    if (k.contains('api_key') || k.contains('token')) return false;
    if (k.startsWith(AppConstants.keyCustomCloudProfiles)) return false;
    if (k == AppConstants.keyBackupTreeUri) return false;
    if (k.startsWith('local_model_')) return false;
    if (k.startsWith('litert_gpu_')) return false;
    if (k.startsWith(AppConstants.autoFastBenchKeyPrefix)) return false;
    if (k.startsWith(AppConstants.visionBenchKeyPrefix)) return false;
    return true;
  }

  Future<Map<String, dynamic>> buildConfigTemplate() async {
    final hive = Get.find<HiveService>();
    final settings = <String, dynamic>{};
    for (final key in hive.settingsBox.keys) {
      if (_isExportableSetting(key.toString())) {
        settings[key.toString()] = hive.settingsBox.get(key);
      }
    }
    return {
      'type': 'privatelm-config',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'appVersion': Get.find<SettingsController>().appVersion.value,
      'settings': settings,
      'mmprojOverrides': _mmprojOverrides,
      'modelParams': {
        for (final key in hive.settingsBox.keys)
          if (key
              .toString()
              .startsWith(AppConstants.modelParamsKeyPrefix))
            key.toString():
                jsonDecode(hive.settingsBox.get(key).toString()),
      },
    };
  }

  Future<void> applyConfigTemplate(Map<String, dynamic> config,
      {bool models = false}) async {
    final log = Get.find<AppLogService>();
    var applied = 0;
    final settings = config['settings'];
    if (settings is Map) {
      final hive = Get.find<HiveService>();
      settings.forEach((key, value) {
        if (_isExportableSetting(key)) {
          hive.setSetting(key, value);
          applied++;
        }
      });
      final overrides = config['mmprojOverrides'];
      if (overrides is Map) {
        _mmprojOverrides = overrides.cast<String, String>();
        await hive.setSetting(_mmprojOverridesKey,
            jsonEncode(_mmprojOverrides));
      }
      final params = config['modelParams'];
      if (params is Map) {
        params.forEach((key, value) =>
            hive.setSetting(key, jsonEncode(value)));
      }
    }
    log.info('Restore: $applied setting(s), '
        'models=$models from ${config['exportedAt']}');
  }

  /// Finds a `*mmproj*.gguf` next to [modelPath], smallest first. HF ships
  /// projectors beside the weights, so an imported pair just works without
  /// any catalogue entry.
  Future<String?> _findSiblingMmproj(String modelPath) async {
    try {
      final dir = Directory(File(modelPath).parent.path);
      final candidates = dir
          .listSync()
          .whereType<File>()
          .where((f) {
            final name = f.path.split('/').last.toLowerCase();
            return name.endsWith('.gguf') &&
                name.contains('mmproj') &&
                f.path != modelPath;
          })
          .toList()
        ..sort((a, b) => a.lengthSync().compareTo(b.lengthSync()));
      if (candidates.isEmpty) return null;
      print('[ModelController] Sibling projector found: '
          '${candidates.first.path.split('/').last}');
      return candidates.first.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> loadModel(String filename) async {
    if (_inference.isLoadingModel.value) {
      Get.snackbar('Model Loading', 'Another model is already loading.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    final path = await _download.modelPath(filename);
    final model =
        availableModels.firstWhereOrNull((m) => m.filename == filename);
    if (_isAuxiliaryImageFile(filename)) {
      Get.snackbar(
        'Helper File',
        '$filename is used internally by image generation and cannot be loaded as a model.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    final isLiteRt = filename.toLowerCase().endsWith('.litertlm') ||
        model?.runtime == AiModel.runtimeLiteRt;
    final targetRuntime =
        model?.runtime ?? AiModel.runtimeFromFilename(filename);
    if (_inference.requiresAppRestartForRuntime(targetRuntime)) {
      await _showRuntimeRestartDialog(
        currentRuntime: _inference.sessionNativeRuntime,
        targetRuntime: targetRuntime,
      );
      return;
    }
    final fileBytes = await _modelFileBytes(filename, path, model);
    if (model != null && _isIncompleteCatalogFile(model, fileBytes)) {
      final actual = DownloadService.formatBytes(fileBytes);
      Get.find<AppLogService>().error(
        'Incomplete model file blocked',
        details:
            '$filename is $actual, expected about ${model.size}',
      );
      Get.snackbar(
        'Incomplete Model File',
        '$filename is only $actual. Delete it and download again.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
      return;
    }
    if (filename.toLowerCase().endsWith('.safetensors') &&
        !await _hasValidSafetensorsHeader(path)) {
      Get.find<AppLogService>().error(
        'Corrupt safetensors file blocked',
        details: '$filename failed safetensors header validation',
      );
      Get.snackbar(
        'Corrupt Model File',
        '$filename did not download correctly. Delete it and download again.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
      return;
    }
    if (isLiteRt && !await _hasLikelyValidLiteRtFile(path, fileBytes)) {
      Get.find<AppLogService>().error(
        'Corrupt LiteRT model file blocked',
        details: '$filename failed LiteRT file validation; size=$fileBytes',
      );
      Get.snackbar(
        'Corrupt Model File',
        '$filename is not a valid LiteRT-LM file. Delete it and download again.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 6),
      );
      return;
    }
    final loadAction = await _confirmModelLoadSafety(
      filename: filename,
      fileBytes: fileBytes,
      isLiteRt: isLiteRt,
    );
    if (loadAction == _ModelLoadAction.cancel) return;
    if (loadAction == _ModelLoadAction.unload) {
      await unloadModel();
      return;
    }
    if (isLiteRt && !await _confirmLiteRtGpuWarning()) return;

    if (isImageModel(model ??
        AiModel(
          name: filename,
          filename: filename,
          url: '',
          size: '',
          description: '',
          template: '',
        ))) {
      // Auto-download TAESD for fast VAE decode if not present
      String? taesdPath;
      try {
        const taesdFilename = 'taesd.safetensors';
        const taesdUrl = 'https://huggingface.co/madebyollin/taesd/resolve/main/diffusion_pytorch_model.safetensors';
        final hasTaesd = await _download.isModelDownloaded(taesdFilename);
        if (!hasTaesd) {
          print('[ModelController] TAESD not found, downloading...');
          await _download.downloadModel(url: taesdUrl, filename: taesdFilename);
          print('[ModelController] TAESD downloaded successfully');
        } else {
          print('[ModelController] TAESD already present');
        }
        taesdPath = await _download.modelPath(taesdFilename);
      } catch (e) {
        print('[ModelController] TAESD download failed (will use standard VAE): $e');
      }

      // Show loading dialog with live logs
      _showImageModelLoadingDialog(filename);
      final result = await _localImage.loadModel(path, modelName: filename, taesdPath: taesdPath);
      // Close loading dialog
      if (Get.isDialogOpen ?? false) Get.back();

      final isError = !_localImage.isModelLoaded.value;
      Get.snackbar(
        isError ? 'Model Not Loaded' : 'Image Model',
        result,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: isError
            ? const Color(0xFFFF9500).withValues(alpha: 0.15)
            : const Color(0xFF34C759).withValues(alpha: 0.15),
        colorText: isError ? const Color(0xFFFF9500) : const Color(0xFF34C759),
        duration:
            isError ? const Duration(seconds: 6) : const Duration(seconds: 2),
      );
    } else {
      // A multimodal GGUF is two files. Fetch the projector before loading, so
      // a first run on a fresh install still comes up with vision rather than
      // silently downgrading to text.
      String? mmprojPath;
      if (model != null && model.needsMmproj) {
        try {
          if (!await _download.isModelDownloaded(model.mmprojFilename)) {
            // Only queue it if nothing is fetching it already: downloadModel
            // now starts the projector alongside the weights, so loading
            // while that is still in flight would enqueue the same file twice.
            if (!isDownloadingModel(model.mmprojFilename)) {
              print('[ModelController] Projector missing, downloading...');
              await _download.downloadModel(
                  url: model.mmprojUrl, filename: model.mmprojFilename);
            }
            // On Android the call above only queues the transfer, so without
            // this the load would hand mtmd a path to a file that does not
            // exist yet and come up text-only.
            if (!await _download.awaitDownload(model.mmprojFilename)) {
              throw Exception('Projector download did not complete');
            }
          }
          mmprojPath = await _download.modelPath(model.mmprojFilename);
        } catch (e) {
          print('[ModelController] Projector download failed: $e');
        }
      }

      // Explicit pairing wins over everything; then the catalogue entry;
      // then any mmproj file sitting next to the weights. HF ships projectors
      // as "mmproj-<stem>.gguf" beside the GGUF, so an imported pair just
      // works without any configuration.
      if (mmprojPath == null) {
        final ref = mmprojRefFor(filename);
        if (ref != null && ref.isNotEmpty) {
          mmprojPath = ref.startsWith('/')
              ? ref
              : await _download.modelPath(ref);
        }
      }
      mmprojPath ??= await _findSiblingMmproj(path);

      final result = await _inference.loadModel(
        path,
        modelName: filename,
        modelRuntime: model?.runtime,
        enableLiteRtVision: model == null ? false : isVisionModel(model),
        mmprojPath: mmprojPath,
      );
      if (_inference.isModelLoaded.value) {
        final fallbackToText = result.toLowerCase().contains('text-only');
        _inference.isVisionLoaded.value =
            fallbackToText ? false : (model == null ? false : isVisionModel(model));
        await _settings.setInferenceMode('local');
        Get.snackbar('Model Loaded', result,
            snackPosition: SnackPosition.BOTTOM);
      } else {
        bool showDetails = false;
        Get.dialog(
          StatefulBuilder(
            builder: (context, setState) {
              final friendlyMsg = _getFriendlyErrorMessage(result);
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final detailBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
              final detailBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
              
              return AlertDialog(
                backgroundColor: Theme.of(context).dialogTheme.backgroundColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error.withValues(alpha: isDark ? 0.15 : 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.error_outline_rounded,
                        color: Theme.of(context).colorScheme.error,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Model Load Failed',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        friendlyMsg,
                        style: GoogleFonts.inter(
                          fontSize: 14, 
                          height: 1.5,
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'TROUBLESHOOTING TIPS',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildTipRow(context, Icons.delete_outline_rounded, 'Delete the model and try redownloading it completely.'),
                      _buildTipRow(context, Icons.memory_rounded, 'Ensure your device has at least 2-3 GB of free RAM.'),
                      if (result.toLowerCase().contains('litert') || filename.toLowerCase().endsWith('.litertlm'))
                        _buildTipRow(context, Icons.settings_suggest_rounded, 'Double check if this LiteRT-LM file matches your architecture.'),
                      const SizedBox(height: 12),

                      // Technical Details Toggle Button
                      InkWell(
                        onTap: () => setState(() => showDetails = !showDetails),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                showDetails ? 'Hide Technical Details' : 'Show Technical Details',
                                style: GoogleFonts.inter(
                                  fontSize: 12, 
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              Icon(
                                showDetails ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                      ),

                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        child: showDetails
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 8),
                                  Container(
                                    constraints: const BoxConstraints(maxHeight: 180),
                                    width: double.maxFinite,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: detailBg,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: detailBorder, width: 1),
                                    ),
                                    child: SingleChildScrollView(
                                      child: SelectableText(
                                        result,
                                        style: GoogleFonts.firaCode(
                                          fontSize: 11,
                                          height: 1.4,
                                          color: isDark ? const Color(0xFFFDA4AF) : const Color(0xFF9F1239),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Get.back(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(
                      'Close',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      }
    }
  }

  Future<void> _showRuntimeRestartDialog({
    required String currentRuntime,
    required String targetRuntime,
  }) async {
    final currentLabel = _runtimeLabel(currentRuntime);
    final targetLabel = _runtimeLabel(targetRuntime);
    await Get.dialog<void>(
      AlertDialog(
        title: const Text('Restart required'),
        content: Text(
          'You already used $currentLabel in this app session. '
          'Switching to $targetLabel without restarting can crash the native runtime.\n\n'
          'Restart the app, then load this model.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Get.back();
              try {
                await _androidImportChannel.invokeMethod('restartApp');
              } catch (_) {
                SystemNavigator.pop();
              }
            },
            child: const Text('Restart app'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  String _runtimeLabel(String runtime) {
    switch (runtime.toLowerCase()) {
      case AiModel.runtimeLiteRt:
        return 'LiteRT';
      case AiModel.runtimeLlama:
        return 'GGUF';
      default:
        return 'local model';
    }
  }

  Future<int> _modelFileBytes(
    String filename,
    String path,
    AiModel? model,
  ) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.length();
        fileSizes[filename] = bytes;
        return bytes;
      }
    } catch (_) {}
    final cached = fileSizes[filename] ?? 0;
    if (cached > 0) return cached;
    return model == null ? 0 : _knownModelBytes(model);
  }

  Future<bool> _hasValidSafetensorsHeader(String path) async {
    RandomAccessFile? raf;
    try {
      final file = File(path);
      final length = await file.length();
      if (length < 16) return false;
      raf = await file.open();
      final bytes = await raf.read(16);
      if (bytes.length < 16) return false;

      var headerLength = 0;
      for (var i = 0; i < 8; i++) {
        headerLength += bytes[i] << (8 * i);
      }

      if (headerLength <= 2 || headerLength > length - 8) return false;
      if (headerLength > 64 * 1024 * 1024) return false;
      return bytes[8] == 0x7B;
    } catch (_) {
      return false;
    } finally {
      await raf?.close();
    }
  }

  Future<bool> _hasLikelyValidLiteRtFile(String path, int fileBytes) async {
    RandomAccessFile? raf;
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final length = await file.length();
      if (length < 10 * 1024 * 1024) return false;

      raf = await file.open();
      final bytes = await raf.read(16);
      if (bytes.length < 8) return false;

      // Verify LiteRT-LM magic identifier 'LITERTLM' at bytes 0-7
      final hasLmLiteRt = bytes[0] == 0x4C && // 'L'
          bytes[1] == 0x49 && // 'I'
          bytes[2] == 0x54 && // 'T'
          bytes[3] == 0x45 && // 'E'
          bytes[4] == 0x52 && // 'R'
          bytes[5] == 0x54 && // 'T'
          bytes[6] == 0x4C && // 'L'
          bytes[7] == 0x4D; // 'M'

      if (hasLmLiteRt) {
        return true;
      }

      // Note: We intentionally DO NOT allow standard TFLite models starting with 'TFL3' at offset 4
      // if they lack the 'LITERTLM' container header, because the native LiteRT-LM engine 
      // strictly expects the .litertlm conversational bundle structure and will crash with a
      // SIGABRT native assert check failure if it is not present.
      return false;
    } catch (_) {
      return false;
    } finally {
      await raf?.close();
    }
  }

  Future<_ModelLoadAction> _confirmModelLoadSafety({
    required String filename,
    required int fileBytes,
    required bool isLiteRt,
  }) async {
    final availableRamGb = await _refreshAvailableRamGb();

    final availableBytes = (availableRamGb * 1024 * 1024 * 1024).round();
    final modelLabel = fileBytes > 0
        ? DownloadService.formatWholeMb(fileBytes)
        : 'Unknown size';
    final ramLabel = availableBytes > 0
        ? DownloadService.formatWholeMb(availableBytes)
        : 'Unknown';
    final lower = filename.toLowerCase();
    final hasMeasuredMemory = availableBytes > 0 && fileBytes > 0;
    final isCriticallyLow = hasMeasuredMemory &&
        (availableBytes < fileBytes || _isLowMemoryBytes(availableBytes));
    final isLargeForRam =
        availableBytes > 0 && fileBytes > 0 && availableBytes < fileBytes * 2;
    final isLowRam = availableBytes > 0 && _isLowMemoryBytes(availableBytes);
    final String warning;
    if (isCriticallyLow) {
      warning =
          'Available RAM is lower than recommended. This can crash the app if Android cannot reserve enough memory.';
    } else if (isLargeForRam || isLowRam || isLiteRt) {
      warning =
          'This can crash the app if Android cannot reserve enough memory for the model.';
    } else {
      warning = 'Loading local models can use more memory than the file size.';
    }
    final runtimeLabel = isLiteRt
        ? 'LiteRT-LM'
        : lower.endsWith('.gguf')
            ? 'GGUF'
            : lower.endsWith('.safetensors')
                ? 'Image model'
                : 'Local model';
    final loadedName = _inference.loadedModelName.value;
    final hasLoadedModel =
        _inference.isModelLoaded.value && loadedName.isNotEmpty;
    final isSameModelLoaded = hasLoadedModel && loadedName == filename;

    final result = await Get.dialog<_ModelLoadAction>(
      AlertDialog(
        title: Text(isCriticallyLow ? 'Restart recommended' : 'Load model?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(filename),
            const SizedBox(height: 12),
            Text('Runtime: $runtimeLabel'),
            Text('Available RAM: $ramLabel'),
            Text('Model size: $modelLabel'),
            if (hasLoadedModel) ...[
              const SizedBox(height: 12),
              Text(
                isSameModelLoaded
                    ? 'This model is already loaded.'
                    : 'Already loaded: $loadedName',
              ),
              if (!isSameModelLoaded)
                const Text('Unload it before loading another model.'),
            ],
            const SizedBox(height: 12),
            Text(warning),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: _ModelLoadAction.cancel),
            child: const Text('Cancel'),
          ),
          if (hasLoadedModel)
            TextButton(
              onPressed: () => Get.back(result: _ModelLoadAction.unload),
              child: const Text('Unload'),
            ),
          if (isCriticallyLow)
            TextButton(
              onPressed: () async {
                Get.back(result: _ModelLoadAction.cancel);
                try {
                  await _androidImportChannel.invokeMethod('restartApp');
                } catch (_) {
                  SystemNavigator.pop();
                }
              },
              child: const Text('Restart app'),
            ),
          ElevatedButton(
            onPressed: () async {
              await _refreshAvailableRamGb();
              Get.back(result: _ModelLoadAction.continueLoad);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
    return result ?? _ModelLoadAction.cancel;
  }

  Future<bool> _confirmLiteRtGpuWarning() async {
    final mode = _settings.liteRtPerformanceMode.value;
    if (mode == 'cpu_safe') return true;

    final accepted = _hive.getSetting<bool>(
          AppConstants.keyLiteRtGpuWarningAccepted,
          defaultValue: false,
        ) ??
        false;
    if (accepted) return true;

    final modeLabel = mode == 'gpu_fast' ? 'GPU Fast' : 'Auto Fast';
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: Text('$modeLabel LiteRT speed'),
        content: const Text(
          'GPU can make LiteRT models much faster, closer to Edge Gallery speed. '
          'On some phones GPU/OpenCL can crash the app while loading. '
          'If that happens, Auto Fast will use CPU on the next load.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Continue'),
          ),
        ],
      ),
      barrierDismissible: false,
    );

    if (confirmed == true) {
      await _hive.setSetting(AppConstants.keyLiteRtGpuWarningAccepted, true);
      return true;
    }
    return false;
  }

  bool _isLowMemoryBytes(int bytes) => bytes < 768 * 1024 * 1024;

  Future<double> _refreshAvailableRamGb() async {
    try {
      final device = Get.find<DeviceInfoService>();
      await device.refreshMemoryInfo();
      return device.availableRamGB.value;
    } catch (_) {
      return 0;
    }
  }

  void _showImageModelLoadingDialog(String filename) {
    final localImage = Get.find<LocalImageService>();
    Get.dialog(
      Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Get.isDarkMode ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 20),
              Text(
                'Loading $filename',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Obx(() {
                final log = localImage.latestLog.value;
                if (log.isEmpty) {
                  return const Text(
                    'Initializing model...',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  );
                }
                return Text(
                  log,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                );
              }),
            ],
          ),
        ),
      ),
      barrierDismissible: false,
    );
  }

  Future<void> unloadModel() async {
    await _inference.unloadModel();
    await _localImage.unloadModel();
  }

  Future<void> importModelFromStorage() async {
    if (isImporting.value) {
      Get.snackbar(
          'Import in Progress', 'Wait for the current import to finish.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    if (Platform.isAndroid) {
      await _importModelWithAndroidPicker();
      return;
    }

    String? partialImportPath;
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.any,
        withData: false,
        withReadStream: true,
      );

      if (result != null) {
        final picked = result.files.single;
        final filename = picked.name;
        final lower = filename.toLowerCase();

        if (!lower.endsWith('.gguf') &&
            !lower.endsWith('.litertlm') &&
            !lower.endsWith('.safetensors')) {
          Get.snackbar('Unsupported Model',
              'Only .gguf, .litertlm, and .safetensors files can be imported.',
              snackPosition: SnackPosition.BOTTOM);
          return;
        }

        final file = picked.path == null ? null : File(picked.path!);
        final totalBytes = picked.size > 0
            ? picked.size
            : file == null
                ? 0
                : await file.length();
        if (totalBytes <= 0) {
          Get.snackbar('Import Failed', 'The selected file is empty.',
              snackPosition: SnackPosition.BOTTOM);
          return;
        }

        final sourceStream = picked.readStream ?? file?.openRead();
        if (sourceStream == null) {
          Get.snackbar(
            'Import Failed',
            'Unable to read the selected file. Try selecting it from local storage.',
            snackPosition: SnackPosition.BOTTOM,
          );
          return;
        }

        final modelsDir = await _download.modelsDir;
        final destPath = '$modelsDir/$filename';
        final partPath = '$destPath.part';
        partialImportPath = partPath;
        final destFile = File(destPath);
        final partFile = File(partPath);
        var shouldReplace = false;

        if (await destFile.exists()) {
          final replace = await _confirmReplace(filename);
          if (!replace) return;
          shouldReplace = true;
        }

        isImporting.value = true;
        importFileName.value = filename;
        importStatus.value = 'Copying to app storage...';
        importCopiedBytes.value = 0;
        importTotalBytes.value = totalBytes;
        importBytesPerSecond.value = 0;

        if (await partFile.exists()) {
          await partFile.delete();
        }

        await _copyWithProgress(sourceStream, partFile);
        if (shouldReplace && await destFile.exists()) {
          await destFile.delete();
        }
        await partFile.rename(destPath);
        fileSizes[filename] = await File(destPath).length();

        await refreshDownloaded();
        localFilter.value = 'downloaded';
        importStatus.value = 'Import complete';
        Get.snackbar('Import Successful', 'Model $filename imported.',
            snackPosition: SnackPosition.BOTTOM);
      }
    } catch (e) {
      if (partialImportPath != null) {
        final partialFile = File(partialImportPath);
        if (await partialFile.exists()) {
          await partialFile.delete();
        }
      }
      Get.find<AppLogService>().error('Model import failed', details: e);
      Get.snackbar('Import Failed', '$e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isImporting.value = false;
      importFileName.value = '';
      importStatus.value = '';
      importCopiedBytes.value = 0;
      importTotalBytes.value = 0;
      importBytesPerSecond.value = 0;
    }
  }

  Future<void> _importModelWithAndroidPicker() async {
    try {
      isImporting.value = true;
      importFileName.value = '';
      importStatus.value = 'Select a model file...';
      importCopiedBytes.value = 0;
      importTotalBytes.value = 0;
      importBytesPerSecond.value = 0;

      final result =
          await _androidImportChannel.invokeMapMethod<String, dynamic>(
        'pickAndImportModel',
        {'modelsDir': await _download.modelsDir},
      );

      if (result?['cancelled'] == true) return;

      final filename = result?['filename'] as String?;
      if (filename != null && filename.isNotEmpty) {
        fileSizes[filename] = (result?['bytes'] as num?)?.toInt() ??
            await _download.getModelSize(filename);
        await refreshDownloaded();
        localFilter.value = 'downloaded';
        Get.snackbar('Import Successful', 'Model $filename imported.',
            snackPosition: SnackPosition.BOTTOM);
      }
    } on PlatformException catch (e) {
      Get.find<AppLogService>().error(
        'Android model import failed',
        details: '${e.code}: ${e.message}',
      );
      Get.snackbar('Import Failed', e.message ?? e.code,
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.find<AppLogService>()
          .error('Android model import failed', details: e);
      Get.snackbar('Import Failed', '$e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isImporting.value = false;
      importFileName.value = '';
      importStatus.value = '';
      importCopiedBytes.value = 0;
      importTotalBytes.value = 0;
      importBytesPerSecond.value = 0;
    }
  }

  Future<void> _copyWithProgress(
    Stream<List<int>> source,
    File destination,
  ) async {
    final startedAt = DateTime.now();
    final sink = destination.openWrite();
    try {
      await for (final chunk in source) {
        sink.add(chunk);
        importCopiedBytes.value += chunk.length;
        final elapsed =
            DateTime.now().difference(startedAt).inMilliseconds / 1000;
        if (elapsed > 0) {
          importBytesPerSecond.value = importCopiedBytes.value / elapsed;
        }
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close();
      if (await destination.exists()) {
        await destination.delete();
      }
      rethrow;
    }
  }

  Future<bool> _confirmReplace(String filename) async {
    final result = await Get.dialog<bool>(
      Builder(
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          
          return AlertDialog(
            backgroundColor: Theme.of(context).dialogTheme.backgroundColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: isDark ? 0.15 : 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.copy_all_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Model Already Exists',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              'A model file named "$filename" is already imported in your local app storage. Would you like to replace it?',
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.5,
                color: isDark ? Colors.white70 : Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(result: false),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Get.back(result: true),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
                child: Text(
                  'Replace File',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    return result ?? false;
  }

  Future<void> _deletePartialImports() async {
    try {
      final dir = Directory(await _download.modelsDir);
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.part')) {
          await entity.delete();
        }
      }
    } catch (_) {}
  }

  String _getFriendlyErrorMessage(String rawError) {
    final lower = rawError.toLowerCase();
    if (lower.contains('unknown model architecture') ||
        lower.contains('unsupported model architecture')) {
      return 'This GGUF uses a model architecture that is not supported by the bundled llama.cpp runtime. Update the app runtime or try a GGUF exported for a supported architecture.';
    }
    if (lower.contains('missing key') ||
        lower.contains('failed to load gguf split')) {
      return 'This appears to be a split GGUF model, but one or more required model files are missing. Import every split into the same folder before loading it.';
    }
    if (lower.contains('failed to load model from buffer') ||
        lower.contains('invalid_argument') ||
        lower.contains('invalid gguf') ||
        lower.contains('missing or unreadable') ||
        lower.contains('incomplete') ||
        lower.contains('corrupt')) {
      return 'The model file appears to be incomplete or corrupted. This usually happens when the download is interrupted or the file is invalid.';
    }
    if (lower.contains('out of memory') ||
        lower.contains('allocate') ||
        lower.contains('oom') ||
        lower.contains('cannot allocate')) {
      return 'Your device ran out of memory (RAM) trying to load this model. Mobile devices have strict memory limits; try using a smaller or more highly quantized model (e.g., 1B or 3B parameters, q4_k_m quantized).';
    }
    if (lower.contains('opencl') ||
        lower.contains('vulkan') ||
        lower.contains('opengl') ||
        lower.contains('gpu') ||
        lower.contains('cl_') ||
        lower.contains('driver')) {
      return 'A hardware or GPU driver error occurred while initializing the model. Try disabling GPU acceleration or switching to CPU-only inference in Settings.';
    }
    return 'The native AI engine encountered an unexpected error while loading the model. Please check the technical details below for more information.';
  }

  Widget _buildTipRow(BuildContext context, IconData icon, String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: isDark ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.45,
                color: isDark ? Colors.white70 : Colors.black87,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
