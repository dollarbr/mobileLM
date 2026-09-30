import 'dart:math';

/// Whether the local API server requires a key, and which one.
///
/// Pure on purpose. This is a migration rule, and a migration rule is exactly
/// the kind of thing that is wrong silently: get it backwards and the server
/// comes up on `0.0.0.0` with no key and nothing says so. Putting it in a
/// plain function makes the three cases assertable without a device, a Hive
/// box, or a socket.
///
/// ## Why it is on by default now, and it was not before
///
/// The server binds `InternetAddress.anyIPv4` — all interfaces, not just
/// loopback — so it has always been reachable from the local network. Until
/// this release that was a smaller problem than it sounds, because the worst a
/// caller could do without a key was spend some CPU asking for tokens. Nobody
/// can get that far in a way you would not notice.
///
/// The model-management endpoints change the answer. `POST /v1/models/download`
/// writes gigabytes to the device, `/v1/models/load` and `/unload` change what
/// every other client on the network is talking to, and `GET /v1/models/local`
/// lists what is on the phone. An open server on a café Wi-Fi went from "costs
/// some battery" to "can use your phone as its storage and change its state",
/// which is the point at which a default of `off` stops being defensible.
///
/// ## The one case that stays off
///
/// A stored key with `useApiKey` explicitly `false` is a person who turned it
/// off after reading it. That choice is kept, including across upgrades —
/// silently re-enabling it would be the app overriding a security decision the
/// user made on purpose, and there is no way to tell that apart from a bug
/// afterwards. What changes is only the case where **no key has ever been
/// generated**, which is the install that is actually exposed.

/// What the boot path should do with what is in storage.
class ServerAuthDecision {
  const ServerAuthDecision({
    required this.apiKey,
    required this.requireKey,
    required this.generated,
  });

  /// The key to store and to hand to the server. Never empty.
  final String apiKey;

  /// Whether the server should reject requests without a matching bearer.
  final bool requireKey;

  /// True when [apiKey] was just generated and has to be written to storage.
  final bool generated;

  @override
  String toString() => 'ServerAuthDecision(requireKey: $requireKey, '
      'generated: $generated, key: ${apiKey.isEmpty ? '<empty>' : '<set>'})';
}

/// Alphabet for a generated key.
///
/// URL-safe and unambiguous, because this string gets typed into `curl` headers
/// and into an OpenAI client on another machine. No `+`/`/` (which need
/// escaping in a header value), no `=` (padding, and it reads as an encoding
/// artefact), and none of the characters that look like each other in a
/// terminal — no `0`/`O`, no `1`/`l`/`I` — because a mistyped key fails as
/// `401 Unauthorized` with nothing to say which character was wrong.
const _alphabet = 'abcdefghijkmnopqrstuvwxyz23456789';

/// A fresh key.
///
/// 32 characters from a 32-character alphabet is 160 bits, which is past the
/// point where brute force matters for a device on a home network. The old
/// scheme was 24 hex bytes, also fine and still accepted for keys already
/// stored; this one is only about not generating characters that get
/// mistyped on the way to a `curl` command.
String generateServerApiKey([int length = 32]) {
  final random = Random.secure();
  return List.generate(
      length, (_) => _alphabet[random.nextInt(_alphabet.length)]).join();
}

/// The rule. [storedKey] and [storedUseKey] are whatever Hive returned, so
/// `null` means "never written".
ServerAuthDecision decideServerAuth({
  String? storedKey,
  bool? storedUseKey,
  String Function([int]) generator = generateServerApiKey,
}) {
  final existing = storedKey?.trim() ?? '';

  // No key has ever existed. Generate one and turn the requirement on, which
  // is the whole point of the change: this is the install that is currently
  // open on every interface.
  if (existing.isEmpty) {
    return ServerAuthDecision(
      apiKey: generator(),
      requireKey: true,
      generated: true,
    );
  }

  // A key exists. `null` here means the requirement was never written, which
  // predates this release and predates the risk, so it now defaults to on.
  // An explicit `false` is a person who turned it off on purpose, and it is
  // left alone.
  return ServerAuthDecision(
    apiKey: existing,
    requireKey: storedUseKey ?? true,
    generated: false,
  );
}

/// Compare two secrets without leaking where they differ.
///
/// `a == b` in Dart returns as soon as it finds a difference, so the time it
/// takes tells a caller how many leading characters were right. On a home
/// network that is close to theoretical — an attacker would need thousands of
/// requests to get a signal out of a 160-bit key they are also not allowed to
/// guess. It is here because the cost is four lines and the alternative is a
/// comment explaining why the obvious thing was not done.
///
/// Lengths are compared first and the loop runs over the shorter one, so a
/// wrong-length key does not even enter the loop. That is not a leak here
/// either: the key length is a constant of this app, not a secret.
bool constantTimeEquals(String? a, String? b) {
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// Check an `Authorization` header against the configured key.
///
/// The scheme is matched case-insensitively because `bearer` is a registered
/// scheme name and HTTP header values are not case-sensitive in the auth
/// scheme token; the token itself is not, and is compared exactly.
bool authorizationMatches(String? header, String? expectedKey) {
  if (header == null) return false;
  final trimmed = header.trim();
  final space = trimmed.indexOf(' ');
  if (space <= 0) return false;
  final scheme = trimmed.substring(0, space);
  if (scheme.toLowerCase() != 'bearer') return false;
  return constantTimeEquals(trimmed.substring(space + 1).trim(), expectedKey);
}
