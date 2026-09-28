// The LiteRT-LM engine over `dart:ffi`, shaped like the Kotlin plugin it replaces.
//
// The contract this file has to keep is not "call the native function". It is the
// behaviour `inference_android.dart` already depends on, which the Kotlin path
// provided and which a rewrite silently changes if nobody writes it down:
//
// - **Generation blocks the calling isolate.** `mobilelm_send_stream` blocks
//   until the turn ends, so this runs it on a spawned isolate and the UI isolate
//   never blocks. The Kotlin path had a channel per token and an idle timer; this
//   has one blocking call and the same timeouts, which is strictly less machinery
//   for the same behaviour.
// - **Text arrives already unwrapped.** The Kotlin path filtered the stream's
//   JSON envelope with `messageToMap`; the Rust side does it with
//   `mobilelm_core::json::extract_content_text` before the callback fires. So
//   there is no `_cleanLiteRtChunk` here, and adding one would be a second
//   implementation of a fix that is already made — the bug 34 host tests missed
//   was exactly that envelope reaching the user.
// - **The same three fallbacks survive a load failure**: text-only when the file
//   has no audio encoder, and the two vision-signature messages. Those are in
//   `inference_android.dart` and are not duplicated here; this class raises, and
//   the caller decides.
// - **The conversation is recreated when the temperature changes**, because the
//   C API fixes the sampler at creation. Same condition the Kotlin path used.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'mobilelm_core_bindings.dart';

/// One part of a multimodal turn.
///
/// The field names are not ours — the engine's C++ reads `type`, `text`, `path`
/// and `blob` by name, and a name it does not recognise is not an error: the turn
/// is accepted and the media is silently dropped, leaving the model answering from
/// the text alone. `path` is preferred over `blob` for anything already on disk,
/// because the engine memory-maps it.
sealed class MessagePart {
  const MessagePart();

  Map<String, dynamic> toJson();
}

class TextPart extends MessagePart {
  const TextPart(this.text);
  final String text;

  @override
  Map<String, dynamic> toJson() => {'type': 'text', 'text': text};
}

class ImageFilePart extends MessagePart {
  const ImageFilePart(this.path);
  final String path;

  @override
  Map<String, dynamic> toJson() => {'type': 'image', 'path': path};
}

class AudioFilePart extends MessagePart {
  const AudioFilePart(this.path);
  final String path;

  @override
  Map<String, dynamic> toJson() => {'type': 'audio', 'path': path};
}

/// A rendered chat message. The engine takes JSON, so this is what gets built.
class LiteRtMessage {
  LiteRtMessage(this.role, this.parts);

  /// A plain-text turn, which is the overwhelmingly common case.
  factory LiteRtMessage.text(String role, String text) =>
      LiteRtMessage(role, [TextPart(text)]);

  final String role;
  final List<MessagePart> parts;

  /// True when the turn carries anything but text, so the caller can tell a
  /// multimodal turn from a textual one without inspecting the parts.
  bool get isMultimodal =>
      parts.any((p) => p is ImageFilePart || p is AudioFilePart);

  String toJson() => jsonEncode({
        'role': role,
        'content': parts.map((p) => p.toJson()).toList(),
      });

  static String encodeAll(Iterable<LiteRtMessage> messages) =>
      jsonEncode(messages.map((m) => jsonDecode(m.toJson())).toList());
}

/// Everything needed to open a conversation, and the state that decides whether
/// it needs opening again.
///
/// The recreation rule is the interesting part, and it is not new: the Kotlin path
/// recreated a conversation when the system prompt changed, when the temperature
/// changed, or when it had sent messages and the caller arrived with no history.
/// All three are here, because all three are consequences of the C API fixing
/// things at creation time rather than choices.
class ConversationRequest {
  ConversationRequest({
    this.systemPrompt,
    this.history = const [],
    this.temperature,
    this.topK,
    this.topP,
    this.greedy = false,
    this.maxOutputTokens,
  });

  final String? systemPrompt;

  /// Already-rendered messages, oldest first. Empty means "no history", which is
  /// what a cleared conversation sends.
  final List<LiteRtMessage> history;

  final double? temperature;
  final int? topK;
  final double? topP;
  final bool greedy;
  final int? maxOutputTokens;

  /// Whether the conversation currently open already matches [next].
  ///
  /// The temperature is compared with `==` on a double on purpose: it comes from
  /// a slider and takes a handful of distinct values, so a difference of 1e-16
  /// would rebuild the conversation on every single turn for no reason.
  ///
  /// The fourth condition is not a micro-optimisation. A conversation that has
  /// already spoken holds turns in the engine, and the Kotlin path recreated the
  /// conversation when the caller arrived with no history — otherwise the model
  /// answers as if the exchange in between never happened, which is the one bug
  /// in this area a user cannot work around.
  bool matches(ConversationRequest next) {
    if (next.systemPrompt != systemPrompt) return false;
    if (next.temperature != temperature) return false;
    if (next.topK != topK || next.topP != topP) return false;
    if (next.greedy != greedy) return false;
    if (next.maxOutputTokens != maxOutputTokens) return false;
    if (_spoken && next.history.isEmpty) return false;
    return true;
  }

  /// True once a turn has run on the conversation this describes.
  bool _spoken = false;

  void markSpoken() => _spoken = true;
}

/// One turn's result, plus the measurements that come with it.
class TurnResult {
  const TurnResult({
    required this.text,
    required this.chunks,
    required this.wallMs,
    this.benchmark,
  });

  /// The whole reply, assembled from the stream. Same string the UI showed, so a
  /// caller that renders from the stream and one that renders from here agree.
  final String text;

  /// Stream callbacks that carried text. **Not the model's token count** — the
  /// engine streams by graph step, so a 0.6B model produced 215 chunks for 48
  /// requested tokens. A throughput figure built on this is a figure about the
  /// engine's stepping, and `benchmark` is where the real counts are.
  final int chunks;

  final int wallMs;

  /// The runtime's own timings, when it has them.
  final EngineBenchmark? benchmark;
}

/// Raised when a turn fails. [retryable] mirrors the Kotlin path's condition: it
/// retried up to twice on `Status Code: 13`, which is LiteRT-LM's INTERNAL_ERROR.
class LiteRtGenerationException implements Exception {
  LiteRtGenerationException(this.message, {this.retryable = false});

  final String message;
  final bool retryable;

  @override
  String toString() => 'LiteRT-LM: $message'
      '${retryable ? ' (retryable)' : ''}';
}

/// The engine, on a generation isolate.
///
/// One isolate owns the handle. The native handle is `Send` and deliberately not
/// `Sync` — no engine here is safe for concurrent calls, and the LiteRT-LM C API
/// in particular will corrupt state if you pretend otherwise. The Kotlin plugin
/// enforced that with an `engineId` string and a convention; here the type system
/// enforces it, because the handle simply never crosses an isolate boundary.
class LiteRtEngine {
  LiteRtEngine._(this._runtimePath, this._boot);

  /// The native library this engine loaded, for a log line. Distinguishes "no NPU
  /// here" from "no runtime here", which are different bugs with different fixes.
  final String _runtimePath;
  String get runtimePath => _runtimePath;

  /// What the isolate was spawned with. A plain sendable map plus the port to
  /// answer on — a struct would need a second `ReceivePort` just to carry the
  /// port, and this is the whole of the boot state.
  final Map<String, dynamic> _boot;

  Isolate? _isolate;
  SendPort? _commands;
  ReceivePort? _ports;
  Completer<void>? _ready;
  ConversationRequest? _open;
  int _nextTag = 0;
  final Map<int, Completer<Object?>> _replies = {};

  /// Load a model and start a generation isolate.
  ///
  /// Throws [MobilelmException] with the native wording on failure. A load
  /// failure is where the encoder arguments matter most: passing no
  /// [visionBackend] for a model that has a vision encoder is a crash later, on
  /// the engine's own thread, not an error here.
  static Future<LiteRtEngine> load({
    required String modelPath,
    required String backend,
    String runtimePath = kLiteRtRuntimeName,
    int nCtx = 0,
    int nThreads = 0,
    String? cacheDir,
    String? dispatchDir,
    String? visionBackend,
    String? audioBackend,
    String? systemPrompt,
  }) async {
    if (MobilelmCore.tryLoad() == null) {
      throw MobilelmException(
        'the core is not in this build. A release APK has it; a debug build '
        'predating the wiring, a web target, or a test on a laptop does not.',
        symbol: 'DynamicLibrary.open',
      );
    }
    final engine = LiteRtEngine._(runtimePath, <String, dynamic>{
      'runtimePath': runtimePath,
      'modelPath': modelPath,
      'backend': backend,
      'nCtx': nCtx,
      'nThreads': nThreads,
      'cacheDir': cacheDir,
      'dispatchDir': dispatchDir,
      'visionBackend': visionBackend,
      'audioBackend': audioBackend,
      'systemPrompt': systemPrompt,
    });
    await engine._start();
    return engine;
  }

  /// Spawn the isolate and wait for its handshake.
  ///
  /// The handshake is not ceremony. The isolate's command port does not exist
  /// until the isolate has run, and the first reply could arrive before `spawn`
  /// has returned, so a port that is not listened to from the start drops
  /// messages — and the symptom is a load that hangs forever with no error.
  Future<void> _start() async {
    final ready = Completer<void>();
    _ready = ready;
    final ports = ReceivePort();
    _ports = ports;
    ports.listen(_onMessage);
    _isolate = await Isolate.spawn(
      _isolateEntry,
      <String, dynamic>{'boot': _boot, 'reply': ports.sendPort},
      debugName: 'mobilelm-litert',
      errorsAreFatal: false,
    );
    await ready.future;

    // The load is a *command*, not something the spawn does. The isolate reads the
    // boot map inside its `load` case and nothing else would ever reach that case,
    // so the engine was never created and every later call saw a null handle. Sent
    // explicitly, and awaited, so a load failure surfaces here as an exception
    // rather than as a puzzling error three calls later.
    await _ask('load');
  }

  /// One listener for the isolate's whole life: the handshake, then tagged
  /// replies. Registered before `spawn` returns, so nothing is missed.
  void _onMessage(dynamic message) {
    if (message is _Handshake) {
      _commands = message.port;
      _ready?.complete();
      _ready = null;
      return;
    }
    if (message is! Map) return;
    final tag = message['tag'] as int?;
    if (tag == null) return;
    final completer = _replies.remove(tag);
    if (completer == null || completer.isCompleted) return;
    final error = message['error'];
    if (error != null) {
      // The isolate already stringified a `MobilelmException`, prefix and all, so
      // re-wrapping it here produced "mobilelm_core: mobilelm_core: …" — which
      // reads like two failures rather than one. Passed through as a plain
      // exception, keeping the wording the far side chose.
      completer.completeError('$error');
    } else {
      completer.complete(message['result']);
    }
  }

  /// The load report from the native side.
  Future<Map<String, dynamic>> loadReport() async =>
      (await _ask('loadReport') as Map).cast<String, dynamic>();

  /// The optional C API symbols this device's runtime lacks.
  ///
  /// Empty means it has everything this build knows how to use. A non-empty list
  /// is the answer to "why is temperature doing nothing" on a device whose runtime
  /// is not the one this build was tested against.
  Future<List<String>> missingSymbols() async =>
      (await _ask('missingSymbols') as List).cast<String>();

  /// Open or replace the conversation, if [request] differs from what is open.
  Future<void> ensureConversation(ConversationRequest request) async {
    final current = _open;
    if (current != null && current.matches(request)) return;
    await _ask('conversation', <String, dynamic>{
      'systemPrompt': request.systemPrompt,
      'historyJson': LiteRtMessage.encodeAll(request.history),
      'temperature': request.temperature ?? 0,
      'topK': request.topK ?? 0,
      'topP': request.topP ?? 0,
      'greedy': request.greedy,
      'maxOutputTokens': request.maxOutputTokens ?? 0,
    });
    request.markSpoken();
    _open = request;
  }

  /// Stream one turn, delivering each piece of text as it arrives.
  ///
  /// The whole reply is also returned, assembled from the same pieces, so a caller
  /// can render the stream and store the result without the two disagreeing.
  ///
  /// Retries a retryable failure twice, which is the Kotlin path's condition and
  /// its count: Status Code 13 is LiteRT-LM's INTERNAL_ERROR, and on a 0.6B model
  /// on a phone it is a real occurrence rather than a theoretical one.
  Future<TurnResult> send(
    LiteRtMessage message, {
    int maxTokens = 0,
    void Function(String piece)? onToken,
  }) async {
    var lastError = '';
    for (var attempt = 0; attempt <= 2; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(seconds: attempt));
      }
      try {
        return await _sendOnce(message, maxTokens, onToken);
      } on LiteRtGenerationException catch (e) {
        lastError = e.message;
        if (!e.retryable) rethrow;
      }
    }
    throw LiteRtGenerationException(
      'generation failed after 2 retries. Try a smaller model or a shorter '
      'prompt. Error: $lastError',
    );
  }

  Future<TurnResult> _sendOnce(
    LiteRtMessage message,
    int maxTokens,
    void Function(String piece)? onToken,
  ) async {
    final buffer = StringBuffer();
    var chunks = 0;
    var failure = '';
    final started = DateTime.now();

    final stream = ReceivePort();
    final done = Completer<void>();
    stream.listen((event) {
      if (event is String) {
        if (event.isEmpty) return;
        buffer.write(event);
        chunks++;
        onToken?.call(event);
      } else if (event is _StreamEnd) {
        failure = event.error ?? '';
        if (!done.isCompleted) done.complete();
      }
    });

    Object? reply;
    Object? thrown;
    try {
      reply = await _ask('send', <String, dynamic>{
        'messageJson': message.toJson(),
        'maxTokens': maxTokens,
        'port': stream.sendPort,
      });
    } catch (e) {
      // The native call reports failure twice, on purpose: once as a thrown
      // exception and once as a `_StreamEnd` carrying the engine's own words. The
      // stream is the better of the two, so the exception is held and the stream
      // is still read below.
      thrown = e;
    }
    try {
      // The native call is the blocking one, so its reply arrives with the last
      // chunk. Waiting for the stream as well means a stream that ends without a
      // final marker is a visible failure rather than a silent short answer.
      await done.future;
    } catch (e) {
      thrown ??= e;
    } finally {
      stream.close();
    }

    if (failure.isNotEmpty) {
      throw LiteRtGenerationException(
        failure,
        retryable: failure.contains('Status Code: 13'),
      );
    }
    if (thrown != null) throw '$thrown';
    _open?.markSpoken();
    final map = reply is Map ? reply.cast<String, dynamic>() : const {};
    return TurnResult(
      text: buffer.toString(),
      chunks: chunks,
      wallMs: DateTime.now().difference(started).inMilliseconds,
      benchmark: map['benchmark'] == null
          ? null
          : _benchmarkFromJson((map['benchmark'] as Map).cast<String, dynamic>()),
    );
  }

  /// Tokens a prompt would occupy, per the engine's own tokenizer. -1 when the
  /// runtime has no tokenizer API, which is a real possibility and not worth
  /// raising: a missing token count is not a failed load.
  Future<int> countTokens(String text) async =>
      await _ask('countTokens', text) as int;

  /// The runtime's own timings for the conversation, or null.
  Future<EngineBenchmark?> benchmark() async {
    final b = await _ask('benchmark');
    return b == null ? null : _benchmarkFromJson((b as Map).cast<String, dynamic>());
  }

  /// Free the engine.
  ///
  /// The handle is released on the isolate that created it, which is the only
  /// thread allowed to touch it. If the isolate is already gone the handle died
  /// with it — the process is the isolate's address space — so there is nothing
  /// to clean up and nothing to complain about.
  Future<void> dispose() async {
    if (_isolate == null) return;
    try {
      await _ask('dispose');
    } catch (_) {
      // The isolate went away first. That is the normal end of a cancelled turn.
    }
    _ports?.close();
    _ports = null;
    _isolate = null;
    _commands = null;
    _open = null;
    for (final c in _replies.values) {
      if (!c.isCompleted) {
        c.completeError(MobilelmException('the engine was disposed'));
      }
    }
    _replies.clear();
  }

  /// Send one command and await its reply, tagged so concurrent callers each get
  /// their own answer rather than the first one to arrive.
  Future<Object?> _ask(String op, [Object? arg]) {
    final port = _commands;
    if (port == null || _isolate == null) {
      return Future<Object?>.error(
        MobilelmException('the engine is not loaded', symbol: op),
      );
    }
    final completer = Completer<Object?>();
    final tag = _nextTag++;
    _replies[tag] = completer;
    port.send(arg is Map<String, dynamic>
        ? {'op': op, 'tag': tag, 'args': arg}
        : {'op': op, 'tag': tag, 'arg': arg});
    return completer.future;
  }

  /// The isolate body. Runs once and then serves commands until disposed.
  ///
  /// Every `MobilelmCore` call happens on *this* isolate, which is the whole
  /// reason the handle never crosses a boundary: the native engine is `Send` and
  /// deliberately not `Sync`, and a `Pointer` that appeared on two isolates would
  /// be two threads calling one conversation.
  static void _isolateEntry(Map<String, dynamic> message) {
    final boot = (message['boot'] as Map).cast<String, dynamic>();
    final replyPort = message['reply'] as SendPort;

    final core = MobilelmCore.tryLoad();
    if (core == null) {
      replyPort.send({
        'tag': -1,
        'error': 'the core is not in this build',
      });
      return;
    }

    final commands = ReceivePort();
    replyPort.send(_Handshake(commands.sendPort));

    Pointer<Void> handle = nullptr;
    // One stream callback for the whole engine, not one per turn. See
    // `_StreamBridge` for why the per-turn version lost chunks and hung.
    final bridge = _StreamBridge();
    commands.listen((dynamic raw) {
      final msg = (raw as Map).cast<String, dynamic>();
      final op = msg['op'] as String;
      final tag = msg['tag'] as int;
      final args = msg['args'] == null
          ? const <String, dynamic>{}
          : (msg['args'] as Map).cast<String, dynamic>();
      try {
        Object? result;
        switch (op) {
          case 'load':
            handle = core.createEngine(
              runtimePath: boot['runtimePath'] as String,
              modelPath: boot['modelPath'] as String,
              backend: boot['backend'] as String,
              nCtx: boot['nCtx'] as int,
              nThreads: boot['nThreads'] as int,
              cacheDir: boot['cacheDir'] as String?,
              dispatchDir: boot['dispatchDir'] as String?,
              visionBackend: boot['visionBackend'] as String?,
              audioBackend: boot['audioBackend'] as String?,
              systemPrompt: boot['systemPrompt'] as String?,
            );
            result = true;
          case 'loadReport':
            result = _loadReportToJson(core.engineLoadReport(handle));
          case 'missingSymbols':
            result = core.symbolsMissing(boot['runtimePath'] as String);
          case 'conversation':
            core.openConversation(
              handle,
              systemPrompt: args['systemPrompt'] as String?,
              historyJson: args['historyJson'] as String?,
              temperature: (args['temperature'] as num).toDouble(),
              topK: args['topK'] as int,
              topP: (args['topP'] as num).toDouble(),
              greedy: args['greedy'] as bool,
              maxOutputTokens: args['maxOutputTokens'] as int,
            );
            result = true;
          case 'send':
            result = _send(core, bridge, handle, args);
          case 'countTokens':
            result = core.countTokens(handle, msg['arg'] as String);
          case 'benchmark':
            final b = core.benchmark(handle);
            result = b == null ? null : _benchmarkToJson(b);
          case 'dispose':
            if (handle != nullptr) {
              core.freeEngine(handle);
              handle = nullptr;
            }
            // The stream callable is closed here, and only here: it lives as long
            // as the engine, so there is no turn boundary for a queued callback
            // to be caught on.
            bridge.close();
            result = true;
          default:
            throw MobilelmException('unknown op $op');
        }
        replyPort.send({'tag': tag, 'result': result});
      } catch (e) {
        replyPort.send({'tag': tag, 'error': '$e'});
      }
    });
  }

  /// The blocking native call, with a `NativeCallable.listener` bridging the
  /// engine's thread to this isolate's port.
  ///
  /// `listener` and not `isolateLocal`: the callback fires on a thread LiteRT
  /// owns, and only `listener` may be invoked from a thread other than the owning
  /// isolate's. `isolateLocal` is a runtime error the first time a chunk arrives,
  /// which is every turn.
  static Map<String, dynamic> _send(
    MobilelmCore core,
    _StreamBridge bridge,
    Pointer<Void> handle,
    Map<String, dynamic> args,
  ) {
    final messageJson = args['messageJson'] as String;
    bridge.beginTurn(
      args['port'] as SendPort,
      maxTokens: args['maxTokens'] as int,
      messageBytes: messageJson.length,
    );
    Object? thrown;
    int nativeStatus = -999;
    try {
      nativeStatus = core.sendStream(
        handle,
        messageJson,
        args['maxTokens'] as int,
        bridge.callable,
        // The context is an id, and the native side only passes it back. Nothing
        // is allocated for it and nothing can dangle.
        0,
      );
    } catch (e) {
      // Kept rather than rethrown here: the engine's own reason is already
      // queued on the stream port as a `_StreamEnd`, and the caller reads that
      // first. Rethrowing from here would preempt it and report the plumbing
      // instead of the cause — which is exactly what the device run did.
      thrown = e;
    } finally {
      // In a `finally`, so the instrument also covers the failing path. It used to
      // run only on success, which meant the one run that most needed it printed
      // nothing.
      bridge.endTurn(nativeStatus: nativeStatus);
    }
    if (thrown != null) {
      throw '$thrown';
    }
    final b = core.benchmark(handle);
    return {'benchmark': b == null ? null : _benchmarkToJson(b)};
  }

  static Map<String, dynamic> _benchmarkToJson(EngineBenchmark b) => {
        'ttftMs': b.ttftMs,
        'prefillTokens': b.prefillTokens,
        'decodeTokens': b.decodeTokens,
        'prefillTps': b.prefillTps,
        'decodeTps': b.decodeTps,
      };

  static EngineBenchmark _benchmarkFromJson(Map<String, dynamic> j) =>
      EngineBenchmark(
        ttftMs: (j['ttftMs'] as num).toDouble(),
        prefillTokens: (j['prefillTokens'] as num).toInt(),
        decodeTokens: (j['decodeTokens'] as num).toInt(),
        prefillTps: (j['prefillTps'] as num).toDouble(),
        decodeTps: (j['decodeTps'] as num).toDouble(),
      );

  static Map<String, dynamic> _loadReportToJson(LoadReport r) => {
        'runtime': r.runtime,
        'requested': r.requested,
        'actual': r.actual,
        'fallbackReason': r.fallbackReason,
        'loadMs': r.loadMs,
        'modelBytes': r.modelBytes,
        'capabilities': r.capabilities,
        'nCtx': r.nCtx,
        'notes': r.notes,
      };
}

/// What the isolate sends back at startup: the port its commands go to.
class _Handshake {
  const _Handshake(this.port);
  final SendPort port;
}

/// The end of a stream: `error` is null on success.
class _StreamEnd {
  const _StreamEnd(this.error);
  final String? error;
}

/// Owns the one stream callback an engine has, for the engine's whole life.
///
/// **Why not one per turn.** A `NativeCallable.listener` is asynchronous: the
/// native trampoline hands the invocation to the isolate's event loop and
/// *returns*, so the `is_final` callback the engine issues immediately before
/// `mobilelm_send_stream` returns is still queued when that call returns. The
/// per-turn version closed the callable in a `finally`, which therefore raced
/// the last message and could discard it — the turn then waited on a
/// `_StreamEnd` that had already been thrown away, with no timeout, which is a
/// hang rather than an error. The same race could drop a non-final chunk and
/// shorten the answer without any signal, which is the one failure the `is_final`
/// design exists to make impossible.
///
/// A callable per engine removes the race by removing the moment of destruction:
/// there is no turn boundary to close across, and `close()` happens in `dispose`,
/// where nothing is in flight. One trampoline per engine instead of one per turn
/// is also a smaller cost than the thing it is preventing.
///
/// **The counters exist so a failure can be located from the log alone.** Three
/// device runs in a row failed in ways the log could not distinguish — one was a
/// flag, one was an undispatched command, one is this. Each cost a 22-minute
/// build to diagnose. If the process dies mid-turn, the last line written says
/// whether the engine ever started producing (`beginTurn` with no `firstChunk`),
/// produced and stopped (`lastChunk` far short of `endTurn`), or finished and
/// lost the ending (`endTurn` with no `endPort`).
class _StreamBridge {
  SendPort? _port;
  int _turn = 0;
  int _chunks = 0;
  bool _announcedFirst = false;
  int _lastChunkAtMs = 0;

  late final NativeCallable<MobilelmStreamCallbackNative> callable =
      NativeCallable<MobilelmStreamCallbackNative>.listener(_onNative);

  void _onNative(int ctx, Pointer<Utf8> text, int isFinal, Pointer<Utf8> err) {
    final port = _port;
    // A callback with no turn in progress is a turn that already ended, which
    // means the previous one was closed early. Counted rather than ignored,
    // because "chunks for a turn that is over" is exactly the symptom that is
    // otherwise invisible.
    if (port == null) {
      _orphanedCallbacks++;
      return;
    }
    if (err != nullptr) {
      port.send(_StreamEnd(err.toDartString()));
      return;
    }
    if (text != nullptr) {
      final piece = text.toDartString();
      if (piece.isNotEmpty) {
        if (!_announcedFirst) {
          _announcedFirst = true;
          _firstChunkAtMs = DateTime.now().millisecondsSinceEpoch;
          print('[LiteRt] firstChunk turn=$_turn after '
              '${_firstChunkAtMs - _turnStartMs}ms');
        }
        _chunks++;
        _lastChunkAtMs = DateTime.now().millisecondsSinceEpoch;
        port.send(piece);
      }
    }
    if (isFinal != 0) {
      print('[LiteRt] streamEnd turn=$_turn chunks=$_chunks');
      port.send(const _StreamEnd(null));
    }
  }

  int _firstChunkAtMs = 0;
  int _turnStartMs = 0;
  int _orphanedCallbacks = 0;

  void beginTurn(SendPort port, {required int maxTokens, required int messageBytes}) {
    _port = port;
    _turn++;
    _chunks = 0;
    _announcedFirst = false;
    _orphanedCallbacks = 0;
    _turnStartMs = DateTime.now().millisecondsSinceEpoch;
    print('[LiteRt] beginTurn turn=$_turn '
        'messageBytes=$messageBytes maxTokens=$maxTokens');
  }

  /// Called once the blocking native call has returned, which is *before* the
  /// queued callbacks have necessarily run.
  void endTurn({required int nativeStatus}) {
    // `lastChunkAtMs` is 0 when the engine produced nothing at all, which reads
    // differently from "produced some and then stopped" — the two are the
    // prefill-crash and the mid-decode-death, and the gap between them is the
    // difference between a model that would not answer and one that stopped.
    final tail = _lastChunkAtMs == 0
        ? -1
        : DateTime.now().millisecondsSinceEpoch - _lastChunkAtMs;
    print('[LiteRt] endTurn turn=$_turn nativeStatus=$nativeStatus '
        'chunks=$_chunks firstChunk=${_announcedFirst ? 'yes' : 'NO'} '
        'lastChunkToEndMs=$tail orphaned=$_orphanedCallbacks');
    // The port is cleared only after the ending has been queued, and the queue
    // holds the `_StreamEnd` before it holds nothing.
    _port = null;
  }

  void close() {
    if (_port != null) {
      print('[LiteRt] close while a turn was still open: '
          'turn=$_turn chunks=$_chunks');
    }
    callable.close();
  }
}

