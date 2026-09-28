import 'dart:convert';
import 'dart:math' show sqrt;

import 'package:flutter/services.dart';

/// What a loaded GGUF can do as an encoder, and the ability to do it.
///
/// ## What this is for
///
/// Most GGUFs in this app are generation models: they take a prompt and emit
/// tokens. A second family does not generate at all — BERT, ModernBERT,
/// JinaBERT, NomicBERT, NeoBERT, EuroBERT and the embedding families. They run
/// the sequence through and **pool** the result into one vector, which is an
/// embedding (MEAN / CLS / LAST), a relevance score (RANK with one class) or a
/// set of class scores (RANK with several, e.g. a sentiment or intent head).
///
/// A classifier like Laya is `text-classification` and will never be a chat
/// model. This is the surface that can run it.
///
/// ## Why the model declares what it is
///
/// The pooling type is read from `<arch>.pooling_type` in the GGUF metadata,
/// so [info] answers from the file rather than from a guess at the filename. It
/// also means a *generation* model is not silently misdetected: it carries no
/// pooling type, [info] reports `is_encoder: false`, and [encode] refuses with
/// an explanation instead of returning a vector of zeros.
///
/// The format for a pair is the model's own `rerank` chat template with
/// `{query}` and `{document}` substituted when it has one, and the vocab's SEP
/// token as the boundary when it does not. Joining with a space would tokenize
/// into one undifferentiated run and return a confident number about nothing.
///
/// This is `llama_decode` under the hood, not `llama_encode` — the latter feeds
/// the encoder half of an encode-**decoder** into cross-attention, which an
/// encoder-only model has no use for.
class LlamaEncoder {
  static const _channel = MethodChannel('llama_flutter_android/model_meta');

  /// What the loaded model is capable of. Defaults to "not an encoder" when no
  /// model is loaded, which is the honest answer rather than an error: asking
  /// is how you find out whether one is.
  static Future<EncoderInfo> info() async {
    try {
      final raw = await _channel.invokeMethod<String>('encoderInfo');
      if (raw == null || raw.isEmpty) return const EncoderInfo();
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return const EncoderInfo();
      return EncoderInfo(
        isEncoder: json['is_encoder'] == true,
        pooling: (json['pooling'] as String?) ?? 'unspecified',
        nClsOut: (json['n_cls_out'] as num?)?.toInt() ?? 0,
        nEmbdOut: (json['n_embd_out'] as num?)?.toInt() ?? 0,
        outputLength: (json['output_len'] as num?)?.toInt() ?? 0,
        inferredPooling: json['inferred_pooling'] == true,
        archIsEncoder: json['arch_is_encoder'] == true,
        ggufName: (json['gguf_name'] as String?) ?? '',
        ggufTags: _splitCsv(json['gguf_tags'] as String?),
        ggufLabels: _splitCsv(json['gguf_labels'] as String?),
        ggufPooling: (json['gguf_pooling'] as String?) ?? '',
        hasClassificationHead:
            json['has_classification_head'] == true,
        maxInputTokens: (json['max_input_tokens'] as num?)?.toInt() ?? 0,
        labels:
            (json['labels'] as List?)?.map((e) => '$e').toList() ??
                const <String>[],
      );
    } on PlatformException {
      return const EncoderInfo();
    } on MissingPluginException {
      return const EncoderInfo();
    } on FormatException {
      // The native side builds this JSON with `snprintf` into a fixed buffer, and
      // four of its fields are strings read out of a file: `general.name`,
      // `general.tags`, the arch-scoped `classifier.output_labels`. A long enough
      // name truncates the buffer, a truncated string makes the whole payload
      // invalid JSON, and `jsonDecode` throws `FormatException` — which nothing
      // above catches. The symptom without this line is a crash in the console
      // rather than a model that reports less than it could.
      //
      // 'not an encoder' is the safe direction: it hides the console, which is
      // the same answer a missing channel gives, and it does not claim a
      // capability that could not be read.
      return EncoderInfo();
    }
  }

  /// Pool [text] into a vector.
  ///
  /// Pass [query] only for a cross-encoder, and pass it as the *query* side:
  /// the native side puts it first and the document after the SEP boundary,
  /// which is the order a reranker was trained on. A classifier such as Laya
  /// takes [query] null and scores the text on its own.
  ///
  /// Throws [EncoderUnavailable] when the loaded model is a generation model.
  static Future<EncoderOutput> encode(String text, {String? query}) async {
    final resolved = (query == null || query.isEmpty) ? null : query;
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('encode', {
        'text': text,
        'query': resolved ?? '',
      });
      if (res == null) {
        throw const EncoderUnavailable('The encoder returned nothing.');
      }
      final values = (res['values'] as List?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const <double>[];
      return EncoderOutput(
        values: values,
        elapsedMs: (res['elapsedMs'] as num?)?.toInt() ?? 0,
      );
    } on PlatformException catch (e) {
      throw EncoderUnavailable(e.message ?? e.toString());
    } on MissingPluginException {
      throw const EncoderUnavailable(
          'The native library is not available on this platform.');
    }
  }
}

/// What a loaded model can do as an encoder.
class EncoderInfo {
  const EncoderInfo({
    this.isEncoder = false,
    this.pooling = 'unspecified',
    this.nClsOut = 0,
    this.nEmbdOut = 0,
    this.outputLength = 0,
    this.inferredPooling = false,
    this.archIsEncoder = false,
    this.ggufName = '',
    this.ggufTags = const <String>[],
    this.ggufLabels = const <String>[],
    this.ggufPooling = '',
    this.hasClassificationHead = false,
    this.maxInputTokens = 0,
    this.labels = const <String>[],
  });

  /// True when the GGUF declares a pooling type. False for a generation model.
  final bool isEncoder;

  /// `mean`, `cls`, `last` (embeddings) or `rank` (rerank / classify).
  final String pooling;

  /// Number of classifier outputs. 0 for an embedding model, 1 for a reranker.
  final int nClsOut;

  /// Width of the model's output embedding.
  final int nEmbdOut;

  /// How many floats [LlamaEncoder.encode] returns: `nClsOut` for a RANK
  /// model, `nEmbdOut` otherwise.
  final int outputLength;

  /// Class labels, when the GGUF carries them. Empty for a reranker.
  final List<String> labels;

  /// True when [pooling] was concluded rather than read.
  ///
  /// A `jina-reranker-v1-tiny-en` declares no `<arch>.pooling_type` at all, and
  /// llama.cpp then falls back to `NONE` — the model loads, answers `/v1/chat`,
  /// and never pools anything. The native side infers `RANK` for encoder
  /// architectures with a usable document/query boundary, which is what
  /// llama.cpp's own `--rerank` does. This flag is how a caller learns that
  /// happened, so `pooling: rank` is not read as the file having said so.
  final bool inferredPooling;

  /// True when the architecture is encoder-only, whatever [pooling] ended up as.
  ///
  /// The case this exists for is `jina-reranker-v1-tiny-en`: a real
  /// cross-encoder whose GGUF has no `cls.output.*`, so there is no logit for
  /// llama.cpp to return and the pooling stays `NONE`. Without this flag that
  /// model is indistinguishable from a chat model, and the honest refusal —
  /// "this conversion has no classification head" — is impossible to give,
  /// because the only thing the native side can say is that it is not an
  /// encoder. It is.
  final bool archIsEncoder;

  /// An encoder architecture that can produce no output at all.
  ///
  /// [archIsEncoder] and not [isEncoder] together: the architecture says encoder
  /// and the pooling stayed `NONE`, which means llama.cpp has neither a logit to
  /// return nor a vector to pool. The file is a body with the ends cut off.
  ///
  /// This exists to be *said*. The alternative — reporting `is_encoder: false`
  /// and letting the chat fall back to the conversation — is what the device did
  /// with `jina-reranker-v1-tiny-en`, and it produced no symptom at all: a model
  /// that loads, occupies the screen, and silently is not a chat model either.
  /// A caller that knows the model is a shell can say so; it cannot invent the
  /// reason from `is_encoder: false`.
  bool get isHeadless => archIsEncoder && !isEncoder;

  /// What the file's own metadata claims it is, from `general.tags`.
  ///
  /// Measured across the five files tested on the Edge 60, this key is present on
  /// one of four — `jina-reranker-v1-tiny-en` carries
  /// `[reranker, cross-encoder, transformers.js, text-classification]`, the GTE
  /// and `bge-small` carry none — so it can never decide a role. It is reported
  /// because it is the only place a conversion states its *intent*, and the gap
  /// between intent and delivery is exactly what a person needs spelled out:
  /// that file says it is a reranker, and it is not one.
  final List<String> ggufTags;

  /// `general.name` as the file wrote it. Often useless and occasionally
  /// misleading: the GTE's is `Gte Reranker Modernbert Base` and the jina's is
  /// `Jina Bert Implementation`, which is the *base* model the reranker was
  /// built from rather than the reranker.
  final String ggufName;

  /// `<arch>.classifier.output_labels`, straight from the file.
  ///
  /// Separate from [labels] — the same values, in principle, read two ways.
  /// `bge-small-en-v1.5` carries `[LABEL_0]` and is not a classifier: it is the
  /// residue of a size-1 head on a model that embeds, which is why [isClassifier]
  /// requires `pooling == 'rank'` and not just a label being present.
  final List<String> ggufLabels;

  /// `<arch>.pooling_type` exactly as the file wrote it, or '' when undeclared.
  ///
  /// Absent on both the GTE and the jina and present on `bge-small`
  /// (`2`, CLS), so the converters disagree about whether to write it. That
  /// inconsistency is why the native side infers pooling for a reranker rather
  /// than trusting this, and why it must never be read as the answer.
  final String ggufPooling;

  /// Whether the file carries `cls.output.weight`.
  ///
  /// The one hard requirement for a score. A file without it can still be an
  /// embedding model, but there is no logit in it — llama.cpp would hand back a
  /// single float of a pooled hidden state, a number that ranks plausibly and
  /// means nothing.
  final bool hasClassificationHead;

  /// Most tokens one `(query, document)` pair may carry, 0 when unknown.
  ///
  /// An encoder pools the whole sequence in one pass and cannot be split into
  /// microbatches, so this is a hard ceiling rather than a chunking hint.
  /// `llama-context.cpp:1495` states the requirement as a `GGML_ASSERT`, which
  /// on a phone means a `SIGABRT` with no HTTP response — measured on the Edge
  /// 60: 606 tokens pass, ~2400 do not. Exceeding it now returns a message with
  /// the count instead.
  final int maxInputTokens;

  /// A model that emits one score per class.
  ///
  /// `pooling == 'rank'` is required, not just `nClsOut > 1`, and the device is
  /// why. A real `bge-small-en-v1.5` reports **both** `pooling: cls` and
  /// `nClsOut: 1` with a label `LABEL_0` — the residue of a size-1 classification
  /// head on a model that embeds. It returns 384 values. So `nClsOut` alone
  /// cannot answer "is this a classifier", and a check built on it tells a caller
  /// that an embedding model is a one-class classifier. Only a RANK pooling type
  /// means the classification head is attached to the graph.
  bool get isClassifier => isEncoder && pooling == 'rank' && nClsOut > 1;

  /// A model that scores a query/document pair.
  ///
  /// `nClsOut <= 1`, not `== 1`, for the same reason `isClassifier` requires
  /// `pooling == 'rank'`: the device reports
  /// **jina-reranker-v1-tiny-en as `pooling: rank` with `n_cls_out: 0`**, and it
  /// is a reranker. It has exactly one output by definition, and the count is
  /// simply absent from the file. Testing `== 1` refuses the one model this
  /// classification exists to serve, with a message that reads as though the
  /// model were something else.
  bool get isReranker => isEncoder && pooling == 'rank' && nClsOut <= 1;

  /// A model that produces a vector, for semantic search.
  bool get isEmbedding => isEncoder && pooling != 'rank';

  @override
  String toString() =>
      'EncoderInfo(isEncoder: $isEncoder, pooling: $pooling, '
      'nClsOut: $nClsOut, nEmbdOut: $nEmbdOut, outputLength: $outputLength, '
      'labels: ${labels.length})';
}

/// One pooled sequence.
class EncoderOutput {
  const EncoderOutput({required this.values, this.elapsedMs = 0});

  final List<double> values;

  /// Wall-clock time the native call spent, measured around the blocking decode.
  final int elapsedMs;

  /// Euclidean norm, for the "is this vector actually empty?" check.
  double get norm => sqrt(values.fold<double>(0, (sum, v) => sum + v * v));
}

/// The loaded model cannot serve this call, and the native side said why.
class EncoderUnavailable implements Exception {
  const EncoderUnavailable(this.message);
  final String message;

  @override
  String toString() => 'EncoderUnavailable: $message';
}

/// Splits a comma-joined list the native side flattened, dropping empty entries.
///
/// The native reader hands arrays back as one string because it is a `jstring`
/// across JNI and a `jobjectArray` would be a second thing to build for a value
/// read once per console query. An absent key arrives as `''`, which must come
/// back as an empty list and not as `['']` — a one-element list of nothing is
/// the kind of thing that then reads as "the file declared one thing".
List<String> _splitCsv(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const <String>[];
  return raw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
}
