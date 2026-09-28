import 'package:get/get.dart';

import '../core/constants.dart';
import 'app_log_service.dart';
import 'hive_service.dart';

/// Per-role encoder parameters, each either auto-detected or overridden.
///
/// The pattern throughout is `null` meaning *ask the model*, and a value meaning
/// *use this instead*. It is not a "default" field, and the difference is the
/// whole point: a default bakes one model's number in and applies it to another,
/// which is how a 2048-token ceiling measured on one cross-encoder ends up
/// truncating a model that could have taken 8192.
///
/// What is auto-detectable and what is not, measured on the Edge 60:
///
/// - **Token ceiling — auto.** The native side publishes `max_input_tokens`,
///   clamped to 2048. It is a real ceiling and not a hint: an encoder pools the
///   whole sequence in one pass and cannot split it, so
///   `llama-context.cpp:1495` states the requirement as a `GGML_ASSERT`, which on
///   a phone is a `SIGABRT` with no HTTP response. Overriding it upward does not
///   raise the assert, it moves the crash.
/// - **Input prefix — manual, always.** E5 wants `query: ` and `passage: `, BGE
///   wants `query: ` on one side only, Nomic wants `search_document: `. No
///   amount of reading the file says which, and getting it wrong does not error —
///   it returns vectors that retrieve worse, silently. This is the parameter
///   that matters most and the one least likely to be guessed.
/// - **Normalisation — auto, overridable.** llama.cpp L2-normalises for some
///   pooling types and not others; the console prints the norm so the answer is
///   visible rather than assumed.
/// - **Top N / document separator / return documents — manual.** These are
///   request-shaping choices about the *response*, not about the model, and
///   nothing in a file can say what the caller wants back.
///
/// Per role, because the answers are genuinely different. A reranker has no
/// document separator question because it takes a list; an embedder has no top-N
/// because it returns one vector. Splitting them is not tidiness, it is the
/// absence of dead controls.
class EncoderSettingsService extends GetxService {
  final _hive = Get.find<HiveService>();
  final _log = Get.find<AppLogService>();

  // ── embeddings ────────────────────────────────────────────────────────────
  /// Prepended to the query side. The single most consequential setting here.
  final embedQueryPrefix = RxnString();
  final embedPassagePrefix = RxnString();

  /// L2-normalise the returned vector. Null asks the model.
  final embedNormalize = RxnBool();

  // ── rerank ────────────────────────────────────────────────────────────────
  /// How many documents come back. Null means all of them, which is the
  /// Cohere-compatible default and also the answer nobody wants past ~20.
  final rerankTopN = RxnInt();
  final rerankReturnDocuments = true.obs;
  final rerankSigmoid = true.obs;

  /// Splits a newline-delimited `documents` string into individual documents.
  ///
  /// Newline is what the console writes and what most clients send, but a
  /// document can contain a newline and there is no way to tell a separator from
  /// a paragraph break. JSON is unambiguous, which is why the value is
  /// configurable rather than fixed: a caller passing a JSON array already has
  /// the boundaries and should not be re-split.
  final rerankDocumentSeparator = '\n'.obs;

  // ── shared ceiling ────────────────────────────────────────────────────────
  /// Overrides the native's `max_input_tokens`. Null asks the model.
  ///
  /// Rejected above the native ceiling on purpose. Raising it cannot raise the
  /// `GGML_ASSERT`; it relocates a refused request with a token count into a
  /// process kill with no response, and the difference between those two is the
  /// difference between a bug report and a crash report.
  final encoderMaxInputTokens = RxnInt();

  static const int nativeMaxInputTokens = 2048;

  @override
  void onInit() {
    super.onInit();
    _load();
  }

  void _load() {
    embedQueryPrefix.value = _hive.getSetting<String>(AppConstants.keyEmbedQueryPrefix);
    embedPassagePrefix.value = _hive.getSetting<String>(AppConstants.keyEmbedPassagePrefix);
    embedNormalize.value = _hive.getSetting<bool>(AppConstants.keyEmbedNormalize);
    rerankTopN.value = _hive.getSetting<int>(AppConstants.keyRerankTopN);
    rerankReturnDocuments.value =
        _hive.getSetting<bool>(AppConstants.keyRerankReturnDocuments) ?? true;
    rerankSigmoid.value = _hive.getSetting<bool>(AppConstants.keyRerankSigmoid) ?? true;
    rerankDocumentSeparator.value =
        _hive.getSetting<String>(AppConstants.keyRerankDocumentSeparator) ?? '\n';
    encoderMaxInputTokens.value =
        _hive.getSetting<int>(AppConstants.keyEncoderMaxInputTokens);
  }

  Future<void> setEmbedQueryPrefix(String? v) async {
    embedQueryPrefix.value = _emptyToNull(v);
    await _hive.setSetting(AppConstants.keyEmbedQueryPrefix, embedQueryPrefix.value);
  }

  Future<void> setEmbedPassagePrefix(String? v) async {
    embedPassagePrefix.value = _emptyToNull(v);
    await _hive.setSetting(AppConstants.keyEmbedPassagePrefix, embedPassagePrefix.value);
  }

  Future<void> setEmbedNormalize(bool? v) async {
    embedNormalize.value = v;
    await _hive.setSetting(AppConstants.keyEmbedNormalize, v);
  }

  Future<void> setRerankTopN(int? v) async {
    rerankTopN.value = (v == null || v <= 0) ? null : v;
    await _hive.setSetting(AppConstants.keyRerankTopN, rerankTopN.value);
  }

  Future<void> setRerankReturnDocuments(bool v) async {
    rerankReturnDocuments.value = v;
    await _hive.setSetting(AppConstants.keyRerankReturnDocuments, v);
  }

  Future<void> setRerankSigmoid(bool v) async {
    rerankSigmoid.value = v;
    await _hive.setSetting(AppConstants.keyRerankSigmoid, v);
  }

  Future<void> setRerankDocumentSeparator(String? v) async {
    // A separator of only whitespace would split every document into its
    // characters, and the request would still return 200 with 400 results.
    // Anything that is not whitespace is acceptable; nothing is not.
    if (v == null || v.trim().isEmpty) {
      _log.error('encoder: refused an empty document separator',
          details: 'a whitespace-only separator splits every document into characters');
      return;
    }
    rerankDocumentSeparator.value = v;
    await _hive.setSetting(AppConstants.keyRerankDocumentSeparator, v);
  }

  Future<void> setEncoderMaxInputTokens(int? v) async {
    if (v != null && v > nativeMaxInputTokens) {
      _log.error('encoder: refused a token ceiling above the native limit',
          details: 'asked for $v, the ceiling is $nativeMaxInputTokens. '
              'Raising it cannot raise the GGML_ASSERT — it moves a refused '
              'request into a process kill.');
      return;
    }
    encoderMaxInputTokens.value = (v == null || v <= 0) ? null : v;
    await _hive.setSetting(
        AppConstants.keyEncoderMaxInputTokens, encoderMaxInputTokens.value);
  }

  /// The ceiling to enforce, given what the loaded model reported.
  ///
  /// The override can only ever *lower* the detected value, even though the
  /// setter allows any value up to the native cap. A model that reports 512 does
  /// not become able to take 2048 because someone typed a bigger number, and the
  /// assert does not read this setting either — it reads the context the context
  /// was created with. So the number is clamped rather than trusted, and the
  /// reason is logged when the two disagree.
  int effectiveMaxInputTokens(int detected) {
    final o = encoderMaxInputTokens.value;
    if (o == null || o <= 0) return detected > 0 ? detected : nativeMaxInputTokens;
    if (detected > 0 && o > detected) {
      _log.info('encoder: token ceiling override of $o is above the '
          'detected $detected; using the detected value');
      return detected;
    }
    return o;
  }

  /// Everything cleared, back to asking the model for everything.
  ///
  /// One control because the individual resets are never what anyone wants: a
  /// stale prefix left behind after switching from E5 to BGE is exactly the kind
  /// of thing that makes vectors quietly worse with no symptom, and hunting four
  /// separate reset buttons for it is how it survives.
  Future<void> resetAll() async {
    await setEmbedQueryPrefix(null);
    await setEmbedPassagePrefix(null);
    await setEmbedNormalize(null);
    await setRerankTopN(null);
    await setRerankReturnDocuments(true);
    await setRerankSigmoid(true);
    await setRerankDocumentSeparator('\n');
    await setEncoderMaxInputTokens(null);
  }

  /// How many parameters are currently overriding the model's own values.
  int get overrideCount =>
      (embedQueryPrefix.value != null ? 1 : 0) +
      (embedPassagePrefix.value != null ? 1 : 0) +
      (embedNormalize.value != null ? 1 : 0) +
      (rerankTopN.value != null ? 1 : 0) +
      (rerankDocumentSeparator.value != '\n' ? 1 : 0) +
      (encoderMaxInputTokens.value != null ? 1 : 0);

  static String? _emptyToNull(String? v) {
    if (v == null) return null;
    // Trimmed, because a prefix of one space is indistinguishable from a typo and
    // it changes every vector it is applied to.
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
}
