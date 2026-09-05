import 'package:flutter_test/flutter_test.dart';

import 'package:mobilelm/services/privileged_service.dart';
import 'package:mobilelm/services/tools/privileged_tools.dart';

void main() {
  test('the block is empty unless Shizuku is ready', () {
    // A model told about a tool that then refuses to run wastes a turn
    // arguing with itself — the same reasoning the registry already applies
    // to the enabled filter.
    for (final s in ShizukuState.values) {
      final tools = s == ShizukuState.ready
          ? buildPrivilegedTools(run: (_) async => '')
          : const [];
      expect(tools.isEmpty, s != ShizukuState.ready, reason: '$s');
    }
  });

  test('every state that is not ready reports what the user must do', () {
    expect(ShizukuState.notInstalled.hint, contains('install'));
    expect(ShizukuState.stopped.hint, contains('Start'));
    expect(ShizukuState.needsPermission.hint, contains('permission'));
    expect(ShizukuState.ready.hint, isEmpty);
  });
}
