// A lista de `TextLanguage.englishWords` tem buracos?
//
// A lista é uma **afirmação**, e é o mesmo problema das sete omissões da trava:
// o que **falta** nela não se nota, porque um filtro que não casa nada reporta
// a mesma coisa que um filtro que não acha nada. As sete omissões eram de
// *escopo* — uma pasta, um parâmetro de call site, uma letra na classe do
// regex — e todas apareceram por causa externa. Esta é de **conteúdo**, e a
// causa externa seria a mesma: um `dump` do aparelho mostrando uma palavra que a
// lista não conhece.
//
// A forma é uma lista do que **não pode** aparecer, e ela só funciona se o resto
// for o universo — que aqui é o inglês, e é por isso que esta lista é uma
// **amostra auditada** e não umDerived. Cada entrada abaixo é uma string que eu
// li no fonte e que é texto de tela em inglês. Duas verificações por entrada:
//
//   1. **ainda existe no fonte** — uma amostra que sumiu não mede nada, que é o
//      mesmo resultado de uma lista vazia por um motivo diferente;
//   2. **`pareceInglesAmplo` a vê** — e é aqui que a lista de palavras é julgada.
//
//     dart run tool/word_list_probe.dart
//
// **Um zero no fim é o resultado que este arquivo mais produz**, e ele não
// distingue "a lista está completa" de "a lista parou de casar". Por isso a
// segunda verificação é uma **direção só** — texto que a lista **deveria** ver
// e não vê. O irmão na outra direção já existe: `test/` tem
// `'a varredura ainda enxerga os literais, filtro ou não'`.
import 'dart:io';

import 'package:mobilelm/services/text_language.dart';

/// Texto de tela em inglês que **li no fonte**, com o motivo de estar aqui.
///
/// O motivo é o que torna a lista auditável, pelo mesmo motivo de
/// `TextLanguage.naoTexto`: uma lista sem motivo é uma lista que ninguém
/// confere.
const amostras = <String, String>{
  'Benchmark running…': 'estado do card de benchmark; o filtro pegou pelo "running"',
  'Benchmark usability': 'mesmo ternário, ramo sem palavra que o filtro conheça',
  'CPU Safe mode, one short question. Takes a few seconds to load the model, then a few to answer.':
      'descrição do card; pega por "model" e "seconds"',
  'Not now': 'botão de diálogo de confirmação, sem palavra da lista',
  'Show it anyway': 'botão ao lado de "Hide the local model list"; pega pelo "Hide"',
  'Hide the local model list': 'pega por "the" e "list"',
  'Verifying...': 'rótulo de botão no mesmo ternário de "Save Key"',
  'Save Key': 'rótulo de botão; pega por "Save"',
  'No online model selected': 'pega por "online" e "model"',
  'You are about to download @m for use in the app.':
      'diálogo de download; com o valor no lugar, como a tela mostra',
  'Weights: @s + projector': 'rótulo de diálogo de download; o placeholder não é palavra',
  'Size: @s': 'rótulo de diálogo de download',
  'Name': 'label de campo de texto, sem palavra da lista',
  'Enter model name': 'hint de campo; pega por "model"',
  'Enter model URL': 'hint de campo; "URL" não está na lista e "Enter" também não',
  'Could not resolve file size. Ensure the URL is accessible.':
      'aviso do diálogo de download por URL; pega por "file"',
  '1 download in progress · its own bar is on its card':
      'rodapé do diálogo; pega por "download"',
  'https://huggingface.co/…/model.gguf':
      'hint de URL — exemplo, e a lista deveria recusá-lo por outro motivo',
};

void main() {
  final fonte = <String>[];
  for (final raiz in ['lib/views', 'lib/widgets', 'lib/controllers']) {
    final d = Directory(raiz);
    if (!d.existsSync()) continue;
    for (final f in d.listSync(recursive: true).whereType<File>()) {
      if (f.path.endsWith('.dart')) fonte.add(f.readAsStringSync());
    }
  }
  final todo = fonte.join('\n');

  var naoExiste = 0;
  var naoVisto = 0;
  for (final e in amostras.entries) {
    // **A conferência é pelo pedaço fixo, com o placeholder removido.** A chave
    // tem `@m` e o fonte tem `${model.name}`: comparar a chave inteira com o
    // fonte daria zero para toda amostra interpolada, que é o mesmo resultado de
    // uma lista vazia por um motivo diferente.
    final fixo = e.key.split('@').first.trim();
    if (!todo.contains(fixo)) {
      naoExiste++;
      stdout.writeln('SUMIU DO FONTE  "$fixo"\n    ${e.value}');
      continue;
    }
    // **O valor no lugar do placeholder**, porque é o que a tela mostra e é o
    // que o filtro tem que julgar: `@m` não é palavra de nenhum idioma.
    final naTela =
        e.key.replaceAll('@m', 'Qwen3-0.6B.litertlm').replaceAll('@s', '142 MB');
    if (!TextLanguage.pareceInglesAmplo(naTela)) {
      naoVisto++;
      stdout.writeln('NAO VISTO       "$naTela"\n    ${e.value}');
    }
  }
  stdout.writeln('--- sumiu do fonte: $naoExiste   '
      'nao vistos pela lista: $naoVisto   de ${amostras.length} amostras');
  stdout.writeln('--- englishWords: ${TextLanguage.englishWords.length} '
      'palavras · naoTexto: ${TextLanguage.naoTexto.length} entradas');
}
