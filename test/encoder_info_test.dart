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
  group('inferred pooling', () {
    test('defaults to false, so "the file said so" is the default reading', () {
      const info = EncoderInfo(isEncoder: true, pooling: 'rank', nClsOut: 1);
      expect(info.inferredPooling, isFalse);
      expect(info.isReranker, isTrue);
    });

    test('an inferred reranker with no class count is still a reranker', () {
      // Exactly what jina-reranker-v1-tiny-en reports on the device: no
      // pooling_type in the GGUF, llama.cpp falls back to NONE, the native side
      // infers RANK from the architecture plus a usable boundary — and
      // n_cls_out is 0, not 1. Testing `== 1` refused it with a message that
      // said the model returned "0 class scores", which is true and useless.
      const info = EncoderInfo(
        isEncoder: true,
        pooling: 'rank',
        nClsOut: 0,
        nEmbdOut: 384,
        outputLength: 1,
        inferredPooling: true,
      );
      expect(info.isReranker, isTrue);
      expect(info.isClassifier, isFalse);
      expect(info.isEmbedding, isFalse);
      expect(info.inferredPooling, isTrue);
    });
  });

  group('EncoderInfo classification', () {
    test('a generation model is not an encoder', () {
      const info = EncoderInfo();
      expect(info.isEncoder, isFalse);
      expect(info.isEmbedding, isFalse);
      expect(info.isReranker, isFalse);
      expect(info.isClassifier, isFalse);
    });

    test('an embedding model with a one-class head is still an embedding model', () {
      // Measured on the device, and the reason `nClsOut` cannot be the test.
      // A real bge-small-en-v1.5 reports all three of these at once:
      //   pooling: cls, output_length: 384, n_cls_out: 1, labels: [LABEL_0]
      // It returns 384 values. Classifying on n_cls_out > 0 would tell a caller
      // that a 384-dimension embedding model is a classifier, and the /v1/rerank
      // refusal would quote "1 class score" as its evidence. It did, until this
      // test existed.
      const info = EncoderInfo(
        isEncoder: true,
        pooling: 'cls',
        nClsOut: 1,
        nEmbdOut: 384,
        outputLength: 384,
        labels: ['LABEL_0'],
      );
      expect(info.isEmbedding, isTrue);
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
