import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/core/constants.dart';

/// The two catalogue mistakes this repo has already paid for, plus the one the
/// encoder batch was nearly about to add.
///
/// The general rule from `AGENTS.md` is that a bad catalogue entry has no
/// symptom other than the download, and that a 404 shows up only at download
/// time. The encoder entries add a second, quieter failure of the same shape: a
/// GGUF that downloads fine, loads fine, and produces nothing. `jina-reranker-
/// v1-tiny-en` is 36 MB, half a second, and no output at all — the conversion
/// put the head at `cls.weight` where llama.cpp looks for `cls.output`. Nothing
/// in the app can check that from Dart, which is what `tool/gguf-screen.py` is
/// for; what Dart *can* check is that the entry is complete and not a duplicate
/// of another one, and that is what this file does.
void main() {
  final encoders = AppConstants.encoderModels;

  group('the encoder catalogue', () {
    test('is not empty, and every entry is a llama-runtime GGUF', () {
      expect(encoders, isNotEmpty);
      for (final m in encoders) {
        expect(m['runtime'], 'llama', reason: '${m['name']} is not llama');
        expect(m['filename'], endsWith('.gguf'),
            reason: '${m['name']} is not a GGUF');
      }
    });

    test('has no duplicate filename', () {
      // The `mmprojFilename` rule from AGENTS.md, for the field that does not
      // exist here: the app stores a download under `filename`, so two entries
      // sharing one silently overwrite each other. The user downloads the first,
      // then the second, and the first is gone with no error.
      final seen = <String>{};
      for (final m in encoders) {
        final f = m['filename'];
        expect(seen.add(f!), isTrue, reason: 'duplicate filename: $f');
      }
    });

    test('has no duplicate URL, which is a different failure', () {
      // Two entries pointing at one file would be a copy-paste slip, and it
      // would show up as "the same model listed twice" with no other symptom.
      final seen = <String>{};
      for (final m in encoders) {
        final u = m['url'];
        expect(seen.add(u!), isTrue, reason: 'duplicate url: $u');
      }
    });

    test('declares a size for every entry, and it parses as bytes or MB', () {
      // The declared size is what the catalogue rule checks against
      // `content-length` before a commit. An entry without one cannot be checked
      // at all, which is the same as unchecked.
      for (final m in encoders) {
        final size = m['size'];
        expect(size, isNotNull, reason: '${m['name']} has no size');
        expect(RegExp(r'^\d+(\.\d+)?\s*(KB|MB|GB)$').hasMatch(size!),
            isTrue, reason: '${m['name']} size is "$size"');
      }
    });

    test('every URL is a resolve/main link to a .gguf', () {
      // A 404 has no symptom before the download, so the shape of the URL is
      // the only thing that can be checked here. `gguf-screen.py` is what
      // actually confirms one.
      for (final m in encoders) {
        final url = m['url']!;
        expect(url, contains('/resolve/main/'),
            reason: '${m['name']} url is not a resolve link: $url');
        expect(url, endsWith('.gguf'), reason: '${m['name']} url: $url');
      }
    });

    test('carries a description long enough to act on', () {
      // The description is the only place the trade-off is written down — size
      // against what the model is actually for. "GGUF" is not a description.
      //
      // **Nos dois idiomas**, e não é redundância: a ficha que a tela mostra é
      // uma das duas, e um CHECK que passasse em inglês deixaria metade das
      // entradas reprovando em português.
      for (final m in encoders) {
        for (final idioma in const ['descriptionEn', 'descriptionPt']) {
          expect(m[idioma]!.length, greaterThan(40),
              reason: '${m['name']} has a one-word $idioma');
        }
      }
    });
  });

  group('the general catalogue is untouched by the encoder addition', () {
    test('no encoder filename collides with a chat-model filename', () {
      // `ModelController.onInit` concatenates the two lists, so a collision
      // would make one of them unreachable and nothing would say so.
      final chat = AppConstants.availableModels.map((m) => m['filename']).toSet();
      for (final m in encoders) {
        expect(chat.contains(m['filename']), isFalse,
            reason: '${m['filename']} is in both lists');
      }
    });
  });
}
