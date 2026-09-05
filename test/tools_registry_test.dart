import 'package:flutter_test/flutter_test.dart';

import 'package:mobilelm/services/tools/builtin_tools.dart';
import 'package:mobilelm/services/tools/tool_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ToolRegistry registry;
  setUp(() => registry = buildDefaultToolRegistry());

  test('unknown tool names come back as an error, not a throw', () async {
    final out = await registry.execute('nope', {});
    expect(out, startsWith('Error: no tool named "nope"'));
    expect(out, contains('calculate'));
  });

  test('a safe tool runs without any confirmation', () async {
    final out = await registry.execute('calculate', {'expression': '2+3'});
    expect(out, contains('5'));
  });

  test('a write tool is gated behind confirmation', () async {
    final out = await registry.execute('clipboard_write', {'text': 'x'});
    expect(out, ToolRegistry.confirmMarker);
  });

  test('the confirmed call reaches the tool (gate passed)', () async {
    // The clipboard platform channel is absent under flutter_test; execute
    // catches that and reports it as a normal error. Either way the marker
    // must be gone — its absence is what proves the gate opened.
    final out = await registry
        .execute('clipboard_write', {'text': 'x'}, confirmed: true);
    expect(out, isNot(ToolRegistry.confirmMarker));
  });

  test('a privileged tool is gated even though it only reads', () async {
    final registry = ToolRegistry([
      Tool(
        name: 'peek',
        description: 'reads something privileged',
        risk: ToolRisk.privileged,
        run: (_) async => 'data',
      ),
    ]);

    // Shell privilege has no "just looking" mode: logcat carries other apps'
    // content, so a read confirms exactly like a write does.
    expect(await registry.execute('peek', {}), ToolRegistry.confirmMarker);
    expect(await registry.execute('peek', {}, confirmed: true), 'data');
  });

  test('preview renders the command a confirmation dialog should show', () {
    final tool = Tool(
      name: 'peek',
      description: 'x',
      risk: ToolRisk.privileged,
      preview: (args) => 'getprop ${args['key']}',
      run: (_) async => '',
    );

    expect(tool.preview!({'key': 'ro.build.id'}), 'getprop ro.build.id');
  });
}
