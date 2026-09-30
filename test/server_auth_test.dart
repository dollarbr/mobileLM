// Whether the local API server requires a key.
//
// This is a migration rule, and migration rules are the kind of thing that is
// wrong silently. There are three cases and only one of them is obvious:
//
//   - no key has ever been generated  -> generate one, require it (this is the
//     install that is currently open on every interface)
//   - a key exists, the flag was never written -> require it (predates both the
//     risk and this change)
//   - a key exists, the flag is explicitly false -> leave it off, because that
//     is a person who read it and chose that
//
// The third case is the one worth arguing about, so it has a test that says so
// in as many words: silently re-enabling auth would be the app overriding a
// security decision the user made on purpose, and after the fact there is no
// way to tell that apart from a bug.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/utils/server_auth.dart';

void main() {
  String fixed([int length = 32]) => 'k' * length;

  group('a phone that never had a key is the one that is exposed', () {
    test('generates a key and turns the requirement on', () {
      final d = decideServerAuth(storedKey: null, storedUseKey: null);
      expect(d.apiKey, isNotEmpty);
      expect(d.requireKey, isTrue);
      expect(d.generated, isTrue, reason: 'the caller has to persist it');
    });

    test('a blank or whitespace key counts as no key', () {
      // Hive hands back whatever was written, and a field the user cleared is
      // an empty string, not a null. Treating that as "has a key" would leave
      // `requireKey: true` with an empty key, and an empty key is what the
      // server reads as "auth is off" — so the app would show the toggle on
      // while the server was wide open. The two would disagree.
      for (final blank in ['', '   ', '\n', '\t']) {
        final d = decideServerAuth(storedKey: blank, storedUseKey: false);
        expect(d.generated, isTrue, reason: 'blank key: ${blank.length} chars');
        expect(d.apiKey, isNotEmpty);
        expect(d.requireKey, isTrue);
      }
    });

    test('the generated key is not the caller-supplied generator reused', () {
      // Two calls, two different keys. A generator that returned a constant
      // would satisfy every other test in this file and be useless.
      final a = decideServerAuth();
      final b = decideServerAuth();
      expect(a.apiKey, isNot(b.apiKey));
    });
  });

  group('an existing key is kept, and a deliberate opt-out is respected', () {
    test('keeps the stored key byte for byte', () {
      // The whole point of storing it. Trimming it here would silently change
      // the credential a client is holding.
      final d = decideServerAuth(storedKey: 'abc123', storedUseKey: true);
      expect(d.apiKey, 'abc123');
      expect(d.generated, isFalse, reason: 'nothing new to persist');
    });

    test('a key with no stored flag now requires auth', () {
      // The flag key was written after the key, so a device can have one
      // without the other. Defaulting that to on is the change.
      final d = decideServerAuth(storedKey: 'abc123', storedUseKey: null);
      expect(d.requireKey, isTrue);
      expect(d.apiKey, 'abc123');
    });

    test('an explicit opt-out stays off, with the key still in place', () {
      // Not "with no key" — the key is kept so turning it back on does not
      // have to generate a new one and break whatever the user had wired up.
      final d = decideServerAuth(storedKey: 'abc123', storedUseKey: false);
      expect(d.requireKey, isFalse);
      expect(d.apiKey, 'abc123');
      expect(d.generated, isFalse);
    });
  });

  group('generated keys are typeable into a curl header', () {
    test('never contains a character that needs escaping', () {
      // The key ends up in `Authorization: Bearer <key>` on another machine,
      // often typed by hand from this screen. `+`, `/` and `=` in a header
      // value are an escaping problem; the first two are also the ones people
      // fat-finger.
      for (var i = 0; i < 200; i++) {
        final k = generateServerApiKey();
        expect(k, matches(RegExp(r'^[a-z2-9]+$')),
            reason: 'unexpected character in $k');
      }
    });

    test('omits the characters that look alike in a terminal', () {
      // No 0/O, no 1/l/I. A mistyped key comes back as `401 Unauthorized` with
      // nothing saying which character was wrong, so the cost of a mistake is a
      // debugging session.
      var all = '';
      for (var i = 0; i < 100; i++) {
        all += generateServerApiKey();
      }
      for (final forbidden in ['0', 'O', '1', 'l', 'I']) {
        expect(all.contains(forbidden), isFalse, reason: 'has "$forbidden"');
      }
    });

    test('has enough entropy to not be a lookup problem', () {
      // 32 characters from a 32-character alphabet is 160 bits. The test is
      // not "is it 160 bits" — it is "is it long enough that a collision
      // between two keys generated on two phones is not a thing to think
      // about".
      expect(generateServerApiKey().length, 32);
      expect(generateServerApiKey(64).length, 64);
    });

    test('the injected generator is the one that is used', () {
      // So the rule can be tested without depending on real randomness.
      final d = decideServerAuth(generator: fixed);
      expect(d.apiKey, fixed());
    });
  });

  group('comparing a key does not leak where it differs', () {
    test('equal strings match', () {
      expect(constantTimeEquals('abc', 'abc'), isTrue);
    });

    test('a difference anywhere is a mismatch', () {
      expect(constantTimeEquals('abc', 'abd'), isFalse);
      expect(constantTimeEquals('abc', 'aBc'), isFalse);
      expect(constantTimeEquals('abc', 'abcd'), isFalse);
      expect(constantTimeEquals('abcd', 'abc'), isFalse);
      expect(constantTimeEquals('', 'a'), isFalse);
    });

    test('null on either side is a mismatch, not a crash', () {
      expect(constantTimeEquals(null, 'abc'), isFalse);
      expect(constantTimeEquals('abc', null), isFalse);
      expect(constantTimeEquals(null, null), isFalse);
    });

    test('unicode is compared by code unit, like any other string', () {
      // Dart strings are UTF-16; `abc` and `abç` are different lengths and must
      // not be equal. A comparison that iterated runes instead would make
      // `á` and `a` differ in length handling.
      expect(constantTimeEquals('abc', 'abç'), isFalse);
      expect(constantTimeEquals('abç', 'abç'), isTrue);
    });
  });

  group('the Authorization header', () {
    const key = 'abcdefgh';

    test('accepts the documented form', () {
      expect(authorizationMatches('Bearer $key', key), isTrue);
    });

    test('accepts the scheme in any case, because HTTP allows it', () {
      // `bearer` is a registered scheme name and the scheme token of an
      // auth-params field is case-insensitive. A client that sends `bearer`
      // and gets a 401 is a client that works everywhere else.
      expect(authorizationMatches('bearer $key', key), isTrue);
      expect(authorizationMatches('BEARER $key', key), isTrue);
      expect(authorizationMatches('BeArEr $key', key), isTrue);
    });

    test('tolerates whitespace where a header would have it', () {
      expect(authorizationMatches('Bearer   $key  ', key), isTrue);
    });

    test('rejects the wrong scheme', () {
      expect(authorizationMatches('Basic $key', key), isFalse);
      expect(authorizationMatches('$key', key), isFalse);
      expect(authorizationMatches(key, key), isFalse);
    });

    test('rejects a wrong or missing token', () {
      expect(authorizationMatches('Bearer wrong', key), isFalse);
      expect(authorizationMatches('Bearer ', key), isFalse);
      expect(authorizationMatches('', key), isFalse);
      expect(authorizationMatches(null, key), isFalse);
    });

    test('rejects a token that merely contains the key', () {
      // The failure a substring check would have: `Bearer x<key>` must not
      // pass. This is why the header is split and the token compared whole.
      expect(authorizationMatches('Bearer x$key', key), isFalse);
      expect(authorizationMatches('Bearer ${key}x', key), isFalse);
    });
  });
}
