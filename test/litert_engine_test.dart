// Tests for the pieces of the FFI layer that are pure logic.
//
// None of these load `libmobilelm_core.so`: it is an aarch64 Android library, and
// a test that needs a device to pass is a test nobody runs. What is testable
// without one is exactly what is most likely to be wrong — the JSON the engine
// reads, and the rule for when a conversation must be rebuilt — because those are
// where a mistake is silent rather than loud.
//
// The engine's C++ reads `type`, `text`, `path` and `blob` by name out of the
// parsed JSON (`runtime/conversation/model_data_processor/data_utils.cc`). A name
// it does not recognise is **not an error**: `LoadItemData` throws where a missing
// key is read, the turn is accepted, and the model answers from the text alone
// with the image silently dropped. That is the same shape as the response-side bug
// 34 host tests missed, so the expectations here are written against the C++ that
// reads them, not against the header's description of them.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/ffi/litert_engine.dart';
import 'package:mobilelm/ffi/mobilelm_core_bindings.dart';

void main() {
  group('LiteRtMessage', () {
    test('a text turn is the array form, not the bare-string form', () {
      // The C API also accepts `{"role":"user","content":"hi"}`, and a bare string
      // is accepted as an *empty* turn. One shape for both is deliberate: a
      // second builder differing only in whether `content` is a string or an
      // array is a second thing to get wrong.
      final json = LiteRtMessage.text('user', 'oi').toJson();
      expect(jsonDecode(json), {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'oi'}
        ],
      });
    });

    test('media parts use path, because the engine memory-maps them', () {
      final msg = LiteRtMessage('user', [
        const TextPart('descreva'),
        const ImageFilePart('/data/user/0/com.dollarbr.mobilelm/cache/i.jpg'),
        const AudioFilePart('/data/user/0/com.dollarbr.mobilelm/cache/a.wav'),
      ]);
      final decoded = jsonDecode(msg.toJson()) as Map<String, dynamic>;
      final parts = decoded['content'] as List;
      expect(parts, [
        {'type': 'text', 'text': 'descreva'},
        {
          'type': 'image',
          'path': '/data/user/0/com.dollarbr.mobilelm/cache/i.jpg'
        },
        {
          'type': 'audio',
          'path': '/data/user/0/com.dollarbr.mobilelm/cache/a.wav'
        },
      ]);
      expect(msg.isMultimodal, isTrue);
    });

    test('a text-only turn reports itself as not multimodal', () {
      // The caller uses this to decide whether the turn needs an encoder backend
      // at load time, so getting it wrong means either a crash (sending media to a
      // model with no encoder) or a wasted encoder (building one nobody sends to).
      expect(LiteRtMessage.text('user', 'oi').isMultimodal, isFalse);
    });

    test('a prompt cannot inject a second content part', () {
      // Escaping is the Rust side's job, but the Dart side must not undo it: if
      // this layer re-encoded by hand the guarantee would live in two places.
      final json = LiteRtMessage.text('user', '"}{\\"type\\":\\"image\\"}')
          .toJson();
      final parts =
          (jsonDecode(json) as Map<String, dynamic>)['content'] as List;
      expect(parts, hasLength(1));
      expect((parts.first as Map)['type'], 'text');
    });

    test('non-ascii survives as UTF-8 rather than \\u escapes', () {
      // Valid JSON either way, and the consumer is a C++ parser that handles it.
      // Escaping would only make the log harder to read.
      final json = LiteRtMessage.text('user', 'olá, maçã').toJson();
      expect(json, contains('olá, maçã'));
      expect(json, isNot(contains(r'\u00e7')));
    });

    test('encodeAll produces a JSON array, and [] for no history', () {
      // `set_messages` takes an array. An empty string or a single object is an
      // error natively, and `[]` has to be accepted because "clear the
      // conversation" is the one thing that must always work.
      expect(LiteRtMessage.encodeAll(const []), '[]');
      final one = LiteRtMessage.encodeAll([LiteRtMessage.text('user', 'oi')]);
      expect(jsonDecode(one), hasLength(1));
      expect((jsonDecode(one) as List).first, {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'oi'}
        ],
      });
    });
  });

  group('ConversationRequest.matches', () {
    ConversationRequest req({
      String? systemPrompt,
      double? temperature = 0.7,
      int? topK = 64,
      List<LiteRtMessage> history = const [],
    }) =>
        ConversationRequest(
          systemPrompt: systemPrompt,
          temperature: temperature,
          topK: topK,
          topP: 0.95,
          history: history,
        );

    test('an identical request does not rebuild', () {
      expect(req().matches(req()), isTrue);
    });

    test('a temperature change rebuilds, because the sampler is fixed at create',
        () {
      // Not an optimisation. The C API sets the sampler when the conversation is
      // created, so reusing the conversation would silently keep the old
      // temperature — the slider would move and nothing would happen.
      expect(req(temperature: 0.7).matches(req(temperature: 0.7)), isTrue);
      expect(req(temperature: 0.7).matches(req(temperature: 0.2)), isFalse);
    });

    test('a system prompt change rebuilds', () {
      expect(req(systemPrompt: 'a').matches(req(systemPrompt: 'b')), isFalse);
    });

    test('a sampler knob change rebuilds', () {
      expect(req(topK: 64).matches(req(topK: 32)), isFalse);
    });

    test('a spoken conversation arriving with no history rebuilds', () {
      // The engine is holding turns the caller has forgotten. Reusing it makes
      // the model answer as if the exchange in between never happened, and that
      // is the one bug in this area a user cannot work around.
      final spoken = req();
      spoken.markSpoken();
      expect(spoken.matches(req()), isFalse);
      // ...and keeps rebuilding until the caller sends history again.
      expect(spoken.matches(req(history: [LiteRtMessage.text('user', 'oi')])),
          isTrue);
    });
  });

  group('LiteRtMessage encoding matches the Rust builder', () {
    // The Rust side renders the same structure with `json::parts_message`, and its
    // tests pin the field names against the C++. This is the Dart half of the same
    // contract: if the two ever disagree, the message that works on one engine
    // path silently loses its media on the other.
    test('a text-only turn is byte-identical to the Rust builder output', () {
      // `json::parts_message("user", &[Text("oi")])` in mobilelm-core.
      expect(
        LiteRtMessage.text('user', 'oi').toJson(),
        '{"role":"user","content":[{"type":"text","text":"oi"}]}',
      );
    });
  });

  group('SamplerReport', () {
    // The device said `UNIMPLEMENTED: Sampler type: 1 not implemented yet`, and
    // the fix made a substitution possible. Without this the app could not tell
    // "temperature 0.8 is in force" from "temperature 0.8 is ignored", which are
    // the same reply on a greedy sampler. `full` is the field that carries the
    // difference, so it is the field a decode bug would quietly zero.
    test('a substituted type is not full, a matched one is', () {
      final substituted = SamplerReport.fromJson(const {
        'requested': 'top_k',
        'actual': 'greedy',
        'full': false,
        'note': 'sampler: greedy, substituted for top_k',
      });
      expect(substituted.actual, 'greedy');
      expect(substituted.full, isFalse,
          reason: 'on greedy, temperature and top_k are not consulted');

      final matched = SamplerReport.fromJson(const {
        'requested': 'top_k',
        'actual': 'top_k',
        'full': true,
        'note': 'sampler: top_k',
      });
      expect(matched.full, isTrue);
    });

    test('the engine default decodes as null actual, not as a missing field', () {
      // `actual` is nullable in Dart and JSON `null` in Rust. A decode that turned
      // it into a throw would take down the turn that was only asking a question.
      final report = SamplerReport.fromJson(const {
        'requested': 'top_k',
        'actual': null,
        'full': false,
        'note': 'sampler: the engine default is in use',
      });
      expect(report.actual, isNull);
      expect(report.full, isFalse);
    });
  });

  group('LiteRtEngine.load', () {
    // The device run found the bug this pins. With the switch on, `load` spawned the
    // isolate, completed the handshake, and returned an engine whose native handle
    // was never created — because the isolate only builds the engine inside its
    // `case 'load':` and nothing ever sent that command. Every later call then
    // failed on a null handle, three calls away from the cause.
    //
    // A laptop cannot reproduce that: there is no core library here, so the guard
    // throws first. What *is* reproducible, and is the class of the bug, is the
    // shape of the failure — `load` either produces a working engine or throws. It
    // must never return something that looks loaded and is not, because that is
    // what turns one missing line into a null-pointer three calls later.
    test('throws rather than returning a half-built engine', () async {
      expect(
        () => LiteRtEngine.load(
          modelPath: '/does/not/exist.litertlm',
          backend: 'cpu',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('the guard names the missing library, not a symptom of it', () async {
      // "the core is not in this build" is actionable. "engine handle is null" is
      // the same information one indirection further from the cause, and is what
      // the device actually reported.
      Object? caught;
      try {
        await LiteRtEngine.load(
          modelPath: '/does/not/exist.litertlm',
          backend: 'cpu',
        );
      } catch (e) {
        caught = e;
      }
      expect(caught, isNotNull,
          reason: 'load must not succeed on a build with no core');
      final text = caught.toString();
      expect(text, contains('not in this build'),
          reason: 'the error must name the cause: $text');
      expect(text, isNot(contains('handle is null')),
          reason: 'a null handle is a symptom, not a cause: $text');
    });
  });
}
