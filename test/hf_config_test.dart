import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/services/hf_search_service.dart';

/// The four repos this logic was measured against, with the fields taken
/// verbatim from their `config.json` on 2026-09-28.
///
/// The point of every case here is the same one: a checkpoint's config states
/// what the *checkpoint* is, and a conversion is free to lose part of it. Only
/// the jina pair — where the two disagree — can catch a check that mistakes the
/// config for the file.
HfConfig cfg(
  List<String> archs, {
  String modelType = 'bert',
  String embPooler = '',
  Map<String, String> labels = const {},
}) =>
    HfConfig(
      repoId: 'x/y',
      architectures: archs,
      modelType: modelType,
      embPooler: embPooler,
      labels: labels.entries.map((e) => '${e.key}: ${e.value}').toList(),
    );

void main() {
  group('what the checkpoint declares', () {
    test('a sequence-classification head is the only head that scores', () {
      expect(
        cfg(['ModernBertForSequenceClassification']).declaresClassificationHead,
        isTrue,
      );
      expect(cfg(['BertModel']).declaresClassificationHead, isFalse);
      expect(cfg(['JinaBertModel']).declaresClassificationHead, isFalse);
    });

    test('labels do not decide it, because bge carries a label and embeds', () {
      // `id2label: {"0": "LABEL_0"}` on a model that returns a 384-vector. A
      // check keyed on labels calls this a classifier, which is the same trap
      // `EncoderInfo.isClassifier` avoids by requiring pooling == 'rank'.
      final bge = cfg(['BertModel'], labels: {'0': 'LABEL_0'});
      expect(bge.labels, ['0: LABEL_0']);
      expect(bge.declaresClassificationHead, isFalse);
      expect(bge.declaresLmHead, isFalse);
    });

    test('a causal head is a chat model, not a scorer', () {
      final llama = cfg(['LlamaForCausalLM'], modelType: 'llama');
      expect(llama.declaresLmHead, isTrue);
      expect(llama.declaresClassificationHead, isFalse);
    });

    test('an empty architecture list is "no opinion", not "no head"', () {
      final blank = cfg([]);
      expect(blank.declaresClassificationHead, isFalse);
      expect(blank.declaresLmHead, isFalse);
      expect(blank.verdict, contains('does not declare an architecture'));
    });
  });

  group('pooling', () {
    test('maps the trained value to llama.cpp, and nothing else', () {
      expect(cfg(['BertModel'], embPooler: 'mean').poolingType, 1);
      expect(cfg(['BertModel'], embPooler: 'cls').poolingType, 2);
      expect(cfg(['BertModel'], embPooler: 'last').poolingType, 3);
      // Absent stays null rather than defaulting to CLS. A BERT defaults to CLS,
      // and inferring a value from a missing key is the confident wrong answer
      // this whole path exists to avoid.
      expect(cfg(['BertModel']).poolingType, isNull);
    });

    test('emb_pooler is not usable on a checkpoint with no head', () {
      // The jina reranker declares `emb_pooler: mean` and `JinaBertModel`. Read
      // without the gate, this would relabel a file that produces nothing as an
      // embedder — and `jina-reranker-v1-tiny-en` is exactly that file.
      final jina = cfg(['JinaBertModel'], embPooler: 'mean');
      expect(jina.poolingType, 1);
      expect(jina.ggufPoolingNote, contains('Not usable'));
    });

    test('a head plus emb_pooler is the one case both are worth', () {
      final gte = cfg(['ModernBertForSequenceClassification'],
          modelType: 'modernbert');
      expect(gte.declaresClassificationHead, isTrue);
      // The GTE's own GGUF declares no <arch>.pooling_type at all, so trained
      // metadata from the checkpoint is the only pooling that file ever states.
      expect(gte.ggufPoolingNote, contains('A GGUF that kept the head'));
    });
  });

  group('the verdict a person reads before the download', () {
    test('names the headless case, because that is the one that wastes 36 MB', () {
      final v = cfg(['JinaBertModel']).verdict;
      expect(v, contains('base model'));
      expect(v, contains('load and produce nothing'));
    });

    test('does not promise a score it cannot check', () {
      // A head in the checkpoint says a conversion *could* score. Whether this
      // particular GGUF kept the head is only knowable from the file.
      final v = cfg(['ModernBertForSequenceClassification']).verdict;
      expect(v, contains('can score'));
      expect(v, contains('only knowable from the file itself'));
    });

    test('says "only embeds" for a masked-LM checkpoint', () {
      expect(cfg(['BertForMaskedLM']).verdict, contains('it will only embed'));
    });
  });
}
