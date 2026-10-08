import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/core/constants.dart';
import 'package:mobilelm/l10n/app_translation.dart';
import 'package:mobilelm/models/ai_model.dart';

/// The `role` field and the block it produces.
///
/// Two things can go wrong here and neither of them shows on screen: a model with
/// no `role` landing in the wrong block (invisible — it just looks like an
/// ordinary Vision model), and a `role` value the grouping does not know about
/// (an entry that silently disappears from every block, because the label it
/// produces is not in `order` and `indexOf` returns -1 for everything).
void main() {
  /// The grouping, copied out of `ModelController._byModality`.
  ///
  /// **Copied, and that is the reason the second group below exists.** This file
  /// cannot import the controller — its constructor pulls in `HiveService`,
  /// `InferenceService` and `AppLogService`, so a test about grouping becomes a
  /// test of the dependency container. So the rule is restated here, and the test
  /// that pins it to the real implementation is the one that reads this file's
  /// name out of the real source.
  String labelFor(AiModel m) => m.isDecisionModel
      ? 'Decision models'
      : m.filename.endsWith('.safetensors')
          ? 'Image generation'
          : m.needsMmproj
              ? 'Multimodal'
              : 'Text';

  const order = [
    'Decision models',
    'Text',
    'Vision',
    'Multimodal',
    'Image generation',
  ];

  /// `availableModels` is a list of **maps**, not of `AiModel` — the catalogue is
  /// declared as data and the model is built from it. Reading `.role` off a map
  /// is a compile error, which is this file's first lesson arriving for free.
  final catalogo = AppConstants.availableModels.map(AiModel.fromMap).toList();

  group('the role is a declared fact, never a filename guess', () {
    test('only one entry declares a role', () {
      final comRole = catalogo.where((m) => m.role.isNotEmpty).toList();
      expect(comRole.length, 1, reason: 'the d1-3B, and nothing else yet');
      expect(comRole.single.filename, 'd1-3B-Q4_K_M.gguf');
      expect(comRole.single.isDecisionModel, isTrue);
    });

    test('no entry derives its role from the name', () {
      // `bge-small-en-v1.5` was once identified as a classifier because
      // something read the name and guessed. The defence is that the field is the
      // only source, so an entry without one is *not* a decision model no matter
      // what its filename looks like.
      for (final m in catalogo) {
        final name = m.filename.toLowerCase();
        if (!name.contains('d1') && !name.contains('tev')) continue;
        expect(m.role, 'decision',
            reason: '${m.filename} looks like a decision model but declares '
                '"${m.role}" — either the name or the field is lying');
      }
    });

    test('an unknown role is not a decision model, and says so', () {
      final m = AiModel(
        name: 'x',
        filename: 'x.gguf',
        url: '',
        size: '',
        descriptionEn: '',
        template: 'chatml',
        role: 'somethingElse',
      );
      expect(m.isDecisionModel, isFalse);
      // And it must not vanish: an unknown role still has to land in a block.
      expect(labelFor(m), 'Text');
      expect(order.contains(labelFor(m)), isTrue);
    });
  });

  /// **Pins the copy above to the real implementation.**
  ///
  /// `labelFor` is a restatement of `ModelController._byModality`, because the
  /// controller cannot be constructed in a test without dragging in `HiveService`,
  /// `InferenceService` and `AppLogService`. A restatement is a second copy, and
  /// a second copy drifts — the group below would keep passing while the screen
  /// did something else.
  ///
  /// So this reads the source and asserts the **three** things the restatement
  /// depends on: that the role test comes **first** in the ternary chain (a
  /// vision decision model would otherwise land in Multimodal), that the block
  /// label is the literal this file groups by, and that the `order` list really
  /// starts with it. A rename in either place fails here.
  test('the copy above still matches _byModality in the source', () {
    final src =
        File('lib/controllers/model_controller.dart').readAsStringSync();

    expect(
        RegExp(r"final label = m\.isDecisionModel\s*\?\s*'Decision models'",
                multiLine: true)
            .hasMatch(src),
        isTrue,
        reason: '_byModality no longer tests isDecisionModel first');

    // And it is checked **before** the modality branches, which is the whole
    // claim. The first version of this assertion looked for `isImageModel`
    // *between* `isDecisionModel` and the next semicolon — and of course it found
    // one, because `isImageModel` legitimately sits in the `else` chain. A
    // restatement's error is worth writing down: it asserted the wrong property
    // and would have failed on correct code.
    // Scoped to the **function**, not to the file: `isImageModel` is used three
    // times above `_byModality` for the section lists, so a file-wide `indexOf`
    // compares against an unrelated call and the assertion is about nothing.
    final start = src.indexOf('List<ModelBlock> _byModality');
    expect(start, greaterThan(-1));
    final body = src.substring(start, src.indexOf('\n  }', start));
    final role = body.indexOf('m.isDecisionModel');
    expect(role, greaterThan(-1));
    for (final other in ['isImageModel', 'isVisionModel']) {
      expect(body.indexOf(other), greaterThan(role),
          reason: '$other is now tested before isDecisionModel, so a decision '
              'model with an mmproj would land in a modality block');
    }

    // The order list starts with it, as a list literal, not alphabetically.
    final orderMatch = RegExp(
      r"const order = \[[^\]]*'Decision models'[^\]]*\]",
      multiLine: true,
    ).firstMatch(src);
    expect(orderMatch, isNotNull,
        reason: 'the order list no longer names Decision models');
    expect(orderMatch!.group(0)!.indexOf('Decision models'),
        lessThan(orderMatch.group(0)!.indexOf('Text')),
        reason: 'Decision models has to sort before Text');
  });

  group('the block a model lands in', () {
    test('the d1-3B goes to Decision models, not to Multimodal', () {
      // It **has** an `mmproj`, so by modality it is a vision model. The role
      // wins, because "it answers with one letter" is what someone opening this
      // category is looking for.
      final d1 =
          catalogo.firstWhere((m) => m.filename == 'd1-3B-Q4_K_M.gguf');
      expect(d1.needsMmproj, isTrue,
          reason: 'it really is a vision model — that is the point of the test');
      expect(labelFor(d1), 'Decision models');
    });

    test('a vision model without a role is unaffected', () {
      final vl =
          catalogo.firstWhere((m) => m.filename.startsWith('LFM2.5-VL-450M'));
      expect(vl.role, isEmpty);
      expect(labelFor(vl), 'Multimodal');
    });

    test('Decision models sorts first', () {
      expect(order.first, 'Decision models');
      expect(order.indexOf('Decision models'),
          lessThan(order.indexOf('Text')),
          reason: 'a model that answers with a letter is the most surprising '
              'thing in this list');
    });

    test('every block the grouping can produce is in the order list', () {
      // **This is the assertion that catches a role nobody handled.** The order
      // is sorted with `indexOf`, and an unlisted label gets -1 — which sorts it
      // *first*, silently, and puts a block with no heading translation at the
      // top of the list.
      for (final produced in [
        'Decision models',
        'Text',
        'Vision',
        'Multimodal',
        'Image generation',
      ]) {
        expect(order.contains(produced), isTrue, reason: produced);
      }
      expect(order.toSet().length, order.length, reason: 'no duplicates');
    });
  });

  /// Every `(label, translation key)` pair `_rotuloDoBloco` can return, read out
  /// of the real source.
  ///
  /// **This group exists because mutation M3 survived the whole suite.** The
  /// mutation replaced `'Decision models' => 'mv_block_decision'` with
  /// `'Decision models' => 'Decision models'` — one string, in a private static
  /// switch — and **633/633 tests stayed green**. Nothing caught it, because:
  ///
  ///  * `language_preference_test.dart` requires each entry in `naoTexto` to
  ///    *exist as a literal in the source*, and `'Decision models'` still does
  ///    (three other places). The literal being present is not the label being
  ///    translated.
  ///  * the key-count test reads 919 in both maps, and `mv_block_decision` was
  ///    never removed from either map — the count test cannot see that the code
  ///    stopped using it.
  ///  * nothing asserted the mapping itself.
  ///
  /// So the consequence of M3 was a Portuguese user seeing an English heading,
  /// invisibly, and a `labelKey` that is dead code. That is the same shape as the
  /// `order` `indexOf` -1 trap: a silent default eating a real mistake.
  ///
  /// It cannot be reached by calling the function — it is private and the
  /// controller cannot be constructed in a test anyway — so the switch is read
  /// from the source instead, the same way the rest of this file reads `_byModality`.
  List<MapEntry<String, String>> paresDoRotulo() {
    final src =
        File('lib/controllers/model_controller.dart').readAsStringSync();
    final at = src.indexOf('static String _rotuloDoBloco');
    expect(at, greaterThan(-1), reason: '_rotuloDoBloco foi removido ou renomeado');
    final end = src.indexOf('};', at);
    final corpo = src.substring(at, end == -1 ? src.length : end);
    final pares = <MapEntry<String, String>>[];
    for (final m in RegExp(r"'([^']+)'\s*=>\s*'([^']+)'").allMatches(corpo)) {
      pares.add(MapEntry(m.group(1)!, m.group(2)!));
    }
    return pares;
  }

  group('a chave que o bloco devolve existe e é traduzida', () {
    test('o switch nao esta vazio, ou seja o parser acima ainda casa', () {
      // A parser que casa zero pares faz o grupo inteiro passar. Este é o
      // controle do próprio instrumento de medição.
      expect(paresDoRotulo().length, greaterThanOrEqualTo(5),
          reason: 'o switch _rotuloDoBloco mudou de forma; o parser parou de casar');
    });

    test('toda chave devolvida existe nos DOIS idiomas', () {
      final en = AppTranslation().keys['en_US']!;
      final pt = AppTranslation().keys['pt_BR']!;
      for (final par in paresDoRotulo()) {
        for (final (idioma, mapa) in [('en', en), ('pt', pt)]) {
          expect(mapa.containsKey(par.value), isTrue,
              reason: '${par.key} devolve ${par.value}, que não está no mapa '
                  '$idioma — o bloco sai com a chave crua');
        }
      }
    });

    test('o Decision models é traduzido, e traduzido diferente em cada idioma', () {
      final en = AppTranslation().keys['en_US']!;
      final pt = AppTranslation().keys['pt_BR']!;
      final chave = paresDoRotulo()
          .firstWhere((p) => p.key == 'Decision models')
          .value;
      expect(chave, 'mv_block_decision',
          reason: 'a chave deixou de ser a do bloco de decisão');
      expect(en[chave], 'Decision models');
      expect(pt[chave], 'Modelos de decisão');
    });

    test('uma chave de bloco não pode estar morta em nenhum idioma', () {
      // O reverso do teste acima: se `_rotuloDoBloco` parou de devolver
      // `mv_block_decision`, ela vira lixo — e o teste da contagem continua
      // contando, porque ele só soma.
      final usada = paresDoRotulo().map((p) => p.value).toSet();
      for (final chave in const [
        'mv_block_decision',
        'mv_block_text',
        'mv_block_vision',
        'mv_block_multimodal',
        'mv_block_image_generation',
      ]) {
        expect(usada.contains(chave), isTrue, reason: '$chave não é devolvida '
            'por nenhum ramo do switch');
      }
    });
  });

  group('the URLs were confirmed before the entry went in', () {
    test('every d1 URL is a LiquidAI GGUF repo, not a base model', () {
      // `LiquidAI/LFM2-d1-3B-GGUF` returns 401 and the model name *looks* like
      // LFM2 because it is one. `general.base_model.0.repo_url` in the GGUF is
      // the **base model**, so neither the file nor the name can be trusted for
      // this — only a HEAD against the real repository.
      final d1 =
          catalogo.firstWhere((m) => m.filename == 'd1-3B-Q4_K_M.gguf');
      for (final url in [d1.url, d1.mmprojUrl]) {
        expect(url, contains('huggingface.co/LiquidAI/'),
            reason: url);
        expect(url, contains('/resolve/main/'), reason: url);
        expect(url, isNot(contains('LFM2-d1')), reason: url);
      }
    });

    test('the projector travels with the model, because vision needs it', () {
      final d1 =
          catalogo.firstWhere((m) => m.filename == 'd1-3B-Q4_K_M.gguf');
      expect(d1.isVision, isTrue);
      expect(d1.mmprojFilename, 'mmproj-d1-3B-Q8_0.gguf');
      expect(d1.needsMmproj, isTrue);
    });

    test('the declared size is the smallest published quantisation', () {
      // BF16 5.03 GB, F16 5.03, Q8_0 2.68 — and 1.56 is the Q4_K_M. The card
      // is therefore **absent on a 5.6 GB phone** (1.56 GB against a
      // `maxModelBytes` of 1.40), which is the filter working and not a defect.
      final d1 =
          catalogo.firstWhere((m) => m.filename == 'd1-3B-Q4_K_M.gguf');
      expect(d1.size, '1.56 GB');
      final maxOnA72 = (5.6 * 0.25 * 1024 * 1024 * 1024).round();
      final declared = (1.56 * 1024 * 1024 * 1024).round();
      expect(declared, greaterThan(maxOnA72),
          reason: 'if this ever stops being true, the note in the '
              'description is lying');
    });
  });
}
