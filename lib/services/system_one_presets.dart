/// One click-and-run decision.
///
/// ## Why these exist at all
///
/// The window's problem is not that typing a decision is hard. It is that
/// **nobody can tell whether the answer is right.** A person types a state, picks
/// three options, and gets a letter — and if the letter is wrong there is no way
/// to know whether the model is wrong, the prompt is wrong, or the readout is
/// wrong. A preset fixes the first two, so what is left is the third.
///
/// That is the same argument the reranker presets make and the same reason they
/// are worth having: a preset is a **control**, not a demo. Every one of these
/// carries what the A72 actually answered, so a person can compare the number on
/// screen with the number that was measured.
///
/// ## The numbers are measurements, and they include the wrong ones
///
/// Two of these are here **because the model gets them wrong**, and that is the
/// useful part:
///
/// - `charge` — Tev1 says `billing` at 0.697, and the generated-letter path said
///   `A` for the same ticket. Correct.
/// - `outage` — Tev1's `P(true)` measured **0.5188** for "a service is down"
///   against a checkout returning 500. That is a coin flip on a question whose
///   answer is obviously yes, and it is the number the Laya card predicts
///   ("mean confidence never drops below 0.885 at any accuracy level").
/// - `forgot` — the generated-letter path answered `C` (account) in **50.7 s**,
///   and `A` (bug) twice in **2.0–2.2 s** for tickets where `A` was wrong. The
///   cost is part of the preset because the slowness is a fact about the readout,
///   not about one ticket.
///
/// **Nothing here is a claim that the model is good.** It is a record of what it
/// said on one phone on one day, and the window shows it next to the live
/// answer so the two can be compared.
class DecisionPreset {
  const DecisionPreset({
    required this.id,
    required this.state,
    required this.options,
    this.question,
    this.instruction,
    this.type = 'choice',
    this.measured,
    this.note,
  });

  /// Stable, and the key the translation uses.
  final String id;

  /// The state, verbatim — it goes into the JSON envelope the window builds.
  final String state;

  /// The options, in the order the letter assignment follows.
  final List<String> options;

  /// The question text. Null uses the window's own field, which a preset that
  /// sets options but not a question would leave describing a different thing.
  final String? question;

  /// The system instruction, or null for the model card's default.
  final String? instruction;

  /// Which of the three typed shapes this preset exercises.
  final String type;

  /// What the A72 answered, measured. Null when it was not measured on this path.
  ///
  /// A [String] and not a number: the two shapes report different things — a
  /// `choice` has a top probability, a `noul` has P(true), a `score` has an
  /// index — and one number field would have to mean three different numbers.
  final String? measured;

  /// Why this preset is here, when the measured answer is not obviously right.
  final String? note;

  /// The window's own question field is the id's default question, and this is it.
  static const String defaultQuestion = 'a que área isto pertence?';

  /// The four presets, ordered so the first one is the one that works.
  ///
  /// **Order is not alphabetical and it is not by difficulty.** It is by "does
  /// this answer something the previous one does not": a `choice` with three
  /// options, a `noul` whose answer should be yes and is not, a `score` on an
  /// ordered scale, and a decision model on a real ticket. A list ordered by
  /// name would put `charge` after `forgot` and the window's first click would be
  /// the one that times out.
  static const List<DecisionPreset> all = [
    DecisionPreset(
      id: 'charge',
      state: 'fui cobrado duas vezes pelo pedido #4417 neste mês',
      options: ['billing', 'technical support', 'account'],
      question: 'a que área isto pertence?',
      // **A instrução é a pergunta, e este preset só funciona porque está
      // escrita aqui — o A72 mediu o contrário.** Sem `instructions`, o endpoint
      // usa o **id** da pergunta como o texto dela, e o id desta janela é
      // `decision`. O mesmo estado, o mesmo modelo e as mesmas três opções dão
      // `C: account` 0,5847 / 0,2846 / 0,1307 com a pergunta `decision`, e
      // `A: billing` 0,5312 / 0,1640 / 0,3047 com a pergunta de verdade. A
      // segunda é a resposta certa para uma cobrança duplicada; a primeira é o
      // preset dizendo que_errou sem nenhum aviso.
      instruction: 'a que área isto pertence?',
      measured: 'billing nos DOIS · 0,6972 no Tev1 · 0,5312 no d1-3B',
      note: 'Os dois modelos acertam a área e discordam na força: 0,6972 com '
          'confiança 0,5458 no Tev1, 0,5312 com 0,2968 no d1-3B. A letra '
          'gerada disse A para o mesmo ticket.',
    ),
    DecisionPreset(
      id: 'outage',
      type: 'noul',
      state: 'Checkout started returning 500 errors at 9am and orders are blocked.',
      options: [],
      question: 'Is a service down?',
      instruction: 'Is a service down?',
      measured: 'P(true) 0,5188 no Tev1 · 0,5522 no d1-3B',
      note: 'A resposta óbvia é sim e os DOIS modelos deram quase uma moeda: '
          '0,5188 no Tev1 e 0,5522 no d1-3B, medidos em dias diferentes. É o '
          'número que o card da Laya descreve: confiança não pega erro. A '
          'resposta está certa e a confiança não ajuda.',
    ),
    DecisionPreset(
      id: 'urgency',
      type: 'score',
      state: 'fui cobrado duas vezes pelo pedido #4417',
      options: ['Can wait', 'This week', 'Today'],
      question: 'How urgent?',
      instruction: 'How urgent?',
      measured: 'nível 0 (Can wait) no Tev1 · nível 2 (Today) no d1-3B',
      note: 'Os DOIS modelos medidos, e eles discordam: o Tev1 respondeu "pode '
          'esperar" (0,5537) para uma cobrança duplicada, o que é errado, e o '
          'd1-3B respondeu "hoje" (0,5120), que é certo. O Tev1 é um decision '
          'model de LETRA pedido sobre um nível ordenado. É por isso que a '
          'medição cita o modelo: a mesma pergunta, o mesmo preset e duas '
          'respostas.',
    ),
    DecisionPreset(
      id: 'forgot',
      state: 'esqueceu a senha e não entra na conta',
      options: ['bug', 'billing', 'account'],
      question: 'a que área isto pertence?',
      // Mesma razão do `charge`: sem isto a pergunta do modelo seria a
      // palavra `decision`.
      instruction: 'a que área isto pertence?',
      measured: 'C (account) no Tev1, em 50,7 s',
      note: 'O caminho da letra levou 50,7 s aqui e 2,0 s em dois outros '
          'tickets, tudo no Tev1. O custo é do readout, não deste ticket. '
          'No d1-3B este preset ainda não foi medido.',
    ),
  ];

  /// The preset with [id], or null.
  static DecisionPreset? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// The translation key for the chip label.
  String get labelKey => 'soc_preset_$id';

  /// The translation key for the sentence under the chips.
  String get noteKey => 'soc_preset_note_$id';
}