import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:path_provider/path_provider.dart';

import '../controllers/settings_controller.dart';
import '../core/constants.dart';
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
    int port = 8080,
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

  bool _isAuthorized(HttpRequest request) {
    final key = _apiKey;
    if (key == null || key.isEmpty) return true;
    final header = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    return header.trim() == 'Bearer $key';
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
    await _json(request, {
      'server': 'mobileLM Local OpenAI API',
      'running': true,
      'model': hasModel ? inference.loadedModelName.value : null,
      'runtime': inference.loadedModelRuntime.value,
      'requires_litert': false,
      'capabilities': {
        'text': hasModel && !encoder.isEncoder,
        'image': isLiteRt && inference.isVisionLoaded.value,
        'audio': isLiteRt,
        'streaming': hasModel && !encoder.isEncoder,
        'gguf': hasModel && !isLiteRt,
        'embeddings': encoder.isEmbedding,
        'rerank': encoder.isReranker,
        'classify': encoder.isClassifier,
      },
      'encoder': encoder.isEncoder
          ? {
              'pooling': encoder.pooling,
              'output_length': encoder.outputLength,
              'n_cls_out': encoder.nClsOut,
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
      return 'The loaded model is a generation model, not an encoder. '
          'Embeddings, rerank and classify need a GGUF whose metadata carries '
          '<arch>.pooling_type — a BERT or ModernBERT architecture, or one of '
          'the embedding families.';
    }
    if (wanted == 'embeddings' && (info.isReranker || info.isClassifier)) {
      return 'The loaded model is a ${info.isReranker ? 'reranker' : 'classifier'} '
          '(${info.pooling} pooling, ${info.nClsOut} output(s)), which returns scores '
          'rather than a vector. Use /v1/rerank or /v1/classify.';
    }
    if (wanted == 'rerank' && !info.isReranker) {
      return 'The loaded model returns ${info.nClsOut} class score(s), not a single '
          'relevance score. Use /v1/classify for it, or load a model with one class.';
    }
    if (wanted == 'classify' && !info.isClassifier) {
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

  static List<String> _stringList(Object? raw, {String? field}) {
    if (raw is! List) {
      if (field != null) {
        throw FormatException("'$field' must be an array of strings");
      }
      return const [];
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
      final raw = body['input'];
      inputs = raw is String
          ? [raw]
          : _stringList(raw, field: 'input');
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
    final data = <Map<String, dynamic>>[];
    _busy = true;
    try {
      for (var i = 0; i < inputs.length; i++) {
        final out = await LlamaEncoder.encode(inputs[i]);
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
        data.add({
          'object': 'embedding',
          'index': i,
          'embedding': _normalize(out.values),
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
    final documents = (body['documents'] ?? body['texts']) is List
        ? _stringList(body['documents'] ?? body['texts'])
        : const <String>[];
    if (documents.isEmpty) {
      await _json(request, {'error': "'documents' is required"},
          status: HttpStatus.badRequest);
      return;
    }
    final topN = (body['top_n'] as num?)?.toInt();

    _busy = true;
    final results = <Map<String, dynamic>>[];
    try {
      for (var i = 0; i < documents.length; i++) {
        final out = await LlamaEncoder.encode(documents[i], query: query);
        results.add({
          'index': i,
          'relevance_score': out.values.isEmpty ? 0.0 : out.values.first,
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

    final inputs = (body['input'] ?? body['inputs']) is List
        ? _stringList(body['inputs'] ?? body['input'])
        : [if (body['input'] is String) body['input'] as String];
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
      return 'No local model loaded. Load a GGUF or LiteRT-LM model first.';
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
