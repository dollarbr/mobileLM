/// Reading a `.tflite` file's signatures without the runtime.
///
/// ## Why this exists at all
///
/// The LiteRT Java API binds tensors **by name** — `run(Map<String,
/// TensorBuffer>, Map<String, TensorBuffer>, signatureName)` — but it offers no
/// way to *list* those names. It can create input and output buffers by
/// signature index (`createInputBuffers(0)`) and it can report a tensor's type
/// only if you already know its name (`getInputTensorType(name, signature)`).
///
/// So a host that wants to run an arbitrary model has to read the names from
/// somewhere, and the somewhere is the FlatBuffer the model already is. The
/// alternative — assume input 0 is the features and output 0 is the logits —
/// works on exactly the models that were designed to be obvious and fails
/// silently on everything else. Laya's act head is the counterexample: it takes
/// `pooled_cls` **and** `feats`, and its output is `act_logits`. Guessing the
/// arity would not run it at all.
///
/// ## What is read
///
/// Only the `Model.signature_defs` and the referenced `SubGraph.tensors`. Tensor
/// *data* is not touched, so this works on a header-sized read of a local file
/// in practice — but see the caveat on remote models below.
///
/// Pure, and for the same reason `acceleration.dart` and `memory_readout.dart`
/// are pure: the mapping from bytes to "this model takes `feats` of four floats"
/// is decidable on a laptop, and it is the part that is silently wrong if it is
/// wrong.
library;

import 'dart:convert';
import 'dart:typed_data';

/// The TFLite `TensorType` enum, as far as this needs to care.
///
/// The numeric values are the ones in `tensorflow/lite/schema/schema.fbs`, and
/// they are load-bearing: the file stores a byte, not a name. `resource` and
/// `variant` are present in the schema but never appear as a model input, and
/// `float16` and the 4-bit types are stored in weights rather than in a
/// signature, so they are recognised by name and rejected by
/// [TensorType.supportedAsInput] rather than silently coerced.
enum TensorType {
  float32(0, 'FLOAT32', 4),
  float16(1, 'FLOAT16', 2),
  int32(2, 'INT32', 4),
  uint8(3, 'UINT8', 1),
  int64(4, 'INT64', 8),
  string(5, 'STRING', 0),
  /// Named `boolean` and not `bool` because `bool` is a Dart type and
  /// cannot be an enum value. The label stays the schema's `BOOL`.
  boolean(6, 'BOOL', 1),
  int16(7, 'INT16', 2),
  complex64(8, 'COMPLEX64', 8),
  int8(9, 'INT8', 1),
  float64(10, 'FLOAT64', 8),
  complex128(11, 'COMPLEX128', 16),
  uint64(12, 'UINT64', 8),
  resource(13, 'RESOURCE', 0),
  variant(14, 'VARIANT', 0),
  uint32(15, 'UINT32', 4),
  uint16(16, 'UINT16', 2),
  int4(17, 'INT4', 0);

  const TensorType(this.code, this.label, this.bytesPerElement);

  final int code;
  final String label;
  final int bytesPerElement;

  /// The inverse of [label].
  ///
  /// Throws on an unknown label rather than defaulting, for the reason in
  /// [LitertTensor.fromJson]: a type this build does not know is a schema newer
  /// than the code, and the only safe reading of that is to refuse.
  static TensorType fromLabel(String label) => values.firstWhere(
        (t) => t.label == label,
        orElse: () => throw FormatException(
            'Unknown TFLite tensor type "$label". The schema this build reads '
            'does not have it, which means the model was produced by a newer '
            'converter.'),
      );

  static TensorType fromCode(int code) => values.firstWhere(
        (t) => t.code == code,
        orElse: () => throw FormatException(
            'Unknown TFLite tensor type code $code. A model using it was '
            'probably produced by a newer converter than the schema this reads.'),
      );

  /// Whether this can carry data through the host's float/int bridge.
  ///
  /// `float16` is the interesting exclusion. It is a perfectly ordinary type in
  /// the schema and it appears constantly in weights, but a graph that takes
  /// fp16 **activations** would need a different buffer path, and writing
  /// float32 at it would produce a plausible-looking wrong answer rather than
  /// an error. Refusing it is the only safe reading.
  bool get supportedAsInput => switch (this) {
        TensorType.float32 ||
        TensorType.int32 ||
        TensorType.int64 ||
        TensorType.int8 ||
        TensorType.uint8 ||
        TensorType.boolean =>
          true,
        _ => false,
      };
}

/// One tensor in a signature, with everything needed to build its buffer.
class LitertTensor {
  const LitertTensor({
    required this.name,
    required this.type,
    required this.shape,
  });

  /// The name the Java API binds by. Empty when the model omits it, which is
  /// legal in the schema and useless for a host — see [LitertSignature.bindable].
  final String name;

  final TensorType type;

  /// Full shape as stored, including the leading batch dimension.
  final List<int> shape;

  /// Element count, the product of [shape].
  ///
  /// A dimension of `-1` means "dynamic" in the schema, and it is a placeholder
  /// rather than a count, so the product is computed with it as 0 and the
  /// result is flagged instead of being reported as a real size. Guessing a
  /// batch size here would allocate a buffer of the wrong length and fail
  /// somewhere less obvious than this.
  int get elementCount {
    if (shape.any((d) => d < 0)) return 0;
    var n = 1;
    for (final d in shape) {
      n *= d;
    }
    return n;
  }

  bool get hasDynamicDimension => shape.any((d) => d < 0);

  /// `[1, 1024]` rather than `1x1024`, because that is how the contract, the
  /// schema and the Java API all write it and a log line that reshapes the
  /// notation makes the two hard to compare by eye.
  String get shapeLabel =>
      '[${shape.isEmpty ? '' : shape.join(', ')}]';

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type.label,
        'shape': shape,
        if (hasDynamicDimension) 'dynamic': true,
      };

  /// Read back what [toJson] wrote.
  ///
  /// The inverse exists because the screen runs over HTTP: the console asks the
  /// server to read the FlatBuffer and gets JSON back, and it needs the same
  /// value the server built. Re-parsing the file on the client would be a second
  /// reader for a value that crossed the wire already, and the two could disagree
  /// about a schema nobody changed.
  ///
  /// **A type it does not recognise is an error, not a guess.** `toJson` writes
  /// the schema's own label (`FLOAT32`), and a label this reader does not know is
  /// a schema newer than the code — the same condition [TensorType.fromCode]
  /// refuses on the read side. Falling back to float32 there would turn "a model
  /// I cannot describe" into "a model that computes something".
  static LitertTensor fromJson(Map<String, dynamic> j) => LitertTensor(
        name: '${j['name'] ?? ''}',
        type: TensorType.fromLabel('${j['type']}'),
        shape: ((j['shape'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
      );

  @override
  String toString() => '$name ${type.label} $shapeLabel';
}

/// A named input or output group: one `SignatureDef`.
class LitertSignature {
  const LitertSignature({
    required this.key,
    required this.inputs,
    required this.outputs,
    required this.subgraphIndex,
  });

  /// `serving_default` for essentially everything the TF converter emits.
  final String key;

  final List<LitertTensor> inputs;
  final List<LitertTensor> outputs;
  final int subgraphIndex;

  /// Whether the Java API can actually be driven with this signature.
  ///
  /// It cannot when a tensor is unnamed, because the API binds by name; it
  /// cannot when an input is a type the host's bridge does not carry; and it
  /// cannot when there is no input or no output to bind at all.
  ///
  /// That last one is a bug this had: `inputs.every(...)` on an empty list is
  /// `true`, so a signature with **no inputs** passed as bindable — and since
  /// [LitertModelInfo.defaultSignature] falls back to "the first bindable one",
  /// such a signature would be chosen as the default and then have nothing to
  /// fill in. Both ends are non-empty checks, not just the type check.
  bool get bindable =>
      key.isNotEmpty &&
      inputs.isNotEmpty &&
      outputs.isNotEmpty &&
      inputs.every((t) => t.name.isNotEmpty && t.type.supportedAsInput) &&
      outputs.every((t) => t.name.isNotEmpty);

  /// Why it is not bindable, in one line, for a log or an error message.
  String get unusableReason {
    if (key.isEmpty) return 'the signature has no key';
    if (inputs.isEmpty) return 'the signature has no inputs to bind';
    if (outputs.isEmpty) return 'the signature has no outputs to read';
    final unnamed = inputs.where((t) => t.name.isNotEmpty == false);
    if (unnamed.isNotEmpty) {
      return 'input tensor(s) without a name: the Java API binds by name';
    }
    final badType = inputs.where((t) => t.type.supportedAsInput == false);
    if (badType.isNotEmpty) {
      return 'input of unsupported type ${badType.first.type.label}';
    }
    return 'unknown';
  }

  static LitertSignature fromJson(Map<String, dynamic> j) => LitertSignature(
        key: '${j['signature'] ?? ''}',
        inputs: ((j['inputs'] as List?) ?? const [])
            .map((e) => LitertTensor.fromJson(e as Map<String, dynamic>))
            .toList(),
        outputs: ((j['outputs'] as List?) ?? const [])
            .map((e) => LitertTensor.fromJson(e as Map<String, dynamic>))
            .toList(),
        subgraphIndex: (j['subgraph'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'signature': key,
        'subgraph': subgraphIndex,
        'inputs': [for (final t in inputs) t.toJson()],
        'outputs': [for (final t in outputs) t.toJson()],
        'bindable': bindable,
        if (bindable == false) 'unusable_reason': unusableReason,
      };

  @override
  String toString() =>
      '$key(${inputs.join(', ')} -> ${outputs.join(', ')})';
}

/// Everything worth knowing about a `.tflite` before running it.
class LitertModelInfo {
  const LitertModelInfo({
    required this.version,
    required this.description,
    required this.signatures,
  });

  final int version;
  final String description;
  final List<LitertSignature> signatures;

  /// The signature a host should use when the caller did not name one.
  ///
  /// `serving_default` first, because that is the name the TF converter gives
  /// the single signature of a converted model, and it is what the Laya contract
  /// binds by. Falls back to the first bindable signature, and then to the first
  /// signature at all, so a model with one odd name still reports itself instead
  /// of coming back as an empty list.
  LitertSignature? get defaultSignature {
    if (signatures.isEmpty) return null;
    for (final s in signatures) {
      if (s.key == 'serving_default') return s;
    }
    for (final s in signatures) {
      if (s.bindable) return s;
    }
    return signatures.first;
  }

  static LitertModelInfo fromJson(Map<String, dynamic> j) => LitertModelInfo(
        version: (j['version'] as num?)?.toInt() ?? 0,
        description: '${j['description'] ?? ''}',
        signatures: ((j['signatures'] as List?) ?? const [])
            .map((e) => LitertSignature.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'description': description,
        'signatures': [for (final s in signatures) s.toJson()],
        if (defaultSignature != null) 'default': defaultSignature!.key,
      };

  @override
  String toString() => 'LitertModelInfo v$version '
      '${description.isEmpty ? '' : '"$description" '}'
      '($signatures)';
}

/// Raised when the bytes are not a `.tflite` this reader can make sense of.
///
/// The messages name the file identifier and the offset, because the two
/// failures that actually happen are "this is not a tflite" and "this is a
/// tflite from a newer schema", and they are indistinguishable from a stack
/// trace otherwise.
class LitertFormatException extends FormatException {
  LitertFormatException(String message) : super(message);
}

/// A minimal read-only FlatBuffer cursor.
///
/// Only the four things the TFLite schema needs: a table's field, a vector of
/// offsets, a string, and a vector of scalars. Written out rather than pulled in
/// as a dependency because the whole thing is 60 lines and the alternative is a
/// package that would be the app's only flatbuffer use.
class _Fb {
  _Fb(this.bytes) : _view = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData _view;

  int _u8(int p) => _view.getUint8(p);

  int _u16(int p) {
    _range(p, 2);
    return _view.getUint16(p, Endian.little);
  }

  int _i32(int p) {
    _range(p, 4);
    return _view.getInt32(p, Endian.little);
  }

  int _u32(int p) {
    _range(p, 4);
    return _view.getUint32(p, Endian.little);
  }

  void _range(int p, int n) {
    if (p < 0 || p + n > bytes.length) {
      throw LitertFormatException(
          'Read past the end of the file: wanted $n byte(s) at $p of '
          '${bytes.length}. The file is truncated or is not a FlatBuffer.');
    }
  }

  /// Position of a table's field, or null when the field is absent.
  ///
  /// A field is absent in two distinguishable ways and both mean "absent": the
  /// vtable slot is zero, or the slot is past the end of the vtable (the table
  /// was written by a build whose schema had more fields than this reader knows
  /// about). Collapsing them is correct here — the alternative is treating an
  /// unknown trailing field as a real value.
  int? _field(int table, int id) {
    _range(table, 4);
    final vtable = table - _i32(table);
    if (vtable < 0 || vtable + 4 > bytes.length) {
      throw LitertFormatException(
          'Table at $table points to a vtable at $vtable, outside the file. '
          'Not a FlatBuffer, or a corrupt one.');
    }
    final vtableSize = _u16(vtable);
    final slot = 4 + id * 2;
    if (slot + 2 > vtableSize) return null;
    final off = _u16(vtable + slot);
    if (off == 0) return null;
    return table + off;
  }

  /// The root table.
  int root() {
    _range(0, 4);
    final p = _u32(0);
    if (p < 4 || p >= bytes.length) {
      throw LitertFormatException(
          'Root offset $p is outside a ${bytes.length}-byte file.');
    }
    return p;
  }

  int u32Field(int table, int id, {int fallback = 0}) =>
      _field(table, id) == null ? fallback : _u32(_field(table, id)!);

  int i32Field(int table, int id, {int fallback = 0}) =>
      _field(table, id) == null ? fallback : _i32(_field(table, id)!);

  int u8Field(int table, int id, {int fallback = 0}) =>
      _field(table, id) == null ? fallback : _u8(_field(table, id)!);

  /// A string field, or '' when absent.
  ///
  /// The `+ p` is the whole thing and it is the easiest thing to get wrong: a
  /// FlatBuffer field holding a string stores a **uoffset relative to its own
  /// position**, not an absolute one. Reading the uint32 as a position works
  /// until it does not, and when it fails it reports a plausible length at a
  /// plausible offset, so the error looks like a truncated file. `vectorField`
  /// below does the same addition, correctly.
  String stringField(int table, int id) {
    final p = _field(table, id);
    if (p == null) return '';
    return _string(p + _u32(p));
  }

  /// Start of a vector's elements, and its length, via the offset field.
  _Vec vectorField(int table, int id) {
    final p = _field(table, id);
    if (p == null) return const _Vec(0, 0);
    final start = p + _u32(p);
    return _Vec(start, _u32(start));
  }

  String _string(int p) {
    final len = _u32(p);
    _range(p + 4, len);
    return utf8.decode(bytes.sublist(p + 4, p + 4 + len),
        allowMalformed: true);
  }

  /// Element `i` of a vector of tables, as an absolute position.
  int vectorTable(int start, int i) => start + 4 + i * 4 + _u32(start + 4 + i * 4);

  int vectorInt(int start, int i) {
    final p = start + 4 + i * 4;
    return _i32(p);
  }

  List<int> vectorInts(int start, int count) =>
      [for (var i = 0; i < count; i++) vectorInt(start, i)];

  String vectorString(int start, int i) =>
      _string(start + 4 + i * 4 + _u32(start + 4 + i * 4));
}

class _Vec {
  const _Vec(this.start, this.length);
  final int start;
  final int length;
}

/// Parse the header of a `.tflite` model.
///
/// The first 4 bytes must be `TFL3`. That check is not pedantry: it is the
/// difference between "this file is not a TFLite model" and whatever nonsense
/// the byte offsets would otherwise decode into, and the repo already has a
/// `gguf_header.py` that does the same job for GGUF.
LitertModelInfo parseLitertModel(Uint8List bytes) {
  if (bytes.length < 8) {
    throw LitertFormatException(
        'A .tflite needs at least 8 bytes to say anything; got ${bytes.length}. '
        'The file is truncated.');
  }
  final magic = String.fromCharCodes(bytes.sublist(4, 8));
  if (magic != 'TFL3') {
    throw LitertFormatException(
        'File identifier is "$magic", not "TFL3". This is not a TFLite model — '
        'it may be a GGUF, a safetensors, or an HTML error page.');
  }

  final fb = _Fb(bytes);
  final model = fb.root();

  // Subgraph 0 is where the signature's tensor indices point. A signature may
  // name another subgraph, and that one has to be resolved too rather than
  // assuming 0.
  final subgraphs = fb.vectorField(model, 2);
  final signaturesV = fb.vectorField(model, 7);

  final signatures = <LitertSignature>[];
  final cache = <int, ({int index, List<LitertTensor> tensors})>{};

  ({int index, List<LitertTensor> tensors}) subgraphAt(int i) => cache.putIfAbsent(i, () {
        if (i < 0 || i >= subgraphs.length) {
          throw LitertFormatException(
              'Signature points at subgraph $i of a model with '
              '${subgraphs.length} subgraph(s).');
        }
        final sg = fb.vectorTable(subgraphs.start, i);
        final tensorsV = fb.vectorField(sg, 0);
        final tensors = <LitertTensor>[];
        for (var t = 0; t < tensorsV.length; t++) {
          final tp = fb.vectorTable(tensorsV.start, t);
          final shapeV = fb.vectorField(tp, 0);
          tensors.add(LitertTensor(
            name: fb.stringField(tp, 3),
            type: TensorType.fromCode(fb.u8Field(tp, 1)),
            shape: fb.vectorInts(shapeV.start, shapeV.length),
          ));
        }
        return (index: i, tensors: tensors);
      });

  for (var s = 0; s < signaturesV.length; s++) {
    final sd = fb.vectorTable(signaturesV.start, s);
    final subIndex = fb.i32Field(sd, 3);
    final tensors = subgraphAt(subIndex).tensors;
    signatures.add(LitertSignature(
      key: fb.stringField(sd, 2),
      inputs: _tensorMaps(fb, fb.vectorField(sd, 0), tensors),
      outputs: _tensorMaps(fb, fb.vectorField(sd, 1), tensors),
      subgraphIndex: subIndex,
    ));
  }

  return LitertModelInfo(
    version: fb.u32Field(model, 0),
    description: fb.stringField(model, 3),
    signatures: signatures,
  );
}

/// Resolve `TensorMap` entries against the subgraph's tensor list.
///
/// A `TensorMap` carries a `name` and a `tensor_index`; the name is the one the
/// Java API binds by and the index is the one that gets the shape and type. They
/// agree in every model the converter emits, and when they do not the **index**
/// is authoritative for the shape because that is what the runtime reads. A name
/// that does not match the tensor is kept as written rather than replaced,
/// because that disagreement is a fact about the file and worth surfacing.
List<LitertTensor> _tensorMaps(_Fb fb, _Vec v, List<LitertTensor> tensors) {
  final out = <LitertTensor>[];
  for (var i = 0; i < v.length; i++) {
    final tm = fb.vectorTable(v.start, i);
    final index = fb.i32Field(tm, 1);
    final name = fb.stringField(tm, 0);
    if (index < 0 || index >= tensors.length) {
      throw LitertFormatException(
          'TensorMap "$name" points at tensor $index of ${tensors.length}.');
    }
    final t = tensors[index];
    out.add(t.name == name ? t : LitertTensor(name: name, type: t.type, shape: t.shape));
  }
  return out;
}
