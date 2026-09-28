import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart'
    show LlamaEncoder, EncoderInfo;

import '../core/colors.dart';
import '../services/encoder_settings_service.dart';

/// Settings for one encoder role: what the model can do, and what you may
/// override.
///
/// Every row is the same two-column idea, and the two columns are the point:
/// the value **auto-detected from the loaded file** on the left, and the override
/// on the right. Showing only the override is how a setting becomes a lie — the
/// number in the field looks like a fact about the model, and the one number
/// here that really is one is the token ceiling, because it comes from
/// `llama_model_n_ctx_train` on the file itself.
///
/// The detected column is populated on open, not held. `LlamaEncoder.info()` is
/// a round trip to the JNI, and a Settings screen that is not open should not be
/// paying for it — and the answer changes when the loaded model does, so a cached
/// one would be a stale one.
class EncoderParametersPanel extends StatefulWidget {
  const EncoderParametersPanel({
    super.key,
    required this.role,
    required this.isDark,
  });

  /// `'embed'` or `'rerank'`.
  final String role;
  final bool isDark;

  @override
  State<EncoderParametersPanel> createState() => _EncoderParametersPanelState();
}

class _EncoderParametersPanelState extends State<EncoderParametersPanel> {
  final _encoder = Get.find<EncoderSettingsService>();

  EncoderInfo? _info;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final info = await LlamaEncoder.info();
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _loading = false;
      });
    }
  }

  int get _detectedCeiling => _info?.maxInputTokens ?? 0;

  @override
  Widget build(BuildContext context) {
    final isEmbed = widget.role == 'embed';
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header(context),
      const SizedBox(height: 10),
      if (_loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        )
      else if (_loadError != null)
        _error(context)
      else ...[
        _ceiling(context),
        const SizedBox(height: 12),
        if (isEmbed) ..._embedRows(context) else ..._rerankRows(context),
      ],
      const SizedBox(height: 12),
      _resetAll(context),
    ]);
  }

  Widget _header(BuildContext context) {
    final dim = Theme.of(context).hintColor;
    return Row(children: [
      Icon(
        widget.role == 'embed'
            ? Icons.gradient_rounded
            : Icons.low_priority_rounded,
        size: 16,
        color: widget.isDark ? AppColors.primary : Colors.teal,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          widget.role == 'embed'
              ? 'Embeddings turn text into one vector each.'
              : 'Rerankers score a query against each document.',
          style: GoogleFonts.inter(fontSize: 12, color: dim),
        ),
      ),
      TextButton(
        onPressed: _probe,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: Text('re-read', style: GoogleFonts.inter(fontSize: 11)),
      ),
    ]);
  }

  Widget _error(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Could not read the loaded model: $_loadError',
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.error)),
        const SizedBox(height: 4),
        Text('The overrides below still apply. The auto-detected column is the '
            'part that needs the model.',
            style: GoogleFonts.inter(fontSize: 11,
                color: Theme.of(context).hintColor)),
      ]),
    );
  }

  /// The one row where the detected number is a hard fact.
  Widget _ceiling(BuildContext context) {
    final detected = _detectedCeiling;
    final effective = _encoder.effectiveMaxInputTokens(detected);
    final override = _encoder.encoderMaxInputTokens.value;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('Token ceiling',
                style: GoogleFonts.inter(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Text(
            detected > 0 ? 'model: $detected' : 'model: unknown',
            style: GoogleFonts.jetBrainsMono(fontSize: 11),
          ),
          const SizedBox(width: 8),
          Text('in use: $effective',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: override == null
                      ? Theme.of(context).hintColor
                      : AppColors.primary)),
        ]),
        const SizedBox(height: 6),
        Text(
          'A query and a document together must fit in this. An encoder pools '
          'the whole sequence in one pass and cannot split it, so the limit is '
          'a hard ceiling, not a hint. The native side caps it at '
          '${EncoderSettingsService.nativeMaxInputTokens}.',
          style: GoogleFonts.inter(fontSize: 11, color: Theme.of(context).hintColor),
        ),
        const SizedBox(height: 8),
        Row(children: [
          _numberField(
            controller: TextEditingController(
                text: override?.toString() ?? ''),
            hint: 'auto',
            width: 92,
            onSubmitted: (v) =>
                _encoder.setEncoderMaxInputTokens(int.tryParse(v.trim())),
          ),
          const SizedBox(width: 8),
          if (override != null)
            TextButton(
              onPressed: () => _encoder.setEncoderMaxInputTokens(null),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: Text('reset', style: GoogleFonts.inter(fontSize: 11)),
            ),
          if (override != null && detected > 0 && override > detected)
            Expanded(
              child: Text('above what the model reported — using the model\'s',
                  style: GoogleFonts.inter(
                      fontSize: 10, color: Theme.of(context).hintColor)),
            ),
        ]),
      ]),
    );
  }

  List<Widget> _embedRows(BuildContext context) {
    return [
      _textRow(
        context,
        label: 'Query prefix',
        hint: 'e5: "query: "',
        blurb: 'Prepended when a request also sends `query`. E5 wants '
            '"query: ", BGE wants it on one side only, Nomic wants '
            '"search_query: ". Wrong here does not error — the vectors just '
            'retrieve worse.',
        value: _encoder.embedQueryPrefix.value,
        onSubmit: _encoder.setEmbedQueryPrefix,
      ),
      const SizedBox(height: 10),
      _textRow(
        context,
        label: 'Passage prefix',
        hint: 'e5: "passage: "',
        blurb: 'Prepended to a plain `input`. The other half of the same '
            'asymmetry — a model trained with both sides marked returns vectors '
            'built for one kind of text if you mark neither.',
        value: _encoder.embedPassagePrefix.value,
        onSubmit: _encoder.setEmbedPassagePrefix,
      ),
      const SizedBox(height: 10),
      _choiceRow(
        context,
        label: 'Normalise',
        blurb: 'Auto follows the model. Off returns the raw vector, for a '
            'caller doing its own normalisation.',
        value: _encoder.embedNormalize.value,
        onChanged: _encoder.setEmbedNormalize,
      ),
      const SizedBox(height: 10),
      _capabilities(context),
    ];
  }

  List<Widget> _rerankRows(BuildContext context) {
    return [
      _numberRow(
        context,
        label: 'Top N',
        hint: 'all',
        blurb: 'How many documents come back. A request that sends its own '
            '`top_n` wins over this.',
        value: _encoder.rerankTopN.value,
        min: 1,
        max: 200,
        onSubmit: _encoder.setRerankTopN,
      ),
      const SizedBox(height: 10),
      _textRow(
        context,
        label: 'Document separator',
        hint: r'newline',
        blurb: 'Used when `documents` arrives as one string. A newline cannot '
            'be told from a paragraph break, so a document sent with blank lines '
            'in it comes back split and ranked, with nothing to indicate it.',
        value: _encoder.rerankDocumentSeparator.value == '\n'
            ? null
            : _encoder.rerankDocumentSeparator.value,
        displayValue: _encoder.rerankDocumentSeparator.value == '\n'
            ? 'newline'
            : _encoder.rerankDocumentSeparator.value,
        onSubmit: _encoder.setRerankDocumentSeparator,
      ),
      const SizedBox(height: 10),
      _choiceRow(
        context,
        label: 'Include probability',
        blurb: 'Adds `relevance_score_probability` next to the raw logit. The '
            'logit is left alone either way — it is the measured contract, and a '
            'cross-encoder\'s sigmoid is not calibrated anyway.',
        value: _encoder.rerankSigmoid.value,
        onChanged: (v) => _encoder.setRerankSigmoid(v ?? true),
      ),
      const SizedBox(height: 10),
      _choiceRow(
        context,
        label: 'Return documents',
        blurb: 'Echoes each document back with its score, the way Cohere does. '
            'Off halves the response on a long list.',
        value: _encoder.rerankReturnDocuments.value,
        onChanged: (v) => _encoder.setRerankReturnDocuments(v ?? true),
      ),
      const SizedBox(height: 10),
      _capabilities(context),
    ];
  }

  /// What the loaded model actually reported, so the rest has a scale.
  Widget _capabilities(BuildContext context) {
    final i = _info;
    final dim = Theme.of(context).hintColor;
    if (i == null || !i.isEncoder) {
      return Text('No encoder loaded. These settings apply to the next one.',
          style: GoogleFonts.inter(fontSize: 11, color: dim));
    }
    Widget line(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(children: [
            SizedBox(
                width: 116,
                child: Text(k,
                    style: GoogleFonts.jetBrainsMono(fontSize: 10, color: dim))),
            Text(v, style: GoogleFonts.jetBrainsMono(fontSize: 10)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('The loaded model reports',
            style: GoogleFonts.inter(
                fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        line('pooling', i.pooling),
        line('output length', '${i.outputLength}'),
        line('embedding dim', '${i.nEmbdOut}'),
        if (i.labels.isNotEmpty) line('labels', i.labels.join(', ')),
        if (i.ggufTags.isNotEmpty) line('file says it is', i.ggufTags.join(', ')),
      ]),
    );
  }

  Widget _resetAll(BuildContext context) {
    final n = _encoder.overrideCount;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: n == 0
            ? null
            : () async {
                await _encoder.resetAll();
                setState(() {});
              },
        icon: const Icon(Icons.restart_alt_rounded, size: 16),
        label: Text(
            n == 0 ? 'Nothing overridden' : 'Reset $n override${n == 1 ? '' : 's'}',
            style: GoogleFonts.inter(fontSize: 12)),
        style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(40)),
      ),
    );
  }

  // ── rows ──────────────────────────────────────────────────────────────────
  Widget _textRow(
    BuildContext context, {
    required String label,
    required String hint,
    required String blurb,
    required String? value,
    required Future<void> Function(String?) onSubmit,
    String? displayValue,
  }) {
    final c = TextEditingController(text: displayValue ?? value ?? '');
    return _panel(context, label, blurb, c, hint, (v) async {
      await onSubmit(v);
      if (mounted) setState(() {});
    });
  }

  Widget _numberRow(
    BuildContext context, {
    required String label,
    required String hint,
    required String blurb,
    required int? value,
    required int min,
    required int max,
    required Future<void> Function(int?) onSubmit,
  }) {
    final c = TextEditingController(text: value?.toString() ?? '');
    return _panel(context, label, blurb, c, hint, (v) async {
      await onSubmit(int.tryParse(v.trim()));
      if (mounted) setState(() {});
    });
  }

  Widget _panel(
    BuildContext context,
    String label,
    String blurb,
    TextEditingController c,
    String hint,
    Future<void> Function(String) onSubmit,
  ) {
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text(label,
              style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        SizedBox(
          width: 150,
          child: TextField(
            controller: c,
            style: GoogleFonts.jetBrainsMono(fontSize: 12),
            textAlign: TextAlign.end,
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onSubmitted: onSubmit,
          ),
        ),
      ]),
      const SizedBox(height: 4),
      Text(blurb,
          style: GoogleFonts.inter(
              fontSize: 11, color: Theme.of(context).hintColor)),
    ]);
  }

  Widget _numberField({
    required TextEditingController controller,
    required String hint,
    required double width,
    required Future<void> Function(String) onSubmitted,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        style: GoogleFonts.jetBrainsMono(fontSize: 12),
        keyboardType: TextInputType.number,
        textAlign: TextAlign.end,
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onSubmitted: (v) async {
          await onSubmitted(v);
        },
      ),
    );
  }

  Widget _choiceRow(
    BuildContext context, {
    required String label,
    required String blurb,
    required bool? value,
    required Future<void> Function(bool?) onChanged,
  }) {
    // Three states, not two: auto, on, off. A two-way switch cannot express
    // "ask the model", and every parameter here is auto by default — a switch
    // stuck on would be indistinguishable from a default the user chose.
    final opts = <({String label, bool? value})>[
      (label: 'auto', value: null),
      (label: 'on', value: true),
      (label: 'off', value: false),
    ];
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text(label,
              style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        SegmentedButton<bool?>(
          segments: [
            for (final o in opts)
              ButtonSegment<bool?>(
                value: o.value,
                label: Text(o.label, style: GoogleFonts.inter(fontSize: 11)),
              ),
          ],
          selected: {value},
          showSelectedIcon: false,
          onSelectionChanged: (s) async {
            await onChanged(s.first);
            if (mounted) setState(() {});
          },
        ),
      ]),
      const SizedBox(height: 4),
      Text(blurb,
          style: GoogleFonts.inter(
              fontSize: 11, color: Theme.of(context).hintColor)),
    ]);
  }
}
