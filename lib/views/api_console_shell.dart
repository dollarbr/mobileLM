import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/colors.dart';
import '../services/system_one.dart';

/// The transport and the look that the local-API consoles share.
///
/// **A shared interface, not a shared widget**, and the distinction is the whole
/// design. Two consoles use this:
///
/// - `LitertHeadConsole`, which **introspects** a loaded `.tflite`: what the file
///   is, which tensors it wants, what the device can accelerate;
/// - `SystemOneConsole`, which **drives** a System One model: it asks a question
///   and shows what came back, and the caller supplies the labels.
///
/// They have almost nothing in common past this file, and merging them would
/// force a `switch` inside a body that is already a `switch`. What they do have in
/// common is a way of talking to `127.0.0.1:8091` and a way of drawing the answer,
/// and that is here.
///
/// The encoder console deliberately does **not** use this yet. It reaches the
/// server through a different path with a different lifecycle — it is a monitor
/// of the loaded model, mounted permanently above the chat — and adopting this
/// would change a screen that works and that has a layout test which has already
/// proven itself by failing. That is its own decision, not a default.
///
/// ## Three rules in here, all of them paid for on the A72
///
/// 1. **The method travels with the call.** `request(method, path)` and the
///    `get`/`post` wrappers, never a bare `_post` that someone reaches for with a
///    `GET` path. The route check on the server is `request.method == 'GET'`, so
///    a `POST` on a `GET`-only route falls through to the 404 arm, the console
///    catches it, and the failure presents itself as "the server is up and the
///    model is not loaded yet".
/// 2. **The status comes back with the body.** A refusal is data: `/v1/classify`
///    answers 422 with the model's own text for exactly the case where a decision
///    model ignored the contract, and that text is the only way to see what
///    happened. Throwing the status away as a transport error is what leaves a
///    panel blank where the answer should be.
/// 3. **The auth header is resolved per request, not once.** A stored key with
///    `useApiKey` toggled on while a console is open used to make every call
///    401 with nothing else on screen changing.
class ApiConsoleClient {
  ApiConsoleClient({
    required this.baseUrl,
    this.authHeaders = const {},
    this.authResolver,
    this.connectTimeout = const Duration(seconds: 5),
    this.defaultTimeout = const Duration(seconds: 90),
    this.throwOnError = false,
  });

  /// Where the server is. Empty means "not told yet", and a request on an empty
  /// base throws a message that says so rather than building `Uri.parse('/v1/…')`.
  final String baseUrl;

  /// Passed in by the caller when it already knows them — which is what lets a
  /// layout test build a console without standing up the GetX graph.
  final Map<String, String> authHeaders;

  /// Read **per request**, so a key toggled on while the console is open is
  /// picked up. The reason is a bug this file's clients used to have.
  ///
  /// A closure and not a `ServerController`: the shell has no business knowing
  /// about GetX, and the caller is the one that knows where the key lives. It is
  /// also what lets a layout test drive a console with no dependency container at
  /// all — pass `authHeaders` and the whole graph stays out of it.
  final Map<String, String> Function()? authResolver;

  final Duration connectTimeout;

  /// Long by default because the *compile* is the slow part: a 705 MB graph takes
  /// seconds of native time, and the load endpoint answers `202` before that work
  /// happens, so the real wait is on the follow-up poll rather than on the POST.
  final Duration defaultTimeout;

  /// Whether a non-2xx becomes a thrown [StateError] carrying the server's own
  /// message, instead of coming back in the body.
  ///
  /// **Per client, not per call, and the reason is that the two consoles want
  /// genuinely different things.** `LitertHeadConsole` wants an exception: every
  /// one of its call sites is `on Object catch (e) => _error = '$e'`, and that is
  /// how a refusal reaches the screen. `SystemOneConsole` wants the body: a
  /// `/v1/classify` 422 carries the decision model's own text, and that text is
  /// the answer to the question the user asked — throwing it away leaves a panel
  /// blank where the answer should be.
  ///
  /// Per client and not per call so a single console cannot mix the two policies
  /// halfway down a flow, which would be a screen where the same status code is
  /// sometimes an error and sometimes content.
  final bool throwOnError;

  Map<String, String> auth() {
    if (authHeaders.isNotEmpty) return authHeaders;
    return authResolver?.call() ?? const {};
  }

  /// Whether the server is answering, without deciding anything else.
  ///
  /// Two seconds throughout, because this runs on open and on every re-probe: a
  /// slow answer here is a display that takes a second to say "no". The endpoint
  /// is `capabilities` because it is the one that is 200 on a server with no
  /// model loaded — a probe that used a model-requiring endpoint reported the
  /// server as down whenever the model was not there.
  Future<bool> ping() async {
    if (baseUrl.isEmpty) return false;
    try {
      final client = HttpClient()..connectionTimeout = connectTimeout;
      final req = await client
          .getUrl(Uri.parse('$baseUrl/v1/server/capabilities'))
          .timeout(const Duration(seconds: 2));
      for (final e in auth().entries) {
        req.headers.set(e.key, e.value);
      }
      final res = await req.close().timeout(const Duration(seconds: 2));
      client.close();
      return res.statusCode == 200;
    } on Object {
      return false;
    }
  }

  /// One call. Returns the decoded body with `__status` folded in.
  ///
  /// **Does not throw on a non-200 by default.** The caller decides what a `422`
  /// means, and for a decision model it means the answer is on the screen. A
  /// 2xx-only helper is the wrong shape for an endpoint whose refusals carry
  /// evidence.
  ///
  /// The two decisions this method used to make — how to build the request and
  /// how to read the reply — are [apiPlan] and [apiReply], and they are **pure**.
  /// That is not tidiness. `flutter_test` replaces `HttpClient` with a stub that
  /// answers 400 to everything, so anything past this line cannot be tested in
  /// this harness at all, and the two things that can go wrong here (a `POST` on
  /// a `GET`-only route, a refusal thrown away) are both above it.
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic> body = const {},
    Duration? timeout,
  }) async {
    final plan = apiPlan(
      method: method,
      baseUrl: baseUrl,
      path: path,
      body: body,
      auth: auth(),
    );
    final client = HttpClient()..connectionTimeout = connectTimeout;
    final uri = Uri.parse(plan.uri);
    final req =
        method == 'GET' ? await client.getUrl(uri) : await client.postUrl(uri);
    req.headers.contentType = ContentType.json;
    for (final e in plan.headers.entries) {
      req.headers.set(e.key, e.value);
    }
    if (plan.payload != null) req.write(plan.payload!);
    final res = await req.close().timeout(timeout ?? defaultTimeout);
    final text = await res.transform(utf8.decoder).join();
    client.close();
    return apiReply(
      status: res.statusCode,
      text: text,
      throwOnError: throwOnError,
    );
  }

  Future<Map<String, dynamic>> get(String path, {Duration? timeout}) =>
      request('GET', path, timeout: timeout);

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic> body = const {},
    Duration? timeout,
  }) =>
      request('POST', path, body: body, timeout: timeout);
}

/// What a call is going to be, decided before any socket exists.
///
/// Pure, and separated from [ApiConsoleClient] because **`flutter_test` replaces
/// `HttpClient` with a stub that answers 400 to everything.** A real
/// `HttpServer` in a test reaches nothing: the client's own client is the one
/// that got swapped, so the test proves the stub answers, not that the code does.
/// Everything that can actually go wrong in a call is decided here instead, and
/// this is testable.
class ApiCallPlan {
  const ApiCallPlan({
    required this.method,
    required this.uri,
    this.headers = const {},
    this.payload,
  });

  final String method;

  /// Absolute, so a caller reading a failure sees where it went.
  final String uri;

  final Map<String, String> headers;

  /// Null on a `GET`, and that is not an accident: a `GET` with a body is a
  /// request the server is free to ignore, and a helper that writes one anyway
  /// hides a caller's mistake instead of showing it.
  final String? payload;

  @override
  String toString() =>
      '$method $uri${payload == null ? '' : ' +${payload!.length}B'}';
}

/// Build the call. Throws when there is no address, with a message that says so.
ApiCallPlan apiPlan({
  required String method,
  required String baseUrl,
  required String path,
  Map<String, dynamic> body = const {},
  Map<String, String> auth = const {},
}) {
  if (baseUrl.isEmpty) {
    throw StateError(
      'the API server has not reported an address yet — open Settings, API '
      'server, and start it',
    );
  }
  return ApiCallPlan(
    method: method,
    uri: '$baseUrl$path',
    headers: auth,
    // `encodeBody`, not `jsonEncode`: a head that produced a non-finite logit
    // makes `jsonEncode` throw, and the honest answer there names the number
    // JavaScript does not have.
    payload: method == 'GET' ? null : encodeBody(body),
  );
}

/// Read a reply, with the status folded into the body as `__status`.
///
/// Throws only when [throwOnError] and the status is neither 200 nor 202. **202
/// is a success here** and that is the load endpoint's whole contract: it
/// answers before the compile happens, so treating it as a refusal would make
/// every load look like a failure.
Map<String, dynamic> apiReply({
  required int status,
  required String text,
  bool throwOnError = false,
}) {
  // **A body that is not JSON is a body, not a crash.** `jsonDecode` throws a
  // `FormatException` whose message is "Unexpected character (at character 1)"
  // followed by the text — and a console that showed that instead of the text
  // would turn a proxy's `Bad Gateway` into a complaint about a character
  // nobody can act on. A parse failure therefore falls through to the raw text,
  // which is what the `error`-less branch below then reports.
  Map<String, dynamic> decoded = const {};
  final trimmed = text.trim();
  if (trimmed.isNotEmpty) {
    try {
      final parsed = jsonDecode(trimmed);
      if (parsed is Map<String, dynamic>) decoded = parsed;
    } on FormatException {
      decoded = const {};
    }
  }
  if (throwOnError && status != 200 && status != 202) {
    throw StateError('${decoded['error'] ?? text}'.trim());
  }
  return {...decoded, '__status': status};
}

/// The status out of a body that [ApiConsoleClient.request] folded in.
int statusOf(Map<String, dynamic> body) {
  final s = body['__status'];
  return s is int ? s : 200;
}

/// The body without the bookkeeping key, for showing.
Map<String, dynamic> payloadOf(Map<String, dynamic> body) {
  final out = Map<String, dynamic>.of(body)..remove('__status');
  return out;
}

// ── the look ────────────────────────────────────────────────────────────────

/// The colours every one of these consoles paints with.
///
/// One source, because two screens that each pick `0xFF1C1C1E` for a card and
/// `0xFF2C2C2E` for a field are two screens that have to be edited in two places
/// to become one thing — and the whole reason this file exists is that they
/// should be one thing.
class ConsolePalette {
  const ConsolePalette(this.isDark)
      : card = null,
        field = null;

  /// A palette built from colours a caller **already has in hand**.
  ///
  /// This exists so a screen that already resolved its own colours can adopt the
  /// shared widgets without being refactored to thread a palette through every
  /// signature to get there. `LitertHeadConsole` has carried `(isDark, field,
  /// card)` as three parameters through five panels, and changing all of them to
  /// reach one shared widget would be a larger and riskier diff than the thing
  /// it buys.
  ///
  /// **Brightness is derived from the card's own luminance**, and not passed in,
  /// because a caller that has the colour can be asked for less. Every one of
  /// these cards is either `0xFF1C1C1E` or white, so the estimate is not a
  /// heuristic doing a hard job — and it removes the temptation to pass a
  /// `isDark` that is a lie, which the three-argument form invited.
  factory ConsolePalette.explicit(Color card, Color field) => ConsolePalette._(
        isDark: ThemeData.estimateBrightnessForColor(card) == Brightness.dark,
        card: card,
        field: field,
      );

  const ConsolePalette._({
    required this.isDark,
    required this.card,
    required this.field,
  });

  final bool isDark;

  /// Null when the palette was made from brightness alone, in which case the
  /// getters below supply the value. Non-null when a caller brought its own.
  final Color? card;
  final Color? field;

  Color get background =>
      isDark ? const Color(0xFF0F0F11) : const Color(0xFFF7F7F9);

  Color get resolvedCard =>
      card ?? (isDark ? const Color(0xFF1C1C1E) : Colors.white);

  Color get resolvedField =>
      field ?? (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7));

  Color get muted => AppColors.textMuted;

  static ConsolePalette of(BuildContext context) =>
      ConsolePalette(Theme.of(context).brightness == Brightness.dark);
}

/// A titled block. The unit both consoles build their screens from.
Widget consoleCard({
  required ConsolePalette palette,
  required String title,
  required Widget child,
  String? note,
  Widget? trailing,
  EdgeInsets padding = const EdgeInsets.all(14),
  double radius = 14,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: padding,
    decoration: BoxDecoration(
      color: palette.resolvedCard,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title,
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            if (trailing != null) trailing,
          ],
        ),
        const SizedBox(height: 8),
        child,
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(note,
              style: GoogleFonts.inter(fontSize: 11, color: palette.muted)),
        ],
      ],
    ),
  );
}

/// A text field on the console's field colour, with no border of its own.
Widget consoleField({
  required ConsolePalette palette,
  required TextEditingController controller,
  String? hint,
  String? label,
  int maxLines = 1,
  int minLines = 1,
  bool mono = false,
  TextStyle? style,
  ValueChanged<String>? onChanged,
}) {
  final text = TextField(
    controller: controller,
    maxLines: maxLines,
    minLines: minLines,
    onChanged: onChanged,
    style: style ??
        (mono
            ? GoogleFonts.jetBrainsMono(fontSize: 12)
            : GoogleFonts.inter(fontSize: 13)),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: (mono
              ? GoogleFonts.jetBrainsMono(fontSize: 12)
              : GoogleFonts.inter(fontSize: 13))
          .copyWith(color: palette.muted),
      border: InputBorder.none,
    ),
  );
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (label != null) ...[
        Text(label,
            style: GoogleFonts.inter(fontSize: 11, color: palette.muted)),
        const SizedBox(height: 4),
      ],
      Container(
        width: double.infinity,
        color: palette.resolvedField,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: text,
      ),
    ],
  );
}

/// A block of fixed-width text — logits, a tensor listing, a refusal.
///
/// [radius] exists because the two consoles disagreed: the System One window
/// wanted square corners and the `.tflite` console a 8 dp radius, and the first
/// version of this widget had neither parameter, so adopting it would have meant
/// one of them changing how it looks. The union of both is smaller than the
/// duplication it replaces.
Widget consoleMono({
  required ConsolePalette palette,
  required String text,
  double fontSize = 11,
  int? maxHeight,
  double radius = 0,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    constraints: maxHeight == null
        ? null
        : BoxConstraints(maxHeight: maxHeight.toDouble()),
    // **The colour lives inside the `decoration`, never in `color:` beside it.**
    // A `Container` asserts that it was given both — "Cannot provide both a color
    // and a decoration" — and adding [radius] here put the colour in both places.
    // It threw on the `.tflite` console's first paint, on the device, and only
    // there: this widget's own test builds it through a `Material` with a
    // `Column`, and an assertion thrown inside a `Container`'s constructor
    // happens before layout, so the test that would have caught it was not the
    // one running. Which is the point of the device.
    decoration: BoxDecoration(
      color: palette.resolvedField,
      borderRadius: radius == 0 ? null : BorderRadius.circular(radius),
    ),
    child: SingleChildScrollView(
      child: Text(text,
          style: GoogleFonts.jetBrainsMono(
              fontSize: fontSize, color: AppColors.textPrimary)),
    ),
  );
}

/// A failure, in red, with an icon.
Widget consoleErrorCard(String message) {
  return _tinted(
    message: message,
    color: AppColors.error,
    icon: Icons.error_outline,
  );
}

/// A confirmation, deliberately **not** the red card.
///
/// Both consoles do three things on purpose and put all three in the same red box
/// would make the app look broken every time it worked. An unload that freed a
/// head is not an error, and the difference belongs in how it is shown.
Widget consoleNoticeCard(String message) {
  return _tinted(
    message: message,
    color: AppColors.success,
    icon: Icons.check_circle_outline,
  );
}

/// A warning attached to a field, in amber.
Widget consoleProblem(String message) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.warning_amber_rounded,
          size: 15, color: AppColors.warning),
      const SizedBox(width: 6),
      Expanded(
        child: Text(message,
            style: GoogleFonts.inter(fontSize: 11, color: AppColors.warning)),
      ),
    ],
  );
}

/// An aside, in the muted colour, under a card or a field.
Widget consoleNote(String text, {Color? color, double fontSize = 11}) {
  return Text(text,
      style: GoogleFonts.inter(
          fontSize: fontSize, color: color ?? AppColors.textMuted));
}

Widget _tinted({
  required String message,
  required Color color,
  required IconData icon,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message,
              style: GoogleFonts.inter(fontSize: 12, color: color)),
        ),
      ],
    ),
  );
}

/// A row of actions, in a `Wrap`.
///
/// **A `Wrap`, not a `Row`, and this is the fifth time in this repo.** A `Row` of
/// an icon plus an English label with nothing limiting it is the exact shape of
/// the three overflows already paid for, and the fix that generalises is not to
/// add an `Expanded` to each button but to stop assuming they fit. `Wrap` is also
/// the right widget because they are alternatives, and stacking them says that in
/// a way side-by-side buttons do not.
Widget consoleActions({
  required List<Widget> children,
  double spacing = 8,
  WrapCrossAlignment crossAxisAlignment = WrapCrossAlignment.center,
}) {
  return Wrap(
    spacing: spacing,
    runSpacing: spacing,
    crossAxisAlignment: crossAxisAlignment,
    children: children,
  );
}

/// `void` in a `Future`, so a deliberately un-awaited call reads as deliberate.
void ignoreFuture(Future<void> f) {}
