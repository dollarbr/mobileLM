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
          gguf: false,
          fits: false),
      'custom-litert',
    );
  });

  test('catalogue entries split by runtime', () {
    String? catalogue({bool image = false, bool litert = false, bool gguf = false}) =>
        modelSectionKey(
            downloaded: false,
            custom: false,
            image: image,
            litert: litert,
            gguf: gguf,
            fits: true);

    expect(catalogue(gguf: true), 'gguf');
    expect(catalogue(litert: true), 'litert');
    expect(catalogue(image: true), 'image');
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
          gguf: true,
          fits: false),
      isNull,
    );
  });
}
