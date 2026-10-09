import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mobilelm/l10n/app_translation.dart';
import 'package:mobilelm/services/system_one.dart';
import 'package:mobilelm/services/system_one_presets.dart';
import 'package:mobilelm/views/system_one_console.dart';

/// The two new cards of the System One window, **mounted**.
///
/// ## Why this file exists and what it does not repeat
///
/// `system_one_presets_test.dart` proves the presets are well-formed and that the
/// three bodies are what the endpoint accepts. Neither of those can see whether
/// the window draws the chips, and this repo has a standing record of the two
/// failures that a pure-Dart test cannot catch:
///
/// - A test that mounted the screen inside a `Scaffold` **passed against the bug
///   it was written for**, because the `Scaffold` is what supplies the `Material`
///   that `ChoiceChip` demands. This file borrows the sibling file's harness
///   verbatim, `Material` and no `Scaffold` — the screen is opened with `Get.to`
///   and that is the context it really runs in.
/// - A widget below the fold of a `ListView` that has not been scrolled to is
///   **absent, not wrong**. Every assertion here drags the list first. This is
///   the fifth time this repo meets it and the comment is on each one.
///
/// The `.tr` calls need the map registered or they return the key and every
/// assertion here would be looking for an identifier.
void main() {
  setUp(() {
    Get.addTranslations(AppTranslation().keys);
    Get.locale = const Locale('en', 'US');
  });

  Future<void> hostile(WidgetTester tester) async {
    tester.view.physicalSize = const Size(720, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      // **Sem `const` aqui, e o analyzer tem razão.** `SystemOneConsole` tem
      // campos `final` inicializados (`TextEditingController`), e um `const`
      // exigiria que todos fossem constantes de compilação — o construtor
      // inteiro não é const-constructível. A dica do lint é genérica e aqui
      // ela não se aplica.
      GetMaterialApp(
        home: SystemOneConsole(
          shape: SystemOneShape.decision,
          baseUrl: 'http://127.0.0.1:1',
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();
    // **`pumpAndSettle` e não `pump`, porque `_probe()` roda em `initState` e
    // enquanto ele está em voo `_busy` é verdadeiro — e um `ChoiceChip` com
    // `onSelected: null` aceita o toque e não faz nada.** Os chips ficavam
    // inertes, e o teste falhava em "não desenhou" quando o defeito era "não
    // reage". A porta é `127.0.0.1:1`, então a falha é imediata e o settle
    // acontece em milissegundos; se o probe não assentasse, este `pumpAndSettle`
    // estouraria o tempo e o defeito apareceria aqui em vez de nos chips.
    await tester.pumpAndSettle();
  }

  /// Drag the list back to the top and settle.
  ///
  /// **The tap moves the list away from what the assertion is about.** The
  /// fields live above the preset card, so tapping a chip to fill them leaves
  /// them outside the `ListView` cache — `find.byType(EditableText)` then
  /// returns `[]` and the assertion reads "nothing was filled" when everything
  /// was. The failure names the wrong thing, which is worse than no failure.
  ///
  /// `dragUntilVisible` cannot help: it drags toward a finder that has to
  /// **exist** to be dragged to, and the whole problem is that it does not.
  Future<void> scrollToTop(WidgetTester tester) async {
    final list = find.byType(ListView);
    for (var i = 0; i < 8; i++) {
      await tester.drag(list, const Offset(0, 900));
      await tester.pumpAndSettle();
    }
  }
  /// Drag the list until [finder] is built, then hand it back.
  ///
  /// **Always from the top, and that is not an optimisation — it is the
  /// direction the helper gets right by construction.** `dragUntilVisible` drags
  /// in the direction it is given and throws `Bad state: No element` when it
  /// runs out of list with the finder still absent. It cannot scroll *up*, so
  /// any target above the current scroll position is unreachable by it — and
  /// "unreachable" arrives as `No element`, which reads as "the widget is not
  /// drawn" when the widget is drawn and simply cached away.
  ///
  /// Both failures in this file had that one cause: the preset card is below the
  /// readout card and above the text fields, so a tap on a preset puts *both* of
  /// them outside the cache in opposite directions.
  Future<Finder> scrolledTo(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) await scrollToTop(tester);
    if (finder.evaluate().isEmpty) {
      await tester.dragUntilVisible(finder, find.byType(ListView),
          const Offset(0, -240));
    }
    return finder;
  }


  /// Walk the whole list from top to bottom and report whether [finder] ever
  /// gets built.
  ///
  /// **The only absence assertion a lazy list can support, and the reason is
  /// the cache.** A `ListView` builds a window of children and discards the
  /// rest, so `findsNothing` at any single scroll position says only *"not in
  /// this window"* — which is true of the last row of the screen as surely as
  /// of a card that was never added. Scrolling to one end does not fix it
  /// either, because the card can sit anywhere between the two ends.
  ///
  /// So: from the top, one screenful at a time, checking after every step. The
  /// answer is then about the whole list, and it is the answer the window's
  /// `if (decisionTypeNeedsOptions(...))` deserves.
  Future<bool> everAppears(WidgetTester tester, Finder finder) async {
    await scrollToTop(tester);
    for (var i = 0; i < 12; i++) {
      if (finder.evaluate().isNotEmpty) return true;
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    return finder.evaluate().isNotEmpty;
  }

  /// Scroll [finder] into view and **tap it**, or fail saying which step failed.
  ///
  /// **`dragUntilVisible` alone is not enough, and this is the sixth time this
  /// repo meets the fold — the first time in its nastier form.** It stops as
  /// soon as the node is *built*, not when it is on screen: the chip came out at
  /// `Offset(180.0, 1206.0)` in a viewport of 1200 dp, six points below the
  /// edge, and `tester.tap` refused with "would not hit test on the specified
  /// widget". The chip was there, the label was the string the assertion wanted,
  /// and the tap did nothing.
  ///
  /// So: `dragUntilVisible` to get it built, then `ensureVisible` to get it on
  /// screen, then tap. The two guards produce different messages — "not found"
  /// when the card does not draw the widget at all, "off-screen" when it draws
  /// it somewhere the finger cannot reach — and telling them apart is the whole
  /// point of a failing test.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await scrolledTo(tester, finder);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    final box = tester.getRect(finder);
    final view = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(
      box.center.dy >= 0 && box.center.dy <= view.height,
      isTrue,
      reason: 'o widget está desenhado mas fora da tela: centro '
          '${box.center.dy} numa janela de ${view.height} dp. '
          'Um "não achou" aqui é um "achou e não dá para tocar".',
    );
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('o cartão de presets', () {
    testWidgets('os quatro chips estão na tela, e o primeiro é o que funciona',
        (tester) async {
      await hostile(tester);
      // A ordem é por "responde algo que o anterior não respondia", e a razão
      // está em `DecisionPreset.all`. O que esta tela tem que garantir é que
      // **os quatro existem** — um `for` sobre uma lista vazia desenha um
      // `Wrap` vazio que passa em qualquer teste de "não quebrou".
      for (final id in DecisionPreset.all.map((p) => p.id)) {
        expect(await scrolledTo(tester, find.text('soc_preset_$id'.tr)),
            findsOneWidget,
            reason: 'o chip $id não foi desenhado');
      }
    });

    testWidgets('sem nada escolhido a carta diz que nada foi escolhido',
        (tester) async {
      await hostile(tester);
      // O estado honesto. Uma carta que mostrasse a medição do `charge` sem
      // ninguém ter tocado em nada ensinaria que a janela sabe a resposta.
      expect(await scrolledTo(tester, find.text('soc_presets_none'.tr)),
          findsOneWidget);
    });

    testWidgets('um preset medido mostra o número e o porquê', (tester) async {
      await hostile(tester);
      // **`charge` primeiro, porque é o único cujo `measured` é só uma
      // palavra.** O card mostra `On this phone, measured: billing`, e o que
      // esta prova é que o texto interpolado está lá com o valor dentro — um
      // `preencher` sem a chave na mutação desenha `On this phone, measured: @m`
      // e a tela fica com um placeholder visível.
      await tapVisible(tester, find.text('soc_preset_charge'.tr));
      expect(find.textContaining('measured: billing'), findsOneWidget);
      expect(find.textContaining('0.6972'), findsOneWidget);
      // E a nota do `charge`, que é uma das duas que dizem por que o preset
      // existe.
      expect(find.text('soc_preset_note_charge'.tr), findsOneWidget);
    });

    testWidgets('o preset noul traz as palavras do próprio modelo', (tester) async {
      await hostile(tester);
      await tapVisible(tester, find.text('soc_preset_outage'.tr));
      // **A nota do `outage` é a frase mais importante da janela.** Ela diz que a
      // resposta óbvia é sim e o modelo deu 0,5188 — e é a única coisa no cartão
      // que impede alguém de ler "confidence 0,5458" como "acertou". Se ela sumir,
      // o preset vira uma demo que ensina o oposto do que mediu.
      final note = await scrolledTo(
          tester, find.text('soc_preset_note_outage'.tr));
      expect(note, findsOneWidget);
      expect(find.textContaining('coin flip'), findsOneWidget);
    });

    testWidgets('o preset preenche os campos, e não só desenha o chip',
        (tester) async {
      await hostile(tester);
      await tapVisible(tester, find.text('soc_preset_charge'.tr));
      // **O `measured` primeiro, com a carta de presets ainda em cache** — as
      // duas coisas que este teste afirma vivem em pontos **opostos** da lista
      // (o número embaixo dos chips, os campos acima deles), e só uma delas por
      // vez está construída. Verificar as duas de uma vez exige um `scrollToTop`
      // entre elas, e a ordem importa porque subir tira o número do cache.
      expect(find.textContaining('measured: billing'), findsOneWidget);
      await scrollToTop(tester);
      // **A afirmação que os testes de serviço não fazem**: os controladores de
      // texto mudaram. Um chip que só redesenhe o próprio destaque e deixe os
      // campos como estavam seria um botão decorativo, e a pessoa bateria nele e
      // veria a pergunta antiga.
      //
      // **`widgetWithText(TextField, ...)` não serve aqui, e é uma armadilha de
      // API e não de layout.** Um `TextField` não tem um `Text` filho: ele
      // desenha `EditableText`, e `find.text` acha o texto desenhado mas
      // `widgetWithText` pergunta por um `Text` **descendente** — que não
      // existe. A leitura honesta é pelo controlador, que é o mesmo objeto que
      // o dedo digita.
      final filled = tester
          .widgetList<EditableText>(find.byType(EditableText))
          .map((e) => e.controller.text)
          .toList();
      expect(
        filled,
        contains('fui cobrado duas vezes pelo pedido #4417 neste mês'),
        reason: 'o preset não preencheu o estado. Controladores na tela: $filled',
      );
      expect(
        filled,
        contains('a que área isto pertence?'),
        reason: 'a pergunta do preset também não foi preenchida',
      );
    });

    testWidgets('tocar no preset leva ao caminho do logit, e não ao da letra',
        (tester) async {
      await hostile(tester);
      await tapVisible(tester, find.text('soc_preset_charge'.tr));
      // Um preset que preenche os campos e deixa a pessoa na carta de variantes
      // responderia com uma **letra**, e nenhuma das quatro medições é uma letra
      // exceto a do `forgot` — que é a mais lenta e a que a pessoa não está
      // olhando. O `logit` é o único readout cujo número se compara com o
      // `measured`.
      //
      // **`scrolledTo` e não `expect` direto**: a carta do readout está ACIMA da
      // de presets, e o `ListView` já tinha descartado a linha. Um nó fora do
      // cache de um `ListView` não é "errado", é "inexistente", e o teste
      // reprovaria por causa de onde a lista parou.
      final logit = await scrolledTo(tester, find.text('soc_readout_logit'.tr));
      expect(logit, findsOneWidget,
          reason: 'o preset não trocou o readout para o de logit');
      // E a carta de variantes some, porque ela mede se a LETRA muda e uma
      // distribuição não tem letra para mudar. **Rolada até o fim antes**, para
      // que a ausência seja "não está em lugar nenhum" e não "está abaixo da
      // dobra".
      expect(await everAppears(tester, find.text('soc_variants'.tr)), isFalse,
          reason: 'a carta de variantes sobreviveu à troca para o readout de '
              'logit, e ela mede se a LETRA muda — que uma distribuição não faz');
    });
  });

  group('editar apaga a medição, e é o que a torna honesta', () {
    testWidgets('digitar no estado tira a frase de medido', (tester) async {
      await hostile(tester);
      await tapVisible(tester, find.text('soc_preset_charge'.tr));
      expect(await scrolledTo(
              tester, find.textContaining('measured: billing')),
          findsOneWidget,
          reason: 'a medição do preset tem que estar lá antes de ser apagada, '
              'ou este teste passa por uma carta que nunca mostrou nada');

      // Um caractere é suficiente, e não é um detalhe: o listener dispara por
      // tecla, e um teste que digitasse uma frase inteira não distinguiria
      // "apaga na primeira tecla" de "apaga na última".
      await scrollToTop(tester);
      await tester.enterText(find.byType(EditableText).first, 'x');
      await tester.pumpAndSettle();

      // **`everAppears`, não `findsNothing`.** A medição fica numa carta abaixo
      // do campo que a pessoa acabou de digitar, então um `findsNothing` logo
      // depois do toque afirmaria "não está na janela" — que é verdade de
      // qualquer coisa que a rolagem deixou de fora.
      expect(
        await everAppears(tester, find.textContaining('measured:')),
        isFalse,
        reason: 'a medição do preset sobreviveu à edição do estado: a tela '
            'passa a comparar um número com uma pergunta que não é a do preset',
      );
      // E o cartão diz a verdade sobre o que está na tela.
      expect(await scrolledTo(tester, find.text('soc_presets_none'.tr)),
          findsOneWidget);
    });

    testWidgets('mudar uma opção também tira a frase de medido', (tester) async {
      await hostile(tester);
      await tapVisible(tester, find.text('soc_preset_charge'.tr));
      expect(await scrolledTo(
              tester, find.textContaining('measured: billing')),
          findsOneWidget);

      // **Um caminho de código diferente, e por isso um teste separado.** Apagar
      // pelo `_setOption` não passa por `_edited`: o `TextField` de cada opção é
      // construído com um controller **novo** a partir do rótulo, então nenhum
      // dos três listeners de tela dispara. Deixar só o teste do estado cobrir
      // isto seria um teste que passa pelo motivo errado — foi a mutação 3 deste
      // arquivo que mostrou.
      //
      // **O campo é localizado pelo conteúdo, e não por índice.** `at(2)` foi a
      // primeira tentativa e reprovou com `RangeError`: no topo da lista só há
      // dois `EditableText` construídos — o do estado e o da pergunta —, e o
      // cartão de opções está abaixo da dobra. Um índice é posição, e a posição
      // é o que a rolagem desfaz.
      final field = find.byWidgetPredicate(
          (w) => w is EditableText && w.controller.text == 'technical support',
          description: 'o campo da opção "technical support"');
      await scrolledTo(tester, field);
      expect(field, findsOneWidget,
          reason: 'o preset não pôs "technical support" no segundo campo');
      await tester.enterText(field, 'outra coisa');
      await tester.pumpAndSettle();

      expect(
        await everAppears(tester, find.textContaining('measured:')),
        isFalse,
        reason: 'a medição sobreviveu à edição de uma opção: trocar o trio de '
            'opções é trocar a pergunta que a medição descreve',
      );
    });
  });

  group('o cartão do tipo de resposta', () {
    testWidgets('os três tipos têm um chip, e os três nomes estão na tela',
        (tester) async {
      await hostile(tester);
      // Um `for` sobre uma lista com um item só desenha um chip e passa num
      // teste de "os chips existem". Este é sobre os **três** — e a lista é a
      // mesma que `kAnswerTypes`, de modo que um tipo novo sem chip reprova
      // aqui e não só numa imagem de tela.
      for (final t in ['choice', 'score', 'noul']) {
        expect(await scrolledTo(tester, find.text(kAnswerTypeKey[t]!.tr)),
            findsOneWidget,
            reason: 'o chip $t não foi desenhado');
      }
    });

    testWidgets('escolher noul esconde o cartão de opções', (tester) async {
      await hostile(tester);
      // **O cartão some em vez de desabilitar.** O endpoint escreve as duas
      // afirmações sozinho e ignora o `criteria` que chegar, então um cartão
      // visível é um campo que aceita texto e não faz nada com ele — pior do
      // que não haver cartão. A prova é negativa e é a única prova possível: a
      // linha `what will be sent` **sai da tela junto**.
      final willSend = await scrolledTo(
          tester,
          find.textContaining('{A: bug, B: billing, C: account}'));
      expect(willSend, findsOneWidget);

      await tapVisible(tester, find.text(kAnswerTypeKey['noul']!.tr));

      //
      // **`everAppears` e não `findsNothing`, e a diferença é a lista.** Um
      // `findsNothing` aqui affirmaria *"não está nesta janela da lista"*, que
      // é verdade da última linha da tela tanto quanto de uma carta que nunca
      // foi adicionada. `everAppears` percorre a lista inteira e responde à
      // pergunta que o `if (decisionTypeNeedsOptions(...))` de fato faz.
      expect(
        await everAppears(
            tester, find.textContaining('{A: bug, B: billing, C: account}')),
        isFalse,
        reason: 'a linha "what the window will send" continua em algum lugar da '
            'lista depois de escolher noul: o cartão de opções não foi removido',
      );
      expect(await scrolledTo(tester, find.text('soc_answer_type_note_noul'.tr)),
          findsOneWidget);
      // E o texto de `add an option` some com ele — a mesma carta.
      expect(await everAppears(tester, find.text('soc_add_option'.tr)), isFalse,
          reason: '"add an option" é do cartão de opções e sobreviveu ao noul');
    });

    testWidgets('escolher noul diz que não manda opções', (tester) async {
      await hostile(tester);
      await tapVisible(tester, find.text(kAnswerTypeKey['noul']!.tr));
      // **A frase é metade do contrato.** Uma pessoa que digita critérios e não
      // os vê usados precisa de uma razão na tela, e a razão é que a segunda
      // conjunto de palavras para o mesmo booleano não é uma segunda opinião.
      final note = await scrolledTo(
          tester, find.text('soc_answer_type_note_noul'.tr));
      expect(note, findsOneWidget);
      expect(find.textContaining('calibrated'), findsOneWidget);
    });

    testWidgets('voltar para choice traz o cartão de opções',
        (tester) async {
      await hostile(tester);
      await tapVisible(tester, find.text(kAnswerTypeKey['noul']!.tr));
      await tapVisible(tester, find.text(kAnswerTypeKey['choice']!.tr));
      // O caminho de volta, e é o que torna o seletor utilizável: esconder um
      // cartão sem forma de trazê-lo de volta deixa a janela num estado em que
      // a pessoa perdeu campo sem ter feito nada de errado.
      expect(await scrolledTo(
          tester,
          find.textContaining('{A: bug, B: billing, C: account}')),
          findsOneWidget);
    });
  });

  group('360 dp com texto 2x não transborda', () {
    testWidgets('com os dois cartões novos desenhados', (tester) async {
      await hostile(tester);
      // O `Wrap` dos chips é a peça que quebra: quatro chips com nome em 2× não
      // cabem em 180 dp de largura e cada um mede o **seu** `RenderFlex`.
      // Qualquer transbordo sai por `takeException`.
      for (final id in DecisionPreset.all.map((p) => p.id)) {
        await tapVisible(tester, find.text('soc_preset_$id'.tr));
      }
      expect(tester.takeException(), isNull);
      while (tester.takeException() != null) {}
    });
  });
}
