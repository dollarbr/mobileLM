import 'dart:ui' show Locale;

/// Qual idioma a tela fala, e como uma preferência salva vira um [Locale].
///
/// Existe porque o idioma **não pode ser deduzido**. O app já foi `pt_BR` com
/// `locale: Get.deviceLocale` e `fallbackLocale: pt_BR`, e o resultado foi uma
/// tela portuguesa num aparelho que podia estar em qualquer idioma — mais 62
/// descrições de catálogo em inglês, que é metade do defeito. Deduzir foi o
/// que produziu o problema, então deduzir virou **opção explícita** ("auto")
/// e o padrão passou a ser uma escolha declarada.
///
/// **O default é `en`, e isso não é cosmético.** O GetX devolve a própria chave
/// para uma tradução que não existe — foi assim que 38 chaves apareceram como
/// `tool_round_trips` e `mobile_lm` numa UI portuguesa, sem nada lançar. Com EN
/// como padrão, ligar o idioma sem o mapa em inglês renderiza 316
/// identificadores. Por isso o mapa existe inteiro, e
/// `test/language_preference_test.dart` falha se uma chave voltar a faltar em
/// qualquer um dos dois idiomas.
class LanguagePreference {
  const LanguagePreference._();

  /// Segue o idioma do aparelho.
  static const String auto = 'auto';
  static const String english = 'en';
  static const String portugueseBrazil = 'pt_BR';

  /// A ordem é a da tela: auto primeiro, porque é o que a maioria quer.
  static const List<String> opcoes = <String>[auto, english, portugueseBrazil];

  /// O padrão é **inglês**, e a escolha é do dono do app.
  static const String padrao = english;

  /// Normaliza o que veio do Hive.
  ///
  /// O Hive guarda string e um valor desconhecido é possível de três jeitos: um
  /// downgrade de versão, um arquivo editado à mão, ou o valor de um build
  /// futuro que este não conhece. Nenhum desses é erro de digitação que vale
  /// mostrar — e **nenhum pode derrubar a tela**, que é o que acontece se o
  /// `Locale` sai com `languageCode` vazio.
  ///
  /// Desconhecido cai em [auto], que é a única escolha que nunca está
  /// **errada**: ela segue o aparelho, que é o que quem não sabe o que pediu
  /// queria. Cair em `en` transformaria um valor corrompido em inglês fixo, e
  /// a pessoa nem perceberia que a preferência dela sumiu.
  static String normalizar(String? bruto) {
    if (bruto == null) return padrao;
    // **A comparação é em minúsculas e o retorno é a grafia canônica.** O
    // valor guardado é sempre um dos três de [opcoes], mas ele pode ter vindo
    // de um `.arb`, de um arquivo editado à mão ou de uma versão futura deste
    // código — e `pt-BR` é a mesma escolha que `pt_BR` com outra grafia.
    // Casar só a forma exata transformava uma grafia em lixo, e o lixo vira
    // `auto`: a preferência da pessoa era perd silenciosamente.
    switch (bruto.trim().toLowerCase()) {
      case auto:
        return auto;
      case english:
      case 'en_us':
      case 'en-us':
        return english;
      case portugueseBrazil:
      case 'pt-br':
      case 'pt_br':
      case 'pt':
        return portugueseBrazil;
      default:
        return auto;
    }
  }

  /// A [preferencia] virada no [Locale] que o `GetMaterialApp` recebe.
  ///
  /// **`auto` só tem uma regra, e ela é o parágrafo inteiro:** o aparelho em
  /// português (qualquer variante) mostra português, e qualquer outro idioma
  /// mostra inglês. O app não fala mais idiomas, então "outro idioma" não é
  /// erro — é o caso comum e ele é inglês.
  ///
  /// Sem aparelho ([device] nulo) o resultado é o [padrao], que é inglês.
  /// Antes do boot o `deviceLocale` ainda não existe, e um app que mostra a
  /// tela de splash em português para depois trocar para inglês tem um flicker
  /// que ninguém pediu; o inverso — inglês estável, depois troca — é o que a
  /// escolha do dono pede.
  static Locale resolver(String preferencia, Locale? device) {
    final p = normalizar(preferencia);
    if (p == english) return const Locale('en', 'US');
    if (p == portugueseBrazil) return const Locale('pt', 'BR');

    if (device == null || device.languageCode.isEmpty) {
      return const Locale('en', 'US');
    }
    return device.languageCode == 'pt'
        ? const Locale('pt', 'BR')
        : const Locale('en', 'US');
  }

  /// O idioma é português?
  ///
  /// Serve para a escolha que não é de texto: qual `description` do catálogo
  /// pintar. **Não usa a preferência e usa o [Locale]**, porque quem pergunta
  /// é a tela, e a tela já tem o [Locale] que o GetMaterialApp está usando.
  static bool ehPortugues(Locale? locale) => locale?.languageCode == 'pt';

  /// A descrição do catálogo no idioma pedido.
  ///
  /// **Os dois idiomas vêm com o nome no campo** (`descriptionEn`,
  /// `descriptionPt`) e a escolha acontece aqui. Um campo `description` que
  /// "significa português" é o que existia, e é o defeito que o seletor veio
  /// consertar: com EN como padrão, quem adiciona uma entrada com só
  /// `description` publica português num app inglês sem nenhum aviso.
  ///
  /// A queda é **do pedido para o que existe**, nunca para a string vazia: uma
  /// descrição em falta mostra a linha em branco num card que já tem nome,
  /// tamanho e template, e o vazio parece um erro do aparelho.
  static String descricao({
    required String? en,
    required String? pt,
    required Locale? locale,
  }) {
    final e = (en ?? '').trim();
    final d = (pt ?? '').trim();
    if (e.isEmpty && d.isEmpty) return '';
    if (e.isEmpty) return d;
    if (d.isEmpty) return e;
    return ehPortugues(locale) ? d : e;
  }

  /// O rótulo curto da opção, para a tela do seletor.
  ///
  /// **Os rótulos ficam no código e não no mapa `.tr`.** Um rótulo que se
  /// traduz para o idioma escolhido não diz mais qual idioma é — em português,
  /// "Auto", "Inglês" e "Português (Brasil)" dizem; em inglês, os mesmos nomes
  /// de novo. O nome do idioma é o dado, e um dado localizado deixa de
  /// identificar o idioma.
  static String rotulo(String opcao, Locale? locale) {
    final pt = ehPortugues(locale);
    switch (normalizar(opcao)) {
      case english:
        return 'English';
      case portugueseBrazil:
        return pt ? 'Português (Brasil)' : 'Portuguese (Brazil)';
      default:
        return pt ? 'Automático' : 'Automatic';
    }
  }
}
