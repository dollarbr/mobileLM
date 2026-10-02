import 'package:get/get.dart';

/// Preenche os `@nome` de um texto traduzido.
///
/// Existe porque **um literal interpolado é a única classe de texto de tela que
/// a ferramenta de varredura recusa de propósito**: `TextLanguage.looksEnglish`
/// devolve falso para qualquer texto com `$`, e está certo — o valor no fonte
/// não é o valor na tela, e trocar o literal inteiro por uma chave apagaria a
/// parte que muda. Deixada de fora, a classe reaparece em português numa tela
/// que já foi traduzida.
///
/// São 19 no primeiro levantamento, e todos com a mesma forma: um trecho fixo
/// em volta de um ou dois valores.
///
/// O GetX tem `trParams`, e ele é o padrão dele — mas substitui por uma chave só,
/// e metade destes textos tem **dois** valores, um no meio e outro no fim.
///
/// **Por que `replaceAll` e não interpolação do Dart:** a ordem das palavras
/// muda entre os idiomas. `"@n saltos"` e `"@n hops"` dão a mesma frase;
/// `"@n @m"` não dá, e a chave precisa poder dizer as duas coisas.
///
/// **Um `@nome` que sobra é erro de chave, não texto para o usuário.** Um `@n`
/// esquecido na tradução apareceria na tela como `@n`, que é o mesmo defeito do
/// GetX devolvendo o próprio identificador — por isso [preencher] exige que todo
/// `@nome` do texto traduzido esteja em [valores], e falha dizendo qual.
///
/// **A conferência é ANTES da troca, e não depois.** A primeira versão trocava
/// primeiro e olhava o resultado, e um valor com `@` no meio — um email, um nome
/// de arquivo como `meu@model.gguf` — criava um placeholder que ninguém pediu e
/// o helper recusava texto legítimo. O conjunto de placeholders vem da
/// **tradução**, que é onde ele está escrito, e é o único lugar de onde ele pode
/// vir com certeza.
String preencher(String chave, Map<String, String> valores) {
  final texto = chave.tr;
  for (final m in RegExp(r'@([A-Za-z_][A-Za-z0-9_]*)').allMatches(texto)) {
    final nome = m.group(1)!;
    if (!valores.containsKey(nome)) {
      throw ArgumentError(
          'a chave "$chave" tem @$nome sem valor — o texto traduzido é '
          '"$texto" e os valores são ${valores.keys.toList()}');
    }
  }
  var saida = texto;
  for (final entrada in valores.entries) {
    saida = saida.replaceAll('@${entrada.key}', entrada.value);
  }
  return saida;
}
