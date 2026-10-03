import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mobilelm/l10n/app_translation.dart';
import 'package:mobilelm/services/text_interpolation.dart';

/// Um mapa do `AppTranslation` por idioma.
///
/// `AppTranslation().keys` é `Map<idioma, Map<chave, texto>>`, e o índice é a
/// única forma de ler um idioma sem o outro — o teste de cobertura já registra
/// que a lista **mesclada** devolveria o `pt_BR` para as chaves dos dois.
Map<String, String> _mapa(String lang) => AppTranslation().keys[lang]!;

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

    test(
        'todo @nome do mapa tem valor em toda chamada, ou a tela fica vermelha',
        () {
      // **Este teste existe por causa do `@ramGB`, e a forma do defeito é
      // diferente da de todos os outros deste arquivo.**
      //
      // `preencher` lê `@([A-Za-z_][A-Za-z0-9_]*)`, e `GB` colado no nome é
      // parte do nome: `@ramGB` é *um* placeholder, não `@ram` seguido de
      // `GB`. A tradutora escreveu `'Available: @ramGB · …'` — que parece
      // perfeito, porque `@ram` é o nome do valor e `GB` é a unidade, e a
      // leitura humana faz a separação que o regex não pode fazer.
      //
      // O sintoma no aparelho foi o pior possível para um erro de texto: a
      // `ArgumentError` de [preencher] **cai dentro do `build`**, e o Flutter
      // troca o `Text` inteiro por um retângulo **vermelho** que ocupa a linha
      // toda. O log dizia `a chave "set_device_budget" tem @ramGB sem valor`, e
      // a tela dizia Configurações inteira vermelha — a leitura óbvia é "o app
      // quebrou", não "faltou um espaço na tradução".
      //
      // **A defesa é o espaço, e a regra é:** unidade, sufixo e pontuação vão
      // **fora** do placeholder. `@ram GB`, `@ctx tokens`, `@n×` — nunca
      // `@ramGB`. Sem o espaço não há como distinguir, e a distinção é o que
      // o helper inteiro existe para fazer.
      for (final lang in const ['en_US', 'pt_BR']) {
        final mapa = _mapa(lang);
        final colados = <String>[];
        for (final entrada in mapa.entries) {
          final re = RegExp(r'@[A-Za-z_][A-Za-z0-9_]*[A-Z0-9]');
          for (final m in re.allMatches(entrada.value)) {
            colados.add('$lang  ${entrada.key}  "${m.group(0)}"');
          }
        }
        expect(colados, isEmpty,
            reason: 'placeholder com letra ou dígito colado depois. O regex de '
                '`preencher` lê "@ramGB" como UM nome, e a chamada não tem '
                'valor para ele: a `ArgumentError` cai dentro do build e a '
                'tela fica com um retângulo vermelho no lugar do texto. Ponha '
                'o espaço — "@ram GB".\n  ${colados.join('\n  ')}');
      }
      // **E o caso que está certo continua funcionando**, para o teste não
      // passar por não rodar nada.
      expect(
          preencher('set_device_budget',
              {'ram': '1.2', 'ctx': '2048', 'tok': '1024'}),
          contains('1.2 GB'));
      Get.locale = const Locale('pt', 'BR');
      expect(
          preencher('set_device_budget',
              {'ram': '1.2', 'ctx': '2048', 'tok': '1024'}),
          'Disponível: 1.2 GB · Contexto: 2048 · Tokens: 1024');
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
