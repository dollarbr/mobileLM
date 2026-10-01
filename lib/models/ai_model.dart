class AiModel {
  static const runtimeLlama = 'llama';
  static const runtimeLiteRt = 'litert';
  static const runtimeSd = 'sd';

  /// The tensor-interpreter runtime: a `.tflite`, driven by LiteRT's
  /// `CompiledModel`.
  ///
  /// A fourth value, and not a flavour of `runtimeLiteRt`. The two share a name
  /// in Google's Maven repository and nothing else: `litertlm-android` takes a
  /// prompt and streams tokens, and this takes named input tensors and returns
  /// named output tensors. Calling a `.tflite` "litert" would put it in the same
  /// list as the 586 MB generative models, and the button on its card would load
  /// it into an engine that cannot read its magic bytes.
  static const runtimeTflite = 'tflite';

  static bool hasVisionMarker(String value) {
    final lower = value.toLowerCase();
    return lower.contains('vl-') ||
        lower.contains('-vl') ||
        lower.contains('llava') ||
        lower.contains('vision');
  }

  final String name;
  final String filename;
  final String url;
  final String size;
  final String description;
  final String template;
  final String runtime;
  final bool isVision;

  /// Multimodal projector for GGUF models: the second file that turns pixels
  /// or audio samples into embeddings. Empty for models that have none, and
  /// always empty for LiteRT, which carries its encoders inside the .litertlm.
  final String mmprojUrl;
  final String mmprojFilename;
  final bool isImported;
  final bool isCustom;

  /// The model the app uses to prove the CPU path works, and the one every
  /// benchmark number is taken against.
  ///
  /// This is a role, not a size. It exists because of a measurement: a 230M
  /// model answers a short turn in ~12 tok/s on a Galaxy A72 (Snapdragon 720G,
  /// two A76), while a 360M one on the same phone did not return a token inside
  /// the 60 s prefill budget. Same engine, same gate, same code — the only
  /// variable that changed was how much arithmetic the prefill had to do. So a
  /// device that is too slow to answer a bigger model can still be *measured*,
  /// which is what a self-test needs. Anything heavier would make the test
  /// indistinguishable from the thing it is testing.
  ///
  /// Kept out of the picker's normal flow on purpose: it is a yardstick, not a
  /// suggestion. One model in the catalogue carries it today.
  final bool isBenchmark;

  AiModel({
    required this.name,
    required this.filename,
    required this.url,
    required this.size,
    required this.description,
    required this.template,
    String? runtime,
    this.isVision = false,
    this.isImported = false,
    this.isCustom = false,
    this.mmprojUrl = '',
    this.mmprojFilename = '',
    this.isBenchmark = false,
  }) : runtime = runtime ?? runtimeFromFilename(filename, template: template);

  factory AiModel.fromMap(Map<String, String> map) => AiModel(
        name: map['name'] ?? '',
        filename: map['filename'] ?? '',
        url: map['url'] ?? '',
        size: map['size'] ?? '',
        description: map['description'] ?? '',
        template: map['template'] ?? 'chatml',
        runtime: map['runtime'],
        isVision: map['vision'] == 'true',
        isImported: map['imported'] == 'true',
        isCustom: map['custom'] == 'true',
        isBenchmark: map['benchmark'] == 'true',
        mmprojUrl: map['mmprojUrl'] ?? '',
        mmprojFilename: map['mmprojFilename'] ?? '',
      );

  Map<String, String> toMap() => {
        'name': name,
        'filename': filename,
        'url': url,
        'size': size,
        'description': description,
        'template': template,
        'runtime': runtime,
        if (isVision) 'vision': 'true',
        if (isImported) 'imported': 'true',
        if (isCustom) 'custom': 'true',
        if (isBenchmark) 'benchmark': 'true',
        if (mmprojUrl.isNotEmpty) 'mmprojUrl': mmprojUrl,
        if (mmprojFilename.isNotEmpty) 'mmprojFilename': mmprojFilename,
      };

  /// True when this model needs a projector alongside the weights.
  bool get needsMmproj => mmprojFilename.isNotEmpty;

  static String runtimeFromFilename(String filename, {String? template}) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.litertlm')) return runtimeLiteRt;
    if (lower.endsWith('.tflite')) return runtimeTflite;
    if (lower.endsWith('.safetensors') || template == runtimeSd) {
      return runtimeSd;
    }
    return runtimeLlama;
  }

  AiModel copyWith({
    String? name,
    String? filename,
    String? url,
    String? size,
    String? description,
    String? template,
    String? runtime,
    bool? isVision,
    bool? isImported,
    bool? isCustom,
    bool? isBenchmark,
    String? mmprojUrl,
    String? mmprojFilename,
  }) {
    return AiModel(
      name: name ?? this.name,
      filename: filename ?? this.filename,
      url: url ?? this.url,
      size: size ?? this.size,
      description: description ?? this.description,
      template: template ?? this.template,
      runtime: runtime ?? this.runtime,
      isVision: isVision ?? this.isVision,
      isImported: isImported ?? this.isImported,
      isCustom: isCustom ?? this.isCustom,
      isBenchmark: isBenchmark ?? this.isBenchmark,
      mmprojUrl: mmprojUrl ?? this.mmprojUrl,
      mmprojFilename: mmprojFilename ?? this.mmprojFilename,
    );
  }
}

/// What the model card can state about a model beyond its file size.
/// GGUF fields come from the file's own header; LiteRT files carry no such
/// header, so only what is true by construction (the app-wide context cap)
/// or readable from the filename lands here.
class ModelSpec {
  /// Parameter count as advertised, e.g. `1.6B` or `E2B`.
  final String? paramsLabel;

  /// Maximum context window in tokens.
  final int? contextLength;

  /// Quantization tag from the filename, e.g. `Q4_0`.
  final String? quantLabel;

  const ModelSpec({this.paramsLabel, this.contextLength, this.quantLabel});

  bool get isEmpty =>
      paramsLabel == null && contextLength == null && quantLabel == null;
}
