/// The test window's model layer: what a System One model **is**, and what its
/// answer means.
///
/// Pure on purpose, for the same reason `decision_model.dart`,
/// `acceleration.dart` and `memory_readout.dart` are. The window's job is to let
/// somebody drive a decision on a phone, and the two things that can go wrong
/// there are both decidable without one:
///
/// 1. **Calling the wrong shape.** A decision model and a classification head
///    take different bodies on the same endpoint, and a window that guesses
///    produces a refusal that reads like a broken model.
/// 2. **Inventing a number.** Both endpoints return `relevance_score: null` and
///    a `why_…` string saying why. A window that quietly drops the null and
///    shows a bar chart of raw logits as though it were confidence is lying, and
///    it would be the first place in the app that does.
///
/// ## What a "System One" model is
///
/// The name comes from the four that made it worth naming — Jev, Laya, Tev1 and
/// Bespoke-Nimble — and the class is **open**: it is "a model that answers a
/// structured question with a class", and the next one published will be in it
/// without anybody editing this file. So nothing here keys off those four
/// names, and there is a test that says so.
///
/// That is not a style choice. It is the rule the 0.4.0 encoders already
/// settled: **the role comes from what the file is, never from what it is
/// called**. `bge-small-en-v1.5` was once classified as a classifier because
/// something read the name and guessed, and the cost of that class of bug is a
/// screen that lies about the model on it.
///
/// ## The one thing both shapes share
///
/// **The label set belongs to the caller.** A decision model is given its
/// options; a head's class 0 is whatever the person who trained it decided.
/// Neither carries its own names, so the window has to ask for them, and both
/// endpoints return `label: null` rather than guess. Getting this backwards is
/// the whole reason the app has no "confidence" anywhere in this file.
library;

import 'dart:convert';

/// How a System One model answers, decided from facts about the file.
enum SystemOneShape {
  /// A plain language model fine-tuned to answer with **one letter** — Tev1,
  /// Bespoke-Nimble, OpenJev.
  ///
  /// Decided by **absence**: a loaded GGUF that carries no `cls.output.weight`
  /// cannot use the head path, because the head path scores classes that this
  /// kind of model does not have.
  decision,

  /// A `.tflite` classification head — the Laya act head is the one that
  /// exists.
  ///
  /// Decided by the **file extension alone**, with nothing loaded and nothing
  /// asked. A head has no `cls.*` tensor to be recognised by, so the extension
  /// is the only fact available, and it is a fact rather than a setting.
  tfliteHead,

  /// A GGUF that carries a real classification head and scores every class in
  /// one forward pass.
  ///
  /// This is the shape the **encoder console** already drives, so the window
  /// treats it as a known thing rather than re-testing it.
  ggufHead,

  /// Not enough is known yet.
  ///
  /// A GGUF's shape is unknowable until it is loaded, and a window that picked
  /// one anyway would send a body the endpoint refuses. Unknown is the honest
  /// answer, and it is why the window asks the server rather than deciding.
  unknown,
}

/// The shape of [filename], from what is known about it.
///
/// [isTflite] and [hasClassificationHead] are the two facts that exist, and
/// [filename] is only ever consulted for its extension — **never for its name**.
/// [isTflite] is passed in rather than derived from [filename] so that a caller
/// which already knows (the catalogue, the model card) and a caller which is
/// guessing from the extension cannot silently disagree; when it is null the
/// extension decides, and that is the weaker answer.
SystemOneShape systemOneShapeOf({
  String? filename,
  bool? isTflite,
  bool? hasClassificationHead,
}) {
  final tflite = isTflite ?? (filename?.toLowerCase().endsWith('.tflite') ?? false);
  if (tflite) return SystemOneShape.tfliteHead;
  if (hasClassificationHead == null) return SystemOneShape.unknown;
  return hasClassificationHead ? SystemOneShape.ggufHead : SystemOneShape.decision;
}

/// Whether a shape answers a class at all, as opposed to chat.
///
/// [SystemOneShape.unknown] is **false**, and that is deliberate: a window that
/// treats "not decided" as "probably a decision model" is how the wrong body
/// gets sent. A caller has to resolve [SystemOneShape.unknown] first.
bool isClassAnswering(SystemOneShape shape) =>
    shape == SystemOneShape.decision ||
    shape == SystemOneShape.tfliteHead ||
    shape == SystemOneShape.ggufHead;

/// One option in a decision, and the label a class index carries.
class SystemOneOption {
  const SystemOneOption(this.letter, this.label);

  final String letter;
  final String label;

  SystemOneOption copyWith({String? letter, String? label}) =>
      SystemOneOption(letter ?? this.letter, label ?? this.label);

  @override
  String toString() => '$letter: $label';
}

/// The option list, edited in the window and sent as the endpoint's `choices`.
///
/// Immutable, because the window rebuilds it on every keystroke and a mutable
/// list here would mean the sent body and the shown body can differ.
class SystemOneOptions {
  const SystemOneOptions(this.items);

  final List<SystemOneOption> items;

  static const SystemOneOptions empty = SystemOneOptions([]);

  /// The starting list, and it is the measured one.
  ///
  /// Tev1's card asks for 2–24 options, and the three that came out of the A72
  /// run are the ones a support queue actually has. Starting empty would make
  /// the first tap produce a 400 that says "at least two", which teaches the
  /// shape of the API but not the task.
  static const SystemOneOptions starter = SystemOneOptions([
    SystemOneOption('A', 'bug'),
    SystemOneOption('B', 'billing'),
    SystemOneOption('C', 'account'),
  ]);

  /// The letters available, in order. 24 is the endpoint's cap, and A–X is 24.
  static const List<String> letters = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', //
    'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P',
    'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X',
  ];

  /// Why this list cannot be sent, or null when it can.
  ///
  /// Fewer than two is not a choice — the endpoint refuses it, and a one-option
  /// "decision" is a model that always agrees, which is a decision endpoint that
  /// cannot say no. More than 24 is the card's cap, not this window's taste.
  String? get problem {
    if (items.length < 2) return 'At least two options.';
    if (items.length > 24) return 'At most 24 options.';
    for (final o in items) {
      if (o.label.trim().isEmpty) return 'Option ${o.letter} has no label.';
    }
    final seen = <String, String>{};
    for (final o in items) {
      final letter = o.letter.trim().toUpperCase();
      if (letter.isEmpty) return 'An option has no letter.';
      final key = o.label.trim().toLowerCase();
      final before = seen[letter];
      if (before != null && before != key) {
        return 'Letter $letter is used twice, for "$before" and "$key".';
      }
      seen[letter] = key;
    }
    return null;
  }

  bool get isValid => problem == null;

  /// The body the generative path wants.
  ///
  /// Keyed by the letter **as typed**, upper-cased, because `parseDecisionAnswer`
  /// accepts either case and a lower-case key would show up in a `curl` the user
  /// copied as a difference from the model card.
  Map<String, String> toChoices() => {
        for (final o in items) o.letter.trim().toUpperCase(): o.label.trim(),
      };

  SystemOneOptions add() {
    if (items.length >= letters.length) return this;
    final used = items.map((o) => o.letter.trim().toUpperCase()).toSet();
    final next = letters.firstWhere((l) => !used.contains(l), orElse: () => '');
    if (next.isEmpty) return this;
    return SystemOneOptions([...items, SystemOneOption(next, '')]);
  }

  /// Remove the option at [index], and say if it was not there.
  SystemOneOptions removeAt(int index) {
    if (index < 0 || index >= items.length) return this;
    final next = [...items]..removeAt(index);
    return SystemOneOptions(next);
  }

  SystemOneOptions replace(int index, SystemOneOption option) {
    if (index < 0 || index >= items.length) return this;
    final next = [...items];
    next[index] = option;
    return SystemOneOptions(next);
  }

  /// Parse the textarea form: one option per line, `A label` or just `label`.
  ///
  /// A bare label gets the next unused letter, so a user who does not care about
  /// letters never types one, and a user who does can pin them. Parsing is
  /// **not** validation: a line with no label is kept as an empty label so the
  /// window can show the problem next to the row that has it, instead of
  /// dropping the row and leaving the user to wonder where it went.
  ///
  /// Two shapes of line that the first version got wrong, both found by the
  /// tests rather than by reading it:
  ///
  /// - **A repeated letter still loses the prefix.** On `A bug` then
  ///   `A billing`, the second line is the pinned form with a letter already
  ///   taken. Treating the whole line as a label produces an option called
  ///   "A billing" — which is neither what the user typed as a label nor what
  ///   they typed as a letter, and it is silent.
  /// - **A line that is only a letter is an option with no label.** `A bug` then
  ///   `B` used to become an option auto-lettered `B` and labelled `"B"`, so the
  ///   row said `B: B` and validated. The user gets a row with an empty field
  ///   and a message on it, which is the state they can fix.
  static SystemOneOptions parse(String text) {
    final out = <SystemOneOption>[];
    final used = <String>{};
    var nextIndex = 0;

    String nextFreeLetter() {
      while (nextIndex < SystemOneOptions.letters.length &&
          used.contains(SystemOneOptions.letters[nextIndex])) {
        nextIndex++;
      }
      return nextIndex < SystemOneOptions.letters.length
          ? SystemOneOptions.letters[nextIndex]
          : '';
    }

    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      var letter = '';
      var label = line;

      // `A label` — the pinned form. The letter has to be in range, so a label
      // beginning with a word like "A conta" is not read as option A; and a
      // label that *is* option A keeps the word after the separator, which is
      // the point of requiring a separator rather than just a capital.
      final pinned = RegExp(r'^([A-Za-z])[\s).:\-]+(.+)$').firstMatch(line);
      // `A` on its own: an option whose label is still blank.
      final bare = RegExp(r'^([A-Za-z])$').firstMatch(line);

      final String? candidate = pinned?.group(1) ?? bare?.group(1);
      if (candidate != null) {
        final up = candidate.toUpperCase();
        if (SystemOneOptions.letters.contains(up)) {
          letter = up;
          label = pinned != null ? pinned.group(2)!.trim() : '';
        }
      }

      if (letter.isEmpty) {
        letter = nextFreeLetter();
        nextIndex++;
      } else if (used.contains(letter)) {
        // Pinned to a letter already taken: keep the label, move the letter.
        letter = nextFreeLetter();
        nextIndex++;
      }

      if (letter.isEmpty) continue;
      used.add(letter);
      out.add(SystemOneOption(letter, label));
    }
    return SystemOneOptions(out);
  }

  /// The textarea form back, so the two directions cannot drift.
  String toText() => items.map((o) => '${o.letter} ${o.label}').join('\n');
}

/// The caller's labels for a head's classes, **in class-index order**.
///
/// A separate type from [SystemOneOptions] because the two limits are not the
/// same and reusing one for both invents a limit that does not exist:
///
/// - the **decision** path is 2–24, and that is the Tev1 card's number, checked
///   in `toChoices`'s owner above;
/// - a **head** has as many classes as it was trained with, and the act head has
///   two while a 350-way label set is a normal thing to bring to a 512-way head.
///   Refusing 25 labels here would be the app inventing a rule.
///
/// No letters either: on the logits path the order **is** the identity, and
/// showing "A"/"B" over class 0 and class 1 suggests the letter is what selects
/// the class, which is not how anything reads it.
class SystemOneLabels {
  const SystemOneLabels(this.items);

  final List<String> items;

  static const SystemOneLabels empty = SystemOneLabels([]);

  int get length => items.length;

  bool get isEmpty => items.isEmpty;

  /// Whether this list can be sent, and why not when it cannot.
  ///
  /// **No upper bound, deliberately.** The 24 is the decision card's.
  String? get problem {
    if (items.isEmpty) return 'At least one label.';
    for (var i = 0; i < items.length; i++) {
      if (items[i].trim().isEmpty) return 'Label ${i + 1} is empty.';
    }
    return null;
  }

  bool get isValid => problem == null;

  List<String> toJson() => [for (final l in items) l.trim()];

  SystemOneLabels replace(int index, String label) {
    if (index < 0 || index >= items.length) return this;
    final next = [...items];
    next[index] = label;
    return SystemOneLabels(next);
  }

  /// Append an empty row, so there is always somewhere to type.
  SystemOneLabels addBlank() => SystemOneLabels([...items, '']);

  SystemOneLabels removeAt(int index) {
    if (index < 0 || index >= items.length) return this;
    final next = [...items]..removeAt(index);
    return SystemOneLabels(next);
  }

  /// The two the Laya act head actually has, as a starting point.
  ///
  /// Named, and **only** because the head is published with two outputs — the
  /// names come from the act head's own documentation and are the one case where
  /// this app is not guessing, because the model's author said what they are.
  static const SystemOneLabels starter = SystemOneLabels([
    'not a persona',
    'is a persona',
  ]);
}

/// What the phone has loaded, as the three endpoints report it.
///
/// A class and not a pair of fields because **there are three sources and they
/// do not overlap**, and the first version of the window looked at one of them
/// and said a falsehood about the other two:
///
/// - `GET /v1/models/local` → `loaded: {filename, runtime, backend, gpu,
///   gpu_layers, accelerated, vision}`. **GGUF only.** There is no `classifier`
///   key in it — the first version of the window read `loaded['classifier']`,
///   which is therefore always null, so every loaded GGUF came out as a decision
///   model including a GGUF that really does carry a classification head. A
///   field that does not exist reads exactly like a field that is false, which
///   is why it went unnoticed.
/// - `GET /v1/server/capabilities` → `capabilities.classify`, the real flag, and
///   the only one that knows whether a `cls.output.weight` is in the file.
/// - `GET /v1/litert/status` → `loaded` for the **LiteRT** runtime, which is a
///   different runtime in a different plugin and does not appear in the caller's
///   `loaded` at all. The window opened from the server screen said "nothing
///   loaded" with a `.tflite` head loaded and its contract on the next screen.
class DeviceState {
  const DeviceState({
    this.ggufName = '',
    this.ggufRuntime = '',
    this.ggufClassifies = false,
    this.tfliteName = '',
  });

  final String ggufName;
  final String ggufRuntime;

  /// From `capabilities.classify` — **not** from anything in
  /// `/v1/models/local`, which does not carry it.
  final bool ggufClassifies;

  final String tfliteName;

  bool get hasGguf => ggufName.isNotEmpty;

  bool get hasTflite => tfliteName.isNotEmpty;

  bool get isEmpty => !hasGguf && !hasTflite;

  /// Parse the three responses. Each one is optional, because each probe is
  /// independent and one failing must not blank the other two.
  static DeviceState fromResponses({
    Map<String, dynamic>? local,
    Map<String, dynamic>? capabilities,
    Map<String, dynamic>? litertStatus,
  }) {
    final loaded = local?['loaded'];
    final caps = capabilities?['capabilities'];
    return DeviceState(
      ggufName: loaded is Map ? '${loaded['filename'] ?? ''}' : '',
      ggufRuntime: loaded is Map ? '${loaded['runtime'] ?? ''}' : '',
      ggufClassifies: caps is Map && caps['classify'] == true,
      tfliteName: litertStatus?['loaded'] is Map
          ? '${(litertStatus!['loaded'] as Map)['path'] ?? ''}'
                  .split('/')
                  .last
          : '',
    );
  }
}

/// The shape to drive, resolved from what is loaded — or null when nothing is.
///
/// [given] wins when it is not [SystemOneShape.unknown], because the card the
/// user tapped named it and a card is a better source than a poll. Past that,
/// the order is the one that answers the question honestly:
///
/// 1. a **GGUF that classifies** is a head with its own label set — the
///    encoder console drives that one and this window has nothing to ask;
/// 2. a **GGUF that does not** is a decision model, because a GGUF with no
///    `cls.output.weight` cannot use the head path and the head path is the only
///    other one `/v1/classify` has;
/// 3. a **`.tflite`** is a head, and the window takes its name and works.
///
/// The `.tflite` in third rather than first is the point. Both runtimes can be
/// loaded at once — they are different plugins and separate endpoints — and when
/// both are, a GGUF is the one `/v1/classify` will route to, so the GGUF decides.
SystemOneShape? resolveSystemOneShape(
  DeviceState device, {
  SystemOneShape given = SystemOneShape.unknown,
}) {
  if (given != SystemOneShape.unknown) return given;
  if (device.hasGguf) {
    return device.ggufClassifies
        ? SystemOneShape.ggufHead
        : SystemOneShape.decision;
  }
  if (device.hasTflite) return SystemOneShape.tfliteHead;
  return null;
}

/// The `.tflite` the window should name, or null for the other shapes.
///
/// The card's file wins; otherwise the one that is loaded. Empty when neither,
/// and empty is a real answer: the head path cannot be driven by name alone,
/// because a head has no `cls.output.weight` to be recognised by.
String? resolveSystemOneHeadFilename(
  DeviceState device, {
  String? fromCard,
}) {
  if (fromCard != null && fromCard.isNotEmpty) return fromCard;
  return device.hasTflite ? device.tfliteName : null;
}

/// What a head declares it wants, read out of what the server reported.
///
/// Pure, and built from a payload **taken off the device** rather than one
/// written here — which is the whole reason it exists as its own type.
///
/// The first version of the window parsed the feature count out of
/// `POST /v1/litert/screen` by looking for a `signature` object with an `inputs`
/// list. On the A72 that screen returns a **`signatures` array**, each entry
/// with its own `inputs`, and the parse found nothing and reported "any length
/// is fine" for a head that wants 1024 numbers. The unit test for it passed,
/// because the test fed it the shape I had imagined. Measured shape, from
/// `laya_en_act_head_fp32.tflite` on the Galaxy A72:
///
/// ```json
/// {"version":3,"signatures":[{"signature":"serving_default","subgraph":0,
///   "inputs":[{"name":"feats","type":"FLOAT32","shape":[1,4]},
///             {"name":"pooled_cls","type":"FLOAT32","shape":[1,1024]}],
///   "outputs":[{"name":"act_logits","type":"FLOAT32","shape":[1,2]}],
///   "bindable":true}],"default":"serving_default"}
/// ```
///
/// Note `feats` before `pooled_cls` — the 4-element auxiliary is stored first,
/// which is the measured reason the feature tensor is the **largest** input and
/// not the first one.
///
/// [fromStatus] reads the richer form `GET /v1/litert/status` returns once a head
/// is loaded, where the server has already done the same analysis and named the
/// feature tensor directly.
class HeadContract {
  const HeadContract({
    this.featureName = '',
    this.featureCount,
    this.auxiliary = const [],
    this.classCount,
    this.signature = '',
  });

  /// The tensor that carries the features, and how many numbers it wants.
  final String featureName;
  final int? featureCount;

  /// Inputs beyond the feature vector: name and how many numbers each wants.
  final List<HeadAuxiliary> auxiliary;

  /// How many classes come out, when the file said.
  final int? classCount;

  final String signature;

  /// From `GET /v1/litert/status`, whose `loaded.head` names all of it.
  ///
  /// Null when nothing is loaded, which is a real state and not a failure: the
  /// window's caller has to load the head first, and the message that says so
  /// names the endpoint.
  static HeadContract? fromStatus(Map<String, dynamic> json) {
    final loaded = json['loaded'];
    if (loaded is! Map) return null;
    final head = loaded['head'];
    if (head is! Map) return null;
    final features = head['features'];
    if (features is! Map) return null;
    return HeadContract(
      featureName: '${features['name'] ?? ''}',
      featureCount: _elementCount(features['shape']),
      classCount: _elementCount((head['logits'] as Map?)?['shape']),
      auxiliary: _auxiliaryOf(head['auxiliary']),
      signature: '${loaded['signature'] ?? ''}',
    );
  }

  /// From `POST /v1/litert/screen`, which is what is available before a load.
  ///
  /// Falls back across both shapes on purpose: the array is what the A72 sends,
  /// and a single object is what a one-signature tool would naturally produce, so
  /// accepting both costs four lines and removes a question.
  static HeadContract? fromScreen(Map<String, dynamic> json) {
    Map<String, dynamic>? sig;
    final list = json['signatures'];
    if (list is List && list.isNotEmpty && list.first is Map) {
      sig = list.first as Map<String, dynamic>;
    } else if (json['signature'] is Map) {
      sig = json['signature'] as Map<String, dynamic>;
    }
    final inputs = sig?['inputs'];
    if (inputs is! List || inputs.isEmpty) return null;

    // **The largest input is the feature vector**, for the reason the whole file
    // keeps repeating: the act head stores `feats [1,4]` before
    // `pooled_cls [1,1024]`, so "the first" picks the auxiliary and the window
    // would then tell the user a head wants 4 numbers and it wants 1024.
    Map<String, dynamic>? biggest;
    var biggestCount = 0;
    final rest = <HeadAuxiliary>[];
    for (final t in inputs) {
      if (t is! Map) continue;
      final count = _elementCount(t['shape']) ?? 0;
      final entry = Map<String, dynamic>.from(t);
      if (count > biggestCount) {
        // The **old** biggest becomes an auxiliary. The first version pushed
        // `entry` — the new one — which left the auxiliary list holding the
        // feature tensor and dropped the real auxiliary, and the test caught it
        // on the first payload taken off the device.
        if (biggest != null) rest.add(_aux(biggest, biggestCount));
        biggest = entry;
        biggestCount = count;
      } else {
        rest.add(_aux(entry, count));
      }
    }
    // No readable shape on any input means **null, not a contract with a null
    // count**. A null count reads as "this head wants some number of numbers,
    // unknown how many", and the window would then let the user paste whatever
    // and learn the answer from a 400. Null reads as "this is not a head I can
    // build a request for", which is what is true, and the message that comes
    // with it can say so.
    if (biggest == null) return null;
    return HeadContract(
      featureName: '${biggest['name'] ?? ''}',
      featureCount: biggestCount == 0 ? null : biggestCount,
      classCount: _outputCount(sig),
      auxiliary: rest,
      signature: '${sig?['signature'] ?? ''}',
    );
  }

  /// How many classes the first output holds, or null when it does not say.
  static int? _outputCount(Map<String, dynamic>? sig) {
    final outputs = sig?['outputs'];
    if (outputs is! List || outputs.isEmpty) return null;
    final first = outputs.first;
    if (first is! Map) return null;
    return _elementCount(first['shape']);
  }

  static HeadAuxiliary _aux(Map<String, dynamic> t, int? count) =>
      HeadAuxiliary('${t['name'] ?? ''}', count);
}

/// One input beyond the feature vector.
class HeadAuxiliary {
  const HeadAuxiliary(this.name, this.count);

  final String name;
  final int? count;

  @override
  String toString() => count == null ? name : '$name [$count]';
}

List<HeadAuxiliary> _auxiliaryOf(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final t in raw)
      if (t is Map)
        HeadAuxiliary('${t['name'] ?? ''}', _elementCount(t['shape'])),
  ];
}

/// How many numbers a shape holds, or null when it does not say.
///
/// The product, not the last dimension: `pooled_cls [1,1024]` is 1024 numbers
/// and `feats [1,4]` is 4, and reading only the last dimension gets both right
/// by accident on a batch of 1 — which is the only batch anybody sends. The
/// product is right for every batch, and the batch dimension is what makes a
/// head's count a guess rather than a fact if it is ignored.
int? _elementCount(Object? shape) {
  if (shape is! List || shape.isEmpty) return null;
  var n = 1;
  for (final d in shape) {
    if (d is! num) return null;
    n *= d.toInt();
  }
  return n;
}

/// A feature vector on its way into a head.
///
/// Two sources, and they are **not equivalent**, which is the reason this is a
/// class and not a `List<double>`:
///
/// - a **pasted** vector — the caller got it somewhere and knows what it is;
/// - one this app **embedded** with a chosen encoder, which is a claim the
///   window can make and cannot verify.
///
/// The second is the whole reason the Laya act head is reachable at all: it
/// wants 1024 floats and nobody types 1024 floats. But an embedding from a
/// ModernBERT encoder is not the same space as the `pooled_cls` a *different*
/// encoder produced, and no code here can tell whether the pairing is right —
/// the vectors are both 1024 long and both plausible. So [source] is carried all
/// the way to the display and shown, instead of the window presenting a vector
/// it generated as if it were ground truth.
class FeatureVector {
  const FeatureVector(this.values, {this.source = 'pasted', this.expectedCount});

  final List<double> values;

  /// Where it came from, in the caller's words. Shown next to the result.
  final String source;

  /// What the head says it wants, when the head has been screened. Null means
  /// unknown, which is not the same as "any length is fine".
  final int? expectedCount;

  int get length => values.length;

  /// Why this vector cannot be sent, or null when it can.
  String? get problem {
    if (values.isEmpty) return 'No numbers in the vector.';
    if (expectedCount != null && values.length != expectedCount) {
      return 'The head wants $expectedCount numbers, this vector has '
          '${values.length}.';
    }
    return null;
  }

  bool get isValid => problem == null;

  List<double> toJson() => values;

  /// Parse a pasted vector: whitespace, commas and newlines all separate.
  ///
  /// Returns null for a token that is not a number, rather than dropping it —
  /// a 1024-number vector with one silently ignored element is a wrong answer
  /// with no way to see it, and the count check above is exactly the thing that
  /// catches it.
  static FeatureVector? parse(String text) {
    final cleaned = text.replaceAll(RegExp(r'[\s,\[\]]+'), ' ').trim();
    if (cleaned.isEmpty) return null;
    final out = <double>[];
    for (final token in cleaned.split(' ')) {
      if (token.isEmpty) continue;
      final v = double.tryParse(token);
      if (v == null) return null;
      out.add(v);
    }
    return out.isEmpty ? null : FeatureVector(out);
  }
}

/// What one run produced, whichever shape produced it.
///
/// One class for both, because the window shows both and a UI that switches
/// types per shape is a UI with two sets of bugs. The fields that do not apply
/// are null, and **the reason they are null is carried too** — see [whyNoScore].
class SystemOneResult {
  const SystemOneResult({
    this.model = '',
    this.shape,
    this.label,
    this.letter,
    this.logits,
    this.topIndex,
    this.logitLabels = const [],
    this.whyNoScore,
    this.raw,
    this.notes = const [],
    this.auxiliaryUsed = const [],
    this.featuresInput,
    this.featureSource,
    this.requestedAccelerator,
    this.availableAccelerators = const [],
    this.failure,
  });

  final String model;
  final SystemOneShape? shape;

  /// The caller's label for the answer. From the model's own letter on the
  /// decision path, from the caller's own list by index on the logits path.
  final String? label;

  /// The letter the model emitted. Null on the logits path — there is no letter
  /// in a logit vector, and printing "A" there would be a decision the app made.
  final String? letter;

  final List<double>? logits;
  final int? topIndex;

  /// The caller's labels, by class index. **Empty when the caller supplied
  /// none**, which is the normal case for a `.tflite`, and the display then says
  /// so instead of numbering classes as if the numbers meant something.
  final List<String> logitLabels;

  /// The endpoint's own explanation of why there is no score.
  ///
  /// Kept verbatim, and shown. A window that hid this would leave the user
  /// looking at numbers with nowhere to put them, and the natural next question
  /// — "so what is 0.81?" — is one the app cannot answer.
  final String? whyNoScore;

  /// The decision model's own text, for a clean answer and for a refused one.
  final String? raw;

  /// Everything the response carried that is true and not one of the above.
  final List<String> notes;

  final List<String> auxiliaryUsed;
  final String? featuresInput;
  final String? featureSource;
  final String? requestedAccelerator;
  final List<String> availableAccelerators;

  /// The refusal, verbatim, when the run failed.
  ///
  /// A failed decision is a **result on this screen**, not an error toast: the
  /// endpoint answers 422 with the raw text for exactly the case where the
  /// model wrote prose, and that text is the only way to see what happened.
  final String? failure;

  /// A result with nothing in it, for the formatter and for tests.
  static const empty = SystemOneResult();

  bool get isFailure => failure != null;

  /// The class the caller's own labels give this answer, or null.
  ///
  /// Null when there are no logits, and null when there are more logits than
  /// labels — the head was trained on a label set the caller did not supply, and
  /// "class 3" is the honest way to say so.
  String? get labelledTop {
    final t = topIndex;
    if (t == null) return null;
    if (t < 0 || t >= logitLabels.length) return null;
    final l = logitLabels[t].trim();
    return l.isEmpty ? null : l;
  }

  /// The label for a class index, with the honest fallback.
  String labelAt(int index) {
    if (index < 0 || index >= logitLabels.length) return 'class $index';
    final l = logitLabels[index].trim();
    return l.isEmpty ? 'class $index' : l;
  }

  bool get hasCallerLabels => logitLabels.isNotEmpty;

  /// Parse a `POST /v1/classify` response, whatever shape it came back in.
  ///
  /// Takes the status alongside the body because **the refusal is data here**:
  /// a 422 carries the model's raw text and the options it should have picked
  /// from, and treating it as a transport error throws away the only evidence.
  ///
  /// [callerLabels] is the caller's own label list, passed in rather than read
  /// out of the response, because it belongs to the **request**: the `.tflite`
  /// path returns `label: null` and sends no label set at all, so a window that
  /// read the labels from the body would display "class 0" for a run the user
  /// had labelled in the field above it. A GGUF head that does carry labels uses
  /// those instead.
  SystemOneResult fromClassify(
    Map<String, dynamic> json, {
    int status = 200,
    List<String> callerLabels = const [],
  }) {
    final model = _str(json['model']) ?? '';
    final labels = callerLabels.isNotEmpty ? callerLabels : (_strings(json['labels']) ?? const []);
    final error = _str(json['error']);
    if (error != null) {
      final bits = <String>[error];
      final raw = _str(json['raw']);
      if (raw != null && raw.isNotEmpty) bits.add('said: $raw');
      final expected = json['expected_one_of'];
      if (expected is List && expected.isNotEmpty) {
        bits.add('expected one of ${expected.join(', ')}');
      }
      return SystemOneResult(
        model: model,
        shape: shape,
        failure: bits.join(' — '),
        whyNoScore: _str(json['why_no_score']),
        notes: _notes(json),
      );
    }
    if (status != 200) {
      return SystemOneResult(
        model: model,
        shape: shape,
        failure: error ?? 'HTTP $status',
        notes: _notes(json),
      );
    }

    final logits = _doubles(json['logits']);
    if (logits != null) {
      final top = json['top_index'];
      return SystemOneResult(
        model: model,
        shape: shape ?? SystemOneShape.tfliteHead,
        logits: logits,
        topIndex: top is int ? top : null,
        logitLabels: labels,
        label: _str(json['label']),
        whyNoScore: _str(json['why_no_score']),
        auxiliaryUsed: _strings(json['auxiliary_used']) ?? const [],
        featuresInput: _str(json['features_input']),
        featureSource: _str(json['feature_source']),
        requestedAccelerator: _str(json['requested']),
        availableAccelerators: _strings(json['available']) ?? const [],
        notes: _notes(json),
      );
    }

    return SystemOneResult(
      model: model,
      shape: shape ?? SystemOneShape.decision,
      label: _str(json['label']),
      letter: _str(json['choice']),
      whyNoScore: _str(json['why_no_scores']),
      notes: _notes(json),
    );
  }

  /// A client-side refusal, so a window that never sent anything still shows a
  /// result shape instead of a blank panel.
  factory SystemOneResult.failed(String message, {String model = ''}) =>
      SystemOneResult(model: model, failure: message);

  /// The JSON body for the decision shape.
  ///
  /// `input` **and** `state` are both accepted by the endpoint for the same
  /// field, and this sends `state` because that is the Bespoke payload's name
  /// and the window's field is the state.
  Map<String, dynamic> decisionBody({
    required String state,
    required String question,
    required SystemOneOptions options,
    String? instruction,
  }) {
    final body = <String, dynamic>{
      'state': state,
      if (question.trim().isNotEmpty) 'question': question.trim(),
      'choices': options.toChoices(),
    };
    if (instruction != null && instruction.trim().isNotEmpty) {
      body['instruction'] = instruction;
    }
    return body;
  }

  /// The JSON body for a `.tflite` head.
  ///
  /// [filename] is **required** here and optional on the other two shapes, for
  /// the reason the endpoint documents: a head has no `cls.output.weight` to be
  /// recognised by, so the caller is the only thing that can say which head it
  /// means.
  ///
  /// [labels] is **not** sent. The `.tflite` path returns `label: null` and
  /// ignores a label set, because the label set belongs to whoever trained the
  /// head and only the caller knows it — so they are held on this side and
  /// passed back into [fromClassify], and putting them on the wire would be
  /// asking the endpoint to echo a name back to the person who sent it.
  Map<String, dynamic> tfliteBody({
    required String filename,
    required FeatureVector features,
    Map<String, FeatureVector> auxiliary = const {},
    String? featuresInput,
  }) {
    return {
      'filename': filename,
      'features': features.toJson(),
      if (auxiliary.isNotEmpty)
        'auxiliary_inputs': {
          for (final e in auxiliary.entries) e.key: e.value.toJson(),
        },
      if (featuresInput != null && featuresInput.isNotEmpty)
        'features_input': featuresInput,
    };
  }
}

String? _str(Object? v) {
  if (v == null) return null;
  final s = '$v';
  return s.isEmpty ? null : s;
}

List<double>? _doubles(Object? v) {
  if (v is! List || v.isEmpty) return null;
  final out = <double>[];
  for (final e in v) {
    if (e is! num) return null;
    out.add(e.toDouble());
  }
  return out;
}

List<String>? _strings(Object? v) {
  if (v is! List) return null;
  return [for (final e in v) '$e'];
}

/// The scalar fields a response carries that are true and not part of the answer.
///
/// Drawn from a fixed list rather than by iterating the map, because a response
/// also carries `error`, `raw`, `expected_one_of` and the `why_…` strings — and
/// dumping those into a "notes" list is how a refusal ends up displayed as a
/// successful run with the failure in the details.
List<String> _notes(Map<String, dynamic> json) {
  const interesting = [
    'runtime',
    'signature',
    'n_classes',
    'executed_accelerator',
    'executed_accelerator_note',
    'seconds',
    'loaded',
  ];
  return [
    for (final k in interesting)
      if (json[k] != null && '$json[k]'.isNotEmpty) '$k: ${json[k]}',
  ];
}

/// Encode a body for a request, tolerating the logit's `NaN`/`Infinity`.
///
/// `jsonEncode` **throws** on a non-finite double, and a logit vector coming
/// back from a head that diverged is exactly how that happens. The window would
/// then show an exception where the honest answer is "the model produced a
/// number JavaScript does not have", which is a real and diagnosable state.
String encodeBody(Object? body) {
  try {
    return jsonEncode(body);
  } on JsonUnsupportedObjectError {
    return jsonEncode(_sanitize(body));
  }
}

Object? _sanitize(Object? v) {
  if (v is double) {
    if (v.isNaN) return 'NaN';
    if (v.isInfinite) return v.isNegative ? '-Infinity' : 'Infinity';
    return v;
  }
  if (v is List) return [for (final e in v) _sanitize(e)];
  if (v is Map) return {for (final e in v.entries) e.key: _sanitize(e.value)};
  return v;
}

/// Logits as fixed-width text, biggest first.
///
/// Sorted by value so the top class is first, because a table in index order
/// makes the caller hunt for the answer the response already named in
/// `top_index`. The `*` marks it. **The order is not a ranking of confidence** —
/// the values are raw logits, and the reason is [SystemOneResult.whyNoScore].
String formatLogits(List<double> logits, SystemOneResult result) {
  final rows = [...logits.indexed]
    ..sort((a, b) => b.$2.compareTo(a.$2));
  final width = <int>[for (final (i, _) in rows) result.labelAt(i).length]
      .fold<int>(0, (a, b) => a > b ? a : b);
  return [
    for (final (i, v) in rows)
      '$i${i == result.topIndex ? ' *' : '  '}  '
      '${result.labelAt(i).padRight(width)}  '
      '${v.toStringAsFixed(4)}',
  ].join('\n');
}
