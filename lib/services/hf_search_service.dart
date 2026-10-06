import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:get/get.dart';

import '../core/constants.dart';

/// One repository as it comes back from a Hugging Face search.
class HfRepo {
  final String id;
  final int downloads;
  final int likes;

  /// What the hub says the repo is for. Empty on the many GGUF repos that
  /// never set one — absence is not evidence of incompatibility, so those are
  /// kept rather than filtered out.
  final String pipelineTag;

  const HfRepo({
    required this.id,
    this.downloads = 0,
    this.likes = 0,
    this.pipelineTag = '',
  });

  String get owner => id.contains('/') ? id.split('/').first : '';
  String get name => id.contains('/') ? id.split('/').last : id;
}

/// A vision or audio projector shipped alongside the weights.
class HfProjector {
  final String repoId;
  final String path;
  final int sizeBytes;

  const HfProjector({
    required this.repoId,
    required this.path,
    required this.sizeBytes,
  });

  String get filename => path.split('/').last;
  String get url => 'https://huggingface.co/$repoId/resolve/main/$path';

  /// Traduzido, como [HfFile.sizeLabel]. O projetor não vai para
  /// `AiModel.size` — ele tem o próprio campo `mmprojFilename` — então aqui
  /// basta o rótulo de tela.
  String get sizeLabel => _rotulo(_formatBytes(sizeBytes));
  String get quant => _quantOf(filename);
}

/// One downloadable GGUF inside a repository.
///
/// A repo usually holds the same weights at half a dozen quantisation levels,
/// so the file — not the repo — is what a user actually picks.
class HfFile {
  final String repoId;
  final String path;
  final int sizeBytes;

  /// The repo's projectors, smallest first. A multimodal GGUF is useless
  /// without one, so they travel with the file rather than as separate entries
  /// the user has to know to match up.
  final List<HfProjector> projectors;

  const HfFile({
    required this.repoId,
    required this.path,
    required this.sizeBytes,
    this.projectors = const [],
  });

  String get filename => path.split('/').last;
  String get url => 'https://huggingface.co/$repoId/resolve/main/$path';
  bool get isMultimodal => projectors.isNotEmpty;

  /// LiteRT-LM weights rather than a GGUF. They carry their encoders inside
  /// the file, so they never pair with a projector.
  bool get isLiteRt => filename.toLowerCase().endsWith('.litertlm');

  /// The projector to offer first: the smallest one.
  ///
  /// Repos that ship several differ only by quantisation, and on a phone the
  /// F16 encoder can cost more RAM than the model it serves (LFM2.5-VL: 856 MB
  /// against 583 MB for the Q8_0) for a quality difference nobody sees.
  HfProjector? get recommendedProjector =>
      projectors.isEmpty ? null : projectors.first;

  /// Quantisation as written in the filename ("Q4_K_M"), or an empty string
  /// when the name does not follow the convention.
  String get quant => _quantOf(filename);

  /// O rótulo como a pessoa lê, **traduzido**.
  ///
  /// É getter e não constante porque `.tr` é método de runtime sobre o locale
  /// atual: um `static const` congelaria a língua do boot, que não é a que a
  /// pessoa escolheu.
  String get sizeLabel => _rotulo(_formatBytes(sizeBytes));

  /// O mesmo rótulo **sem traduzir**, para o valor que vai para `AiModel.size`.
  ///
  /// A distinção existe porque [AppConstants.kUnknownSize] é uma sentinela
  /// guardada no Hive e comparada com `==`, e a ficha do modelo importado por
  /// aqui a recebe como valor. Passar a tradução nesse caminho gravaria
  /// português num app configurado para inglês, para sempre.
  String get sizeValor => _formatBytes(sizeBytes);

  /// Weights plus [projector], which is what the download actually costs.
  String totalSizeLabel([HfProjector? projector]) =>
      _rotulo(_formatBytes(sizeBytes + (projector?.sizeBytes ?? 0)));
}

/// Traduz o rótulo de tamanho, e só ele.
///
/// O único valor que precisa de tradução é a sentinela — `1.2 GB` é o mesmo
/// texto nos dois idiomas. A checagem é por igualdade com a constante e não por
/// lista, porque **a sentinela é o valor que o campo guarda** e trocar a
/// comparação por uma heurística seria trocar uma comparação exata por uma
/// adivinhação.
String _rotulo(String formatado) =>
    formatado == AppConstants.kUnknownSize ? 'mc_unknown_size'.tr : formatado;

/// The marker can sit on the repo or on any file inside it, so both are read.
bool _repoIsQuantAware(Map<dynamic, dynamic> raw) {
  final id = (raw['id'] ?? raw['modelId'] ?? '').toString();
  if (isQuantizationAware(id)) return true;
  final tags = (raw['tags'] as List?)?.join(' ') ?? '';
  if (isQuantizationAware(tags)) return true;
  final siblings = raw['siblings'] as List?;
  if (siblings == null) return false;
  return siblings.whereType<Map>().any(
      (f) => isQuantizationAware((f['rfilename'] ?? '').toString()));
}

String _quantOf(String filename) {
  final match =
      RegExp(r'(IQ|Q)\d+(_[A-Z0-9]+)*|BF16|F16|F32', caseSensitive: false)
          .firstMatch(filename);
  return match?.group(0)?.toUpperCase() ?? '';
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return AppConstants.kUnknownSize;
  const gb = 1024 * 1024 * 1024;
  const mb = 1024 * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
  return '${(bytes / mb).round()} MB';
}

/// The on-device runtimes this app has, as a hub query.
///
/// Two formats rather than one because mobileLM ships both llama.cpp and
/// LiteRT-LM, and a GGUF-only browser hid half of what it can actually load.
enum HfFormat {
  any('hf_any', ''),
  gguf('GGUF', 'gguf'),
  liteRtLm('LiteRT-LM', 'litert-lm');

  const HfFormat(this.labelKey, this.tag);

  /// **A chave de tradução do rótulo, e não o rótulo.** `'Any'` é o único dos
  /// três que é palavra em inglês — `GGUF` e `LiteRT-LM` são nome de formato e
  /// não se traduzem — e um `label` cru aqui é texto de tela que nenhuma das
  /// três varreduras alcança, porque o enum mora em `lib/services`.
  final String labelKey;

  /// O rótulo já traduzido, e é o que a view pinta.
  String get label => labelKey.tr;

  /// The hub tag that selects it. `litert-lm` and not `litert`: the latter also
  /// catches TTS, detection and image models built for the runtime.
  final String tag;
}

/// Whether a repo or file name advertises weights that were trained knowing
/// they would be quantised — quantisation-aware training, distillation or
/// fine-tuning. Each vendor names its own recipe: Google ships QAT, Liquid
/// ships QAD, and suffixed forms like `QAT-SFT` or `QAT_RLHF` turn up too.
///
/// Matching is on whole tokens, never substrings, because three letters catch
/// far too much otherwise: `Qabalah-12B` is a model name and `qafast` is a
/// user handle, neither has anything to do with quantisation.
bool isQuantizationAware(String text) {
  final lower = text.toLowerCase();
  if (lower.contains('quantization-aware') ||
      lower.contains('quantization aware') ||
      lower.contains('quantisation-aware') ||
      lower.contains('quantisation aware')) {
    return true;
  }
  for (final token in lower.split(RegExp(r'[^a-z0-9]+'))) {
    if (_quantAwareMarkers.contains(token)) return true;
  }
  return false;
}

/// Deliberately short. `dq` and `qab` were measured against the hub and match
/// nothing but merge suffixes and model names, so they stay out — a filter
/// that returns noise is worse than one that misses.
const _quantAwareMarkers = {'qat', 'qad', 'qaft'};

/// What a repo's upstream checkpoint says it is, from its `config.json`.
///
/// The point of this is to be read *before* a GGUF is downloaded, which is the
/// only moment advice is worth anything. Everything here is a claim about the
/// checkpoint; whether a particular conversion delivered it is a separate
/// question, answered by reading the GGUF's own header — and the two disagree
/// often enough that neither can stand in for the other.
class HfConfig {
  const HfConfig({
    required this.repoId,
    required this.architectures,
    required this.modelType,
    required this.embPooler,
    required this.labels,
  });

  final String repoId;
  final List<String> architectures;
  final String modelType;
  final String embPooler;
  final List<String> labels;

  /// Whether the checkpoint declares a classification head.
  ///
  /// Keyed on the `...ForSequenceClassification` suffix, which is how
  /// transformers names every classifier head — measured across the four repos
  /// that matter here: `gte-reranker-modernbert-base` declares
  /// `ModernBertForSequenceClassification` and does work; `bge-small-en-v1.5`
  /// declares `BertModel` and embeds; `jina-reranker-v1-tiny-en` declares
  /// `JinaBertModel` and is the headless case. Note the caveat that has to
  /// travel with this: `bge-small` carries `id2label: {"0": "LABEL_0"}` and is
  /// emphatically not a classifier, so a label set alone decides nothing — which
  /// is the same trap `EncoderInfo.isClassifier` has to avoid in Dart.
  bool get declaresClassificationHead => architectures.any(
      (a) => a.endsWith('ForSequenceClassification') || a.endsWith('ForTokenClassification'));

  /// Whether the checkpoint declares a language-modelling head.
  bool get declaresLmHead => architectures.any((a) =>
      a.endsWith('ForCausalLM') ||
      a.endsWith('ForConditionalGeneration') ||
      a.endsWith('ForMaskedLM') ||
      a.endsWith('ForSeq2SeqLM'));

  /// Pooling as a llama.cpp value, or null when the file says nothing usable.
  ///
  /// `mean` is the one the jina and its base both declare, and it is trained
  /// metadata rather than a guess. Null when absent, because a BERT's default is
  /// CLS and inferring `mean` from a missing key would be exactly the kind of
  /// confident wrong answer this whole path is trying to avoid.
  int? get poolingType {
    switch (embPooler) {
      case 'mean':
        return 1; // LLAMA_POOLING_TYPE_MEAN
      case 'cls':
        return 2; // LLAMA_POOLING_TYPE_CLS
      case 'last':
        return 3; // LLAMA_POOLING_TYPE_LAST
      default:
        return null;
    }
  }

  /// The caveat that has to travel with [poolingType].
  ///
  /// `emb_pooler` describes pooling a *sequence* into a vector, which is what an
  /// embedding model does. A cross-encoder does not pool — it scores a pair —
  /// and the field is inherited from the base checkpoint, so on a reranker it
  /// describes the model it was built from and not the scoring. Read alone it
  /// would turn the headless jina into an embedder. Gated on the head for that
  /// reason, and the GTE gets the benefit: its own GGUF declares no
  /// `<arch>.pooling_type` at all, so trained metadata from the checkpoint is
  /// the only pooling that file ever states.
  String get ggufPoolingNote =>
      declaresClassificationHead
          ? 'A GGUF that kept the head can use it.'
          : 'Not usable for this checkpoint: a cross-encoder does not pool, and '
              'without a head there is no score either, so this file would '
              'produce nothing.';

  /// One sentence for a person deciding whether to spend the download.
  String get verdict {
    if (architectures.isEmpty) {
      return 'The checkpoint does not declare an architecture, so this file '
          'cannot be judged before it is downloaded.';
    }
    if (declaresClassificationHead) {
      return 'The checkpoint declares a classification head '
          '(${architectures.join(', ')}), so a conversion of it can score a '
          'query against a document. Whether this particular GGUF kept the head '
          'is only knowable from the file itself.';
    }
    if (declaresLmHead) {
      return 'The checkpoint declares a language-modelling head '
          '(${architectures.join(', ')}). It can chat; it has no reranker head, '
          'so a conversion of it will only embed.';
    }
    return 'The checkpoint is a base model '
        '(${architectures.join(', ')}) — no classification head and no LM '
        'head. A GGUF converted from it will load and produce nothing, which is '
        'exactly what jina-reranker-v1-tiny-en does.';
  }
}

/// The Hugging Face facets this app can act on, as one value.
///
/// Only facets the hub's public model API honours are here — the web UI offers
/// more, but a control that quietly does nothing is worse than no control.
class HfFilters {
  const HfFilters({
    this.format = HfFormat.any,
    this.author = '',
    this.minParamsB,
    this.maxParamsB,
    this.tags = const {},
    this.pipelineTag = '',
    this.fitsDevice = true,
    this.nameQuery = '',
    this.quantAware = false,
  });

  /// Keep only quantisation-aware builds. Applied client-side over the repo id
  /// and its file list: the hub has no facet for it, and the marker often
  /// appears only on the file — LiquidAI's repos are named `…-GGUF` and carry
  /// `…-QAD-Q4_0.gguf` inside.
  final bool quantAware;

  /// Substring the repo name/owner must contain (case-insensitive). Applied
  /// client-side: the hub API has no "name contains" facet.
  final String nameQuery;

  /// Which runtime's weights to list.
  final HfFormat format;

  /// Repo owner, e.g. `bartowski`. Empty means any.
  final String author;

  /// Parameter count in billions. Null means unbounded on that end.
  final double? minParamsB;
  final double? maxParamsB;

  /// Hub tags ANDed onto the query: `moe`, `4-bit`, `imatrix`, ...
  final Set<String> tags;

  /// A single `pipeline_tag`. Empty means "anything this app can run".
  final String pipelineTag;

  /// Hide GGUFs that cannot fit this phone's memory. Applies to the file list,
  /// where sizes are known — the repo index carries none.
  final bool fitsDevice;

  /// `num_parameters` as the hub wants it, or null when unbounded both ways.
  String? get paramRangeQuery {
    if (minParamsB == null && maxParamsB == null) return null;
    return 'min:${_b(minParamsB ?? 0)},max:${_b(maxParamsB ?? 2000)}';
  }

  static String _b(double v) =>
      '${v == v.roundToDouble() ? v.round() : v}B';

  /// How many facets are set, for the badge on the Filters button.
  /// `fitsDevice` is excluded: it is on by default, so counting it would show
  /// "1 filter" on an untouched sheet.
  int get activeCount =>
      (format == HfFormat.any ? 0 : 1) +
      (nameQuery.isEmpty ? 0 : 1) +
      (author.isEmpty ? 0 : 1) +
      (minParamsB == null ? 0 : 1) +
      (maxParamsB == null ? 0 : 1) +
      (pipelineTag.isEmpty ? 0 : 1) +
      (quantAware ? 1 : 0) +
      tags.length;

  HfFilters copyWith({
    HfFormat? format,
    String? author,
    double? minParamsB,
    double? maxParamsB,
    Set<String>? tags,
    String? pipelineTag,
    bool? fitsDevice,
    bool clearMin = false,
    bool clearMax = false,
    String? nameQuery,
    bool? quantAware,
  }) {
    return HfFilters(
      format: format ?? this.format,
      nameQuery: nameQuery ?? this.nameQuery,
      quantAware: quantAware ?? this.quantAware,
      author: author ?? this.author,
      minParamsB: clearMin ? null : (minParamsB ?? this.minParamsB),
      maxParamsB: clearMax ? null : (maxParamsB ?? this.maxParamsB),
      tags: tags ?? this.tags,
      pipelineTag: pipelineTag ?? this.pipelineTag,
      fitsDevice: fitsDevice ?? this.fitsDevice,
    );
  }
}

/// Search Hugging Face for GGUF models and list what a repo actually holds.
///
/// Anonymous access only: the public model API needs no token, and asking the
/// user for one to browse a public index would be a worse trade than the lower
/// rate limit it buys.
class HfSearchService {
  HfSearchService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const _base = 'https://huggingface.co/api';
  static const _timeout = Duration(seconds: 20);

  /// One page of the index, most downloaded first.
  ///
  /// An empty [query] browses instead of searching: the hub is the catalogue
  /// here, and a search box alone made the user guess a name before seeing
  /// anything. [skip] pages through it — the hub's cursor is stateful and an
  /// offset is not, which matters when a filter changes mid-scroll.
  Future<List<HfRepo>> browseRepos({
    String query = '',
    HfFilters filters = const HfFilters(),
    int skip = 0,
    int limit = 30,
  }) async {
    if (filters.format != HfFormat.any) {
      return _page(filters.format.tag, query, filters, skip, limit);
    }

    // The hub ANDs repeated `filter` params, so "GGUF or LiteRT" cannot be one
    // request. Two, merged by downloads. Each page is ordered; the sequence
    // across pages is not perfectly interleaved, which is invisible at a
    // glance and cheaper than paging a union client-side.
    final pages = await Future.wait([
      _page(HfFormat.gguf.tag, query, filters, skip, limit),
      _page(HfFormat.liteRtLm.tag, query, filters, skip, limit),
    ]);
    final seen = <String>{};
    final merged = [
      for (final page in pages)
        for (final repo in page)
          if (seen.add(repo.id)) repo,
    ]..sort((a, b) => b.downloads.compareTo(a.downloads));
    return merged;
  }

  Future<List<HfRepo>> _page(
    String formatTag,
    String query,
    HfFilters filters,
    int skip,
    int limit,
  ) async {
    final q = query.trim();
    final range = filters.paramRangeQuery;

    final response = await _dio.get<List<dynamic>>(
      '$_base/models',
      queryParameters: {
        // Repeated `filter` params are ANDed by the hub, so the format tag
        // always survives whatever the user picked in Misc.
        'filter': [formatTag, ...filters.tags],
        'sort': 'downloads',
        'direction': -1,
        'limit': limit,
        if (skip > 0) 'skip': skip,
        if (q.isNotEmpty) 'search': q,
        if (filters.author.isNotEmpty) 'author': filters.author,
        if (filters.pipelineTag.isNotEmpty) 'pipeline_tag': filters.pipelineTag,
        if (range != null) 'num_parameters': range,
        // Only when the filter is on: `full` triples the payload, and it is
        // the only way to see file names without a request per repo.
        if (filters.quantAware) 'full': true,
      },
      options: Options(
        receiveTimeout: _timeout,
        sendTimeout: _timeout,
        responseType: ResponseType.json,
      ),
    );

    return (response.data ?? [])
        .whereType<Map>()
        .where((raw) => !filters.quantAware || _repoIsQuantAware(raw))
        .map((raw) => HfRepo(
              id: (raw['id'] ?? raw['modelId'] ?? '').toString(),
              downloads: (raw['downloads'] as num?)?.toInt() ?? 0,
              likes: (raw['likes'] as num?)?.toInt() ?? 0,
              pipelineTag: (raw['pipeline_tag'] ?? '').toString(),
            ))
        .where((repo) => repo.id.isNotEmpty)
        .toList();
  }

  /// Pipelines this app can actually load. The GGUF index also carries
  /// embedders, ASR and TTS weights there is no runtime for here.
  ///
  /// Applied by the caller rather than inside [browseRepos], so that a page
  /// which filters down to nothing is still distinguishable from the end of
  /// the index — otherwise paging stops on the first all-embeddings page.
  ///
  /// An empty tag passes: most GGUF repos set none, and excluding them would
  /// empty the list.
  static bool isRunnable(String pipelineTag) =>
      pipelineTag.isEmpty || runnablePipelines.contains(pipelineTag);

  static const runnablePipelines = {
    'text-generation',
    'text2text-generation',
    'image-text-to-text',
    'audio-text-to-text',
    'any-to-any',
  };

  /// Every loadable weight file in [repoId], with its size, smallest first.
  ///
  /// Split archives (`-00001-of-00003.gguf`) are dropped: this app downloads
  /// one file per model and cannot reassemble a set. So are LiteRT builds
  /// compiled for another vendor's accelerator, which would download fine and
  /// then fail to load.
  /// The upstream checkpoint's `config.json`, as far as this app can use it.
  ///
  /// Fetches the checkpoint's own description so a GGUF can be judged *before*
  /// it is downloaded. The measured case is `jina-reranker-v1-tiny-en`: its GGUF
  /// is 36 MB, loads in half a second, and cannot do anything — the conversion
  /// put the head at `cls.weight` where llama.cpp looks for `cls.output` and
  /// dropped the `pooler.dense` it was trained against. Its `config.json` says
  /// `architectures: ["JinaBertModel"]`, which is the same fact in one field:
  /// a base model, not a `...ForSequenceClassification`. Reading that costs
  /// 1 kB instead of 36 MB and a download.
  ///
  /// What it cannot do is add a tensor. `config.json` carries shapes and intent,
  /// never weights: it says one logit should exist, which says what to *allocate*
  /// and not what to *put in it*. The `tool/gguf-inject-head.py` experiment is
  /// the proof — it allocated `[768]` from the shape and produced 40+ measurements
  /// stuck in (-1, 1). This is a pre-flight, not a repair.
  Future<HfConfig?> fetchConfig(String repoId) async {
    try {
      final response = await _dio.get<String>(
        '$_base/models/$repoId/resolve/main/config.json',
        options: Options(
          receiveTimeout: _timeout,
          sendTimeout: _timeout,
          responseType: ResponseType.plain,
        ),
      );
      final raw = response.data;
      if (raw == null || raw.isEmpty) return null;
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      return HfConfig(
        repoId: repoId,
        architectures: (json['architectures'] as List?)
                ?.map((e) => '$e')
                .toList(growable: false) ??
            const <String>[],
        modelType: (json['model_type'] as String?) ?? '',
        embPooler: (json['emb_pooler'] as String?) ?? '',
        labels: ((json['id2label'] as Map?) ?? const {})
            .entries
            .map((e) => '${e.key}: ${e.value}')
            .toList(growable: false),
      );
    } on Object {
      // A missing or unreadable config is normal — plenty of repos are GGUFs
      // only. The caller treats null as "no opinion", never as "no head".
      return null;
    }
  }

  Future<List<HfFile>> listModelFiles(String repoId) async {
    final response = await _dio.get<List<dynamic>>(
      '$_base/models/$repoId/tree/main',
      queryParameters: {'recursive': true},
      options: Options(
        receiveTimeout: _timeout,
        sendTimeout: _timeout,
        responseType: ResponseType.json,
      ),
    );

    final entries = (response.data ?? [])
        .whereType<Map>()
        .where((raw) => raw['type'] == 'file')
        .map((raw) => MapEntry(
              (raw['path'] ?? '').toString(),
              (raw['size'] as num?)?.toInt() ?? 0,
            ))
        .where((entry) {
          final lower = entry.key.toLowerCase();
          return lower.endsWith('.gguf') || lower.endsWith('.litertlm');
        })
        .where((entry) => !_isForeignBuild(entry.key))
        .toList();

    bool isProjector(String path) =>
        path.split('/').last.toLowerCase().startsWith('mmproj');

    final projectors = entries.where((e) => isProjector(e.key)).map((e) =>
        HfProjector(repoId: repoId, path: e.key, sizeBytes: e.value)).toList()
      ..sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));

    final files = entries
        .where((e) =>
            !isProjector(e.key) &&
            !RegExp(r'-\d{5}-of-\d{5}\.gguf$', caseSensitive: false)
                .hasMatch(e.key))
        .map((e) => HfFile(
              repoId: repoId,
              path: e.key,
              sizeBytes: e.value,
              // A .litertlm carries its encoders inside, so pairing one with a
              // repo's mmproj would offer a download that does nothing.
              projectors: e.key.toLowerCase().endsWith('.litertlm')
                  ? const []
                  : projectors,
            ))
        .toList();

    files.sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
    return files;
  }

  /// A LiteRT build for hardware this app will not be running on.
  ///
  /// litert-community ships one `.litertlm` per accelerator alongside the
  /// portable one — `_Google_Tensor_G5`, `_qualcomm_sm8750`, `-web`. They are
  /// several gigabytes each and load nowhere else.
  ///
  /// ponytail: a denylist of the vendors seen in the wild, not a positive match
  /// against this phone's SoC. If a MediaTek-specific build ever ships, widen
  /// this into a real check against DeviceInfoService.socHardware.
  static bool _isForeignBuild(String path) => RegExp(
        r'_(google_tensor|qualcomm|intel|amd|nvidia)[_.a-z0-9]*\.litertlm$|'
        r'-web\.litertlm$',
        caseSensitive: false,
      ).hasMatch(path);

}
