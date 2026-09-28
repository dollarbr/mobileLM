import 'package:flutter_test/flutter_test.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';

/// The classification of a loaded GGUF into embedding / reranker / classifier.
///
/// This is the decision that decides which endpoint serves a model and what a
/// caller is allowed to pass, so it is pinned here rather than left to a
/// `switch` that only a device can exercise. The numbers are the ones llama.cpp
/// reports: `n_cls_out` is 0 for an embedding model, 1 for a reranker (a
/// relevance score, no labels) and >1 for a classifier with a label per class.
void main() {
  group('EncoderInfo classification', () {
    test('a generation model is not an encoder', () {
      const info = EncoderInfo();
      expect(info.isEncoder, isFalse);
      expect(info.isEmbedding, isFalse);
      expect(info.isReranker, isFalse);
      expect(info.isClassifier, isFalse);
    });

    test('MEAN pooling with no classes is an embedding model', () {
      const info = EncoderInfo(
        isEncoder: true,
        pooling: 'mean',
        nEmbdOut: 384,
        outputLength: 384,
      );
      expect(info.isEmbedding, isTrue);
      expect(info.isReranker, isFalse);
      expect(info.isClassifier, isFalse);
    });

    test('one class is a reranker, not a one-label classifier', () {
      // The distinction is `n_cls_out == 1`, not "has labels". A reranker
      // returns a single relevance score and takes a query/document pair; a
      // one-label classifier returns the same shape and means something
      // categorically different, so nothing else can tell them apart but the
      // endpoint the caller chose.
      const info = EncoderInfo(
        isEncoder: true,
        pooling: 'rank',
        nClsOut: 1,
        nEmbdOut: 1024,
        outputLength: 1,
      );
      expect(info.isReranker, isTrue);
      expect(info.isClassifier, isFalse);
      expect(info.isEmbedding, isFalse);
    });

    test('several classes is a classifier', () {
      const info = EncoderInfo(
        isEncoder: true,
        pooling: 'rank',
        nClsOut: 2,
        nEmbdOut: 768,
        outputLength: 2,
        labels: ['negative', 'positive'],
      );
      expect(info.isClassifier, isTrue);
      expect(info.isReranker, isFalse);
      expect(info.labels, ['negative', 'positive']);
    });
  });

  group('EncoderOutput.norm', () {
    test('is zero for an all-zero vector, which is the failure to catch', () {
      // The failure this guards is a vector that comes back the right length
      // and means nothing: pooling over an unmarked batch returns [CLS] only.
      // Its length is right, so length is not the check; its norm is zero.
      const output = EncoderOutput(values: [0, 0, 0, 0]);
      expect(output.values.length, 4);
      expect(output.norm, 0.0);
    });

    test('is the Euclidean norm', () {
      const output = EncoderOutput(values: [3, 4]);
      expect(output.norm, closeTo(5.0, 1e-9));
    });
  });
}
