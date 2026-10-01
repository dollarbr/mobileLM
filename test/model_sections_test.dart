import 'package:flutter_test/flutter_test.dart';
import 'package:mobilelm/controllers/model_controller.dart';

void main() {
  // The order of the tests inside modelSectionKey is the feature, so this
  // pins the cases where two of them are true at once.
  test('what is on disk shows under Downloaded and nowhere else', () {
    expect(
      modelSectionKey(
          downloaded: true,
          custom: true,
          image: false,
          litert: true,
          tflite: true,
          gguf: false,
          fits: false),
      'downloaded',
    );
  });

  test('hand-added models split by runtime and ignore the memory cap', () {
    expect(
      modelSectionKey(
          downloaded: false,
          custom: true,
          image: false,
          litert: false,
          tflite: false,
          gguf: true,
          fits: false),
      'custom-gguf',
    );
    expect(
      modelSectionKey(
          downloaded: false,
          custom: true,
          image: false,
          litert: true,
          tflite: false,
          gguf: false,
          fits: false),
      'custom-litert',
    );
    expect(
      modelSectionKey(
          downloaded: false,
          custom: true,
          image: false,
          litert: false,
          tflite: true,
          gguf: false,
          fits: false),
      'custom-tflite',
    );
  });

  test('catalogue entries split by runtime', () {
    String? catalogue({
      bool image = false,
      bool litert = false,
      bool tflite = false,
      bool gguf = false,
    }) =>
        modelSectionKey(
            downloaded: false,
            custom: false,
            image: image,
            litert: litert,
            tflite: tflite,
            gguf: gguf,
            fits: true);

    expect(catalogue(gguf: true), 'gguf');
    expect(catalogue(litert: true), 'litert');
    expect(catalogue(image: true), 'image');
    expect(catalogue(tflite: true), 'tflite');
    // A .safetensors SD checkpoint is not a GGUF, however it is named.
    expect(catalogue(image: true, gguf: true), 'image');
    expect(catalogue(), isNull);
  });

  test('a catalogue model too big for the phone is hidden, not misfiled', () {
    expect(
      modelSectionKey(
          downloaded: false,
          custom: false,
          image: false,
          litert: false,
          tflite: false,
          gguf: true,
          fits: false),
      isNull,
    );
    // A .tflite head goes through the cap like anything else in the catalogue.
    // The heads that exist are kilobytes, so this never bites in practice — but
    // a catalogue that shipped a 2 GB graph would be hidden here rather than
    // offered and failing at compile time.
    expect(
      modelSectionKey(
          downloaded: false,
          custom: false,
          image: false,
          litert: false,
          tflite: true,
          gguf: false,
          fits: false),
      isNull,
    );
  });

  // The one that would have been a silent misfile. `runtimeFromFilename` had no
  // `.tflite` branch, so a `.tflite` fell through to `runtimeLlama` and every
  // predicate that reads the runtime said "GGUF" about a file that llama.cpp
  // cannot open the magic bytes of. The card would then offer "Load" for an
  // engine that rejects it.
  test('a .tflite never lands in a GGUF bucket, even with gguf also true', () {
    // The unreachable state this guards: were both flags ever set together, the
    // order decides, and `tflite` has to win because it is the one the extension
    // and the runtime actually agree on.
    expect(
      modelSectionKey(
          downloaded: false,
          custom: false,
          image: false,
          litert: false,
          tflite: true,
          gguf: true,
          fits: true),
      'tflite',
    );
    // And image still wins over tflite, as it does over every other runtime:
    // an SD checkpoint is an image model first and a file extension second.
    expect(
      modelSectionKey(
          downloaded: false,
          custom: false,
          image: true,
          litert: false,
          tflite: true,
          gguf: false,
          fits: true),
      'image',
    );
  });
}