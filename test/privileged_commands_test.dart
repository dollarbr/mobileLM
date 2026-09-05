import 'package:flutter_test/flutter_test.dart';

import 'package:mobilelm/services/tools/privileged_commands.dart';

void main() {
  group('argument validation', () {
    // A package name reaching the shell unchecked is arbitrary execution as
    // whatever uid Shizuku holds. Narrow tools are only safer than a free
    // shell because of these rules, so each metacharacter gets its own case.
    const injections = [
      'foo; rm -rf /data',
      'foo | cat',
      'foo && id',
      r'foo$(id)',
      'foo`id`',
      'foo\nid',
      'foo id',
    ];

    for (final bad in injections) {
      test('a package name containing ${bad.substring(3)} is rejected', () {
        expect(() => appInfoArgv(bad), throwsA(isA<ArgError>()));
        expect(() => grantArgv(bad, 'android.permission.CAMERA'),
            throwsA(isA<ArgError>()));
      });
    }

    test('a well-formed package name is accepted', () {
      expect(appInfoArgv('com.foo.bar_1'),
          ['dumpsys', 'package', 'com.foo.bar_1']);
    });

    test('the settings namespace is a closed set', () {
      expect(readSettingArgv('secure', 'android_id'),
          ['settings', 'get', 'secure', 'android_id']);
      expect(() => readSettingArgv('bogus', 'k'), throwsA(isA<ArgError>()));
    });

    test('a setting value is never validated, only kept out of a shell string',
        () {
      // The value is free text on purpose — a wallpaper path or a DNS name can
      // contain anything. Safety comes from argv, not from a pattern.
      expect(
        writeSettingArgv('global', 'private_dns_specifier', 'dns.foo; rm -rf /'),
        [
          'settings',
          'put',
          'global',
          'private_dns_specifier',
          'dns.foo; rm -rf /'
        ],
      );
    });

    test('logcat lines are clamped to 500', () {
      expect(logcatArgv(lines: 99999), contains('500'));
      expect(logcatArgv(lines: 0), contains('1'));
    });

    test('list_apps only accepts the three known scopes', () {
      expect(listAppsArgv(only: 'user'), ['pm', 'list', 'packages', '-3']);
      expect(listAppsArgv(only: 'system'), ['pm', 'list', 'packages', '-s']);
      expect(listAppsArgv(only: 'all'), ['pm', 'list', 'packages']);
      expect(() => listAppsArgv(only: 'weird'), throwsA(isA<ArgError>()));
    });
  });

  group('output cap', () {
    test('short output is untouched', () {
      expect(capOutput('hello'), 'hello');
    });

    test('long output is cut and says so', () {
      // dumpsys package runs past 1 MB and LiteRT is pinned at ctx 4096, so an
      // uncapped result does not waste the turn, it ends it.
      final huge = 'x' * 100000;
      final out = capOutput(huge);

      expect(out.length, lessThan(8192 + 64));
      expect(out, contains('truncated'));
      expect(out, contains('KB omitted'));
    });
  });
}
