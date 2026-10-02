import 'dart:io' show HttpHeaders;

import 'dart:ui' show Locale;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mobilelm/l10n/app_translation.dart';
import 'package:mobilelm/views/api_console_shell.dart';

/// The shared console transport's **decisions** — the parts that can be wrong in
/// silence, and the parts this harness can actually see.
///
/// ## Why there is no `HttpServer` in this file
///
/// There was one, and it could not work. `flutter_test` installs an
/// `HttpOverrides` whose `HttpClient` **answers 400 to every request and never
/// opens a socket**, and it says so in the test output:
///
/// > will actually be made. Any test expecting a real network connection and
/// > status code will fail.
///
/// So a real `HttpServer` on a loopback port is unreachable from the client side,
/// and a test built that way proves only that the stub answered. That is the
/// worst kind of test here: it would be green, it would feel like coverage, and
/// the two rules that actually cost a cycle — a `POST` on a `GET`-only route, and
/// a refusal thrown away — are both decided *above* the socket.
///
/// Hence [apiPlan] and [apiReply] being pure. The socket keeps only what only a
/// socket can do.

void main() {

  /// Registra as traduções antes de cada montagem.
  ///
  /// **Sem isto, `.tr` devolve a própria chave** e todas as asserções deste
  /// arquivo — que procuram o **texto em inglês que aparece na tela** — falham
  /// sem que nada tenha mudado. É a mesma razão pela qual 38 chaves apareceram
  /// como identificadores: o GetX não tem o que mostrar quando o mapa não está
  /// carregado.
  ///
  /// E registrar o mapa **verdadeiro** é o que faz o teste checar o texto real
  /// em vez do identificador: se a tradução sair errada, a tela mostra outra
  /// coisa e a asserção pega.
  ///
  /// `Get.locale = ...` e **não** `Get.updateLocale(...)`: o segundo é
  /// assíncrono e reconstrói a árvore, o que dentro de `setUp` dispara
  /// `'inTest': is not true` do binding — e `Get.testMode = false` para
  /// contornar piora, porque é ele que permite tocar em ciclo de vida fora de
  /// um teste.
  setUp(() {
    Get.addTranslations(AppTranslation().keys);
    Get.locale = const Locale('en', 'US');
  });

  const bearer = {HttpHeaders.authorizationHeader: 'Bearer k'};

  group('apiPlan — the method travels with the call', () {
    // The bug this rule came from: the `.tflite` console had a `_post` and called
    // it for `/v1/litert/status`, which is `GET` only. The server's route check
    // is `request.method == 'GET'`, so the `POST` fell through to the 404 arm,
    // the console caught it, showed a probe saying the server was up, and left
    // every status-dependent panel blank. It looked exactly like "the server is
    // up and the head is not loaded yet".
    test('the method is carried, never implied by a helper name', () {
      expect(apiPlan(method: 'GET', baseUrl: 'http://x', path: '/v1/litert/status').method,
          'GET');
      expect(apiPlan(method: 'POST', baseUrl: 'http://x', path: '/v1/litert/run').method,
          'POST');
    });

    test('a GET carries no body, and that is deliberate', () {
      // A GET with a body is one the server is free to ignore, so writing one
      // hides the caller\'s mistake instead of showing it.
      final plan = apiPlan(
        method: 'GET',
        baseUrl: 'http://x',
        path: '/v1/litert/status',
        body: const {'ignored': true},
      );
      expect(plan.payload, isNull);
    });

    test('a POST carries the body, encoded', () {
      final plan = apiPlan(
        method: 'POST',
        baseUrl: 'http://x',
        path: '/v1/classify',
        body: const {'choices': {'A': 'bug', 'B': 'billing'}},
      );
      expect(plan.payload, isNotNull);
      expect(plan.payload, contains('"A":"bug"'));
    });

    test('a non-finite number is sent as text instead of throwing', () {
      // `jsonEncode` throws on a non-finite double, and a head that produced NaN
      // is a real and diagnosable state. The honest answer names the number
      // JavaScript does not have.
      final plan = apiPlan(
        method: 'POST',
        baseUrl: 'http://x',
        path: '/v1/classify',
        body: const {
          'logits': [double.nan, double.infinity, double.negativeInfinity, 0.5]
        },
      );
      expect(plan.payload, contains('"NaN"'));
      expect(plan.payload, contains('"Infinity"'));
      expect(plan.payload, contains('"-Infinity"'));
      expect(plan.payload, contains('0.5'));
    });

    test('the auth headers travel, and an empty map is fine', () {
      expect(apiPlan(method: 'GET', baseUrl: 'http://x', path: '/a', auth: bearer).headers,
          bearer);
      expect(apiPlan(method: 'GET', baseUrl: 'http://x', path: '/a').headers, isEmpty,
          reason: 'the key is off by default in a fresh install, and an empty '
              'map is how that says so without branching at every call site');
    });

    test('no address throws with a message that says which screen to open', () {
      expect(
        () => apiPlan(method: 'GET', baseUrl: '', path: '/v1/models/local'),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            allOf(contains('has not reported an address'), contains('Settings')))),
      );
    });

    test('the uri is absolute, so a failure says where it went', () {
      expect(
        apiPlan(method: 'GET', baseUrl: 'http://127.0.0.1:8091', path: '/health').uri,
        'http://127.0.0.1:8091/health',
      );
    });

    test('toString is readable in a log line', () {
      final s = apiPlan(
              method: 'POST', baseUrl: 'http://x', path: '/v1/classify', body: const {'a': 1})
          .toString();
      expect(s, startsWith('POST http://x/v1/classify'));
      expect(s, contains('B'));
    });
  });

  group('apiReply — a refusal is data, or it is an exception', () {
    test('the status always comes back, folded in', () {
      expect(statusOf(apiReply(status: 200, text: '{"a":1}')), 200);
      expect(statusOf(apiReply(status: 422, text: '{}')), 422);
      expect(statusOf(const {}), 200,
          reason: 'no key means the caller built it by hand; 200 is the default '
              'rather than 0, so a hand-made body is not read as a refusal');
    });

    test('a 422 body is preserved whole', () {
      // The System One window: the decision model wrote prose, the endpoint
      // answered 422 with what it said, and that text is the answer. Throwing it
      // away leaves a panel blank where the result should be.
      final body = apiReply(status: 422, text: '''
        {"error":"The model did not answer with one of the offered options.",
         "raw":"I am not able to classify this.","expected_one_of":["A","B"]}''');
      expect(statusOf(body), 422);
      expect(body['raw'], 'I am not able to classify this.');
      expect(body['expected_one_of'], ['A', 'B']);
    });

    test('an empty body is an empty map, not a crash', () {
      final body = apiReply(status: 204, text: '');
      expect(body, {'__status': 204});
    });

    test('whitespace-only is the same as empty', () {
      expect(apiReply(status: 200, text: '   \n '), {'__status': 200});
    });

    test('throwOnError throws the server\'s own message', () {
      // The `.tflite` console: every call site is `on Object catch (e) =>
      // _error = '$e'`, and that is how a refusal reaches its screen.
      expect(
        () => apiReply(
          status: 400,
          text: '{"error":"Missing \'features\': an array of 1024 floats."}',
          throwOnError: true,
        ),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            contains('an array of 1024 floats'))),
      );
    });

    test('and 202 is a success, because the load endpoint answers before it '
        'compiles', () {
      // Treating 202 as a refusal would make every load look like a failure.
      final body = apiReply(
          status: 202, text: '{"status":"compiling"}', throwOnError: true);
      expect(statusOf(body), 202);
      expect(body['status'], 'compiling');
    });

    test('a refusal with no error field falls back to the raw text', () {
      expect(
        () => apiReply(status: 502, text: 'Bad Gateway', throwOnError: true),
        // `e.message`, not `'$e'`: `StateError.toString()` prefixes the message
        // with "Bad state: ", so matching on the stringified error tests the
        // prefix and not the text the user sees.
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'Bad Gateway')),
      );
    });

    test('a 401 is a refusal, not a healthy answer', () {
      // `/v1/**` is behind `_isAuthorized`, so a wrong key is a 401 with a body
      // that looks like a normal answer. The console that read that as "the
      // server is up" told the user the server was running when the reason
      // nothing worked was the key.
      expect(
        () => apiReply(
            status: 401, text: '{"error":"Unauthorized"}', throwOnError: true),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'Unauthorized')),
      );
    });
  });

  group('the palette', () {
    test('brightness alone supplies the colours', () {
      final dark = ConsolePalette(true);
      expect(dark.resolvedCard, const Color(0xFF1C1C1E));
      expect(dark.resolvedField, const Color(0xFF2C2C2E));
      expect(dark.background, const Color(0xFF0F0F11));

      final light = ConsolePalette(false);
      expect(light.resolvedCard, Colors.white);
      expect(light.resolvedField, const Color(0xFFF2F2F7));
      expect(light.background, const Color(0xFFF7F7F9));
    });

    test('explicit colours win, which is how the .tflite console adopts this '
        'without a refactor', () {
      // That console has carried `(isDark, field, card)` as three parameters
      // through five panels, and changing all of them to reach one shared widget
      // would be a larger and riskier diff than the thing it buys.
      const mine = Color(0xFF123456);
      const mineField = Color(0xFF654321);
      final p = ConsolePalette.explicit(mine, mineField);
      expect(p.resolvedCard, mine);
      expect(p.resolvedField, mineField);
      expect(p.isDark, isTrue,
          reason: 'and the brightness is DERIVED from the card, not passed in — '
              '0xFF123456 is dark, so a caller cannot hand over a colour and a '
              'brightness that disagree');
    });
  });

  group('the shared look', () {
    testWidgets('a card, a field, a mono block and the three messages build',
        (tester) async {
      // Not `const`: the factory derives brightness at runtime, which is the
      // whole point of it — a compile-time constant could not ask.
      final palette =
          ConsolePalette.explicit(const Color(0xFF1C1C1E), const Color(0xFF2C2C2E));
      final ctl = TextEditingController(text: '0.1, 0.2');
      addTearDown(ctl.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: Column(children: [
            consoleCard(
              palette: palette,
              title: 'the feature vector',
              note: 'a note',
              child: consoleField(
                palette: palette,
                controller: ctl,
                hint: 'numbers',
                mono: true,
              ),
            ),
            // **Both radii, and the reason is a bug this file did not catch.**
            // `consoleMono` grew a `radius` parameter so the `.tflite` console
            // could keep its 8 dp corners, and the implementation ended up giving
            // the `Container` a `color:` *and* a `decoration:` carrying the same
            // colour. `Container` asserts that it cannot be given both.
            //
            // It was green here because at the default `radius: 0` the code took
            // the `decoration: null` branch, and only the `.tflite` console — the
            // one caller that passes a radius — ever hit the other branch. **A
            // parameter added and not covered is a parameter whose other values
            // are untested**, and the device found it on the first paint.
            consoleMono(
              palette: palette,
              text: '0.1000  -0.2082',
              radius: 8,
              fontSize: 10,
            ),
            consoleErrorCard('a refusal'),
            consoleNoticeCard('a confirmation'),
            consoleProblem('a warning'),
            consoleNote('an aside'),
            consoleActions(children: [
              OutlinedButton(onPressed: () {}, child: const Text('one'))
            ]),
          ]),
        ),
      ));
      expect(find.text('the feature vector'), findsOneWidget);
      expect(find.text('a confirmation'), findsOneWidget);
      expect(find.text('0.1000  -0.2082'), findsOneWidget);
    });

    testWidgets('the actions row wraps instead of overflowing', (tester) async {
      // A `Row` of icon-plus-label buttons with nothing limiting it is the shape
      // of the three overflows this repo has already paid for, and the fix that
      // generalises is not an `Expanded` per button but stopping the assumption.
      tester.view.physicalSize = const Size(720, 900);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: SizedBox(
            width: 360,
            child: consoleActions(
              children: [
                for (final label in [
                  'Testar local',
                  'System One test',
                  're-probe the device',
                  'run the head'
                ])
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: Text(label, textScaler: const TextScaler.linear(2)),
                  ),
              ],
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });
}
