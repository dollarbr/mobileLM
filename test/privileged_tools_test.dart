import 'package:flutter_test/flutter_test.dart';

import 'package:mobilelm/services/tools/privileged_tools.dart';
import 'package:mobilelm/services/tools/tool_registry.dart';

void main() {
  late List<List<String>> ran;
  late List<Tool> tools;

  setUp(() {
    ran = [];
    tools = buildPrivilegedTools(run: (argv) async {
      ran.add(argv);
      return 'ok';
    });
  });

  Tool byName(String n) => tools.firstWhere((t) => t.name == n);

  test('every privileged tool is risk privileged and has a preview', () {
    expect(tools, hasLength(8));
    for (final t in tools) {
      expect(t.risk, ToolRisk.privileged, reason: t.name);
      expect(t.preview, isNotNull, reason: t.name);
    }
  });

  test('preview shows exactly the command that run receives', () async {
    final tool = byName('read_setting');
    final args = {'namespace': 'secure', 'key': 'android_id'};

    final shown = tool.preview!(args);
    await tool.run(args);

    // If these drift the user approves one thing and another executes.
    expect(ran.single.join(' '), shown);
  });

  test('a rejected argument comes back as an error, never as a command',
      () async {
    final out = await byName('app_info').run({'package': 'foo; rm -rf /'});

    expect(out, startsWith('Error:'));
    expect(ran, isEmpty);
  });

  test('results are capped before reaching the model', () async {
    final big = buildPrivilegedTools(run: (_) async => 'y' * 100000);
    final out = await big.firstWhere((t) => t.name == 'get_logcat').run({});

    expect(out, contains('truncated'));
    expect(out.length, lessThan(8192 + 64));
  });
}
