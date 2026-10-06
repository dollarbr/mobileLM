import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart'
    show LlamaEncoder, EncoderInfo;

import '../controllers/server_controller.dart';
import '../core/colors.dart';
import '../services/inference_service.dart';
import '../services/text_interpolation.dart';
import '../utils/server_auth.dart';
import 'system_one_console.dart';

/// A console for a loaded encoder, shown above the chat.
///
/// It talks to the local HTTP server, not to the JNI. That is deliberate: the
/// thing worth testing on a phone is the API surface, since that is what
/// anything else on the network will use, and a console that went straight to
/// the native layer would pass while the endpoint was broken. It also means the
/// server has to be running, which is stated rather than assumed — a console
/// that silently did nothing when the server was off would be worse than no
/// console.
class EncoderConsole extends StatefulWidget {
  const EncoderConsole({super.key, required this.inference, this.onClose});

  final InferenceService inference;
  final VoidCallback? onClose;

  @override
  State<EncoderConsole> createState() => _EncoderConsoleState();
}

class _EncoderConsoleState extends State<EncoderConsole> {
  final _query = TextEditingController();
  final _documents = TextEditingController();
  final _labels = TextEditingController();
  final _info = Rxn<EncoderInfo>();

  bool _busy = false;
  String? _error;
  String? _raw;
  List<Map<String, dynamic>>? _ranked;
  List<double>? _vector;
  int _ms = 0;
  bool _serverUp = false;
  String _base = '';

  /// Watching the server's own state, so the button tracks it instead of
  /// freezing whatever the answer was when this widget was built.
  List<Worker> _serverWorkers = [];

  String get _role {
    final i = _info.value;
    if (i == null) return '';
    if (i.isHeadless) return 'headless';
    if (!i.isEncoder) return '';
    if (i.isClassifier) return 'classifier';
    if (i.isReranker) return 'reranker';
    if (i.isEmbedding) return 'embedding';
    return 'encoder';
  }

  @override
  void initState() {
    super.initState();
    _load();
    // The console is mounted when the model loads, which is normally *before*
    // the API server is started — so probing once in `initState` reads "not
    // running" and the run button stays disabled for the rest of the session,
    // with nothing on screen to explain it beyond a line of grey text. Measured
    // the hard way: the button looked dead with a server running and reachable.
    //
    // `localUrl` is watched alongside `isRunning` because the port is not
    // fixed. Ask for 8091 and get 8094, and the URL the console must call
    // changes without `isRunning` ever going false.
    final server = Get.find<ServerController>();
    _serverWorkers = [
      ever(server.isRunning, (_) => _probeServer()),
      ever(server.localUrl, (_) => _probeServer()),
      // The key is watched too, and not only `isRunning`: turning it on makes
      // every unauthenticated call 401 and turning it off makes them work
      // again, with no other observable changing. Without this the console keeps
      // whatever the last answer was — so enabling the key in Settings and coming
      // back here leaves a working server reading as broken.
      ever(server.useApiKey, (_) => _probeServer()),
      ever(server.apiKey, (_) => _probeServer()),
    ];
  }

  @override
  void didUpdateWidget(covariant EncoderConsole old) {
    super.didUpdateWidget(old);
    if (old.inference.loadedModelName.value !=
        widget.inference.loadedModelName.value) {
      _load();
    }
  }

  @override
  void dispose() {
    for (final w in _serverWorkers) {
      w.dispose();
    }
    _query.dispose();
    _documents.dispose();
    _labels.dispose();
    super.dispose();
  }

  /// Ready-made cases, per role, that fill the fields.
  ///
  /// These are not prompts in the chat's sense, and that is the point: a chat
  /// prompt is judged by the answer, which an encoder does not give. Each one
  /// here is chosen so the *scores* say something checkable —
  ///
  /// - a case where one document is the answer and three are not, so a working
  ///   reranker puts a clear gap between them;
  /// - an off-domain case, where nothing is relevant and the scores should
  ///   flatten, which is the control that proves the first case was signal and
  ///   not a model that scores everything high;
  /// - a Portuguese case, because the app is pt_BR and an encoder that only
  ///   works in English is a fact worth discovering here rather than later;
  /// - a self-match, the most confident pair that exists, which bounds the top
  ///   of the range.
  ///
  /// Tapping one fills the fields and does not run, so the text is editable
  /// before spending 100 ms of inference on it.
  List<({String label, String query, String documents})> get _templates {
    if (_role == 'reranker') {
      return [
        (
          label: 'enc_case_obvious'.tr,
          query: 'how much storage does the offline map cache use',
          documents:
              'The offline map tiles for the whole region take about 1,4 GB of internal storage.\n'
                  'The map cache holds vector tiles and a small index, around 340 MB per city.\n'
                  'The battery saver reduces background network activity.\n'
                  'A recipe for sourdough bread with whole wheat flour and rye.',
        ),
        (
          label: 'all four are on topic',
          query: 'why does my app crash on Android 15',
          documents: 'Android 15 enforces 16 KB page alignment and a library built without it fails to load.\n'
              'Android 15 restricts background activity launches and needs new PendingIntent flags.\n'
              'Android 15 delivers notifications more slowly to save battery.\n'
              'Android 15 adds predictive back for apps that opt in.',
        ),
        (
          label: 'enc_case_off_domain'.tr,
          query: 'how to bake sourdough bread at home',
          documents: 'Android 15 enforces 16 KB page alignment.\n'
              'The map cache holds about 340 MB per city.\n'
              'Predictive back is opt-in on Android 15.\n'
              'Internal storage shows under Settings, Apps, Storage.',
        ),
        (
          label: 'em português',
          query: 'quanto espaço o cache de mapas ocupa no aparelho',
          documents: 'Os tiles do mapa inteiro ocupam cerca de 1,4 GB de armazenamento interno.\n'
              'O cache guarda tiles vetoriais e um índice pequeno, uns 340 MB por cidade.\n'
              'O economizador de bateria reduz a atividade de rede em segundo plano.\n'
              'Uma receita de pão de fermentação natural com farinha integral.',
        ),
        (
          label: 'enc_case_self_match'.tr,
          query: 'a cross-encoder scores a query against a document',
          documents: 'a cross-encoder scores a query against a document',
        ),
      ];
    }
    if (_role == 'embedding') {
      return [
        (
          label: 'enc_case_paraphrase'.tr,
          query: 'the cat sat on the sofa',
          documents: '',
        ),
        (
          label: 'enc_case_storage'.tr,
          query: 'how much storage does the offline map cache use',
          documents: '',
        ),
        (
          label: 'em português',
          query: 'o gato dormiu no sofá',
          documents: '',
        ),
      ];
    }
    return const [];
  }

  void _applyTemplate(String query, String documents) {
    _query.text = query;
    if (_role == 'reranker') {
      _documents.text = documents;
    }
    setState(() {
      _raw = null;
      _ranked = null;
      _vector = null;
      _error = null;
    });
  }

  Future<void> _load() async {
    if (!widget.inference.isModelLoaded.value) {
      setState(() => _info.value = null);
      return;
    }
    EncoderInfo? info;
    try {
      info = await LlamaEncoder.info();
    } on Object {
      info = null;
    }
    final info2 = info;
    if (!mounted) return;
    setState(() => _info.value = info2);
    await _probeServer();
  }

  /// Re-reads the server's URL and asks it whether it is there.
  ///
  /// Separate from [_load] because the two change for different reasons and at
  /// different times: the encoder surface only when a model is loaded, the
  /// server's address whenever the server starts, stops or moves port. Folding
  /// them together would mean re-querying the JNI on every server toggle.
  Future<void> _probeServer() async {
    // The port comes from the server controller, which is what actually
    // negotiates it: the user can ask for 8091 and get 8094 if 8091 was taken,
    // so a hardcoded port probes a port nothing is listening on and the console
    // says "server not running" while the server is running fine.
    final url = Get.find<ServerController>().baseUrl;
    final up = await _probe(url);
    if (!mounted) return;
    // A probe that came back after the server was asked to stop must not
    // resurrect the button: the user turned it off, and a stale 200 says
    // otherwise.
    if (up && !Get.find<ServerController>().isRunning.value) return;
    setState(() {
      _serverUp = up;
      _base = url;
    });
  }

  /// The `Authorization` header this app's own calls have to carry.
  ///
  /// Empty when the server is not asking for a key, and not asking is the state
  /// this console shipped in — so this line is what keeps it working for whoever
  /// turned the key on afterwards. Without it the probe below reads "not
  /// running" against a server that is running and listening, and the run button
  /// goes dead with nothing on screen to say why.
  Map<String, String> get _auth => localApiHeaders(
        useApiKey: Get.find<ServerController>().useApiKey.value,
        apiKey: Get.find<ServerController>().apiKey.value,
      );

  Future<bool> _probe(String base) async {
    try {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final req = await c
          .getUrl(Uri.parse('$base/v1/server/capabilities'))
          .timeout(const Duration(seconds: 2));
      for (final e in _auth.entries) {
        req.headers.set(e.key, e.value);
      }
      // getUrl devolve o request, não a response: o status code só existe
      // depois do close(), e sem isso o probe não compila.
      final res = await req.close().timeout(const Duration(seconds: 2));
      c.close();
      return res.statusCode == 200;
    } on Object {
      return false;
    }
  }

  /// One call, three shapes, because the three endpoints are three shapes.
  Future<void> _run() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _raw = null;
      _ranked = null;
      _vector = null;
    });
    final t0 = DateTime.now();
    try {
      final path = switch (_role) {
        'embedding' => '/v1/embeddings',
        'reranker' => '/v1/rerank',
        'classifier' => '/v1/classify',
        _ => '',
      };
      if (path.isEmpty) {
        throw StateError('not an encoder');
      }
      final body = switch (_role) {
        'embedding' => {'input': _query.text},
        'reranker' => {
            'query': _query.text,
            'documents': _documents.text
                .split('\n')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList(),
          },
        _ => {
            'input': _query.text,
            'labels': _labels.text
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList(),
          },
      };
      if (_base.isEmpty) {
        throw StateError('soc_no_address_hint'.tr);
      }
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final req = await client.postUrl(Uri.parse('$_base$path'));
      req.headers.contentType = ContentType.json;
      for (final e in _auth.entries) {
        req.headers.set(e.key, e.value);
      }
      req.write(jsonEncode(body));
      final resp = await req.close().timeout(const Duration(seconds: 120));
      final text = await resp.transform(utf8.decoder).join();
      client.close();

      final json = jsonDecode(text) as Map<String, dynamic>;
      if (resp.statusCode != 200) {
        setState(() => _error = (json['error'] ?? text).toString());
        return;
      }
      if (!mounted) return;
      setState(() {
        _ms = DateTime.now().difference(t0).inMilliseconds;
        _raw = const JsonEncoder.withIndent('  ').convert(json);
        if (path == '/v1/rerank') {
          _ranked = ((json['results'] as List?) ?? [])
              .cast<Map<String, dynamic>>()
              .toList();
        } else if (path == '/v1/embeddings') {
          final d = ((json['data'] as List?) ?? []).firstOrNull
              as Map<String, dynamic>?;
          _vector = (d?['embedding'] as List?)?.cast<double>().toList();
        }
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final field = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);

    if (_role.isEmpty) {
      // **This is where the System One window is reachable from, and the old
      // sentence here was wrong for the models it most needed to be right
      // about.** It said "A generation model has nothing here to test", and
      // Tev1-0.8B is a generation model that *is* a decision model: it takes a
      // `state`, a `question` and options, and answers with one letter. Nothing
      // here can test that, because this console's whole shape is one query in
      // and a score vector out — but "nothing here" is not "nothing anywhere",
      // and a user with Tev1 loaded was told the wrong thing by a panel that
      // looked authoritative.
      //
      // **The button does not claim the model is a decision model, because
      // nothing can know that.** A decision model is an ordinary GGUF: Tev1
      // loads as `qwen35`, and so does a chat model that chats. Its metadata
      // carries no flag. So the window is offered as the way to *find out* — it
      // shows this model a set of options and reports the letter back, which is
      // the test, and the window says plainly when the answer is not a letter.
      return Column(
        children: [
          _panel(
            card,
            Icon(Icons.rule,
                color: isDark ? Colors.white54 : Colors.black45, size: 34),
            'Not an encoder',
            'enc_needs_bert'.tr,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _openSystemOne,
            icon: const Icon(Icons.rule, size: 16),
            label: Text('enc_test_as_decision'.tr),
          ),
          const SizedBox(height: 8),
          Text(
            'enc_decision_model_explains'.tr,
            style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      );
    }

    if (_role == 'headless') {
      final tags = _info.value?.ggufTags ?? const <String>[];
      return _panel(
        card,
        Icon(Icons.link_off_rounded,
            color: isDark ? Colors.orange : Colors.deepOrange, size: 34),
        'enc_no_output'.tr,
        'The architecture is an encoder, but this file carries neither a\n'
            'classification head (cls.output.weight) nor a pooling type, so\n'
            'llama.cpp has no logit to return and no vector to pool. It loads,\n'
            'and it can do nothing — it is a body with the ends cut off.\n\n'
            'Nothing in this app can fix that; it is the conversion that is\n'
            'incomplete. A cross-encoder like this one is measured to be useful\n'
            'only for ordering, and ordering needs the head.',
        extra: [
          if (tags.isNotEmpty)
            preencher('enc_self_declared_tags', {'t': tags.join(', ')}),
          'enc_works_reranker'.tr,
          'enc_works_embed'.tr,
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      children: [
        // what is loaded, and whether it can be reached at all
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Icon(Icons.memory_rounded,
                size: 18, color: isDark ? AppColors.primary : Colors.teal),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.inference.loadedModelName.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    // Tappable, because the state it reports is the one thing
                    // about the console that can be wrong without anything
                    // else looking wrong.
                    GestureDetector(
                      onTap: _serverUp ? null : _probeServer,
                      child: Text(
                        _serverUp
                            ? '$_base  ·  $_role'
                            : 'enc_server_off'.tr,
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            decoration:
                                _serverUp ? null : TextDecoration.underline,
                            decorationColor:
                                isDark ? Colors.orange : Colors.deepOrange,
                            color: _serverUp
                                ? Colors.green
                                : (isDark ? Colors.orange : Colors.deepOrange)),
                      ),
                    ),
                  ]),
            ),
            if (widget.onClose != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'enc_hide_console'.tr,
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: widget.onClose,
              ),
          ]),
        ),
        const SizedBox(height: 12),

        // What the file says about itself, next to what it can actually do.
        //
        // Shown for every role, not only the broken one, because the
        // disagreement is the interesting part and it is invisible when the model
        // works: a file that calls itself a reranker and embeds is a different
        // file from one that calls itself a reranker and does not. Every field
        // here is absent on some converter's output — `general.tags` is on one
        // file in four, `<arch>.pooling_type` on one in four — so the empty case
        // is the normal one and is stated rather than left blank.
        ..._fileSays(isDark, field, card),

        if (_role == 'embedding')
          _field(field, 'Text', _query, maxLines: 3)
        else ...[
          if (_templates.isNotEmpty) ...[
            _label('templates', 'enc_tap_to_fill'.tr),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in _templates)
                  ActionChip(
                    label:
                        Text(t.label, style: GoogleFonts.inter(fontSize: 11)),
                    onPressed: () => _applyTemplate(t.query, t.documents),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          _field(field, _role == 'reranker' ? 'Query' : 'Text', _query,
              maxLines: 2),
          if (_role == 'reranker')
            _field(field, 'Documents — one per line', _documents,
                maxLines: 6,
                initial: 'enc_doc_example'.tr)
          else
            _field(field, 'Labels — comma separated', _labels,
                maxLines: 1, initial: 'positive, negative'),
        ],
        const SizedBox(height: 12),

        // Enabled even when the server is down. A disabled button here is
        // indistinguishable from a broken one — the greying tells you it cannot
        // be pressed but not why, and the reason is a line of small grey text
        // above it that reads like a caption. Pressing it and getting a named
        // failure is the same information with a cause, and a control that
        // works by itself cannot be the thing that silently stops working.
        FilledButton.icon(
          onPressed: _busy ? null : _run,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            backgroundColor: _serverUp ? null : Colors.orange,
          ),
          icon: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(
                  _serverUp
                      ? Icons.play_arrow_rounded
                      : Icons.warning_amber_rounded,
                  size: 18),
          label: Text(_busy
              ? 'running'
              : _serverUp
                  ? 'run'
                  : 'enc_run_server_off'.tr),
        ),

        if ((_info.value?.maxInputTokens ?? 0) > 0) ...[
          const SizedBox(height: 8),
          Text(
            preencher('enc_tokens_hint', {'n': _info.value!.maxInputTokens.toString()}),
            style: GoogleFonts.inter(
                fontSize: 11, color: isDark ? Colors.white38 : Colors.black45),
          ),
        ],

        if (_error != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_error!,
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.error)),
          ),
        ],

        if (_ranked != null) ...[
          const SizedBox(height: 14),
          _label('ranked', '$_ms ms  ·  spread ${_spread.toStringAsFixed(4)}'),
          const SizedBox(height: 4),
          Text(
            'enc_bar_scaled'.tr,
            style: GoogleFonts.inter(
                fontSize: 10, color: isDark ? Colors.white38 : Colors.black45),
          ),
          const SizedBox(height: 8),
          if (_spread < 0.0001)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'enc_scores_identical'.tr,
                style: GoogleFonts.inter(fontSize: 11, color: AppColors.error),
              ),
            ),
          for (var i = 0; i < _ranked!.length; i++)
            _scoredRow(
              _ranked![i],
              i,
              field,
              isDark,
              isTop: i == 0,
            ),
        ],

        if (_vector != null) ...[
          const SizedBox(height: 14),
          _label('vector', '${_vector!.length} values · $_ms ms'),
          const SizedBox(height: 6),
          _row('norm', _norm(_vector!).toStringAsFixed(6),
              '1.000000 means L2-normalised: cosine is a plain dot product'),
          const SizedBox(height: 6),
          _mono(_vector!.take(24).map((e) => e.toStringAsFixed(4)).join('  '),
              field),
          if (_vector!.length > 24) ...[
            const SizedBox(height: 4),
            Text(preencher('enc_more_items', {'n': '${_vector!.length - 24}'}),
                style: GoogleFonts.inter(
                    fontSize: 10,
                    color: isDark ? Colors.white38 : Colors.black45)),
          ],
        ],

        if (_raw != null) ...[
          const SizedBox(height: 14),
          _label('response', 'enc_tap_to_copy'.tr),
          const SizedBox(height: 6),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: _raw!));
              Get.snackbar('copied', 'enc_copied'.tr,
                  snackPosition: SnackPosition.BOTTOM,
                  duration: const Duration(seconds: 2));
            },
            child: _mono(_raw!, field, maxHeight: 260),
          ),
        ],
      ],
    );
  }

  /// The file's own account of itself, from the metadata the native side reads
  /// out of the GGUF header.
  ///
  /// Reads the file rather than the hub on purpose: this is the metadata that
  /// came out of the *conversion*, which is the thing in question. The upstream
  /// `config.json` describes the checkpoint, and a conversion is free to lose
  /// part of it — the jina's tags are right and its head is gone, which is only
  /// visible by reading both.
  List<Widget> _fileSays(bool isDark, Color field, Color card) {
    final i = _info.value;
    if (i == null) return const [];
    final dim = isDark ? Colors.white38 : Colors.black45;
    Widget line(String k, String v, {bool warn = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 74,
              child: Text(k,
                  style: GoogleFonts.jetBrainsMono(fontSize: 10, color: dim)),
            ),
            Expanded(
              child: Text(v,
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: warn
                          ? (isDark ? Colors.orange : Colors.deepOrange)
                          : null)),
            ),
          ]),
        );
    final tags = i.ggufTags;
    return [
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration:
            BoxDecoration(color: card, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('enc_what_file_says'.tr,
              style:
                  GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          line('name', i.ggufName.isEmpty ? '(none)' : i.ggufName),
          line('tags', tags.isEmpty ? '(none)' : tags.join(', '),
              warn: tags.isNotEmpty && _role == 'headless'),
          line('labels',
              i.ggufLabels.isEmpty ? '(none)' : i.ggufLabels.join(', ')),
          line('pooling',
              i.ggufPooling.isEmpty ? '(not declared)' : i.ggufPooling),
          line(
              'head',
              i.hasClassificationHead
                  ? 'cls.output.weight present'
                  : 'cls.output.weight ABSENT',
              warn: !i.hasClassificationHead && _role == 'headless'),
          const SizedBox(height: 4),
          Text(
            'enc_file_decides_role'.tr,
            style: GoogleFonts.inter(fontSize: 10, color: dim),
          ),
        ]),
      ),
      const SizedBox(height: 12),
    ];
  }

  String _docsFor(int i) {
    final d = _documents.text.split('\n').map((e) => e.trim()).toList();
    return i < d.length ? d[i] : '(document $i)';
  }

  List<double> get _scores =>
      _ranked!.map((r) => (r['relevance_score'] as num).toDouble()).toList();

  double get _maxScore =>
      _ranked!.isEmpty ? 0 : _scores.reduce((a, b) => a > b ? a : b);

  double get _minScore =>
      _ranked!.isEmpty ? 0 : _scores.reduce((a, b) => a < b ? a : b);

  /// How far apart the best and worst document in this set landed.
  ///
  /// Printed next to the timing because it is the number that decides whether
  /// the ranking means anything, and it is the one that catches a model which
  /// is loaded and returning 200 while scoring everything the same. Measured on
  /// the Edge 60: 2,0698 for a set with one real answer, 0,2177 for a
  /// nonsense query, and the order is the same every time.
  double get _spread => _maxScore - _minScore;

  /// One ranked document: position, a filled bar, the absolute numbers, and
  /// the text that earned the score.
  ///
  /// The bar is scaled between the worst and best score *in this set* rather
  /// than from zero, which is a choice with a consequence worth naming: it makes
  /// a set where every document is equally bad look as decisive as one where
  /// the answer is obvious. The header's spread and the printed logit are what
  /// hold that down, and the flat-set warning covers the degenerate case where
  /// the bar would otherwise divide by zero.
  Widget _scoredRow(Map<String, dynamic> r, int rank, Color field, bool isDark,
      {required bool isTop}) {
    final score = (r['relevance_score'] as num).toDouble();
    final frac = _spread <= 0 ? 0.0 : (score - _minScore) / _spread;
    final accent = isDark ? AppColors.primary : const Color(0xFF6B8E00);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isTop ? accent : field,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('${rank + 1}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isTop
                      ? Colors.black
                      : (isDark ? Colors.white54 : Colors.black45),
                )),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${score.toStringAsFixed(4)}',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          Text('sigmoid ${_sigmoid(score).toStringAsFixed(4)}',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: isDark ? Colors.white38 : Colors.black45)),
        ]),
        const SizedBox(height: 5),
        // Track plus fill. The fill is the score, so it is drawn last and
        // clipped to the fraction — a `FractionallySizedBox` rather than a
        // width, because the parent is unconstrained and a hard width would
        // be wrong on a narrower phone.
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Container(
            height: 6,
            color: field,
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: frac.clamp(0.0, 1.0),
              child: Container(color: accent),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(_docsFor(r['index'] as int),
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: isTop ? FontWeight.w500 : FontWeight.w400,
            )),
      ]),
    );
  }

  /// Open the System One window for whatever is loaded.
  ///
  /// **The shape is left `unknown` on purpose.** This console is looking at a
  /// GGUF that is not an encoder, and the two things it could be — a plain chat
  /// model or a decision model — carry the same metadata. Deciding here from the
  /// filename would be the mistake this whole feature is built to avoid, and the
  /// window asks the server instead.
  void _openSystemOne() {
    Get.to(() => SystemOneConsole(
          // This console is already above the chat, so it opens the window over
          // the top rather than pushing a route on top of itself.
          onClose: () => Get.back(),
        ));
  }

  Widget _panel(Color card, Widget icon, String title, String body,
      {List<String> extra = const []}) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        icon,
        const SizedBox(height: 12),
        Text(title,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: card, borderRadius: BorderRadius.circular(12)),
          child: Text(body,
              style: GoogleFonts.inter(
                  fontSize: 12, height: 1.45, color: Colors.white70)),
        ),
        if (extra.isNotEmpty) ...[
          const SizedBox(height: 14),
          for (final e in extra)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('· $e',
                  style:
                      GoogleFonts.inter(fontSize: 11, color: Colors.white38)),
            ),
        ],
      ],
    );
  }

  Widget _field(Color field, String label, TextEditingController c,
      {int maxLines = 1, String initial = ''}) {
    if (c.text.isEmpty && initial.isNotEmpty) c.text = initial;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        style: GoogleFonts.inter(fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: field,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _label(String t, String hint) => Row(children: [
        Text(t,
            style:
                GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(hint,
            style: GoogleFonts.inter(fontSize: 10, color: Colors.white38)),
      ]);

  Widget _row(String a, String b, String c) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(a,
                style: GoogleFonts.inter(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(width: 10),
            Text(b,
                style: GoogleFonts.inter(fontSize: 10, color: Colors.white38)),
          ]),
          Text(c, style: GoogleFonts.inter(fontSize: 12)),
        ]),
      );

  Widget _mono(String s, Color field, {double? maxHeight}) => Container(
        width: double.infinity,
        constraints: maxHeight == null
            ? const BoxConstraints()
            : BoxConstraints(maxHeight: maxHeight),
        padding: const EdgeInsets.all(10),
        decoration:
            BoxDecoration(color: field, borderRadius: BorderRadius.circular(8)),
        child: SingleChildScrollView(
          child: Text(s,
              style: GoogleFonts.jetBrainsMono(fontSize: 10.5, height: 1.35)),
        ),
      );
}

double _sigmoid(double x) => 1 / (1 + _exp(-x));
double _exp(double x) {
  if (x > 700) return double.infinity;
  if (x < -700) return 0;
  var sum = 1.0, term = 1.0;
  for (var i = 1; i < 20; i++) {
    term *= x / i;
    sum += term;
  }
  return sum;
}

double _norm(List<double> v) {
  var s = 0.0;
  for (final e in v) {
    s += e * e;
  }
  return _sqrt(s);
}

double _sqrt(double x) {
  if (x <= 0) return 0;
  var g = x;
  for (var i = 0; i < 20; i++) {
    g = 0.5 * (g + x / g);
  }
  return g;
}
