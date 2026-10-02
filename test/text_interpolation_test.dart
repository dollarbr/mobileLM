import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mobilelm/l10n/app_translation.dart';
import 'package:mobilelm/services/text_interpolation.dart';

/// A interpolação é a única classe de texto que a varredura **recusa** de
/// propósito, e "recusa" não é o mesmo que "coberta".
///
/// `TextLanguage.looksEnglish` devolve falso para qualquer literal com `$` — e
/// está certo: o valor no fonte não é o valor na tela, e trocar o literal
/// inteiro por uma chave apagaria a parte que muda. O efeito colateral é que
/// `test/inline_english_ratchet_test.dart` **não vê nada disso**, então o teto
/// em zero e a varredura em zero podem coexistir com dezenove telas em inglês.
///
/// Estes testes não auditam o fonte (a varredura de interpolados é um script de
/// um passo, não uma trava contínua, e está escrita no `AGENTS.md`). Auditam a
/// peça que faz a troca: o que acontece quando a tradução tem `@n` a mais, a
/// menos, ou quando o valor traz um `@` que não é placeholder.
void main() {
  setUp(() {
    Get.addTranslations(AppTranslation().keys);
    Get.locale = const Locale('en', 'US');
  });

  group('preencher', () {
    test('troca o @nome pelo valor, em qualquer posição', () {
      expect(
        preencher('set_hops_one', {'n': '3'}),
        'Agent mode: up to 3 hop per message',
      );
      expect(
        preencher('mv_memory_free', {'f': '1200', 't': '4800'}),
        '1200 free of 4800',
      );
    });

    test('o mesmo texto traduzido para português sai em português', () {
      Get.locale = const Locale('pt', 'BR');
      expect(preencher('set_hops_one', {'n': '3'}),
          'Modo agente: até 3 salto por mensagem');
      expect(preencher('set_hops_many', {'n': '7'}),
          'Modo agente: até 7 saltos por mensagem');
    });

    test('um @nome sem valor é erro, e a mensagem diz qual', () {
      // **Um `@n` esquecido apareceria na tela como `@n`.** É o mesmo defeito do
      // GetX devolvendo o próprio identificador: a tela mostra algo, nada lança
      // e quem lê não sabe se é dado ou texto faltando.
      expect(
        () => preencher('set_hops_one', const {}),
        throwsA(isA<ArgumentError>()
            .having((e) => e.message.toString(), 'mensagem', contains('@n'))),
      );
      // **Um valor com `@` não é placeholder, e a conferência é ANTES da troca.**
      // Um email no lugar de `@f` não pode virar erro, e um nome de arquivo com
      // arroba (`meu@model.gguf`) não pode ser partido. A primeira versão do
      // helper trocava primeiro e olhava o resultado, e recusava os dois — o
      // texto legítima acabava passando por defeito.
      expect(
          preencher('mv_memory_free', {'f': 'a@b', 't': '1'}), 'a@b free of 1');
      final t = preencher('mv_delete_filename', {'f': 'meu@model.gguf'});
      expect(t, 'meu@model.gguf will be permanently removed from this device.');
    });

    test('uma chave que não existe devolve a própria chave, e não @algo', () {
      // **Sem tradução, `.tr` devolve a chave, e a chave pode conter `@`.** Se
      // alguém escrever `'@n free of @t'` como chave esperando que o GetX
      // substitua, o que aparece na tela é a chave crua — e `preencher` não
      // distingue os dois casos, porque para ele é a mesma chave. Este teste
      // fixa o comportamento para que a falha seja do mapa e não do helper.
      expect(preencher('chave_que_nao_existe', {'n': '1'}),
          'chave_que_nao_existe');
    });
  });
}
