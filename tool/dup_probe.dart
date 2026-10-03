// Sonda: a varredura AMPLA chega a reportar o MESMO literal duas vezes?
//
// **Ela é o controle positivo do conserto, e por isso ela existe.** O `vistos`
// da ferramenta marcava `m.start` e o `fim` devolvido por `juntarSegmentos`, mas
// nao marcava os inicios dos segmentos DO MEIO. Um literal adjacente de quatro
// linhas tem tres inicios intermediarios, e cada um deles passava por
// `vistos.add` sem estar la dentro — e reportava a mesma frase sem o primeiro
// segmento, que nao e traduzivel porque a frase esta no segmento de cima.
//
// Antes do parametro `inicios`, a sonda acusava **87 grupos com 155 inicios
// extras** e a varredura ampla reportava **257** textos de tela. Com o parametro:
// **0 grupos**, e a varredura reporta **212**. Os 45 que faltam nunca foram
// divida — eram fragmentos de um literal que ja estava na lista.
//
//     dart run tool/dup_probe.dart
//
// **Ela conta o que a FERRAMENTA reporta, e nao o que o fonte permite.** Isso e
// o que a distingue de uma contagem de literais aninhados, que e uma propriedade
// do fonte e nao um defeito: `'${x ? '' : ' '}'` tem dois literais dentro de um
// terceiro e sempre vai ter. O que nao pode existir e dois ACHADOS do mesmo
// literal, e para isso e que o laco abaixo repete o `vistos` da ferramenta letra
// por letra — uma sonda com a propria logica de deduplicacao mede a si mesma.
//
// Um zero aqui e o mesmo resultado de uma sonda que parou de olhar, entao ela
// imprime os grupos em vez de so o total, e o teste
// `test/inline_english_ratchet_test.dart` fixa o mesmo invariante.
//
// **Sobram 4, todos em `server_view.dart` e todos `DADO`, e eles nao sao o
// defeito deste arquivo.** Sao aspas duplas DENTRO de um `'''` de exemplo de
// `curl`: o regex casa a `"` que abre o `-H "Content-Type: …"` e o
// `juntarSegmentos` segue adiante, porque depois do fechamento dela vem um `\n`
// e outra `"`. Fechar isso exige saber que a interpolacao raw comecou num
// `'''`, que o regex nao ve. Nenhum dos quatro e texto de tela — sao exemplo de
// HTTP e Python — e por isso eles **nao entram** no teto, que conta so texto.
import 'dart:io';

import 'package:mobilelm/services/text_language.dart';

void main() {
  var grupos = 0;
  var repetidos = 0;
  final porArquivo = <String, int>{};
  for (final raiz in ['lib/views', 'lib/widgets', 'lib/controllers']) {
    final d = Directory(raiz);
    if (!d.existsSync()) continue;
    for (final f in d.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      final re = RegExp("\\'([^\\'\\n]{2,240})\\'|\"([^\"\\n]{2,240})\"");
      // **Por arquivo.** Um indice aqui e um indice la nao sao o mesmo lugar, e
      // um conjunto unico ja fez a contagem divergir 12 sem ninguem reclamar.
      final vistos = <int>{};
      // `fim` -> quantos ACHADOS chegaram nele. Dois achados com o mesmo `fim`
      // leram o mesmo trecho do fonte: um e um fragmento do outro.
      final fins = <int, String>{};
      for (final m in re.allMatches(src)) {
        if (!vistos.add(m.start)) continue;
        final inicios = <int>[];
        final (joined, fim) =
            TextLanguage.juntarSegmentos(src, m.start, inicios: inicios);
        if (joined.isEmpty) continue;
        vistos.addAll(inicios);
        vistos.add(fim);
        final anterior = fins[fim];
        if (anterior == null) {
          fins[fim] = joined;
          continue;
        }
        grupos++;
        repetidos++;
        porArquivo.update(f.path, (v) => v + 1, ifAbsent: () => 1);
        final linha = (int i) => src.substring(0, i).split('\n').length;
        stdout.writeln('${f.path}:${linha(m.start)} e '
            '${f.path}:${linha(fim)} repetem o mesmo literal\n'
            '    ja reportada: "$anterior"\n'
            '    repetida:     "$joined"');
      }
    }
  }
  stdout.writeln('--- grupos duplicados: $grupos   inicios extras: $repetidos');
  final ord = porArquivo.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in ord) {
    stdout.writeln('  ${e.value}\t${e.key}');
  }
}
