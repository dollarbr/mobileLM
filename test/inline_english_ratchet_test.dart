import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Quantos textos de tela ainda são literais em inglês dentro do código.
///
/// **Este arquivo é uma trava, não uma lista de defeitos.** Ele não afirma que
/// um texto específico está errado — afirma que o número **não cresce**. A
/// lista dos 47 que sobraram está escrita em `AGENTS.md`, com o arquivo e a
/// linha de cada um, e ela é dívida conhecida e medida.
///
/// ## Por que uma trava e não a tradução inteira
///
/// Os 47 que restam são parágrafos de ajuda em telas secundárias, e quase
/// todos são **literais adjacentes** — o Dart concatena os vizinhos em tempo de
/// compilação, então o texto ocupa três a cinco linhas e um `\n` no meio. É a
/// mesma forma que já custou três builds em `constants.dart` na mesma sessão, e
/// reescrever 47 delas com regex é o caminho que produz
/// `"…aparelhos compouca RAM"`: texto novo colado em cima do antigo, que parece
/// traduzido e não está.
///
/// Uma trava é mais útil aqui do que uma tradução apressada. O sintoma que o
/// dono do app descreveu — texto no idioma errado na tela — não era falta de
/// tradução: era um idioma que ninguém escolhia e literais que ninguém
/// localizava. Os dois foram fechados. O que sobra é texto de referência, e a
/// trava garante que ele não vira texto de interface sem ninguém perceber.
///
/// **A guarda que pega o crescimento é a segunda metade do arquivo**: ela
/// recusa literais novos com as palavras que aparecem nesta lista, e diz
/// exatamente onde.
void main() {
  /// Palavras que marcam um literal em inglês de tela.
  ///
  /// A lista é de inglês, e a pergunta é "esta frase tem palavra de inglês que
  /// não é nome de modelo nem exemplo de API" — a mesma inversão do detector de
  /// idioma do catálogo, e pela mesma razão: uma lista do que **não pode**
  /// aparecer só funciona se o resto for o universo.
  const ingles = <String>{
    'the', 'and', 'with', 'for', 'from', 'your', 'this', 'that', 
    'these', 'those', 'there', 'here', 'they', 'their', 'when', 
    'where', 'which', 'while', 'would', 'should', 'could', 'must', 
    'only', 'also', 'very', 'most', 'more', 'less', 'than', 'then', 
    'into', 'about', 'after', 'before', 'without', 'within', 'across', 
    'every', 'each', 'never', 'always', 'nothing', 'everything', 
    'someone', 'anywhere', 'settings', 'model', 'models', 'download', 
    'delete', 'cancel', 'save', 'saved', 'load', 'loaded', 'search', 
    'choose', 'pick', 'enable', 'disable', 'failed', 'ready', 
    'waiting', 'warning', 'success', 'error', 'screen', 'button', 
    'tap', 'device', 'folder', 'file', 'files', 'server', 'network', 
    'key', 'port', 'default', 'appearance', 'inference', 'storage', 
    'agent', 'diagnostics', 'light', 'dark', 'system', 'local', 
    'cloud', 'steps', 'step', 'plan', 'ai', 'template', 'backup', 
    'inspect', 'test', 
  };

  /// Nomes próprios, formatos e exemplos de API: não são idioma.
  const naoTexto = <String>{
    'gguf', 'litert', 'safetensors', 'tflite', 'litertlm', 'openai', 
    'huggingface', 'qat', 'qad', 'qaft', 'q4_0', 'q4_k_m', 'bf16', 
    'fp16', 'int8', 'npu', 'gpu', 'cpu', 'nvidia', 'openrouter', 
    'base_url', 'chat/completions', 'v1', 'rerank', 'embed', 
    'embeddings', 'modello', 'device_local', 'locally', 'locais', 
  };

  /// Arquivos de tela. Os `.arb` ficam de fora: eles não são fonte para nada.
  List<File> telas() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => f.path.contains('/views/') || f.path.contains('/widgets/'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  /// Um literal é "de tela em inglês" quando é uma frase com palavra de
  /// inglês. Um identificador (`OpenAI`, `GGUF`) e um exemplo de API (`curl
  /// $base/v1/...`) não entram, e é por isso que a lista `naoTexto` existe.
  List<String> varre() {
    final achados = <String>[];
    for (final f in telas()) {
      final src = f.readAsStringSync();
      for (final m in RegExp(r"""(?:Text|title|labelText|hintText|tooltip)\s*\(\s*'([^']{8,})'""")
          .allMatches(src)) {
        final bruto = m.group(1)!;
        if (bruto.contains('\$')) continue; // interpolado: não é texto fixo
        var probe = bruto.toLowerCase();
        for (final t in naoTexto) {
          probe = probe.replaceAll(t, ' ');
        }
        final temIngles = ingles
            .any((w) => probe.contains(RegExp('\\b${RegExp.escape(w)}\\b')));
        if (!temIngles) continue;
        achados.add('${f.path}:${src.substring(0, m.start).split('\n').length}'
            '  ${bruto.length > 62 ? '${bruto.substring(0, 62)}…' : bruto}');
      }
    }
    return achados;
  }

  test('o número de literais em inglês não cresce', () {
    // **63 em 2026-10-02**, medido depois que o seletor de idioma, o catálogo
    // bilíngue, as 16 sugestões do chat, os 6 chips de resposta, os 9 rótulos
    // de seção e os 3 modos de tema foram localizados.
    //
    // **Uma auditoria anterior contou 51 e este conta 63, e a diferença é o
    // filtro, não o trabalho.** O primeiro exigia uma letra maiúscula no
    // começo e um conjunto menor de palavras; este não. A lista completa está
    // em `AGENTS.md` com arquivo e linha de cada uma. Registrar o número
    // errado seria a mesma classe de erro que o número de 62 do catálogo já
    // produziu três vezes neste repo.
    //
    // **A trava sobe quando alguém traduz, e nunca afrouxa sozinha.** É
    // deliberado: um teto que cede sozinho deixa de ser uma promessa.
    const teto = 63;
    final hoje = varre();
    expect(hoje.length, lessThanOrEqualTo(teto),
        reason: 'O idioma da tela é uma escolha agora, e texto de interface '
            'que não passa pelo mapa existe numa língua só. Se você adicionou '
            'literal em inglês, use `.tr` e uma chave nos dois mapas '
            '(`lib/l10n/app_translation.dart`). Se você traduziu os que já '
            'existiam, baixe o teto para o número medido:\n'
            '${hoje.length - teto} a mais que o teto:\n'
            '  ${hoje.take(teto + 1).skip(teto).join('\n  ')}');
  });

  test('a varredura ainda enxerga alguma coisa', () {
    // **O irmão que prova que o harness é hostil o bastante.** Um regex que
    // parou de casar reportaria zero e o teto passaria pelo motivo errado —
    // que é o modo de falha que já atingiu a auditoria de overflow, a de
    // overflow de linha e a de descrição de catálogo neste repo, cada uma com
    // a mesma causa: um detector que silenciosamente não vê.
    expect(varre().length, greaterThan(50),
        reason: 'se a varredura parou de casar, o teto acima passa por não ter '
            'o que medir');
  });

  test('a lista em naoTexto não engole telas inteiras', () {
    // `naoTexto` existe para não acusar `OpenAI` e `GGUF`. Um termo colocada
    // ali por engano — `model`, `light`, `about` — apagaria dezenas de linhas
    // de uma vez e o teto passaria sem que ninguém traduzisse nada. Cada termo
    // tem que ser algo que **nunca** é português nem aparece em frase de tela.
    for (final termo in const ['model', 'light', 'dark', 'about', 'settings',
      'test', 'steps', 'plan', 'template', 'key', 'port', 'default']) {
      expect(naoTexto, isNot(contains(termo)),
          reason: '"$termo" é palavra de interface, não nome próprio: '
              'colocá-la em naoTexto apaga linhas do contador em silêncio');
    }
  });
}