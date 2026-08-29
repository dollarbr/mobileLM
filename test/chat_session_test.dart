import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/models/chat_session.dart';

void main() {
  test('a chat keeps its project unless asked to drop it', () {
    final bound = ChatSession(id: 'a', projectPath: 'my-site');

    // A null projectPath means "leave it alone", which is why unbinding needs
    // its own flag: renaming a chat must not silently orphan its files.
    expect(bound.copyWith(title: 'Renamed').projectPath, 'my-site');
    expect(bound.copyWith(projectPath: 'other').projectPath, 'other');
    expect(bound.copyWith(clearProject: true).projectPath, isNull);
  });

  test('the project survives a round trip through storage', () {
    final session = ChatSession(id: 'a', projectPath: 'my-site');
    expect(ChatSession.fromMap(session.toMap()).projectPath, 'my-site');

    final loose = ChatSession(id: 'b');
    expect(ChatSession.fromMap(loose.toMap()).projectPath, isNull);
  });
}
