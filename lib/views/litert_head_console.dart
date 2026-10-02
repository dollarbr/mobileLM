import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../controllers/server_controller.dart';
import '../core/colors.dart';
import '../services/litert_model.dart';
import '../services/litert_service.dart';
import '../utils/server_auth.dart';
import 'api_console_shell.dart';

/// A console for a loaded `.tflite` head, shown above the chat.
///
/// It talks to the local HTTP server, not to the plugin, for the same reason the
/// encoder console does: the thing worth testing on a phone is the API surface,
/// since that is what anything else on the network will use, and a console that
/// went straight to `LiteRt.run()` would pass while `/v1/classify` was broken.
///
/// It is a **separate console** rather than another mode of the encoder one
/// because the two share almost nothing. That console sends a query and reads
/// scores; this one names input tensors and reads logits, and the names are the
/// whole problem — the LiteRT API binds by name and cannot list them, which is
/// why the file is screened before anything is sent to it.
///
/// Two things this deliberately does not do:
///
/// - **It does not invent auxiliary inputs.** A head with inputs beyond the
///   feature vector needs the caller to supply them; filling them with zeros
///   returns a confident logit computed on invented features, which is worse
///   than a refusal that names them.
/// - **It does not claim to know which accelerator ran.** `CompiledModel` has no
///   getter for it, so the console shows what the *device* reports and what was
///   *requested*, and says plainly which of the two it is looking at.
class LitertHeadConsole extends StatefulWidget {
  const LitertHeadConsole({
    super.key,
    this.onClose,
    this.baseUrl,
    this.authHeaders = const {},
    this.filename,
  });

  final VoidCallback? onClose;

  /// The `.tflite` this console is for.
  ///
  /// **Taken from the card the user tapped, not from what happens to be loaded.**
  /// The first version read the loaded model out of `GET /v1/litert/status`, and
  /// the console then opened showing "No .tflite loaded" — measured on the A72,
  /// from the screen reached by tapping the file itself. A console pointed at
  /// nothing because the runtime had nothing loaded yet is a console that cannot
  /// load anything, and the screen it is opened from is the one naming the file.
  ///
  /// The screen and the load still go through the server: this is a name to look
  /// at, not a handle on a runtime.
  final String? filename;

  /// Where the server is, and what to authenticate with.
  ///
  /// Both are constructor arguments with the production values as defaults
  /// rather than `Get.find` calls buried in the state, and the reason is that a
  /// layout test for this screen would otherwise have to stand up the whole
  /// GetX graph: `ServerController` reads `HiveService`, `InferenceService` and
  /// `AppLogService` in its field initialisers, so testing "does the accelerator
  /// row overflow at 360 dp" turns into a test of the dependency container.
  ///
  /// The value still comes from `ServerController` in the app — the port is
  /// negotiated and the key is a setting — so this is a seam, not a second
  /// source of truth.
  final String? baseUrl;

  /// `localApiHeaders(...)` in the app; `{}` in a test.
  final Map<String, String> authHeaders;

  @override
  State<LitertHeadConsole> createState() => _LitertHeadConsoleState();
}

class _LitertHeadConsoleState extends State<LitertHeadConsole> {
  final _features = TextEditingController();
  final _auxiliary = TextEditingController();

  /// The screen result: what the FlatBuffer says the graph wants.
  final _info = Rxn<LitertModelInfo>();

  bool _busy = false;
  String? _error;
  String? _raw;

  /// `top_index` and the logits beside it, kept apart from the raw JSON so the
  /// console can show them as a result rather than as text to read.
  List<double>? _logits;
  int? _topIndex;
  int _ms = 0;

  bool _serverUp = false;
  String _base = '';

  /// Which accelerator to *ask* for. Not what ran — see the class doc.
  List<String> _accelerator = const ['CPU'];

  /// The last status failure, shown next to the accelerator line.
  ///
  /// One line, and named — the same rule the engine errors follow, because a
  /// console that reports a blank panel is worse than one that reports a refusal.
  String? _statusError;

  /// What the device says it can do, from `GET /v1/litert/status`.
  List<String> _available = const [];
  List<String> _requested = const [];
  String? _executed;
  String? _executedNote;

  List<Worker> _workers = [];

  /// The signature this console will drive.
  LitertSignature? get _signature => _info.value?.defaultSignature;

  /// Which input the feature vector fills.
  ///
  /// The **largest** one, and the console says so out loud rather than picking
  /// silently — the rule is a heuristic (see `TfliteHeadShape`) and a heuristic
  /// that does not announce itself is indistinguishable from a bug. Laya's act
  /// head stores `feats [1,4]` *before* `pooled_cls [1,1024]`, so "the first
  /// input" picks the auxiliary, and the endpoint's error message about it is
  /// both correct and about the wrong thing.
  TfliteHeadShape? get _head {
    final s = _signature;
    return s == null ? null : tfliteHeadShape(s);
  }

  bool _screened = false;

  /// Screen as soon as there is something loaded to screen, exactly once.
  ///
  /// Automatic because the console has nothing useful to show without it and the
  /// user did not come here to press "screen" first. Once, because the status
  /// poll fires on every server-state change and a screen is a file read per
  /// change.
  Future<void> _screenOnce() async {
    if (_screened || _busy || !_serverUp) return;
    if (_info.value != null) return;
    if (widget.filename == null && _loadedBasename == null) return;
    _screened = true;
    await _screen();
  }

  /// The production server controller, or null when the console was given its
  /// address directly.
  ServerController? get _server =>
      widget.baseUrl == null ? Get.find<ServerController>() : null;

  @override
  void initState() {
    super.initState();
    // The console mounts before the server is normally started, so a single probe
    // in initState reads "not running" and every button stays dead for the rest
    // of the session with nothing on screen to explain it. Measured on the A72,
    // with a server that was up and reachable.
    //
    // All four observables are watched, and the key matters as much as the
    // address: turning it on makes every unauthenticated call 401 with no other
    // observable changing, so a console that only watches `isRunning` keeps
    // whatever the last answer was.
    final server = _server;
    if (server != null) {
      _workers = [
        ever(server.isRunning, (_) => _probe()),
        ever(server.localUrl, (_) => _probe()),
        ever(server.useApiKey, (_) => _probe()),
        ever(server.apiKey, (_) => _probe()),
      ];
    }
    _probe();
  }

  @override
  void dispose() {
    for (final w in _workers) {
      w.dispose();
    }
    _features.dispose();
    _auxiliary.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    final url = widget.baseUrl ?? Get.find<ServerController>().baseUrl;
    final up = await _ping(url);
    if (!mounted) return;
    // A probe that answered after the server was stopped must not resurrect the
    // button: the user turned it off and a stale 200 says otherwise.
    if (up && _server?.isRunning.value == false) return;
    setState(() {
      _serverUp = up;
      _base = url;
    });
    if (up) {
      unawaited(_status());
      // Independent of the status, and deliberately so. The first version fired
      // the screen from inside `_status`'s success path, which meant a status
      // failure took the screen down with it — and since the status failure was
      // itself a swallowed exception, the console just sat there saying "not
      // screened yet" with nothing anywhere saying that anything had gone wrong.
      // Two questions, two calls, neither able to silence the other.
      unawaited(_screenOnce());
    }
  }

  /// The shared transport: how this console talks to the local server, and the
  /// look it shares with the System One window.
  ///
  /// **A shared client and a shared palette, not a shared widget.** This console
  /// **introspects** a loaded head — what the file is, which tensors it wants,
  /// what the device can accelerate. `SystemOneConsole` **drives** a model: it
  /// asks a question and shows what came back. Merging them would put a `switch`
  /// inside a body that is already a `switch`, and past this line the two have
  /// almost nothing in common.
  ///
  /// `throwOnError: true` because every call site here is
  /// `on Object catch (e) => _error = '$e'` — on this console that is how a
  /// refusal reaches the screen. The System One window wants the opposite,
  /// because a `/v1/classify` 422 carries the decision model's own text and that
  /// text *is* the answer.
  late final ApiConsoleClient _client = ApiConsoleClient(
    baseUrl: _base,
    authHeaders: widget.authHeaders,
    authResolver: _liveAuth,
    throwOnError: true,
  );

  /// The key as the controller holds it **now**, not as it was when this widget
  /// was built.
  ///
  /// `localApiHeaders()` per call and not a stored map: `/v1/**` is behind
  /// `_isAuthorized` and `useApiKey` shipped defaulting to `false`, so no in-app
  /// client sent the header at all and nothing was wrong until somebody turned
  /// the key on — at which point every call came back 401 and this console's
  /// probe read "server not running" against a server that was running, with
  /// nothing else on screen changing.
  Map<String, String> _liveAuth() {
    final server = _server;
    if (server == null) return const {};
    return localApiHeaders(
      useApiKey: server.useApiKey.value,
      apiKey: server.apiKey.value,
    );
  }

  Future<bool> _ping(String base) async {
    // The shared probe, against `capabilities` because that is the one endpoint
    // that answers 200 on a server with no model loaded. A probe that used a
    // model-requiring endpoint reported the server as down whenever the model was
    // not there, which is the same shape of error as the method mistake below.
    return ApiConsoleClient(
      baseUrl: base,
      authHeaders: widget.authHeaders,
      authResolver: _liveAuth,
    ).ping();
  }

  /// One request, returning the decoded body or throwing the server's message.
  ///
  /// **The method is a parameter and not implied by the helper name**, and that
  /// is the whole point of this one function existing in both shapes. The first
  /// version had `_post` and called it for `/v1/litert/status`, which is `GET`
  /// only — the route check is `request.method == 'GET'`, so a `POST` fell
  /// through to the 404 arm. The console caught it, showed a probe that said the
  /// server was up, and left every status-dependent panel blank: "not screened
  /// yet", "device reports: (not read yet)", a run button with nothing to run.
  ///
  /// Measured on the A72, and the failure had no symptom of its own — it looked
  /// exactly like "the server is up and the head is not loaded yet". Which is why
  /// the method travels with the call instead of being chosen by which helper
  /// you reach for.
  ///
  /// The 120 s default is for the *compile*: a 705 MB graph takes seconds of
  /// native time, and the load endpoint answers `202` before that work happens,
  /// so the real wait is on the follow-up poll rather than here.
  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic> body = const {},
    Duration timeout = const Duration(seconds: 120),
  }) =>
      _client.request(method, path, body: body, timeout: timeout);

  /// Screen the file: what it wants, before anything is loaded.
  Future<void> _screen() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final json = await _post(
        '/v1/litert/screen',
        {'filename': await _filename()},
      );
      if (!mounted) return;
      setState(() {
        _info.value = LitertModelInfo.fromJson(json);
        _raw = const JsonEncoder.withIndent('  ').convert(json);
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 120),
  }) =>
      _request('POST', path, body: body, timeout: timeout);

  Future<Map<String, dynamic>> _get(
    String path, {
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _request('GET', path, timeout: timeout);

  /// The file this console is about: the one it was opened for.
  String? get _target => widget.filename ?? _loadedBasename;

  Future<String> _filename() async {
    final t = _target;
    if (t != null) return t;
    throw StateError(
      'no .tflite named. Open the console from a .tflite in the Models '
      'screen, or POST /v1/litert/load with a filename first.',
    );
  }

  /// The loaded model's basename, as the status reports it.
  ///
  /// Used for the *loaded* half of the state — what the runtime actually holds —
  /// which is a different fact from what the console was opened for, and worth
  /// showing separately rather than conflating.
  String? _loadedBasename;

  /// What the device says it can do, and what the runtime holds.
  ///
  /// Called on every server-state change, so it must never be the thing that
  /// decides whether the console works — hence `_screenOnce` is fired by
  /// `_probe`, not from here. Measured: the first version called it from this
  /// method's success path, so a failure here silently took the screen with it.
  Future<void> _status() async {
    try {
      final json = await _get('/v1/litert/status');
      if (!mounted) return;
      final loaded = json['loaded'] as Map?;
      final accel = json['accelerators'] as Map?;
      setState(() {
        _loadedBasename = (loaded?['path'] as String?)?.split('/').last;
        _available = ((accel?['available'] as List?) ?? const [])
            .map((e) => '$e')
            .toList();
        _statusError = null;
      });
    } on Object catch (e) {
      // **Not silent.** A poll that fails quietly is how a `POST` to a GET-only
      // route survived a full on-device run: the panel said "(not read yet)"
      // forever, which reads as "the device has not answered" rather than "this
      // call has been failing since the console opened". The probe still said
      // the server was up — it was, this is a route-level problem — so no other
      // part of the UI disagreed with the blank panel.
      if (mounted) setState(() => _statusError = '$e');
    }
  }

  /// Load, then poll until the compile lands or the wait runs out.
  ///
  /// The poll is because the endpoint answers `202` **before** compiling, which
  /// is the right shape for a load that takes seconds — and it means "202" is
  /// not "loaded". Reporting 202 as success is how a caller ends up believing it
  /// has a model when nothing is compiled, so this waits for the status to say
  /// so and reports a timeout as a timeout.
  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final name = await _filename();
      await _post('/v1/litert/load', {
        'filename': name,
        'accept_risk': true,
        'accelerators': _accelerator,
      });
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        final json = await _get('/v1/litert/status');
        final loaded = json['loaded'] as Map?;
        // Matched by name, not "any model". Loading file A while file B was
        // already compiled would otherwise report success and then screen a head
        // that is not the one the user pressed "run" on.
        if (loaded != null && '${loaded['path']}'.endsWith(name)) {
          if (!mounted) return;
          setState(() {
            _requested =
                ((loaded['requested'] as List?) ?? const []).map((e) => '$e').toList();
            _executed = loaded['executed_accelerator'] as String?;
            _executedNote = loaded['executed_accelerator_note'] as String?;
            _raw = const JsonEncoder.withIndent('  ').convert(loaded);
            _busy = false;
          });
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'LiteRT accepted the file 90 s ago and still has not reported it '
            'compiled. The compile log is in Settings, Log.';
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  /// Run the head through `/v1/classify`, which is the path a client uses.
  ///
  /// Not `/v1/litert/run`: that endpoint takes tensors by name and this console
  /// is here to exercise the one a caller actually has. The two agree to the bit
  /// — measured on the A72 with Laya's act head, difference `0.000e+00` — so
  /// driving `classify` tests more of the real surface.
  Future<void> _run() async {
    if (_busy) return;
    final head = _head;
    if (head == null) {
      setState(() => _error = 'screen a .tflite first — nothing to run');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _logits = null;
      _topIndex = null;
    });
    final t0 = DateTime.now();
    try {
      final body = <String, dynamic>{
        'filename': await _filename(),
        'features': _parseNumbers(_features.text, 'features'),
      };
      final auxText = _auxiliary.text.trim();
      if (auxText.isNotEmpty) {
        final aux = jsonDecode(auxText);
        if (aux is! Map) {
          throw StateError('auxiliary must be a JSON object of name → numbers');
        }
        body['auxiliary_inputs'] = {
          for (final e in aux.entries)
            '${e.key}': _parseNumbers('${e.value}', 'auxiliary_inputs.${e.key}'),
        };
      }
      final json = await _post('/v1/classify', body);
      if (!mounted) return;
      setState(() {
        _ms = DateTime.now().difference(t0).inMilliseconds;
        _raw = const JsonEncoder.withIndent('  ').convert(json);
        _logits = ((json['logits'] as List?) ?? const []).cast<double>();
        _topIndex = json['top_index'] as int?;
        _executed = json['executed_accelerator'] as String?;
        _executedNote = json['executed_accelerator_note'] as String?;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A comma or newline separated list of numbers, as the feature vector.
  ///
  /// Not raw JSON, because pasting 1024 floats as `[0.1, 0.2, …]` is a wall of
  /// brackets nobody types by hand, and the console's job is to make the shape
  /// obvious — 1024 cells, one per float.
  List<double> _parseNumbers(String text, String what) {
    final cleaned = text.replaceAll(RegExp(r'[\[\]]'), '').trim();
    if (cleaned.isEmpty) {
      throw StateError('$what is empty');
    }
    final out = <double>[];
    for (final part in cleaned.split(RegExp(r'[,\s]+'))) {
      if (part.isEmpty) continue;
      final v = double.tryParse(part);
      if (v == null) {
        throw StateError('$what has "$part", which is not a number');
      }
      out.add(v);
    }
    if (out.isEmpty) throw StateError('$what is empty');
    return out;
  }

  /// A vector of [n] values with structure, so the run is not all zeros.
  ///
  /// An all-ones or all-zeros feature vector makes a head output a constant, and
  /// a constant looks like a broken runtime rather than an uninformative input.
  /// This is a sine sweep with two frequencies: deterministic, varied in
  /// magnitude, and it exercises more of the graph than a ramp would.
  String _sampleVector(int n) =>
      [for (var i = 0; i < n; i++) (math.sin(i * 0.37) * 0.5 + math.cos(i * 0.11) * 0.25)]
          .map((v) => v.toStringAsFixed(4))
          .join(', ');

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final field = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    final head = _head;

    return Container(
      color: isDark ? const Color(0xFF0F0F11) : const Color(0xFFF7F7F9),
      // **One `Material`, at the root, and this is the fix rather than a
      // patch.** `ChoiceChip`, `TextField` and `InkWell` each call
      // `debugCheckHasMaterial` on themselves, and this console paints its own
      // background with `Container` + `BoxDecoration`, which is not a `Material`.
      //
      // The first version fixed each site as it appeared: a `Material` around the
      // chips (found in the app log, `ChoiceChip.build` →
      // `debugCheckHasMaterial`), and then the same assert again for the
      // `TextField`s, found in a screenshot. Both were symptom-level, and a
      // console that needs a rule per widget is a console that has to be audited
      // every time a panel is added.
      //
      // It is a root-level problem because of how the screen is shown:
      // `Get.to(() => LitertHeadConsole(...))` puts it under `GetMaterialApp`
      // with no `Scaffold`, and `Scaffold` is what normally supplies the
      // `Material`. `MaterialType.transparency` so the console's own background
      // shows through rather than being painted twice.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
        children: [
          _bar(isDark, card),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
              children: [
                if (_target == null)
                  _panel(
                    card,
                    Icons.inventory_2_outlined,
                    'No .tflite to work on',
                    'A .tflite in the models directory now gets a card in '
                        'Models — open its console from there, or POST '
                        '/v1/litert/load with a filename first.',
                  ),
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_error!,
                        style: GoogleFonts.inter(
                            fontSize: 12, color: AppColors.error)),
                  ),
                  const SizedBox(height: 12),
                ],
                _screenPanel(isDark, field, card, head),
                const SizedBox(height: 12),
                _acceleratorPanel(isDark, field, card),
                if (head != null) ...[
                  const SizedBox(height: 12),
                  _inputPanel(isDark, field, head),
                ],
                const SizedBox(height: 14),
                _buttons(isDark),
                if (_logits != null) ...[
                  const SizedBox(height: 14),
                  _resultPanel(isDark, field, card),
                ],
                if (_raw != null) ...[
                  const SizedBox(height: 14),
                  Text('response — tap to copy',
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white54 : Colors.black45)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: _raw!));
                      Get.snackbar('copied',
                          'the JSON response is on the clipboard',
                          snackPosition: SnackPosition.BOTTOM,
                          duration: const Duration(seconds: 2));
                    },
                    child: _mono(_raw!, field, maxHeight: 240),
                  ),
                ],
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _bar(bool isDark, Color card) {
    return Container(
      color: card,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          Icon(Icons.hexagon_outlined, size: 16,
              color: isDark ? Colors.white54 : Colors.black45),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'TFLite head console',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (widget.onClose != null)
            IconButton(
              onPressed: widget.onClose,
              icon: const Icon(Icons.close_fullscreen_rounded, size: 16),
              tooltip: 'show the conversation',
            ),
        ],
      ),
    );
  }

  /// The file's own account of itself — the signature, and each tensor's name,
  /// type and shape.
  ///
  /// This panel is the console's reason to exist. LiteRT binds tensors by name
  /// and offers no way to *list* those names, so the names come from the
  /// FlatBuffer. That is not a convenience: Laya's act head stores `feats` before
  /// `pooled_cls`, and a host that bound position 0 handed a 4-element tensor to a
  /// 1024-wide input.
  Widget _screenPanel(
      bool isDark, Color field, Color card, TfliteHeadShape? head) {
    final info = _info.value;
    final dim = isDark ? Colors.white38 : Colors.black45;
    Widget line(String k, String v, {Color? color}) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 78,
              child: Text(k,
                  style: GoogleFonts.jetBrainsMono(fontSize: 10, color: dim)),
            ),
            Expanded(
              child: Text(v,
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 10, color: color)),
            ),
          ]),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
          color: card, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('what the file says about itself',
              style:
                  GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (info == null)
            Text('not screened yet',
                style: GoogleFonts.inter(fontSize: 11, color: dim))
          else ...[
            line('version', '${info.version}'),
            line('description',
                info.description.isEmpty ? '(none)' : info.description),
            line('signatures', '${info.signatures.length}'),
            if (info.defaultSignature != null)
              line('default', info.defaultSignature!.key),
            for (final s in info.signatures) ...[
              const SizedBox(height: 6),
              Text('signature ${s.key}',
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 10, fontWeight: FontWeight.w700)),
              line('  subgraph', '${s.subgraphIndex}'),
              for (final t in s.inputs)
                line('  in ${t.name}',
                    '${t.type.label} ${t.shapeLabel}'
                    '${t.hasDynamicDimension ? '  dynamic' : ''}'),
              for (final t in s.outputs)
                line('  out ${t.name}', '${t.type.label} ${t.shapeLabel}'),
              if (!s.bindable)
                Text('  not bindable — ${s.unusableReason}',
                    style: GoogleFonts.inter(
                        fontSize: 10,
                        color: isDark ? Colors.orange : Colors.deepOrange)),
            ],
            if (head != null) ...[
              const SizedBox(height: 8),
              Text(
                'The feature vector fills "${head.features.name}" '
                '(${head.featureCount} values) — the largest input. '
                '${head.auxiliary.isEmpty ? 'There are no other inputs.' : 'The other inputs are yours to supply: '
                    '${head.auxiliary.map((t) => t.name).join(", ")}. They are never filled with zeros.'}',
                style: GoogleFonts.inter(fontSize: 10, color: dim),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _acceleratorPanel(bool isDark, Color field, Color card) {
    const options = {
      'CPU': <String>['CPU'],
      'GPU': <String>['GPU'],
      'CPU+GPU': <String>['CPU', 'GPU'],
    };
    final dim = isDark ? Colors.white38 : Colors.black45;
    // A `Material`, and this is not tidiness. `ChoiceChip` calls
    // `debugCheckHasMaterial` on itself, so a `Container` with a `BoxDecoration`
    // between it and the app's `Material` puts the chip outside every `Material`
    // in the tree: it throws a `FlutterError` from `build`, the console's whole
    // subtree fails to render, and the symptom is a console that looks fine until
    // you tap something.
    //
    // Measured on the A72, and it cost the same eight builds the `ListTile` trap
    // cost in `model_view.dart` — same assert, same blast radius, same
    // "everything except the one widget still works" shape. The card *outside* is
    // the `Container`; the `Material` goes immediately inside it, wrapping the
    // chips.
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
          color: card, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('accelerator — what to ask for',
              style:
                  GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          // No `Material` here, on purpose. There used to be one, added to fix
          // this exact assert; it is gone because the root now provides it, and
          // two mechanisms for one rule is one mechanism too many — the next
          // panel would make somebody wonder which of them is the real fix.
          Wrap(
            spacing: 8,
            children: [
              for (final e in options.entries)
                ChoiceChip(
                  label: Text(e.key,
                      style: GoogleFonts.inter(fontSize: 11)),
                  selected: _accelerator.join(',') == e.value.join(','),
                  onSelected: (_) => setState(() => _accelerator = e.value),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'device reports: ${_available.isEmpty ? "(not read yet)" : _available.join(", ")}\n'
            'requested: ${_requested.isEmpty ? "(not loaded yet)" : _requested.join(", ")}\n'
            'executed: ${_executed ?? "unknown"} — '
            '${_executedNote ?? "LiteRT 2.2.0 does not expose the accelerator it used, so this console cannot say. On the device, LITERT_CL or CPU in the log is the answer."}'
            '${_statusError == null ? "" : "\nstatus call failed: $_statusError"}',
            style: GoogleFonts.inter(
                fontSize: 10,
                color: _statusError == null
                    ? dim
                    : (isDark ? Colors.orange : Colors.deepOrange)),
          ),
        ],
      ),
    );
  }

  Widget _inputPanel(bool isDark, Color field, TfliteHeadShape head) {
    final dim = isDark ? Colors.white38 : Colors.black45;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(
          field,
          'features — ${head.featureCount} floats for "${head.features.name}"',
          _features,
          maxLines: 3,
          onFirstBuild: () => _features.text = _sampleVector(head.featureCount),
        ),
        if (head.auxiliary.isNotEmpty) ...[
          const SizedBox(height: 10),
          _field(
            field,
            'auxiliary_inputs — JSON object, '
                '${head.auxiliary.map((t) => '"${t.name}": ${t.elementCount} floats').join(", ")}',
            _auxiliary,
            maxLines: 3,
            onFirstBuild: () => _auxiliary.text = '{'
                '${head.auxiliary.map((t) => '"${t.name}": [${List.filled(t.elementCount, "0.5").join(", ")}]').join(", ")}'
                '}',
          ),
          const SizedBox(height: 8),
          Text(
            'These are not filled with zeros by the app. A head that needs them '
            'and does not get them is refused by name — a logit computed on '
            'invented features comes back wearing a confident label.',
            style: GoogleFonts.inter(fontSize: 10, color: dim),
          ),
        ],
      ],
    );
  }

  Widget _buttons(bool isDark) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy || !_serverUp ? _screen : null,
                icon: const Icon(Icons.search_rounded, size: 16),
                label: const Text('screen'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy || !_serverUp ? _load : null,
                icon: const Icon(Icons.play_circle_outline_rounded, size: 16),
                label: const Text('load'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Enabled even when the server is down. A greyed button tells you it
        // cannot be pressed but not why, and the reason is small grey text above
        // it. Pressing and getting a named failure is the same information with
        // a cause, and a control that works by itself cannot be the thing that
        // silently stops working.
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
              : Icon(_serverUp
                  ? Icons.play_arrow_rounded
                  : Icons.warning_amber_rounded,
                  size: 18),
          label: Text(_busy
              ? 'running'
              : _serverUp
                  ? 'run'
                  : 'run — server is off'),
        ),
      ],
    );
  }

  Widget _resultPanel(bool isDark, Color field, Color card) {
    final logits = _logits!;
    final top = _topIndex ?? 0;
    final mx = logits.isEmpty
        ? 0.0
        : logits.reduce((a, b) => a > b ? a : b);
    // Bars scaled across the result set rather than from zero: with logits
    // straddling zero — which they do, that is what a logit is — a bar from zero
    // makes the larger of two negative numbers look like the loser.
    final span = logits.length < 2
        ? 1.0
        : (logits.reduce(math.max) - logits.reduce(math.min)).abs();
    final low = logits.isEmpty ? 0.0 : logits.reduce(math.min);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
          color: card, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$_ms ms — raw logits',
              style:
                  GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (var i = 0; i < logits.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text('$i',
                        style: GoogleFonts.jetBrainsMono(fontSize: 10)),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Container(
                          height: 12,
                          decoration: BoxDecoration(
                            color: field,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: span == 0
                              ? 0
                              : ((logits[i] - low).abs() / span).clamp(0.0, 1.0),
                          child: Container(
                            height: 12,
                            decoration: BoxDecoration(
                              color: (i == top
                                      ? AppColors.primary
                                      : AppColors.info)
                                  .withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 78,
                    child: Text(
                      logits[i].toStringAsFixed(4),
                      textAlign: TextAlign.right,
                      style: GoogleFonts.jetBrainsMono(fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'top_index $top by argmax of ${mx.toStringAsFixed(4)}. That is an '
            'argmax and not a prediction: it is the right reading only for a '
            'head trained to work that way, and there is no label here because '
            'only the caller knows what class 0 is.',
            style: GoogleFonts.inter(
                fontSize: 10, color: isDark ? Colors.white38 : Colors.black45),
          ),
        ],
      ),
    );
  }

  // ── shared widgets ───────────────────────────────────────────────────────

  Widget _panel(Color card, IconData icon, String title, String body) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: card, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.inter(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(body, style: GoogleFonts.inter(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(Color field, String label, TextEditingController ctrl,
      {int maxLines = 1, void Function()? onFirstBuild}) {
    // Filled once, when the field first appears. Passing an `initial` to a
    // TextField that is already built does nothing at all — the controller holds
    // whatever it held — and the symptom is a field that stays empty while the
    // code beside it clearly meant to fill it.
    onFirstBuild?.call();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.black45)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          minLines: 1,
          style: GoogleFonts.jetBrainsMono(fontSize: 11),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: field,
            border: const OutlineInputBorder(borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  Widget _mono(String s, Color field, {int maxHeight = 200}) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: maxHeight.toDouble()),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: field, borderRadius: BorderRadius.circular(8)),
      child: SingleChildScrollView(
        child: Text(s, style: GoogleFonts.jetBrainsMono(fontSize: 10)),
      ),
    );
  }
}

/// `void` in a `Future`, so a deliberately un-awaited call reads as deliberate.
void unawaited(Future<void> f) {}