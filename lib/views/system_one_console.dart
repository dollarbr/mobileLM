import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobilelm/services/text_interpolation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../controllers/server_controller.dart';
import '../core/colors.dart';
import '../services/system_one.dart';
import '../utils/server_auth.dart';
import 'api_console_shell.dart';

/// A window for driving a **System One** model: one that answers a structured
/// question with a class instead of chatting.
///
/// The name comes from the four that made it worth naming — Jev, Laya, Tev1,
/// Bespoke-Nimble — and the class is **open**. Nothing here keys off those
/// names: the shape is decided by what the file is, the same way `/v1/classify`
/// decides it, so the next model published lands in this window without anybody
/// editing a list. See `system_one.dart` for why the name of a model is the one
/// thing that may not decide what it is.
///
/// ## Why a window and not a card
///
/// All three shapes already have a console, and all three were built to
/// **introspect** one model: the encoder console screens a GGUF, the `.tflite`
/// console names its tensors. This one is the other half — it *asks* the model
/// something and shows what came back, with the options and the labels on screen
/// where the person asking can see them.
///
/// It talks to the local HTTP server rather than to the engine, for the same
/// reason the other two do: the thing worth testing on a phone is the API
/// surface, since that is what anything else on the network will use, and a
/// window that called `inference.generate()` directly would pass while
/// `/v1/classify` was broken.
///
/// ## Two shapes, one screen
///
/// A **decision** model (Tev1, Nimble, OpenJev) takes text — a `state`, a
/// `question` and the options — and gives back one letter. A **head** (the Laya
/// act head) takes a feature vector and gives back logits. Same endpoint,
/// deliberately different bodies, and the window has to know which it is
/// driving before it can type anything into the request.
///
/// The one thing both shapes share is that **the labels are the caller's**, and
/// that is what the window is mostly made of. Neither a decision model nor a
/// head carries its own class names, both endpoints return `label: null` rather
/// than guess, and the screen shows that null and the endpoint's own reason for
/// it. A screen that turned raw logits into a percentage would be the first
/// place in this app that invents a number, and it would be inventing it in the
/// one place a person is about to trust it.
class SystemOneConsole extends StatefulWidget {
  const SystemOneConsole({
    super.key,
    this.onClose,
    this.baseUrl,
    this.authHeaders = const {},
    this.filename,
    this.shape = SystemOneShape.unknown,
    this.embedders = const [],
    this.headContract,
  });

  final VoidCallback? onClose;

  /// The `.tflite` this window is for, when it is a head.
  ///
  /// **Required on the head path and for a reason that is not plumbing**: the
  /// endpoint takes `filename` on `/v1/classify` for a `.tflite` because a head
  /// has no `cls.output.weight` to be recognised by, so the caller is the only
  /// thing that can say which head it means.
  final String? filename;

  /// Which shape to drive.
  ///
  /// [SystemOneShape.unknown] is a real state, not a default to be papered over:
  /// a GGUF's shape cannot be known until it is loaded, and a window that picked
  /// one anyway would send a body the endpoint refuses. When it is unknown the
  /// window asks the server and shows what it found.
  final SystemOneShape shape;

  /// Embedding models offered as a source of a feature vector.
  ///
  /// Filenames, not `AiModel`s, so that a layout test does not have to stand up
  /// the catalogue. The window does **not** embed with them in this version —
  /// see the note on the vector panel.
  final List<String> embedders;

  /// What the head wants, when the caller already knows.
  ///
  /// **A constructor argument and not only something this screen fetches**, for
  /// two reasons and the second is the one that decided it. The first is that a
  /// card which has already screened a file can hand the answer over and the
  /// window can draw its panels on the first frame instead of after a round
  /// trip. The second is that a layout test for the head panels has no server to
  /// ask — a fake `baseUrl` fails the probe, the contract stays null, and the
  /// panels correctly do not render, which reads as "the panel is missing".
  ///
  /// The window re-probes anyway, and overwrites this. It is a starting value,
  /// not an authority.
  final HeadContract? headContract;

  /// Where the server is, and what to authenticate with.
  ///
  /// Constructor arguments with the production values as defaults rather than
  /// `Get.find` buried in the state, for the reason the `.tflite` console
  /// documents: `ServerController` reads `HiveService`, `InferenceService` and
  /// `AppLogService` in its field initialisers, so testing "does the logits
  /// table overflow at 360 dp" would otherwise become a test of the dependency
  /// container.
  final String? baseUrl;
  final Map<String, String> authHeaders;

  @override
  State<SystemOneConsole> createState() => _SystemOneConsoleState();
}

class _SystemOneConsoleState extends State<SystemOneConsole> {
  // Text controllers are disposed by hand rather than left to the framework,
  // because this state outlives several `setState`s and a controller recreated
  // on a rebuild loses the cursor.
  final _state = TextEditingController();
  final _question = TextEditingController();
  final _vector = TextEditingController();
  final _instruction = TextEditingController();

  /// The model the app currently has loaded, for the header.
  ///
  /// Read from the server and not from `InferenceService`, so that what the
  /// window says is loaded is what the endpoint would act on. A window that read
  /// a different source and disagreed with the server is the "erro que se
  /// apresenta como outra coisa" this repo keeps paying for.
  String _loadedName = '';
  String _loadedRuntime = '';

  /// A head needs a vector; a decision model needs text. `unknown` is treated as
  /// the decision shape **only** after the server has told us something — see
  /// [_resolvedShape], which is null until then.
  SystemOneShape? _resolvedShape;

  SystemOneOptions _options = SystemOneOptions.starter;
  SystemOneLabels _labels = SystemOneLabels.starter;

  FeatureVector? _parsedVector;
  String? _vectorProblem;

  SystemOneResult? _result;

  /// A short, positive report of something the screen did on purpose. Separate
  /// from [_error] because an unload that worked is not an error, and putting it
  /// in the red box would teach the user that the app is broken when it is not.
  String? _notice;
  String? _error;
  bool _busy = false;
  bool _serverUp = false;
  String _base = '';

  /// What the head says it wants. Null means the head is not loaded or its
  /// shape could not be read, which is **not** the same as "any length will do".
  HeadContract? _head;

  /// The auxiliary inputs, keyed by the tensor name the file declares.
  final Map<String, FeatureVector> _auxiliary = {};

  /// The raw text of each auxiliary field, so a half-typed value is not thrown
  /// away on every keystroke by a parse that cannot read it yet.
  final Map<String, TextEditingController> _auxControllers = {};

  int? get _wantedFeatures => _head?.featureCount;

  @override
  void initState() {
    super.initState();
    final given = widget.headContract;
    if (given != null) {
      _head = given;
      for (final aux in given.auxiliary) {
        _auxControllers.putIfAbsent(aux.name, TextEditingController.new);
      }
    }
    unawaited(_probe());
  }

  @override
  void dispose() {
    _state.dispose();
    _question.dispose();
    _vector.dispose();
    _instruction.dispose();
    for (final c in _auxControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The shape actually in play.
  ///
  /// A constructor argument wins, because the card the user tapped named it. A
  /// `.tflite` is always a head — the extension settles it with nothing loaded —
  /// and a GGUF is asked for, because the difference between "has a head" and
  /// "answers with a letter" is only visible after a load.
  SystemOneShape? get _shapeOrNull {
    if (widget.shape != SystemOneShape.unknown) return widget.shape;
    return _resolvedShape;
  }

  /// The shared transport. **No `throwOnError`** — the opposite of
  /// `LitertHeadConsole`, and deliberately: a `/v1/classify` 422 carries the
  /// decision model's own text, and on this screen that text *is* the answer. A
  /// refusal the user cannot read is a blank panel where the result should be.
  late final ApiConsoleClient _client = ApiConsoleClient(
    baseUrl: _base,
    authHeaders: widget.authHeaders,
    authResolver: _liveAuth,
  );

  /// The key as the controller holds it **now**.
  ///
  /// Resolved per request, not once: a console opened before the key was turned
  /// on sent no `Authorization` at all, and when the key was later enabled every
  /// call came back 401 with nothing else on screen changing. The symptom pointed
  /// at the server; the cause was one missing header in the caller.
  Map<String, String> _liveAuth() {
    final server = _server;
    if (server == null) return const {};
    return localApiHeaders(
      useApiKey: server.useApiKey.value,
      apiKey: server.apiKey.value,
    );
  }

  ServerController? get _server => Get.isRegistered<ServerController>()
      ? Get.find<ServerController>()
      : null;

  Future<void> _probe() async {
    final url = widget.baseUrl ?? _server?.baseUrl ?? '';
    if (url.isEmpty) {
      setState(() => _error = 'soc_no_address'.tr);
      return;
    }
    setState(() {
      _base = url;
      _serverUp = true;
    });
    // **Three probes, three independent failures.** The rule the sibling console
    // established: a poll that another one cannot silence is what makes a blank
    // panel read as "the phone has not answered yet".
    //
    // Three calls and not one because the three sources do not overlap, and each
    // knows something the other two do not:
    //
    //   /v1/models/local         -> the GGUF's name and runtime
    //   /v1/server/capabilities  -> whether that GGUF classifies (the ONLY place)
    //   /v1/litert/status        -> the .tflite, a different runtime entirely
    //
    // The `.tflite` probe used to be conditional on the card having named a file,
    // so a window opened from the server screen never asked about the LiteRT
    // runtime at all — and `/v1/models/local` reports a **GGUF-only** `loaded`, so
    // with a head loaded and no GGUF the window said "nothing loaded". That is a
    // falsehood, and the head's own contract was on the next screen.
    await _deviceState();
    if (mounted && _needsHead) await _headContract();
  }

  /// Whether the head probe is worth making.
  bool get _needsHead =>
      widget.filename != null ||
      _device.hasTflite ||
      _shapeOrNull == SystemOneShape.tfliteHead;

  /// What the three endpoints said, which is the only place a `.tflite` shows up.
  DeviceState _device = const DeviceState();

  /// The `.tflite` to name, which may be the one that is loaded rather than the
  /// one the card named.
  String? _headFilename;

  /// What the phone has loaded, across all three runtimes.

  Future<void> _deviceState() async {
    Map<String, dynamic>? local;
    Map<String, dynamic>? caps;
    Map<String, dynamic>? litert;
    final failures = <String>[];

    // **Three `try`s, not one.** A single try would discard the two answers
    // that did arrive because the third one failed, and the window would go on
    // saying "nothing loaded" because the LiteRT probe refused.
    Future<void> probe(
      String what,
      String path,
      void Function(Map<String, dynamic>) into,
    ) async {
      try {
        into(await _request('GET', path));
      } on Object catch (e) {
        // Written, not swallowed: a poll that fails in silence is what makes a
        // blank panel read as "the phone has not answered yet".
        failures.add('$what: $e');
      }
    }

    await probe('soc_local_models'.tr, '/v1/models/local', (j) => local = j);
    await probe('capabilities', '/v1/server/capabilities', (j) => caps = j);
    await probe('litert status', '/v1/litert/status', (j) => litert = j);
    if (!mounted) return;

    final device = DeviceState.fromResponses(
      local: local,
      capabilities: caps,
      litertStatus: litert,
    );
    setState(() {
      _device = device;
      _loadedName = device.ggufName;
      _loadedRuntime = device.ggufRuntime;
      _resolvedShape = resolveSystemOneShape(device, given: widget.shape);
      _headFilename =
          resolveSystemOneHeadFilename(device, fromCard: widget.filename);
      _error = failures.isEmpty
          ? null
          : preencher(
              'soc_could_not_read',
              {'f': failures.map((f) => f.split(':').first).join(', ')});
    });
  }

  /// What the head wants, read from what the server reports about it.
  ///
  /// **Status first, screen as the fallback.** `GET /v1/litert/status` carries a
  /// `head` the server has already analysed — the feature tensor named, the
  /// auxiliaries listed, the class count known — so it is one call instead of
  /// two and it is the richer of the two. `POST /v1/litert/screen` works without
  /// the head being loaded, which is the case where status answers `loaded: null`
  /// and the user needs to be told to load it.
  ///
  /// The first version of this parsed the screen response by looking for a
  /// `signature` **object** with `inputs` in it. On the A72 the response is a
  /// **`signatures` array**, and the parse silently found nothing: the window
  /// reported no wanted count and would have let the user paste four numbers
  /// into a head that wants 1024. Measured on the device, not reasoned about.
  Future<void> _headContract() async {
    final name = _headFilename;
    if (name == null) return;
    HeadContract? contract;
    try {
      final status = await _request('GET', '/v1/litert/status');
      contract = HeadContract.fromStatus(status);
    } on Object catch (e) {
      // Written, not swallowed: a poll that fails in silence is what makes a
      // panel look like the device has not answered yet.
      if (mounted) setState(() => _error = 'status: $e');
      return;
    }
    if (contract == null) {
      // The head is not loaded. That is a state with a way out, and the message
      // names the endpoint rather than leaving the user to work it out.
      try {
        final screen = await _request(
          'POST',
          '/v1/litert/screen',
          body: {'filename': name},
        );
        contract = HeadContract.fromScreen(screen);
      } on Object catch (e) {
        if (mounted) {
          setState(() => _error =
              preencher('soc_screen_failed', {'n': name, 'e': e.toString()}));
        }
        return;
      }
    }
    if (contract == null) {
      // **Only** say "I could not read what it wants" when there is nothing to
      // fall back on. The first version said it unconditionally, so a window
      // opened with a contract already in hand — and whose *re-probe* failed,
      // which happens whenever the server is not up yet — showed a red panel
      // denying a thing it was displaying correctly one line above. The error
      // that presents itself as a different error.
      if (mounted) {
        setState(() => _error = _head == null
            ? 'Could not read what $name wants. Load it first: POST '
                '/v1/litert/load with "accept_risk": true, then re-probe.'
            : 'soc_reprobe_failed'.tr);
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _head = contract;
      _error = null;
    });
    // One controller per declared auxiliary, created once. A controller rebuilt
    // on every `setState` loses the cursor, which on this screen is every
    // keystroke.
    for (final aux in contract.auxiliary) {
      _auxControllers.putIfAbsent(aux.name, TextEditingController.new);
    }
  }

  /// One request, returning the decoded body **and** its status.
  ///
  /// The status comes back rather than being thrown, because for this window a
  /// refusal is a result: `/v1/classify` answers 422 with the model's own text
  /// for exactly the case where a decision model wrote prose, and that text is
  /// the only way to see what happened. Throwing it away as a transport error
  /// leaves a panel blank where the answer should be.
  ///
  /// **The method is a parameter and not implied by the helper name** — and that
  /// rule now lives in [ApiConsoleClient], shared with the `.tflite` console,
  /// because it came from a bug in *that* one: it had a `_post` and called it for
  /// `/v1/litert/status`, which is `GET` only. The route check is
  /// `request.method == 'GET'`, so the `POST` fell through to the 404 arm and the
  /// console showed a healthy probe next to every status panel blank. Measured on
  /// the A72, and it looked exactly like "the server is up and the head is not
  /// loaded yet".
  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic> body = const {},
    Duration timeout = const Duration(seconds: 90),
  }) =>
      _client.request(method, path, body: body, timeout: timeout);

  void _reparseVector() {
    final parsed = FeatureVector.parse(_vector.text);
    setState(() {
      _parsedVector = parsed == null
          ? null
          : FeatureVector(
              parsed.values,
              source: parsed.source,
              expectedCount: _wantedFeatures,
            );
      _vectorProblem = _vector.text.trim().isEmpty
          ? null
          : (parsed == null
              ? 'Not a list of numbers.'
              : FeatureVector(
                  parsed.values,
                  expectedCount: _wantedFeatures,
                ).problem);
    });
  }

  /// Run the decision.
  Future<void> _runDecision() async {
    if (_busy) return;
    final options = _options;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _result = null;
    });
    try {
      final json = await _request(
        'POST',
        '/v1/classify',
        body: const SystemOneResult().decisionBody(
          state: _state.text.trim(),
          question: _question.text,
          options: options,
          instruction: _instruction.text,
        ),
      );
      _show(json, SystemOneShape.decision);
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'classify: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Run the head.
  Future<void> _runHead() async {
    if (_busy) return;
    final vector = _parsedVector;
    final problem = vector?.problem;
    if (vector == null || problem != null) {
      setState(() => _error = problem ?? 'soc_no_feature_vector'.tr);
      return;
    }
    final name = _headFilename;
    if (name == null) {
      setState(() => _error = 'No .tflite named.');
      return;
    }
    // Every auxiliary the user filled, and only those. An unfilled one is left
    // out so the endpoint names it, which is a better outcome than a body with
    // zeros in it and a confident wrong answer on the other side.
    final auxiliary = <String, FeatureVector>{
      for (final e in _auxiliary.entries)
        if (e.value.problem == null) e.key: e.value,
    };
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _result = null;
    });
    try {
      final json = await _request(
        'POST',
        '/v1/classify',
        body: const SystemOneResult().tfliteBody(
          filename: name,
          features: vector,
          auxiliary: auxiliary,
        ),
      );
      _show(json, SystemOneShape.tfliteHead, callerLabels: _labels.toJson());
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'classify: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Free the head, over the API, and say what was actually freed.
  ///
  /// **This is what makes the window's "nothing loaded" state reachable.** Until
  /// `POST /v1/litert/unload` existed there was no way to get there: the LiteRT
  /// routes were `screen`, `load`, `status` and `run`, so a head could only be
  /// replaced by loading another one, and a test window that cannot be emptied is
  /// a test window that keeps testing whatever it was left holding.
  ///
  /// The `409` is the interesting case and it is shown, not swallowed: a run in
  /// flight means the graph is being read, and freeing it there would crash in
  /// native code with no Dart frame to point at. The service owns that guard,
  /// not this screen.
  Future<void> _unloadHead() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final json = await _request('POST', '/v1/litert/unload');
      final unloaded = json['unloaded'] == true;
      final name = '${json['filename'] ?? ''}';
      setState(() {
        // The head and its contract go together. Keeping a contract for a model
        // that is no longer loaded is how a window ends up describing a file
        // that is not there — the panels would say "wants 1024 numbers" about
        // nothing.
        _head = null;
        for (final c in _auxControllers.values) {
          c.clear();
        }
        _auxiliary.clear();
        _parsedVector = null;
        _result = SystemOneResult(
          model: name,
          failure: null,
        );
        _notice = unloaded
            ? preencher('soc_free_unloaded', {'n': name})
            : 'soc_nothing_freed'.tr;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'unload: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(
    Map<String, dynamic> json,
    SystemOneShape shape, {
    List<String> callerLabels = const [],
  }) {
    if (!mounted) return;
    final status = json['__status'];
    setState(() {
      _result = SystemOneResult(shape: shape).fromClassify(
        json,
        status: status is int ? status : 200,
        callerLabels: callerLabels,
      );
    });
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final field = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    final shape = _shapeOrNull;

    return Material(
      // **One `Material`, at the root.** `ChoiceChip`, `TextField` and `InkWell`
      // each call `debugCheckHasMaterial` on themselves, and this screen is shown
      // with `Get.to`, where the `Scaffold` that normally supplies it is not in
      // the path. The sibling console found this twice — `ChoiceChip` in the app
      // log, `TextField` only in a screenshot — and fixed each site as it
      // appeared. A rule per widget is a rule that has to be re-audited every
      // time a panel is added; this is the one fix for all of them.
      type: MaterialType.transparency,
      child: Container(
        color: isDark ? const Color(0xFF0F0F11) : const Color(0xFFF7F7F9),
        child: SafeArea(
          child: Column(
            children: [
              _header(context, shape),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    if (_error != null) _errorCard(_error!),
                    if (_notice != null) _noticeCard(_notice!),
                    if (shape == null)
                      _card(
                        card,
                        field,
                        'soc_which_shape'.tr,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'soc_gguf_answers'.tr,
                              style: GoogleFonts.inter(
                                  fontSize: 12, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _loadedName.isEmpty
                                  ? 'soc_nothing_loaded'.tr: '$_loadedName'
                                      '${_loadedRuntime.isEmpty ? '' : ' ($_loadedRuntime)'}',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                            if (_loadedName.isEmpty) ...[
                              const SizedBox(height: 10),
                              // **Names the way out, and it goes after the state
                              // rather than in the middle of it.** The first
                              // version put it between "The server said:" and
                              // "nothing loaded", which cut one sentence in half
                              // with a paragraph about something else. A dead end
                              // that says only "load something" is a message that
                              // makes the user go looking, and this screen is
                              // reached from a place where loading a model is
                              // three screens away.
                              Text(
                                'soc_load_one_and_probe'.tr,
                                style: GoogleFonts.inter(
                                    fontSize: 11, color: AppColors.info),
                              ),
                            ],
                          ],
                        ),
                      ),
                    if (shape == SystemOneShape.tfliteHead)
                      ..._headPanels(card, field),
                    if (shape == SystemOneShape.decision)
                      ..._decisionPanels(card, field),
                    if (shape == SystemOneShape.ggufHead)
                      _card(
                        card,
                        field,
                        'soc_is_head'.tr,
                        Text(
                          'soc_classification_head_console'.tr,
                          style: GoogleFonts.inter(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ),
                    if (_result != null) _resultCard(card, field, _result!),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, SystemOneShape? shape) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('soc_system_one_test_b'.tr,
                    style: GoogleFonts.inter(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  _shapeLabel(shape),
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                if (!_serverUp)
                  Text('soc_server_no_answer'.tr,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: AppColors.error)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'close'.tr,
            onPressed: () {
              if (widget.onClose != null) {
                widget.onClose!();
              } else {
                Get.back();
              }
            },
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }

  /// The shape, in words, and the word for "not known yet" is deliberate.
  ///
  /// Every branch names what goes **in** and what comes **out**, because a user
  /// who does not know which of the two bodies this window is about to send is
  /// the user who is about to paste a 1024-number vector into a decision model.
  String _shapeLabel(SystemOneShape? shape) {
    final head = switch (shape) {
      SystemOneShape.decision => 'decision — text in, one letter out',
      SystemOneShape.tfliteHead => 'head — feature vector in, logits out',
      SystemOneShape.ggufHead =>
        'soc_head_labels'.tr,
      _ => 'soc_not_decided'.tr,
    };
    final bits = <String>[
      head,
      // **The resolved name, not the card's.** A window opened from the server
      // screen has no card, and the head it is about to drive is the one that is
      // loaded — so showing the card's name here would print an empty string
      // next to a filename the request is about to use.
      if (shape == SystemOneShape.tfliteHead && _headFilename != null)
        _headFilename!,
      if (shape == SystemOneShape.decision && _loadedName.isNotEmpty)
        preencher('soc_loaded_name', {'l': _loadedName}),
      if (shape == SystemOneShape.tfliteHead && _wantedFeatures != null)
        'wants $_wantedFeatures numbers',
    ];
    return bits.join(' · ');
  }

  List<Widget> _decisionPanels(Color card, Color field) {
    return [
      _card(
        card,
        field,
        'soc_state'.tr,
        TextField(
          controller: _state,
          maxLines: 4,
          minLines: 2,
          style: GoogleFonts.inter(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'checkout devolvendo 500 desde 9h',
            hintStyle:
                GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
            border: InputBorder.none,
          ),
        ),
        note:
            'soc_json_envelope'.tr,
      ),
      _card(
        card,
        field,
        'soc_question'.tr,
        TextField(
          controller: _question,
          style: GoogleFonts.inter(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'soc_which_area'.tr,
            hintStyle:
                GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
            border: InputBorder.none,
          ),
        ),
      ),
      _optionsCard(card, field),
      _card(
        card,
        field,
        'soc_system'.tr,
        TextField(
          controller: _instruction,
          maxLines: 3,
          minLines: 1,
          style: GoogleFonts.inter(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'soc_empty_uses_default'.tr,
            hintStyle:
                GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
            border: InputBorder.none,
          ),
        ),
        note:
            'soc_default_ok'.tr,
      ),
      _actions(() => _runDecision(), 'soc_ask_for_the_letter'.tr),
    ];
  }

  List<Widget> _headPanels(Color card, Color field) {
    final vector = _parsedVector;
    final head = _head;
    // The vector's own problem is shown in its own panel below, right under the
    // field that produced it. Repeating it here would put the same sentence
    // twice on one screen, which is how a warning stops being read.
    return [
      _card(
        card,
        field,
        'soc_the_feature_vector'.tr,
        TextField(
          controller: _vector,
          maxLines: 4,
          minLines: 2,
          onChanged: (_) => _reparseVector(),
          style: GoogleFonts.inter(fontSize: 12),
          decoration: InputDecoration(
            hintText: _wantedFeatures == null
                ? 'numbers, separated by spaces or commas'
                : '$_wantedFeatures numbers, separated by spaces or commas',
            hintStyle:
                GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
            border: InputBorder.none,
          ),
        ),
        note:
            'A head wants ${_wantedFeatures ?? 'an unknown number of'} floats '
            'and nobody types that. One comes out of POST /v1/embeddings, using '
            "one of the app's embedding encoders — paste it here."
            '${widget.embedders.isEmpty ? '' : ' In the catalogue: ${widget.embedders.take(3).join(', ')}.'}',
        trailing: vector == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${vector.length} numbers',
                      style: GoogleFonts.inter(
                          fontSize: 11, color: AppColors.textSecondary)),
                  const SizedBox(width: 8),
                  _copy(vector.values.join(', ')),
                ],
              ),
      ),
      if (_vectorProblem != null) _problem(_vectorProblem!),
      ..._auxiliaryPanels(card, field),
      _labelsCard(card, field),
      _actions(() => _runHead(), 'soc_run_head'.tr),
      // Only where there is something to free. A button that unloads nothing is
      // a button whose only effect is to say so.
      if (head != null) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : () => _unloadHead(),
            icon: const Icon(Icons.layers_clear_outlined, size: 16),
            label: Text('soc_free_head'.tr,
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.error)),
          ),
        ),
        Text(
          'soc_litert_unload'.tr,
          style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
        ),
      ],
    ];
  }

  /// One field per input the head declares beyond the feature vector.
  ///
  /// **This panel is the reason the window can drive the one `.tflite` head that
  /// exists.** The Laya act head takes `pooled_cls [1,1024]` *and* `feats
  /// [1,4]`, and the endpoint refuses a request that leaves `feats` out:
  ///
  /// > This head takes 1 input(s) beyond the feature vector … They are not
  /// > filled with zeros on purpose: a logit computed on invented features is a
  /// > number with no meaning.
  ///
  /// (measured on the A72, verbatim). Without a field for it the window could
  /// screen a real head, name its real tensors, and then be unable to ask it
  /// anything — which is a test window that cannot test.
  ///
  /// The count comes from the file, so the field says `feats [1,4]` and a
  /// four-number mistake is caught before the request instead of by it. Nothing
  /// here fills a value: an empty auxiliary is left out of the body and the
  /// endpoint's refusal is shown, which is the same rule the endpoint keeps and
  /// for the same reason.
  List<Widget> _auxiliaryPanels(Color card, Color field) {
    final head = _head;
    if (head == null || head.auxiliary.isEmpty) return const [];
    return [
      // **A head with no name is a hole in the screen, and it gets a line.**
      // It is reachable: this window is opened with no filename from the server
      // screen, and if the LiteRT probe fails — or no head is loaded — the
      // filename is null while the shape and the contract are both known. The
      // panels then draw a working head with nothing saying which file, and the
      // only way to find out is to press Run and be refused. A state the screen
      // can reach has to be a state the screen says.
      if (_headFilename == null)
        _card(
          card,
          field,
          'soc_no_tflite'.tr,
          Text(
            'soc_head_not_recognisable'.tr,
            style:
                GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      for (final aux in head.auxiliary)
        _card(
          card,
          field,
          '${aux.name} — the auxiliary this head also wants',
          Builder(builder: (context) {
            final controller = _auxControllers.putIfAbsent(
                aux.name, TextEditingController.new);
            return TextField(
              controller: controller,
              maxLines: 2,
              minLines: 1,
              onChanged: (v) => _setAuxiliary(aux.name, v, aux.count),
              style: GoogleFonts.jetBrainsMono(fontSize: 12),
              decoration: InputDecoration(
                hintText: aux.count == null
                    ? 'numbers'
                    : '${aux.count} numbers — the ones the host derived',
                hintStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 12, color: AppColors.textMuted),
                border: InputBorder.none,
              ),
            );
          }),
          note: aux.count == null
              ? 'soc_left_empty'.tr: 'soc_left_empty2'.tr,
        ),
    ];
  }

  void _setAuxiliary(String name, String text, int? expected) {
    final parsed = FeatureVector.parse(text);
    if (parsed == null) {
      _auxiliary.remove(name);
      return;
    }
    _auxiliary[name] = FeatureVector(
      parsed.values,
      source: name,
      expectedCount: expected,
    );
  }

  Widget _optionsCard(Color card, Color field) {
    final problem = _options.problem;
    return _card(
      card,
      field,
      'soc_options'.tr,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // `Wrap`, not a `Column` of `Row`s with fixed widths, and not a `Row`
          // of everything. The three paid-for overflows in this repo were all a
          // `Row` with nothing limiting it; here the label field is the only
          // elastic part and the letter and the delete button are fixed, so a
          // 360 dp screen with 2× text stacks instead of throwing.
          for (var i = 0; i < _options.items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(_options.items[i].letter,
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary)),
                  ),
                  Expanded(
                    child: Container(
                      color: field,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: TextField(
                        style: GoogleFonts.inter(fontSize: 13),
                        decoration:
                            const InputDecoration(border: InputBorder.none),
                        controller:
                            TextEditingController(text: _options.items[i].label)
                              ..selection = TextSelection.collapsed(
                                  offset: _options.items[i].label.length),
                        onChanged: (v) => _setOption(i, v),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'remove',
                    onPressed: () =>
                        setState(() => _options = _options.removeAt(i)),
                    icon: const Icon(Icons.close, size: 16),
                  ),
                ],
              ),
            ),
          _add(
              'add an option', () => setState(() => _options = _options.add())),
          if (problem != null) _problem(problem),
          const SizedBox(height: 6),
          Text(
              preencher('soc_what_will_send', {
                // **`toChoices()` devolve um mapa, e a linha mostra o mapa inteiro.**
                // `toString()` de um `Map` é `{A: bug, B: billing}` — sem aspas nas
                // chaves — e é isso que o painel mostra de propósito: a letra *e* o
                // rótulo que a pessoa escreveu. Reduzir para `keys.join(' ')`
                // deixaria só a letra, e o test que afirma esta linha passaria a
                // procurar um texto que não existe mais.
                'o': _options.toChoices().toString(),
              }),
              style:
                  GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _labelsCard(Color card, Color field) {
    final problem = _labels.problem;
    return _card(
      card,
      field,
      'soc_labels_hint'.tr +
          (_head?.classCount == null
              ? ''
              : preencher(
                  'soc_head_class_count', {'c': _head!.classCount.toString()})),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('soc_head_no_class_names'.tr,
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          for (var i = 0; i < _labels.items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 62,
                    child: Text('class $i',
                        style: GoogleFonts.inter(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ),
                  Expanded(
                    child: Container(
                      color: field,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: TextField(
                        style: GoogleFonts.inter(fontSize: 13),
                        decoration:
                            const InputDecoration(border: InputBorder.none),
                        controller:
                            TextEditingController(text: _labels.items[i])
                              ..selection = TextSelection.collapsed(
                                  offset: _labels.items[i].length),
                        onChanged: (v) => _setLabel(i, v),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'remove',
                    onPressed: () =>
                        setState(() => _labels = _labels.removeAt(i)),
                    icon: const Icon(Icons.close, size: 16),
                  ),
                ],
              ),
            ),
          _add('add a label',
              () => setState(() => _labels = _labels.addBlank())),
          if (problem != null) _problem(problem),
          if (_classMismatch != null) _problem(_classMismatch!),
          const SizedBox(height: 4),
          Text('soc_no_upper_limit'.tr,
              style:
                  GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  /// A count of labels that does not match the head, said out loud.
  ///
  /// **A warning, not a refusal.** The endpoint does not care — it never sees
  /// the labels — and the answer is still readable with three names over five
  /// logits: the top index is reported and the unnamed ones say "class 3". So
  /// blocking the run would be the app inventing a rule, which is the thing
  /// `SystemOneLabels` exists to avoid having done to the 24.
  String? get _classMismatch {
    final classes = _head?.classCount;
    if (classes == null || _labels.length == classes) return null;
    return preencher('soc_head_label_mismatch',
        {'c': classes.toString(), 'l': _labels.length.toString()});
  }

  void _setOption(int index, String label) {
    _options = _options.replace(
        index, SystemOneOption(_options.items[index].letter, label));
    setState(() {});
  }

  void _setLabel(int index, String label) {
    _labels = _labels.replace(index, label);
    setState(() {});
  }

  /// The card every panel in this window is built from.
  ///
  /// **A delegation, and the body it replaces was this widget.** Same margin, same
  /// radius, same padding, same `Row` with an `Expanded` title and a trailing
  /// slot, same 8 px gaps, same note styling — the local copy was a fork of
  /// [consoleCard] that had drifted nowhere. Keeping it meant two places to edit
  /// for one change, which is the reason the shell exists.
  ///
  /// The colours are passed in rather than looked up, because this window already
  /// resolved them and re-resolving per card would be a read per panel per
  /// rebuild. [ConsolePalette.explicit] takes the brightness from the card's own
  /// luminance rather than a second parameter that could contradict it.
  Widget _card(
    Color card,
    Color field,
    String title,
    Widget child, {
    String? note,
    Widget? trailing,
  }) {
    return consoleCard(
      palette: ConsolePalette.explicit(card, field),
      title: title,
      note: note,
      trailing: trailing,
      child: child,
    );
  }

  /// A refusal, in red. Delegates to the shared [consoleErrorCard] — the body
  /// it replaced was a fork of it, down to the border alpha.
  Widget _errorCard(String message) => consoleErrorCard(message);

  /// A confirmation, deliberately not the red card.
  ///
  /// The screen does three things on purpose — unloads a head, runs it, refuses a
  /// request — and putting all three in the same red box would make the app look
  /// broken every time it worked. This is the same reasoning as the endpoint
  /// answering `200` on a no-op unload: the difference between "I did something"
  /// and "something went wrong" belongs in how it is shown, not only in the code
  /// path that produced it.
  /// A confirmation, and **deliberately not** the red card: an unload that freed
  /// a head is not an error, and putting all three in one red box makes the
  /// app look broken every time it worked.
  Widget _noticeCard(String message) => consoleNoticeCard(message);

  Widget _problem(String message) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 15, color: AppColors.warning),
          const SizedBox(width: 6),
          Expanded(
            child: Text(message,
                style:
                    GoogleFonts.inter(fontSize: 11, color: AppColors.warning)),
          ),
        ],
      ),
    );
  }

  Widget _add(String label, VoidCallback onTap) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add, size: 16),
        label: Text(label,
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.primary)),
      ),
    );
  }

  Widget _copy(String value) {
    return IconButton(
      tooltip: 'soc_copy'.tr,
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: value));
      },
      icon: const Icon(Icons.copy, size: 15),
    );
  }

  /// The action row, in a `Wrap`.
  ///
  /// A `Row` here is the exact shape of the overflow this repo has already paid
  /// for three times, and this window's actions are English sentences next to
  /// each other with nothing limiting them. `Wrap` is also the right widget
  /// because they are alternatives, and stacking them says that in a way three
  /// side-by-side buttons do not.
  Widget _actions(VoidCallback onRun, String label) {
    return consoleActions(
      children: [
        FilledButton.icon(
          onPressed: _busy ? null : onRun,
          icon: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.play_arrow, size: 18),
          label: Text(_busy ? 'soc_run_now'.tr : label,
              style: GoogleFonts.inter(fontSize: 13)),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => unawaited(_probe()),
          icon: const Icon(Icons.refresh, size: 16),
          label: Text('re-probe', style: GoogleFonts.inter(fontSize: 13)),
        ),
      ],
    );
  }

  /// What came back, in the shape it came back in.
  Widget _resultCard(Color card, Color field, SystemOneResult r) {
    // A local, and not `r.raw!` inline, because Dart does not promote a nullable
    // **instance field** — only locals and final local getters do. `r.raw.trim()`
    // does not compile and `r.raw!.trim()` does, which is a distinction worth
    // having read once rather than re-discovering in a widget tree.
    final raw = r.raw?.trim() ?? '';
    return _card(
      card,
      field,
      r.isFailure ? 'soc_refused'.tr: 'soc_answer'.tr,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r.isFailure)
            Text(r.failure!,
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.error))
          else ...[
            Row(
              children: [
                if (r.letter != null) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(r.letter!,
                        style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary)),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(r.label ?? r.labelledTop ?? '(no label)',
                      style: GoogleFonts.inter(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            if (r.logits != null) ...[
              const SizedBox(height: 10),
              // The values, in a fixed-width block, sorted with the top first.
              // **Not a percentage and not a bar chart**: these are raw logits,
              // and turning them into a confidence is a softmax and a
              // temperature this endpoint does not have.
              Container(
                width: double.infinity,
                color: field,
                padding: const EdgeInsets.all(10),
                child: Text(
                  formatLogits(r.logits!, r),
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 11, color: AppColors.textPrimary),
                ),
              ),
            ],
            if (raw.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(preencher('soc_the_model_said', {'r': raw}),
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ],
          if (r.whyNoScore != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 14, color: AppColors.info),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                      preencher('soc_no_confidence', {'w': r.whyNoScore ?? ''}),
                      style: GoogleFonts.inter(
                          fontSize: 11, color: AppColors.info)),
                ),
              ],
            ),
          ],
          if (r.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final n in r.notes)
              Text(n,
                  style: GoogleFonts.inter(
                      fontSize: 11, color: AppColors.textMuted)),
          ],
          // **What the model was given, and the last thing on the card on
          // purpose.** It is the answer to the question a person asks when a
          // classifier is confident and the input was a number they typed, so it
          // goes below the letter and the logits rather than above them — up
          // there it competes with the result, and the result is what was asked
          // for. The field was on `SystemOneResult` from the day the window was
          // written and no endpoint filled it, so this line used to be
          // unreachable.
          if (r.featureSource != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.input_rounded,
                    size: 14, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(r.featureSource!,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: AppColors.textMuted)),
                ),
              ],
            ),
          ],
          if (r.model.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(preencher('soc_model_label', {'m': r.model ?? ''}),
                style: GoogleFonts.inter(
                    fontSize: 11, color: AppColors.textMuted)),
          ],
        ],
      ),
    );
  }
}
