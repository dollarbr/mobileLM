// The header an in-app caller has to send to the local API.
//
// Why this has a test at all: `/v1/**` has been behind `_isAuthorized` since the
// API-key work, and the in-app consoles called it with no `Authorization` header
// whatsoever. `useApiKey` shipped defaulting to `false`, so nothing broke until
// somebody turned the key on — at which point the encoder console's probe read
// "server not running" against a server that was running and listening, and its
// run button went dead.
//
// The symptom points at the server. The cause is one missing header in the
// caller, and it is invisible until exactly the moment somebody uses the feature
// the key exists for.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/utils/server_auth.dart';

void main() {
  group('localApiHeaders', () {
    test('sends nothing when the server is not asking for a key', () {
      // The default state. A header here would be harmless but wrong: it would
      // make the app depend on a key it does not need, so turning the feature
      // off would have to also mean "no header" or nothing works.
      expect(
        localApiHeaders(useApiKey: false, apiKey: 'abc123'),
        isEmpty,
      );
    });

    test('sends a bearer token when the key is on', () {
      final h = localApiHeaders(useApiKey: true, apiKey: 'abc123');
      expect(h.length, 1);
      expect(h[HttpHeaders.authorizationHeader], 'Bearer abc123');
    });

    // The case that is easy to leave out. `requireKey` can be true with an empty
    // key after a restore, and the server treats an empty expected key as "no
    // key required" (`if (key == null || key.isEmpty) return true`). Sending
    // `Bearer ` would be a malformed header against a server that is asking for
    // nothing, which turns a working configuration into a 401.
    test('sends nothing when the key is on but blank', () {
      expect(localApiHeaders(useApiKey: true, apiKey: ''), isEmpty);
      expect(localApiHeaders(useApiKey: true, apiKey: '   '), isEmpty);
    });

    // A pasted key carries a newline. `trim()` is not tidiness here: the header
    // would be written with the newline in it, and the comparison on the server
    // side trims too, so it would *work* — while every `curl` copied out of
    // Settings would carry the same newline and behave differently depending on
    // the shell. Better to normalise once, in one place.
    test('trims the key, so a pasted one still matches', () {
      final h = localApiHeaders(useApiKey: true, apiKey: '  abc123\n');
      expect(h[HttpHeaders.authorizationHeader], 'Bearer abc123');
    });

    test('what it builds is what the server accepts', () {
      // Round-trip against the real check, not a copy of it. The two sides drift
      // — the scheme case, the surrounding spaces — and this is the only
      // assertion that notices when they do.
      final h = localApiHeaders(useApiKey: true, apiKey: 's3cret-key');
      expect(
        authorizationMatches(
          h[HttpHeaders.authorizationHeader],
          's3cret-key',
        ),
        isTrue,
      );
    });

    test('the scheme is matched case-insensitively, the token is not', () {
      // Both halves are the server's behaviour, asserted here so a change to
      // either is a failing test rather than a 401 on someone's phone.
      expect(
        authorizationMatches('bearer s3cret-key', 's3cret-key'),
        isTrue,
      );
      expect(
        authorizationMatches('BEARER s3cret-key', 's3cret-key'),
        isTrue,
      );
      expect(
        authorizationMatches('Bearer s3cret-KEY', 's3cret-key'),
        isFalse,
      );
      expect(
        authorizationMatches('Bearer wrong-key', 's3cret-key'),
        isFalse,
      );
    });
  });
}