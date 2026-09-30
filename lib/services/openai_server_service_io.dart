import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:path_provider/path_provider.dart';

import '../controllers/model_controller.dart';
import '../controllers/settings_controller.dart';
import '../core/constants.dart';
import '../models/ai_model.dart';
import '../utils/logistic.dart';
import '../utils/server_auth.dart';
import 'encoder_settings_service.dart';
import 'inference_service.dart';

class OpenAiServerService {
  HttpServer? _server;
  bool _busy = false;
  String? _apiKey;
  void Function(String)? _onLog;

  bool get isRunning => _server != null;
  String? get localUrl {
    final port = _server?.port;
    if (port == null) return null;
    final host = _lastReachableAddress;
    return 'http://${host ?? 'localhost'}:$port';
  }

  String? _lastReachableAddress;

  static const int maxBodyBytes = 18 * 1024 * 1024;
  static const int maxDecodedAttachmentBytes = 12 * 1024 * 1024;

  Future<void> start({
    int port = AppConstants.defaultServerPort,
    String? apiKey,
    void Function(String)? onLog,
  }) async {
    if (_server != null) return;
    _apiKey = apiKey?.trim();
    _onLog = onLog;
    _lastReachableAddress = await _reachableIpv4Address();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _onLog?.call('Server listening on ${localUrl ?? 'http://localhost:$port'}');
    unawaited(_serve(_server!));
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
    _busy = false;
    _onLog?.call('Server stopped');
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handle(request));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      _addCorsHeaders(request.response);
      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }

      final path = request.uri.path;
      if (request.method == 'GET' && path == '/health') {
        await _json(request, {'status': 'ok'});
        return;
      }

      if (path.startsWith('/v1/') && !_isAuthorized(request)) {
        await _json(request, {'error': 'Unauthorized'},
            status: HttpStatus.unauthorized);
        return;
      }

      if (request.method == 'GET' && path == '/v1/models') {
        await _handleModels(request);
        return;
      }
      // Local model management. Deliberately *not* folded into /v1/models:
      // that one is the OpenAI contract, where `data` is the models the
      // endpoint can serve, and a client that finds 46 catalogue entries there
      // will try to use them all and get a 404 on the first generation. The
      // OpenAI shape stays exactly as it was.
      if (request.method == 'GET' && path == '/v1/models/local') {
        await _handleLocalModels(request);
        return;
      }
      if (request.method == 'POST' && path == '/v1/models/download') {
        await _handleModelDownload(request);
        return;
      }
      if (request.method == 'POST' && path == '/v1/models/load') {
        await _handleModelLoad(request);
        return;
      }
      if (request.method == 'POST' && path == '/v1/models/unload') {
        await _handleModelUnload(request);
        return;
      }
      if (request.method == 'GET' && path == '/v1/server/capabilities') {
        await _handleCapabilities(request);
        return;
      }
      if (request.method == 'POST' && path == '/v1/chat/completions') {
        await _handleChatCompletions(request);
        return;
      }
      if (request.method == 'POST' && path == '/v1/completions') {
        await _handleCompletions(request);
        return;
      }
      if (request.method == 'POST' && path == '/v1/embeddings') {
        await _handleEmbeddings(request);
        return;
      }
      if (request.method == 'POST' && path == '/v1/rerank') {
        await _handleRerank(request);
        return;
      }
      if (request.method == 'POST' && path == '/v1/classify') {
        await _handleClassify(request);
        return;
      }

      await _json(request, {'error': 'Not found'}, status: HttpStatus.notFound);
    } catch (error) {
      _onLog?.call('Request failed: $error');
      try {
        await _json(
          request,
          {'error': 'Internal server error', 'message': '$error'},
          status: HttpStatus.internalServerError,
        );
      } catch (_) {
        await request.response.close();
      }
    }
  }

  /// Whether this request may proceed.
  ///
  /// An absent key means the requirement is off, and the server says so rather
  /// than refusing everything — the toggle in Settings is a real choice, not a
  /// broken state. It is also a choice the UI now asks about, because the
  /// server binds all interfaces and these endpoints can write to the device.
  ///
  /// The comparison is constant-time and the scheme match is case-insensitive,
  /// both in `server_auth.dart` with the reasoning there. The short form here
  /// (`header.trim() == 'Bearer $key'`) is what this replaced.
  bool _isAuthorized(HttpRequest request) {
    final key = _apiKey;
    if (key == null || key.isEmpty) return true;
    return authorizationMatches(
      request.headers.value(HttpHeaders.authorizationHeader),
      key,
    );
  }

  Future<void> _handleModels(HttpRequest request) async {
    final inference = Get.find<InferenceService>();
    final hasModel = inference.isModelLoaded.value;
    await _json(request, {
      'object': 'list',
      'data': [
        if (hasModel)
          {
            'id': inference.loadedModelName.value,
            'object': 'model',
            'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'owned_by': 'local',
          }
      ],
    });
  }

  // ── Local model management ───────────────────────────────────────────
  //
  // The four endpoints below exist because driving the app by hand is the
  // slow part of measuring it. Curating a catalogue means downloading nine
  // models, loading each one, and sending the same prompt to each — and on a
  // phone whose touchscreen does not respond that is nine rounds of `adb`
  // taps against a panel that fails intermittently, where a mistyped
  // coordinate is indistinguishable from a successful one. Driving the same
  // sequence over HTTP makes each step confirm itself.
  //
  // Two decisions worth stating, because both were the other way round first:
  //
  // **Nothing here blocks.** A 2 GB download is minutes and a model load on a
  // weak phone measured 25 s of first token and 60 s of prefill budget. An
  // HTTP request that hangs that long reads to the client as a timeout, and a
  // timeout is indistinguishable from a crash — so the operation is started,
  // answered 202, and watched on `GET /v1/models/local`. The alternative, a
  // synchronous load, works right up until the phone is the slow one.
  //
  // **Refused, never queued.** Loading while a generation is running would
  // reach the engine as two things at once, and the symptom of that is a
  // model that answers with garbage rather than an error. So a conflict is a
  // 409 with the reason, and the client decides.

  /// One row of the inventory. Built from a catalogue entry plus whatever the
  /// download and inference services currently know about it.
  Map<String, dynamic> _localModelRow(
    AiModel model,
    Set<String> downloaded,
    InferenceService inference,
    ModelController controller,
  ) {
    final filename = model.filename as String;
    final dp = controller.getDownloadProgress(filename);
    final isDownloaded = downloaded.contains(filename);
    final isLoaded = inference.isModelLoaded.value &&
        inference.loadedModelName.value == filename;

    // One word, not a set of booleans. A client polling this has to branch on
    // a combination otherwise, and the combinations are where the bugs are:
    // "downloaded but not idle" and "downloading and loaded at once" are both
    // states a boolean soup describes ambiguously.
    final state = isLoaded
        ? 'loaded'
        : dp != null
            ? (dp.isPaused.value ? 'paused' : 'downloading')
            : isDownloaded
                ? 'downloaded'
                : 'available';

    return {
      'filename': filename,
      'name': model.name,
      'size': model.size,
      'runtime': model.runtime,
      if (model.needsMmproj) 'needs_projector': true,
      'state': state,
      'downloaded': isDownloaded,
      'is_custom': model.isCustom,
      if (model.isBenchmark) 'is_benchmark': true,
      if (dp != null) ...{
        'downloaded_bytes': dp.downloadedBytes.value,
        'total_bytes': dp.totalBytes.value,
        'progress': (dp.progress.value * 100).clamp(0, 100).toStringAsFixed(1),
        'bytes_per_second': dp.bytesPerSecond.value.round(),
      },
    };
  }

  Future<void> _handleLocalModels(HttpRequest request) async {
    final inference = Get.find<InferenceService>();
    final controller = Get.find<ModelController>();
    final downloaded = controller.downloadedFiles.toSet();

    // Catalogue and custom entries in one list, because "what can I load" is
    // one question and the answer is the union. Custom entries (imported by
    // URL, or added from Hugging Face search) are not in `availableModels`, and
    // a load endpoint that refused them would be refusing half the models on
    // the device.
    final rows = <Map<String, dynamic>>[
      for (final m in controller.availableModels)
        _localModelRow(m, downloaded, inference, controller),
      for (final m in controller.customModels)
        _localModelRow(m, downloaded, inference, controller),
    ];
    rows.sort((a, b) => (a['state'] == b['state']
        ? (a['filename'] as String).compareTo(b['filename'] as String)
        : _stateRank(a['state'] as String).compareTo(_stateRank(b['state'] as String))));

    await _json(request, {
      'object': 'list',
      // The loaded model, with the backend it is *actually* on.
      //
      // `loadedBackend` rather than the tier that was asked for, and the
      // difference is the whole point: LiteRT falls back NPU → GPU → CPU
      // natively, so a request for a tier and the tier that ran are two
      // different things. Reporting the request would be reporting a wish.
      'loaded': inference.isModelLoaded.value
          ? {
              'filename': inference.loadedModelName.value,
              'runtime': inference.loadedModelRuntime.value,
              // The real one, not the requested one.
              'backend': inference.loadedBackend.value,
              'gpu': inference.gpuName.value,
              'gpu_layers': inference.gpuLayersUsed.value,
              'accelerated': inference.isGpuAccelerated.value,
              'vision': inference.isVisionLoaded.value,
            }
          : null,
      'loading': inference.modelLoadProgress.value > 0 &&
              inference.modelLoadProgress.value < 1
          ? inference.modelLoadProgress.value
          : null,
      'transfers_in_progress': controller.activeDownloads.length,
      'data': rows,
    });
  }

  /// Loaded first, then mid-transfer, then downloaded, then merely available —
  /// so a client listing "what can I use right now" can stop reading at the
  /// first group it cares about.
  static int _stateRank(String state) => switch (state) {
        'loaded' => 0,
        'downloading' || 'paused' => 1,
        'downloaded' => 2,
        _ => 3,
      };

  /// `_readJson` but a body problem is `null` rather than an exception.
  ///
  /// The existing reader throws on an empty or non-object body, which is right
  /// for the seven generation handlers that cannot do anything without one.
  /// These three can: an empty body means "you forgot `filename`", and the
  /// answer to that is a 400 with a sentence, not a 500 from a parse error
  /// three frames down. The first version of this used `_readJson` directly
  /// and the device answered `500` to `curl -X POST` with no body — measured,
  /// not predicted.
  Future<Map<String, dynamic>?> _readJsonOrNull(HttpRequest request) async {
    try {
      return await _readJson(request);
    } on Object {
      return null;
    }
  }

  /// Find a model by filename across catalogue and custom entries.
  ///
  /// Returns null rather than throwing so both callers can answer with a 404
  /// that lists what does exist. That list is the point: a wrong filename
  /// otherwise fails at download time with nothing to compare against, which
  /// is the same failure the catalogue's URL rule exists to prevent.
  AiModel? _findModel(ModelController controller, String filename) {
    for (final m in controller.availableModels) {
      if (m.filename == filename) return m;
    }
    for (final m in controller.customModels) {
      if (m.filename == filename) return m;
    }
    return null;
  }

  List<String> _knownFilenames(ModelController controller) => [
        ...controller.availableModels.map((m) => m.filename),
        ...controller.customModels.map((m) => m.filename),
      ];

  Future<void> _handleModelDownload(HttpRequest request) async {
    final controller = Get.find<ModelController>();
    final body = await _readJsonOrNull(request);
    final filename = (body?['filename'] as String?)?.trim() ?? '';
    if (filename.isEmpty) {
      await _json(request, {
        'error': "Missing 'filename'. Expected one of the filenames from "
            'GET /v1/models/local.'
      }, status: HttpStatus.badRequest);
      return;
    }

    final model = _findModel(controller, filename);
    if (model == null) {
      await _json(request, {
        'error': 'No such model: $filename',
        'known': _knownFilenames(controller),
      }, status: HttpStatus.notFound);
      return;
    }
    if (controller.downloadedFiles.contains(filename)) {
      await _json(request, {
        'error': 'Already downloaded',
        'state': 'downloaded',
        'filename': filename,
      }, status: HttpStatus.conflict);
      return;
    }
    if (controller.getDownloadProgress(filename) != null) {
      await _json(request, {
        'error': 'Download already in progress',
        'state': 'downloading',
        'filename': filename,
      }, status: HttpStatus.conflict);
      return;
    }

    // Started, not awaited. See the class-level note on why nothing here
    // blocks: the 202 means "accepted", and the progress lives on
    // GET /v1/models/local. `unawaited` is explicit so a future reader does not
    // take the missing `await` for an oversight and "fix" it into a request
    // that hangs for the length of a 2 GB download.
    // Mesma ordem das outras duas operações: resposta antes de começar.
    await _json(request, {
      'accepted': true,
      'filename': filename,
      'name': model.name,
      'size': model.size,
      'watch': 'GET /v1/models/local',
    }, status: HttpStatus.accepted);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    unawaited(controller.downloadModel(model));
  }

  Future<void> _handleModelLoad(HttpRequest request) async {
    final inference = Get.find<InferenceService>();
    final controller = Get.find<ModelController>();
    final body = await _readJsonOrNull(request);
    final filename = (body?['filename'] as String?)?.trim() ?? '';
    if (filename.isEmpty) {
      await _json(request, {
        'error': "Missing 'filename'. Expected one of the filenames from "
            'GET /v1/models/local.'
      }, status: HttpStatus.badRequest);
      return;
    }

    if (!controller.downloadedFiles.contains(filename)) {
      final known = _knownFilenames(controller);
      // Two different mistakes, and saying which one it is saves the caller a
      // round trip. Measured: with a single "Not downloaded" for both, a typo
      // in a filename and a model that simply has not been fetched yet look
      // identical, and the fix for one of them (download it) is nonsense for
      // the other (it does not exist).
      final exists = known.contains(filename);
      await _json(request, {
        'error': exists ? 'Not downloaded: $filename' : 'No such model: $filename',
        'known': known,
        'hint': exists
            ? 'POST /v1/models/download first, then poll GET /v1/models/local '
                'until its state is "downloaded".'
            : 'No catalogue entry has that filename, and no such file is on '
                'the device. A model imported from a URL appears under its file '
                'name on disk; compare against "known" above.',
      }, status: HttpStatus.notFound);
      return;
    }
    if (inference.isModelLoaded.value &&
        inference.loadedModelName.value == filename) {
      await _json(request, {
        'error': 'Already loaded',
        'filename': filename,
        'backend': inference.loadedBackend.value,
      }, status: HttpStatus.conflict);
      return;
    }
    // Refused, not queued. See the class note: the engine cannot generate and
    // load at the same time, and doing it anyway surfaces as a model that
    // answers with nonsense rather than as an error.
    if (_busy) {
      await _json(request, {
        'error': 'A generation is in progress',
        'hint': 'Wait for it to finish, then POST again.',
      }, status: HttpStatus.conflict);
      return;
    }

    // Switching native runtime is a third dialog, and it is not a warning — it
    // is a fact about the process. GGUF runs on one `.so` and LiteRT-LM on
    // another; the session binds to one of them on the first load and cannot
    // change without a restart.
    //
    // Caught here rather than left to `loadModel` because that method's answer
    // is a dialog, and a dialog nobody answers means the request silently does
    // nothing: the endpoint answered `202 accepted` for `Qwen3-0.6B.litertlm`,
    // and 24 s later the GGUF was still loaded and the LiteRT never was. A 202
    // that is not followed by the thing it promised is worse than a refusal.
    final target = _findModel(controller, filename);
    final targetRuntime = (target?.runtime ??
            AiModel.runtimeFromFilename(filename))
        .toLowerCase();
    final currentRuntime = inference.sessionNativeRuntime.toLowerCase();
    if (inference.requiresAppRestartForRuntime(targetRuntime)) {
      await _json(request, {
        'error': 'This model needs a different native runtime than the one '
            'this session is using.',
        'filename': filename,
        'needed_runtime': targetRuntime,
        'session_runtime': currentRuntime.isEmpty ? null : currentRuntime,
        'hint': 'GGUF and LiteRT-LM are two different native libraries and a '
            'session binds to one on its first load. Restart the app, then POST '
            'this again: after a restart there is no session runtime yet, so it '
            'loads without a restart.',
      }, status: HttpStatus.conflict);
      return;
    }

    // The load shows a memory-safety dialog. There is nobody to answer it over
    // HTTP, and the two wrong answers are both bad: leaving it up blocks the
    // caller forever, and letting `loadModel` run without a decision frees the
    // old model and loads nothing — which is exactly what the first version did
    // on the A72, answering 202 and leaving the device with no model.
    //
    // So the caller has to say it accepts the warning. Not a flag that skips
    // the checks — those are the guards, and they run either way. It stands for
    // the tap on "Load", which is the only thing a person was ever being asked.
    final accept = body?['accept_risk'] == true;
    if (!accept) {
      await _json(request, {
        'error': 'Loading a model shows a memory-safety confirmation.',
        'filename': filename,
        'file_size': controller.fileSizes[filename]?.toString() ?? null,
        'hint': 'Re-send with {"filename": "...", "accept_risk": true} to '
            'confirm you accept the warning. The file and memory checks still '
            'run and can still refuse.',
      }, status: HttpStatus.conflict);
      return;
    }

    final previous = inference.isModelLoaded.value
        ? inference.loadedModelName.value
        : null;

    // **A resposta vai antes da operação.** Isso é uma correção medida, e não uma
    // preferência de leitura.
    //
    // A primeira versão chamava `unawaited(controller.loadModel(...))` e só
    // depois escrevia o 202. Uma carga de modelo bloqueia o isolate do Dart —
    // é uma chamada JNI síncrona que segura a thread — e como o `unawaited`
    // começava na linha de cima, o isolate era preso antes de o socket ter
    // algo para enviar. O sintoma no host era `curl` devolvendo `000`, sem
    // código HTTP, em toda requisição que disparava uma operação real:
    // `/v1/models/load` com `accept_risk` e `/v1/models/unload`. E o
    // `409` — que responde e só então descobre que o corpo está errado —
    // funcionava, o que isola a causa: não era o POST, nem o forward, nem o
    // servidor; era a ordem.
    //
    // `GET` continuava respondendo o tempo todo, porque nada bloqueava.
    await _json(request, {
      'accepted': true,
      'filename': filename,
      // Null when nothing was loaded, which is different from loading into an
      // empty slot: the old model is being freed and that costs time too.
      'replaced': previous,
      'watch': 'GET /v1/models/local',
    }, status: HttpStatus.accepted);

    // Um turno do event loop para o socket realmente sair. `close()` enfileira
    // a escrita; sem este `await` o isolate é preso no JNI antes do flush, e o
    // `202` continua não chegando. Centésimos de segundo, uma vez por troca de
    // modelo, em troca de um endpoint que responde.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    unawaited(controller.loadModel(filename, acceptWarnings: true));
  }

  /// `POST /v1/models/unload` — refused, on purpose.
  ///
  /// The first version called `ModelController.unloadModel()` and the exact
  /// failure is worth recording, because "the endpoint does not work" would be
  /// the wrong conclusion. `unloadModel` calls
  /// `_stopServerForMissingModel()`: unloading takes **this server** down with
  /// it, by design, because otherwise every endpoint keeps answering `200` with
  /// nothing behind it and `/v1/server/capabilities` keeps reporting
  /// `running: true` on an empty model. Writing the response before the stop
  /// does not rescue it — the socket closes before the body is flushed and the
  /// client sees `Empty reply from server` with no HTTP code at all. Measured on
  /// the A72, twice, and it is why `curl` reports `000` rather than a status.
  ///
  /// So this is a `409` that names the situation and gives the way out, rather
  /// than an endpoint that half-works. The asymmetry is real and intended:
  /// **loading** keeps the server up, because `InferenceService.unloadModel` is
  /// the first step of every load and deliberately does not touch the server.
  /// So `POST /v1/models/load` is how you swap models, and the whole
  /// measurement campaign runs on it. To get to no model, stop the server —
  /// which is what the app's own toggle does.
  Future<void> _handleModelUnload(HttpRequest request) async {
    final inference = Get.find<InferenceService>();
    if (!inference.isModelLoaded.value) {
      await _json(request, {'error': 'Nothing is loaded'},
          status: HttpStatus.conflict);
      return;
    }
    await _json(request, {
      'error': 'Unloading also takes the local server down, so it cannot be '
          'done over the API.',
      'unloaded_would_be': inference.loadedModelName.value,
      'hint': 'POST /v1/models/load with another filename instead — loading '
          'keeps the server running. Or turn the server off from its own screen '
          'when you want no model at all.',
    }, status: HttpStatus.conflict);
  }


  Future<void> _handleCapabilities(HttpRequest request) async {
    final inference = Get.find<InferenceService>();
    final hasModel = inference.isModelLoaded.value;
    final isLiteRt = hasModel && inference.loadedModelRuntime.value == 'litert';
    // An encoder answers a different question from a generation model, and
    // which of the two is loaded decides every other flag below. Reported here
    // so a client can find out before building a request that will be refused.
    EncoderInfo encoder = const EncoderInfo();
    if (hasModel) {
      try {
        encoder = await LlamaEncoder.info();
      } on Object catch (_) {
        // A generation model, or a runtime without the encoder surface. Either
        // way "no encoder" is the right answer, not a failed request.
      }
    }
    // Three states, not two. `isEncoder` is a loaded encoder with a pooling type;
    // `archIsEncoder` is an encoder-only architecture this build could not turn
    // into a scorer (jina-reranker-v1-tiny-en: a real cross-encoder whose GGUF
    // has no cls.output.*, so there is no logit to return). Neither can generate
    // — a BERT has no LM head, and answering `text: true` sends a client to
    // /v1/chat for whatever the encoder does produce. So `generates` excludes
    // both, and a file this build cannot use reports no capability at all rather
    // than one it does not have.
    final generates =
        hasModel && !encoder.isEncoder && !encoder.archIsEncoder;
    await _json(request, {
      'server': 'mobileLM Local OpenAI API',
      'running': true,
      'model': hasModel ? inference.loadedModelName.value : null,
      'runtime': inference.loadedModelRuntime.value,
      'requires_litert': false,
      'capabilities': {
        'text': generates,
        'image': isLiteRt && inference.isVisionLoaded.value,
        'audio': isLiteRt,
        'streaming': generates,
        'gguf': hasModel && !isLiteRt,
        'embeddings': encoder.isEmbedding,
        'rerank': encoder.isReranker,
        'classify': encoder.isClassifier,
      },
      if (encoder.archIsEncoder && !encoder.isEncoder)
        'note': 'Encoder architecture with no classification head in its GGUF: '
            'no cls.output.* tensor, so there is no logit. This build can do '
            'nothing with it — not generation (an encoder has no LM head) and '
            'not a score.',
      'encoder': encoder.isEncoder
          ? {
              'pooling': encoder.pooling,
              'output_length': encoder.outputLength,
              'n_cls_out': encoder.nClsOut,
              // A caller reading `pooling: rank` should be able to tell whether
              // the file said so or the architecture implied it. A reranker
              // whose GGUF omits the key is common — jina-reranker-v1-tiny-en is
              // one — and the difference is worth surfacing rather than folding
              // into a single field that looks equally confident either way.
              'inferred_pooling': encoder.inferredPooling,
              // Published so a caller batching a hundred documents can find the
              // ceiling without discovering it by being refused. The ceiling is
              // real: an encoder pools the whole sequence in one pass, so it
              // cannot be chunked the way generation can.
              'max_input_tokens': encoder.maxInputTokens,
              'labels': encoder.labels,
            }
          : null,
      // One model at a time, and the slot is shared. An encoder in the slot
      // means nothing can generate until a generation model is loaded back, and
      // vice versa. Said plainly here because it is the one constraint on this
      // surface that a client cannot work around.
      'single_model_slot': true,
    });
  }

  /// The loaded model, or the reason it cannot serve an encoder call.
  ///
  /// A generation model is the common case and the easy mistake: a GGUF loads
  /// fine, `/v1/embeddings` returns 400, and the reason is that it emits tokens
  /// rather than pooling them. The message says that instead of "unsupported".
  Future<String?> _encoderUnavailable(EncoderInfo info, String wanted) async {
    final inference = Get.find<InferenceService>();
    if (!inference.isModelLoaded.value) {
      return 'No model loaded. Load a GGUF that declares a pooling type '
          '(BERT, ModernBERT, or an embedding/reranker model) first.';
    }
    if (!info.isEncoder) {
      // An encoder architecture that could not be given a pooling type is not a
      // chat model, and telling the caller to load an embedding model sends them
      // to fix something that is already correct. Measured on the Edge 60:
      // jina-reranker-v1-tiny-en ranks correctly (NDCG@10 0.9981 on a graded set)
      // but its GGUF carries no cls.output.*, so llama.cpp returns one float of a
      // pooled hidden state — a value in (-1, 1) that orders plausibly and is
      // not a score. Refusing it here, by name, is the whole point.
      if (info.archIsEncoder) {
        // `$wanted` is the endpoint name — 'embeddings', 'rerank', 'classify' —
        // and interpolating it produced "cannot produce a embeddings score" and
        // "a classify score", which is the kind of near-English that reads as a
        // typo and makes the caller doubt the rest of the message. The message
        // is the only thing this endpoint has to say on this path, so it has to
        // be right.
        //
        // The article is part of the data, not a prefix. Fixing only the noun
        // turned "a embeddings" into "a embedding", which is the same mistake
        // one word later: `embedding` takes "an". Only `relevance` and
        // `classification` are singular enough to need no article at all, so all
        // three are written out whole.
        const phrase = {
          'embeddings': 'an embedding',
          'rerank': 'a relevance',
          'classify': 'a classification',
        };
        return 'The loaded model is an encoder whose GGUF has no classification '
            'head, so it cannot produce '
            '${phrase[wanted] ?? 'a $wanted'} score: the conversion kept no '
            'cls.output.* tensor, which is where the logit would come from. '
            'llama.cpp would return one float of a pooled hidden state instead '
            '— a number in (-1, 1) that ranks plausibly and means nothing. Load '
            'a reranker whose GGUF carries the head, such as '
            'gte-reranker-modernbert-base.';
      }
      return 'The loaded model is a generation model, not an encoder. '
          'Embeddings, rerank and classify need a GGUF whose metadata carries '
          '<arch>.pooling_type — a BERT or ModernBERT architecture, or one of '
          'the embedding families.';
    }
    if (wanted == 'embeddings' && (info.isReranker || info.isClassifier)) {
      // Name only the endpoints this model can actually answer. The old text
      // said "Use /v1/rerank or /v1/classify" to a reranker, and /v1/classify
      // refuses it too — measured on the Edge 60 with
      // gte-reranker-modernbert-base: "returns 1 value(s) and 1 label(s), so it
      // is not a multi-class classifier". Pointing a caller at an endpoint that
      // will also refuse costs a round trip to learn the same thing twice.
      final alsoClassifies = info.isClassifier;
      return 'The loaded model is a ${info.isReranker ? 'reranker' : 'classifier'} '
          '(${info.pooling} pooling, ${info.nClsOut} output(s)), which returns scores '
          'rather than a vector. Use /v1/rerank'
          '${alsoClassifies ? ' or /v1/classify' : ''}.';
    }
    if (wanted == 'rerank' && !info.isReranker) {
      // A count of classes is not evidence here, and saying so is the point.
      // bge-small reports n_cls_out: 1 with a LABEL_0 and pooling: cls — it is a
      // 384-value embedding model with the residue of a size-1 head, so a
      // message that quoted the count would confidently call an embedding model a
      // one-class classifier. The pooling type is the thing that decides.
      final what = info.pooling == 'rank'
          ? (info.nClsOut > 1
              ? '${info.nClsOut} class scores'
              : 'a single relevance score, but it is not a RANK-pooling model')
          : 'a ${info.outputLength}-value embedding';
      return 'The loaded model is not a reranker: it returns $what, and rerank '
          'needs a RANK-pooling model with a single relevance score. '
          '${info.isEmbedding ? 'Use /v1/embeddings for it.' : ''}';
    }
    if (wanted == 'classify' && !info.isClassifier) {
      if (info.isEmbedding) {
        return 'The loaded model is an embedding model (${info.pooling} pooling, '
            '${info.outputLength} values), not a classifier. Classify needs a '
            'RANK-pooling model with more than one class.';
      }
      return 'The loaded model returns ${info.outputLength} value(s) and '
          '${info.labels.length} label(s), so it is not a multi-class classifier.';
    }
    return null;
  }

  /// The model name the caller asked for must be the loaded one, as elsewhere.
  Future<String?> _encoderModelMismatch(Map<String, dynamic> body) async {
    final inference = Get.find<InferenceService>();
    final model = (body['model'] as String?)?.trim();
    if (model == null || model.isEmpty) return null;
    if (model != inference.loadedModelName.value) {
      return 'Model not found or not loaded';
    }
    return null;
  }

  /// Coerce a JSON value to a list of strings, or throw with a message that
  /// says which of the two things went wrong.
  ///
  /// "must be an array of strings" for a field that was simply absent sends the
  /// caller looking for a type problem in a request that had no field at all —
  /// found on the device, where `{}` came back with that message.
  static List<String> _stringList(Object? raw, String field) {
    if (raw == null) {
      throw FormatException("'$field' is required");
    }
    if (raw is String) return [raw];
    if (raw is! List) {
      throw FormatException("'$field' must be a string or an array of strings");
    }
    return raw.map((e) => '$e').toList();
  }

  /// `POST /v1/embeddings` — the OpenAI shape, because it is a real one and
  /// clients already speak it. `input` may be a string or an array of strings.
  Future<void> _handleEmbeddings(HttpRequest request) async {
    // _readJson throws on a body that is not a JSON object, and _handle turns
    // that into a 500 — which is the wrong status for a client that sent
    // something malformed, but it is the pre-existing behaviour of every other
    // endpoint here and consistency beats a one-off difference nobody asked for.
    final body = await _readJson(request);
    final info = await LlamaEncoder.info();
    final unavailable = await _encoderUnavailable(info, 'embeddings');
    if (unavailable != null) {
      await _json(request, {'error': unavailable},
          status: HttpStatus.badRequest);
      return;
    }
    final mismatch = await _encoderModelMismatch(body);
    if (mismatch != null) {
      await _json(request, {'error': mismatch}, status: HttpStatus.notFound);
      return;
    }
    if (_busy) {
      await _json(request, {'error': 'Model is busy'}, status: 429);
      return;
    }

    final List<String> inputs;
    try {
      inputs = _stringList(body['input'], 'input');
    } on FormatException catch (e) {
      await _json(request, {'error': e.message}, status: HttpStatus.badRequest);
      return;
    }
    if (inputs.isEmpty) {
      await _json(request, {'error': "'input' is required"},
          status: HttpStatus.badRequest);
      return;
    }

    final inference = Get.find<InferenceService>();
    final saved = Get.find<EncoderSettingsService>();
    final data = <Map<String, dynamic>>[];
    _busy = true;
    try {
      for (var i = 0; i < inputs.length; i++) {
        // The prefix is applied here, on the server, rather than expected of the
        // client — which is the only place it can be applied consistently. Every
        // E5-family model was trained with `query: ` and `passage: ` on the two
        // sides, and every BGE wants `query: ` on the query side only. A client
        // that gets it wrong gets vectors that retrieve worse and nothing else:
        // the request succeeds, the dimensions are right, and the cosine is
        // plausible. There is no error to notice.
        //
        // `input` alone is the passage side. A client that also sends `query`
        // gets the query side instead, which is the same field name `/v1/rerank`
        // already uses, so the two endpoints read the same way.
        final q = (body['query'] as String?)?.trim();
        final onQuerySide = q != null && q.isNotEmpty;
        final prefix = onQuerySide
            ? (saved.embedQueryPrefix.value ?? '')
            : (saved.embedPassagePrefix.value ?? '');
        final out = await LlamaEncoder.encode('$prefix${onQuerySide ? q : inputs[i]}');
        // Norm is checked, not returned: a pooled vector of the right length
        // and all zeros is what a model gives when the batch was never marked
        // for output, and it would sail through every other check here.
        if (out.norm == 0) {
          await _json(request, {
            'error': 'The model returned an empty vector for input '
                '$i. That is a pooling failure, not an empty document.',
          }, status: HttpStatus.internalServerError);
          return;
        }
        // `null` asks the model; `false` is the one override worth having, since
        // cosine retrieval and raw dot-product retrieval are different choices
        // and a caller that wants the raw vector should not have to re-normalise
        // on top of ours.
        final values = saved.embedNormalize.value == false
            ? out.values
            : _normalize(out.values);
        data.add({
          'object': 'embedding',
          'index': i,
          'embedding': values,
        });
      }
    } on EncoderUnavailable catch (e) {
      await _json(request, {'error': e.message},
          status: HttpStatus.badRequest);
      return;
    } finally {
      _busy = false;
    }

    // No `usage` block, even though the OpenAI shape has one. The encode path
    // does not report a token count, and a `prompt_tokens: 0` is not a smaller
    // lie than the field being absent — it is a number a client will bill
    // against. Absent means unknown, which is the truth.
    await _json(request, {
      'object': 'list',
      'data': data,
      'model': inference.loadedModelName.value,
    });
  }

  /// `POST /v1/rerank` — the Cohere/Jina shape, because it is the shape every
  /// reranker client in the wild already sends.
  Future<void> _handleRerank(HttpRequest request) async {
    // _readJson throws on a body that is not a JSON object, and _handle turns
    // that into a 500 — which is the wrong status for a client that sent
    // something malformed, but it is the pre-existing behaviour of every other
    // endpoint here and consistency beats a one-off difference nobody asked for.
    final body = await _readJson(request);
    final info = await LlamaEncoder.info();
    final unavailable = await _encoderUnavailable(info, 'rerank');
    if (unavailable != null) {
      await _json(request, {'error': unavailable},
          status: HttpStatus.badRequest);
      return;
    }
    final mismatch = await _encoderModelMismatch(body);
    if (mismatch != null) {
      await _json(request, {'error': mismatch}, status: HttpStatus.notFound);
      return;
    }
    if (_busy) {
      await _json(request, {'error': 'Model is busy'}, status: 429);
      return;
    }

    final query = (body['query'] as String?)?.trim();
    if (query == null || query.isEmpty) {
      await _json(request, {'error': "'query' is required"},
          status: HttpStatus.badRequest);
      return;
    }
    final List<String> documents;
    try {
      documents = _documentsFrom(body['documents'] ?? body['texts']);
    } on FormatException catch (e) {
      await _json(request, {'error': e.message}, status: HttpStatus.badRequest);
      return;
    }
    if (documents.isEmpty) {
      await _json(request, {'error': "'documents' is required"},
          status: HttpStatus.badRequest);
      return;
    }
    // The request's own `top_n` wins over the saved default. A client that sent
    // one has told us what it wants; silently preferring our setting would make
    // the response shape depend on a phone-side preference the client cannot
    // see, which is the kind of coupling that makes a server hard to reason
    // about from the outside.
    final saved = Get.find<EncoderSettingsService>();
    final topN = (body['top_n'] as num?)?.toInt() ?? saved.rerankTopN.value;

    _busy = true;
    final results = <Map<String, dynamic>>[];
    try {
      for (var i = 0; i < documents.length; i++) {
        final out = await LlamaEncoder.encode(documents[i], query: query);
        results.add({
          'index': i,
          // The raw logit, and deliberately not the sigmoid. This is the
          // contract that was measured on the Edge 60 — a spread of 2,0698
          // across a set with one real answer, and the NDCG@10 of 0,9981 came
          // from these numbers — and the console reads this field to draw its
          // bars. Changing it to a probability would silently rescale every
          // measurement already taken, and a cross-encoder's sigmoid is not
          // calibrated anyway: it spans 0,46–0,87 on a set with one obvious
          // answer, which is not a probability of anything.
          //
          // The probability is offered alongside, under a name that says what
          // it is, for a client that wants one. Both, never one instead of the
          // other.
          'relevance_score': out.values.isEmpty ? 0.0 : out.values.first,
          if (saved.rerankSigmoid.value)
            'relevance_score_probability':
                sigmoid(out.values.isEmpty ? 0.0 : out.values.first),
          if (saved.rerankReturnDocuments.value) 'document': documents[i],
        });
      }
    } on EncoderUnavailable catch (e) {
      await _json(request, {'error': e.message},
          status: HttpStatus.badRequest);
      return;
    } finally {
      _busy = false;
    }

    results.sort((a, b) =>
        (b['relevance_score'] as num).compareTo(a['relevance_score'] as num));
    final ranked =
        topN != null && topN > 0 && topN < results.length ? results.sublist(0, topN) : results;
    await _json(request, {
      'id': inferenceModelName(),
      'results': ranked,
      'meta': {'billed_units': {'search_units': documents.length}},
    });
  }

  /// Splits a `documents` field into individual documents.
  ///
  /// A JSON array is taken as-is: it already has boundaries, and re-splitting it
  /// on a separator would break any document that happens to contain one. A
  /// string is split on the configured separator, which defaults to a newline.
  /// The reason this is configurable at all is that a newline cannot be
  /// distinguished from a paragraph break — a document sent as one line with
  /// blank lines in it arrives here as three documents, ranked, and returned
  /// without a word of complaint.
  List<String> _documentsFrom(Object? raw) {
    if (raw is List) {
      return raw
          .map((e) => '$e'.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (raw is! String) {
      throw const FormatException(
          "'documents' must be a string or an array of strings");
    }
    if (raw.trim().isEmpty) return const [];
    final sep = Get.find<EncoderSettingsService>().rerankDocumentSeparator.value;
    return raw
        .split(sep)
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// `POST /v1/classify` — this app's own shape, because there is no standard
  /// one. Takes a single `input` and returns one score per class, with the
  /// labels the GGUF carried.
  Future<void> _handleClassify(HttpRequest request) async {
    // _readJson throws on a body that is not a JSON object, and _handle turns
    // that into a 500 — which is the wrong status for a client that sent
    // something malformed, but it is the pre-existing behaviour of every other
    // endpoint here and consistency beats a one-off difference nobody asked for.
    final body = await _readJson(request);
    final info = await LlamaEncoder.info();
    final unavailable = await _encoderUnavailable(info, 'classify');
    if (unavailable != null) {
      await _json(request, {'error': unavailable},
          status: HttpStatus.badRequest);
      return;
    }
    final mismatch = await _encoderModelMismatch(body);
    if (mismatch != null) {
      await _json(request, {'error': mismatch}, status: HttpStatus.notFound);
      return;
    }
    if (_busy) {
      await _json(request, {'error': 'Model is busy'}, status: 429);
      return;
    }

    final List<String> inputs;
    try {
      inputs = _stringList(body['input'] ?? body['inputs'], 'input');
    } on FormatException catch (e) {
      await _json(request, {'error': e.message}, status: HttpStatus.badRequest);
      return;
    }
    if (inputs.isEmpty) {
      await _json(request, {'error': "'input' is required"},
          status: HttpStatus.badRequest);
      return;
    }

    _busy = true;
    final results = <Map<String, dynamic>>[];
    try {
      for (final input in inputs) {
        final out = await LlamaEncoder.encode(input);
        if (out.norm == 0) {
          await _json(request, {
            'error': 'The model returned an all-zero score vector.',
          }, status: HttpStatus.internalServerError);
          return;
        }
        results.add({
          'input': input,
          'scores': out.values,
          if (info.labels.isNotEmpty) 'labels': info.labels,
        });
      }
    } on EncoderUnavailable catch (e) {
      await _json(request, {'error': e.message},
          status: HttpStatus.badRequest);
      return;
    } finally {
      _busy = false;
    }

    await _json(request, {
      'object': 'list',
      'model': inferenceModelName(),
      'data': results,
    });
  }

  String inferenceModelName() =>
      Get.find<InferenceService>().loadedModelName.value;

  /// L2-normalise, the way every embedding client expects.
  ///
  /// Skipped when the vector is all zeros rather than producing NaN, which is
  /// what a divide by a zero norm gives and what a client would have to debug
  /// as a model problem rather than a pooling one.
  static List<double> _normalize(List<double> values) {
    var sum = 0.0;
    for (final v in values) {
      sum += v * v;
    }
    if (sum <= 0) return values;
    final inv = 1.0 / sqrt(sum);
    return [for (final v in values) v * inv];
  }

  Future<void> _handleChatCompletions(HttpRequest request) async {
    final body = await _readJson(request);
    final inference = Get.find<InferenceService>();
    final modelError = _localModelError(inference);
    if (modelError != null) {
      await _json(request, {'error': modelError},
          status: HttpStatus.badRequest);
      return;
    }
    if (_busy) {
      await _json(request, {'error': 'Model is busy'}, status: 429);
      return;
    }

    final parsed = await _parseChatRequest(body);
    if (parsed.error != null) {
      await _json(request, {'error': parsed.error},
          status: HttpStatus.badRequest);
      return;
    }

    final model = (body['model'] as String?)?.trim();
    if (model != null &&
        model.isNotEmpty &&
        model != inference.loadedModelName.value) {
      await _json(request, {'error': 'Model not found or not loaded'},
          status: HttpStatus.notFound);
      return;
    }

    final stream = body['stream'] == true;
    _busy = true;
    try {
      if (stream) {
        await _streamChatResponse(request, inference, parsed);
      } else {
        final text = await inference.generate(
          prompt: parsed.prompt,
          systemPrompt: parsed.systemPrompt ??
              _defaultSystemPrompt(inference.loadedModelName.value),
          conversationHistory: parsed.history,
          imagePath: parsed.imagePath,
          audioPath: parsed.audioPath,
        );
        await _json(
            request, _chatResponse(inference.loadedModelName.value, text));
      }
    } finally {
      _busy = false;
      await parsed.cleanup();
    }
  }

  Future<void> _handleCompletions(HttpRequest request) async {
    final body = await _readJson(request);
    final inference = Get.find<InferenceService>();
    final modelError = _localModelError(inference);
    if (modelError != null) {
      await _json(request, {'error': modelError},
          status: HttpStatus.badRequest);
      return;
    }
    if (_busy) {
      await _json(request, {'error': 'Model is busy'}, status: 429);
      return;
    }

    final prompt = body['prompt'];
    if (prompt is! String || prompt.trim().isEmpty) {
      await _json(request, {'error': 'prompt is required'},
          status: HttpStatus.badRequest);
      return;
    }

    final stream = body['stream'] == true;
    _busy = true;
    try {
      if (stream) {
        await _streamCompletionResponse(request, inference, prompt);
      } else {
        final text = await inference.generate(
          prompt: prompt,
          systemPrompt: _defaultSystemPrompt(inference.loadedModelName.value),
        );
        await _json(request, {
          'id': 'cmpl-${_id()}',
          'object': 'text_completion',
          'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'model': inference.loadedModelName.value,
          'choices': [
            {'index': 0, 'text': text, 'finish_reason': 'stop'}
          ],
        });
      }
    } finally {
      _busy = false;
    }
  }

  String? _localModelError(InferenceService inference) {
    if (!inference.isModelLoaded.value) {
      // Names the way out, and the way out is over HTTP: the server starts
      // without a model precisely so this can be a self-contained instruction.
      // A client that has to know that a toggle exists on a phone it is not
      // holding has been told the wrong thing.
      return 'No local model loaded. POST /v1/models/load with a filename from '
          'GET /v1/models/local to load one; the downloaded ones have state '
          '"downloaded".';
    }
    return null;
  }

  Future<_ParsedChatRequest> _parseChatRequest(
      Map<String, dynamic> body) async {
    final rawMessages = body['messages'];
    if (rawMessages is! List || rawMessages.isEmpty) {
      return _ParsedChatRequest.error('messages must be a non-empty array');
    }

    final systemParts = <String>[];
    final history = <Map<String, String>>[];
    var lastUserText = '';
    String? imagePath;
    String? audioPath;
    final tempFiles = <File>[];

    for (var i = 0; i < rawMessages.length; i++) {
      final raw = rawMessages[i];
      if (raw is! Map)
        return _ParsedChatRequest.error('message[$i] must be an object');
      final role = '${raw['role'] ?? ''}';
      if (role != 'system' && role != 'user' && role != 'assistant') {
        return _ParsedChatRequest.error('message[$i].role is unsupported');
      }
      final contentResult = await _parseContent(raw['content']);
      if (contentResult.error != null)
        return _ParsedChatRequest.error(contentResult.error!);
      tempFiles.addAll(contentResult.tempFiles);
      imagePath ??= contentResult.imagePath;
      audioPath ??= contentResult.audioPath;

      if (role == 'system') {
        if (contentResult.text.trim().isNotEmpty)
          systemParts.add(contentResult.text.trim());
        continue;
      }
      if (i == rawMessages.length - 1 && role == 'user') {
        lastUserText = contentResult.text.trim();
      } else {
        history.add({'role': role, 'content': contentResult.text});
      }
    }

    if (lastUserText.isEmpty && imagePath == null && audioPath == null) {
      return _ParsedChatRequest.error(
          'last user message must contain text, image, or audio');
    }

    return _ParsedChatRequest(
      prompt: lastUserText.isEmpty ? 'Describe this attachment.' : lastUserText,
      systemPrompt: systemParts.isEmpty ? null : systemParts.join('\n'),
      history: history,
      imagePath: imagePath,
      audioPath: audioPath,
      tempFiles: tempFiles,
    );
  }

  Future<_ContentResult> _parseContent(dynamic content) async {
    if (content is String) return _ContentResult(text: content);
    if (content is! List)
      return _ContentResult.error(
          'message.content must be a string or content array');

    final text = StringBuffer();
    String? imagePath;
    String? audioPath;
    final tempFiles = <File>[];

    for (final part in content) {
      if (part is! Map)
        return _ContentResult.error('content part must be an object');
      final type = '${part['type'] ?? ''}';
      if (type == 'text') {
        text.write('${part['text'] ?? ''}');
      } else if (type == 'image_url') {
        if (imagePath != null)
          return _ContentResult.error(
              'only one image is supported per request');
        final imageUrl = part['image_url'];
        final url = imageUrl is Map ? '${imageUrl['url'] ?? ''}' : '';
        final file = await _dataUrlToTempFile(url, 'image');
        if (file.error != null) return _ContentResult.error(file.error!);
        imagePath = file.path;
        tempFiles.add(file.file!);
      } else if (type == 'input_audio' || type == 'audio_url') {
        if (audioPath != null)
          return _ContentResult.error(
              'only one audio file is supported per request');
        final raw = part[type == 'input_audio' ? 'input_audio' : 'audio_url'];
        final data = raw is Map ? '${raw['data'] ?? raw['url'] ?? ''}' : '';
        final file = await _dataUrlToTempFile(data, 'audio');
        if (file.error != null) return _ContentResult.error(file.error!);
        audioPath = file.path;
        tempFiles.add(file.file!);
      } else {
        return _ContentResult.error('unsupported content part type: $type');
      }
    }

    return _ContentResult(
      text: text.toString(),
      imagePath: imagePath,
      audioPath: audioPath,
      tempFiles: tempFiles,
    );
  }

  Future<_TempFileResult> _dataUrlToTempFile(String value, String kind) async {
    if (!value.startsWith('data:')) {
      return _TempFileResult.error(
          'Only base64 data URLs are accepted for $kind input');
    }
    final comma = value.indexOf(',');
    if (comma <= 0 || !value.substring(0, comma).contains(';base64')) {
      return _TempFileResult.error('$kind input must be a base64 data URL');
    }
    final meta = value.substring(5, comma).toLowerCase();
    final encoded = value.substring(comma + 1);
    if (encoded.length > maxDecodedAttachmentBytes * 2) {
      return _TempFileResult.error('$kind input is too large');
    }
    late List<int> bytes;
    try {
      bytes = base64Decode(encoded);
    } catch (_) {
      return _TempFileResult.error('$kind input has invalid base64');
    }
    if (bytes.length > maxDecodedAttachmentBytes) {
      return _TempFileResult.error('$kind input is too large');
    }
    final ext = _extensionForMime(meta, kind);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/server_${kind}_${_id()}.$ext');
    await file.writeAsBytes(bytes, flush: true);
    return _TempFileResult(file);
  }

  String _extensionForMime(String mime, String kind) {
    if (mime.contains('png')) return 'png';
    if (mime.contains('webp')) return 'webp';
    if (mime.contains('jpg') || mime.contains('jpeg')) return 'jpg';
    if (mime.contains('wav')) return 'wav';
    if (mime.contains('mp3') || mime.contains('mpeg')) return 'mp3';
    if (mime.contains('m4a') || mime.contains('mp4')) return 'm4a';
    return kind == 'image' ? 'png' : 'wav';
  }

  Future<void> _streamChatResponse(
    HttpRequest request,
    InferenceService inference,
    _ParsedChatRequest parsed,
  ) async {
    final response = request.response;
    _addCorsHeaders(response);
    response.statusCode = HttpStatus.ok;
    response.headers.contentType =
        ContentType('text', 'event-stream', charset: 'utf-8');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    // **`bufferOutput = false` é o que faz isto ser streaming.**
    //
    // O handler já escrevia um chunk por token, via `onToken`, e mesmo assim o
    // cliente recebia uma chunk só, no fim. Medido: um pedido com
    // `stream: true` no A72 devolveu **1 chunk e `[DONE]`, ambos aos 25,86 s** —
    // 25 segundos de espera e depois a resposta inteira, que é o oposto de
    // streaming.
    //
    // A causa é o buffer do `HttpResponse` do Dart: `write()` enfileira, e o
    // que vai para o socket sai no `close()`. Com `bufferOutput` ligado (o
    // padrão) os 48 chunks ficavam na fila até o fim. Desligando, cada
    // `write` vai direto.
    //
    // Importa por dois motivos, e o segundo é o que a medicao do catálogo
    // dependia: um cliente que usa streaming por latência percebida não recebe
    // nada mais cedo, e **não há como medir TTFT pelo stream** enquanto isso.
    response.bufferOutput = false;
    final id = 'chatcmpl-${_id()}';
    final created = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var emitted = false;

    void emit(String token) {
      emitted = true;
      final payload = {
        'id': id,
        'object': 'chat.completion.chunk',
        'created': created,
        'model': inference.loadedModelName.value,
        'choices': [
          {
            'index': 0,
            'delta': {'content': token},
            'finish_reason': null,
          }
        ],
      };
      response.write('data: ${jsonEncode(payload)}\n\n');
    }

    final result = await inference.generate(
      prompt: parsed.prompt,
      systemPrompt: parsed.systemPrompt ??
          _defaultSystemPrompt(inference.loadedModelName.value),
      conversationHistory: parsed.history,
      imagePath: parsed.imagePath,
      audioPath: parsed.audioPath,
      onToken: emit,
    );
    if (!emitted && result.isNotEmpty) emit(result);
    response.write('data: [DONE]\n\n');
    await response.close();
  }

  Future<void> _streamCompletionResponse(
    HttpRequest request,
    InferenceService inference,
    String prompt,
  ) async {
    final response = request.response;
    _addCorsHeaders(response);
    response.statusCode = HttpStatus.ok;
    response.headers.contentType =
        ContentType('text', 'event-stream', charset: 'utf-8');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    // **`bufferOutput = false` é o que faz isto ser streaming.**
    //
    // O Handler já escrevia um chunk por token, via `onToken`, e mesmo assim o
    // cliente recebia uma chunk só, no fim. Medido: um pedido com
    // `stream: true` no A72 devolveu **1 chunk e `[DONE]`, ambos aos 25,86 s** —
    // 25 segundos de espera e depois a resposta inteira, que é o oposto de
    // streaming.
    //
    // A causa é o buffer do `HttpResponse` do Dart: `write()` enfileira, e o
    // que vai para o socket sai no `close()`. Com `bufferOutput` ligado (o
    // padrão) os 48 chunks ficavam na fila até o fim. Desligando, cada
    // `write` vai direto.
    //
    // Importa por dois motivos, e o segundo é o que a medicao do catálogo
    // dependia: um cliente que usa streaming por latência percebida não recebe
    // nada mais cedo, e **não há como medir TTFT pelo stream** enquanto isso.
    response.bufferOutput = false;
    final id = 'cmpl-${_id()}';
    final created = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var emitted = false;

    void emit(String token) {
      emitted = true;
      response.write('data: ${jsonEncode({
            'id': id,
            'object': 'text_completion',
            'created': created,
            'model': inference.loadedModelName.value,
            'choices': [
              {'index': 0, 'text': token, 'finish_reason': null}
            ],
          })}\n\n');
    }

    final result = await inference.generate(
      prompt: prompt,
      systemPrompt: _defaultSystemPrompt(inference.loadedModelName.value),
      onToken: emit,
    );
    if (!emitted && result.isNotEmpty) emit(result);
    response.write('data: [DONE]\n\n');
    await response.close();
  }

  Map<String, dynamic> _chatResponse(String model, String text) {
    return {
      'id': 'chatcmpl-${_id()}',
      'object': 'chat.completion',
      'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'model': model,
      'choices': [
        {
          'index': 0,
          'message': {'role': 'assistant', 'content': text},
          'finish_reason': 'stop',
        }
      ],
    };
  }

  Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
      if (builder.length > maxBodyBytes) {
        throw const HttpException('Request body is too large');
      }
    }
    final body = utf8.decode(builder.takeBytes());
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('JSON body must be an object');
    }
    return decoded;
  }

  Future<void> _json(
    HttpRequest request,
    Map<String, dynamic> data, {
    int status = HttpStatus.ok,
  }) async {
    _addCorsHeaders(request.response);
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(data));
    await request.response.close();
  }

  void _addCorsHeaders(HttpResponse response) {
    response.headers.set(HttpHeaders.accessControlAllowOriginHeader, '*');
    response.headers
        .set(HttpHeaders.accessControlAllowMethodsHeader, 'GET,POST,OPTIONS');
    response.headers.set(
      HttpHeaders.accessControlAllowHeadersHeader,
      'Content-Type, Authorization',
    );
  }

  Future<String?> _reachableIpv4Address() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback) return address.address;
        }
      }
    } catch (_) {}
    return null;
  }

  String _id() {
    final rng = Random.secure();
    return List.generate(12, (_) => rng.nextInt(16).toRadixString(16)).join();
  }

  String _defaultSystemPrompt(String modelName) {
    if (Get.isRegistered<SettingsController>()) {
      return Get.find<SettingsController>().effectiveSystemPromptForModel(
        modelName,
      );
    }
    if (AppConstants.isUncensoredModelName(modelName)) {
      return AppConstants.uncensoredSystemPrompt;
    }
    return AppConstants.systemPrompt;
  }
}

class _ParsedChatRequest {
  final String prompt;
  final String? systemPrompt;
  final List<Map<String, String>> history;
  final String? imagePath;
  final String? audioPath;
  final List<File> tempFiles;
  final String? error;

  _ParsedChatRequest({
    required this.prompt,
    required this.systemPrompt,
    required this.history,
    required this.imagePath,
    required this.audioPath,
    required this.tempFiles,
    this.error,
  });

  _ParsedChatRequest.error(this.error)
      : prompt = '',
        systemPrompt = null,
        history = const [],
        imagePath = null,
        audioPath = null,
        tempFiles = const [];

  Future<void> cleanup() async {
    for (final file in tempFiles) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }
}

class _ContentResult {
  final String text;
  final String? imagePath;
  final String? audioPath;
  final List<File> tempFiles;
  final String? error;

  _ContentResult({
    required this.text,
    this.imagePath,
    this.audioPath,
    this.tempFiles = const [],
    this.error,
  });

  _ContentResult.error(this.error)
      : text = '',
        imagePath = null,
        audioPath = null,
        tempFiles = const [];
}

class _TempFileResult {
  final File? file;
  final String? error;

  _TempFileResult(this.file) : error = null;
  _TempFileResult.error(this.error) : file = null;

  String get path => file!.path;
}
