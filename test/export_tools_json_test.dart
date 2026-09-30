import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/services/tools/builtin_tools.dart';

/// Exports the app's own tool catalogue in the shape a non-llama.cpp runtime
/// wants, so a third-party engine can be handed the same 24 tools the chat sees.
///
/// This exists because the catalogue lives in Dart and the engines do not. Needle
/// takes `--tools tools.json` as "the functions the assistant may call, as a JSON
/// array"; the chat instead feeds the model a rendered `- name(k="...") — text`
/// list. Those are the same information in two shapes, and the second one cannot
/// be handed to a C API. Rather than retyping 24 schemas — which is how a
/// catalogue and its export drift apart within a week — this reads the real
/// registry.
///
/// It is a test rather than a script because `buildDefaultToolRegistry` is
/// importable from `test/` with no service registry, no Hive and no platform
/// channel, which a `tool/*.dart` entry point would not be.
void main() {
  test('export the catalogue for a foreign runtime', () {
    final registry = buildDefaultToolRegistry();
    final tools = registry.all.toList();

    // OpenAI's function shape, which is what an OpenAI-adjacent engine expects
    // and what the app's own `/v1/chat/completions` would accept if it ever sent
    // `tools` rather than rendering the catalogue into the prompt.
    //
    // `parameters` in this app is `Map<String, String>` — argument name to what it
    // means — with no types, so there is nothing to put in a JSON Schema's
    // `properties` beyond the name. That is honest: inventing `{"type": "string"}`
    // for every argument would assert a contract the app does not have, and a
    // model that fills an argument with a number because the schema said `string`
    // is a worse failure than one that guesses from the description.
    final json = [
      for (final t in tools)
        {
          'type': 'function',
          'function': {
            'name': t.name,
            'description': t.description,
            'parameters': {
              'type': 'object',
              'properties': {
                for (final p in t.parameters.entries) p.key: {'description': p.value},
              },
            },
          },
        },
    ];

    // `build/`, not a hardcoded /tmp: this test runs in CI too, and a test that
    // writes outside the repo is a test that passes locally and surprises someone
    // whose filesystem is arranged differently.
    final out = File('build/tools-export.json')..createSync(recursive: true);
    out.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));

    // The assertions, because a report is not a test. What they pin is the
    // property that decides whether a small model can carry this catalogue: the
    // exported text has to stay small enough to fit a small context. 17 tools in
    // 4 KB is the fact worth noticing; a 24th tool with a paragraph-long
    // description is how it stops being true, and nothing else would say so.
    // What the export costs, because the thing that decides whether a small
    // model can carry a large catalogue is the size of the schemas, and that is
    // not knowable without counting.
    final bytes = const JsonEncoder().convert(json).length;
    var descriptionChars = 0, parameterChars = 0;
    for (final t in tools) {
      descriptionChars += t.description.length;
      for (final p in t.parameters.values) {
        parameterChars += p.length;
      }
    }

    // The assertions, because a report is not a test. What they pin is the
    // property that decides whether a small-context runtime can hold the whole
    // catalogue: 17 tools in 4 KB is the fact worth noticing, and a 24th tool with
    // a paragraph-long description is how it stops being true. Nothing else would
    // say so.
    expect(tools.length, greaterThanOrEqualTo(17));
    expect(bytes, lessThan(16384),
        reason: 'tool schemas grew past 16 KB of JSON; a small-context runtime '
            'can no longer hold the whole catalogue');
    for (final entry in json) {
      final fn = entry['function'] as Map<String, dynamic>;
      expect(fn['name'], isA<String>());
      expect((fn['description'] as String).length, lessThan(400),
          reason: '${fn['name']} has a long description');
    }

    //ignore: avoid_print
    print('  ${tools.length} tools · $bytes bytes of JSON');
    //ignore: avoid_print
    print('  descriptions: $descriptionChars chars · parameters: $parameterChars chars');
    //ignore: avoid_print
    print('  total text: ${descriptionChars + parameterChars} chars '
        '(~${((descriptionChars + parameterChars) / 3.5).round()} tokens at 3.5 chars/token)');
    //ignore: avoid_print
    print('  written to ${out.path}');
  });
}
